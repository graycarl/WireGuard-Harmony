# AGENTS.md — WireGuard（HarmonyOS）

> 本文件是 AI coding agent 的项目入口。先读「项目事实」，再按任务查「资料速查」。
> 完整资料清单见 [docs/harmonyos-resources.md](docs/harmonyos-resources.md)。

## 项目事实

| 项 | 值 |
|---|---|
| 应用 | WireGuard |
| 定位 | **WireGuard VPN 客户端的 HarmonyOS 原生重写**：ArkTS + ArkUI 声明式 UI + `VpnExtensionAbility`，功能对齐上游 WireGuard-Android |
| 数据源 | 本地用户配置（wg-quick `.conf` 文本 / 二维码 / 手动编辑），**无后端服务**；配置与私钥仅存本机 |
| 上游参考实现 | `~/LibSource/WireGuard-Android`（tag `1.0.20260315-1-ge7b3a3c1`） |
| 设计文档 | **[docs/design-v0.1.md](docs/design-v0.1.md)**（待编写：MVP 范围/架构/任务拆解，当前仅有本文件与 resources.md） |
| bundleName | `me.graycarl.wireguard` |
| 平台 | HarmonyOS（纯鸿蒙，`runtimeOS: HarmonyOS`，非兼容模式） |
| SDK | 6.1.1(24)，target/compatible 均为 24 |
| 设备 | phone |
| 语言/UI | ArkTS + ArkUI 声明式开发 |
| 构建系统 | hvigor（modelVersion 6.1.1） |

## 仓库结构

当前是 DevEco 模板生成的**可编译空骨架**，业务代码尚未开始：

```
AppScope/            # 应用级配置（app.json5: bundleName/版本/图标）
entry/               # 主模块（type: entry）
  src/main/ets/
    entryability/    # EntryAbility.ets（UIAbility 入口）
    entrybackupability/
    pages/Index.ets  # 首页占位（后续替换为隧道列表页）
  src/main/module.json5   # 模块配置：abilities、deviceTypes、requestPermissions
  src/main/resources/     # base/dark 资源（string/color/float/media）
  src/test/               # 本地单测（hypium，跑在宿主 JVM/Node 模拟环境）
  src/ohosTest/           # 设备侧集成测试
build-profile.json5  # 应用级构建配置（products/签名/SDK 版本）
oh-package.json5     # 依赖声明（当前无三方依赖，仅 devDeps: hypium, hamock）
docs/                # 设计文档与开发资料索引
```

**规划中的目录结构**（动手时按此分层，详见下方「核心设计决策」）：

```
entry/src/main/ets/
  config/       # wg-quick 解析（Config/Interface/Peer/InetAddresses/InetNetwork/InetEndpoint）
  crypto/       # Key/KeyPair/BLAKE2s 等（纯算法，可本地单测）
  model/        # 隧道领域模型 + 快照
  repo/         # 配置持久化（Preferences / 文件 / RDB）
  store/        # 全局状态（AppStorageV2 单例）
  pages/        # 隧道列表 / 编辑 / 详情
  components/   # 复用 UI 片段
  backend/      # ArkTS 侧隧道控制（对应上游 Backend/Tunnel 抽象）
  vpnability/   # VpnExtensionAbility 实现（type: vpn）
```

注意：仓库内**没有 `hvigorw` 脚本**，但 DevEco Studio 内置工具链支持命令行编译（见下节）；
预览/调试/真机运行仍在 **DevEco Studio** 中进行；`local.properties`（SDK 路径）不入库。

## 上游移植映射（WireGuard-Android → 本项目）

上游结构：`tunnel/`（可复用库：配置解析 + 后端 + 加密）+ `ui/`（Android 界面）。

