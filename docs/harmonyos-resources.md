# HarmonyOS 开发资料清单（供 AI agent 查阅）

> 维护原则（违反即视为坏链接，需修复）：
> 1. 每条 URL 必须是**深链**（直达正文，非目录首页）且**免登录**；
> 2. ⚠️ **`.md` 后缀技巧已失效**（2026-09 实测：华为文档站任意 URL 加 `.md` 全站 404），
>    且该站是 JS 渲染的 SPA——裸 URL 用 `curl` 永远返回 200 空壳。
>    **本清单的 URL 仅供人工/浏览器打开**；agent 取正文走下方「如何使用本文档」第 2 条的三条正路。
> 3. 每条附一句话摘要和"何时查阅"；
> 4. 与项目 SDK 对齐：**HarmonyOS 6.1.1 / API 24**（以 build-profile.json5 的 targetSdkVersion 为准）。
> 5. 2026-10 新增的分区（VPN/原生/加密/通知/文件）URL 由 **OpenHarmony docs 仓库文件名逐一 200 校验 + 华为站点 slug 命名规律推导**，
>    尚未逐个在浏览器实测；打开异常时按「如何使用本文档」第 2 条走 raw/d.ts，并顺手修正本文件。
>
> 本文档按**开发任务**分区，不按文档类型分区。新增分区随项目开发需求补充。

## 如何使用本文档

**三层配合：语义速搜 → SDK 核事实 → 官方仓库读全文**

1. **搜索/速答 → Context7**（语义搜索官方文档，返回聚焦片段 + 来源 URL）：
   - 指南库 ID：`/websites/developer_huawei_consumer_cn_doc_harmonyos-guides`
   - API 参考库 ID：`/websites/developer_huawei_consumer_cn_doc_harmonyos-references`
   - Samples 库 ID：`/linganmin/harmonyos_samples`
   - 适合：不知道具体页面、"怎么做 X" 类问题。局限：片段式摘录，可能缺完整签名/版本标注。

2. **核对事实 / 读全文 → 三条正路**（免登录、可 grep、权威）：

   1) **SDK d.ts——第一手事实来源，优先级最高**（API 是否存在、枚举有多少个值，以它为准）：
      ```bash
      SDK=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
      ls $SDK/ets/api/*.d.ts          # 单模块 API（@ohos.* / arkts-apis-*）
      cat $SDK/ets/kits/@kit.*.d.ts   # kit 导出清单（@kit.XxxKit 里到底导出了什么）
      grep -n 'sys_color\|ohos_ic_public' $SDK/toolchains/id_defined.json   # sys.color.* / sys.media.* 合法名
      python3 -c "import json;d=json.load(open('$SDK/toolchains/lib/PermissionDefinitions.json'));..."  # 权限级别
      ```
   2) **OpenHarmony 官方 docs 仓库 raw**（ArkTS 完整示例、能力/算法支持矩阵）：
      `https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/<子系统>/<主题>.md`
      - 例：`security/UniversalKeystoreKit/huks-refined-user-identity-authentication.md`（HUKS 指纹访问控制范式）
      - 能力/规格类问题查 `*-spec.md`，如 `security/CryptoArchitectureKit/crypto-sym-encrypt-decrypt-spec.md`
        （用于确认 `"AES256|CBC|NoPadding"` 这类 transformation 字符串是否合法）
   3) **Context7**（见第 1 条）。

3. **设计新功能前先查权限级别**（决定功能可行性，属于前置闸门）：
   `toolchains/lib/PermissionDefinitions.json` 里
   - `grantMode: system_grant` + `availableLevel: normal` → **声明即可、免弹窗**
     （已核实：`ACCESS_BIOMETRIC`、`PRIVACY_WINDOW`、`FILE_ACCESS_PERSIST`）；
   - `grantMode: user_grant` + `availableLevel: system_basic` → **普通应用拿不到**
     （已核实：`READ_PASTEBOARD`）→ 设计阶段就应避开，否则写完才发现不可实现。

---

## 入门与项目结构

| 资料 | 何时查阅 |
|---|---|
| [开发准备/快速入门](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/start-overview) | 搭建环境、跑通第一个页面 |
| [创建新工程](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-create-new-project) | 新建模块、理解工程模板 |
| [工程目录结构](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-project-structure) | 理解 AppScope/entry/oh-package/hvigor 各文件职责 |

