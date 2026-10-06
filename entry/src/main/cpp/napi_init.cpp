/*
 * WireGuard 数据面 NAPI 入口（当前为编译链空壳）。
 *
 * 决策依据 docs/decisions/0001 + 0002：
 * - 隧道协议（握手 Noise IK + 传输加解密 + 定时器）全部在本 .so 内自研 C 实现；
 * - NAPI 边界保持薄控制面：配置下发 / 控制指令 / 状态与统计上抛，协议细节不外泄。
 *
 * TODO(0001): blake2s / chacha20poly1305 / x25519 参考实现移植（含启动 KAT 自检）
 * TODO(0002): 握手状态机与会话密钥轮换
 * TODO(0001): tun fd <-> UDP 双线程转发（参考官方 VPNControl_Case 线程结构）
 */
#include "napi/native_api.h"
#include <hilog/log.h>

#define LOG_TAG "wg-dataplane"

/** startTunnel(tunFd, configJson) -> 0 成功 / <0 错误码。当前为空壳桩。 */
static napi_value StartTunnel(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t tunFd = -1;
    napi_get_value_int32(env, args[0], &tunFd);
    OH_LOG_INFO(LOG_APP, "startTunnel stub, tunFd=%{public}d (dataplane not implemented yet)", tunFd);

    napi_value result;
    napi_create_int32(env, 0, &result);
    return result;
}

/** stopTunnel()：停止转发线程并释放会话。当前为空壳桩。 */
static napi_value StopTunnel(napi_env env, napi_callback_info info) {
    OH_LOG_INFO(LOG_APP, "stopTunnel stub");
    return nullptr;
}

/** getVersion() -> 数据面版本串，用于冒烟验证 .so 加载与 NAPI 注册。 */
static napi_value GetVersion(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_string_utf8(env, "wg-dataplane 0.0.1-stub", NAPI_AUTO_LENGTH, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"startTunnel", nullptr, StartTunnel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopTunnel", nullptr, StopTunnel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
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

extern "C" __attribute__((constructor)) void RegisterWgModule(void) {
    napi_module_register(&wgModule);
}
