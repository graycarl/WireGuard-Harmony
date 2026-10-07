/*
 * 设备/Peer/会话状态管理（配置解析、allowed-ips 匹配、队列、sockaddr 工具）。
 * 所有状态操作假定调用方持有 dev->lock（wg_runtime/napi 侧负责）。
 */
#include "wireguard.h"
#include "blake2s.h"
#include "curve25519.h"
#include "wg_base64.h"
#include "wg_json.h"

#include <arpa/inet.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WG_JSON_TOKENS 512

void wg_set_last_error(wg_device *dev, const char *fmt, const char *arg)
{
    if (arg)
        snprintf(dev->last_error, sizeof(dev->last_error), fmt, arg);
    else
        snprintf(dev->last_error, sizeof(dev->last_error), "%s", fmt);
}

void wg_device_init(wg_device *dev)
{
    memset(dev, 0, sizeof(*dev));
    dev->tun_fd = -1;
    dev->sock_fd = -1;
    pthread_mutex_init(&dev->lock, NULL);
}

void wg_device_destroy(wg_device *dev)
{
    /* peers 数组内嵌全部密钥/会话/队列，整体清零即完成敏感材料擦除 */
    wg_memzero(dev->peers, sizeof(dev->peers));
    wg_memzero(dev->private_key, sizeof(dev->private_key));
    wg_memzero(dev->public_key, sizeof(dev->public_key));
    dev->n_peers = 0;
    dev->listen_port = 0;
}

/* ---- allowed-ips ---- */

static bool parse_cidr(const char *s, wg_allowed_ip *out)
{
    char buf[64];
    const char *slash = strchr(s, '/');
    size_t hostlen;
    long cidr;
    char *endp = NULL;

    if (!slash) {
        /* 无 / 视为 /32 或 /128 */
        hostlen = strlen(s);
        cidr = -1;
    } else {
        hostlen = (size_t)(slash - s);
        cidr = strtol(slash + 1, &endp, 10);
        if (!endp || *endp != '\0' || cidr < 0)
            return false;
    }
    if (hostlen == 0 || hostlen >= sizeof(buf))
        return false;
    memcpy(buf, s, hostlen);
    buf[hostlen] = '\0';

    if (inet_pton(AF_INET, buf, out->addr) == 1) {
        if (cidr < 0)
            cidr = 32;
        if (cidr > 32)
            return false;
        out->family = 4;
        out->cidr = (uint8_t)cidr;
        return true;
    }
    if (inet_pton(AF_INET6, buf, out->addr) == 1) {
        if (cidr < 0)
            cidr = 128;
        if (cidr > 128)
            return false;
        out->family = 6;
        out->cidr = (uint8_t)cidr;
        return true;
    }
    return false;
}

static bool ip_match(const wg_allowed_ip *a, const uint8_t *ip, int family)
{
    if (a->family != family)
        return false;
    int full = a->cidr / 8;
    int rem = a->cidr % 8;
    if (full > 0 && memcmp(a->addr, ip, (size_t)full) != 0)
        return false;
    if (rem) {
        uint8_t mask = (uint8_t)(0xff << (8 - rem));
        if ((a->addr[full] & mask) != (ip[full] & mask))
            return false;
    }
    return true;
}

wg_peer *wg_peer_for_packet(wg_device *dev, const uint8_t *pkt, size_t len)
{
    if (len < 1)
        return NULL;
    int v = pkt[0] >> 4;
    const uint8_t *dst;
    int family;
    if (v == 4) {
        if (len < 20)
            return NULL;
        dst = pkt + 16;
        family = 4;
    } else if (v == 6) {
        if (len < 40)
            return NULL;
        dst = pkt + 24;
        family = 6;
    } else {
        return NULL;
    }

    wg_peer *best = NULL;
    int best_cidr = -1;
    for (int i = 0; i < dev->n_peers; i++) {
        wg_peer *p = &dev->peers[i];
        for (int j = 0; j < p->n_allowed; j++) {
            const wg_allowed_ip *a = &p->allowed[j];
            if ((int)a->cidr > best_cidr && ip_match(a, dst, family)) {
                best = p;
                best_cidr = a->cidr;
            }
        }
    }
    return best;
}

bool wg_peer_allows_source(const wg_peer *peer, const uint8_t *pkt, size_t len)
{
    if (len < 1)
        return false;
    int v = pkt[0] >> 4;
    const uint8_t *src;
    int family;
    if (v == 4) {
        if (len < 20)
            return false;
        src = pkt + 12;
        family = 4;
    } else if (v == 6) {
        if (len < 40)
            return false;
        src = pkt + 8;
        family = 6;
    } else {
        return false;
    }
    for (int j = 0; j < peer->n_allowed; j++) {
        if (ip_match(&peer->allowed[j], src, family))
            return true;
    }
    return false;
}

