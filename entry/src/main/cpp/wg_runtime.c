/*
 * 运行时：tun ↔ UDP 双转发线程 + 维护定时器线程。
 *
 * 设计要点（对应决策 0001/0005/0006）：
 * - 单实例数据面（决策 0006 §4）：同一时刻只承载一条隧道；
 * - UDP 用非连接 socket + sendto/recvfrom，roaming 换地址不换 socket（决策 0005 §3）；
 * - 所有共享状态操作在 dev->lock 内；线程用 poll 超时轮询 dev->running 退出，
 *   不依赖 close() 打断阻塞读（可移植性更稳）；
 * - 定时器语义对齐 wireguard-go device/timers.go：REKEY_AFTER_TIME / REKEY_TIMEOUT /
 *   REKEY_ATTEMPT_TIME / REJECT_AFTER_TIME / KEEPALIVE_TIMEOUT / persistent keepalive。
 */
#include "wireguard.h"

#include <arpa/inet.h>
#include <errno.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define WG_POLL_MS 200

/* 向 peer 当前 endpoint 发送（v4 端点转为 v4-mapped，适配双栈 socket）。调用方持锁。 */
static void send_raw(wg_device *dev, wg_peer *p, const uint8_t *buf, size_t len)
{
    if (!p->has_endpoint || dev->sock_fd < 0)
        return;

    struct sockaddr_storage dst;
    wg_sockaddr_to_v6mapped(&p->endpoint, &dst);
    socklen_t dlen = dst.ss_family == AF_INET6 ? sizeof(struct sockaddr_in6)
                                               : sizeof(struct sockaddr_in);
    ssize_t r = sendto(dev->sock_fd, buf, len, 0, (const struct sockaddr *)&dst, dlen);
    if (r < 0 && p->endpoint.ss_family == AF_INET) {
        /* socket 非双栈时的兜底：直接用 v4 地址重试 */
        const struct sockaddr_in *v4 = (const struct sockaddr_in *)&p->endpoint;
        r = sendto(dev->sock_fd, buf, len, 0, (const struct sockaddr *)v4, sizeof(*v4));
    }
    if (r >= 0)
        p->last_tx_mono = wg_now_mono();
}

/* 发起一次握手（生成并发送 initiation）。调用方持锁。 */
static void handshake_send_initiation(wg_device *dev, wg_peer *p)
{
    uint8_t msg[WG_INITIATION_LEN];
    size_t len = 0;
    if (wg_handshake_create_initiation(dev, p, msg, &len))
        send_raw(dev, p, msg, len);
    else
        p->handshake_pending = false;
}

/* 有新会话后冲刷排队的内层包。调用方持锁。 */
static void flush_queue(wg_device *dev, wg_peer *p)
{
    if (p->cur_kp < 0 || p->queue_count == 0)
        return;
    uint8_t out[WG_MAX_PACKET + WG_TRANSPORT_HEADER + WG_AEAD_TAG];
    int sent = 0;
    while (sent < p->queue_count) {
        int m = wg_transport_encrypt(dev, p, p->queue[sent], p->queue_len[sent], out, sizeof(out));
        if (m <= 0)
            break; /* 会话又失效：保留剩余，等下次握手 */
        send_raw(dev, p, out, (size_t)m);
        sent++;
    }
    if (sent > 0) {
        size_t left = (size_t)(p->queue_count - sent);
        if (left)
            memmove(p->queue, p->queue + sent, sizeof(p->queue[0]) * left);
        if (left)
            memmove(p->queue_len, p->queue_len + sent, sizeof(p->queue_len[0]) * left);
        p->queue_count = (int)left;
    }
}

/* 出向发送后，若当前会话由我方发起且已超 REKEY_AFTER_TIME，则主动重协商。调用方持锁。 */
static void maybe_rekey(wg_device *dev, wg_peer *p)
{
    if (p->handshake_pending || p->cur_kp < 0)
        return;
    const wg_keypair *kp = &p->kp[p->cur_kp];
    if (kp->valid && kp->initiating && wg_now_mono() - kp->born_mono >= WG_REKEY_AFTER_TIME)
        handshake_send_initiation(dev, p);
}

/* ---------------- tun → UDP ---------------- */
static void *wg_tun_thread(void *arg)
{
    wg_device *dev = (wg_device *)arg;
    uint8_t in[WG_MAX_PACKET];
    uint8_t out[WG_MAX_PACKET + WG_TRANSPORT_HEADER + WG_AEAD_TAG];

    while (dev->running) {
        struct pollfd pfd;
        pfd.fd = dev->tun_fd;
        pfd.events = POLLIN;
        pfd.revents = 0;
        int pr = poll(&pfd, 1, WG_POLL_MS);
        if (pr <= 0)
            continue;

        ssize_t n = read(dev->tun_fd, in, sizeof(in));
        if (n <= 0) {
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR))
                continue;
            break;
        }

        pthread_mutex_lock(&dev->lock);
        wg_peer *p = wg_peer_for_packet(dev, in, (size_t)n);
        if (p) {
            int m = wg_transport_encrypt(dev, p, in, (size_t)n, out, sizeof(out));
            if (m > 0) {
                send_raw(dev, p, out, (size_t)m);
                maybe_rekey(dev, p);
            } else if (m == 0) {
                /* 无有效会话：入队并触发握手 */
                wg_peer_queue(p, in, (size_t)n);
                if (!p->handshake_pending && p->has_endpoint)
                    handshake_send_initiation(dev, p);
            }
        }
        pthread_mutex_unlock(&dev->lock);
    }
    return NULL;
}

