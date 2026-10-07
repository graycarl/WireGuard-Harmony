/**
 * HKDF（RFC 5869，以 HMAC-BLAKE2s 为 PRF）+ WireGuard KDF1/KDF2/KDF3。
 *
 * 两套接口并存的原因（docs/decisions/0002 §4）：
 * - extract/expand：标准 RFC 5869 流程，用 HMAC-BLAKE2s，便于用 python hmac 生成对照向量；
 * - kdf1/kdf2/kdf3：WireGuard 协议实际使用的 KDF（keyed BLAKE2s 直接作 MAC，
 *   见 WireGuard 白皮书 §5.2.2 "HMAC-based Key Derivation" 的实例化），
 *   作为 C 数据面握手实现的直接对照。
 */
import { Blake2s } from './Blake2s';

const HASH_LEN = 32;
const BLOCK_LEN = 64; // BLAKE2s 块长

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

/** HMAC-BLAKE2s（RFC 2104）。 */
function hmacBlake2s(key: Uint8Array, data: Uint8Array): Uint8Array {
  let k = key;
  if (k.length > BLOCK_LEN) {
    k = Blake2s.hash(k);
  }
  const ipad = new Uint8Array(BLOCK_LEN);
  const opad = new Uint8Array(BLOCK_LEN);
  for (let i = 0; i < BLOCK_LEN; i++) {
    ipad[i] = 0x36;
    opad[i] = 0x5C;
  }
  for (let i = 0; i < k.length; i++) {
    ipad[i] = (ipad[i] ^ k[i]) & 0xFF;
    opad[i] = (opad[i] ^ k[i]) & 0xFF;
  }
  return Blake2s.hash(concat(opad, Blake2s.hash(concat(ipad, data))));
}

export class Hkdf {
  /** RFC 5869 extract：salt 为空时按规范用 HashLen 个零字节。 */
  static extract(salt: Uint8Array, ikm: Uint8Array): Uint8Array {
    const effectiveSalt = salt.length === 0 ? new Uint8Array(HASH_LEN) : salt;
    return hmacBlake2s(effectiveSalt, ikm);
  }

  /** RFC 5869 expand：outLen 最大 255*32。 */
  static expand(prk: Uint8Array, info: Uint8Array, outLen: number): Uint8Array {
    if (outLen < 1 || outLen > 255 * HASH_LEN) {
      throw new Error('HKDF expand 输出长度非法');
    }
    const out = new Uint8Array(outLen);
    let t = new Uint8Array(0);
    let written = 0;
    let counter = 1;
    while (written < outLen) {
      const block = concat(concat(t, info), new Uint8Array([counter & 0xFF]));
      t = hmacBlake2s(prk, block);
      const take = Math.min(HASH_LEN, outLen - written);
      out.set(t.subarray(0, take), written);
      written += take;
      counter++;
    }
    return out;
  }

  /** WireGuard KDF1：T1 = MAC(key, input || 0x01)。返回 [T1]。 */
  static kdf1(key: Uint8Array, input: Uint8Array): Uint8Array[] {
    const t1 = Blake2s.keyedHash(key, concat(input, new Uint8Array([1])));
    return [t1];
  }

  /** WireGuard KDF2：T1 同上，T2 = MAC(key, T1 || input || 0x02)。返回 [T1, T2]。 */
  static kdf2(key: Uint8Array, input: Uint8Array): Uint8Array[] {
    const t1 = Blake2s.keyedHash(key, concat(input, new Uint8Array([1])));
    const t2 = Blake2s.keyedHash(key, concat(concat(t1, input), new Uint8Array([2])));
    return [t1, t2];
  }

  /** WireGuard KDF3：T3 = MAC(key, T2 || input || 0x03)。返回 [T1, T2, T3]。 */
  static kdf3(key: Uint8Array, input: Uint8Array): Uint8Array[] {
    const t12 = Hkdf.kdf2(key, input);
    const t3 = Blake2s.keyedHash(key, concat(concat(t12[1], input), new Uint8Array([3])));
    return [t12[0], t12[1], t3];
  }
}