/* ---- 会话管理 ---- */

void wg_peer_install_keypair(wg_device *dev, wg_peer *peer, const wg_keypair *kp)
{
    int slot;
    if (peer->cur_kp < 0) {
        slot = 0;
    } else {
        slot = 1 - peer->cur_kp;
        wg_memzero(&peer->kp[slot], sizeof(peer->kp[slot]));
    }
    peer->kp[slot] = *kp;
    peer->kp[slot].valid = true;
    peer->cur_kp = slot;
    peer->last_handshake_ms = wg_now_realtime_ms();
    (void)dev;
}

void wg_peer_queue(wg_peer *peer, const uint8_t *pkt, size_t len)
{
    if (len == 0 || len > WG_QUEUE_SLOT)
        return;
    int slot;
    if (peer->queue_count < WG_QUEUE_LEN) {
        slot = peer->queue_count++;
    } else {
        /* 满：丢最旧，整体前移 */
        memmove(peer->queue_len, peer->queue_len + 1, sizeof(peer->queue_len) - sizeof(peer->queue_len[0]));
        memmove(peer->queue, peer->queue + 1, sizeof(peer->queue) - sizeof(peer->queue[0]));
        slot = WG_QUEUE_LEN - 1;
    }
    memcpy(peer->queue[slot], pkt, len);
    peer->queue_len[slot] = (uint16_t)len;
}

uint32_t wg_new_index(wg_device *dev)
{
    for (;;) {
        uint8_t b[4];
        if (!wg_random(b, sizeof(b)))
            return 0;
        uint32_t idx = wg_le32(b);
        if (idx == 0)
            continue; /* index 0 保留为非法/无效 */
        bool clash = false;
        for (int i = 0; i < dev->n_peers && !clash; i++) {
            wg_peer *p = &dev->peers[i];
            if (p->handshake_pending && p->pending_index == idx)
                clash = true;
            for (int k = 0; k < 2; k++)
                if (p->kp[k].valid && p->kp[k].index == idx)
                    clash = true;
        }
        if (!clash)
            return idx;
    }
}

/* ---- sockaddr 工具 ---- */

bool wg_sockaddr_equal(const struct sockaddr_storage *a, const struct sockaddr_storage *b)
{
    if (a->ss_family != b->ss_family)
        return false;
    if (a->ss_family == AF_INET) {
        const struct sockaddr_in *x = (const struct sockaddr_in *)a;
        const struct sockaddr_in *y = (const struct sockaddr_in *)b;
        return x->sin_port == y->sin_port && x->sin_addr.s_addr == y->sin_addr.s_addr;
    }
    if (a->ss_family == AF_INET6) {
        const struct sockaddr_in6 *x = (const struct sockaddr_in6 *)a;
        const struct sockaddr_in6 *y = (const struct sockaddr_in6 *)b;
        return x->sin6_port == y->sin6_port &&
               memcmp(&x->sin6_addr, &y->sin6_addr, sizeof(struct in6_addr)) == 0;
    }
    return false;
}

void wg_sockaddr_to_string(const struct sockaddr_storage *ss, char *out, size_t cap)
{
    char ip[INET6_ADDRSTRLEN];
    uint16_t port = 0;
    const void *addr = NULL;
    int family = ss->ss_family;
    bool v6 = false;

    if (ss->ss_family == AF_INET) {
        const struct sockaddr_in *s = (const struct sockaddr_in *)ss;
        addr = &s->sin_addr;
        port = ntohs(s->sin_port);
    } else if (ss->ss_family == AF_INET6) {
        const struct sockaddr_in6 *s = (const struct sockaddr_in6 *)ss;
        if (IN6_IS_ADDR_V4MAPPED(&s->sin6_addr)) {
            /* 双栈 socket 收到的 v4 包是 v4-mapped，统计展示时归一化为 v4 */
            family = AF_INET;
            addr = ((const uint8_t *)&s->sin6_addr) + 12;
            port = ntohs(s->sin6_port);
        } else {
            v6 = true;
            addr = &s->sin6_addr;
            port = ntohs(s->sin6_port);
        }
    } else {
        snprintf(out, cap, "?");
        return;
    }
    if (!inet_ntop(family, addr, ip, sizeof(ip))) {
        snprintf(out, cap, "?");
        return;
    }
    if (v6)
        snprintf(out, cap, "[%s]:%u", ip, port);
    else
        snprintf(out, cap, "%s:%u", ip, port);
}

