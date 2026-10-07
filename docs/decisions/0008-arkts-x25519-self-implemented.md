# 0008 · ArkTS 侧 X25519 自实现（替代不可用的 cryptoFramework by-spec 派生）

- 状态：**已决定**（2026，真机实测后修订）
- 关联：[0002 握手在 C 层](0002-handshake-in-native-c.md)、[0007 测试策略](0007-test-strategy.md)、AGENTS.md「核心设计决策 3」

## 背景

控制面需要「由私钥派生公钥」这一能力：隧道编辑器实时显示/复制本机公钥、详情页展示公钥
（specs/tunnel-editor.md、specs/tunnel-detail.md）。原方案（契约 §4）是薄封装
`cryptoFramework.createAsyKeyGeneratorBySpec(X25519PriKeySpec)`。

**真机实测（2026-10-07，HarmonyOS 真机 + SDK 6.1.1/API 24）该路径不可用**：设备日志

```
HCF: Class is not match. expect class: OPENSSL.ED25519.KEYGENERATOR,
     input class: OPENSSL.X25519.KEYGENERATOR
EngineGenerateAlg25519KeyPairBySpec: Invalid params spec → generate key pair fail
```

即 `generateKeyPairSync()` 直接抛错（本地单测里 `@kit` 是空桩，**永远暴露不出这个问题**）。

## 决策内容

1. `crypto/X25519.ets`：**纯 ArkTS 自实现** X25519 标量乘（RFC 7748 Montgomery ladder +
   clamp + `z^(p-2)` 求逆），提供 `x25519(scalar, uCoordinate)`、`publicKeyFrom(privateKey)`、`basePoint()`。
2. `crypto/KeyPair.ets` 改用 `publicKeyFrom()`，不再 import `@kit.CryptoArchitectureKit`。
3. **可测性因此提升**：进本地单测（`test/X25519.test.ets`），覆盖 RFC 7748 §5.2/§6.1 官方向量
   （含迭代向量）、clamp 语义、u 坐标高位掩码、`KeyPair` 端到端 base64 往返 —— 该能力从
   「真机验证项」升级为「本地回归项」。
4. **C 数据面的 X25519 不受影响**：协议握手仍在 C 层用自带 curve25519 实现（0001/0002 不变），
   本决策只涉及控制面的「公钥派生」这一处。
5. 安全说明：BigInt 无法保证常数时间；本实现仅用于「本机私钥 × 基点」派生本机公钥
   （不做对端可控输入的密钥协商），风险可接受，已在文件头注明。

## 后果

- 正面：少一个平台依赖与真机未知项；公钥派生可 100% 本地回归；编辑器/详情页行为有测试兜底。
- 负面：维护一份自实现算法（约 100 行），需靠 RFC 官方向量保证正确性 → 已有 9 条 KAT 覆盖。
- 遗留：真机仍需确认「编辑器内公钥实时显示」的 UI 行为（属 UI 验证项，不再是算法正确性问题）。

## 回溯条件

若后续 SDK 修复 `createAsyKeyGeneratorBySpec` 的 X25519 路径并真机验证通过，可换回平台实现
（保留 KAT 作为对照测试）；当前无换回理由。
