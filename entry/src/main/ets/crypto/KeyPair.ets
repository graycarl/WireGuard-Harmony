/**
 * WireGuard 密钥对：由 32 字节私钥经 X25519 派生公钥。
 *
 * 薄封装 cryptoFramework 的 X25519（docs/dev-contracts.md §4）：
 * - 本地单测中 cryptoFramework 是空桩 → 公钥派生不进本地断言（仅设备侧有效）；
 * - 字节序约定：官方文档规定密钥参数 bigint 为大端序，X25519 原始密钥为小端字节串，
 *   因此入/出均做字节反转。
 *
 * ⚠️ 真机验证项（RFC 7748 §5.2 测试向量）：
 *   私钥 77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a
 *   公钥 8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Key } from './Key';

const KEY_BYTES = 32;

/** 小端 32 字节 → 大端 bigint。 */
function leBytesToBigint(bytes: Uint8Array): bigint {
  let v = 0n;
  for (let i = bytes.length - 1; i >= 0; i--) {
    v = (v << 8n) | BigInt(bytes[i]);
  }
  return v;
}

/** 大端 bigint → 小端 32 字节（高位补零）。 */
function bigintToLeBytes(v: bigint, outLen: number): Uint8Array {
  const out = new Uint8Array(outLen);
  let rest = v;
  for (let i = 0; i < outLen; i++) {
    out[i] = Number(rest & 0xFFn);
    rest = rest >> 8n;
  }
  return out;
}

/** 经 cryptoFramework X25519 派生公钥（设备侧有效）。 */
function deriveX25519PublicKey(privateKeyBytes: Uint8Array): Uint8Array {
  const spec: cryptoFramework.X25519PriKeySpec = {
    algName: 'X25519',
    specType: cryptoFramework.AsyKeySpecType.PRIVATE_KEY_SPEC,
    sk: leBytesToBigint(privateKeyBytes)
  };
  const gen = cryptoFramework.createAsyKeyGeneratorBySpec(spec);
  const keyPair = gen.generateKeyPairSync();
  const pkBig = keyPair.pubKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.X25519_PK_BN) as bigint;
  return bigintToLeBytes(pkBig, KEY_BYTES);
}

export class KeyPair {
  readonly privateKey: Key;
  readonly publicKey: Key;

  constructor(privateKey: Key) {
    this.privateKey = privateKey;
    this.publicKey = new Key(deriveX25519PublicKey(privateKey.toBytes()));
  }
}
