/*
 * [Interface] 节（对应上游 tunnel/config/Interface.java）。
 *
 * 结构与校验规则见 specs/config-format.md。字段按契约 docs/dev-contracts.md §3 定义。
 */

import { Attribute } from './Attribute';
import { BadConfigException, Location, ParseClass, ParseException, Reason, Section } from './Exceptions';
import { isHostname, parseAddress } from './InetAddresses';
import { InetNetwork, containsNetwork } from './InetNetwork';
import { parseIntegerStrict, pushUnique } from './Internal';
import { validateKeyText } from './KeyText';

/** DNS 解析结果：服务器地址与搜索域名（对应上游 builder 的两个集合）。 */
export class DnsEntries {
  servers: string[] = [];
  searchDomains: string[] = [];
}

function networkStrings(networks: InetNetwork[]): string[] {
  const result: string[] = [];
  for (const network of networks) {
    result.push(network.toString());
  }
  return result;
}

export class Interface {
  addresses: InetNetwork[] = [];
  dnsServers: string[] = [];
  dnsSearchDomains: string[] = [];
  listenPort: number = 0;
  mtu: number = 0;
  privateKey: string = '';
  excludedApplications: string[] = [];
  includedApplications: string[] = [];

  /** 解析 [Interface] 节的所有属性行（多个节已由 Config 合并）。 */
  static parse(lines: string[]): Interface {
    const iface = new Interface();
    for (const line of lines) {
      const attribute = Attribute.parse(line);
      if (attribute === null) {
        throw BadConfigException.sectionError(Section.INTERFACE, Reason.SYNTAX_ERROR, line);
      }
      const key = attribute.key.toLowerCase();
      if (key === 'address') {
        for (const network of Interface.parseAddresses(attribute.value)) {
          if (!containsNetwork(iface.addresses, network)) {
            iface.addresses.push(network);
          }
        }
      } else if (key === 'dns') {
        const dns = Interface.parseDns(attribute.value);
        for (const server of dns.servers) {
          pushUnique(iface.dnsServers, server);
        }
        for (const domain of dns.searchDomains) {
          pushUnique(iface.dnsSearchDomains, domain);
        }
      } else if (key === 'excludedapplications') {
        for (const app of Interface.parseApplications(attribute.value)) {
          pushUnique(iface.excludedApplications, app);
        }
      } else if (key === 'includedapplications') {
        for (const app of Interface.parseApplications(attribute.value)) {
          pushUnique(iface.includedApplications, app);
        }
      } else if (key === 'listenport') {
        iface.listenPort = Interface.parseListenPort(attribute.value);
      } else if (key === 'mtu') {
        iface.mtu = Interface.parseMtu(attribute.value);
      } else if (key === 'privatekey') {
        iface.privateKey = validateKeyText(Section.INTERFACE, Location.PRIVATE_KEY, attribute.value);
      } else {
        throw BadConfigException.sectionError(Section.INTERFACE, Reason.UNKNOWN_ATTRIBUTE, attribute.key);
      }
    }
    iface.finish();
    return iface;
  }

  /** 校验一组逗号分隔的 IP 网络。 */
  static parseAddresses(value: string): InetNetwork[] {
    const result: InetNetwork[] = [];
    for (const item of Attribute.split(value)) {
      let network: InetNetwork;
      try {
        network = InetNetwork.parse(item);
      } catch (e) {
        const parseError = e as ParseException;
        throw BadConfigException.parseError(Section.INTERFACE, Location.ADDRESS,
          parseError.parseClass, parseError.text);
      }
      if (!containsNetwork(result, network)) {
        result.push(network);
      }
    }
    return result;
  }

  /** 校验 DNS 值：可解析为地址的条目为服务器，符合主机名的为搜索域名，否则报错。 */
  static parseDns(value: string): DnsEntries {
    const result = new DnsEntries();
    for (const item of Attribute.split(value)) {
      try {
        pushUnique(result.servers, parseAddress(item));
      } catch (e) {
        const parseError = e as ParseException;
        if (parseError.parseClass === ParseClass.IP_ADDRESS && isHostname(item)) {
          pushUnique(result.searchDomains, item);
        } else {
          throw BadConfigException.parseError(Section.INTERFACE, Location.DNS,
            parseError.parseClass, parseError.text);
        }
      }
    }
    return result;
  }

