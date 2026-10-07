# AGENTS.md — WireGuard（HarmonyOS）

> 本文件是 AI coding agent 的项目入口。先读「项目事实」，再按任务查「资料速查」。
> 完整资料清单见 [docs/harmonyos-resources.md](docs/harmonyos-resources.md)。

## 开发流程规范（Spec 先行，写代码前必读）

本项目采用 **spec 驱动开发**，严格按以下顺序推进，**不允许跳过文档直接写代码**：

1. **`specs/*.md` —— 功能规格（先写）**
   - 从**用户角度**描述需求：功能是什么、用户怎么操作、看到什么、边界情况如何表现。
   - 每个功能一份 spec（如 `specs/tunnel-list.md`、`specs/tunnel-import.md`）。
   - **spec 只描述需求和功能设计，禁止出现任何技术方案**：包括但不限于平台 API 名、
     权限常量名、三方库名、类名/模块名、架构分层、存储方式、算法选型、测试保障方式——
     这些一律放 `docs/decisions/`。
   - spec 中允许涉及平台的只有两类内容：**用户可感知的系统行为**（如系统弹出的授权框）；
     **「待验证事项」中对平台能力的疑问**（用行为语言描述，不得引用 API/组件名）。
2. **`handbook/*.html` —— 用户使用说明书（与 spec 配套）**
   - 面向最终用户的详细操作手册，**带 SVG 截图**（用内联 SVG 模拟界面截图，不依赖真机截图）。
   - 与对应 spec 保持同步：spec 描述的功能必须能在 handbook 中找到对应操作说明。
3. **`docs/decisions/*.md` —— 关键技术决策**
   - 记录「为什么这么做」：方案选型、取舍理由、被否决的备选方案（参照 ADR 风格）。
   - 与代码强相关的架构决策（如数据面分层、加密算法选型）都放这里。
4. **最后才写代码。**

**迭代规则**：后续任何功能新增/变更，**必须先改 spec 与 handbook，再改代码**；
spec / handbook 是验收基准，代码行为与 spec 冲突时以 spec 为准（若 spec 本身有误，先修 spec）。
技术方案变更时同步更新 `docs/decisions/`。

## 项目事实

