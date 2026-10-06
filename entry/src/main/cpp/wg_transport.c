/*
 * 传输消息（type 4）：封包/解包、计数器 nonce、2048-bit 重放窗口、
 * cryptokey routing、roaming（来源地址更新）。
 *
 * 布局：type(4)=4 | receiver_index(4) | counter(8, LE) | AEAD(内层包, ad=ε)
 * nonce = 4×0 || LE64(counter)。
 */
#include "wireguard.h"
#include "chacha20poly1305.h"

#include <string.h>

/* 会话是否可用于发送（未超 REJECT_AFTER_TIME / REJECT_AFTER_MESSAGES） */
static bool kp_send_fresh(const wg_keypair *kp, double now)
{
    if (!kp->valid)
        return false;
    if (kp->send_nonce >= WG_REJECT_AFTER_MESSAGES)
        return false;
    if (now - kp->born_mono > WG_REJECT_AFTER_TIME)
        return false;
    return true;
}

/* 会话是否可用于接收（宽限 REJECT_AFTER_TIME + 2×KEEPALIVE，对齐 kernel 语义） */
static bool kp_recv_fresh(const wg_keypair *kp, double now)
{
    if (!kp->valid)
        return false;
    if (now - kp->born_mono > WG_REJECT_AFTER_TIME + 2 * WG_KEEPALIVE_TIMEOUT)
        return false;
    return true;
}

/* 重放窗口：bit i 对应 counter = recv_top - i。返回 true=接受（并更新窗口）。 */
static bool replay_check(wg_keypair *kp, uint64_t counter)
{
    if (counter >= WG_REJECT_AFTER_MESSAGES)
        return false;
    if (counter > kp->recv_top) {
        uint64_t shift = counter - kp->recv_top;
        if (shift >= WG_REPLAY_WINDOW_BYTES * 8) {
            memset(kp->recv_window, 0, sizeof(kp->recv_window));
        } else {
            /* 向高位移动 shift 位（bit0 恒为最新） */
            size_t bytes = (size_t)(shift / 8);
            unsigned bits = (unsigned)(shift % 8);
            if (bytes)
                memmove(kp->recv_window + bytes, kp->recv_window,
                        sizeof(kp->recv_window) - bytes);
            memset(kp->recv_window, 0, bytes);
            if (bits) {
                for (int i = (int)sizeof(kp->recv_window) - 1; i >= 0; i--) {
                    uint8_t hi = (i - 1 >= 0) ? kp->recv_window[i - 1] : 0;
                    kp->recv_window[i] = (uint8_t)((kp->recv_window[i] << bits) | (hi >> (8 - bits)));
                }
            }
        }
        kp->recv_top = counter;
        kp->recv_window[0] |= 1;
        return true;
    }
    uint64_t diff = kp->recv_top - counter;
    if (diff >= WG_REPLAY_WINDOW_BYTES * 8)
        return false; /* 太旧 */
    size_t byte = (size_t)(diff / 8);
    unsigned bit = (unsigned)(diff % 8);
    uint8_t mask = (uint8_t)(1u << bit);
    if (kp->recv_window[byte] & mask)
        return false; /* 重放 */
    kp->recv_window[byte] |= mask;
    return true;
}

int wg_transport_encrypt(wg_device *dev, wg_peer *peer, const uint8_t *pkt, size_t len,
                         uint8_t *out, size_t out_cap)
{
    if (len == 0 || len > WG_MAX_PACKET || out_cap < WG_TRANSPORT_HEADER + len + WG_AEAD_TAG)
        return -1;
    if (peer->cur_kp < 0)
        return 0;

    wg_keypair *kp = &peer->kp[peer->cur_kp];
    double now = wg_now_mono();
    if (!kp_send_fresh(kp, now))
        return 0; /* 需要新会话 */
    if (!peer->has_endpoint)
        return -1;

    uint64_t counter = kp->send_nonce++;
    wg_put_le32(out, WG_MSG_TRANSPORT);
    wg_put_le32(out + 4, kp->remote_index); /* receiver = 对端的 sender index */
    wg_put_le64(out + 8, counter);

    uint8_t nonce[12];
    memset(nonce, 0, 4);
    wg_put_le64(nonce + 4, counter);
    chacha20poly1305_encrypt(out + WG_TRANSPORT_HEADER, pkt, len, NULL, 0, kp->send_key, nonce);

    peer->tx_bytes += len;
    (void)dev;
    return (int)(WG_TRANSPORT_HEADER + len + WG_AEAD_TAG);
}

