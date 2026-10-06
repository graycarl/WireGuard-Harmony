/*
 * ChaCha20（RFC 8439，public domain 参考实现风格）
 * Poly1305（poly1305-donna 32 位版，Andrew Moon，public domain）
 */
#include "chacha20poly1305.h"
#include "wg_log.h"

#include <string.h>

/* ============================ ChaCha20 ============================ */

static uint32_t chacha_load32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void chacha_store32(uint8_t *p, uint32_t w)
{
    p[0] = (uint8_t)w;
    p[1] = (uint8_t)(w >> 8);
    p[2] = (uint8_t)(w >> 16);
    p[3] = (uint8_t)(w >> 24);
}

static uint32_t rotl32(uint32_t v, unsigned c)
{
    return (v << c) | (v >> (32 - c));
}

#define QR(a, b, c, d)              \
    do {                            \
        a += b; d ^= a; d = rotl32(d, 16); \
        c += d; b ^= c; b = rotl32(b, 12); \
        a += b; d ^= a; d = rotl32(d, 8);  \
        c += d; b ^= c; b = rotl32(b, 7);  \
    } while (0)

static void chacha20_block(uint8_t out[64], const uint32_t state[16])
{
    uint32_t x[16];
    memcpy(x, state, sizeof(x));
    for (unsigned i = 0; i < 10; i++) {
        QR(x[0], x[4], x[8], x[12]);
        QR(x[1], x[5], x[9], x[13]);
        QR(x[2], x[6], x[10], x[14]);
        QR(x[3], x[7], x[11], x[15]);
        QR(x[0], x[5], x[10], x[15]);
        QR(x[1], x[6], x[11], x[12]);
        QR(x[2], x[7], x[8], x[13]);
        QR(x[3], x[4], x[9], x[14]);
    }
    for (unsigned i = 0; i < 16; i++)
        chacha_store32(out + 4 * i, x[i] + state[i]);
    wg_memzero(x, sizeof(x));
}

void chacha20_xor(uint8_t *out, const uint8_t *in, size_t inlen,
                  const uint8_t key[32], const uint8_t nonce[12], uint32_t counter)
{
    uint32_t state[16];
    uint8_t block[64];

    state[0] = 0x61707865u;
    state[1] = 0x3320646eu;
    state[2] = 0x79622d32u;
    state[3] = 0x6b206574u;
    for (unsigned i = 0; i < 8; i++)
        state[4 + i] = chacha_load32(key + 4 * i);
    state[12] = counter;
    state[13] = chacha_load32(nonce + 0);
    state[14] = chacha_load32(nonce + 4);
    state[15] = chacha_load32(nonce + 8);

    while (inlen > 0) {
        chacha20_block(block, state);
        size_t n = inlen < 64 ? inlen : 64;
        for (size_t i = 0; i < n; i++)
            out[i] = in[i] ^ block[i];
        in += n;
        out += n;
        inlen -= n;
        state[12]++;
    }
    wg_memzero(state, sizeof(state));
    wg_memzero(block, sizeof(block));
}

/* ============================ Poly1305 (donna 32) ============================ */

typedef struct {
    uint32_t r[5];
    uint32_t h[5];
    uint32_t pad[4];
    size_t leftover;
    uint8_t buffer[16];
    bool final;
} poly1305_state;

static void poly1305_init(poly1305_state *st, const uint8_t key[32])
{
    /* r &= 0xffffffc0ffffffc0ffffffc0fffffff */
    st->r[0] = (chacha_load32(key + 0)) & 0x3ffffffu;
    st->r[1] = (chacha_load32(key + 3) >> 2) & 0x3ffff03u;
    st->r[2] = (chacha_load32(key + 6) >> 4) & 0x3ffc0ffu;
    st->r[3] = (chacha_load32(key + 9) >> 6) & 0x3f03fffu;
    st->r[4] = (chacha_load32(key + 12) >> 8) & 0x00fffffu;

    for (unsigned i = 0; i < 5; i++)
        st->h[i] = 0;
    for (unsigned i = 0; i < 4; i++)
        st->pad[i] = chacha_load32(key + 16 + 4 * i);
    st->leftover = 0;
    st->final = false;
}

