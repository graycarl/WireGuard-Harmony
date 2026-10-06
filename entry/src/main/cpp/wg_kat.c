/*
 * 密码原语 KAT 自检（决策 0002 §4：构建期/启动期用官方测试向量验证）。
 *
 * 向量来源：
 * - BLAKE2s：RFC 7693 Appendix B（空串 / "abc"）；keyed 向量由 Python hashlib.blake2s 生成。
 * - HMAC-BLAKE2s / KDF1/2/3：wireguard-go device/kdf_test.go 官方向量
 *   （key="test-key"/"wireguard"、input 同值），另加 32 字节 key 的向量覆盖生产路径。
 * - ChaCha20-Poly1305：RFC 8439 §2.8.2 AEAD 向量。
 * - X25519：RFC 7748 §5.2（两次标量乘）与 §6.1（DH 交换 + 公钥派生）。
 */
#include "wireguard.h"
#include "blake2s.h"
#include "chacha20poly1305.h"
#include "curve25519.h"

#include <string.h>

static uint8_t hexval(char c)
{
    if (c >= '0' && c <= '9')
        return (uint8_t)(c - '0');
    if (c >= 'a' && c <= 'f')
        return (uint8_t)(c - 'a' + 10);
    if (c >= 'A' && c <= 'F')
        return (uint8_t)(c - 'A' + 10);
    return 0xff;
}

/* 把十六进制串解码到 out（调用方保证容量足够）。返回 out 字节数，非法输入返回 -1。 */
static int unhex(const char *s, uint8_t *out)
{
    size_t n = strlen(s);
    if (n % 2 != 0)
        return -1;
    for (size_t i = 0; i < n / 2; i++) {
        uint8_t hi = hexval(s[2 * i]);
        uint8_t lo = hexval(s[2 * i + 1]);
        if (hi == 0xff || lo == 0xff)
            return -1;
        out[i] = (uint8_t)((hi << 4) | lo);
    }
    return (int)(n / 2);
}

static bool eq(const uint8_t *a, const uint8_t *b, size_t n)
{
    return wg_ct_equal(a, b, n);
}

/* 通用 KDF3（任意长度 key；用于核对官方短 key 向量），与 wireguard-go HMAC1/HMAC2 语义一致 */
static void kat_kdf3(uint8_t t0[32], uint8_t t1[32], uint8_t t2[32],
                     const uint8_t *key, size_t keylen, const uint8_t *input, size_t inlen)
{
    uint8_t prk[32];
    uint8_t buf[33];
    blake2s_hmac(prk, input, inlen, key, keylen, 32);
    blake2s_hmac(t0, (const uint8_t *)"\x01", 1, prk, 32, 32);
    memcpy(buf, t0, 32);
    buf[32] = 0x02;
    blake2s_hmac(t1, buf, 33, prk, 32, 32);
    memcpy(buf, t1, 32);
    buf[32] = 0x03;
    blake2s_hmac(t2, buf, 33, prk, 32, 32);
    wg_memzero(prk, sizeof(prk));
    wg_memzero(buf, sizeof(buf));
}

/* key 为 "test-key"（8B）input 为 "test-input"（10B）；期望来自 wireguard-go kdf_test.go */
static bool kat_kdf_official(void)
{
    uint8_t key[16], input[16], t0[32], t1[32], t2[32], exp0[32], exp1[32], exp2[32];
    int kl = unhex("746573742d6b6579", key);         /* "test-key" */
    int il = unhex("746573742d696e707574", input);   /* "test-input" */
    if (kl < 0 || il < 0)
        return false;
    (void)unhex("6f0e5ad38daba1bea8a0d213688736f19763239305e0f58aba697f9ffc41c633", exp0);
    (void)unhex("df1194df20802a4fe594cde27e92991c8cae66c366e8106aaa937a55fa371e8a", exp1);
    (void)unhex("fac6e2745a325f5dc5d11a5b165aad08b0ada28e7b4e666b7c077934a4d76c24", exp2);
    kat_kdf3(t0, t1, t2, key, (size_t)kl, input, (size_t)il);
    if (!eq(t0, exp0, 32) || !eq(t1, exp1, 32) || !eq(t2, exp2, 32))
        return false;

    /* 第二组官方向量："wireguard" x2 */
    uint8_t k2[16], i2[16];
    int k2l = unhex("776972656775617264", k2);
    int i2l = unhex("776972656775617264", i2);
    if (k2l < 0 || i2l < 0)
        return false;
    (void)unhex("491d43bbfdaa8750aaf535e334ecbfe5129967cd64635101c566d4caefda96e8", exp0);
    (void)unhex("1e71a379baefd8a79aa4662212fcafe19a23e2b609a3db7d6bcba8f560e3d25f", exp1);
    (void)unhex("31e1ae48bddfbe5de38f295e5452b1909a1b4e38e183926af3780b0c1e1f0160", exp2);
    kat_kdf3(t0, t1, t2, k2, (size_t)k2l, i2, (size_t)i2l);
    if (!eq(t0, exp0, 32) || !eq(t1, exp1, 32) || !eq(t2, exp2, 32))
        return false;

    /* 生产路径 wg_kdf1/2/3：32 字节 key 向量（Python hmac 生成，值随 RFC 2104 构造） */
    uint8_t key32[32], in32[32], k1[32], k2b[32], k3[32];
    (void)unhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", key32);
    (void)unhex("202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f", in32);
    (void)unhex("6a96444e20e8d4c1cee974416acae1c10b3c92886010e54ed94dafb2c3b80ea0", exp0);
    (void)unhex("57af120b0de7acbe7907ec149c5ae870a2dbb74232b65777ba4123f1f7f888f5", exp1);
    (void)unhex("0926c7caabb6e8d73beda759e6f4f0d324ce5b5000bcf8cd784b26db3049faa9", exp2);
    wg_kdf1(k1, key32, in32, 32);
    if (!eq(k1, exp0, 32))
        return false;
    wg_kdf2(k1, k2b, key32, in32, 32);
    if (!eq(k1, exp0, 32) || !eq(k2b, exp1, 32))
        return false;
    wg_kdf3(k1, k2b, k3, key32, in32, 32);
    if (!eq(k1, exp0, 32) || !eq(k2b, exp1, 32) || !eq(k3, exp2, 32))
        return false;
    return true;
}

