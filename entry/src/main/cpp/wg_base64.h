/* base64 编解码（标准字符集，带 padding；密钥场景固定 32 字节 ↔ 44 字符）。 */
#ifndef WG_BASE64_H
#define WG_BASE64_H
#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/* 解码：非法字符/长度返回 false；out 容量需 >= (inlen/4)*3。返回实际长度于 out_len。 */
bool wg_b64_decode(uint8_t *out, size_t *out_len, const char *in, size_t inlen);
/* 编码：out 容量需 >= 4*((inlen+2)/3)+1；输出 NUL 结尾。 */
void wg_b64_encode(char *out, const uint8_t *in, size_t inlen);

#ifdef __cplusplus
}
#endif
#endif /* WG_BASE64_H */