void wg_sockaddr_to_v6mapped(const struct sockaddr_storage *in, struct sockaddr_storage *out)
{
    if (in->ss_family != AF_INET) {
        *out = *in;
        return;
    }
    const struct sockaddr_in *s = (const struct sockaddr_in *)in;
    struct sockaddr_in6 d;
    memset(&d, 0, sizeof(d));
    d.sin6_family = AF_INET6;
    d.sin6_port = s->sin_port;
    ((uint8_t *)&d.sin6_addr)[10] = 0xff;
    ((uint8_t *)&d.sin6_addr)[11] = 0xff;
    memcpy(((uint8_t *)&d.sin6_addr) + 12, &s->sin_addr, 4);
    memset(out, 0, sizeof(*out));
    memcpy(out, &d, sizeof(d));
}

/* 解析 endpoint "host:port"（host 为 IPv4 / [IPv6] / 域名），getaddrinfo 同步解析。 */
static bool resolve_endpoint(wg_device *dev, const char *endpoint, struct sockaddr_storage *out,
                             socklen_t *out_len)
{
    char host[256];
    char port[8];
    const char *colon = NULL;
    const char *port_str = NULL;

    memset(out, 0, sizeof(*out));

    if (endpoint[0] == '[') {
        const char *close = strchr(endpoint, ']');
        if (!close || close[1] != ':')
            return false;
        size_t hl = (size_t)(close - endpoint - 1);
        if (hl == 0 || hl >= sizeof(host))
            return false;
        memcpy(host, endpoint + 1, hl);
        host[hl] = '\0';
        port_str = close + 2;
    } else {
        colon = strrchr(endpoint, ':');
        if (!colon || strchr(endpoint, ':') != colon) /* 无端口或多个冒号（未加括号的 IPv6） */
            return false;
        size_t hl = (size_t)(colon - endpoint);
        if (hl == 0 || hl >= sizeof(host))
            return false;
        memcpy(host, endpoint, hl);
        host[hl] = '\0';
        port_str = colon + 1;
    }
    if (strlen(port_str) == 0 || strlen(port_str) >= sizeof(port))
        return false;
    for (const char *c = port_str; *c; c++)
        if (*c < '0' || *c > '9')
            return false;
    snprintf(port, sizeof(port), "%s", port_str);

    struct addrinfo hints;
    struct addrinfo *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;

    int rc = getaddrinfo(host, port, &hints, &res);
    if (rc != 0 || !res) {
        wg_set_last_error(dev, "%s", host);
        return false;
    }
    /* 优先 v4（双栈 socket 下 v4-mapped 发送最稳） */
    struct addrinfo *pick = NULL;
    for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
        if (ai->ai_family == AF_INET) {
            pick = ai;
            break;
        }
    }
    if (!pick) {
        for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
            if (ai->ai_family == AF_INET6) {
                pick = ai;
                break;
            }
        }
    }
    if (!pick || pick->ai_addrlen > sizeof(*out)) {
        freeaddrinfo(res);
        wg_set_last_error(dev, "%s", host);
        return false;
    }
    memcpy(out, pick->ai_addr, pick->ai_addrlen);
    *out_len = (socklen_t)pick->ai_addrlen;
    freeaddrinfo(res);
    return true;
}

/* ---- 配置解析 ---- */

static bool decode_key(const char *b64, uint8_t out[32])
{
    size_t n = 0;
    return strlen(b64) == 44 && wg_b64_decode(out, &n, b64, 44) && n == 32;
}

