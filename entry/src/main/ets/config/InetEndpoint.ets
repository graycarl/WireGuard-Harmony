/*
 * 对端（主机:端口，对应上游 tunnel/config/InetEndpoint.java）。
 *
 * 与上游的差异（specs/config-format.md 差异 3）：整串禁止 `/ ? # @`
 * （上游允许 `@`，会导致实际连接的域名被静默改变）。
 */

import { ParseClass, ParseException } from './Exceptions';
import { isIpv4, isIpv6 } from './InetAddresses';

const FORBIDDEN_CHARACTERS = /[/?#@]/;
const DIGITS_ONLY = /^[0-9]+$/;

export class InetEndpoint {
  readonly host: string;
  readonly port: number;
  private readonly ipv6: boolean;

  constructor(host: string, port: number, ipv6: boolean) {
    this.host = host;
    this.port = port;
    this.ipv6 = ipv6;
  }

  /** 解析 `主机:端口`；主机可为 IPv4、`[IPv6]` 或域名。 */
  static parse(endpoint: string): InetEndpoint {
    if (FORBIDDEN_CHARACTERS.test(endpoint)) {
      throw new ParseException(ParseClass.ENDPOINT, endpoint);
    }
    let host = '';
    let portText = '';
    let ipv6 = false;
    if (endpoint.startsWith('[')) {
      const close = endpoint.indexOf(']');
      if (close < 0) {
        throw new ParseException(ParseClass.ENDPOINT, endpoint);
      }
      host = endpoint.substring(1, close);
      const rest = endpoint.substring(close + 1);
      if (!rest.startsWith(':')) {
        throw new ParseException(ParseClass.ENDPOINT, endpoint);
      }
      portText = rest.substring(1);
      if (!isIpv6(host)) {
        throw new ParseException(ParseClass.ENDPOINT, endpoint);
      }
      ipv6 = true;
    } else {
      const colon = endpoint.lastIndexOf(':');
      if (colon < 0) {
        throw new ParseException(ParseClass.ENDPOINT, endpoint);
      }
      host = endpoint.substring(0, colon);
      portText = endpoint.substring(colon + 1);
      if (host.length === 0 || host.indexOf(':') >= 0) {
        throw new ParseException(ParseClass.ENDPOINT, endpoint);
      }
      if (isIpv4(host)) {
        ipv6 = false;
      }
    }
    if (!DIGITS_ONLY.test(portText)) {
      throw new ParseException(ParseClass.ENDPOINT, endpoint);
    }
    const port = parsePort(portText);
    if (port < 0 || port > 65535) {
      throw new ParseException(ParseClass.ENDPOINT, endpoint);
    }
    return new InetEndpoint(host, port, ipv6);
  }

  get isIpv6(): boolean {
    return this.ipv6;
  }

  toString(): string {
    return `${this.ipv6 ? `[${this.host}]` : this.host}:${this.port}`;
  }

  equals(other: InetEndpoint): boolean {
    return this.host === other.host && this.port === other.port;
  }
}

function parsePort(text: string): number {
  let result = 0;
  for (let i = 0; i < text.length; i++) {
    result = result * 10 + (text.charCodeAt(i) - 48);
  }
  return result;
}
