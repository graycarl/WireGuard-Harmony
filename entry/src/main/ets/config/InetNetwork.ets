/*
 * IP 网络（地址 + 掩码，对应上游 tunnel/config/InetNetwork.java）。
 */

import { ParseClass, ParseException } from './Exceptions';
import { isIpv4, parseAddress } from './InetAddresses';
import { parseIntegerStrict } from './Internal';

export class InetNetwork {
  readonly address: string;
  readonly mask: number;

  constructor(address: string, mask: number) {
    this.address = address;
    this.mask = mask;
  }

  /** 解析 `地址/掩码`（掩码可省略，IPv4 默认 32、IPv6 默认 128）。 */
  static parse(network: string): InetNetwork {
    const slash = network.lastIndexOf('/');
    let rawMask = -1;
    let addressText = network;
    if (slash >= 0) {
      const maskText = network.substring(slash + 1);
      rawMask = parseIntegerStrict(maskText);
      addressText = network.substring(0, slash);
    }
    const address = parseAddress(addressText);
    const maxMask = isIpv4(address) ? 32 : 128;
    if (rawMask > maxMask) {
      throw new ParseException(ParseClass.IP_NETWORK, network);
    }
    const mask = rawMask >= 0 ? rawMask : maxMask;
    return new InetNetwork(address, mask);
  }

  get isIpv4(): boolean {
    return isIpv4(this.address);
  }

  toString(): string {
    return `${this.address}/${this.mask}`;
  }

  equals(other: InetNetwork): boolean {
    return this.address === other.address && this.mask === other.mask;
  }
}

/** 列表中是否已存在等价网络。 */
export function containsNetwork(networks: InetNetwork[], network: InetNetwork): boolean {
  for (const item of networks) {
    if (item.equals(network)) {
      return true;
    }
  }
  return false;
}