bool wg_transport_make_keepalive(wg_device *dev, wg_peer *peer, uint8_t *out, size_t *out_len)
{
    (void)dev;
    if (peer->cur_kp < 0 || !peer->has_endpoint)
        return false;
    wg_keypair *kp = &peer->kp[peer->cur_kp];
    double now = wg_now_mono();
    if (!kp_send_fresh(kp, now))
        return false;

    uint64_t counter = kp->send_nonce++;
    wg_put_le32(out, WG_MSG_TRANSPORT);
    wg_put_le32(out + 4, kp->remote_index); /* receiver = 对端的 sender index */
    wg_put_le64(out + 8, counter);
    uint8_t nonce[12];
    memset(nonce, 0, 4);
    wg_put_le64(nonce + 4, counter);
    chacha20poly1305_encrypt(out + WG_TRANSPORT_HEADER, NULL, 0, NULL, 0, kp->send_key, nonce);
    *out_len = WG_TRANSPORT_HEADER + WG_AEAD_TAG;
    return true;
}

bool wg_transport_decrypt(wg_device *dev, const uint8_t *msg, size_t len,
                          const struct sockaddr_storage *src,
                          uint8_t *plain_out, size_t *plain_len, wg_peer **peer_out)
{
    *peer_out = NULL;
    *plain_len = 0;
    if (len < WG_TRANSPORT_HEADER + WG_AEAD_TAG || wg_le32(msg) != WG_MSG_TRANSPORT)
        return false;
    if (len - WG_TRANSPORT_HEADER - WG_AEAD_TAG > WG_MAX_PACKET)
        return false;

    uint32_t receiver = wg_le32(msg + 4);
    uint64_t counter = wg_le64(msg + 8);
    double now = wg_now_mono();

    /* 按 receiver index 找会话（含 prev 槽） */
    wg_peer *peer = NULL;
    wg_keypair *kp = NULL;
    for (int i = 0; i < dev->n_peers && !kp; i++) {
        for (int k = 0; k < 2; k++) {
            if (dev->peers[i].kp[k].valid && dev->peers[i].kp[k].index == receiver) {
                peer = &dev->peers[i];
                kp = &peer->kp[k];
                break;
            }
        }
    }
    if (!kp || !kp_recv_fresh(kp, now))
        return false;

    uint8_t nonce[12];
    memset(nonce, 0, 4);
    wg_put_le64(nonce + 4, counter);
    size_t pt_len = len - WG_TRANSPORT_HEADER - WG_AEAD_TAG;
    /* 先解密认证，再校验重放窗口（对齐 wireguard-go receive.go：
     * Open() → ValidateCounter() → allowedips），避免伪造高计数包推动窗口造成 DoS。 */
    if (!chacha20poly1305_decrypt(plain_out, msg + WG_TRANSPORT_HEADER,
                                  pt_len + WG_AEAD_TAG,
                                  NULL, 0, kp->recv_key, nonce)) {
        return false;
    }
    if (!replay_check(kp, counter))
        return false;

    if (pt_len > 0) {
        /* cryptokey routing：源 IP 必须在 peer allowedIPs 内 */
        if (!wg_peer_allows_source(peer, plain_out, pt_len))
            return false;
        peer->rx_bytes += pt_len;
    }

    /* roaming：来源地址变化且消息已认证 → 更新 endpoint */
    if (src && (!peer->has_endpoint || !wg_sockaddr_equal(&peer->endpoint, src))) {
        peer->endpoint = *src;
        peer->endpoint_len = (src->ss_family == AF_INET) ? sizeof(struct sockaddr_in)
                                                         : sizeof(struct sockaddr_in6);
        peer->has_endpoint = true;
    }

    peer->last_rx_mono = now;
    /* 收包后若久未发送 → 回 keepalive（对齐 kernel timer_need_another_keepalive） */
    if (peer->last_tx_mono == 0.0 || now - peer->last_tx_mono >= WG_KEEPALIVE_TIMEOUT)
        peer->need_keepalive = true;

    *plain_len = pt_len;
    *peer_out = peer;
    return true;
}