| 上游（`~/LibSource/WireGuard-Android`） | 本项目 | 说明 |
|---|---|---|
| `tunnel/.../config/{Config,Interface,Peer,Attribute,InetAddresses,InetNetwork,InetEndpoint,ParseException,BadConfigException}.java` | `entry/src/main/ets/config/` | **纯字符串/二进制解析，无平台依赖 → 最适合先做，且能 100% 本地单测** |
| `tunnel/.../crypto/{Key,KeyPair,KeyFormatException}.java` | `entry/src/main/ets/crypto/` | base64/hex 编解码、公私钥格式与校验；**纯逻辑** |
| `tunnel/.../crypto/Curve25519.java` | `entry/src/main/ets/crypto/`（薄封装 `cryptoFramework`） | 平台原语 → 只做薄封装，列真机验证清单 |
| （协议中内联的 BLAKE2s / keyed-BLAKE2s、HKDF、ChaCha20-Poly1305） | `entry/src/main/ets/crypto/`（**自实现**） | 见「核心设计决策 3」，框架不给 BLAKE2s |
| `tunnel/.../android/backend/{Backend,GoBackend,WgQuickBackend,Tunnel,Statistics,BackendException}.java` | `entry/src/main/ets/backend/` + `ets/vpnability/` | 上游走 `VpnService`；鸿蒙走 `VpnExtensionAbility` + `vpnExtension` API |
| `tunnel/tools/{libwg-go,wireguard-tools,ndk-compat,elf-cleaner}`（C/Go + CMake） | 新增 `entry/src/main/cpp/` | 必须用 OHOS NDK 交叉编译；数据面（tun fd ↔ UDP）在 C/C++ 侧 |
| `tunnel/.../android/util/{RootShell,SharedLibraryLoader,ToolsInstaller}.java` | **裁剪**（无对应物） | 鸿蒙无 root、无 `wg`/`wg-quick` 命令行工具、无动态加载本地库需求 |
| `ui/src/main/java/.../{activity,fragment,viewmodel,model,configStore,preference,widget,util}` | `entry/src/main/ets/{pages,components,viewmodel,model,store,repo,util}` | 界面重写（ArkUI），非逐行翻译 |
| `ui/src/main/res/**` | `entry/src/main/resources/**` | 布局→ArkUI 声明式；图标/字符串/颜色资源按鸿蒙规范重做 |

## 命令行构建（Makefile 封装，agent 可直接编译验证）

已封装进根目录 `Makefile`（底层调用 DevEco Studio 内置工具链，无需打开 IDE）：

```bash
make build        # 编译 + 打包 debug HAP（未签名，产物在 entry/build/default/outputs/）
make test         # 跑 LocalUnit 单测（hypium，entry/src/test）
make ohpm-install # 拉取 ohpm 依赖（首次 make test 前必需；test 目标已内置缺失检测）
make help         # 列出全部目标
```

- 签名需在 DevEco Studio 里配置后才可装真机；未签名时 SignHap WARN 跳过，可忽略
- 环境变量（DEVECO_SDK_HOME / JAVA_HOME / PATH）由 Makefile 自动设置，无需手动导出
- 若本机 DevEco Studio 不在 `/Applications/DevEco-Studio.app`，改 Makefile 顶部路径
- ⚠️ **`make test` 的假绿**：hypium 用例失败时 hvigor 仍可能打印 `BUILD SUCCESSFUL`，
  只有日志里有 `Error in <case>`。判断测试是否真的通过必须：
  `make test 2>&1 | grep -c "Error in"` 为 0（Makefile 的 test 目标已内置该校验）。

## 核心设计决策

> 项目早期填充。以下 1–4 条已由 SDK/官方文档核实（见括号内证据），动手前请遵守。

### 1. 数据面必须在原生层，ArkTS 只做控制面（关键，决定整个架构）

官方三方 VPN 能力只负责**创建虚拟网卡 + 配置路由**，「连接隧道过程及内部连接的协议需要应用内部自行实现」
（证据：`net-vpnExtension.md` 简介）。API 事实（证据：`$SDK/ets/api/@ohos.net.vpnExtension.d.ts`）：

- `vpnExtension.createVpnConnection(context)` → `VpnConnection`
- `vpnConnection.create(vpnConfig: VpnConfig): Promise<number>` —— **返回值为虚拟网卡 tun fd**
- `vpnConnection.protect(socketFd: number)` —— 保护隧道 socket，使其流量不被 VPN 自身路由
- `vpnConnection.generateVpnId()` / `destroy()` / `destroy(vpnId)` / `protectProcessNet()`
- **没有任何 ArkTS 级的 tun 读写接口** → tun fd 必须交给 C/C++ 侧用 `read`/`write` 处理
- 必须声明 `extensionAbilities` 中 `"type": "vpn"` 的扩展 Ability；`startVpnExtensionAbility(want)`
  首次连接会弹系统授权框；**系统同时只允许一条 VPN 连接**，重复启动会被拒绝

