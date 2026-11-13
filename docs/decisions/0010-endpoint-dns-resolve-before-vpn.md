# 0010 · endpoint 域名解析必须在 `VpnConnection.create()` 之前

- 状态：**已决定**（2026-10，真机反馈「有效域名也报无法解析 DNS」后修订）
- 关联：[0001 数据面自研](0001-dataplane-self-implemented-c.md)、[0002 握手在 C 层](0002-handshake-in-native-c.md)、
  [0004 UI↔VPN IPC](0004-ui-vpn-ipc.md)、契约 §8/§10、specs/tunnel-connection.md

## 背景

原实现（契约 §10 旧版）的启动顺序是：

```
createVpnConnection → create(vpnConfig)  ← 系统 VPN 生效：默认路由 + DNS 交给 tun
→ createUdpSocket → protect
→ startTunnel(tunFd, sockFd, configJson) ← 到这里才 getaddrinfo 解析 endpoint
```

真机现象：`Endpoint` 写 **IP** 能正常连接；写 **域名** 则报
「建立连接时出错：无法解析 DNS 主机名：'vpn.example.com'」，而同一域名在手机浏览器/
其他应用中可正常解析（网络健康）。

## 根因

`create()` 一返回，VPN 扩展进程自身的网络就被自己的 VPN 接管了：

1. `allowedIPs` 里的 `0.0.0.0/0`（排除局域网的场景是若干具体段）被装成系统路由，
   **默认出网流量指向 tun**；
2. `VpnConfig.dnsAddresses`（如 `1.1.1.1`）成为该网络的 DNS，且这些地址本身也在
   `allowedIPs` 里（编辑器会自动补 `/32` 主机路由，specs/tunnel-editor.md）。

此时 C 侧才 `getaddrinfo(host)` → DNS 查询包被路由进 tun → 而 tun 的另一端要靠
`startTunnel` 起线程、跑 Noise IK 握手才能转发数据，**而握手正卡在「解析完成之后」** →
解析包永远没有应答 → `EAI_AGAIN`/超时 → 返回 `-2`。这是典型的自依赖死锁（chicken-and-egg）。

补充事实：

- `protect(socketFd)` **只保护传入的那一个 fd**，`getaddrinfo` 内部用的 socket 不在其列；
  平台为此在 API 22 才补了 `protectProcessNet()`（「保护本进程之后新建的所有 socket」），
  反证默认不保护本进程流量。
- 官方样例 `VPNControl_Case`（`entry/src/main/ets/vpnability/VPNExtentionAbility.ets`）
  的顺序也是 `udpConnect()`（建 socket）→ `protect()` → `SetupVpn()`（即 `create`）→ 处理 tun，
  即「socket/protect 在 create 之前」；它用的是硬编码 IP，故只佐证顺序、不佐证域名解析。
- 数字 IP 走 `getaddrinfo` 的 numeric 分支，不发任何 DNS 查询 → 所以「IP 能连、域名不能」。
  netd DNS 缓存命中时域名也可能偶然成功，症状表现为时好时坏。

## 决策内容

1. NAPI 拆成两段（契约 §8）：
   - `prepareTunnel(configJson)`：KAT 自检 → 解析配置 → **解析全部 endpoint（getaddrinfo）**。
     不碰 fd、不起线程。错误码 `-1`/`-2`（DNS）/`-5`（KAT）。
   - `startTunnel(tunFd, sockFd)`：仅设 fd → `bind(listenPort)` → 起三线程。
     未 prepare 时返回 `-1`（用 `g_prepared` 兜住顺序）。
2. `WgVpnAbility.startAsync()` 顺序改为（契约 §10）：
   ```
   prepare(configJson)                // 此时无 VPN，DNS 走 Wi-Fi/蜂窝，正常解析
   → vpnConnection.create(vpnConfig)  // 失败仍映射「无法创建 tun 设备」等既有文案
   → createUdpSocket() → protect(sockFd) → protectProcessNet()（失败仅记日志）
   → startTunnel(tunFd)               // UDP fd 已在 createUdpSocket() 交给数据面
   ```
