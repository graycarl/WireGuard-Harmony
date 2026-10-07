/*
 * ChaCha20-Poly1305 AEAD（RFC 8439，96-bit nonce）。
 * ChaCha20 移植自 RFC 8439 参考实现（public domain）；
 * Poly1305 移植自 poly1305-donna（Andrew Moon，public domain / MIT，32 位版本）。
 * WireGuard 传输消息 nonce 构造：4 字节 0 || 64-bit LE 计数器。
 */
#ifndef WG_CHACHA20POLY1305_H
#define WG_CHACHA20POLY1305_H
#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

void chacha20_xor(uint8_t *out, const uint8_t *in, size_t inlen,
                  const uint8_t key[32], const uint8_t nonce[12], uint32_t counter);

void poly1305_auth(uint8_t tag[16], const uint8_t *in, size_t inlen, const uint8_t key[32]);

/* AEAD 加密：out 长度 = inlen + 16（密文||tag）。in/out 可重叠（out==in）。 */
void chacha20poly1305_encrypt(uint8_t *out, const uint8_t *in, size_t inlen,
                              const uint8_t *aad, size_t aadlen,
                              const uint8_t key[32], const uint8_t nonce[12]);

/* AEAD 解密并校验 tag：成功返回 true 且 out 为明文（长度 inlen-16），失败返回 false（out 不写）。 */
bool chacha20poly1305_decrypt(uint8_t *out, const uint8_t *in, size_t inlen,
                              const uint8_t *aad, size_t aadlen,
                              const uint8_t key[32], const uint8_t nonce[12]);

#ifdef __cplusplus
}
#endif
#endif /* WG_CHACHA20POLY1305_H */