因此数据面任务（wireguard-go 或自研隧道）交叉编译为 `.so`，通过 NAPI 暴露给 ArkTS。
官方可运行参考：`applications_app_samples` 的
[VPNControl_Case](https://github.com/openharmony/applications_app_samples/tree/master/code/DocsSample/NetWork_Kit/NetWorkKit_NetManager/VPNControl_Case)
（`entry/src/main/cpp/napi_init.cpp`：两个线程分别做 tun→UDP 与 UDP→tun 转发）。

### 2. 权限与可见性边界（已核实，早于编码确认）

| 能力 | 权限 | 结论 |
|---|---|---|
| 三方 VPN（`VpnExtensionAbility`） | 仅 `ohos.permission.INTERNET`（`system_grant` + `normal`） | ✅ 普通应用可用，声明即免弹窗 |
| 系统 VPN 管理 `@ohos.net.vpn` | `ohos.permission.MANAGE_VPN`（`system_grant` + **`system_basic`**） | ❌ 普通应用拿不到，**不要走这条路** |

（证据：`$SDK/toolchains/lib/PermissionDefinitions.json` + 官方 `net-vpnExtension.md`）

⚠️ 另有：`"type": "vpn"` 在老版本 SDK 的 `toolchains/modulecheck/module.json` 里缺失，
需手动补枚举并清缓存；**本机 SDK 6.1.1/API 24 已包含 `"vpn"` 枚举，无需补丁**（已核实）。

### 3. 分层要适配「本地单测平台 API 是空桩」（重要，会反向决定模块划分）

`src/test` 的本地单测里所有 `@kit` API 都是空桩——不抛错、返回空数据
（实测 `cryptoFramework.createMd('MD5')` 返回 0 字节摘要、AES 解密返回空数组）。所以：

- **纯算法/纯逻辑要自实现或依赖注入**（可 100% 本地测）：wg-quick 解析、base64/hex 编解码、
  BLAKE2s、HKDF、配置 diff、路由表计算 —— 全部放进不 import `@kit` 的纯 ArkTS 模块；
- **平台原语只做成薄封装**（几行 `cryptoFramework`/`vpnExtension` 调用）并列进真机验证清单：
  X25519 协商、ChaCha20-Poly1305、Keystore 私钥、socket、tun fd 读写。

**SDK 事实（已核实）**：`@ohos.security.cryptoFramework` 提供 `ChaCha20`（含 Poly1305 模式）、
`X25519`、`HKDF`；**不提供 BLAKE2s**（ArkTS 与 NDK `CryptoArchitectureKit/` 均无，消息摘要只有 SHA256/MD5/SHA3）。
WireGuard 协议强依赖 BLAKE2s（含 keyed 模式做 MAC）→ **必须自实现或移植参考 C 实现**，
且正好落在「纯算法 → 可本地单测」这一类。

### 4. ArkUI 架构约定

1. **路由栈即历史栈**：页面导航用 `Navigation` + `NavDestination`，隧道详情页 = push 一个节点页，
   系统返回 = pop，兄弟切换 = replace，面包屑 = popTo。单栏应用显式 `.mode(NavigationMode.Stack)`。
2. **状态管理用 V2 范式**（`@ObservedV2`/`@Trace`/`@Local`）；页面间共享状态走
   `AppStorageV2.connect` 单例，勿靠路由 param 传大对象。
   （若共享状态是**普通类单例**而非 `@ObservedV2`：在单例上加 `addListener/removeListener`，
   页面用 `@Local version: number` 自增触发重渲。）
3. **隧道状态是「外部真源」**：连接状态由 VpnExtensionAbility/后端驱动，UI 只订阅快照。
   单例 store 暴露 `snapshot` + `subscribe`，避免「UI 认为在连、系统已断」的双真源。

<!-- 在此补充项目特有决策（数据流/同步策略/渲染规则等） -->

## 开发资料速查

### 给 agent 的资料使用规则（重要）

1. **搜索优先用 Context7**：华为官方 Guides/References 已被 Context7 收录（官方源，
   trustScore 10），支持语义搜索、返回带来源的聚焦片段，比读全页省 context：
   - 指南库：`/websites/developer_huawei_consumer_cn_doc_harmonyos-guides`
   - API 参考库：`/websites/developer_huawei_consumer_cn_doc_harmonyos-references`
   （用法见 context7 skill：先 resolve 再 query，每个查询聚焦单一主题）
2. **精读原文：华为文档站取不到正文，走下面三条正路**（2026-09 实测：
   该站是 JS 渲染的 SPA，裸 URL 用 `curl` 永远返回 200 空壳，**加 `.md` 后缀已全站 404**，
   不能用 HTTP 状态码判断页面是否存在）：
   1) **SDK d.ts（第一手事实来源，优先级最高）**：
      `$DEVECO_SDK_HOME/default/openharmony/ets/api/*.d.ts`（API/枚举）、
      `ets/kits/@kit.*.d.ts`（kit 导出清单）、
      `toolchains/id_defined.json`（`sys.color.*` / `sys.media.*` 合法资源名）、
      `toolchains/lib/PermissionDefinitions.json`（权限 grantMode/availableLevel）。
      **不确定某 API/枚举是否存在时先 grep d.ts**，别猜。
      NDK 头文件在 `default/openharmony/native/sysroot/usr/include/`。
   2) **OpenHarmony 官方 docs 仓库 raw（含 ArkTS 示例、算法规格表）**：
      `https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/<子系统>/<主题>.md`，
      例 `network/net-vpnExtension.md`（**本项目必读**）、
      `security/CryptoArchitectureKit/crypto-sym-encrypt-decrypt-spec.md`（能力/算法支持矩阵查 `*-spec.md`）。
   3) **Context7**（见上）。
