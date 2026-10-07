/*
 * WireGuard 握手：Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s。
 * 消息布局（全部小端头部）：
 *   initiation(148): type(4)=1 | sender_index(4) | ephemeral(32) |
 *                    enc_static(48) | enc_tai64n(28) | mac1(16) | mac2(16)
 *   response(92):    type(4)=2 | sender_index(4) | receiver_index(4) |
 *                    ephemeral(32) | enc_empty(16) | mac1(16) | mac2(16)
 * cookie（type 3）v1 不实现（决策 0002 §3）：mac2 恒零，收到 cookie reply 忽略。
 */
#include "wireguard.h"
#include "blake2s.h"
#include "chacha20poly1305.h"
#include "curve25519.h"

#include <string.h>
#include <time.h>

/* initiation 中 mac1 之前的字节数（type..enc_tai64n 结束） */
#define INIT_MAC1_OFFSET 116
/* response 中 mac1 之前的字节数 */
#define RESP_MAC1_OFFSET 60

static void hash2(uint8_t out[32], const uint8_t *a, size_t alen, const uint8_t *b, size_t blen)
{
    blake2s_state S;
    blake2s_init(&S, 32);
    blake2s_update(&S, a, alen);
    if (b && blen)
        blake2s_update(&S, b, blen);
    blake2s_final(&S, out);
}

/* ck0 = HASH(CONSTRUCTION)；h0 = HASH(ck0 || IDENTIFIER)；h = HASH(h0 || responder_static_pub)
 * （对齐 wireguard-go init()：InitialChainKey=HASH(NoiseConstruction)，
 *   InitialHash=mixHash(InitialChainKey, WGIdentifier)） */
static void initial_state(uint8_t ck[32], uint8_t h[32], const uint8_t responder_pub[32])
{
    uint8_t tmp[32];
    blake2s(tmp, (const uint8_t *)WG_CONSTRUCTION, strlen(WG_CONSTRUCTION), 32);
    hash2(h, tmp, 32, (const uint8_t *)WG_IDENTIFIER, strlen(WG_IDENTIFIER));
    hash2(h, h, 32, responder_pub, 32);
    memcpy(ck, tmp, 32);
    wg_memzero(tmp, sizeof(tmp));
}

/* mac1 = BLAKE2s-keyed(key=HASH(label||pub), msg, 16) */
static void mac1_compute(uint8_t out[16], const uint8_t pub[32], const uint8_t *msg, size_t len)
{
    uint8_t key[32];
    hash2(key, (const uint8_t *)WG_LABEL_MAC1, 8, pub, 32);
    blake2s_keyed(out, msg, len, key, 32, 16);
    wg_memzero(key, sizeof(key));
}

/* TAI64N：12 字节 = BE64(sec + 2^62 + 10) || BE32(nsec) */
static void tai64n_now(uint8_t out[12])
{
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    uint64_t sec = (uint64_t)ts.tv_sec + 0x400000000000000aULL;
    uint32_t nsec = (uint32_t)ts.tv_nsec;
    for (int i = 0; i < 8; i++)
        out[i] = (uint8_t)(sec >> (56 - 8 * i));
    for (int i = 0; i < 4; i++)
        out[8 + i] = (uint8_t)(nsec >> (24 - 8 * i));
}

static void aead_nonce_zero(uint8_t nonce[12])
{
    memset(nonce, 0, 12);
}

