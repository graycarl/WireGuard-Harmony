/**
 * 设备侧加密随机源薄封装（本文件是 crypto/ 中唯二允许 import @kit 的文件之一）。
 *
 * ⚠️ 本地单测中 cryptoFramework 是空桩（返回空数据），所以 Key.generate() 在测试中
 * 必须注入确定性 rng，本默认实现只在设备侧有效。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

export function secureRandomBytes(len: number): Uint8Array {
  const rand = cryptoFramework.createRandom();
  const blob = rand.generateRandomSync(len);
  return new Uint8Array(blob.data.slice(0, len));
}
