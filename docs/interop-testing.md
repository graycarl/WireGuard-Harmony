# 互操作验收方案（决策 0007 第三层 · 测试终点）

> 本项目数据面为**自研 C 实现**（[0001](decisions/0001-dataplane-self-implemented-c.md)、
> [0002](decisions/0002-handshake-in-native-c.md)），协议正确性的**最终判据**是
> 「与上游 Linux `wg` 对端真机互通」。本文件把决策 0007 的六条用例写成可执行的步骤与判定标准。
>
> 硬门槛：**六条用例全部通过**前，项目不视为「测试完成」。前置的本地单测与
> [device-verification.md](device-verification.md) 应已全绿。

## 1. 拓扑

```
+-------------------+          UDP 51820          +---------------------------+
|  HarmonyOS phone  | <==========================> |  Linux host (公网)        |
|  WireGuard App    |                              |  wg0 (kernel wireguard)   |
|  隧道 IP 10.7.0.2 |                              |  隧道 IP 10.7.0.1         |
+-------------------+                              +---------------------------+
```

- 对端使用 Linux 内核 `wireguard`（或 `wireguard-go`），作为**协议参照实现**。
- 手机侧用本应用导入 `.conf` 连接（`Address = 10.7.0.2/24`；`AllowedIPs = 0.0.0.0/0`）。
- 只验证隧道内互通时**不需要** NAT；若要让手机经隧道上网，再在 host 上配 MASQUERADE。

## 2. 准备（宿主机）

```bash
# --- 两对密钥 ---
mkdir -p /tmp/wginterop && cd /tmp/wginterop
umask 077
wg genkey | tee host.key   | wg pubkey > host.pub
wg genkey | tee phone.key  | wg pubkey > phone.pub
wg genpsk > psk.key        # PSK 用例用

# --- 对端（host）配置 ---
cat > host.conf <<EOF
[Interface]
PrivateKey = $(cat host.key)
Address = 10.7.0.1/24
ListenPort = 51820

[Peer]
# 手机
PublicKey = $(cat phone.pub)
AllowedIPs = 10.7.0.2/32
# PersistentKeepalive = 25   # 用例 3 打开
EOF

wg-quick up /tmp/wginterop/host.conf
wg show                                     # 确认接口 up、listen port 51820
```

```bash
# --- 手机侧配置（在应用里导入/新建，或二维码导入）---
cat > phone.conf <<EOF
[Interface]
PrivateKey = $(cat phone.key)
Address = 10.7.0.2/24
DNS = 1.1.1.1
MTU = 1420

[Peer]
PublicKey = $(cat host.pub)
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = <HOST_PUBLIC_IP>:51820
PersistentKeepalive = 25
EOF
qrencode -t utf8 < phone.conf     # 可选：扫码导入
```

- `AllowedIPs = 0.0.0.0/0` 时，host 的公网 IP 也会走隧道 → 需要 host 上放行/或先把
  `Endpoint` 指向 host 的**额外公网地址**并由 host 自己做 SNAT；为避免自环，建议互操作用例里
  手机侧 `AllowedIPs` 先只填 `10.7.0.0/24`（路由隔离干净），需要整网验证时再放开。
- 手机侧 `Endpoint` 必须是 host 可达的公网/局域网地址（同局域网直接用 `192.168.x.x` 也可）。

## 3. 观测手段

| 位置 | 手段 | 用途 |
|---|---|---|
| host | `wg show` / `wg show wg0 dump` | latest handshake、transfer rx/tx、endpoint、allowed ips |
| host | `watch -n 2 wg show` | 观察握手刷新与 rekey |
| host | `tcpdump -ni any udp port 51820 -vv` | 看包是否到达、消息类型（长度）、重传节奏 |
| phone | `hdc shell hilog \| grep -E "WgVpnAbility\|wg-dataplane"` | 连接过程、错误码、握手/定时器日志（C 层日志开关见 §6） |
| phone | 应用详情页 | 各 Peer 的接收/发送字节与上次握手时间 |
| phone | `hdc shell hilog -r` | 开始用例前清空日志 |

