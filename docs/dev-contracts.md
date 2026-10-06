# 开发契约（dev-contracts）

> 本文件是**模块间 API 的单一真源**，供并行开发的各任务遵循。只约定接口与数据格式，
> 不重复 specs/decisions 中已有的需求与理由。实现时若与本文件冲突，先改本文件再改代码。
>
> 需求基准：`specs/*.md`；技术决策：`docs/decisions/0001-0007`。

## 1. 分层与目录归属

| 目录 | 职责 | 能否 import `@kit` |
|---|---|---|
| `ets/config/` | wg-quick 解析/序列化/校验（对应上游 tunnel/config） | ❌ 纯模块，进本地单测 |
| `ets/crypto/` | base64、Key/KeyPair、BLAKE2s、HKDF（ArkTS 镜像，KAT 对照） | 仅 `KeyPair` 派生公钥时薄封装 cryptoFramework（见 §4） |
| `ets/model/` | 隧道领域模型与状态枚举 | ❌ |
| `ets/repo/` | tunnels.json 持久化（文件 I/O 注入） | ❌（I/O 接口注入，实现由调用方给） |
| `ets/store/` | 全局状态门面 AppStore + `RecordMapper`（Config↔Record 纯映射） | ✅（AppStore）/ ❌（RecordMapper） |
| `ets/backend/` | 隧道控制 Backend/VpnController、IPC 协议 `IpcProtocol`、AuthGuard、PrivacyMode | ✅ |
| `ets/platform/` | 平台实现：`FsFileIO`、`PreferencesStore`、`NativeBridge` | ✅ |
| `ets/vpnability/` | WgVpnAbility（VPN 进程：建网卡、下发 C 数据面、发公共事件） | ✅ |
| `ets/pages/`、`ets/components/` | UI（ArkUI 声明式） | ✅ |
| `ets/util/` | 日志（Logger，按进程分文件）、格式化（字节/时间） | 日志用 fs/hilog；格式化纯逻辑 |
| `cpp/` | C 数据面全部（原语/握手/传输/定时器/NAPI 胶水） | NDK only |

## 2. 公共规则

- **隧道名**：正则 `^[A-Za-z0-9_=+.-]{1,15}$`，重名判定完全一致（区分大小写）。
- **列表排序**（自然排序）：按「数字段按数值、其余按字符」大小写不敏感比较；
  比较结果为 0 时按原始字符串（区分大小写）再比较。实现放 `config/`（如 `Attribute` 或独立 `Names.ts`），
  签名：`compareTunnelNames(a: string, b: string): number`。
- **错误包装**：面向用户提示统一「<操作>失败：<原因>」或各 spec 列出的固定文案；
  底部提示用 `promptAction.showToast`。
- **文案语言**：全部中文硬编码（本项目仅中文）；需要 spec 固定文案时逐字取自 spec。
- **ArkTS 严格模式**：遵守 AGENTS.md「已知坑」清单（禁 `as const`、禁构造参数属性、
  interface 禁 `obj['key']`、对象字面量需显式类型、错误对象 `as BusinessError` 等）。

## 3. `config/` 契约

镜像上游 `tunnel/.../config/`，纯字符串/二进制解析，错误文案**中文本地化**（spec config-format.md §错误描述方式）：

```ts
export class ParseException extends Error { readonly line?: string; readonly column?: number }
export class BadConfigException extends Error {
  // message 已是完整本地化串，如「在 本地 的 私钥 字段发生了 密钥长度错误 的问题」
  // location: '本地' | '远程'；field?: 中文字段名；reason: 中文原因
}
export class InetNetwork { static parse(s: string): InetNetwork; toString(): string }   // CIDR
export class InetEndpoint { static parse(s: string): InetEndpoint; readonly host: string; readonly port: number; toString(): string }
export class Interface {
  addresses: InetNetwork[]; dnsServers: string[]; dnsSearchDomains: string[];
  listenPort: number;   // 0 = 随机/未设置
  mtu: number;          // 0 = 自动/未设置
  privateKey: string;   // base64；空串 = 未设置
  excludedApplications: string[]; includedApplications: string[];
  toWgQuickString(): string;
}
export class Peer {
  publicKey: string; presharedKey: string;   // base64，空串 = 未设置
  allowedIPs: InetNetwork[]; endpoint: InetEndpoint | null;
  persistentKeepalive: number;               // 0 = 关闭
  toWgQuickString(): string;
}
export class Config {
  interface: Interface; peers: Peer[];
  static parse(text: string): Config;        // 抛 BadConfigException/ParseException
  toWgQuickString(): string;                 // 标准序列化（spec config-format.md §导出序列化）
}
export function isValidTunnelName(name: string): boolean;
export function compareTunnelNames(a: string, b: string): number;
// 「排除局域网」公网段展开/等价判定（spec tunnel-editor.md）：纯逻辑放 config/
export const PUBLIC_NETWORKS_V4: string[];   // 30 条固定网段
export function expandExcludeLan(allowedIPs: string[], dnsServers: string[]): string[];
export function isExcludeLanExpanded(allowedIPs: string[]): boolean;
export function collapseExcludeLan(allowedIPs: string[], dnsServers: string[]): string[]; // 恢复 0.0.0.0/0
```

