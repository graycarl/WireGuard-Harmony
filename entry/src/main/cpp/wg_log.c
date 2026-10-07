#include "wg_log.h"

#include <string.h>
#include <time.h>

#if defined(__APPLE__)
#include <stdlib.h> /* arc4random_buf */
#else
#include <fcntl.h>
#include <unistd.h>
#endif

static volatile uint8_t wg_zero_sink;

void wg_memzero(void *p, size_t n)
{
    volatile uint8_t *vp = (volatile uint8_t *)p;
    while (n--)
        *vp++ = 0;
    wg_zero_sink = 0;
    (void)wg_zero_sink;
}

uint32_t wg_le32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

uint64_t wg_le64(const uint8_t *p)
{
    return (uint64_t)wg_le32(p) | ((uint64_t)wg_le32(p + 4) << 32);
}

void wg_put_le32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

void wg_put_le64(uint8_t *p, uint64_t v)
{
    wg_put_le32(p, (uint32_t)v);
    wg_put_le32(p + 4, (uint32_t)(v >> 32));
}

bool wg_random(uint8_t *out, size_t n)
{
#if defined(__APPLE__)
    arc4random_buf(out, n);
    return true;
#else
    /* OHOS / Linux：读 /dev/urandom（getrandom 封装在 NDK 各 API level 不一致，urandom 足够） */
    int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return false;
    size_t off = 0;
    while (off < n) {
        ssize_t r = read(fd, out + off, n - off);
        if (r <= 0) {
            close(fd);
            return false;
        }
        off += (size_t)r;
    }
    close(fd);
    return true;
#endif
}

double wg_now_mono(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

uint64_t wg_now_realtime_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)ts.tv_nsec / 1000000ULL;
}

bool wg_ct_equal(const uint8_t *a, const uint8_t *b, size_t n)
{
    uint8_t d = 0;
    for (size_t i = 0; i < n; i++)
        d |= (uint8_t)(a[i] ^ b[i]);
    return d == 0;
}

/* 测试注入点：仅 hosttest 使用（可复现握手）；生产环境保持 NULL。 */
bool (*wg_ephemeral_hook)(uint8_t out[32]) = NULL;

bool wg_ephemeral_key(uint8_t out[32])
{
    if (wg_ephemeral_hook)
        return wg_ephemeral_hook(out);
    return wg_random(out, 32);
}
