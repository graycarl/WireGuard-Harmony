/**
 * X25519（RFC 7748）本地 KAT —— 纯 ArkTS 实现，可在本地单测验证。
 *
 * 动机（真机实测）：SDK 的 cryptoFramework X25519 by-spec 生成器在设备上不可用，
 * 因此公钥派生改为自实现；本用例是该实现的正确性保障（RFC 7748 §5.2/§6.1 官方向量）。
 */
import { describe, it, expect } from '@ohos/hypium';
import { Coding } from '../main/ets/crypto/Coding';
import { x25519, publicKeyFrom, basePoint } from '../main/ets/crypto/X25519';
import { Key } from '../main/ets/crypto/Key';
import { KeyPair } from '../main/ets/crypto/KeyPair';

function hex(s: string): Uint8Array {
  return Coding.hexDecode(s);
}

function expectHex(actual: Uint8Array, expectedHex: string): void {
  expect(Coding.hexEncode(actual)).assertEqual(expectedHex);
}

export default function x25519Test() {
  describe('X25519', () => {
    it('RFC 7748 §5.2: 私钥 a 派生公钥 A（基点标量乘）', 0, () => {
      const a = hex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a');
      expectHex(publicKeyFrom(a),
        '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a');
    });

    it('RFC 7748 §5.2: 私钥 b 以 A 为 u 坐标派生共享密钥', 0, () => {
      const b = hex('5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb');
      const aPub = hex('8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a');
      expectHex(x25519(b, aPub),
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742');
    });

    it('RFC 7748 §6.1: 向量 1', 0, () => {
      const k = hex('a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4');
      const u = hex('e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c');
      expectHex(x25519(k, u),
        'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552');
    });

    it('RFC 7748 §6.1: 向量 2', 0, () => {
      const k = hex('4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d');
      const u = hex('e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493');
      expectHex(x25519(k, u),
        '95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957');
    });

    it('RFC 7748 §5.2: iterated 1 次（k=u=9）', 0, () => {
      const nine = hex('0900000000000000000000000000000000000000000000000000000000000000');
      expectHex(x25519(nine, nine),
        '422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079');
    });

    it('decodeU 忽略最高位（u 高位掩码）', 0, () => {
      const k = hex('a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4');
      const u = hex('e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c');
      const masked = u.slice();
      masked[31] = masked[31] | 0x80;
      expectHex(x25519(k, masked),
        'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552');
    });

    it('clamp：私钥低 3 位清零、最高位置位、次高位置位', 0, () => {
      // 全 0 私钥 clamp 后等价于常数标量，与显式 clamp 后的结果一致
      const zero = new Uint8Array(32);
      const clamped: Uint8Array = new Uint8Array(32);
      clamped[0] = 0 & 248;
      clamped[31] = (0 & 127) | 64;
      expectHex(x25519(zero, basePoint()), Coding.hexEncode(x25519(clamped, basePoint())));
    });

    it('私钥长度错误抛错', 0, () => {
      let threw = false;
      try {
        x25519(new Uint8Array(31), basePoint());
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('KeyPair：由 base64 私钥派生公钥（RFC 7748 §5.2 向量）', 0, () => {
      const a = hex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a');
      const pair = new KeyPair(Key.fromBase64(Coding.base64Encode(a)));
      expectHex(pair.publicKey.toBytes(),
        '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a');
      expect(pair.publicKey.toBase64()).assertEqual(
        Coding.base64Encode(hex('8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a')));
    });
  });
}