## ArkTS 语言

| 资料 | 何时查阅 |
|---|---|
| [初识 ArkTS 语言](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/introduction-to-arkts) | ArkTS 与 TypeScript 的差异、严格模式限制（如禁用 any/对象字面量类型等） |
| [状态管理 V1→V2 迁移](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-v1-v2-migration) | 判断该用 @State 还是 @ObservedV2/@Trace 等新一代装饰器 |

## 应用模型（Ability）

| 资料 | 何时查阅 |
|---|---|
| [UIAbility 组件概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uiability-overview) | 理解 Stage 模型、UIAbility 与页面的关系 |
| [UIAbility 生命周期](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uiability-lifecycle) | onCreate/onForeground/onBackground 等回调的正确用法 |

## ArkUI 组件与声明式 UI

| 资料 | 何时查阅 |
|---|---|
| [声明式 UI 描述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-declarative-ui-description) | UI 描述范式基础：自定义组件、@Builder、链式属性 |
| [@Builder 函数](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-builder) | 复用 UI 片段、@BuilderParam 传 UI 结构 |
| [自定义组件生命周期](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-page-custom-components-lifecycle) | aboutToAppear/aboutToDisappear/onPageShow 等 |
| [Text 组件 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-text) | 文本展示、富文本混排 |
| [TextInput 组件 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-textinput) | 单行/多行文本输入 |
| [RichEditor 组件 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-richeditor) | 富文本编辑器（图文混排内容编辑） |
| [List 组件 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-list) | 列表页 |
| [Scroll 组件 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-scroll) | 滚动容器 |
| [Navigation 组件 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-navigation) | 页面导航容器（推荐方案，见"路由与导航"） |

> 查其他组件：URL 规律为 `harmonyos-references/ts-basic-components-<名称>` /
> `ts-container-<名称>`，改名后加 `.md` 验证是否存在。

## 状态管理

| 资料 | 何时查阅 |
|---|---|
| [状态管理概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-state-management-overview) | 选型入口：组件内状态/跨组件/跨页面/AppStorage 怎么选 |
| [@State 装饰器](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-state) | 组件内可变状态的基本用法 |

## 路由与导航

| 资料 | 何时查阅 |
|---|---|
| [组件导航 Navigation（推荐）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-navigation-navigation) | **页面跳转首选**。该页是索引，含子链接：基础架构/NavDestination/页面路由/转场动画/跨包路由/分栏模式 |
| [Navigation 子页面 NavDestination](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-navigation-navdestination) | 目标页面的声明与生命周期 |
| [Navigation 页面路由](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-navigation-jump) | push/replace/pop、传参、路由栈操作 |

## 数据持久化

| 资料 | 何时查阅 |
|---|---|
| [应用数据持久化概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/app-data-persistence-overview) | 选型：Preferences / KV-Store / RelationalStore 哪个适合业务数据 |
| [通过用户首选项持久化](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-persistence-by-preferences) | 配置项、轻量 KV |
| [Preferences API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-data-preferences) | 首选项完整 API |
| [通过关系型数据库持久化](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-persistence-by-rdb-store) | **结构化数据存储首选**（SQLite 封装），建表/增删改查/谓词 |
| [RelationalStore API 总览](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-data-relationalstore) | 模块入口页，含 RdbStore/ResultSet/RdbPredicates 等子页链接 |
| [RdbStore 接口](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-data-relationalstore-rdbstore) | insert/update/query/delete 等方法签名 |

## 网络

| 资料 | 何时查阅 |
|---|---|
| [HTTP 数据请求](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/http-request) | 发起请求、权限声明（ohos.permission.INTERNET） |
| [@ohos.net.http API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-http) | 请求/响应完整 API |

## VPN 与网络隧道（本项目核心）

> 上游 WireGuard-Android 的 `tunnel/` 与 `ui/` 全部能力最终落在这个分区。