要点（逐条对齐 spec config-format.md，含 6 条「与上游的差异」修正）：
- 键不区分大小写、值非空、行内 `#` 注释截断、列表逗号分隔、重复键标量取最后/列表累加、
  值首字符不能是空白、未知键/节报错、`DNS` 条目 IP→服务器 / 主机名→搜索域名 / 其他→报 DNS 字段。
- MTU 负值报在 MTU 字段（不修成监听端口）；Included/Excluded 同设报「应用过滤的两种模式不能同时设置」；
  Endpoint 含 `@` 或 `/ ? #` 报「无法解析对端」。
- 导出：`DNS` 行服务器或搜索域名任一非空即输出；列表 `, ` 连接；键名标准大小写。
- 序列化往返必须幂等（parse(serialize(c)) ≡ c），进单测。

## 4. `crypto/` 契约

```ts
export class Key {                          // 32 字节，base64 44 字符（末位 '='）
  static fromBase64(s: string): Key;        // 抛 KeyFormatException（长度错误/含错误字符）
  static generate(): Key;                   // 设备侧 cryptoFramework 随机；本地单测注入 rng
  toBase64(): string; toBytes(): Uint8Array;
}
export class KeyFormatException extends Error { /* 中文：密钥长度错误 / 密钥中含错误字符 */ }
export class KeyPair {
  readonly privateKey: Key; readonly publicKey: Key;
  constructor(privateKey: Key);             // X25519 派生公钥：薄封装 cryptoFramework（设备侧有效，
}                                           //   本地单测为空桩 → 公钥派生不进本地断言，只测格式/异常）
export class Blake2s {                       // 自实现纯 ArkTS，过 RFC 7693 KAT（含 keyed）
  static hash(data: Uint8Array, outLen?: number): Uint8Array;
  static keyedHash(key: Uint8Array, data: Uint8Array, outLen?: number): Uint8Array;
}
export class Hkdf {                          // RFC 5869 with BLAKE2s，过 WireGuard 握手 KAT
  static extract(salt: Uint8Array, ikm: Uint8Array): Uint8Array;
  static expand(prk: Uint8Array, info: Uint8Array, outLen: number): Uint8Array;
}
```

## 5. `model/` + `repo/` 契约

```ts
export enum TunnelState { DOWN = 'down', UP = 'up' }
export class Tunnel { name: string; config: Config }
export interface PeerStats { publicKey: string; rxBytes: number; txBytes: number;
  lastHandshakeMs: number; endpoint: string }
```

**tunnels.json**（应用私有 files 目录；临时文件 + rename 原子写；损坏→备份原文件按空列表处理并记日志）：

```json
{ "version": 1, "tunnels": [ {
  "name": "wg0",
  "interface": { "privateKey": "b64", "addresses": ["10.0.0.2/32"], "listenPort": 0,
    "dnsServers": ["1.1.1.1"], "dnsSearchDomains": ["ex.com"], "mtu": 0,
    "excludedApplications": [], "includedApplications": [] },
  "peers": [ { "publicKey": "b64", "presharedKey": "", "allowedIPs": ["0.0.0.0/0"],
    "endpoint": "vpn.example.com:51820", "persistentKeepalive": 0 } ]
} ] }
```

```ts
export interface FileIO {                    // 注入：store/(UI 进程) 与 vpnability/(VPN 进程) 各自用 fs 实现
  read(path: string): string | null;         // 不存在 → null
  write(path: string, content: string): void; // 原子写由实现保证（tmp+rename）
  rename(src: string, dst: string): void;
}
export class TunnelRepository {              // 纯逻辑，全部可本地单测
  constructor(io: FileIO, dirPath: string);
  load(): Tunnel[];                          // 损坏恢复 + 单条损坏跳过（记日志回调）
  saveAll(tunnels: Tunnel[]): void;
  add / remove / rename / replace(name, config) / findByName …（按 UI 需要）
}
```

## 6. `store/` 契约（UI 唯一入口；普通类单例 + addListener/removeListener，页面 `@Local version` 自增重渲）