static void poly1305_blocks(poly1305_state *st, const uint8_t *in, size_t inlen)
{
    const uint32_t hibit = st->final ? 0u : (1u << 24); /* 1 << 128 */

    while (inlen >= 16) {
        uint32_t t[5];
        uint32_t r[5], h[5];
        uint64_t d[5];
        uint32_t c;

        t[0] = chacha_load32(in + 0);
        t[1] = chacha_load32(in + 4);
        t[2] = chacha_load32(in + 8);
        t[3] = chacha_load32(in + 12);

        h[0] = st->h[0] + (t[0] & 0x3ffffffu);
        h[1] = st->h[1] + (((t[0] >> 26) | (t[1] << 6)) & 0x3ffffffu);
        h[2] = st->h[2] + (((t[1] >> 20) | (t[2] << 12)) & 0x3ffffffu);
        h[3] = st->h[3] + (((t[2] >> 14) | (t[3] << 18)) & 0x3ffffffu);
        h[4] = st->h[4] + ((t[3] >> 8) | hibit);

        for (unsigned i = 0; i < 5; i++)
            r[i] = st->r[i];

        d[0] = (uint64_t)h[0] * r[0] + (uint64_t)h[1] * (r[4] * 5) + (uint64_t)h[2] * (r[3] * 5) +
               (uint64_t)h[3] * (r[2] * 5) + (uint64_t)h[4] * (r[1] * 5);
        d[1] = (uint64_t)h[0] * r[1] + (uint64_t)h[1] * r[0] + (uint64_t)h[2] * (r[4] * 5) +
               (uint64_t)h[3] * (r[3] * 5) + (uint64_t)h[4] * (r[2] * 5);
        d[2] = (uint64_t)h[0] * r[2] + (uint64_t)h[1] * r[1] + (uint64_t)h[2] * r[0] +
               (uint64_t)h[3] * (r[4] * 5) + (uint64_t)h[4] * (r[3] * 5);
        d[3] = (uint64_t)h[0] * r[3] + (uint64_t)h[1] * r[2] + (uint64_t)h[2] * r[1] +
               (uint64_t)h[3] * r[0] + (uint64_t)h[4] * (r[4] * 5);
        d[4] = (uint64_t)h[0] * r[4] + (uint64_t)h[1] * r[3] + (uint64_t)h[2] * r[2] +
               (uint64_t)h[3] * r[1] + (uint64_t)h[4] * r[0];

        c = (uint32_t)(d[0] >> 26); h[0] = (uint32_t)d[0] & 0x3ffffffu;
        d[1] += c; c = (uint32_t)(d[1] >> 26); h[1] = (uint32_t)d[1] & 0x3ffffffu;
        d[2] += c; c = (uint32_t)(d[2] >> 26); h[2] = (uint32_t)d[2] & 0x3ffffffu;
        d[3] += c; c = (uint32_t)(d[3] >> 26); h[3] = (uint32_t)d[3] & 0x3ffffffu;
        d[4] += c; c = (uint32_t)(d[4] >> 26); h[4] = (uint32_t)d[4] & 0x3ffffffu;
        h[0] += c * 5; c = h[0] >> 26; h[0] &= 0x3ffffffu;
        h[1] += c;

        for (unsigned i = 0; i < 5; i++)
            st->h[i] = h[i];

        in += 16;
        inlen -= 16;
    }
}

static void poly1305_update(poly1305_state *st, const uint8_t *in, size_t inlen)
{
    if (st->leftover) {
        size_t want = 16 - st->leftover;
        if (want > inlen)
            want = inlen;
        memcpy(st->buffer + st->leftover, in, want);
        inlen -= want;
        in += want;
        st->leftover += want;
        if (st->leftover < 16)
            return;
        poly1305_blocks(st, st->buffer, 16);
        st->leftover = 0;
    }
    if (inlen >= 16) {
        size_t want = inlen & ~(size_t)15;
        poly1305_blocks(st, in, want);
        in += want;
        inlen -= want;
    }
    if (inlen) {
        memcpy(st->buffer, in, inlen);
        st->leftover = inlen;
    }
}

