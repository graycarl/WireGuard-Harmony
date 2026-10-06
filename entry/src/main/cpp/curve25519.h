/*
 * X25519（RFC 7748）。
 * 移植自 TweetNaCl（public domain，Daniel J. Bernstein 等）的 crypto_scalarmult，
 * 仅保留 Montgomery ladder（X25519），去掉 Ed25519 相关部分。
 */
#ifndef WG_CURVE25519_H
#define WG_CURVE25519_H
#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

#define CURVE25519_KEY_SIZE 32

/* q = n * p（Montgomery ladder）。n 为标量（内部做 clamp），p 为 u 坐标。 */
void curve25519(uint8_t q[32], const uint8_t n[32], const uint8_t p[32]);
/* q = n * basepoint（生成公钥） */
void curve25519_base(uint8_t q[32], const uint8_t n[32]);

#ifdef __cplusplus
}
#endif
#endif /* WG_CURVE25519_H */
