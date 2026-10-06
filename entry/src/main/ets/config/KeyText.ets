/*
 * WireGuard Base64 密钥文本校验（对应上游 crypto/Key.fromBase64 的校验语义）。
 *
 * 与上游一致：长度必须是 44 字符且末位为 '='，否则报「密钥长度错误」；
 * 长度正确但含 base64 字符集以外的字符（或末位填充不合法）报「密钥中含错误字符」。
 */

import { BadConfigException, KeyFormatType, Location, Section } from './Exceptions';

const BASE64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/** 返回密钥格式错误类型；合法返回 null。 */
export function keyFormatType(value: string): KeyFormatType | null {
  if (value.length !== 44 || value.charAt(43) !== '=') {
    return KeyFormatType.LENGTH;
  }
  for (let i = 0; i < 43; i++) {
    if (BASE64_ALPHABET.indexOf(value.charAt(i)) < 0) {
      return KeyFormatType.CONTENTS;
    }
  }
  // 32 字节的 base64 末段只有 4 位有效数据，最后一位有效字符的低 2 位必须为 0。
  if (BASE64_ALPHABET.indexOf(value.charAt(42)) % 4 !== 0) {
    return KeyFormatType.CONTENTS;
  }
  return null;
}

/** 校验密钥文本，失败抛中文本地化的 BadConfigException。 */
export function validateKeyText(section: Section, field: Location, value: string): string {
  const type = keyFormatType(value);
  if (type !== null) {
    throw BadConfigException.keyError(section, field, type);
  }
  return value;
}