static void poly1305_finish(poly1305_state *st, uint8_t tag[16])
{
    if (st->leftover) {
        size_t i = st->leftover;
        st->buffer[i++] = 1;
        for (; i < 16; i++)
            st->buffer[i] = 0;
        st->final = true;
        poly1305_blocks(st, st->buffer, 16);
    }

    /* fully carry h */
    uint32_t h[5];
    uint32_t c;
    memcpy(h, st->h, sizeof(h));
    c = h[1] >> 26; h[1] &= 0x3ffffffu; h[2] += c;
    c = h[2] >> 26; h[2] &= 0x3ffffffu; h[3] += c;
    c = h[3] >> 26; h[3] &= 0x3ffffffu; h[4] += c;
    c = h[4] >> 26; h[4] &= 0x3ffffffu; h[0] += c * 5;
    c = h[0] >> 26; h[0] &= 0x3ffffffu; h[1] += c;

    /* compute h + -p */
    uint32_t g[5];
    g[0] = h[0] + 5; c = g[0] >> 26; g[0] &= 0x3ffffffu;
    g[1] = h[1] + c; c = g[1] >> 26; g[1] &= 0x3ffffffu;
    g[2] = h[2] + c; c = g[2] >> 26; g[2] &= 0x3ffffffu;
    g[3] = h[3] + c; c = g[3] >> 26; g[3] &= 0x3ffffffu;
    g[4] = h[4] + c - (1u << 26);

    /* select h if h < p, or h + -p if h >= p */
    uint32_t mask = (g[4] >> 31) - 1; /* all ones if h>=p (g4 didn't borrow), else 0 */
    uint32_t nmask = ~mask;
    for (unsigned i = 0; i < 5; i++)
        h[i] = (h[i] & nmask) | (g[i] & mask);

    /* h 转 4×32-bit 字并加上 pad（donna 原版进位链） */
    uint64_t f;
    uint32_t h0 = h[0] | (h[1] << 26);
    uint32_t h1 = (h[1] >> 6) | (h[2] << 20);
    uint32_t h2 = (h[2] >> 12) | (h[3] << 14);
    uint32_t h3 = (h[3] >> 18) | (h[4] << 8);
    f = (uint64_t)h0 + st->pad[0]; h0 = (uint32_t)f;
    f = (uint64_t)h1 + st->pad[1] + (f >> 32); h1 = (uint32_t)f;
    f = (uint64_t)h2 + st->pad[2] + (f >> 32); h2 = (uint32_t)f;
    f = (uint64_t)h3 + st->pad[3] + (f >> 32); h3 = (uint32_t)f;
    chacha_store32(tag + 0, h0);
    chacha_store32(tag + 4, h1);
    chacha_store32(tag + 8, h2);
    chacha_store32(tag + 12, h3);

    wg_memzero(st, sizeof(*st));
    wg_memzero(h, sizeof(h));
    wg_memzero(g, sizeof(g));
}

void poly1305_auth(uint8_t tag[16], const uint8_t *in, size_t inlen, const uint8_t key[32])
{
    poly1305_state st;
    poly1305_init(&st, key);
    poly1305_update(&st, in, inlen);
    poly1305_finish(&st, tag);
}

/* ============================ AEAD ============================ */

/* RFC 8439 §2.8：mac_data = aad || pad16 || ciphertext || pad16 || le64(aadlen) || le64(ctlen) */
static void aead_mac(uint8_t tag[16], const uint8_t poly_key[32],
                     const uint8_t *aad, size_t aadlen,
                     const uint8_t *ct, size_t ctlen)
{
    poly1305_state st;
    uint8_t zeros[16] = { 0 };
    uint8_t lens[16];

    poly1305_init(&st, poly_key);
    poly1305_update(&st, aad, aadlen);
    if (aadlen % 16)
        poly1305_update(&st, zeros, 16 - (aadlen % 16));
    poly1305_update(&st, ct, ctlen);
    if (ctlen % 16)
        poly1305_update(&st, zeros, 16 - (ctlen % 16));
    wg_put_le64(lens, (uint64_t)aadlen);
    wg_put_le64(lens + 8, (uint64_t)ctlen);
    poly1305_update(&st, lens, 16);
    poly1305_finish(&st, tag);
    wg_memzero(lens, sizeof(lens));
}

/* 生成 ChaCha20 密钥流块（counter=0，取前 64 字节）作为 Poly1305 一次性密钥。
 * 注意：不能写 chacha20_xor(buf, buf, ...)（那要求 buf 已置零），必须先置零。 */
static void chacha20_keystream(uint8_t out[64], const uint8_t key[32], const uint8_t nonce[12], uint32_t counter)
{
    uint8_t zeros[64] = { 0 };
    chacha20_xor(out, zeros, sizeof(zeros), key, nonce, counter);
}

void chacha20poly1305_encrypt(uint8_t *out, const uint8_t *in, size_t inlen,
                              const uint8_t *aad, size_t aadlen,
                              const uint8_t key[32], const uint8_t nonce[12])
{
    uint8_t poly_key[64];

    chacha20_keystream(poly_key, key, nonce, 0);
    chacha20_xor(out, in, inlen, key, nonce, 1);
    aead_mac(out + inlen, poly_key, aad, aadlen, out, inlen);
    wg_memzero(poly_key, sizeof(poly_key));
}

bool chacha20poly1305_decrypt(uint8_t *out, const uint8_t *in, size_t inlen,
                              const uint8_t *aad, size_t aadlen,
                              const uint8_t key[32], const uint8_t nonce[12])
{
    if (inlen < 16)
        return false;
    size_t ctlen = inlen - 16;
    uint8_t poly_key[64];
    uint8_t tag[16];
    bool ok;

    chacha20_keystream(poly_key, key, nonce, 0);
    aead_mac(tag, poly_key, aad, aadlen, in, ctlen);
    ok = wg_ct_equal(tag, in + ctlen, 16);
    wg_memzero(tag, sizeof(tag));
    if (!ok) {
        wg_memzero(poly_key, sizeof(poly_key));
        return false;
    }
    chacha20_xor(out, in, ctlen, key, nonce, 1);
    wg_memzero(poly_key, sizeof(poly_key));
    return true;
}
