# WireGuard 数据面（自研 C，见 docs/decisions/0001/0002）
cmake_minimum_required(VERSION 3.16)
project(wireguard_harmony C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# NAPI 胶水层 + 密码原语 + 握手/传输/运行时（全部协议逻辑在本 .so 内）
add_library(entry SHARED
    napi_init.cpp
    blake2s.c
    chacha20poly1305.c
    curve25519.c
    wg_base64.c
    wg_device.c
    wg_handshake.c
    wg_json.c
    wg_kat.c
    wg_log.c
    wg_runtime.c
    wg_transport.c
)

target_compile_options(entry PRIVATE -Wall -Wextra)

# NAPI 与 hilog（OHOS NDK 系统库）；pthread 在 libc 内无需单列
target_link_libraries(entry PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
)