bool wg_handshake_create_initiation(wg_device *dev, wg_peer *peer, uint8_t *out, size_t *out_len)
{
    uint8_t ck[32], h[32], k[32], dh[32];
    uint8_t nonce[12];
    uint8_t tai[12];

    if (!peer->has_endpoint)
        return false;

    initial_state(ck, h, peer->public_key);

    /* ephemeral */
    if (!wg_ephemeral_key(peer->pending_eph_priv))
        return false;
    uint8_t eph_pub[32];
    curve25519_base(eph_pub, peer->pending_eph_priv);

    /* ck = KDF1(ck, eph_pub)；h = HASH(h || eph_pub) */
    wg_kdf1(ck, ck, eph_pub, 32);
    hash2(h, h, 32, eph_pub, 32);

    memset(out, 0, WG_INITIATION_LEN);
    wg_put_le32(out, WG_MSG_INITIATION);
    uint32_t index = wg_new_index(dev);
    if (index == 0)
        return false;
    wg_put_le32(out + 4, index);
    memcpy(out + 8, eph_pub, 32);

    /* (ck, k) = KDF2(ck, DH(eph_priv, rs))；enc_static = AEAD(k, 0, s_pub, h) */
    curve25519(dh, peer->pending_eph_priv, peer->public_key);
    wg_kdf2(ck, k, ck, dh, 32);
    aead_nonce_zero(nonce);
    chacha20poly1305_encrypt(out + 40, dev->public_key, 32, h, 32, k, nonce);
    hash2(h, h, 32, out + 40, 48);

    /* (ck, k) = KDF2(ck, DH(s_priv, rs))；enc_ts = AEAD(k, 0, tai64n, h) */
    curve25519(dh, dev->private_key, peer->public_key);
    wg_kdf2(ck, k, ck, dh, 32);
    tai64n_now(tai);
    chacha20poly1305_encrypt(out + 88, tai, 12, h, 32, k, nonce);
    hash2(h, h, 32, out + 88, 28);

    mac1_compute(out + INIT_MAC1_OFFSET, peer->public_key, out, INIT_MAC1_OFFSET);
    /* mac2 恒零（无 cookie） */

    /* 保存 pending 状态供 response 处理 */
    memcpy(peer->pending_ck, ck, 32);
    memcpy(peer->pending_hash, h, 32);
    peer->pending_index = index;
    peer->handshake_pending = true;
    double now = wg_now_mono();
    if (peer->first_attempt_mono == 0.0)
        peer->first_attempt_mono = now;
    peer->last_attempt_mono = now;

    wg_memzero(ck, sizeof(ck));
    wg_memzero(h, sizeof(h));
    wg_memzero(k, sizeof(k));
    wg_memzero(dh, sizeof(dh));
    wg_memzero(eph_pub, sizeof(eph_pub));
    *out_len = WG_INITIATION_LEN;
    return true;
}

