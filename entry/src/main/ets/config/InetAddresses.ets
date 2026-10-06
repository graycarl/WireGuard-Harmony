/*
 * 数字 IP 地址与主机名校验（对应上游 tunnel/config/InetAddresses.java）。
 *
 * 纯字符串解析，不做 DNS 查询。
 */

import { ParseClass, ParseException } from './Exceptions';

const HOSTNAME_PATTERN = /^(?=.{1,255}$)[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?(?:\.[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?)*\.?$/;

/** 是否为严格 dotted-quad IPv4 字面量。 */
export function isIpv4(value: string): boolean {
  const parts = value.split('.');
  if (parts.length !== 4) {
    return false;
  }
  for (const part of parts) {
    if (part.length === 0 || part.length > 3) {
      return false;
    }
    for (let i = 0; i < part.length; i++) {
      const code = part.charCodeAt(i);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    if (part.length > 1 && part.charAt(0) === '0') {
      return false;
    }
    let octet = 0;
    for (let i = 0; i < part.length; i++) {
      octet = octet * 10 + (part.charCodeAt(i) - 48);
    }
    if (octet > 255) {
      return false;
    }
  }
  return true;
}

/** 是否为 IPv6 字面量（支持 `::` 压缩、末尾内嵌 IPv4、`%zone` 作用域）。 */
export function isIpv6(value: string): boolean {
  let text = value;
  const zoneIndex = text.indexOf('%');
  if (zoneIndex >= 0) {
    if (text.substring(zoneIndex + 1).length === 0) {
      return false;
    }
    text = text.substring(0, zoneIndex);
  }
  if (text.length === 0) {
    return false;
  }
  const doubleIndex = text.indexOf('::');
  const hasDouble = doubleIndex >= 0;
  if (hasDouble && text.indexOf('::', doubleIndex + 1) >= 0) {
    return false;
  }
  let head: string[] = [];
  let tail: string[] = [];
  if (hasDouble) {
    const headText = text.substring(0, doubleIndex);
    const tailText = text.substring(doubleIndex + 2);
    head = headText.length > 0 ? headText.split(':') : [];
    tail = tailText.length > 0 ? tailText.split(':') : [];
  } else {
    head = text.split(':');
  }
  const groups: string[] = [];
  for (const group of head) {
    groups.push(group);
  }
  for (const group of tail) {
    groups.push(group);
  }
  let count = 0;
  for (let i = 0; i < groups.length; i++) {
    const group = groups[i];
    if (group.length === 0) {
      return false;
    }
    if (i === groups.length - 1 && group.indexOf('.') >= 0) {
      if (!isIpv4(group)) {
        return false;
      }
      count += 2;
    } else {
      if (!/^[0-9A-Fa-f]{1,4}$/.test(group)) {
        return false;
      }
      count += 1;
    }
  }
  return hasDouble ? count <= 7 : count === 8;
}

/** 是否为合法 DNS 主机名（搜索域名判定用）。 */
export function isHostname(value: string): boolean {
  return HOSTNAME_PATTERN.test(value);
}

/** 校验并返回数字 IP 地址字符串；失败抛 ParseException(IP 地址)。 */
export function parseAddress(value: string): string {
  if (value.length === 0) {
    throw new ParseException(ParseClass.IP_ADDRESS, value);
  }
  if (isIpv4(value) || isIpv6(value)) {
    return value;
  }
  throw new ParseException(ParseClass.IP_ADDRESS, value);
}
