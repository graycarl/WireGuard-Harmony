/*
 * BLAKE2s（RFC 7693）参考实现。
 * 移植自 RFC 7693 Appendix A（CC0 / public domain, Samuel Neves <sneves@dei.uc.pt>）。
 */
#include "blake2s.h"
#include "wg_log.h"

#include <string.h>

static const uint32_t blake2s_iv[8] = {
    0x6A09E667UL, 0xBB67AE85UL, 0x3C6EF372UL, 0xA54FF53AUL,
    0x510E527FUL, 0x9B05688CUL, 0x1F83D9ABUL, 0x5BE0CD19UL
};

static const uint8_t blake2s_sigma[10][16] = {
    {  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15 },
    { 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3 },
    { 11,  8, 12,  0,  5,  2, 15, 13, 10, 14,  3,  6,  7,  1,  9,  4 },
    {  7,  9,  3,  1, 13, 12, 11, 14,  2,  6,  5, 10,  4,  0, 15,  8 },
    {  9,  0,  5,  7,  2,  4, 10, 15, 14,  1, 11, 12,  6,  8,  3, 13 },
    {  2, 12,  6, 10,  0, 11,  8,  3,  4, 13,  7,  5, 15, 14,  1,  9 },
    { 12,  5,  1, 15, 14, 13,  4, 10,  0,  7,  6,  3,  9,  2,  8, 11 },
    { 13, 11,  7, 14, 12,  1,  3,  9,  5,  0, 15,  4,  8,  6,  2, 10 },
    {  6, 15, 14,  9, 11,  3,  0,  8, 12,  2, 13,  7,  1,  4, 10,  5 },
    { 10,  2,  8,  4,  7,  6,  1,  5, 15, 11,  9, 14,  3, 12, 13,  0 },
};

static uint32_t load32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void store32(uint8_t *p, uint32_t w)
{
    p[0] = (uint8_t)w;
    p[1] = (uint8_t)(w >> 8);
    p[2] = (uint8_t)(w >> 16);
    p[3] = (uint8_t)(w >> 24);
}

static uint32_t rotr32(uint32_t w, unsigned c)
{
    return (w >> c) | (w << (32 - c));
}

#define G(r, i, a, b, c, d)                                                     \
    do {                                                                        \
        a = a + b + m[blake2s_sigma[r][2 * (i) + 0]];                           \
        d = rotr32(d ^ a, 16);                                                  \
        c = c + d;                                                              \
        b = rotr32(b ^ c, 12);                                                  \
        a = a + b + m[blake2s_sigma[r][2 * (i) + 1]];                           \
        d = rotr32(d ^ a, 8);                                                   \
        c = c + d;                                                              \
        b = rotr32(b ^ c, 7);                                                   \
    } while (0)

#define ROUND(r)                                                                \
    do {                                                                        \
        G(r, 0, v[0], v[4], v[8], v[12]);                                       \
        G(r, 1, v[1], v[5], v[9], v[13]);                                       \
        G(r, 2, v[2], v[6], v[10], v[14]);                                      \
        G(r, 3, v[3], v[7], v[11], v[15]);                                      \
        G(r, 4, v[0], v[5], v[10], v[15]);                                      \
        G(r, 5, v[1], v[6], v[11], v[12]);                                      \
        G(r, 6, v[2], v[7], v[8], v[13]);                                       \
        G(r, 7, v[3], v[4], v[9], v[14]);                                       \
    } while (0)

static void blake2s_compress(blake2s_state *S, const uint8_t in[BLAKE2S_BLOCKLEN])
{
    uint32_t m[16];
    uint32_t v[16];

    for (size_t i = 0; i < 16; i++)
        m[i] = load32(in + i * 4);
    for (size_t i = 0; i < 8; i++)
        v[i] = S->h[i];
    v[8] = blake2s_iv[0];
    v[9] = blake2s_iv[1];
    v[10] = blake2s_iv[2];
    v[11] = blake2s_iv[3];
    v[12] = blake2s_iv[4] ^ S->t[0];
    v[13] = blake2s_iv[5] ^ S->t[1];
    v[14] = blake2s_iv[6] ^ S->f[0];
    v[15] = blake2s_iv[7] ^ S->f[1];

    for (unsigned r = 0; r < 10; r++)
        ROUND(r);

    for (size_t i = 0; i < 8; i++)
        S->h[i] ^= v[i] ^ v[i + 8];
}

