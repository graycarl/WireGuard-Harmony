/*
 * WireGuard 数据面 NAPI 入口（薄控制面，决策 0001/0002）。
 *
 * 接口契约见 docs/dev-contracts.md §8：
 *   createUdpSocket() -> fd        （VPN 进程先 protect(fd) 再 startTunnel）
 *   startTunnel(tunFd, sockFd, configJson) -> 0 / <0 错误码
 *   stopTunnel() / getStats() / getLastError() / getVersion()
 * 错误码：-1 参数/内部；-2 endpoint DNS 解析失败（getLastError=主机名）；
 *        -3 socket/bind 失败；-4 线程创建失败；-5 启动 KAT 自检失败。
 *
 * 本层不含协议逻辑：只做参数转换、设备生命周期、状态快照。
 */
#include "napi/native_api.h"
#include "wireguard.h"
#include "wg_base64.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

/* 全局单实例数据面（决策 0006 §4：同一时刻只承载一条隧道） */
wg_device g_wg;
static bool g_dev_ready = false;

static napi_value Int32(napi_env env, int32_t v)
{
    napi_value r;
    napi_create_int32(env, v, &r);
    return r;
}

/* ---------------- createUdpSocket ---------------- */
static napi_value CreateUdpSocket(napi_env env, napi_callback_info info)
{
    (void)info;
    int fd = socket(AF_INET6, SOCK_DGRAM, 0);
    if (fd < 0)
        return Int32(env, -3);
    int off = 0;
    /* 双栈：同一 socket 承载 v4（v4-mapped）与 v6 端点 */
    (void)setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &off, sizeof(off));
    return Int32(env, fd);
}

/* ---------------- startTunnel ---------------- */
static napi_value StartTunnel(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = { nullptr, nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 3)
        return Int32(env, -1);

    int32_t tun_fd = -1;
    int32_t sock_fd = -1;
    napi_get_value_int32(env, args[0], &tun_fd);
    napi_get_value_int32(env, args[1], &sock_fd);
    if (tun_fd < 0)
        return Int32(env, -1);

    static char config_json[8192];
    size_t jlen = 0;
    if (napi_get_value_string_utf8(env, args[2], config_json, sizeof(config_json), &jlen) != napi_ok)
        return Int32(env, -1);

    if (!g_dev_ready) {
        wg_device_init(&g_wg);
        g_dev_ready = true;
    }

    /* 重新启动前先停干净旧实例 */
    wg_runtime_stop(&g_wg);
    wg_device_destroy(&g_wg);
    g_wg.tun_fd = tun_fd;
    /* sockFd < 0 时复用 createUdpSocket() 已创建的 fd */
    g_wg.sock_fd = sock_fd >= 0 ? sock_fd : g_wg.sock_fd;
    g_wg.listen_port = 0;
    g_wg.n_peers = 0;
    g_wg.running = false;
    g_wg.threads_started = false;
    g_wg.last_error[0] = '\0';

    if (!wg_kat_selftest()) {
        wg_set_last_error(&g_wg, "crypto KAT selftest failed", NULL);
        return Int32(env, -5);
    }

    int rc = wg_device_configure(&g_wg, config_json);
    if (rc != 0)
        return Int32(env, rc); /* -1；-2 时 last_error 为解析失败的主机名 */

    if (g_wg.sock_fd < 0)
        return Int32(env, -3);

    struct sockaddr_in6 addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin6_family = AF_INET6;
    addr.sin6_addr = in6addr_any;
    addr.sin6_port = htons(g_wg.listen_port);
    if (bind(g_wg.sock_fd, (const struct sockaddr *)&addr, sizeof(addr)) < 0) {
        char msg[64];
        snprintf(msg, sizeof(msg), "bind failed: errno=%d", errno);
        wg_set_last_error(&g_wg, "%s", msg);
        return Int32(env, -3);
    }

    if (wg_runtime_start(&g_wg) != 0)
        return Int32(env, -4);

    return Int32(env, 0);
}

