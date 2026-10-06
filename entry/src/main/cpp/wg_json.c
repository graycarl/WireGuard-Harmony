#include "wg_json.h"

#include <string.h>

typedef struct {
    const char *js;
    size_t len;
    size_t pos;
    int toknext;
    int toksuper; /* 当前容器 token 下标，-1 = 顶层 */
    wg_jtoken *tokens;
    int num_tokens;
} wg_jparser;

static int jalloc(wg_jparser *p)
{
    if (p->toknext >= p->num_tokens)
        return -1;
    wg_jtoken *t = &p->tokens[p->toknext];
    t->type = WG_J_UNDEFINED;
    t->start = t->end = -1;
    t->size = 0;
    t->parent = p->toksuper;
    return p->toknext++;
}

static void jfill(wg_jparser *p, int i, wg_jtype type, int start, int end)
{
    wg_jtoken *t = &p->tokens[i];
    t->type = type;
    t->start = start;
    t->end = end;
    t->size = 0;
}

static int jparse_primitive(wg_jparser *p)
{
    size_t start = p->pos;
    int ti;
    while (p->pos < p->len) {
        char c = p->js[p->pos];
        if (c == ',' || c == '}' || c == ']' || c == ' ' || c == '\t' || c == '\n' || c == '\r')
            break;
        if ((unsigned char)c < 32 || c == ':')
            return -1;
        p->pos++;
    }
    ti = jalloc(p);
    if (ti < 0)
        return -2;
    jfill(p, ti, WG_J_PRIMITIVE, (int)start, (int)p->pos);
    if (p->toksuper >= 0)
        p->tokens[p->toksuper].size++;
    return 0;
}

static int jparse_string(wg_jparser *p)
{
    size_t start = p->pos;
    int ti;
    p->pos++; /* 跳过引号 */
    while (p->pos < p->len) {
        char c = p->js[p->pos];
        if (c == '"') {
            ti = jalloc(p);
            if (ti < 0)
                return -2;
            jfill(p, ti, WG_J_STRING, (int)start + 1, (int)p->pos);
            p->pos++;
            if (p->toksuper >= 0)
                p->tokens[p->toksuper].size++;
            return 0;
        }
        if (c == '\\') {
            p->pos++;
            if (p->pos >= p->len)
                return -1;
        }
        p->pos++;
    }
    return -1;
}

int wg_json_parse(const char *js, size_t len, wg_jtoken *tokens, int num_tokens)
{
    wg_jparser p;
    int count = 0;

    p.js = js;
    p.len = len;
    p.pos = 0;
    p.toknext = 0;
    p.toksuper = -1;
    p.tokens = tokens;
    p.num_tokens = num_tokens;

    for (; p.pos < p.len; p.pos++) {
        char c = js[p.pos];
        switch (c) {
        case '{':
        case '[': {
            int ti = jalloc(&p);
            if (ti < 0)
                return p.toknext + 16; /* 容量不足：返回需求估值 */
            wg_jtoken *t = &tokens[ti];
            t->type = (c == '{') ? WG_J_OBJECT : WG_J_ARRAY;
            t->start = (int)p.pos;
            if (p.toksuper >= 0)
                tokens[p.toksuper].size++;
            p.toksuper = ti;
            count++;
            break;
        }
        case '}':
        case ']': {
            if (p.toksuper < 0)
                return -1;
            wg_jtype want = (c == '}') ? WG_J_OBJECT : WG_J_ARRAY;
            int ti = p.toksuper;
            if (tokens[ti].type != want)
                return -1;
            tokens[ti].end = (int)p.pos + 1;
            p.toksuper = tokens[ti].parent;
            break;
        }
        case '"': {
            int r = jparse_string(&p);
            if (r < 0)
                return r == -2 ? p.toknext + 16 : -1;
            count++;
            if (p.toksuper >= 0 && tokens[p.toksuper].type == WG_J_OBJECT) {
                /* 对象内字符串若是 key（后跟 ':'），不作为 value 计数修正：
                 * 简化：对象 size 按 key 计，jparse_string 已 +1，value 又 +1。
                 * 统一在 object_get 里按 2*i 步进遍历。 */
            }
            p.pos--; /* for 循环会再 +1 */
            break;
        }
        case ':':
            /* 把 toksuper 指向 key 之后的 value 归属：无需处理，size 已按 token 计 */
            break;
        case ',':
        case ' ':
        case '\t':
        case '\n':
        case '\r':
            break;
        default: {
            int r = jparse_primitive(&p);
            if (r == -2)
                return p.toknext + 16;
            if (r < 0)
                return -1;
            count++;
            p.pos--; /* primitive 已停在分隔符 */
            break;
        }
        }
    }

    if (p.toksuper != -1)
        return -1; /* 未闭合 */
    (void)count;
    return 0;
}

