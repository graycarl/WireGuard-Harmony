/*
 * 隧道名称规则与自然排序（specs/README.md 公共术语、specs/tunnel-list.md 列表排序）。
 *
 * 与上游的差异（tunnel-list.md）：仅大小写不同的名称未定义稳定顺序，
 * 本项目补齐为「大小写不敏感比较，相同则按原始字符串比较」。
 */

const TUNNEL_NAME_PATTERN = /^[A-Za-z0-9_=+.-]{1,15}$/;

/** 隧道名称规则：仅 ASCII 字母、数字及 `_ = + . -`，长度 1–15。 */
export function isValidTunnelName(name: string): boolean {
  return TUNNEL_NAME_PATTERN.test(name);
}

function isDigitChar(code: number): boolean {
  return code >= 48 && code <= 57;
}

function stripLeadingZeros(text: string): string {
  let index = 0;
  while (index < text.length - 1 && text.charAt(index) === '0') {
    index++;
  }
  return text.substring(index);
}

/** 比较两个数字段：返回负数/0/正数。 */
function compareNumberChunks(a: string, b: string): number {
  const left = stripLeadingZeros(a);
  const right = stripLeadingZeros(b);
  if (left.length !== right.length) {
    return left.length - right.length;
  }
  if (left === right) {
    return 0;
  }
  return left < right ? -1 : 1;
}

/**
 * 自然排序：大小写不敏感，数字段按数值比较（wg2 在 wg10 之前）；
 * 完全不区分大小写时相等则按原始字符串比较。
 */
export function compareTunnelNames(a: string, b: string): number {
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    const codeA = a.charCodeAt(i);
    const codeB = b.charCodeAt(j);
    if (isDigitChar(codeA) && isDigitChar(codeB)) {
      let endA = i;
      while (endA < a.length && isDigitChar(a.charCodeAt(endA))) {
        endA++;
      }
      let endB = j;
      while (endB < b.length && isDigitChar(b.charCodeAt(endB))) {
        endB++;
      }
      const diff = compareNumberChunks(a.substring(i, endA), b.substring(j, endB));
      if (diff !== 0) {
        return diff;
      }
      i = endA;
      j = endB;
    } else {
      const lowerA = a.charAt(i).toLowerCase();
      const lowerB = b.charAt(j).toLowerCase();
      if (lowerA !== lowerB) {
        return lowerA < lowerB ? -1 : 1;
      }
      i++;
      j++;
    }
  }
  if (i < a.length) {
    return 1;
  }
  if (j < b.length) {
    return -1;
  }
  if (a === b) {
    return 0;
  }
  return a < b ? -1 : 1;
}