  /** 校验监听端口（0–65535，0 表示随机）。 */
  static parseListenPort(value: string): number {
    let port: number;
    try {
      port = parseIntegerStrict(value);
    } catch (e) {
      throw new BadConfigException(Section.INTERFACE, Location.LISTEN_PORT, Reason.INVALID_NUMBER, value);
    }
    if (port < 0 || port > 65535) {
      throw BadConfigException.valueError(Section.INTERFACE, Location.LISTEN_PORT, value);
    }
    return port;
  }

  /** 校验 MTU（非负整数，0 表示自动）。 */
  static parseMtu(value: string): number {
    let mtu: number;
    try {
      mtu = parseIntegerStrict(value);
    } catch (e) {
      throw new BadConfigException(Section.INTERFACE, Location.MTU, Reason.INVALID_NUMBER, value);
    }
    if (mtu < 0) {
      throw BadConfigException.valueError(Section.INTERFACE, Location.MTU, value);
    }
    return mtu;
  }

  /** 拆分应用过滤列表。 */
  static parseApplications(value: string): string[] {
    return Attribute.split(value);
  }

  /** 编辑器保存前的完整校验（复用与解析相同的规则）。 */
  validate(): BadConfigException | null {
    try {
      if (this.privateKey.length === 0) {
        throw new BadConfigException(Section.INTERFACE, Location.PRIVATE_KEY, Reason.MISSING_ATTRIBUTE);
      }
      validateKeyText(Section.INTERFACE, Location.PRIVATE_KEY, this.privateKey);
      if (this.addresses.length > 0) {
        Interface.parseAddresses(Attribute.join(networkStrings(this.addresses)));
      }
      if (this.dnsServers.length > 0 || this.dnsSearchDomains.length > 0) {
        Interface.parseDns(Attribute.join(this.dnsServers.concat(this.dnsSearchDomains)));
      }
      Interface.parseListenPort(this.listenPort.toString());
      Interface.parseMtu(this.mtu.toString());
      if (this.excludedApplications.length > 0 && this.includedApplications.length > 0) {
        throw new BadConfigException(Section.INTERFACE, Location.INCLUDED_APPLICATIONS,
          Reason.APPLICATION_FILTER_CONFLICT);
      }
    } catch (e) {
      return e as BadConfigException;
    }
    return null;
  }

  toWgQuickString(): string {
    let text = '';
    if (this.addresses.length > 0) {
      text += `Address = ${Attribute.join(networkStrings(this.addresses))}\n`;
    }
    if (this.dnsServers.length > 0 || this.dnsSearchDomains.length > 0) {
      const all: string[] = [];
      for (const server of this.dnsServers) {
        all.push(server);
      }
      for (const domain of this.dnsSearchDomains) {
        all.push(domain);
      }
      text += `DNS = ${Attribute.join(all)}\n`;
    }
    if (this.excludedApplications.length > 0) {
      text += `ExcludedApplications = ${Attribute.join(this.excludedApplications)}\n`;
    }
    if (this.includedApplications.length > 0) {
      text += `IncludedApplications = ${Attribute.join(this.includedApplications)}\n`;
    }
    if (this.listenPort > 0) {
      text += `ListenPort = ${this.listenPort}\n`;
    }
    if (this.mtu > 0) {
      text += `MTU = ${this.mtu}\n`;
    }
    if (this.privateKey.length > 0) {
      text += `PrivateKey = ${this.privateKey}\n`;
    }
    return text;
  }

  /** 必填项与互斥项检查（仅解析路径调用）。 */
  private finish(): void {
    if (this.privateKey.length === 0) {
      throw new BadConfigException(Section.INTERFACE, Location.PRIVATE_KEY, Reason.MISSING_ATTRIBUTE);
    }
    if (this.excludedApplications.length > 0 && this.includedApplications.length > 0) {
      throw new BadConfigException(Section.INTERFACE, Location.INCLUDED_APPLICATIONS,
        Reason.APPLICATION_FILTER_CONFLICT);
    }
  }
}
