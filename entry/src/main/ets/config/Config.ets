/*
 * wg-quick 配置（对应上游 tunnel/config/Config.java）。
 *
 * 解析规则见 specs/config-format.md：多个 [Interface] 节合并，[Peer] 节各自独立；
 * 第一个节标题之前仅允许空行与注释。
 */

import { BadConfigException, Reason, Section } from './Exceptions';
import { Interface } from './Interface';
import { Peer } from './Peer';

export class Config {
  interface: Interface;
  peers: Peer[];

  constructor(iface: Interface, peers: Peer[]) {
    this.interface = iface;
    this.peers = peers;
  }

  /** 从编辑器模型构造（不做校验，保存前调用 validate）。 */
  static from(iface: Interface, peers: Peer[]): Config {
    return new Config(iface, peers);
  }

  /** 解析 wg-quick 文本；失败抛中文本地化的 BadConfigException。 */
  static parse(text: string): Config {
    const rawLines = text.split(/\r\n|\r|\n/);
    const interfaceLines: string[] = [];
    const peerGroups: string[][] = [];
    let currentPeer: string[] | null = null;
    let mode = 0; // 0 = 未进入任何节，1 = Interface，2 = Peer
    let seenInterface = false;
    for (const rawLine of rawLines) {
      let line = rawLine;
      const commentIndex = line.indexOf('#');
      if (commentIndex !== -1) {
        line = line.substring(0, commentIndex);
      }
      line = line.trim();
      if (line.length === 0) {
        continue;
      }
      if (line.startsWith('[')) {
        if (currentPeer !== null) {
          peerGroups.push(currentPeer);
          currentPeer = null;
        }
        const lower = line.toLowerCase();
        if (lower === '[interface]') {
          mode = 1;
          seenInterface = true;
        } else if (lower === '[peer]') {
          mode = 2;
          currentPeer = [];
        } else {
          throw BadConfigException.sectionError(Section.CONFIG, Reason.UNKNOWN_SECTION, line);
        }
      } else if (mode === 1) {
        interfaceLines.push(line);
      } else if (mode === 2) {
        if (currentPeer !== null) {
          currentPeer.push(line);
        }
      } else {
        throw BadConfigException.sectionError(Section.CONFIG, Reason.UNKNOWN_SECTION, line);
      }
    }
    if (currentPeer !== null) {
      peerGroups.push(currentPeer);
    }
    if (!seenInterface) {
      throw BadConfigException.sectionError(Section.CONFIG, Reason.MISSING_SECTION);
    }
    const iface = Interface.parse(interfaceLines);
    const peers: Peer[] = [];
    for (const group of peerGroups) {
      peers.push(Peer.parse(group));
    }
    return new Config(iface, peers);
  }

  /** 编辑器保存前的完整校验；返回首个错误，全部合法返回 null。 */
  validate(): BadConfigException | null {
    const interfaceError = this.interface.validate();
    if (interfaceError !== null) {
      return interfaceError;
    }
    for (const peer of this.peers) {
      const peerError = peer.validate();
      if (peerError !== null) {
        return peerError;
      }
    }
    return null;
  }

  /** 标准 wg-quick 序列化（specs/config-format.md §导出序列化）。 */
  toWgQuickString(): string {
    let text = `[Interface]\n${this.interface.toWgQuickString()}`;
    for (const peer of this.peers) {
      text += `\n[Peer]\n${peer.toWgQuickString()}`;
    }
    return text;
  }
}
