/*
 * 纯逻辑小工具（不依赖任何平台 API）。
 */

import { ParseClass, ParseException } from './Exceptions';

/** 严格整数解析（拒绝 `12abc`、`1.5`；允许前导 +/-），失败抛 ParseException。 */
export function parseIntegerStrict(value: string): number {
  if (!/^[+-]?[0-9]+$/.test(value)) {
    throw new ParseException(ParseClass.NUMBER, value);
  }
  let negative = false;
  let start = 0;
  if (value.charAt(0) === '+') {
    start = 1;
  } else if (value.charAt(0) === '-') {
    negative = true;
    start = 1;
  }
  let result = 0;
  for (let i = start; i < value.length; i++) {
    result = result * 10 + (value.charCodeAt(i) - 48);
  }
  return negative ? -result : result;
}

/** 去重追加（保持首次出现顺序，对应上游 LinkedHashSet 语义）。 */
export function pushUnique(target: string[], value: string): void {
  if (!target.includes(value)) {
    target.push(value);
  }
}
