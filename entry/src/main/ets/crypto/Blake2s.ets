/**
 * BLAKE2s 纯 ArkTS 实现（RFC 7693），含 keyed 模式与 1–32 字节可变输出。
 *
 * 用途：ArkTS 镜像实现，作为 C 数据面实现的 KAT 对照（docs/decisions/0002 §4）。
 * 正确性由 entry/src/test/Crypto.test.ets 中的官方等价测试向量保证。
 */

const IV: number[] = [
  0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
  0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
];

/** RFC 7693 消息置换表（10 轮 × 16）。 */
const SIGMA: number[][] = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]
];

function rotr32(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

function g(v: number[], a: number, b: number, c: number, d: number, x: number, y: number): void {
  v[a] = (v[a] + v[b] + x) >>> 0;
  v[d] = rotr32((v[d] ^ v[a]) >>> 0, 16);
  v[c] = (v[c] + v[d]) >>> 0;
  v[b] = rotr32((v[b] ^ v[c]) >>> 0, 12);
  v[a] = (v[a] + v[b] + y) >>> 0;
  v[d] = rotr32((v[d] ^ v[a]) >>> 0, 8);
  v[c] = (v[c] + v[d]) >>> 0;
  v[b] = rotr32((v[b] ^ v[c]) >>> 0, 7);
}

/** 压缩函数：处理一个 64 字节块。t0/t1 为已处理字节计数（含本块，低/高 32 位）。 */
function compress(h: number[], block: Uint8Array, blockOffset: number, t0: number, t1: number, isLast: boolean): void {
  const m: number[] = [];
  for (let i = 0; i < 16; i++) {
    const o = blockOffset + i * 4;
    m.push((block[o] | (block[o + 1] << 8) | (block[o + 2] << 16) | (block[o + 3] << 24)) >>> 0);
  }
  const v: number[] = [];
  for (let i = 0; i < 8; i++) {
    v.push(h[i]);
  }
  for (let i = 0; i < 8; i++) {
    v.push(IV[i]);
  }
  v[12] = (v[12] ^ t0) >>> 0;
  v[13] = (v[13] ^ t1) >>> 0;
  if (isLast) {
    v[14] = (v[14] ^ 0xFFFFFFFF) >>> 0;
  }

  for (let r = 0; r < 10; r++) {
    const s = SIGMA[r];
    g(v, 0, 4, 8, 12, m[s[0]], m[s[1]]);
    g(v, 1, 5, 9, 13, m[s[2]], m[s[3]]);
    g(v, 2, 6, 10, 14, m[s[4]], m[s[5]]);
    g(v, 3, 7, 11, 15, m[s[6]], m[s[7]]);
    g(v, 0, 5, 10, 15, m[s[8]], m[s[9]]);
    g(v, 1, 6, 11, 12, m[s[10]], m[s[11]]);
    g(v, 2, 7, 8, 13, m[s[12]], m[s[13]]);
    g(v, 3, 4, 9, 14, m[s[14]], m[s[15]]);
  }
  for (let i = 0; i < 8; i++) {
    h[i] = (h[i] ^ v[i] ^ v[i + 8]) >>> 0;
  }
}

function blake2s(data: Uint8Array, key: Uint8Array, outLen: number): Uint8Array {
  if (outLen < 1 || outLen > 32) {
    throw new Error('BLAKE2s 输出长度必须在 1-32 字节之间');
  }
  if (key.length > 32) {
    throw new Error('BLAKE2s 密钥最长 32 字节');
  }
  const h: number[] = [];
  for (let i = 0; i < 8; i++) {
    h.push(IV[i]);
  }
  // 参数块：digest_length | key_length<<8 | fanout=1<<16 | depth=1<<24
  h[0] = (h[0] ^ 0x01010000 ^ (key.length << 8) ^ outLen) >>> 0;

  let t0 = 0;
  let t1 = 0;
  const addCounter = (n: number): void => {
    t0 = (t0 + n) >>> 0;
    if (t0 < n) {
      t1 = (t1 + 1) >>> 0;
    }
  };
  const zeroBlock = new Uint8Array(64);

  // keyed 模式：密钥补零到 64 字节，视作消息前缀（RFC 7693 §2.5）。
  // 注意：若消息为空，密钥块本身就是最终块（与参考实现一致）。
  if (key.length > 0) {
    const keyBlock = new Uint8Array(64);
    keyBlock.set(key, 0);
    addCounter(64);
    if (data.length === 0) {
      compress(h, keyBlock, 0, t0, t1, true);
      return finish(h, outLen);
    }
    compress(h, keyBlock, 0, t0, t1, false);
  }

  if (data.length === 0) {
    compress(h, zeroBlock, 0, t0, t1, true);
  } else {
    let offset = 0;
    while (offset < data.length) {
      const remaining = data.length - offset;
      const take = remaining > 64 ? 64 : remaining;
      const isLast = remaining <= 64;
      if (take === 64) {
        addCounter(64);
        compress(h, data, offset, t0, t1, isLast);
      } else {
        const lastBlock = new Uint8Array(64);
        lastBlock.set(data.subarray(offset, offset + take), 0);
        addCounter(take);
        compress(h, lastBlock, 0, t0, t1, true);
      }
      offset += take;
    }
  }

  return finish(h, outLen);
}

function finish(h: number[], outLen: number): Uint8Array {
  const full = new Uint8Array(32);
  for (let i = 0; i < 8; i++) {
    full[i * 4] = h[i] & 0xFF;
    full[i * 4 + 1] = (h[i] >>> 8) & 0xFF;
    full[i * 4 + 2] = (h[i] >>> 16) & 0xFF;
    full[i * 4 + 3] = (h[i] >>> 24) & 0xFF;
  }
  return full.slice(0, outLen);
}

export class Blake2s {
  /** 无密钥散列，outLen 缺省 32。 */
  static hash(data: Uint8Array, outLen: number = 32): Uint8Array {
    return blake2s(data, new Uint8Array(0), outLen);
  }

  /** keyed 散列（WireGuard 的 MAC(key, input) 原语），outLen 缺省 32。 */
  static keyedHash(key: Uint8Array, data: Uint8Array, outLen: number = 32): Uint8Array {
    return blake2s(data, key, outLen);
  }
}