static int blake2s_set_lastblock(blake2s_state *S)
{
    S->f[0] = (uint32_t)-1;
    return 0;
}

static int blake2s_increment_counter(blake2s_state *S, uint32_t inc)
{
    S->t[0] += inc;
    S->t[1] += (S->t[0] < inc);
    return 0;
}

static int blake2s_init0(blake2s_state *S, size_t outlen)
{
    memset(S, 0, sizeof(*S));
    for (size_t i = 0; i < 8; i++)
        S->h[i] = blake2s_iv[i];
    /* 参数块：digest_length | key_length | fanout=1 | depth=1 */
    S->h[0] ^= 0x01010000u ^ ((uint32_t)outlen);
    S->outlen = outlen;
    return 0;
}

int blake2s_init(blake2s_state *S, size_t outlen)
{
    if (!outlen || outlen > BLAKE2S_OUTLEN)
        return -1;
    return blake2s_init0(S, outlen);
}

int blake2s_init_key(blake2s_state *S, size_t outlen, const uint8_t *key, size_t keylen)
{
    uint8_t block[BLAKE2S_BLOCKLEN];

    if (!outlen || outlen > BLAKE2S_OUTLEN || !key || !keylen || keylen > BLAKE2S_KEYLEN)
        return -1;
    blake2s_init0(S, outlen);
    S->h[0] ^= (uint32_t)keylen << 8;
    memset(block, 0, BLAKE2S_BLOCKLEN);
    memcpy(block, key, keylen);
    blake2s_update(S, block, BLAKE2S_BLOCKLEN);
    wg_memzero(block, sizeof(block));
    return 0;
}

int blake2s_update(blake2s_state *S, const uint8_t *in, size_t inlen)
{
    if (!in || inlen == 0)
        return 0;
    size_t left = S->buflen;
    size_t fill = BLAKE2S_BLOCKLEN - left;
    if (inlen > fill) {
        S->buflen = 0;
        memcpy(S->buf + left, in, fill);
        blake2s_increment_counter(S, BLAKE2S_BLOCKLEN);
        blake2s_compress(S, S->buf);
        in += fill;
        inlen -= fill;
        while (inlen > BLAKE2S_BLOCKLEN) {
            blake2s_increment_counter(S, BLAKE2S_BLOCKLEN);
            blake2s_compress(S, in);
            in += BLAKE2S_BLOCKLEN;
            inlen -= BLAKE2S_BLOCKLEN;
        }
    }
    memcpy(S->buf + S->buflen, in, inlen);
    S->buflen += inlen;
    return 0;
}

int blake2s_final(blake2s_state *S, uint8_t *out)
{
    uint8_t buffer[BLAKE2S_OUTLEN] = { 0 };
    size_t outlen = S->outlen;

    blake2s_increment_counter(S, (uint32_t)S->buflen);
    blake2s_set_lastblock(S);
    memset(S->buf + S->buflen, 0, BLAKE2S_BLOCKLEN - S->buflen);
    blake2s_compress(S, S->buf);
    for (size_t i = 0; i < 8; i++)
        store32(buffer + 4 * i, S->h[i]);
    memcpy(out, buffer, outlen);
    wg_memzero(buffer, sizeof(buffer));
    return 0;
}

void blake2s(uint8_t *out, const uint8_t *in, size_t inlen, size_t outlen)
{
    blake2s_state S;
    blake2s_init(&S, outlen);
    blake2s_update(&S, in, inlen);
    blake2s_final(&S, out);
}

void blake2s_keyed(uint8_t *out, const uint8_t *in, size_t inlen,
                   const uint8_t *key, size_t keylen, size_t outlen)
{
    blake2s_state S;
    blake2s_init_key(&S, outlen, key, keylen);
    blake2s_update(&S, in, inlen);
    blake2s_final(&S, out);
}

