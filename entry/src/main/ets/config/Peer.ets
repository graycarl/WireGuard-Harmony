/*
 * [Peer] 节（对应上游 tunnel/config/Peer.java）。
 *
 * 结构与校验规则见 specs/config-format.md。字段按契约 docs/dev-contracts.md §3 定义。
 */

import { Attribute } from './Attribute';
import { BadConfigException, Location, ParseException, Reason, Section } from './Exceptions';
import { InetNetwork, containsNetwork } from './InetNetwork';
import { InetEndpoint } from './InetEndpoint';
import { parseIntegerStrict } from './Internal';
import { validateKeyText } from './KeyText';

const MAX_PERSISTENT_KEEPALIVE = 65535;

function networkStrings(networks: InetNetwork[]): string[] {
  const result: string[] = [];
  for (const network of networks) {
    result.push(network.toString());
  }
  return result;
}

export class Peer {
  publicKey: string = '';
  presharedKey: string = '';
  allowedIPs: InetNetwork[] = [];
  endpoint: InetEndpoint | null = null;
  persistentKeepalive: number = 0;

  /** 解析 [Peer] 节的所有属性行。 */
  static parse(lines: string[]): Peer {
    const peer = new Peer();
    for (const line of lines) {
      const attribute = Attribute.parse(line);
      if (attribute === null) {
        throw BadConfigException.sectionError(Section.PEER, Reason.SYNTAX_ERROR, line);
      }
      const key = attribute.key.toLowerCase();
      if (key === 'allowedips') {
        for (const network of Peer.parseAllowedIPs(attribute.value)) {
          if (!containsNetwork(peer.allowedIPs, network)) {
            peer.allowedIPs.push(network);
          }
        }
      } else if (key === 'endpoint') {
        peer.endpoint = Peer.parseEndpoint(attribute.value);
      } else if (key === 'persistentkeepalive') {
        peer.persistentKeepalive = Peer.parsePersistentKeepalive(attribute.value);
      } else if (key === 'presharedkey') {
        peer.presharedKey = validateKeyText(Section.PEER, Location.PRE_SHARED_KEY, attribute.value);
      } else if (key === 'publickey') {
        peer.publicKey = validateKeyText(Section.PEER, Location.PUBLIC_KEY, attribute.value);
      } else {
        throw BadConfigException.sectionError(Section.PEER, Reason.UNKNOWN_ATTRIBUTE, attribute.key);
      }
    }
    peer.finish();
    return peer;
  }

  /** 校验一组逗号分隔的路由段。 */
  static parseAllowedIPs(value: string): InetNetwork[] {
    const result: InetNetwork[] = [];
    for (const item of Attribute.split(value)) {
      let network: InetNetwork;
      try {
        network = InetNetwork.parse(item);
      } catch (e) {
        const parseError = e as ParseException;
        throw BadConfigException.parseError(Section.PEER, Location.ALLOWED_IPS,
          parseError.parseClass, parseError.text);
      }
      if (!containsNetwork(result, network)) {
        result.push(network);
      }
    }
    return result;
  }

  /** 校验对端。 */
  static parseEndpoint(value: string): InetEndpoint {
    try {
      return InetEndpoint.parse(value);
    } catch (e) {
      const parseError = e as ParseException;
      throw BadConfigException.parseError(Section.PEER, Location.ENDPOINT,
        parseError.parseClass, parseError.text);
    }
  }

  /** 校验保活间隔（0–65535 秒，0 表示关闭）。 */
  static parsePersistentKeepalive(value: string): number {
    let seconds: number;
    try {
      seconds = parseIntegerStrict(value);
    } catch (e) {
      throw new BadConfigException(Section.PEER, Location.PERSISTENT_KEEPALIVE,
        Reason.INVALID_NUMBER, value);
    }
    if (seconds < 0 || seconds > MAX_PERSISTENT_KEEPALIVE) {
      throw BadConfigException.valueError(Section.PEER, Location.PERSISTENT_KEEPALIVE, value);
    }
    return seconds;
  }

  /** 编辑器保存前的完整校验（复用与解析相同的规则）。 */
  validate(): BadConfigException | null {
    try {
      if (this.publicKey.length === 0) {
        throw new BadConfigException(Section.PEER, Location.PUBLIC_KEY, Reason.MISSING_ATTRIBUTE);
      }
      validateKeyText(Section.PEER, Location.PUBLIC_KEY, this.publicKey);
      if (this.presharedKey.length > 0) {
        validateKeyText(Section.PEER, Location.PRE_SHARED_KEY, this.presharedKey);
      }
      if (this.allowedIPs.length > 0) {
        Peer.parseAllowedIPs(Attribute.join(networkStrings(this.allowedIPs)));
      }
      Peer.parsePersistentKeepalive(this.persistentKeepalive.toString());
    } catch (e) {
      return e as BadConfigException;
    }
    if (this.endpoint !== null) {
      try {
        Peer.parseEndpoint(this.endpoint.toString());
      } catch (e) {
        return e as BadConfigException;
      }
    }
    return null;
  }

  toWgQuickString(): string {
    let text = '';
    if (this.allowedIPs.length > 0) {
      text += `AllowedIPs = ${Attribute.join(networkStrings(this.allowedIPs))}\n`;
    }
    if (this.endpoint !== null) {
      text += `Endpoint = ${this.endpoint.toString()}\n`;
    }
    if (this.persistentKeepalive > 0) {
      text += `PersistentKeepalive = ${this.persistentKeepalive}\n`;
    }
    if (this.presharedKey.length > 0) {
      text += `PresharedKey = ${this.presharedKey}\n`;
    }
    if (this.publicKey.length > 0) {
      text += `PublicKey = ${this.publicKey}\n`;
    }
    return text;
  }

  /** 必填项检查（仅解析路径调用）。 */
  private finish(): void {
    if (this.publicKey.length === 0) {
      throw new BadConfigException(Section.PEER, Location.PUBLIC_KEY, Reason.MISSING_ATTRIBUTE);
    }
  }
}
