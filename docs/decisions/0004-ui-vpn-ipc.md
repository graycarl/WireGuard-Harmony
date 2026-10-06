# 0004 · UI 进程 ↔ VpnExtensionAbility 进程：下行 want+共享存储，上行公共事件

- 状态：**已决定**（2026）
- 关联：[specs/tunnel-connection.md](../specs/tunnel-connection.md)「状态一致性」、[0003 持久化](0003-persistence-json-file.md)、AGENTS.md 决策 4.3（隧道状态是外部真源）

## 背景

VpnExtensionAbility 运行在**独立的 VPN 服务进程**。UI 进程与它之间需要两条通道：
下行（启动/停止/配置）与上行（隧道状态、统计快照）。spec 要求「开关状态永远以系统侧
真实 VPN 状态为准」，并在应用被结束、其他 VPN 抢占等场景自动纠正 UI——这决定了
上行通道必须存在且不能依赖用户操作触发。

## 已核实的平台事实

| 事实 | 证据 |
|---|---|
| VpnExtensionAbility 生命周期回调**只有** `onCreate(want)` / `onDestroy()`，无 `onConnect`/bind 式 IPC | `@ohos.app.ability.VpnExtensionAbility.d.ts` |
| `vpnExtension` 只有 start/stop/create/protect/destroy/generateVpnId，**没有查询当前 VPN 状态的 API** | `@ohos.net.vpnExtension.d.ts` |
| 停止只能停本应用启动的 VPN；系统同时只允许一条 VPN，重复启动被拒 | net-vpnExtension.md |
| `Emitter`、`EventHub`、`AppStorage` 均为**进程内**机制，不能跨进程 | 各自 d.ts / 官方文档 |
| 两个进程同属一个应用沙箱，**应用私有目录文件双进程可读写** | 应用沙箱模型 |

## 候选方案与取舍

| 方案 | 结论 | 理由 |
|---|---|---|
| want 携带全量隧道配置下行 | ❌ | want 参数有大小限制；配置 JSON 双份序列化/反序列化，且与 0003 的单一真源冲突。 |
| Emitter/EventHub/AppStorageV2 做上行 | ❌ | 全部进程内机制，物理上不可达。 |
| 自建 socket / IPC 通道 | ❌ | 过重：要解决鉴权、粘包、双端生命周期；收益相对公共事件+文件不明显。 |
| **下行：want 只带隧道名，配置由 VPN 进程自读共享存储；上行：公共事件 + 启动对账** | ✅ | 全部基于已核实能力，无双真源，实现最简。 |

## 决策内容

1. **下行控制**：
   - 启动：`startVpnExtensionAbility(want{parameters: {tunnelName}})` → VPN 进程 `onCreate`
     按隧道名从 `tunnels.json`（0003）自读全量配置，构建 VpnConfig + 下发 C 数据面。
   - 停止：`stopVpnExtensionAbility` → VPN 进程 `onDestroy` 内 destroy 连接。
   - **运行中改配置 = 先 stop 再 start**（对齐 spec：编辑保存/改名正在连接的隧道 = 断开后以新配置重连；
     系统只允许一条 VPN，本无热更新通道）。
2. **上行状态**：
   - VPN 进程在状态迁移（连接中→已连接/失败、断开）与统计更新时，
     用 `commonEventManager` 发布**自定义公共事件**（事件名应用私有命名空间，
     数据只含：隧道名、状态枚举、rx/tx 计数、最近握手时间——**不含任何密钥/配置**）。
   - UI 侧全局 store（AppStorageV2 单例）订阅该事件并更新快照；页面只订阅 store。
3. **启动对账**：
   - 依据官方「服务生命周期」（UI 进程退出 → 系统停止 VPN），**UI 冷启动一律呈现全部断开**，
     不做状态恢复猜测。
   - 若真机验证推翻了该行为（见待验证清单），再升级为「VPN 进程写状态文件 + 心跳时间戳，
     UI 启动读文件对账」的方案——届时只加文件层，事件通道不变。
4. **状态枚举**：沿用上游 `Tunnel.State` 语义（UP/DOWN/TOGGLE）映射 spec 的
   连接中/已连接/已断开；UI 不维护任何「意图态」。

## 待验证清单（真机，来自 spec 待验证事项 + 本决策新增）

1. 应用进程被系统结束后，系统断开 VPN 的实际表现与时延（决定「冷启动一律断开」是否成立）。
2. 系统设置里关闭 VPN 后，本应用/VPN 进程能否拿到通知（`onDestroy` 是否被回调）。
3. 第三方 VPN 应用发起连接时，是抢占成功（我方被断）还是被系统拒绝（官方文档说拒绝，
   需实测确认 UI 纠正路径是否需要）。
4. VPN 进程在后台发布自定义公共事件的可靠性（息屏/后台冻结场景）。

## 后果

- 正面：无自建 IPC、无状态双真源；spec「状态自动纠正」落到具体机制；冷启动语义简单可讲。
- 负面：统计刷新粒度受公共事件频率限制（实时流量曲线精度有限）→ 可接受，
  详情页统计按秒级事件推送；待验证清单任一证伪都只需局部升级，不动通道结构。