/* ---------------- stopTunnel ---------------- */
static napi_value StopTunnel(napi_env env, napi_callback_info info)
{
    (void)info;
    wg_runtime_stop(&g_wg);
    if (g_wg.sock_fd >= 0) {
        close(g_wg.sock_fd);
        g_wg.sock_fd = -1;
    }
    /* tun fd 归 vpnConnection 所有，不在此关闭 */
    g_wg.tun_fd = -1;
    wg_device_destroy(&g_wg);
    return Int32(env, 0);
}

/* ---------------- getStats ---------------- */
typedef struct {
    uint8_t public_key[32];
    uint64_t rx_bytes;
    uint64_t tx_bytes;
    uint64_t last_handshake_ms;
    char endpoint[64];
} stat_snapshot;

static napi_value GetStats(napi_env env, napi_callback_info info)
{
    (void)info;
    static stat_snapshot snap[WG_MAX_PEERS];
    int n = 0;

    pthread_mutex_lock(&g_wg.lock);
    if (g_wg.n_peers > WG_MAX_PEERS)
        n = WG_MAX_PEERS;
    else
        n = g_wg.n_peers;
    for (int i = 0; i < n; i++) {
        const wg_peer *p = &g_wg.peers[i];
        memcpy(snap[i].public_key, p->public_key, 32);
        snap[i].rx_bytes = p->rx_bytes;
        snap[i].tx_bytes = p->tx_bytes;
        snap[i].last_handshake_ms = p->last_handshake_ms;
        snap[i].endpoint[0] = '\0';
        if (p->has_endpoint)
            wg_sockaddr_to_string(&p->endpoint, snap[i].endpoint, sizeof(snap[i].endpoint));
    }
    pthread_mutex_unlock(&g_wg.lock);

    napi_value arr;
    napi_create_array_with_length(env, (size_t)n, &arr);
    for (int i = 0; i < n; i++) {
        napi_value obj;
        napi_create_object(env, &obj);

        char b64[64];
        wg_b64_encode(b64, snap[i].public_key, 32);
        napi_value v;
        napi_create_string_utf8(env, b64, NAPI_AUTO_LENGTH, &v);
        napi_set_named_property(env, obj, "publicKey", v);
        napi_create_double(env, (double)snap[i].rx_bytes, &v);
        napi_set_named_property(env, obj, "rxBytes", v);
        napi_create_double(env, (double)snap[i].tx_bytes, &v);
        napi_set_named_property(env, obj, "txBytes", v);
        napi_create_double(env, (double)snap[i].last_handshake_ms, &v);
        napi_set_named_property(env, obj, "lastHandshakeMs", v);
        napi_create_string_utf8(env, snap[i].endpoint, NAPI_AUTO_LENGTH, &v);
        napi_set_named_property(env, obj, "endpoint", v);

        napi_set_element(env, arr, (uint32_t)i, obj);
    }
    return arr;
}

/* ---------------- getLastError / getVersion ---------------- */
static napi_value GetLastError(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value r;
    napi_create_string_utf8(env, g_wg.last_error, NAPI_AUTO_LENGTH, &r);
    return r;
}

static napi_value GetVersion(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value r;
    napi_create_string_utf8(env, WG_VERSION, NAPI_AUTO_LENGTH, &r);
    return r;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"createUdpSocket", nullptr, CreateUdpSocket, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startTunnel", nullptr, StartTunnel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopTunnel", nullptr, StopTunnel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getStats", nullptr, GetStats, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getLastError", nullptr, GetLastError, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    if (!g_dev_ready) {
        wg_device_init(&g_wg);
        g_dev_ready = true;
    }
    return exports;
}
EXTERN_C_END

static napi_module wgModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterWgModule(void)
{
    napi_module_register(&wgModule);
}