bool wg_handshake_consume_initiation(wg_device *dev, const uint8_t *msg, size_t len,
                                     uint8_t *out_response, size_t *out_len, wg_peer **peer_out)
{
    uint8_t ck[32], h[32], k[32], dh[32], tau[32];
    uint8_t nonce[12];
    uint8_t static_pub[32];
    wg_peer *peer;

    *peer_out = NULL;
    if (len != WG_INITIATION_LEN || wg_le32(msg) != WG_MSG_INITIATION)
        return false;

    /* mac1 校验（key 用我方静态公钥） */
    uint8_t mac[16];
    mac1_compute(mac, dev->public_key, msg, INIT_MAC1_OFFSET);
    if (!wg_ct_equal(mac, msg + INIT_MAC1_OFFSET, 16))
        return false;

    const uint8_t *eph_i = msg + 8;

    initial_state(ck, h, dev->public_key);
    wg_kdf1(ck, ck, eph_i, 32);
    hash2(h, h, 32, eph_i, 32);

    /* (ck, k) = KDF2(ck, DH(s_priv, eph_i))；解 enc_static → 对端静态公钥 */
    curve25519(dh, dev->private_key, eph_i);
    wg_kdf2(ck, k, ck, dh, 32);
    aead_nonce_zero(nonce);
    if (!chacha20poly1305_decrypt(static_pub, msg + 40, 48, h, 32, k, nonce)) {
        goto fail;
    }
    hash2(h, h, 32, msg + 40, 48);

    peer = wg_peer_by_pubkey(dev, static_pub);
    if (!peer) {
        goto fail;
    }

    /* 重复 initiation：直接重发缓存响应（防重放/防抖动，对齐 kernel 行为） */
    if (peer->has_cached_response && peer->last_initiation_len == len &&
        wg_ct_equal(peer->last_initiation, msg, len)) {
        memcpy(out_response, peer->cached_response, peer->cached_response_len);
        *out_len = peer->cached_response_len;
        *peer_out = peer;
        return true;
    }

    /* (ck, k) = KDF2(ck, DH(s_priv, s_i))；解 tai64n 并做防重放（严格递增） */
    curve25519(dh, dev->private_key, static_pub);
    wg_kdf2(ck, k, ck, dh, 32);
    uint8_t tai[12];
    if (!chacha20poly1305_decrypt(tai, msg + 88, 28, h, 32, k, nonce)) {
        goto fail;
    }
    if (peer->has_tai64n && memcmp(tai, peer->last_tai64n, 12) <= 0) {
        goto fail;
    }
    hash2(h, h, 32, msg + 88, 28);

    /* ---- 生成 response ---- */
    uint8_t eph_r_priv[32], eph_r_pub[32];
    if (!wg_ephemeral_key(eph_r_priv))
        goto fail;
    curve25519_base(eph_r_pub, eph_r_priv);

    wg_kdf1(ck, ck, eph_r_pub, 32);
    hash2(h, h, 32, eph_r_pub, 32);

    /* (ck) = KDF1(ck, DH(eph_r, eph_i))；密钥由后面的 KDF3(psk) 给出 */
    curve25519(dh, eph_r_priv, eph_i);
    wg_kdf1(ck, ck, dh, 32);
    /* (ck) = KDF1(ck, DH(eph_r, s_i)) */
    curve25519(dh, eph_r_priv, static_pub);
    wg_kdf1(ck, ck, dh, 32);

    /* (ck, tau, k) = KDF3(ck, psk)；h = HASH(h || tau) */
    {
        const uint8_t *psk = peer->has_psk ? peer->preshared_key : NULL;
        uint8_t zero_psk[32] = { 0 };
        if (!psk)
            psk = zero_psk;
        wg_kdf3(ck, tau, k, ck, psk, 32);
    }
    hash2(h, h, 32, tau, 32);

    memset(out_response, 0, WG_RESPONSE_LEN);
    wg_put_le32(out_response, WG_MSG_RESPONSE);
    uint32_t index = wg_new_index(dev);
    if (index == 0)
        goto fail;
    wg_put_le32(out_response + 4, index);
    wg_put_le32(out_response + 8, wg_le32(msg + 4)); /* receiver = 对端 sender index */
    memcpy(out_response + 12, eph_r_pub, 32);

    /* enc_empty = AEAD(k, 0, ε, h) */
    chacha20poly1305_encrypt(out_response + 44, NULL, 0, h, 32, k, nonce);
    hash2(h, h, 32, out_response + 44, 16);

    mac1_compute(out_response + RESP_MAC1_OFFSET, peer->public_key, out_response, RESP_MAC1_OFFSET);

    /* 安装会话：响应方 send=T2 / recv=T1（T1/T2 = KDF2(ck, ε)） */
    {
        uint8_t t1[32], t2[32];
        wg_keypair kp;
        memset(&kp, 0, sizeof(kp));
        wg_kdf2(t1, t2, ck, NULL, 0);
        memcpy(kp.recv_key, t1, 32);
        memcpy(kp.send_key, t2, 32);
        kp.index = index;
        kp.remote_index = wg_le32(msg + 4); /* initiation 的 sender = 对端 index */
        kp.born_mono = wg_now_mono();
        kp.initiating = false;
        wg_peer_install_keypair(dev, peer, &kp);
        wg_memzero(t1, sizeof(t1));
        wg_memzero(t2, sizeof(t2));
        wg_memzero(&kp, sizeof(kp));
    }

    memcpy(peer->last_tai64n, tai, 12);
    peer->has_tai64n = true;
    /* 缓存 initiation/响应（重复 initiation 重发） */
    memcpy(peer->last_initiation, msg, len);
    peer->last_initiation_len = len;
    memcpy(peer->cached_response, out_response, WG_RESPONSE_LEN);
    peer->cached_response_len = WG_RESPONSE_LEN;
    peer->has_cached_response = true;
    /* 新握手使旧的 pending（我方曾发起）作废：对端已另起会话 */
    peer->handshake_pending = false;
    peer->first_attempt_mono = 0.0;

    wg_memzero(eph_r_priv, sizeof(eph_r_priv));
    wg_memzero(ck, sizeof(ck));
    wg_memzero(h, sizeof(h));
    wg_memzero(k, sizeof(k));
    wg_memzero(dh, sizeof(dh));
    wg_memzero(tau, sizeof(tau));
    wg_memzero(static_pub, sizeof(static_pub));
    *out_len = WG_RESPONSE_LEN;
    *peer_out = peer;
    return true;

fail:
    wg_memzero(ck, sizeof(ck));
    wg_memzero(h, sizeof(h));
    wg_memzero(k, sizeof(k));
    wg_memzero(dh, sizeof(dh));
    wg_memzero(static_pub, sizeof(static_pub));
    return false;
}

