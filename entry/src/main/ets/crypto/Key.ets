/**
 * WireGuard 密钥值对象（32 字节，base64 编码 44 字符、末位 '='）。
 *
 * 错误语义对齐上游 KeyFormatException（specs/config-format.md §密钥编码）：
 * - LENGTH   → 「密钥长度错误」（base64 非 44 字符或解码后非 32 字节）
 * - CONTENTS → 「密钥中含错误字符」（字符集/padding 非法）
 */
import { Coding } from './Coding';
import { secureRandomBytes } from './PlatformRandom';

export enum KeyFormatType {
  LENGTH,
  CONTENTS
}

export class KeyFormatException extends Error {
  readonly formatType: KeyFormatType;
  readonly input: string;

  constructor(formatType: KeyFormatType, input: string) {
    super(formatType === KeyFormatType.LENGTH ? '密钥长度错误' : '密钥中含错误字符');
    this.name = 'KeyFormatException';
    this.formatType = formatType;
    this.input = input;
  }
}

/** 随机源注入类型：测试注入确定性 rng，设备侧缺省走 cryptoFramework。 */
export type RandomSource = (len: number) => Uint8Array;

export class Key {
  static readonly LENGTH_BYTES: number = 32;
  static readonly LENGTH_BASE64: number = 44;

  private readonly bytes: Uint8Array;

  constructor(bytes: Uint8Array) {
    if (bytes.length !== Key.LENGTH_BYTES) {
      throw new KeyFormatException(KeyFormatType.LENGTH, '');
    }
    this.bytes = bytes.slice();
  }

  /** 从 base64（44 字符）解析，失败抛 KeyFormatException。长度校验先于字符校验（对齐上游）。 */
  static fromBase64(base64: string): Key {
    if (base64.length !== Key.LENGTH_BASE64) {
      throw new KeyFormatException(KeyFormatType.LENGTH, base64);
    }
    let decoded: Uint8Array;
    try {
      decoded = Coding.base64Decode(base64);
    } catch (e) {
      throw new KeyFormatException(KeyFormatType.CONTENTS, base64);
    }
    if (decoded.length !== Key.LENGTH_BYTES) {
      throw new KeyFormatException(KeyFormatType.LENGTH, base64);
    }
    return new Key(decoded);
  }

  /** 生成随机密钥。rng 缺省为设备加密随机源（本地单测必须注入确定性 rng）。 */
  static generate(rng?: RandomSource): Key {
    const source: RandomSource = rng !== undefined ? rng : secureRandomBytes;
    const bytes = source(Key.LENGTH_BYTES);
    if (bytes.length !== Key.LENGTH_BYTES) {
      throw new KeyFormatException(KeyFormatType.LENGTH, '');
    }
    return new Key(bytes);
  }

  toBase64(): string {
    return Coding.base64Encode(this.bytes);
  }

  /** 返回副本，外部修改不影响本对象。 */
  toBytes(): Uint8Array {
    return this.bytes.slice();
  }

  equals(other: Key): boolean {
    for (let i = 0; i < Key.LENGTH_BYTES; i++) {
      if (this.bytes[i] !== other.bytes[i]) {
        return false;
      }
    }
    return true;
  }
}
