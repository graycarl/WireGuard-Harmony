# 0005 · 生命周期与重连边界：不保活、不自启，roaming 靠协议自然恢复

- 状态：**已决定**（2026）
- 关联：[specs/tunnel-connection.md](../specs/tunnel-connection.md)、[0004 进程通信](0004-ui-vpn-ipc.md)、AGENTS.md「本项目特有」已知坑

## 背景

上游 WireGuard-Android 依赖 Android 的前台服务与 Always-on VPN 实现「后台常驻、
开机自连」。需确定本项目在 HarmonyOS 上对等的生命周期承诺与重连策略。

## 已核实的平台事实

| 事实 | 证据 |
|---|---|
| **调用 `startVpnExtensionAbility` 的应用进程退出 → 系统主动停止 VPN**；VPN 服务进程销毁 → 同样停止 | net-vpnExtension.md「服务生命周期」 |
| `MANAGE_VPN`（系统 VPN 管理，含 always-on 类能力）是 `system_basic`，普通应用拿不到 | PermissionDefinitions.json（AGENTS.md 决策 2） |
| 系统同时只允许一条 VPN 连接 | net-vpnExtension.md |

**推论**：鸿蒙三方 VPN 应用**没有 always-on、没有开机自连的系统入口**；
且 UI 进程死亡即断连，「应用退出后 VPN 常驻」在机制上不成立。

## 决策内容

1. **不保活**：不做任何后台常驻尝试（不申请长时任务、不做进程拉活）。应用退出 = VPN 断开，
   作为产品语义如实写进 handbook（spec 已定「用户打开应用后所有隧道均显示为断开，需手动开启」）。
2. **不自启**：不提供开机/启动自动重连（spec 裁剪总表已定）。
3. **网络切换（Wi-Fi ↔ 蜂窝 roaming）**：**不做显式处理**，依赖 WireGuard 协议特性自然恢复——
   UDP 无连接，发包路径自动走新网络；对端看到的是源地址变化（协议原生支持 roaming）；
   NAT 重绑后的入向恢复由 keepalive/握手重试定时器兜底（C 数据面，0002）。
   spec 已定「网络切换时连接保持，UI 状态不变」，机制由本决策补齐。
4. **网络完全断开再恢复**：不自动重连，需用户手动开启（spec 已定）。
   UI 侧检测到系统网络断开时可把开关状态标注为等待态，但不发起重连动作。
5. **增强候选（不进 v1）**：VPN 进程内监听 `@ohos.net.connection` 网络变化事件，
   在切换后主动触发一次重新握手以加速入向恢复。待真机观察 roaming 实际恢复时延后再决定是否立项。

## 后果

- 正面：与系统能力边界完全对齐，无「承诺了做不到」的产品债；spec/handbook 措辞有据可依。
- 负面：用户期望的「类 Android 常驻 VPN」体验缺失 → 这是平台约束而非实现取舍，
  handbook 需明确告知；通知栏常驻通知（spec 另有定义）照做，但它只是展示与入口，**不是保活手段**。