```ts
export interface TunnelSnapshot {            // UI 只读快照（决策 0004：外部真源）
  name: string; state: TunnelState;
  peers: PeerStats[];                        // 详情页实时统计
}
export class AppStore {
  static get(): AppStore;                    // 懒初始化单例
  init(context: Context): void;              // EntryAbility 调用（幂等）：Logger、FsFileIO+repo、订阅事件
  records(): TunnelRecord[];                 // 已按 compareTunnelNames 排序（每次 load，量小）
  tunnels(): Tunnel[];                       // 领域对象（同排序）
  configOf(name: string): Config | null;     // RecordMapper.toConfig
  snapshot(name: string): TunnelSnapshot;    // 无 → { state:DOWN, peers:[] }
  activeName(): string | null;               // 真实激活隧道（Backend 事件驱动）
  isToggling(name: string): boolean;         // 开关禁用依据（连接结果确定前）
  toggle(name: string): Promise<string | null>;   // 失败返回「建立/断开连接时出错：<原因>」；null=成功
  create(name: string, config: Config): Promise<string | null>;      // 新建议定文案
  save(originalName: string, name: string, config: Config): Promise<string | null>; // 改名/改配置；已连接先断后重连
  importTunnel(name: string, config: Config): Promise<string | null>; // 「无法导入隧道：<原因>」
  remove(names: string[]): Promise<string | null>;  // 全部成功 null，否则「无法删除 N 项：<原因>」
  addListener(cb: () => void): void; removeListener(cb: () => void): void;
}
```

要点：连接状态/统计只由公共事件驱动（UI 不存意图态）；冷启动全部 DOWN（决策 0004 §3）。

## 7. `backend/` 契约

```ts
export class Backend {                       // 进程内单例（static get()）
  initIpc(context: Context): void;           // createSubscriberSync + subscribeToEvent(TUNNEL_EVENT)
  activeName(): string | null;               // 由事件维护的单一真源（决策 0006）
  setActiveFromEvent(tunnel: string, state: IpcState): void;
  connect(name: string): Promise<void>;      // 若 A 已激活：先 disconnect(A) 再 start(B)；B 失败尽力恢复 A
  disconnect(name: string): Promise<void>;   // stop + 等 down 事件（超时按成功）
  addListener(cb: (payload: IpcPayload) => void): void;
  removeListener(cb: (payload: IpcPayload) => void): void;
}
```

- `VpnController.start/stop(tunnelName)`：vpnExtension 薄封装（Want 带 `parameters.tunnelName`）。
  BusinessError code → spec 固定文案映射：`2203001` 用户未授权 VPN 服务；`2203002` 系统同时只允许一条
  VPN 连接…；`2200001/2200002/2200003/401`（create 路径）无法创建 tun 设备；其余 start 失败 → 无法启动 VPN 服务。
- `AuthGuard.authenticate(title): Promise<AuthResult>`（SUCCESS/FAILED/CANCELLED/ERROR；无认证能力→SUCCESS）。
- `PrivacyMode.setEnabled(context, bool)`；`NativeBridge`（§8 的函数 + `buildConfigJson(Config)` + `describeStartError`）。
- 操作前缀：开启失败「建立连接时出错：<原因>」；关闭失败「断开连接时出错：<原因>」。

## 8. NAPI 契约（`cpp/types/libentry/Index.d.ts`，C 侧实现，双方不得擅自改）

```ts
export interface WgPeerStats { publicKey: string; rxBytes: number; txBytes: number;
  lastHandshakeMs: number; endpoint: string }
/** 创建 UDP socket（VPN 进程用它先调 vpnConnection.protect(fd) 再 startTunnel）。失败 <0 */
export const createUdpSocket: () => number;
/** 启动数据面：绑定 sockFd(listenPort)、解析全部 endpoint（getaddrinfo，同步）、派生密钥、
 *  起 tun↔UDP 转发线程与维护定时器线程。返回 0 成功；<0 错误码（细节用 getLastError）。 */
export const startTunnel: (tunFd: number, sockFd: number, configJson: string) => number;
export const stopTunnel: () => void;          // 幂等：停线程、关 fd、清会话
export const getStats: () => WgPeerStats[];   // 快照；lastHandshakeMs=0 表从未握手
export const getLastError: () => string;      // 如解析失败的主机名
export const getVersion: () => string;        // 如 "wg-harmony 1.0.0"
// configJson 结构：
// { "privateKey": "b64", "listenPort": 0,
//   "peers": [ { "publicKey": "b64", "presharedKey": "", "endpoint": "host:port",
//                "allowedIPs": ["0.0.0.0/0"], "persistentKeepalive": 0 } ] }
```