/* ---------------- UDP → tun ---------------- */
static void *wg_udp_thread(void *arg)
{
    wg_device *dev = (wg_device *)arg;
    uint8_t buf[WG_MAX_PACKET + WG_TRANSPORT_HEADER + WG_AEAD_TAG];
    uint8_t plain[WG_MAX_PACKET];

    while (dev->running) {
        struct pollfd pfd;
        pfd.fd = dev->sock_fd;
        pfd.events = POLLIN;
        pfd.revents = 0;
        int pr = poll(&pfd, 1, WG_POLL_MS);
        if (pr <= 0)
            continue;

        struct sockaddr_storage src;
        socklen_t slen = sizeof(src);
        ssize_t n = recvfrom(dev->sock_fd, buf, sizeof(buf), 0, (struct sockaddr *)&src, &slen);
        if (n <= 0)
            continue;
        if (n < 4)
            continue;

        pthread_mutex_lock(&dev->lock);
        uint32_t type = wg_le32(buf);
        if (type == WG_MSG_INITIATION) {
            uint8_t resp[WG_RESPONSE_LEN];
            size_t rlen = 0;
            wg_peer *p = NULL;
            if (wg_handshake_consume_initiation(dev, buf, (size_t)n, resp, &rlen, &p)) {
                send_raw(dev, p, resp, rlen);
                flush_queue(dev, p);
            }
        } else if (type == WG_MSG_RESPONSE) {
            wg_peer *p = wg_handshake_consume_response(dev, buf, (size_t)n);
            if (p)
                flush_queue(dev, p);
        } else if (type == WG_MSG_TRANSPORT) {
            size_t plen = 0;
            wg_peer *p = NULL;
            if (wg_transport_decrypt(dev, buf, (size_t)n, &src, plain, &plen, &p)) {
                if (plen > 0) {
                    ssize_t w = write(dev->tun_fd, plain, plen);
                    (void)w;
                }
            }
        }
        /* type 3 (cookie reply)：v1 不实现 cookie，静默忽略（决策 0002 §3） */
        pthread_mutex_unlock(&dev->lock);
    }
    return NULL;
}

/* ---------------- 维护定时器 ---------------- */
static void *wg_timer_thread(void *arg)
{
    wg_device *dev = (wg_device *)arg;

    while (dev->running) {
        for (int i = 0; i < WG_TIMER_TICK_MS; i++) {
            if (!dev->running)
                return NULL;
            usleep(1000);
        }

        pthread_mutex_lock(&dev->lock);
        double now = wg_now_mono();
        for (int i = 0; i < dev->n_peers; i++) {
            wg_peer *p = &dev->peers[i];

            /* 1. 会话到期作废 */
            for (int k = 0; k < 2; k++) {
                if (p->kp[k].valid &&
                    now - p->kp[k].born_mono > WG_REJECT_AFTER_TIME + 2 * WG_KEEPALIVE_TIMEOUT)
                    p->kp[k].valid = false;
            }
            bool fresh = p->cur_kp >= 0 && p->kp[p->cur_kp].valid;

            /* 2. 握手重试 / 超时放弃 */
            if (p->handshake_pending) {
                if (now - p->first_attempt_mono >= WG_REKEY_ATTEMPT_TIME) {
                    p->handshake_pending = false;
                    p->queue_count = 0;
                } else if (now - p->last_attempt_mono >= WG_REKEY_TIMEOUT) {
                    handshake_send_initiation(dev, p);
                }
            } else if (!fresh && p->queue_count > 0 && p->has_endpoint) {
                /* 3. 有数据待发但无会话 → 发起握手 */
                handshake_send_initiation(dev, p);
            }

            /* 4. 有会话：冲刷队列 + keepalive */
            if (fresh) {
                flush_queue(dev, p);

                bool need_ka = p->need_keepalive;
                if (p->persistent_keepalive > 0 && !need_ka) {
                    double last = p->last_tx_mono > p->last_rx_mono ? p->last_tx_mono : p->last_rx_mono;
                    if (last == 0.0 || now - last >= (double)p->persistent_keepalive)
                        need_ka = true;
                }
                if (need_ka) {
                    uint8_t out[WG_TRANSPORT_HEADER + WG_AEAD_TAG];
                    size_t len = 0;
                    if (wg_transport_make_keepalive(dev, p, out, &len)) {
                        send_raw(dev, p, out, len);
                        maybe_rekey(dev, p);
                    }
                    p->need_keepalive = false;
                }
            }
        }
        pthread_mutex_unlock(&dev->lock);
    }
    return NULL;
}

int wg_runtime_start(wg_device *dev)
{
    dev->running = true;

    if (pthread_create(&dev->th_tun, NULL, wg_tun_thread, dev) != 0) {
        dev->running = false;
        return -4;
    }
    if (pthread_create(&dev->th_udp, NULL, wg_udp_thread, dev) != 0) {
        dev->running = false;
        pthread_join(dev->th_tun, NULL);
        return -4;
    }
    if (pthread_create(&dev->th_timer, NULL, wg_timer_thread, dev) != 0) {
        dev->running = false;
        pthread_join(dev->th_tun, NULL);
        pthread_join(dev->th_udp, NULL);
        return -4;
    }
    dev->threads_started = true;
    return 0;
}

void wg_runtime_stop(wg_device *dev)
{
    if (!dev->threads_started)
        return;
    dev->running = false;
    pthread_join(dev->th_tun, NULL);
    pthread_join(dev->th_udp, NULL);
    pthread_join(dev->th_timer, NULL);
    dev->threads_started = false;
}