/* 遍历 object 的 key/value 对：object 的子 token 按 [key,value] 交替出现。
 * 注意 jparse 里 size 对每个子 token（key 与 value 各 +1），所以步进按 token 树走。 */
static int jchild(const wg_jtoken *tokens, int ntok, int parent, int after)
{
    for (int i = after; i < ntok; i++) {
        if (tokens[i].parent == parent)
            return i;
    }
    return -1;
}

/* 返回 parent 的第 n 个子 token 下标 */
static int jnth_child(const wg_jtoken *tokens, int ntok, int parent, int n)
{
    int idx = -1;
    for (int i = 0; i <= n; i++) {
        idx = jchild(tokens, ntok, parent, idx + 1);
        if (idx < 0)
            return -1;
    }
    return idx;
}

int wg_json_object_get(const char *js, const wg_jtoken *tokens, int ntok, int obj, const char *key)
{
    if (tokens[obj].type != WG_J_OBJECT)
        return -1;
    int n = tokens[obj].size / 2; /* key+value 各计一次 */
    for (int i = 0; i < n; i++) {
        int ki = jnth_child(tokens, ntok, obj, 2 * i);
        int vi = jnth_child(tokens, ntok, obj, 2 * i + 1);
        if (ki < 0 || vi < 0)
            return -1;
        const wg_jtoken *k = &tokens[ki];
        int klen = k->end - k->start;
        if ((int)strlen(key) == klen && strncmp(js + k->start, key, (size_t)klen) == 0)
            return vi;
    }
    return -1;
}

bool wg_json_string(const char *js, const wg_jtoken *tok, char *out, size_t out_cap)
{
    if (tok->type != WG_J_STRING)
        return false;
    size_t o = 0;
    for (int i = tok->start; i < tok->end; i++) {
        char c = js[i];
        if (c == '\\' && i + 1 < tok->end) {
            char e = js[++i];
            switch (e) {
            case 'n': c = '\n'; break;
            case 't': c = '\t'; break;
            case 'r': c = '\r'; break;
            case 'b': c = '\b'; break;
            case 'f': c = '\f'; break;
            case 'u':
                i += 4; /* \uXXXX：配置场景不需要，吞掉 */
                if (i >= tok->end)
                    return false;
                c = '?';
                break;
            default: c = e; break;
            }
        }
        if (o + 1 >= out_cap)
            return false;
        out[o++] = c;
    }
    out[o] = '\0';
    return true;
}

bool wg_json_long(const char *js, const wg_jtoken *tok, long *out)
{
    if (tok->type != WG_J_PRIMITIVE)
        return false;
    long v = 0;
    bool neg = false;
    int i = tok->start;
    if (js[i] == '-') {
        neg = true;
        i++;
    }
    if (i >= tok->end)
        return false;
    for (; i < tok->end; i++) {
        if (js[i] < '0' || js[i] > '9')
            return false;
        v = v * 10 + (js[i] - '0');
    }
    *out = neg ? -v : v;
    return true;
}
