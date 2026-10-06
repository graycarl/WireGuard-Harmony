/*
 * 主机侧协议仿真测试（决策 0007「C 层自测」增强项）。
 *
 * 覆盖：
 *  1. 密码原语 KAT（调用 wg_kat_selftest）
 *  2. 双端 Noise IK 握手仿真（无 PSK / 有 PSK 两种）
 *  3. 会话密钥一致性（A.send == B.recv 且 A.recv == B.send）
 *  4. transport 消息加解密、nonce 计数、重放拒绝、篡改拒绝、keepalive
 *  5. cryptokey routing（源 IP 不在 peer allowedIPs 内必须丢弃）
 *  6. roaming（来源地址变化且认证通过 → 更新 endpoint）
 *  7. 输出握手/传输转录文件，供 verify_handshake.py 做**独立**协议核对
 *
 * 编译运行见 build.sh。本文件不依赖 NAPI/OHOS，只用 POSIX + 标准库。
 */
#include "../wireguard.h"
#include "../blake2s.h"
#include "../curve25519.h"
#include "../wg_base64.h"

#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_fail = 0;

#define CHECK(cond, msg)                                                       \
    do {                                                                       \
        if (cond) {                                                            \
            printf("  [ok]   %s\n", (msg));                                    \
        } else {                                                               \
            printf("  [FAIL] %s\n", (msg));                                    \
            g_fail++;                                                          \
        }                                                                      \
    } while (0)

/* ---------------- 固定测试密钥 ---------------- */
static const char *A_PRIV_HEX = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a";
static const char *B_PRIV_HEX = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb";
static const char *PSK_HEX = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

static int unhex(const char *s, uint8_t *out, size_t cap)
{
    size_t n = strlen(s);
    if (n % 2 || n / 2 > cap)
        return -1;
    for (size_t i = 0; i < n / 2; i++) {
        unsigned v;
        if (sscanf(s + 2 * i, "%2x", &v) != 1)
            return -1;
        out[i] = (uint8_t)v;
    }
    return (int)(n / 2);
}

/* ---------------- 可复现临时密钥注入 ---------------- */
static int g_eph_call = 0;
static uint8_t g_eph_used[8][32];

static bool eph_hook(uint8_t out[32])
{
    uint8_t base = (uint8_t)(0x20 + g_eph_call * 0x11);
    for (int i = 0; i < 32; i++)
        out[i] = (uint8_t)(base + (uint8_t)i);
    if (g_eph_call < 8)
        memcpy(g_eph_used[g_eph_call], out, 32);
    g_eph_call++;
    return true;
}

/* ---------------- 设备配置 ---------------- */
static wg_device g_dev_a;
static wg_device g_dev_b;

static void build_config(wg_device *dev, const uint8_t priv[32], const uint8_t peer_pub[32],
                         const uint8_t *psk, char *json, size_t cap)
{
    char b64_priv[64], b64_pub[64], b64_psk[64] = "";
    wg_b64_encode(b64_priv, priv, 32);
    wg_b64_encode(b64_pub, peer_pub, 32);
    if (psk)
        wg_b64_encode(b64_psk, psk, 32);
    snprintf(json, cap,
             "{\"privateKey\":\"%s\",\"listenPort\":0,\"peers\":[{\"publicKey\":\"%s\","
             "\"presharedKey\":\"%s\",\"endpoint\":\"127.0.0.1:51820\","
             "\"allowedIPs\":[\"0.0.0.0/0\"],\"persistentKeepalive\":25}]}",
             b64_priv, b64_pub, b64_psk);
    (void)dev;
}

/* 构造一个最小内层 IPv4/UDP 包（src/dst 为点分十进制） */
static size_t make_inner_packet(uint8_t *pkt, const char *src, const char *dst, uint8_t fill)
{
    memset(pkt, 0, 28);
    pkt[0] = 0x45; /* IPv4, IHL=5 */
    pkt[2] = 0x00;
    pkt[3] = 28; /* total length */
    inet_pton(AF_INET, src, pkt + 12);
    inet_pton(AF_INET, dst, pkt + 16);
    pkt[9] = 17; /* UDP */
    for (int i = 20; i < 28; i++)
        pkt[i] = fill;
    return 28;
}

