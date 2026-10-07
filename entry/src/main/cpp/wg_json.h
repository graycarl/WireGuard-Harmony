/*
 * 极简 JSON 解析（jsmn 风格 token 流，零动态分配）。
 * 只用于解析结构固定的 configJson（契约 §8）：对象/数组/字符串/数字/true/false/null。
 * 算法参照 jsmn（MIT, Serge Zaitsev），按本项目需要重写。
 */
#ifndef WG_JSON_H
#define WG_JSON_H
#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdbool.h>

typedef enum {
    WG_J_UNDEFINED = 0,
    WG_J_OBJECT,
    WG_J_ARRAY,
    WG_J_STRING,
    WG_J_PRIMITIVE /* 数字/true/false/null */
} wg_jtype;

typedef struct {
    wg_jtype type;
    int start; /* 字符串/原始值在原文中的起止（对象/数组为 -1） */
    int end;
    int size;  /* 直接子元素数（对象按 key 计，每个 key 跟随其 value） */
    int parent;
} wg_jtoken;

/* 解析：tokens 容量不足返回需要的数量（>0）；语法错误返回 <0；成功返回 0。 */
int wg_json_parse(const char *js, size_t len, wg_jtoken *tokens, int num_tokens);

/* 在 object token 中按键找 value token 下标（未找到返回 -1）。 */
int wg_json_object_get(const char *js, const wg_jtoken *tokens, int ntok, int obj, const char *key);
/* token → 字符串（含基本转义处理）；out_cap 含 NUL。返回 false=容量不足/类型不符。 */
bool wg_json_string(const char *js, const wg_jtoken *tok, char *out, size_t out_cap);
/* token → long（PRIMITIVE 数字）。 */
bool wg_json_long(const char *js, const wg_jtoken *tok, long *out);

#ifdef __cplusplus
}
#endif
#endif /* WG_JSON_H */
