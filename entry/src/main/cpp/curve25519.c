/*
 * X25519（RFC 7748）。
 * 移植自 TweetNaCl（public domain, Bernstein / van Gastel / Janssen / Lange / Schwabe / Smetsers）
 * crypto_scalarmult 核心，只保留 X25519 ladder。
 */
#include "curve25519.h"
#include "wg_log.h"

typedef int64_t i64;
typedef i64 gf[16];

static const gf gf_121665 = { 0xDB41, 1 };

/* 进位归一化（TweetNaCl car25519） */
static void car25519(gf o)
{
    for (int i = 0; i < 16; i++) {
        i64 c;
        o[i] += (1LL << 16);
        c = o[i] >> 16;
        o[(i + 1) * (i < 15)] += c - 1 + 37 * (c - 1) * (i == 15);
        o[i] -= c * 65536; /* 用乘法代替 c<<16：避免负值左移的 UB，语义等价 */
    }
}

static void sel25519(gf p, gf q, int b)
{
    i64 c = ~(b - 1);
    for (int i = 0; i < 16; i++) {
        i64 t = c & (p[i] ^ q[i]);
        p[i] ^= t;
        q[i] ^= t;
    }
}

static void pack25519(uint8_t *o, const gf n)
{
    gf t, m;
    int b = 0;

    for (int i = 0; i < 16; i++)
        t[i] = n[i];
    car25519(t);
    car25519(t);
    car25519(t);
    for (int j = 0; j < 2; j++) {
        m[0] = t[0] - 0xffed;
        for (int i = 1; i < 15; i++) {
            m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1);
            m[i - 1] &= 0xffff;
        }
        m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1);
        b = (int)((m[15] >> 16) & 1);
        m[14] &= 0xffff;
        sel25519(t, m, 1 - b);
    }
    for (int i = 0; i < 16; i++) {
        o[2 * i] = (uint8_t)(t[i] & 0xff);
        o[2 * i + 1] = (uint8_t)(t[i] >> 8);
    }
    wg_memzero(t, sizeof(t));
    wg_memzero(m, sizeof(m));
}

static void unpack25519(gf o, const uint8_t *n)
{
    for (int i = 0; i < 16; i++)
        o[i] = n[2 * i] + ((i64)n[2 * i + 1] << 8);
    o[15] &= 0x7fff; /* RFC 7748：收到的 u 坐标最高位必须屏蔽 */
}

static void gf_add(gf o, const gf a, const gf b)
{
    for (int i = 0; i < 16; i++)
        o[i] = a[i] + b[i];
}

static void gf_sub(gf o, const gf a, const gf b)
{
    for (int i = 0; i < 16; i++)
        o[i] = a[i] - b[i];
}

static void gf_mul(gf o, const gf a, const gf b)
{
    i64 t[31];
    for (int i = 0; i < 31; i++)
        t[i] = 0;
    for (int i = 0; i < 16; i++)
        for (int j = 0; j < 16; j++)
            t[i + j] += a[i] * b[j];
    for (int i = 0; i < 15; i++)
        t[i] += 38 * t[i + 16];
    for (int i = 0; i < 16; i++)
        o[i] = t[i];
    car25519(o);
    car25519(o);
    wg_memzero(t, sizeof(t));
}

static void gf_sqr(gf o, const gf a)
{
    gf_mul(o, a, a);
}

static void gf_inv(gf o, const gf in)
{
    gf c;
    for (int i = 0; i < 16; i++)
        c[i] = in[i];
    for (int a = 253; a >= 0; a--) {
        gf_sqr(c, c);
        if (a != 2 && a != 4)
            gf_mul(c, c, in);
    }
    for (int i = 0; i < 16; i++)
        o[i] = c[i];
    wg_memzero(c, sizeof(c));
}

void curve25519(uint8_t q[32], const uint8_t n[32], const uint8_t p[32])
{
    uint8_t z[32];
    gf x, a, b, c, d, e, f;

    for (int i = 0; i < 31; i++)
        z[i] = n[i];
    z[31] = (uint8_t)((n[31] & 127) | 64);
    z[0] &= 248;

    unpack25519(x, p);
    for (int i = 0; i < 16; i++) {
        b[i] = x[i];
        a[i] = c[i] = d[i] = 0;
    }
    a[0] = d[0] = 1;

    for (int i = 254; i >= 0; --i) {
        int r = (z[i >> 3] >> (i & 7)) & 1;
        sel25519(a, b, r);
        sel25519(c, d, r);
        gf_add(e, a, c);
        gf_sub(a, a, c);
        gf_add(c, b, d);
        gf_sub(b, b, d);
        gf_sqr(d, e);
        gf_sqr(f, a);
        gf_mul(a, c, a);
        gf_mul(c, b, e);
        gf_add(e, a, c);
        gf_sub(a, a, c);
        gf_sqr(b, a);
        gf_sub(c, d, f);
        gf_mul(a, c, gf_121665);
        gf_add(a, a, d);
        gf_mul(c, c, a);
        gf_mul(a, d, f);
        gf_mul(d, b, x);
        gf_sqr(b, e);
        sel25519(a, b, r);
        sel25519(c, d, r);
    }
    gf_inv(c, c);
    gf_mul(a, a, c);
    pack25519(q, a);

    wg_memzero(z, sizeof(z));
    wg_memzero(x, sizeof(x));
    wg_memzero(a, sizeof(a));
    wg_memzero(b, sizeof(b));
    wg_memzero(c, sizeof(c));
    wg_memzero(d, sizeof(d));
    wg_memzero(e, sizeof(e));
    wg_memzero(f, sizeof(f));
}

void curve25519_base(uint8_t q[32], const uint8_t n[32])
{
    static const uint8_t basepoint[32] = { 9 };
    curve25519(q, n, basepoint);
}