static bool kat_blake2s(void)
{
    uint8_t out[32], exp[32];

    blake2s(out, NULL, 0, 32);
    (void)unhex("69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9", exp);
    if (!eq(out, exp, 32))
        return false;

    blake2s(out, (const uint8_t *)"abc", 3, 32);
    (void)unhex("508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982", exp);
    if (!eq(out, exp, 32))
        return false;

    /* keyed：key = 00..1f，msg = "WireGuard" */
    uint8_t key[32];
    (void)unhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", key);
    blake2s_keyed(out, (const uint8_t *)"WireGuard", 9, key, 32, 32);
    (void)unhex("a8e7bf141db6cdd64e401d49cb6eadd8837ed8da4dcf2e0cd23fdfe9850b8ded", exp);
    return eq(out, exp, 32);
}

static bool kat_chacha20poly1305(void)
{
    uint8_t key[32], nonce[12], aad[12], pt[114], exp[130], out[130], back[114];
    (void)unhex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f", key);
    (void)unhex("070000004041424344454647", nonce);
    (void)unhex("50515253c0c1c2c3c4c5c6c7", aad);
    int pl = unhex("4c616469657320616e642047656e746c656d656e206f662074686520636c6173"
                   "73206f66202739393a204966204920636f756c64206f6666657220796f75206f"
                   "6e6c79206f6e652074697020666f7220746865206675747572652c2073756e73"
                   "637265656e20776f756c642062652069742e",
                   pt);
    int el = unhex("d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6"
                   "3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36"
                   "92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc"
                   "3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd060"
                   "0691",
                   exp);
    if (pl != 114 || el != 130)
        return false;

    chacha20poly1305_encrypt(out, pt, (size_t)pl, aad, sizeof(aad), key, nonce);
    if (!eq(out, exp, (size_t)el))
        return false;
    /* 翻转一字节必须解密失败（tag 校验） */
    out[el - 1] ^= 1;
    if (chacha20poly1305_decrypt(back, out, (size_t)el, aad, sizeof(aad), key, nonce))
        return false;
    out[el - 1] ^= 1;
    if (!chacha20poly1305_decrypt(back, out, (size_t)el, aad, sizeof(aad), key, nonce))
        return false;
    return eq(back, pt, (size_t)pl);
}

static bool kat_x25519(void)
{
    uint8_t scalar[32], u[32], out[32], exp[32];

    /* RFC 7748 §5.2 向量 1 */
    (void)unhex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4", scalar);
    (void)unhex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c", u);
    (void)unhex("c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552", exp);
    curve25519(out, scalar, u);
    if (!eq(out, exp, 32))
        return false;

    /* RFC 7748 §5.2 向量 2 */
    (void)unhex("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d", scalar);
    (void)unhex("e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493", u);
    (void)unhex("95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957", exp);
    curve25519(out, scalar, u);
    if (!eq(out, exp, 32))
        return false;

    /* RFC 7748 §6.1 DH 交换 */
    uint8_t a_priv[32], b_priv[32], a_pub[32], b_pub[32], a_shared[32], b_shared[32];
    (void)unhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a", a_priv);
    (void)unhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb", b_priv);
    (void)unhex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", exp);
    curve25519_base(a_pub, a_priv);
    if (!eq(a_pub, exp, 32))
        return false;
    (void)unhex("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f", exp);
    curve25519_base(b_pub, b_priv);
    if (!eq(b_pub, exp, 32))
        return false;
    (void)unhex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742", exp);
    curve25519(a_shared, a_priv, b_pub);
    curve25519(b_shared, b_priv, a_pub);
    if (!eq(a_shared, exp, 32) || !eq(b_shared, exp, 32))
        return false;

    return true;
}

bool wg_kat_selftest(void)
{
    if (!kat_blake2s()) {
        WG_LOGE("KAT failed: blake2s");
        return false;
    }
    if (!kat_kdf_official()) {
        WG_LOGE("KAT failed: hmac/kdf");
        return false;
    }
    if (!kat_chacha20poly1305()) {
        WG_LOGE("KAT failed: chacha20poly1305");
        return false;
    }
    if (!kat_x25519()) {
        WG_LOGE("KAT failed: x25519");
        return false;
    }
    WG_LOGI("KAT selftest passed");
    return true;
}