static struct sockaddr_storage mk_addr(const char *ip, uint16_t port)
{
    struct sockaddr_storage ss;
    memset(&ss, 0, sizeof(ss));
    struct sockaddr_in *s = (struct sockaddr_in *)&ss;
    s->sin_family = AF_INET;
    s->sin_port = htons(port);
    inet_pton(AF_INET, ip, &s->sin_addr);
    return ss;
}

static void tr_line(FILE *tr, const char *key, const uint8_t *v, size_t n)
{
    if (!tr)
        return;
    fprintf(tr, "%s=", key);
    for (size_t i = 0; i < n; i++)
        fprintf(tr, "%02x", v[i]);
    fputc('\n', tr);
}

/* ---------------- 一次完整双端仿真 ---------------- */
static void run_pair(const char *label, bool use_psk, FILE *tr)
{
    printf("== %s ==\n", label);

    uint8_t a_priv[32], b_priv[32], psk[32];
    uint8_t a_pub[32], b_pub[32];
    unhex(A_PRIV_HEX, a_priv, 32);
    unhex(B_PRIV_HEX, b_priv, 32);
    int psk_len = unhex(PSK_HEX, psk, 32);
    if (psk_len != 32)
        use_psk = false;
    curve25519_base(a_pub, a_priv);
    curve25519_base(b_pub, b_priv);

    char json_a[512], json_b[512];
    build_config(&g_dev_a, a_priv, b_pub, use_psk ? psk : NULL, json_a, sizeof(json_a));
    build_config(&g_dev_b, b_priv, a_pub, use_psk ? psk : NULL, json_b, sizeof(json_b));

    wg_device_init(&g_dev_a);
    wg_device_init(&g_dev_b);
    CHECK(wg_device_configure(&g_dev_a, json_a) == 0, "configure device A");
    CHECK(wg_device_configure(&g_dev_b, json_b) == 0, "configure device B");
    if (g_fail)
        return;

    wg_peer *pa = &g_dev_a.peers[0]; /* A 的 peer = B */
    wg_peer *pb = &g_dev_b.peers[0]; /* B 的 peer = A */
    CHECK(pa->has_endpoint && pb->has_endpoint, "endpoint resolved");
    CHECK(pa->has_psk == use_psk, "psk flag set");

    int eph_base = g_eph_call;

    /* --- 握手 --- */
    uint8_t m1[WG_INITIATION_LEN], m2[WG_RESPONSE_LEN];
    size_t m1len = 0, m2len = 0;
    CHECK(wg_handshake_create_initiation(&g_dev_a, pa, m1, &m1len) && m1len == WG_INITIATION_LEN,
          "A creates initiation");
    wg_peer *responder = NULL;
    CHECK(wg_handshake_consume_initiation(&g_dev_b, m1, m1len, m2, &m2len, &responder) &&
              responder == pb && m2len == WG_RESPONSE_LEN,
          "B consumes initiation and creates response");
    wg_peer *initiator = wg_handshake_consume_response(&g_dev_a, m2, m2len);
    CHECK(initiator == pa, "A consumes response");
    if (g_fail)
        return;

    /* --- 会话密钥一致 --- */
    CHECK(pa->cur_kp >= 0 && pb->cur_kp >= 0, "both peers have a keypair");
    const wg_keypair *ka = &pa->kp[pa->cur_kp];
    const wg_keypair *kb = &pb->kp[pb->cur_kp];
    CHECK(wg_ct_equal(ka->send_key, kb->recv_key, 32), "A.send == B.recv");
    CHECK(wg_ct_equal(ka->recv_key, kb->send_key, 32), "A.recv == B.send");
    CHECK(ka->remote_index == kb->index && kb->remote_index == ka->index,
          "local/remote index pair consistent");
    CHECK(pa->last_handshake_ms > 0 && pb->last_handshake_ms > 0, "handshake timestamps set");
    CHECK(ka->initiating && !kb->initiating, "initiator/responder roles");

    /* --- transport A→B --- */
    uint8_t inner[64], out[128], plain[128];
    size_t plen = make_inner_packet(inner, "10.0.0.1", "10.0.0.2", 0xab);
    int olen = wg_transport_encrypt(&g_dev_a, pa, inner, plen, out, sizeof(out));
    CHECK(olen == (int)(WG_TRANSPORT_HEADER + plen + WG_AEAD_TAG), "A encrypts transport message");

    struct sockaddr_storage roam = mk_addr("127.0.0.2", 12345);
    size_t out_plain = 0;
    wg_peer *hit = NULL;
    CHECK(wg_transport_decrypt(&g_dev_b, out, (size_t)olen, &roam, plain, &out_plain, &hit) &&
              hit == pb && out_plain == plen && memcmp(plain, inner, plen) == 0,
          "B decrypts transport message");

    /* --- roaming --- */
    CHECK(pb->has_endpoint && wg_sockaddr_equal(&pb->endpoint, &roam), "roaming updates endpoint");
    char epstr[64];
    wg_sockaddr_to_string(&pb->endpoint, epstr, sizeof(epstr));
    CHECK(strcmp(epstr, "127.0.0.2:12345") == 0, "endpoint string normalized");

    /* --- 重放拒绝 --- */
    CHECK(!wg_transport_decrypt(&g_dev_b, out, (size_t)olen, &roam, plain, &out_plain, &hit),
          "replayed message rejected");

    /* --- 篡改拒绝 --- */
    size_t plen2 = make_inner_packet(inner, "10.0.0.1", "10.0.0.2", 0xcd);
    int olen2 = wg_transport_encrypt(&g_dev_a, pa, inner, plen2, out, sizeof(out));
    out[olen2 - 1] ^= 0x01;
    CHECK(!wg_transport_decrypt(&g_dev_b, out, (size_t)olen2, &roam, plain, &out_plain, &hit),
          "tampered tag rejected");
    out[olen2 - 1] ^= 0x01;
    CHECK(wg_transport_decrypt(&g_dev_b, out, (size_t)olen2, &roam, plain, &out_plain, &hit),
          "tag failure does not consume replay window (decrypt-before-replay order)");

    /* --- keepalive --- */
    size_t kalen = 0;
    CHECK(wg_transport_make_keepalive(&g_dev_a, pa, out, &kalen) && kalen == WG_TRANSPORT_HEADER + WG_AEAD_TAG,
          "A creates keepalive");
    CHECK(wg_transport_decrypt(&g_dev_b, out, kalen, &roam, plain, &out_plain, &hit) && out_plain == 0,
          "B accepts keepalive (empty payload)");

    /* --- B→A 方向 --- */
    size_t plen3 = make_inner_packet(inner, "10.0.0.2", "10.0.0.1", 0xef);
    int olen3 = wg_transport_encrypt(&g_dev_b, pb, inner, plen3, out, sizeof(out));
    CHECK(olen3 > 0 && wg_transport_decrypt(&g_dev_a, out, (size_t)olen3, NULL, plain, &out_plain, &hit) &&
              out_plain == plen3 && memcmp(plain, inner, plen3) == 0,
          "B→A transport works");

    /* --- cryptokey routing：源 IP 不在 allowedIPs 内必须丢弃 --- */
    wg_allowed_ip keep;
    memset(&keep, 0, sizeof(keep));
    inet_pton(AF_INET, "10.0.0.0", keep.addr);
    keep.family = 4;
    keep.cidr = 24;
    wg_allowed_ip saved = pb->allowed[0];
    pb->allowed[0] = keep;
    size_t plen4 = make_inner_packet(inner, "192.168.1.7", "10.0.0.2", 0x11);
    int olen4 = wg_transport_encrypt(&g_dev_a, pa, inner, plen4, out, sizeof(out));
    CHECK(olen4 > 0 && !wg_transport_decrypt(&g_dev_b, out, (size_t)olen4, &roam, plain, &out_plain, &hit),
          "source outside allowedIPs dropped (cryptokey routing)");
    pb->allowed[0] = saved;

    /* --- 重复 initiation 重发缓存响应 --- */
    uint8_t m2b[WG_RESPONSE_LEN];
    size_t m2blen = 0;
    wg_peer *again = NULL;
    CHECK(wg_handshake_consume_initiation(&g_dev_b, m1, m1len, m2b, &m2blen, &again) && again == pb &&
              m2blen == m2len && memcmp(m2, m2b, m2len) == 0,
          "duplicate initiation replays cached response");

    /* --- 转录（供独立 Python 核对） --- */
    if (tr) {
        uint8_t psk_flag = use_psk ? 1 : 0;
        tr_line(tr, "use_psk", &psk_flag, 1);
        tr_line(tr, "a_priv", a_priv, 32);
        tr_line(tr, "a_pub", a_pub, 32);
        tr_line(tr, "b_priv", b_priv, 32);
        tr_line(tr, "b_pub", b_pub, 32);
        tr_line(tr, "psk", psk, 32);
        tr_line(tr, "eph_i", g_eph_used[eph_base], 32);
        tr_line(tr, "eph_r", g_eph_used[eph_base + 1], 32);
        tr_line(tr, "msg1", m1, m1len);
        tr_line(tr, "msg2", m2, m2len);
        /* 受控的 transport 消息：A→B（新计数器） */
        uint8_t tinner[64];
        size_t tplen = make_inner_packet(tinner, "10.0.0.1", "10.0.0.2", 0x5a);
        uint8_t tout[128];
        int tol = wg_transport_encrypt(&g_dev_a, pa, tinner, tplen, tout, sizeof(tout));
        if (tol > 0) {
            tr_line(tr, "transport_ab", tout, (size_t)tol);
            tr_line(tr, "plain_ab", tinner, tplen);
        }
        uint8_t binner[64];
        size_t bplen = make_inner_packet(binner, "10.0.0.2", "10.0.0.1", 0x6b);
        uint8_t bout[128];
        int bol = wg_transport_encrypt(&g_dev_b, pb, binner, bplen, bout, sizeof(bout));
        if (bol > 0) {
            tr_line(tr, "transport_ba", bout, (size_t)bol);
            tr_line(tr, "plain_ba", binner, bplen);
        }
    }

    wg_device_destroy(&g_dev_a);
    wg_device_destroy(&g_dev_b);
}

int main(int argc, char **argv)
{
    const char *tr_nopsk = argc > 1 ? argv[1] : "transcript_nopsk.txt";
    const char *tr_psk = argc > 2 ? argv[2] : "transcript_psk.txt";

    printf("=== WireGuard 数据面主机侧测试 ===\n");

    printf("-- 密码原语 KAT --\n");
    CHECK(wg_kat_selftest(), "primitives KAT (blake2s/hmac-kdf/chacha20poly1305/x25519)");

    wg_ephemeral_hook = eph_hook;

    FILE *tr1 = fopen(tr_nopsk, "w");
    if (!tr1)
        printf("[warn] cannot open transcript file %s\n", tr_nopsk);
    run_pair("握手 + 传输（无 PSK）", false, tr1);
    if (tr1)
        fclose(tr1);

    FILE *tr2 = fopen(tr_psk, "w");
    if (!tr2)
        printf("[warn] cannot open transcript file %s\n", tr_psk);
    run_pair("握手 + 传输（有 PSK）", true, tr2);
    if (tr2)
        fclose(tr2);

    printf("=== 结果：%s（失败断言 %d 个）===\n", g_fail == 0 ? "PASS" : "FAIL", g_fail);
    return g_fail == 0 ? 0 : 1;
}