3. **设计新功能前先查权限级别**：`toolchains/lib/PermissionDefinitions.json` 里
   `system_grant`+`availableLevel: normal` = 声明即可、**免弹窗**（如 `ACCESS_BIOMETRIC`、`PRIVACY_WINDOW`）；
   `system_basic` = **普通应用拿不到**（如 `READ_PASTEBOARD`、`MANAGE_VPN`）→ 设计阶段就该避开。
4. **只查深链，不查目录页**。`docs/harmonyos-resources.md` 里的 URL 用于**人工/浏览器查看**，
   agent 取正文请用上面第 2 条的 1)/2)。
5. **版本对齐**：查 API 时注意页面中 "起始版本" 标注；本项目是 API 24。
   ArkTS 状态管理有 V1/V2 两代范式，优先 V2。
6. 完整分类清单（含一句话摘要 + 何时查阅）：
   **[docs/harmonyos-resources.md](docs/harmonyos-resources.md)**

### 任务 → 资料分区索引

| 我要做什么 | 去看 resources.md 哪一节 |
|---|---|
| **实现 VPN 隧道 / 虚拟网卡 / 路由** | **VPN 与网络隧道（本项目核心）** |
| **写 C/C++ 原生层、交叉编译 .so** | **NDK / NAPI 原生开发** |
| **密钥交换 / AEAD / 摘要 / 私钥存储** | **加解密与安全** |
| 发 HTTP 请求、socket | 网络 |
| VPN 常驻通知、保活 | 通知与后台任务 |
| 导入 .conf 文件、申请权限 | 文件选择与权限申请 |
| 新建页面 / 写 UI 布局 / 用组件 | ArkUI 组件与声明式 UI |
| 组件状态、父子通信、页面刷新 | 状态管理 |
| 多页面跳转、传参、返回栈 | 路由与导航 |
| 存数据（配置/KV/SQLite/文件） | 数据持久化 |
| 打日志、调试、排查崩溃 | 日志与调试 |
| 写单元测试 / UI 测试 | 测试 |
| 签名、打包、真机运行 | 签名、构建与发布 |
| 不懂 ArkTS 与 TS 的差异 | ArkTS 语言 |
| Ability 生命周期、应用模型 | 应用模型（Ability） |

## 已知坑（随开发积累）

当第一次做错了，后续修复时，需要总结一些经验写入这里，避免后续继续踩坑。

### 鸿蒙通识

- 华为文档站是 SPA：裸 URL 用 curl 永远返回 200 空壳 HTML，**不能用 HTTP 状态码判断页面存在**；
  且 `.md` 后缀技巧已全站 404（2026-09 实测）→ 取正文走 SDK d.ts / OpenHarmony docs raw。
- **测试假绿**：hypium 用例失败时 hvigor 仍可能打印 `BUILD SUCCESSFUL`，只有日志里有 `Error in <case>`。
  → 判测试通过必须 `make test 2>&1 | grep -c "Error in"` == 0（Makefile 的 test 目标已内置校验）。
