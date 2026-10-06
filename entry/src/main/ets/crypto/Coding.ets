/**
 * base64 / hex 编解码（纯实现，不依赖平台 API）。
 *
 * base64 解码为严格模式：字符集仅 A-Za-z0-9+/，`=` padding 只允许出现在末尾（0~2 个），
 * 总长度必须是 4 的倍数。任何违规抛 Error（调用方按需映射为 KeyFormatException）。
 */

const B64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/** 字符 → 6bit 值；非法字符返回 -1。 */
function b64Value(ch: string): number {
  const code = ch.charCodeAt(0);
  if (code >= 65 && code <= 90) { // A-Z
    return code - 65;
  }
  if (code >= 97 && code <= 122) { // a-z
    return code - 97 + 26;
  }
  if (code >= 48 && code <= 57) { // 0-9
    return code - 48 + 52;
  }
  if (code === 43) { // '+'
    return 62;
  }
  if (code === 47) { // '/'
    return 63;
  }
  return -1;
}

export class Coding {
  /** 严格 base64 解码。非法字符/非法 padding/长度非 4 倍数均抛 Error。 */
  static base64Decode(input: string): Uint8Array {
    if (input.length % 4 !== 0) {
      throw new Error('base64 长度不是 4 的倍数');
    }
    let padding = 0;
    if (input.length > 0 && input.charAt(input.length - 1) === '=') {
      padding++;
    }
    if (input.length > 1 && input.charAt(input.length - 2) === '=') {
      padding++;
    }
    // '=' 只能出现在末尾
    for (let i = 0; i < input.length - padding; i++) {
      if (b64Value(input.charAt(i)) < 0) {
        throw new Error('base64 含错误字符');
      }
    }
    const outLen = (input.length / 4) * 3 - padding;
    const out = new Uint8Array(outLen);
    let outPos = 0;
    for (let i = 0; i < input.length; i += 4) {
      let acc = 0;
      for (let j = 0; j < 4; j++) {
        const v = b64Value(input.charAt(i + j));
        acc = (acc << 6) | (v < 0 ? 0 : v);
      }
      if (outPos < outLen) {
        out[outPos++] = (acc >>> 16) & 0xFF;
      }
      if (outPos < outLen) {
        out[outPos++] = (acc >>> 8) & 0xFF;
      }
      if (outPos < outLen) {
        out[outPos++] = acc & 0xFF;
      }
    }
    return out;
  }

  /** base64 编码（带标准 padding）。 */
  static base64Encode(data: Uint8Array): string {
    let out = '';
    for (let i = 0; i < data.length; i += 3) {
      const b0 = data[i];
      const b1 = i + 1 < data.length ? data[i + 1] : 0;
      const b2 = i + 2 < data.length ? data[i + 2] : 0;
      const acc = (b0 << 16) | (b1 << 8) | b2;
      out += B64_ALPHABET.charAt((acc >>> 18) & 63);
      out += B64_ALPHABET.charAt((acc >>> 12) & 63);
      out += i + 1 < data.length ? B64_ALPHABET.charAt((acc >>> 6) & 63) : '=';
      out += i + 2 < data.length ? B64_ALPHABET.charAt(acc & 63) : '=';
    }
    return out;
  }

  /** hex 解码（大小写均可；长度必须为偶数，非法字符抛 Error）。 */
  static hexDecode(input: string): Uint8Array {
    if (input.length % 2 !== 0) {
      throw new Error('hex 长度必须为偶数');
    }
    const out = new Uint8Array(input.length / 2);
    for (let i = 0; i < out.length; i++) {
      const hi = Coding.hexValue(input.charAt(i * 2));
      const lo = Coding.hexValue(input.charAt(i * 2 + 1));
      if (hi < 0 || lo < 0) {
        throw new Error('hex 含错误字符');
      }
      out[i] = (hi << 4) | lo;
    }
    return out;
  }

  /** hex 编码（小写）。 */
  static hexEncode(data: Uint8Array): string {
    const digits = '0123456789abcdef';
    let out = '';
    for (let i = 0; i < data.length; i++) {
      out += digits.charAt(data[i] >>> 4);
      out += digits.charAt(data[i] & 0xF);
    }
    return out;
  }

  private static hexValue(ch: string): number {
    const code = ch.charCodeAt(0);
    if (code >= 48 && code <= 57) { // 0-9
      return code - 48;
    }
    if (code >= 97 && code <= 102) { // a-f
      return code - 97 + 10;
    }
    if (code >= 65 && code <= 70) { // A-F
      return code - 65 + 10;
    }
    return -1;
  }
}