3. `prepareTunnel` 失败即**不创建系统 VPN**：状态栏不会出现 VPN 图标（`create()` 未被调用），
   直接把「无法解析 DNS 主机名」事件发给 UI。注意：**系统 VPN 授权框不在这一步的范围内** ——
   授权框由系统在 `startVpnExtensionAbility()` 时弹出，且只有授权后系统才会拉起本扩展 Ability 的
   `onCreate`（平台 `net-vpnExtension.md`），因此它总是早于 `prepareTunnel`，与解析成败无关。
   用户可感知的行为以 specs/tunnel-connection.md 为准。
4. 顺带加 `protectProcessNet()`（API 22，SDK 24 可用）：让 VPN 进程之后新建的 socket
   （将来的 endpoint 二次解析、诊断上报）默认走底层网络，避免同类死锁复发。
5. 顺带修 fd 归属：`createUdpSocket()` 产出的 fd 直接记入数据面（`g_wg.sock_fd`，唯一 owner），
   由 `stopTunnel()`/下一次 `prepareTunnel()` 关闭；`startTunnel(tunFd)` 只接收 tun fd，不再接受覆写 UDP fd。
   这样 `protect()` 失败等异常路径不会漏关 fd（旧实现在 `startTunnel` 之前该 fd 无人持有，每次失败漏一个）。
   同时 `startTunnel` 入口即清 `g_prepared`（失败即视为本次 prepare 已消费）。

## 被否决的备选方案

| 方案 | 否决理由 |
|---|---|
| 只在解析期间 `protect` 一个「解析用 socket」 | `getaddrinfo` 不暴露内部 socket，无法 protect；自建 DNS 客户端（手写 UDP DNS 报文 + 自己解析）成本远超收益 |
| 仅靠 `protectProcessNet()` 而不调顺序 | 该 API 只保护**之后新建**的 socket，且解析发生在 netd 侧，是否受保护取决于平台实现 → 不能作为唯一依据；顺序修复是确定性的 |
| 在 UI 进程解析域名后把 IP 通过 want 传给扩展 Ability | 配置会在 IPC 里多出一份派生数据；UI 进程可能被系统冻结/不在前台；将来 endpoint 二次解析仍要回到扩展进程 |
| 先 `create` 但把 `dnsAddresses` 留空 | 仍然走 tun 路由（默认路由已生效），不解决死锁 |

## 后果

- 正面：有效域名可正常连接（DP-4b 回归项）；解析失败路径不再创建 VPN，也不再消费系统授权；
  `startTunnel` 职责收敛为「绑 fd + 起线程」，更易测。
- 负面：NAPI 从 1 个启动入口变 2 个，`WgVpnAbility` 需要成对处理失败回滚（`stopTunnel` 幂等，
  `g_prepared` 在 stop/start 后清零）；文档（契约 §8/§10、spec、handbook、验证清单）需同步。
- **遗留 1**：endpoint 仍只解析一次，DDNS 换 IP / 切网络后只能靠重连生效；
  要做周期性二次解析时，必须在上面的 `protectProcessNet()` 生效之后进行，否则重回本 bug。
- **遗留 2（切换隧道的窄窗口）**：`Backend.connect()` 先等上一条隧道发 down 事件再起下一条，
  而 `WgVpnAbility.teardown()` 里的 `vpnConnection.destroy()` 是 fire-and-forget，down 事件
  可能在系统 VPN 完全拆除**之前**就发出——此时新隧道的 `prepareTunnel` 域名解析可能仍被
  残留路由影响。窗口极小（毫秒级），首次验证按 DP-4d（两条域名隧道来回切换）观察；
  若真机复现，再改成「等 destroy 落地（带上限，如 1s）再发 down 事件」。

## 回溯条件

若平台把「VPN 扩展进程自身的名字解析」默认排除在 VPN 路由之外（真机验证 DP-4b 在本顺序下与
旧顺序下均通过），可简化回单入口；目前无此证据，保留拆分。