- **首次 `make test` 报 `Failed to resolve OhmUrl ... "@ohos/hypium"`**：根因是缺 `oh_modules` → `make ohpm-install`。
- **手写骨架缺 `entry/oh-package.json5`** 时报 `OhPackageLoader.processModuleDependencyMap →
  ERR_INVALID_ARG_TYPE: The "data" argument must be of type string ... Received undefined`——
  错误信息完全看不出真实原因。同级还需 `entry/{build-profile.json5,hvigorfile.ts,obfuscation-rules.txt,.gitignore}`。
- **本地单测里所有 `@kit` 平台 API 都是空桩**：不抛错但返回空数据（`createMd('MD5')` 返回 0 字节摘要、
  AES 解密返回空数组）→ 纯算法必须自实现/依赖注入才能本地测，平台原语列真机清单（见「核心设计决策 3」）。
- **`buffer.from(str,'utf-8')` 返回 `Buffer`，不能直接当 `Uint8Array` 用**（本地 mock 下 `byteOffset` 还是伪造值）
  → 用 `new Uint8Array(buffer.from(s,'utf-8').buffer)`。
- **`sys.media.*` / `sys.color.*` 里看似通用的名字可能是 private**：如 `ohos_ic_public_settings`
  在 `toolchains/id_defined.json` 中不存在（编译报 Unknown resource name）→ 先去该文件 grep 合法符号。
- **模板工程不要带他人的签名材料绝对路径**：`build-profile.json5` 留 `"signingConfigs": []` 即可正常构建
  （只 WARN），签名由用户在 DevEco Studio 里配置。
- **ArkTS 严格模式编译坑**：禁 `as const`；禁 `unknown` 类型转换（错误对象
  用 `as BusinessError`，`import { BusinessError } from '@kit.BasicServicesKit'`）；interface 对象
  禁 `obj['key']` 索引访问（先 `as Record<string, Object>`）；禁构造参数属性 `constructor(private x)`；
  对象字面量必须对应显式类型；字符串不能直接传枚举参数（用 `http.RequestMethod.GET`）。
- **组件类型/枚举不是全从 @kit.ArkUI 导出**：`NavPathStack`/`Navigation` 等是全局声明（不 import）；
  `TextInputType` 实为 `InputType`。不确定时 grep `component/*.d.ts`（组件声明）与 `kits/@kit.*.d.ts`。
- **Navigation 默认显示空标题栏+空工具栏并占位**：`hideTitleBar`/`hideToolBar` 默认均为 false，
  即使不配置也会占位压缩内容区（实测 ~112vp）→ 单栏应用应显式 `.hideTitleBar(true).hideToolBar(true)`。
- **Navigation 路由表必须绑组件内 @Builder 方法**（`.navDestination(this.PageMap)`）；
  `pushPath({name})` 不传 param 时运行时是 `undefined`，若透传给 `@Param param: object` 会类型不匹配 → **页面空白**。
- **未绑定组件的 Scroller 调用 `currentOffset()`/`scrollTo()` 会崩溃**（API 23 才有 `offset()` 安全版）
  → 对未绑定 scroller 的调用要按形态分支跳过。
- **`MenuItemOptions.content` 只接受 ResourceStr**（不能传 CustomBuilder）；**Menu 长按菜单**用
  `bindContextMenu(ResponseType.LongPress)`，半模态表单用 `bindSheet`。

### 本项目特有（WireGuard / VPN 方向）

- **`MANAGE_VPN` 是 `system_basic`**：看到 `@ohos.net.vpn` 系列 API 别急着用，普通应用只能用
  `@ohos.net.vpnExtension`（三方 VPN 能力，只需 `INTERNET`）。
- **`VpnConnection.create()` 的返回值是 tun fd，且 ArkTS 侧没有读写它的接口**：
  不要尝试在 ArkTS 里 `read/write` 虚拟网卡；需要 NAPI + 原生线程。
- **`protect(socketFd)` 不可省**：不保护隧道 socket 会导致隧道自身流量被卷进 VPN 形成环回。
- **系统同时只允许一条 VPN 连接**：启动接口被拒时不要重试，应提示用户先断开现有 VPN
  （对应上游「其他 VPN 应用正在运行」的提示）。
- **调用 `startVpnExtensionAbility` 的应用进程退出 → 系统会主动断开 VPN**（官方「服务生命周期」）：
  保活/重连策略要基于这个事实设计，不能假设后台常驻。
- **BLAKE2s 不在鸿蒙密码框架内**（ArkTS 与 NDK 都没有）：WireGuard 握手/传输密钥派生依赖它，
  必须自实现；不要试图用 HMAC-SHA256 顶替（协议不兼容，无法与对端互通）。
