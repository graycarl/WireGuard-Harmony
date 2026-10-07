/*
 * BLAKE2s（RFC 7693）参考实现，含 keyed 模式（keyed BLAKE2s 即 WireGuard 的 HMAC 角色）。
 * 移植自 RFC 7693 Appendix A 参考实现（CC0 / public domain，原作者 Samuel Neves 等），
 * 裁剪为流式三件套 init/update/final + 便捷一次性接口。
 */
#ifndef WG_BLAKE2S_H
#define WG_BLAKE2S_H
#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

#define BLAKE2S_OUTLEN 32
#define BLAKE2S_KEYLEN 32
#define BLAKE2S_BLOCKLEN 64

typedef struct {
    uint32_t h[8];
    uint32_t t[2];
    uint32_t f[2];
    uint8_t buf[BLAKE2S_BLOCKLEN];
    size_t buflen;
    size_t outlen;
} blake2s_state;

int blake2s_init(blake2s_state *S, size_t outlen);
int blake2s_init_key(blake2s_state *S, size_t outlen, const uint8_t *key, size_t keylen);
int blake2s_update(blake2s_state *S, const uint8_t *in, size_t inlen);
int blake2s_final(blake2s_state *S, uint8_t *out);

/* 一次性哈希 */
void blake2s(uint8_t *out, const uint8_t *in, size_t inlen, size_t outlen);
/* keyed 一次性哈希（WireGuard 的 MAC1/MAC2 语义：MAC(key, input) = keyed BLAKE2s） */
void blake2s_keyed(uint8_t *out, const uint8_t *in, size_t inlen,
                   const uint8_t *key, size_t keylen, size_t outlen);

/* HMAC-BLAKE2s（RFC 2104 ipad/opad，BLAKE2s 为哈希函数、块长 64）。
 * 注意：WireGuard 的 KDF/HKDF 用的是 **HMAC-BLAKE2s**，不是 keyed BLAKE2s
 * （见 wireguard-go device/noise-helpers.go：HMAC1/HMAC2 用 crypto/hmac 包装 blake2s）。
 * out 输出 32 字节。 */
void blake2s_hmac(uint8_t *out, const uint8_t *in, size_t inlen,
                  const uint8_t *key, size_t keylen, size_t outlen);

/* WireGuard kdf：prk = HMAC(ck, input)；T1 = HMAC(prk, 0x01)；
 * T2 = HMAC(prk, T1||0x02)；T3 = HMAC(prk, T2||0x03)。对应上游 kernel blake2s_hmac / noise.c kdf()。 */
void wg_kdf1(uint8_t t1[32], const uint8_t ck[32], const uint8_t *input, size_t input_len);
void wg_kdf2(uint8_t t1[32], uint8_t t2[32], const uint8_t ck[32], const uint8_t *input, size_t input_len);
void wg_kdf3(uint8_t t1[32], uint8_t t2[32], uint8_t t3[32], const uint8_t ck[32],
             const uint8_t *input, size_t input_len);

#ifdef __cplusplus
}
#endif
#endif /* WG_BLAKE2S_H */