统一的判定脚本（host）：

```bash
wg_show() { watch -n 2 'wg show; echo; date'; }
# 或采样：for i in $(seq 1 30); do wg show wg0 dump | awk '{print strftime("%H:%M:%S"), $5, $6, $7, $8}'; sleep 2; done
```

## 4. 用例

### 用例 1：握手建立（两方向）

**1a 手机发起**
1. 应用里连接手机侧隧道。
2. host：`watch -n 2 wg show`。
3. **判定**：host 的 `latest handshake` 在数秒内变为「刚刚」；手机详情页「上次握手时间」显示「现在/几秒之前」。
4. 记录握手耗时（应用内 UI 到 host 首个 handshake 的延迟）。

**1b 对端发起**
1. 保持连接，等待会话过期（>180s 无流量）或重启 host 接口：`wg-quick down/up host.conf`。
2. host：`ping -c 3 10.7.0.2`。
3. **判定**：ping 有回包；`wg show` 出现新的 handshake；手机详情页握手时间刷新。
4. 双向均通过 → 用例 1 PASS（说明我方 initiation 与 response 两条路径都正确）。

### 用例 2：双向数据收发（计数器 / nonce / 重放窗口）

```bash
# --- 小包：双向 ---
# host 侧：
ping -c 20 10.7.0.2
# 手机侧：应用详情页观察接收/发送计数增长；若设备可执行 shell：
#   hdc shell ping -c 20 10.7.0.1

# --- 大流量：两种可行途径（手机一般无 iperf3，二选一）---
# (a) 若手机侧可跑 iperf3：
#   host:   iperf3 -s
#   手机:    iperf3 -c 10.7.0.1 -t 30
# (b) 回退：host 单向 UDP 灌流，验证入向大流量与计数器：
#   host:   timeout 30 sh -c 'cat /dev/zero | nc -u 10.7.0.2 9999'
#           # 同时 host 侧 `wg show` 的 transfer tx 与手机详情页「接收」同步增长
```

**判定**
- `ping -c 20` 丢包 0；`wg show` 两端 `transfer` 计数都增长；手机详情页接收/发送字节数随之增长。
- 大流量传输后无进程崩溃、无连续重连（`wg show` handshake 不异常频繁刷新）。
- **重放验证**：host 侧抓包并重放同一批 transport 包
  （`tcpdump -w replay.pcap -c 200 udp port 51820` 后 `tcpreplay --intf1=<iface> replay.pcap`）。
  **判定**：重放包不会产生重复交付（应用侧无异常、`wg show` 计数不因重放而重复增长），
  且进程不崩溃（重放窗口生效）。
- 单向通 / 不通 → 见 §5 排查表。

### 用例 3：keepalive 长时在线（≥10 分钟）

1. host 的 `[Peer]` 打开 `PersistentKeepalive = 25`（或保持手机侧 25）。
2. host：`watch -n 5 wg show`，手机保持隧道连接、不做任何操作，持续 **≥10 分钟**。
3. **判定**：`latest handshake` 每约 2 分钟刷新一次（会话保活重协商）；期间
   `ping -i 30 10.7.0.2` 全程无丢包；无断开/重连。
4. 记录 10 分钟后手机侧电池/流量占用（可用系统设置查看），确认无异常高频包。

### 用例 4：rekey

1. host：`watch -n 2 'wg show; date'`。
2. 手机侧持续发包（`ping -i 5 10.7.0.1`）。
3. **判定**：会话龄满 ~120s 后出现一次新的 handshake（rekey），且**期间 ping 不中断**
   （重协商平滑，旧会话在 reject-after（180s）内仍可用）；`wg show` 的
   `latest handshake` 更新而 peer 不断开。
4. 若用抓包：观察到新一轮 initiation/response（长度 148/92 字节消息）交替出现。

### 用例 5：roaming（Wi-Fi ↔ 蜂窝）

