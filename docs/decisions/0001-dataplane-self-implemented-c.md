# 0001 · 数据面隧道实现：自研 C（不移植 wireguard-go，不引入 Rust）

- 状态：**已决定**（2026）
- 关联：AGENTS.md「核心设计决策 1」（数据面必须在原生层）、上游 `tunnel/tools/libwg-go`

## 背景

数据面必须在原生层（C/C++）：`VpnConnection.create()` 返回的 tun fd 在 ArkTS 侧没有任何读写接口，
tun ↔ UDP 的收发包只能在原生线程中完成。上游 WireGuard-Android 的数据面是
**wireguard-go**（Go 用户态实现，经 gomobile 编译为 libwg-go）。本项目需要一个
能在 HarmonyOS（OHOS NDK，aarch64）上运行的等价物。

## 候选方案与取舍

| 方案 | 结论 | 理由 |
|---|---|---|
| **A. 移植 wireguard-go（gomobile → libwg-go）** | ❌ 否决 | Go 官方不支持 OHOS 交叉编译目标；gomobile 产物面向 Android JNI，OHOS 无对应运行时支持。需要维护私有 Go 工具链补丁，风险最高、不可持续。 |
| **B. boringtun（Cloudflare Rust 实现）** | ❌ 否决 | Rust 的 OHOS target 已有社区路径，但会引入第二条独立工具链（rustup + target + cargo 构建接入 hvigor）与 crates 供应链审计负担；且 boringtun 本身演进缓慢、历史上有遗留缺陷修复不及时的问题。对「单一 NDK + CMake」的构建简洁性是显著倒退。 |
| **C. 自研 C 数据面** | ✅ **选用** | 依赖最少（仅 OHOS NDK + CMake，无额外工具链）；协议本身规模可控（握手 Noise IK + ChaCha20-Poly1305 传输 + 计数器/nonce + keepalive/rekey 定时器）；与「核心设计决策 3」的可测性分层天然契合（纯算法可在 ArkTS 侧做镜像实现用于本地单测）。 |

## 决策内容

数据面在 `entry/src/main/cpp/` 以 C 实现，构建为单一 `.so`，经 NAPI 暴露给 ArkTS。
实现范围（v1 只实现协议必要子集）：

1. **传输层**：tun fd ↔ UDP socket 双线程转发（参考官方 VPNControl_Case 的线程结构）、
   消息封包/解包（类型 4 transport data）、计数器 nonce、拒绝重放（滑动窗口）。
2. **会话与定时器**：按索引（index）管理会话密钥，rekey-after-time / reject-after-time、
   keepalive、握手发起时机（闲置 120s 重协商、发送时无有效会话则触发）。
3. **密码原语（原生侧）**：BLAKE2s（含 keyed）、HKDF、ChaCha20-Poly1305、X25519 均
   **移植成熟公共域参考实现**（如 wireguard 内核实现 / RFC 8439 / curve25519-donna 系），
   不自创算法；全部以官方测试向量（KAT）验证。鸿蒙密码框架无 BLAKE2s（已核实），
   且原生侧统一自实现可避免 ArkTS↔C 往返调用。
4. **NAPI 接口（薄）**：`start(tunFd, config)` / `stop()` / `addPeer` 类配置下发 /
   状态与统计回调上抛。原生层不解析 wg-quick 文本——配置解析仍在 ArkTS 纯模块，
   解析结果以结构化参数下发。

## 明确不在本决策内的事

- **握手协议放 ArkTS 控制面还是同放 C 层**：单独决策（0002，待写）。本决策只确定
  「凡落原生层的协议代码用 C 自研，不引入 Go/Rust」。若 0002 决定握手放 C 层，
  属本决策的自然延伸，无需推翻。
- 多 peer 并发数据面的性能优化（零拷贝、多线程收包）：v1 之后视真机实测再定。

## 后果

**正面**
- 构建链纯净：hvigor + OHOS NDK + CMake 即可，agent 可全程命令行验证（`make build`）。
- 无第三方大依赖，供应链面最小；协议行为完全可控，与 spec 对齐无黑盒。
- 纯算法（BLAKE2s/HKDF 等）可在 ArkTS 侧写同向量的镜像实现，进本地单测（决策 3 分层不变）。

**负面与缓解**
- 协议正确性责任自负 → 缓解：① 全部密码原语过官方 KAT；② 验收终点为
  **与上游 Linux `wg` 对端真机互操作**（握手 + 双向收发 + 长时 keepalive），
  测试拓扑与步骤写入测试策略文档；③ 仅实现协议必要子集，拒绝花哨扩展。
- 安全审计成本（手写 C 的内存安全） → 缓解：收发包路径禁用动态分配的热路径、
  固定长度缓冲区、全程边界检查；后续可考虑移植路径上启用 ASan 做 fuzz 冒烟。

## 被否决方案的回溯条件

若真机互操作阶段发现自研实现存在无法定位的协议偏差且排查成本失控，
允许重新评估方案 B（boringtun）作为数据面 fallback；方案 A 因工具链死结不回溯。