| 项 | 值 |
|---|---|
| 应用 | WireGuard |
| 定位 | **WireGuard VPN 客户端的 HarmonyOS 原生重写**：ArkTS + ArkUI 声明式 UI + `VpnExtensionAbility`，功能对齐上游 WireGuard-Android |
| 数据源 | 本地用户配置（wg-quick `.conf` 文本 / 二维码 / 手动编辑），**无后端服务**；配置与私钥仅存本机 |
| 上游参考实现 | `~/LibSource/WireGuard-Android`（tag `1.0.20260315-1-ge7b3a3c1`） |
| 设计文档 | **[specs/*.md](specs/)**（功能规格）+ **[handbook/*.html](handbook/)**（用户说明书）+ **[docs/decisions/*.md](docs/decisions/)**（技术决策 0001–0008）+ **[docs/dev-contracts.md](docs/dev-contracts.md)**（模块间 API 单一真源）；完整索引见 [docs/harmonyos-resources.md](docs/harmonyos-resources.md) |
| 验收文档 | **[docs/device-verification.md](docs/device-verification.md)**（真机验证清单）+ **[docs/interop-testing.md](docs/interop-testing.md)**（与 Linux `wg` 互操作验收） |
| 实现状态 | 数据面（C：BLAKE2s/HMAC/ChaCha20-Poly1305/X25519 + Noise IK 握手 + 传输 + 定时器 + NAPI + 启动 KAT）与全部功能页面（列表/详情/编辑器/导入/设置/日志/隐私）已实现；本地单测 117 例全绿、`make build` 可打包签名 HAP；**真机与互操作验收未完成**（见验收文档；真机已发现并修掉 1 处平台限制，见 [docs/decisions/0008](docs/decisions/0008-arkts-x25519-self-implemented.md)） |
| bundleName | `me.graycarl.wireguard` |
| 平台 | HarmonyOS（纯鸿蒙，`runtimeOS: HarmonyOS`，非兼容模式） |
| SDK | 6.1.1(24)，target/compatible 均为 24 |
| 设备 | phone |
| 调试手机 | 真机无线调试固定 IP **`192.168.50.30`**（端口仍随机，用 `scripts/hdc-wifi` 自动发现，见「真机无线调试」） |
| 语言/UI | ArkTS + ArkUI 声明式开发 |
| 构建系统 | hvigor（modelVersion 6.1.1） |

## 仓库结构

业务代码已实现（详见下方目录与 [docs/dev-contracts.md](docs/dev-contracts.md)）：

```
AppScope/            # 应用级配置（app.json5: bundleName/版本/图标）
entry/               # 主模块（type: entry）
  src/main/ets/
    entryability/    # EntryAbility.ets（UIAbility 入口；初始化 Logger/主题/AppStore）
    entrybackupability/
    config/          # wg-quick 解析/序列化/校验（纯 ArkTS，可本地单测）
    crypto/          # base64/hex、Key/KeyPair、BLAKE2s、HKDF（镜像实现，KAT 对照）
                     # + X25519 纯 ArkTS 实现（RFC 7748 KAT；cryptoFramework by-spec 不可用，见决策 0008）
    model/           # 隧道领域模型（TunnelState/PeerStats/Tunnel）
    repo/            # tunnels.json 持久化（FileIO 注入 + TunnelRepository，纯逻辑）
    store/           # AppStore（UI 唯一入口）+ RecordMapper（Config ↔ TunnelRecord）
    backend/         # Backend（单激活互斥/切换回滚）、VpnController（vpnExtension 薄封装+错误映射）、
                     # AuthGuard（锁屏认证）、PrivacyMode（防截屏）、IpcProtocol（公共事件）
    platform/        # FsFileIO（原子写）、PreferencesStore（主题）、NativeBridge（NAPI 薄封装）
    util/            # Logger/Format/Toast/Clipboard/FileUtil/RouteParams/TunnelDisplay（尽量纯，可单测）
    services/        # ImportService/ImportLogic（文件·zip·二维码·图片二维码导入）
    components/      # 复用 UI 片段（列表项/开关/卡片/应用过滤/命名对话框等）
    pages/           # Index（Navigation 宿主）/ 列表 / 详情 / 编辑器 / 设置 / 日志 / 扫码 + RouteStack
    vpnability/      # WgVpnAbility.ets（VPN 进程：建虚拟网卡、下发数据面、发公共事件）
  src/main/cpp/          # C 数据面（原语/握手/传输/定时器/NAPI/KAT/hosttest，见 docs/decisions/0001-0002）
  src/main/module.json5   # abilities、vpn extensionAbility、requestPermissions(INTERNET/CAMERA/PRIVACY_WINDOW/ACCESS_BIOMETRIC)
  src/main/resources/     # base/dark 资源（string/color/float/media）
  src/test/               # 本地单测（hypium，跑在宿主 JVM/Node 模拟环境）
  src/ohosTest/           # 设备侧集成测试
build-profile.json5  # 应用级构建配置（products/签名/SDK 版本）
oh-package.json5     # 依赖声明（devDeps: hypium/hamock；entry 模块另有 libentry.so 本地依赖）
specs/               # 功能规格（用户视角，写代码前必须先写，见「开发流程规范」）
handbook/            # 用户使用说明书（HTML + 内联 SVG 截图）
docs/                # 资料索引、decisions/（技术决策）、dev-contracts.md（模块 API 单一真源）、
                     # device-verification.md（真机清单）、interop-testing.md（互操作用例）
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
| （协议中内联的 BLAKE2s / keyed-BLAKE2s、HKDF、ChaCha20-Poly1305） | BLAKE2s/HKDF 镜像实现在 `entry/src/main/ets/crypto/`（**自实现**，进本地单测）；正式协议实现在 `entry/src/main/cpp/` | 见「核心设计决策 3」与 [docs/decisions/0002](docs/decisions/0002-handshake-in-native-c.md)：框架不给 BLAKE2s；原语只在 C 层维护一份，ArkTS 侧仅作 KAT 对照 |
| `tunnel/.../android/backend/{Backend,GoBackend,WgQuickBackend,Tunnel,Statistics,BackendException}.java` | `entry/src/main/ets/backend/` + `ets/vpnability/` | 上游走 `VpnService`；鸿蒙走 `VpnExtensionAbility` + `vpnExtension` API |
| `tunnel/tools/{libwg-go,wireguard-tools,ndk-compat,elf-cleaner}`（C/Go + CMake） | 新增 `entry/src/main/cpp/` | 必须用 OHOS NDK 交叉编译；数据面（tun fd ↔ UDP）在 C 侧，**自研而非移植 libwg-go**（见 [docs/decisions/0001](docs/decisions/0001-dataplane-self-implemented-c.md)） |
| `tunnel/.../android/util/{RootShell,SharedLibraryLoader,ToolsInstaller}.java` | **裁剪**（无对应物） | 鸿蒙无 root、无 `wg`/`wg-quick` 命令行工具、无动态加载本地库需求 |
| `ui/src/main/java/.../{activity,fragment,viewmodel,model,configStore,preference,widget,util}` | `entry/src/main/ets/{pages,components,viewmodel,model,store,repo,util}` | 界面重写（ArkUI），非逐行翻译 |
| `ui/src/main/res/**` | `entry/src/main/resources/**` | 布局→ArkUI 声明式；图标/字符串/颜色资源按鸿蒙规范重做 |

## 命令行构建（Makefile 封装，agent 可直接编译验证）

已封装进根目录 `Makefile`（底层调用 DevEco Studio 内置工具链，无需打开 IDE）：

```bash
make build        # 编译 + 打包 debug HAP（产物在 entry/build/default/outputs/；本机配好签名即出 *-signed.hap）
make test         # 跑 LocalUnit 单测（hypium，entry/src/test）
make ohpm-install # 拉取 ohpm 依赖（首次 make test 前必需；test 目标已内置缺失检测）
make sign-import  # 把 DevEco Studio 写进 build-profile.json5 的签名材料搬到本机文件并还原之
make sign-status  # 查看签名材料来源（仓库是否干净 / 材料文件是否存在）
make help         # 列出全部目标
```

- **签名材料不入库**：`build-profile.json5` 里 `app.signingConfigs` 恒为 `[]`（入库的是 products/
  SDK/buildModeSet/modules），本机材料放**已 gitignore** 的 `signing-config.local.json`，由
  `hvigorfile.ts` 经 `config.ohos.overrides.signingConfig` 注入（详见 AGENTS 已知坑）。
  未配签名时 SignHap WARN 跳过、只产出 unsigned HAP，不影响编译验证。
- 在 DevEco Studio 里改签名（Project Structure > Signing Configs > Apply）会把 `build-profile.json5`
  写脏 → 跑一次 `make sign-import` 搬运 + 还原，仓库保持零签名材料。
- 环境变量（DEVECO_SDK_HOME / JAVA_HOME / PATH）由 Makefile 自动设置，无需手动导出
- 若本机 DevEco Studio 不在 `/Applications/DevEco-Studio.app`，改 Makefile 顶部路径
- ⚠️ **`make test` 的假绿**：hypium 用例失败时 hvigor 仍可能打印 `BUILD SUCCESSFUL`，
  只有日志里有 `Error in <case>`。判断测试是否真的通过必须：
  `make test 2>&1 | grep -c "Error in"` 为 0（Makefile 的 test 目标已内置该校验）。

## 真机无线调试（hdc 端口随机，别手抄）

鸿蒙手机「无线调试」的端口**每次开启 / 重启 / 换 Wi-Fi 都会变**，官方 UI 不给固定；设备上还常有
3~5 个「TCP 能连上但不是 hdc」的开放端口，`hdc tconn` 打上去会**挂 30~60s** 才返回（不是网络慢、
也不是扫描慢，别被带偏）。已封装自动发现（脚本随 `harmonyos-project-init` skill 分发，**本项目不落副本**，
升级 skill 即生效）：

- **本机调试用手机 IP 固定为 `192.168.50.30`**（已做地址绑定），直接把它传给脚本即可；
  但**端口仍每次开启/重启/换 Wi-Fi 都会变**，所以照旧走脚本、别手抄端口。

```bash
/Users/hongbo/.pi/agent/skills/harmonyos-project-init/scripts/hdc-wifi 192.168.50.30     # 常用：指定本机调试手机（IP 固定，端口由脚本发现）
/Users/hongbo/.pi/agent/skills/harmonyos-project-init/scripts/hdc-wifi                   # 热路径 ~1s：记住上次 IP:端口，命中即连
/Users/hongbo/.pi/agent/skills/harmonyos-project-init/scripts/hdc-wifi --port 5555       # 配 `hdc tmode port 5555` 的固定端口模式（若机型支持固定端口）
```

- 只有端口变了才扫描：并发扫 25000-65535（1024 并发 / 0.25s，约 10s）+ 逐个带超时验证 → 冷启动约 24s。
- **别**为了更快把扫描并发调到 4096/0.12s：实测 4 万个端口一个都扫不到（SYN 被设备丢弃）。
- 依赖 bash≥3.2 / python3≥3.9 / DevEco 自带 hdc（脚本自动定位，`HDC=` 可覆盖），
  不需要 brew 装任何东西（也无需 timeout/nc/jq，无需 sudo）。
- 首次无线连接需在手机上点「允许」授权；设备侧 ICMP 常被封，所以脚本的 ping 只作提示、不作判据。

## 核心设计决策

> 以下 1–4 条为 SDK/官方文档核实过的架构约束（见括号内证据），动手前请遵守。
> 完整技术决策（数据面自研、握手分层、持久化、进程通信、生命周期、单激活、测试策略）见
> [docs/decisions/0001–0007](docs/decisions/)；模块间 API 的单一真源见
> [docs/dev-contracts.md](docs/dev-contracts.md)（实现与契约冲突时先改契约再改代码）。

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
  ChaCha20-Poly1305、Keystore 私钥、socket、tun fd 读写、锁屏认证、防截屏。
  （X25519 **已因平台限制改为纯 ArkTS 自实现**并进本地 KAT，不再属于平台原语，见决策 0008。）

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
- **`build-profile.json5` 入库、签名材料不入库**：该文件必须提交（products/SDK/buildModeSet/modules 是
  构建单一真源），但 `app.signingConfigs` 是 DevEco Studio 写进去的**本机绝对路径 + 加密口令**，提交了
  别人 clone 下来必错。本项目做法：仓库里留 `"signingConfigs": []`，材料放 gitignore 的
  `signing-config.local.json`，再由 `hvigorfile.ts` 注入；DevEco GUI 写脏后跑 `make sign-import` 搬运还原
  （脚本 `scripts/sign-config.mjs`）。
- **hvigor 注入签名配置的位置是 `config.ohos.overrides.signingConfig`，不是顶层 `overrides`**：
  `hvigorfile.ts` 导出 `{ system, plugins, config: { ohos: { overrides: {...} } } }`
  （hvigor 内部 `parseConfig(node, defaultExport.config)` → `getConfigOpt().getObject('ohos')`）。
  该对象**只允许 `material` / `type` 两个键**——多带 `name` 直接 `00303038 Schema validate failed`
  （报错 instancePath `/overrides/signingConfig`，params 里会列出 allowedValues，好在报错指向 hvigorfile.ts，
  但不说清是哪个字段多余）。生效判据：日志出现 `Finished :entry:default@SignHap` + 产出 `*-signed.hap`
  （反之是 `Will skip sign 'hos_hap'`）。口令必须是 DevEco 加密后的十六进制串（密钥来自 `~/.ohos/config/material/`，
  hvigor 用 `DecipherUtil` 解密），**换成明文口令会报 INVALID_DATA**。
- **改 hvigorfile.ts 后 hvigor 会重新读取签名配置**：`SignHap` 不再 UP-TO-DATE；删掉 `*-signed.hap` 再
  `make build` 即可强制重签，比 `make clean` 全量重建快得多。
- `js-apis-*` 旧命名页面多为子页面索引（几 KB 的链接列表），
  `arkts-apis-*` 新命名页面才有完整 API 正文。
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
  排查空白页优先级：路由表形式 → param 透传 → NavDestination 是否包在子页组件内。
- **Navigation 内容区安全区/高度规则**：Navigation 自身全屏但**内容区布局在安全区内**（顶部避让状态栏、
  底部避让手势条，底部手势条区域露 Navigation 背景）；Navigation 默认 `expandSafeArea([SYSTEM],TOP/BOTTOM)`
  只是绘制扩展。排查底部留白时不要怀疑子组件 `height('100%')` 失效——先量 Navigation/内容区实际高度
  （`onAreaChange` 打日志），根因常是标题栏/工具栏占位或安全区。
- **正文延伸到屏幕底用 Navigation 级 ignoreLayoutSafeArea**：`expandSafeArea` 仅扩展绘制区域、布局不变，
  透明背景组件加它无视觉效果、滚动内容也不会延伸（旧方案在页面 Column 上加它无效）；正确做法是
  Navigation 上 `.ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])`
  （API 20+，枚举全局声明免 import），且**前提是标题栏/工具栏已隐藏**，否则无法扩展到非安全区。
- **V2 组件可作 NavDestination 宿主**：官方 Navigation 案例全是 V1（@Component），但 @ComponentV2 文档
  声明与 @Component 行为一致（无 NavDestination 限制），可放心用。
- **LazyForEach 禁用零高度占位项实现折叠**：折叠行若渲染为 `Row().height(0)`，索引↔像素映射非线性，
  fling 穿过折叠块边界时可见窗口单帧跳过上百索引 → 单帧批量创建组件，造成严重滚动抖动
  （症状：含折叠内容多时滚动持续卡顿，日志可见行组件成片重建）。正确做法：数据源只放可见行，
  折叠态记录在全量数组（foldedAncestors），toggle 时过滤重建可见数组 + onDataReloaded（纯数据 O(n)）。
- **应用图标规范**（官方《应用图标》设计指南）：分层资源 background+foreground 均 1024×1024 正方形 PNG，
  不做圆角（系统裁切）；**背景层不允许透明像素**；渐变色方向统一、上浅下深、两端色值差异适度；
  前景主体居中、勿近四角。module.json5 的 `$media:layered_image` 用的是 entry 模块资源（覆盖 AppScope
  同名资源），改图标时 **AppScope 与 entry 两处 + startIcon.png 都要替换**。
- **未绑定组件的 Scroller 调用 `currentOffset()`/`scrollTo()` 会崩溃**（API 23 才有 `offset()` 安全版）
  → 对未绑定 scroller 的调用要按形态分支跳过。
- **菜单组件约束**：`MenuItemOptions.content` 只接受 ResourceStr，不能传 CustomBuilder（编译报
  `Type '() => void' is not assignable to 'ResourceStr'`），`MenuItemAttribute` 也没有 fontColor
  → 长按菜单里删除项做红字需换自定义 Menu 布局，或用普通项 + `labelInfo: '不可恢复'` 警示；
  **Menu 长按菜单**用 `bindContextMenu(ResponseType.LongPress)`，半模态表单用 `bindSheet`。
- **对接第三方 REST API 先查清写操作回显**：部分端点（如 create）有 id 回显但缺完整字段，
  多数（update/move/delete）只有 `{"status":"ok"}` 无回显；本地乐观更新时缺失字段（priority/时间戳等）
  需自行估算，否则下次全量刷新后内容跳变。
- **编辑表单防富文本覆盖**：数据源富文本（如服务器端 markdown→HTML 转换）由别处生成时，简单纯文本
  表单无法编辑富文本。保存时**只提交变更字段**（与纯文本原文比较），未改动的字段不提交，
  避免"纯文本回写覆盖服务器已存富文本"。
- **真机无线调试端口随机，且「看起来能连」的端口不代表是 hdc**：端口每次开启/重启/换 Wi-Fi 都变
  （无规律，实测落在 `3xxxx`~`6xxxx`），官方 UI 不给固定。设备上常有 3~5 个**TCP 能连上但不是 hdc**
  的开放端口，`hdc tconn` 打上去会**挂 30~60s** 才返回（易误判为网络/扫描慢）→ 别手抄端口、别裸调
  `hdc tconn`，用上节「真机无线调试」里的 `scripts/hdc-wifi` 自动发现。
  两个附带坑：① 已连接时 `hdc tconn` 返回 `[Info]Target is connected, repeat operation` 而非
  `Connect OK`，判断是否连上要看 `hdc list targets` 里有没有 `IP:port`；
  ② 设备侧 ICMP 常被封，`ping` 不通不代表不在线。

- **`@Param` + `ForEach` 复用不刷新子组件**（ArkUI 已知限制）：列表项的连接状态/统计不要父→子透传
  （`@Param` 不会随 `ForEach` 复用更新）→ 子组件自订阅 `AppStore`（`@Local` + 变更检测），
  或用 `@ObservedV2` 单例 + `@Trace`。本项目 `components/TunnelSwitch.ets`、`PeerCard.ets`、`ListSelection.ets` 是范例。
- **ArkTS 严格模式 × Navigation 路由**：`pathStack.pushPath({ name, param })` 报
  `arkts-no-untyped-obj-literals`（`NavPathInfo` 是组件声明的 class）→ 用 `new NavPathInfo(name, param)`；
  `@Param param: object = {}` 同样非法 → 用显式类实例（本项目 `pages/RouteStack.ets` 的
  `EmptyParam/EditorParam`，所有页面参数契约集中在那里）。
- **未被引用的 .ets 不会被编译**：新骨架文件（占位页、RouteStack）在接入引用前编译错误不会暴露，
  一旦被 `Index.ets` 引用就集中报错 → 新文件要尽早接入引用并 `make build` 验证。
- **改了依赖声明必须重跑 `make ohpm-install`**：新增 `libentry.so` 本地依赖（或任何 `oh-package.json5` 变更）后
  不重跑，类型声明会退化为 `any`，报错是 `arkts-no-any-unknown`，指向的文件看起来毫不相关（如 NativeBridge.ets）。
- **`sys.media.*` 无设置/齿轮图标，SDK 无 `sys.symbol.*`**：设置入口用文字按钮；图标一律先
  在 `toolchains/id_defined.json` grep 到合法符号再用（已有条目的补充）。
- **userAuth 回调类型是 `IAuthCallback`（`onResult`）**：写成 `instance.on('result', fn)` 编译不过；
  无认证能力设备应在 `getAvailableStatus` 判断后直接放行（本项目 `backend/AuthGuard.ets` 已处理）。

### 本项目特有（WireGuard / VPN 方向）

- **VPN 授权拒绝与「已有 VPN 占用」的错误码**：`VpnConnection.create()` 的 `2203001`（用户未授权）/
  `2203002`（已有其他 VPN）必须分别映射 spec 文案；`startVpnExtensionAbility` 的
  401/16000001/16000002/16000011/16000006/16000050/16200001 归入「无法启动 VPN 服务」。
- **普通应用无法枚举已安装应用**：`getBundleInfo`/`getLauncherAbilityInfo` 需
  `GET_BUNDLE_INFO_PRIVILEGED`（system_basic，拿不到），SDK 也无 `getAllBundleInfo` →
  「应用过滤」对话框固定走空态「未找到可用应用」（spec tunnel-editor.md 已定案）；
  平台开放后只需改 `components/AppCatalog.ets`。
- **自定义公共事件是 UI 进程 ↔ VPN 进程的唯一上行通道**（决策 0004）：事件名
  `me.graycarl.wireguard.event.TUNNEL`，payload 走 `CommonEventPublishData.data`（JSON 字符串），
  **绝不含密钥/配置**；进程内 Emitter/AppStorage 均不可跨进程，不要误用。

- **`externalNativeOptions` 必须放在模块 `build-profile.json5` 的 `buildOption` 内**：放根部会被 hvigor
  schema 拒绝（报错只列 allowedValues，不提示正确位置）。

- **`MANAGE_VPN` 是 `system_basic`**：看到 `@ohos.net.vpn` 系列 API 别急着用，普通应用只能用
  `@ohos.net.vpnExtension`（三方 VPN 能力，只需 `INTERNET`）。
- **`VpnConnection.create()` 的返回值是 tun fd，且 ArkTS 侧没有读写它的接口**：
  不要尝试在 ArkTS 里 `read/write` 虚拟网卡；需要 NAPI + 原生线程。
- **`protect(socketFd)` 不可省**：不保护隧道 socket 会导致隧道自身流量被卷进 VPN 形成环回。
- **系统同时只允许一条 VPN 连接**：启动接口被拒时不要重试，应提示用户先断开现有 VPN
  （该提示为本项目新增文案，上游无对应提示）。
- **调用 `startVpnExtensionAbility` 的应用进程退出 → 系统会主动断开 VPN**（官方「服务生命周期」）：
  保活/重连策略要基于这个事实设计，不能假设后台常驻。
- **BLAKE2s 不在鸿蒙密码框架内**（ArkTS 与 NDK 都没有）：WireGuard 握手/传输密钥派生依赖它，
  必须自实现；不要试图用 HMAC-SHA256 顶替（协议不兼容，无法与对端互通）。
- **`cryptoFramework` 的 X25519「按 spec 生成密钥对」在真机上不可用**：
  `createAsyKeyGeneratorBySpec({algName:'X25519', sk: <bigint>})` 在设备上直接失败，hilog 报
  `Class is not match. expect class: OPENSSL.ED25519.KEYGENERATOR, input class: OPENSSL.X25519.KEYGENERATOR`
  → `generateKeyPairSync()` 抛错（本地单测是空桩，永远测不出来）。
  公钥派生已改为**纯 ArkTS X25519**（`crypto/X25519.ets`，Montgomery ladder + RFC 7748 官方向量本地 KAT）。
  若后续要用平台 X25519：先真机验证该 API，别信 d.ts 声明齐全就当可用。