/* HMAC-BLAKE2s（RFC 2104）：K' = pad/H(key)；内层 H(K'^ipad || msg)；外层 H(K'^opad || inner)。
 * WireGuard 的 KDF 用的是它（不是 keyed BLAKE2s），必须严格对齐。 */
void blake2s_hmac(uint8_t *out, const uint8_t *in, size_t inlen,
                  const uint8_t *key, size_t keylen, size_t outlen)
{
    uint8_t x_key[BLAKE2S_BLOCKLEN];
    uint8_t inner[BLAKE2S_OUTLEN];
    uint8_t full[BLAKE2S_OUTLEN];
    blake2s_state S;

    memset(x_key, 0, sizeof(x_key));
    if (keylen > BLAKE2S_BLOCKLEN)
        blake2s(x_key, key, keylen, BLAKE2S_OUTLEN);
    else if (keylen)
        memcpy(x_key, key, keylen);

    for (size_t i = 0; i < BLAKE2S_BLOCKLEN; i++)
        x_key[i] ^= 0x36;
    blake2s_init(&S, BLAKE2S_OUTLEN);
    blake2s_update(&S, x_key, BLAKE2S_BLOCKLEN);
    blake2s_update(&S, in, inlen);
    blake2s_final(&S, inner);

    for (size_t i = 0; i < BLAKE2S_BLOCKLEN; i++)
        x_key[i] ^= 0x5c ^ 0x36;
    blake2s_init(&S, BLAKE2S_OUTLEN);
    blake2s_update(&S, x_key, BLAKE2S_BLOCKLEN);
    blake2s_update(&S, inner, BLAKE2S_OUTLEN);
    blake2s_final(&S, full);

    memcpy(out, full, outlen <= BLAKE2S_OUTLEN ? outlen : BLAKE2S_OUTLEN);
    wg_memzero(x_key, sizeof(x_key));
    wg_memzero(inner, sizeof(inner));
    wg_memzero(full, sizeof(full));
}

static void kdf_expand(uint8_t *dst, size_t dst_len, const uint8_t secret[32],
                       const uint8_t *prev, size_t prev_len, uint8_t suffix)
{
    uint8_t buf[BLAKE2S_OUTLEN + 1];
    uint8_t full[BLAKE2S_OUTLEN];
    if (prev_len)
        memcpy(buf, prev, prev_len);
    buf[prev_len] = suffix;
    blake2s_hmac(full, buf, prev_len + 1, secret, 32, BLAKE2S_OUTLEN);
    memcpy(dst, full, dst_len <= BLAKE2S_OUTLEN ? dst_len : BLAKE2S_OUTLEN);
    wg_memzero(full, sizeof(full));
    wg_memzero(buf, sizeof(buf));
}

void wg_kdf1(uint8_t t1[32], const uint8_t ck[32], const uint8_t *input, size_t input_len)
{
    uint8_t secret[32];
    blake2s_hmac(secret, input, input_len, ck, 32, 32);
    kdf_expand(t1, 32, secret, NULL, 0, 1);
    wg_memzero(secret, sizeof(secret));
}

void wg_kdf2(uint8_t t1[32], uint8_t t2[32], const uint8_t ck[32], const uint8_t *input, size_t input_len)
{
    uint8_t secret[32];
    blake2s_hmac(secret, input, input_len, ck, 32, 32);
    kdf_expand(t1, 32, secret, NULL, 0, 1);
    kdf_expand(t2, 32, secret, t1, 32, 2);
    wg_memzero(secret, sizeof(secret));
}

void wg_kdf3(uint8_t t1[32], uint8_t t2[32], uint8_t t3[32], const uint8_t ck[32],
             const uint8_t *input, size_t input_len)
{
    uint8_t secret[32];
    blake2s_hmac(secret, input, input_len, ck, 32, 32);
    kdf_expand(t1, 32, secret, NULL, 0, 1);
    kdf_expand(t2, 32, secret, t1, 32, 2);
    kdf_expand(t3, 32, secret, t2, 32, 3);
    wg_memzero(secret, sizeof(secret));
}
