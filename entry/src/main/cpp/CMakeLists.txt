# WireGuard 数据面（自研 C，见 docs/decisions/0001）
cmake_minimum_required(VERSION 3.16)
project(wireguard_harmony C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# NAPI 胶水层 + 后续协议实现（blake2s / chacha20poly1305 / x25519 / 握手 / 转发）
add_library(entry SHARED
    napi_init.cpp
)

# NAPI 与 hilog（OHOS NDK 系统库）
target_link_libraries(entry PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
)
