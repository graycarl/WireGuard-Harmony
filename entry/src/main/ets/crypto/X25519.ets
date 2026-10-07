/**
 * X25519（RFC 7748）纯 ArkTS 实现 —— 仅用于「由私钥派生公钥」的标量乘。
 *
 * 为什么自实现而不薄封装 cryptoFramework：
 * 真机实测 SDK 的 `cryptoFramework.createAsyKeyGeneratorBySpec(X25519PriKeySpec)`
 * 在设备上直接失败（hilog）：
 *   HCF: Class is not match. expect class: OPENSSL.ED25519.KEYGENERATOR,
 *        input class: OPENSSL.X25519.KEYGENERATOR
 *   EngineGenerateAlg25519KeyPairBySpec: Invalid params spec → generate key pair fail
 * 即该路径不可用；而 X25519 标量乘是纯算法，自实现后可用 RFC 7748 官方向量本地单测
 * （符合 docs/decisions/0007 的可测性分层）。
 *
 * 安全说明：本实现只处理本机私钥 × 基点（或对端公钥），不暴露于攻击者可控的时序侧信道；
 * 未做常数时间实现（BigInt 无法保证），风险可接受。
 */

const P: bigint = (1n << 255n) - 19n; // 2^255 - 19
const A24: bigint = 121665n;

/** 小端 32 字节 → bigint。 */
function leToBig(bytes: Uint8Array): bigint {
  let v = 0n;
  for (let i = bytes.length - 1; i >= 0; i--) {
    v = (v << 8n) | BigInt(bytes[i]);
  }
  return v;
}

/** bigint → 小端 32 字节。 */
function bigToLe(value: bigint): Uint8Array {
  const out = new Uint8Array(32);
  let rest = value;
  for (let i = 0; i < 32; i++) {
    out[i] = Number(rest & 0xFFn);
    rest = rest >> 8n;
  }
  return out;
}

/** mod p（保证非负）。 */
function mod(value: bigint): bigint {
  const r = value % P;
  return r < 0n ? r + P : r;
}

/** 模幂：base^exp mod p（平方-乘法）。 */
function modPow(base: bigint, exp: bigint): bigint {
  let result = 1n;
  let b = mod(base);
  let e = exp;
  while (e > 0n) {
    if ((e & 1n) === 1n) {
      result = (result * b) % P;
    }
    b = (b * b) % P;
    e >>= 1n;
  }
  return result;
}

/** 私钥 clamp（RFC 7748 §5）。 */
function clampScalar(scalar: Uint8Array): Uint8Array {
  if (scalar.length !== 32) {
    throw new Error('X25519 私钥长度必须为 32 字节');
  }
  const k = scalar.slice();
  k[0] = k[0] & 248;
  k[31] = k[31] & 127;
  k[31] = k[31] | 64;
  return k;
}

/**
 * X25519 标量乘（Montgomery ladder）：返回 32 字节小端结果。
 * @param scalar 32 字节私钥（内部会被 clamp）
 * @param uCoordinate 32 字节 u 坐标（公钥；基点 = 9 后跟 31 个 0）
 */
export function x25519(scalar: Uint8Array, uCoordinate: Uint8Array): Uint8Array {
  const k = clampScalar(scalar);
  const kBig = leToBig(k);
  // RFC 7748：解码 u 时忽略最高位
  const u = uCoordinate.slice();
  u[31] = u[31] & 127;
  const x1 = mod(leToBig(u));

  let x2 = 1n;
  let z2 = 0n;
  let x3 = x1;
  let z3 = 1n;
  let swap = 0n;

  for (let t = 254; t >= 0; t--) {
    const kt = (kBig >> BigInt(t)) & 1n;
    swap = swap ^ kt;
    if (swap === 1n) {
      let tmp = x2;
      x2 = x3;
      x3 = tmp;
      tmp = z2;
      z2 = z3;
      z3 = tmp;
    }
    swap = kt;

    const a = mod(x2 + z2);
    const aa = mod(a * a);
    const b = mod(x2 - z2);
    const bb = mod(b * b);
    const e = mod(aa - bb);
    const c = mod(x3 + z3);
    const d = mod(x3 - z3);
    const da = mod(d * a);
    const cb = mod(c * b);
    const daPlusCb = mod(da + cb);
    const daMinusCb = mod(da - cb);
    x3 = mod(daPlusCb * daPlusCb);
    z3 = mod(x1 * mod(daMinusCb * daMinusCb));
    x2 = mod(aa * bb);
    z2 = mod(e * mod(aa + mod(A24 * e)));
  }

  if (swap === 1n) {
    let tmp = x2;
    x2 = x3;
    x3 = tmp;
    tmp = z2;
    z2 = z3;
    z3 = tmp;
  }

  // z2^(p-2) = z2^{-1} mod p
  const inv = modPow(z2, P - 2n);
  return bigToLe(mod(x2 * inv));
}

/** X25519 基点（u = 9）。 */
export function basePoint(): Uint8Array {
  const u = new Uint8Array(32);
  u[0] = 9;
  return u;
}

/** 由私钥（32 字节）派生公钥（base point 标量乘）。 */
export function publicKeyFrom(privateKey: Uint8Array): Uint8Array {
  return x25519(privateKey, basePoint());
}