int wg_device_configure(wg_device *dev, const char *config_json)
{
    static wg_jtoken tokens[WG_JSON_TOKENS];
    size_t len = strlen(config_json);
    memset(tokens, 0, sizeof(tokens));
    int rc = wg_json_parse(config_json, len, tokens, WG_JSON_TOKENS);
    if (rc != 0) {
        wg_set_last_error(dev, "config json parse failed", NULL);
        return -1;
    }
    /* 顶层必须是 object */
    int root = -1;
    for (int i = 0; i < WG_JSON_TOKENS; i++) {
        if (tokens[i].parent == -1 && tokens[i].type == WG_J_OBJECT) {
            root = i;
            break;
        }
        if (tokens[i].type == WG_J_UNDEFINED)
            break;
    }
    if (root < 0)
        return -1;

    char buf[512];
    int ti;

    ti = wg_json_object_get(config_json, tokens, WG_JSON_TOKENS, root, "privateKey");
    if (ti < 0 || !wg_json_string(config_json, &tokens[ti], buf, sizeof(buf)) ||
        !decode_key(buf, dev->private_key)) {
        wg_set_last_error(dev, "bad privateKey", NULL);
        return -1;
    }
    curve25519_base(dev->public_key, dev->private_key);

    dev->listen_port = 0;
    ti = wg_json_object_get(config_json, tokens, WG_JSON_TOKENS, root, "listenPort");
    if (ti >= 0) {
        long v = 0;
        if (wg_json_long(config_json, &tokens[ti], &v) && v > 0 && v <= 65535)
            dev->listen_port = (uint16_t)v;
    }

    dev->n_peers = 0;
    int peers = wg_json_object_get(config_json, tokens, WG_JSON_TOKENS, root, "peers");
    if (peers < 0 || tokens[peers].type != WG_J_ARRAY)
        return 0; /* 零 Peer 合法（spec：不做额外拦截） */

    int n = tokens[peers].size;
    if (n > WG_MAX_PEERS)
        n = WG_MAX_PEERS;

    /* peers 数组的子元素下标：依赖 wg_json.c 的 parent 链 */
    int idx = -1;
    int count = 0;
    for (int i = 0; i < WG_JSON_TOKENS && count < n; i++) {
        if (tokens[i].type == WG_J_UNDEFINED)
            break;
        if (tokens[i].parent != peers)
            continue;
        int pi = i;
        wg_peer *p = &dev->peers[dev->n_peers];
        memset(p, 0, sizeof(*p));
        p->cur_kp = -1;

        ti = wg_json_object_get(config_json, tokens, WG_JSON_TOKENS, pi, "publicKey");
        if (ti < 0 || !wg_json_string(config_json, &tokens[ti], buf, sizeof(buf)) ||
            !decode_key(buf, p->public_key)) {
            wg_set_last_error(dev, "bad peer publicKey", NULL);
            return -1;
        }
        /* 不允许与自身公钥相同（协议禁止） */
        if (wg_ct_equal(p->public_key, dev->public_key, 32)) {
            wg_set_last_error(dev, "peer key equals own", NULL);
            return -1;
        }

        ti = wg_json_object_get(config_json, tokens, WG_JSON_TOKENS, pi, "presharedKey");
        if (ti >= 0 && wg_json_string(config_json, &tokens[ti], buf, sizeof(buf)) &&
            strlen(buf) == 44) {
            if (decode_key(buf, p->preshared_key))
                p->has_psk = true;
        }

        ti = wg_json_object_get(config_json, tokens, WG_JSON_TOKENS, pi, "endpoint");
        if (ti >= 0 && wg_json_string(config_json, &tokens[ti], buf, sizeof(buf)) && buf[0]) {
            if (!resolve_endpoint(dev, buf, &p->endpoint, &p->endpoint_len)) {
                wg_device_destroy(dev);
                return -2; /* last_error 已是主机名 */
            }
            p->has_endpoint = true;
        }

        ti = wg_json_object_get(config_json, tokens, WG_JSON_TOKENS, pi, "persistentKeepalive");
        if (ti >= 0) {
            long v = 0;
            if (wg_json_long(config_json, &tokens[ti], &v) && v > 0 && v <= 65535)
                p->persistent_keepalive = (uint16_t)v;
        }

        ti = wg_json_object_get(config_json, tokens, WG_JSON_TOKENS, pi, "allowedIPs");
        if (ti >= 0 && tokens[ti].type == WG_J_ARRAY) {
            int na = tokens[ti].size;
            for (int j = 0; j < WG_JSON_TOKENS && p->n_allowed < WG_MAX_ALLOWED_IPS && na > 0; j++) {
                if (tokens[j].type == WG_J_UNDEFINED)
                    break;
                if (tokens[j].parent != ti)
                    continue;
                na--;
                if (!wg_json_string(config_json, &tokens[j], buf, sizeof(buf)))
                    continue;
                wg_allowed_ip a;
                if (parse_cidr(buf, &a))
                    p->allowed[p->n_allowed++] = a;
            }
        }

        dev->n_peers++;
        count++;
        idx = pi;
    }
    (void)idx;
    return 0;
}

wg_peer *wg_peer_by_pubkey(wg_device *dev, const uint8_t pubkey[32])
{
    for (int i = 0; i < dev->n_peers; i++) {
        if (wg_ct_equal(dev->peers[i].public_key, pubkey, 32))
            return &dev->peers[i];
    }
    return NULL;
}
