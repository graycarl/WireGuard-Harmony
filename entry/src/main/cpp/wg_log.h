/*
 * 平台隔离层：日志与基础可移植工具。
 * OHOS 用 hilog；主机侧测试用 stderr。其余代码只准用本头文件的宏/函数。
 */
#ifndef WG_LOG_H
#define WG_LOG_H
#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __OHOS__
#include <hilog/log.h>
#define WG_LOGI(...) OH_LOG_INFO(LOG_APP, __VA_ARGS__)
#define WG_LOGE(...) OH_LOG_ERROR(LOG_APP, __VA_ARGS__)
#define WG_LOGD(...) OH_LOG_DEBUG(LOG_APP, __VA_ARGS__)
#else
#include <stdio.h>
#define WG_LOGI(...) do { fprintf(stderr, "[I] " __VA_ARGS__); fputc('\n', stderr); } while (0)
#define WG_LOGE(...) do { fprintf(stderr, "[E] " __VA_ARGS__); fputc('\n', stderr); } while (0)
#define WG_LOGD(...) do { fprintf(stderr, "[D] " __VA_ARGS__); fputc('\n', stderr); } while (0)
#endif

/* ---- 显式清零（防编译器优化掉密钥擦除） ---- */
void wg_memzero(void *p, size_t n);

/* ---- 小端编码/解码（协议全部 LE 字段） ---- */
uint32_t wg_le32(const uint8_t *p);
uint64_t wg_le64(const uint8_t *p);
void wg_put_le32(uint8_t *p, uint32_t v);
void wg_put_le64(uint8_t *p, uint64_t v);

/* ---- 随机数 ---- */
bool wg_random(uint8_t *out, size_t n);
/* 握手临时密钥（可注入用于可复现测试；未设置 hook 时用平台随机） */
bool wg_ephemeral_key(uint8_t out[32]);
extern bool (*wg_ephemeral_hook)(uint8_t out[32]);

/* ---- 时间：单调秒（定时器用）与实时 epoch 毫秒（统计/ Tai64N 用） ---- */
double wg_now_mono(void);
uint64_t wg_now_realtime_ms(void);

/* ---- 常量时间比较 ---- */
bool wg_ct_equal(const uint8_t *a, const uint8_t *b, size_t n);

#ifdef __cplusplus
}
#endif
#endif /* WG_LOG_H */
