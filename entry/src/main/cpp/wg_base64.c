#include "wg_base64.h"

static int b64_val(char c)
{
    if (c >= 'A' && c <= 'Z')
        return c - 'A';
    if (c >= 'a' && c <= 'z')
        return c - 'a' + 26;
    if (c >= '0' && c <= '9')
        return c - '0' + 52;
    if (c == '+')
        return 62;
    if (c == '/')
        return 63;
    return -1;
}

bool wg_b64_decode(uint8_t *out, size_t *out_len, const char *in, size_t inlen)
{
    if (inlen == 0 || inlen % 4 != 0)
        return false;
    size_t o = 0;
    for (size_t i = 0; i < inlen; i += 4) {
        int v0 = b64_val(in[i]);
        int v1 = b64_val(in[i + 1]);
        int v2 = in[i + 2] == '=' ? -2 : b64_val(in[i + 2]);
        int v3 = in[i + 3] == '=' ? -2 : b64_val(in[i + 3]);
        bool last = (i + 4 == inlen);

        if (v0 < 0 || v1 < 0 || v2 == -1 || v3 == -1)
            return false;
        if ((v2 == -2 || v3 == -2) && !last)
            return false; /* padding 只允许在末尾 */
        if (v2 == -2 && v3 != -2)
            return false;
        if (v2 == -2 && v3 == -2) {
            out[o++] = (uint8_t)((v0 << 2) | (v1 >> 4));
            if ((v1 & 0x0f) != 0)
                return false; /* 非规范 padding 位 */
            break;
        }
        if (v3 == -2) {
            out[o++] = (uint8_t)((v0 << 2) | (v1 >> 4));
            out[o++] = (uint8_t)((v1 << 4) | (v2 >> 2));
            if ((v2 & 0x03) != 0)
                return false;
            break;
        }
        out[o++] = (uint8_t)((v0 << 2) | (v1 >> 4));
        out[o++] = (uint8_t)((v1 << 4) | (v2 >> 2));
        out[o++] = (uint8_t)((v2 << 6) | v3);
    }
    *out_len = o;
    return true;
}

void wg_b64_encode(char *out, const uint8_t *in, size_t inlen)
{
    static const char tbl[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t o = 0;
    size_t i = 0;
    while (i + 3 <= inlen) {
        uint32_t v = ((uint32_t)in[i] << 16) | ((uint32_t)in[i + 1] << 8) | in[i + 2];
        out[o++] = tbl[(v >> 18) & 63];
        out[o++] = tbl[(v >> 12) & 63];
        out[o++] = tbl[(v >> 6) & 63];
        out[o++] = tbl[v & 63];
        i += 3;
    }
    if (i < inlen) {
        uint32_t v = (uint32_t)in[i] << 16;
        bool two = (i + 1 < inlen);
        if (two)
            v |= (uint32_t)in[i + 1] << 8;
        out[o++] = tbl[(v >> 18) & 63];
        out[o++] = tbl[(v >> 12) & 63];
        out[o++] = two ? tbl[(v >> 6) & 63] : '=';
        out[o++] = '=';
    }
    out[o] = '\0';
}