1. 手机用 Wi-Fi 连接隧道，持续 `ping 10.7.0.1`（host 侧执行 `ping -i 1 10.7.0.2` 更直观）。
2. 关闭 Wi-Fi 切到蜂窝（或反向）。
3. **判定**：`wg show` 的 `endpoint` 变为新的手机源地址端口；连通性在**可接受时延**内恢复
   （依赖 keepalive/握手重试定时器；记录实测恢复时间）。
4. UI 状态保持「已连接」、不闪断（spec tunnel-connection.md §网络变化）。
5. 记录恢复时延，作为决策 0005 §5「增强候选（网络变化事件触发主动重握手）」的立项依据。

### 用例 6：PSK 互通

1. 手机侧 Peer 增加 `PresharedKey = <psk>`；host 的 `[Peer]` 增加同一 `PresharedKey`。
2. 重新连接，回到用例 1/2。
3. **判定**：握手成功、双向收发正常。
4. 反向验证：仅一端配 PSK → 必须**握手失败且不崩溃**（预期无回包），证明 PSK 确实参与密钥混合。

## 5. 失败判定与最小排查路径

| 现象 | 最可能原因 | 排查动作 |
|---|---|---|
| host `tcpdump` 收不到我方任何包 | 未发起握手 / UDP socket 被路由环回 / endpoint 解析错 | 检查 DNS 错误提示、`protect(sockFd)` 是否调用、监听端口绑定 |
| 收到我方 initiation 但 host 不回 | MAC1 错、静态密钥/时间戳 AEAD 错、链式哈希错 | 对 host 与实现的 BLAKE2s/HMAC KAT；核对 mac1 计算对象（msg 前 116 字节）；核对 Tai64N 时间戳格式 |
| 收到 response 但我方不通 | response 解析/密钥派生（KDF1/KDF2 顺序）错 | hosttest 的 Python 独立核对流程；比对 `wg show` 与本地会话密钥派生中间值 |
| 握手成功但数据不通 | transport 消息格式（type/receiver index）错、计数/重放窗口 bug | 抓包看 transport 包长度；核对 receiver index；检查解密后再校验重放窗口 |
| 仅单向通 | cryptokey routing（入向源 IP 校验）/ AllowedIPs 最长前缀匹配错 | 用 `ping` 双向分别测；临时把 AllowedIPs 放宽到 `0.0.0.0/0` 排除路由因素 |
| 频繁重连/握手风暴 | rekey / reject-after / 握手重试定时器常量错 | 观察 `wg show` handshake 刷新间隔；核对 120s/180s/5s/90s 常量与触发条件 |
| 大流量后卡死或崩溃 | 非nonce 溢出、缓冲区越界、锁竞争 | 打开 ASan 主机测试；用小包高频压测；检查收包路径动态分配 |
| PSK 配置下才失败 | PSK 混入顺序（应先与 chaining key 做 KDF，再与握手哈希） | 对照 wireguard-go 的 `mixPreSharedKey` 顺序 |

## 6. 日志开关

- ArkTS 侧：`hilog | grep -E "WgVpnAbility|AppStore|Backend|NativeBridge"`（业务日志 domain 0x0001）。
- C 数据面：`hilog | grep wg-dataplane`；握手/定时器的详细日志由 `cpp/wg_log.h`
  的调试级别控制（真机调试期常开，验收后降级）。
- 需要更细的协议报文比对时，可临时在 `wg_runtime.c` 的收发路径打印
  「消息类型 + 长度 + 计数器」（**禁止打印任何密钥材料**，见 specs/privacy-security.md §5）。

## 7. v1 已知限制（预期行为，不算失败）

- **cookie（message type 3）未实现**（决策 0002 §3）：遇到高负载对端主动回 cookie reply 时，
  我方将其静默忽略、继续按重试定时器发起握手。功能上不影响正常互通；
  若对端在 DoS 压力下持续回 cookie，表现为握手反复失败——此时应记录并评估补做 cookie。
- **多 peer 并发性能优化**（零拷贝、多线程收包）未做：多 Peer 大量流量时性能以功能正确为准。
- 应用进程退出即断连（平台约束，决策 0005）：不作为互操作失败项。
