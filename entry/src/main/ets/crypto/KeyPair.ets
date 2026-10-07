/**
 * WireGuard 密钥对：由 32 字节私钥经 X25519 派生公钥。
 *
 * X25519 用纯 ArkTS 实现（crypto/X25519.ets，RFC 7748）——原因见该文件头：
 * 真机实测 `cryptoFramework.createAsyKeyGeneratorBySpec(X25519PriKeySpec)` 不可用
 * （HCF: expect ED25519 KEYGENERATOR, input X25519 KEYGENERATOR → generate key pair fail）。
 * 自实现后可本地单测（RFC 7748 官方向量），不再依赖平台原语。
 */
import { Key } from './Key';
import { publicKeyFrom } from './X25519';

export class KeyPair {
  readonly privateKey: Key;
  readonly publicKey: Key;

  constructor(privateKey: Key) {
    this.privateKey = privateKey;
    this.publicKey = new Key(publicKeyFrom(privateKey.toBytes()));
  }
}