| 资料 | 何时查阅 |
|---|---|
| [连接VPN（三方VPN能力）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/net-vpnExtension) | **本项目核心文档**。三方 `VpnExtensionAbility` 完整开发步骤：建 UDP 隧道 → `protect` → 构建 `VpnConfig` → `create` 拿到 tun fd → 自行收发虚拟网卡数据；含 VpnConfig 全字段表 |
| [@ohos.net.vpnExtension API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-net-vpnExtension) | `VpnConnection` 全部方法（`create`/`generateVpnId`/`protect`/`protectProcessNet`/`destroy`）与 `VpnConfig` 类型定义 |
| [VpnExtensionAbility API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-VpnExtensionAbility) | VPN 扩展 Ability 的 `onCreate`/`onDestroy` 生命周期 |
| [官方 VPN 示例工程 VPNControl_Case](https://github.com/openharmony/applications_app_samples/tree/master/code/DocsSample/NetWork_Kit/NetWorkKit_NetManager/VPNControl_Case) | **可直接跑的端到端参考**：ArkTS 侧 VpnExtensionAbility + C++ 侧 `napi_init.cpp`（两个线程做 tun fd ↔ UDP socket 双向转发）+ CMakeLists |
| [管理网络连接](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/net-connection-manager) | 监听 WiFi/蜂窝切换并重连隧道 |
| [使用Socket访问网络](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/socket-connection) | UDP socket 创建、把 fd 交给原生层 / 交给 `protect` |
| [统计网络流量消耗](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/net-statistics) | 上游 `Statistics`（收发字节数/握手时间）的对应实现 |
| [VPN管理（仅对系统应用开放）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/net-vpn-sys) | ⚠️ 走这条需要 `MANAGE_VPN`（system_basic）。**三方应用不要用**，用 `net-vpnExtension` |

## NDK / NAPI 原生开发

> WireGuard 的隧道协议（wireguard-go / 数据面）必须在 C/C++ 侧实现并交叉编译；ArkTS 只做薄壳。

| 资料 | 何时查阅 |
|---|---|
| [Native API 开发指导（NAPI）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/napi-guidelines) | ArkTS ↔ C/C++ 互调：模块注册、类型转换、线程安全；写 wireguard-go 适配层必读 |
| [网络管理（C/C++）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/native-netmanager-guidelines) | 原生侧 socket/网络状态 API |
| [WebSocket（C/C++）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/native-websocket-guidelines) | 原生网络编程范式补充参考 |
| SDK 事实来源 | NDK 头文件：`$DEVECO_SDK_HOME/default/openharmony/native/sysroot/usr/include/`（含 `CryptoArchitectureKit/`）；交叉编译工具链在 `native/llvm/` |

## 加解密与安全

> 上游 `crypto/` 与 WireGuard 协议原语在本分区的覆盖情况**直接决定可行性**，动手前先核对。

| 资料 | 何时查阅 |
|---|---|
| [Crypto Architecture Kit简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/crypto-architecture-kit-intro) | 算法能力总览与选型入口 |
| [对称密钥加解密算法规格](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/crypto-sym-encrypt-decrypt-spec) | 确认 `"ChaCha20|Poly1305"` 这类 transformation 字符串是否合法 |
| [ChaCha20（Poly1305模式）加解密](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/crypto-chacha20-encrypt-decrypt-poly1305) | WireGuard 数据面 AEAD；核对 nonce/AAD 规格是否匹配（WireGuard 用 96-bit nonce） |
| [消息摘要计算介绍及算法规格](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/crypto-generate-message-digest-overview) | ⚠️ **仅 SHA256/MD5/SHA3**。WireGuard 需要的是 **BLAKE2s**（含 keyed/带 key 的 MAC）→ **框架不提供，必须自实现** |
| [消息认证码计算HMAC](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/crypto-compute-hmac) | HMAC/CMAC；注意 WireGuard 用的是 keyed-BLAKE2s，**不能**用 HMAC 顶替 |
| [使用X25519进行密钥协商](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/crypto-key-agreement-using-x25519) | WireGuard 的 Curve25519 密钥交换 |
| [密钥协商介绍及算法规格](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/crypto-key-agreement-overview) | 判断可用协商算法与规格 |
| [Universal Keystore Kit简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/huks-overview) | 私钥落盘/免导出（对应上游用 Android Keystore 保存私钥的思路） |
| SDK 事实来源 | `$SDK/ets/api/@ohos.security.cryptoFramework.d.ts`、`$SDK/native/sysroot/usr/include/CryptoArchitectureKit/` |

## 日志与调试

| 资料 | 何时查阅 |
|---|---|
| [HiLog 日志](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hilog) | 打日志、DOMAIN/TAG 规范、`hdc shell hilog` 查看 |
| [HiLog API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-hilog) | hilog.debug/info/warn/error 签名 |

## 测试

| 资料 | 何时查阅 |
|---|---|
| [代码测试（Hypium）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-code-test) | 单元测试/UI 测试编写与执行 |
| [应用测试概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/test-kit-overview) | 测试能力全景 |

## 签名、构建与发布

| 资料 | 何时查阅 |
|---|---|
| [应用/元服务签名](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing) | 配置签名证书（真机运行前置条件） |
| [真机运行](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-run-device) | 连接设备运行调试 |

## 折叠屏与外屏适配（Pura X）

| 资料 | 何时查阅 |
|---|---|
| [Pura X 常见问题（官方 FAQ）](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-purax-1) | 外屏适配申请审核等；SPA 站裸 URL 无正文，走 Context7 / 搜索引擎缓存 |
| [Pura X Max 适配官方指南](https://developer.huawei.com/consumer/cn/newdevice/pura-x-max/) | 阔折叠适配总入口（设备特点、模拟器、云调试） |
| 官方《折叠屏UX体验标准》《折叠屏应用开发指导》《Pura X外屏开发实践》 | 外屏适配验收依据（一多专区 / 设备场景专区，站内搜索标题） |

**已核实的平台事实（2026，真机 + 官方渠道确认）**：
- **外屏显示三方应用是白名单制**：完成外屏适配 → 上架应用市场 → 提交
  「Pura X 外屏应用展示申请」→ 华为审核通过加白名单后，应用才能出现在外屏。
  **本地 hdc 安装的开发版无法被添加到外屏**（系统设置里添加不了是预期行为）。
- **外屏不支持本地真机调试**（官方问答）：外屏形态调试用 DevEco Studio 的
  Pura X 模拟器（设备管理器下载）；Pura X Max 另有 AGC 云调试真机。
- 外屏断点：横向 sm / 纵向 md（1:1 方形）；内外屏接续：外屏→内屏直接接续；
  内屏→外屏默认亮屏锁定，解锁后已适配应用接续到外屏。

## 系统能力与其他

| 资料 | 何时查阅 |
|---|---|
| [SysCap 系统能力](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/syscap) | 判断某 API 在目标设备是否可用 |

## 通知与后台任务

| 资料 | 何时查阅 |
|---|---|
| [通知概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-overview) | VPN 连接状态常驻通知（官方明确要求 VPN 应用提供） |
| [Background Tasks Kit简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/background-task-overview) | 选型：短时/长时/延迟任务 |
| [长时任务](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/continuous-task) | 保活要求；注意三方 VPN 由 VpnExtensionAbility 托管，**调用方进程退出时系统会主动断开 VPN** |

## 文件选择与权限申请

| 资料 | 何时查阅 |
|---|---|
| [选择用户文件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/select-user-file) | 导入 `.conf` 配置（对应上游 "Import from file"） |
| [声明权限](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/declare-permissions) | module.json5 `requestPermissions` 写法 |
| [向用户申请授权](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/request-user-authorization) | `user_grant` 权限的弹窗流程 |
| [应用权限列表（normal 级）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/permissions-for-all) | 哪些权限声明即可用（三方 VPN 只需 `ohos.permission.INTERNET`） |
---

## 已验证但暂未分区的 URL 规律备忘

- 指南类：`harmonyos-guides/<主题>`；API 参考类：`harmonyos-references/<主题>`
- ArkTS API 模块新命名：`arkts-apis-<kit>-<模块>[-<类/接口>]`
- 旧命名 `js-apis-*` 页面多为子页索引；正文在 `arkts-apis-*` 页面
- 站内搜索命中带 `-V13`/`-V14` 版本后缀的 URL 时，去掉后缀即为最新版地址
- **这些 URL 规律只用于人工打开**；agent 需要正文时请走上面第 2 条（SDK d.ts / docs 仓库 raw）

## 待补充（随项目开发填充）

- [x] 文件管理 → 见「文件选择与权限申请」
- [x] 权限申请流程（acl/user_grant） → 见「文件选择与权限申请」
- [ ] 二维码扫描（导入 `wg` 配置二维码，Scan Kit；上游有 "Import from QR code"）
- [ ] 键盘处理与输入法
- [ ] 备份与恢复（EntryBackupAbility 已建，backup_config.json）
- [ ] 上架流程（AppGallery Connect）
- [ ] 已知坑清单（报错信息 → 解法 → 文档出处）