错误码：`-1` 参数/内部错误；`-2` endpoint DNS 解析失败（getLastError=主机名）；
`-3` socket/bind 失败；`-4` 资源不足/线程创建失败；`-5` 启动 KAT 自检失败。
线程模型：tun→UDP 线程、UDP→tun 线程、维护线程（~250ms 节拍：rekey/reject-after/
keepalive/握手重试与指数退避）。UDP 用非连接 socket + sendto/recvfrom（roaming 换地址不换 socket）。
启动时跑 KAT（blake2s/chacha20poly1305/x25519 编译期内置官方向量），失败返回 -5。
平台相关仅日志与 fd 读写，用宏隔离便于主机侧测试。

## 9. IPC 公共事件契约（决策 0004）

- 事件名：`me.graycarl.wireguard.event.TUNNEL`
- 发布：`commonEventManager.publish(TUNNEL_EVENT, { data: encodePayload(payload) }, cb)`
- payload JSON：`{ "tunnel": "wg0", "state": "up"|"down", "peers": [PeerStats…], "error"?: string }`
  （state 迁移时立即发；up 期间每 1s 发一次统计；down 时 peers 为空数组；`error` 仅「建立失败」时携带，
  供 UI 立即拿到失败原因，不等待超时）
- 订阅：`createSubscriberSync({events:[TUNNEL_EVENT]})` + `subscribeToEvent`；UI 侧 AppStore 订阅并更新快照；
  payload 绝不含密钥/配置。

## 10. WgVpnAbility 流程

onCreate(want)：① 读 `tunnelName`（空→自毁）；② repo 读配置（缺→发 down 事件+自毁）；
③ 构建 VpnConfig（tunnelAddresses=Interface.addresses、dnsAddresses、routes=全部 peers allowedIPs
去重、mtu>0 才设、trusted/blockedApplications 按 included/excluded）——字段名以
`@ohos.net.vpnExtension.d.ts` 为准；④ `createVpnConnection(context).create(cfg)` 拿 tunFd
（失败→「无法创建 tun 设备」事件+自毁）；⑤ `createUdpSocket()`→`protect(sockFd)`；
⑥ `startTunnel(tunFd, sockFd, configJson)`（失败按 §8 错误码映射发事件+自毁）；
⑦ 发 up 事件并起 1s 统计发布定时器。
onDestroy：停定时器 → `stopTunnel()` → `vpnConnection.destroy()` → 发 down 事件。

## 11. UI 路由契约

- 单 `Navigation`（Stack 模式，`hideTitleBar/hideToolBar(true)`，`ignoreLayoutSafeArea` 底部，
  见 AGENTS.md 已知坑）+ `NavPathStack`，路由表绑组件内 `@Builder PageMap`。
- 页面：`pages/Index.ets`（宿主：Navigation + 隧道列表）；
  路由名：`detail`（param=隧道名）、`editor`（param={name?: 隧道名}，无 name=新建）、
  `settings`、`log`、`scan`（扫码页，若用系统默认扫码 UI 则无此页）。
- 详情页返回时若隧道已不存在→自动 pop 回列表（spec tunnel-detail.md）。
- 返回列表/详情时刷新开关状态（aboutToAppear 拉 AppStore 快照）。

## 12. 权限 / 依赖 / 资源约定

- `module.json5` requestPermissions 追加：`ohos.permission.CAMERA`（扫码，user_grant，
  用前动态申请）、`ohos.permission.PRIVACY_WINDOW`（编辑器防截屏，system_grant 声明即用）、
  `ohos.permission.ACCESS_BIOMETRIC`（锁屏认证，system_grant 声明即用）。
- `entry/oh-package.json5` dependencies 追加：`"libentry.so": "file:./src/main/cpp/types/libentry"`。
- 图标：`sys.media.*` 符号必须先在 `$DEVECO_SDK_HOME/default/openharmony/toolchains/id_defined.json`
  grep 到才可用；不确定就用文字按钮。
- 应用过滤：可枚举范围以平台能力为准（大概率普通应用拿不到全量列表 → 空态「未找到可用应用」，
  spec 已定案）；VpnConfig 的 trusted/blockedApplications 字段照常接。

## 13. 构建与测试纪律

- 每个任务完成前必须：`make test`（校验 `grep -c "Error in "` 为 0）+ `make build` 全绿。
- 首次跑测试前先 `make ohpm-install`（worktree 内同样需要）。
- 纯模块（config/crypto/model/repo）单测放 `entry/src/test/*.test.ets`，一模块一文件。
- 真机不可验的能力（X25519 派生、userAuth、vpnExtension、防截屏、扫码）写进
  `docs/device-verification.md` 清单（收尾任务统一整理）。
