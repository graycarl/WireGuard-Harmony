# WireGuard for HarmonyOS

WireGuard VPN 客户端的 **HarmonyOS 原生重写**：ArkTS + ArkUI 声明式 UI + `VpnExtensionAbility`，
功能对齐上游 [WireGuard for Android](https://github.com/WireGuard/wireguard-android)。

> **状态**：数据面（C：BLAKE2s / HMAC / ChaCha20-Poly1305 / X25519 + Noise IK 握手 + 传输 + 定时器 + NAPI）
> 与全部功能页面已实现；本地单测 117 例全绿，`make build` 可打包签名 HAP。
> **真机与互操作验收仍在进行中**（清单见 `docs/device-verification.md`）。
> 未上架应用市场，也不提供安装包下载，请自行构建。

📖 **用户手册（在线）**：<https://graycarl.github.io/WireGuard-Harmony/>
（源文件在 [`handbook/`](handbook/)，改完需合并到 `main` 才会自动发布，见
[`.github/workflows/pages.yml`](.github/workflows/pages.yml)）

## 特性

- **无后端、无账号**：配置与私钥只存本机；支持 wg-quick `.conf` 文本、二维码（含图片识别）、手动编辑
- **数据面自研 C 实现**：tun fd 读写与 UDP 转发在原生层，`protect()` 保护隧道 socket 防环回
- **纯 ArkTS 的 X25519**：平台「按 spec 派生密钥对」在真机上不可用，故自实现并做 RFC 7748 KAT
  （见 [`docs/decisions/0008`](docs/decisions/0008-arkts-x25519-self-implemented.md)）
- 单激活互斥、切换回滚、锁屏认证、防截屏、应用过滤、实时统计、日志脱敏

## 构建

需要 DevEco Studio（SDK 6.1.1 / API 24，`runtimeOS: HarmonyOS`）。仓库内**没有 `hvigorw`**，
用根目录 `Makefile` 调用 IDE 内置工具链，无需打开 IDE：

```bash
make ohpm-install   # 首次：拉取 ohpm 依赖
make build          # 编译 + 打包 debug HAP → entry/build/default/outputs/
make test           # 本地单测（hypium，无平台 API 依赖的纯逻辑）
make sign-status    # 查看当前签名材料来源
make help           # 列出全部目标
```

**签名材料不入库**：`build-profile.json5` 里 `app.signingConfigs` 恒为 `[]`（入库的是
products / SDK 版本 / buildModeSet / modules），本机材料放已 gitignore 的 `signing-config.local.json`，
由 `hvigorfile.ts` 经 `config.ohos.overrides.signingConfig` 注入。在 DevEco Studio 里配置或修改签名后，
跑一次 `make sign-import` 把材料搬进本地文件并还原 `build-profile.json5`。未配置签名时构建只产出
`entry-default-unsigned.hap`（SignHap 阶段 WARN 跳过），不影响编译验证。

## 目录

```
AppScope/           应用级配置（bundleName / 版本 / 分层图标）
entry/src/main/ets/ ArkTS 控制面：config(解析) / crypto / model / repo / store / backend /
                    platform / services / components / pages / vpnability(VPN 进程)
entry/src/main/cpp/ C 数据面：原语 / 握手 / 传输 / 定时器 / NAPI / 启动 KAT
entry/src/test/     本地单测（hypium）
specs/              功能规格（用户视角，先于代码）
handbook/           用户使用说明书（HTML + 内联 SVG 截图）
docs/decisions/     技术决策 0001–0008（数据面自研、握手分层、持久化、进程通信…）
docs/               真机验证清单、互操作验收、模块 API 契约
AGENTS.md           给 AI coding agent 的项目上下文（事实 / 构建 / 资料检索 / 已知坑）
```

## 与上游的关系

Android 版的 `tunnel/`（配置解析 + 后端 + 加密）与 `ui/` 是本项目的主要参照：wg-quick 解析、
密钥编解码、数据面分层与握手流程均按上游行为对齐，但界面为 ArkUI 重写、数据面为 C 自研（非移植
libwg-go）。平台上无对应物的部分（root、`wg`/`wg-quick` 命令行、动态加载本地库）已裁剪。

## 许可与致谢

[Apache License 2.0](LICENSE)。

本项目是 [WireGuard for Android](https://github.com/WireGuard/wireguard-android) 的 HarmonyOS 重写，
其配置解析、密钥格式、协议行为参照上游实现（Copyright © WireGuard LLC，Apache-2.0）；
`entry/src/main/ets/crypto/` 中的 BLAKE2s / HKDF 为镜像实现，仅用于本地 KAT 对照。

WireGuard 是 WireGuard LLC 的注册商标；本项目为社区实现，与其无隶属或背书关系。