wg_peer *wg_handshake_consume_response(wg_device *dev, const uint8_t *msg, size_t len)
{
    uint8_t ck[32], h[32], k[32], dh[32], tau[32];
    uint8_t nonce[12];

    if (len != WG_RESPONSE_LEN || wg_le32(msg) != WG_MSG_RESPONSE)
        return NULL;

    uint32_t receiver = wg_le32(msg + 8);
    wg_peer *peer = NULL;
    for (int i = 0; i < dev->n_peers; i++) {
        if (dev->peers[i].handshake_pending && dev->peers[i].pending_index == receiver) {
            peer = &dev->peers[i];
            break;
        }
    }
    if (!peer)
        return NULL;

    const uint8_t *eph_r = msg + 12;

    memcpy(ck, peer->pending_ck, 32);
    memcpy(h, peer->pending_hash, 32);

    /* ck = KDF1(ck, eph_r)；h = HASH(h || eph_r) */
    wg_kdf1(ck, ck, eph_r, 32);
    hash2(h, h, 32, eph_r, 32);

    /* (ck) = KDF1(ck, DH(eph_i_priv, eph_r)) */
    curve25519(dh, peer->pending_eph_priv, eph_r);
    wg_kdf1(ck, ck, dh, 32);
    /* (ck) = KDF1(ck, DH(s_priv, eph_r)) */
    curve25519(dh, dev->private_key, eph_r);
    wg_kdf1(ck, ck, dh, 32);

    /* (ck, tau, k) = KDF3(ck, psk)；h = HASH(h || tau) */
    {
        const uint8_t *psk = peer->has_psk ? peer->preshared_key : NULL;
        uint8_t zero_psk[32] = { 0 };
        if (!psk)
            psk = zero_psk;
        wg_kdf3(ck, tau, k, ck, psk, 32);
    }
    hash2(h, h, 32, tau, 32);

    /* 校验 enc_empty = AEAD(k, 0, ε, h) */
    aead_nonce_zero(nonce);
    uint8_t empty_pt[1];
    if (!chacha20poly1305_decrypt(empty_pt, msg + 44, 16, h, 32, k, nonce))
        goto fail;
    hash2(h, h, 32, msg + 44, 16);

    /* 安装会话：发起方 send=T1 / recv=T2 */
    {
        uint8_t t1[32], t2[32];
        wg_keypair kp;
        memset(&kp, 0, sizeof(kp));
        wg_kdf2(t1, t2, ck, NULL, 0);
        memcpy(kp.send_key, t1, 32);
        memcpy(kp.recv_key, t2, 32);
        kp.index = peer->pending_index;
        kp.remote_index = wg_le32(msg + 4); /* response 的 sender = 对端 index */
        kp.born_mono = wg_now_mono();
        kp.initiating = true;
        wg_peer_install_keypair(dev, peer, &kp);
        wg_memzero(t1, sizeof(t1));
        wg_memzero(t2, sizeof(t2));
        wg_memzero(&kp, sizeof(kp));
    }

    peer->handshake_pending = false;
    peer->first_attempt_mono = 0.0;
    wg_memzero(peer->pending_eph_priv, sizeof(peer->pending_eph_priv));

    wg_memzero(ck, sizeof(ck));
    wg_memzero(h, sizeof(h));
    wg_memzero(k, sizeof(k));
    wg_memzero(dh, sizeof(dh));
    wg_memzero(tau, sizeof(tau));
    return peer;

fail:
    wg_memzero(ck, sizeof(ck));
    wg_memzero(h, sizeof(h));
    wg_memzero(k, sizeof(k));
    wg_memzero(dh, sizeof(dh));
    return NULL;
}
