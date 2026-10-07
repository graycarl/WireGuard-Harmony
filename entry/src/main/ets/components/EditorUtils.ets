/*
 * 编辑器纯逻辑（输入过滤、表单草稿 ↔ wg-quick 配置映射）。
 *
 * 不 import @kit → 可本地单测（docs/decisions/0007 第一层）。
 * 需求依据：specs/tunnel-editor.md（字段与输入行为）、specs/config-format.md（校验）。
 */

import { Config } from '../config/Config';
import { Interface, DnsEntries } from '../config/Interface';
import { Peer } from '../config/Peer';
import { InetNetwork } from '../config/InetNetwork';
import { isIpv4 } from '../config/InetAddresses';
import { isExcludeLanExpanded } from '../config/PrivateNetworks';

/** 隧道名最大长度（specs/README.md 公共术语）。 */
export const TUNNEL_NAME_MAX_LENGTH: number = 15;
/** Base64 密钥长度（32 字节 → 44 字符）。 */
export const KEY_BASE64_LENGTH: number = 44;

const BASE64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const NAME_ALLOWED = /^[A-Za-z0-9_=+.-]$/;

let draftCounter: number = 0;

function newDraftId(): string {
  draftCounter++;
  return `peer-${draftCounter}`;
}

/** 是否为空/仅空白文本。 */
export function isBlank(text: string): boolean {
  return text.trim().length === 0;
}

/** 名称输入过滤：仅允许 ASCII 字母、数字及 `_ = + . -`，超长截断。 */
export function filterTunnelNameInput(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    if (out.length >= TUNNEL_NAME_MAX_LENGTH) {
      break;
    }
    const ch = text.charAt(i);
    if (NAME_ALLOWED.test(ch)) {
      out += ch;
    }
  }
  return out;
}

/** 密钥输入过滤：仅 `A-Za-z0-9+/`，第 44 位允许 `=`，总长上限 44。 */
export function filterBase64KeyInput(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    if (out.length >= KEY_BASE64_LENGTH) {
      break;
    }
    const ch = text.charAt(i);
    if (BASE64_ALPHABET.indexOf(ch) >= 0) {
      out += ch;
    } else if (ch === '=' && out.length === KEY_BASE64_LENGTH - 1) {
      out += ch;
    }
  }
  return out;
}

/** 数字输入过滤（监听端口/MTU/保活间隔）。 */
export function filterDigitsInput(text: string, maxLength: number): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    if (out.length >= maxLength) {
      break;
    }
    const ch = text.charAt(i);
    if (ch >= '0' && ch <= '9') {
      out += ch;
    }
  }
  return out;
}

/** 逗号分隔文本 → 去空白、去空的片段列表。 */
export function splitListText(text: string): string[] {
  const out: string[] = [];
  for (const part of text.split(',')) {
    const trimmed = part.trim();
    if (trimmed.length > 0) {
      out.push(trimmed);
    }
  }
  return out;
}

/** DNS 文本中的 IPv4 字面量服务器（「排除局域网」补入 /32 路由时联动用）。 */
export function parseDnsServerText(text: string): string[] {
  const out: string[] = [];
  for (const item of splitListText(text)) {
    if (isIpv4(item) && !out.includes(item)) {
      out.push(item);
    }
  }
  return out;
}

/** 规范化路由文本（可解析项转标准形式，非法项原样保留）——表单展示用。 */
export function normalizeNetworkText(text: string): string {
  const out: string[] = [];
  for (const item of splitListText(text)) {
    let value = item;
    try {
      value = InetNetwork.parse(item).toString();
    } catch (e) {
      value = item;
    }
    if (!out.includes(value)) {
      out.push(value);
    }
  }
  return out.join(', ');
}

/** 单个 Peer 的表单草稿（纯数据，便于本地单测）。 */
export interface PeerDraft {
  id: string;
  publicKey: string;
  presharedKey: string;
  allowedIPsText: string;
  endpointText: string;
  keepaliveText: string;
  excludeLan: boolean;
}

/** 空白 Peer 草稿（「添加节点」用）。 */
export function emptyPeerDraft(): PeerDraft {
  const draft: PeerDraft = {
    id: newDraftId(),
    publicKey: '',
    presharedKey: '',
    allowedIPsText: '',
    endpointText: '',
    keepaliveText: '',
    excludeLan: false
  };
  return draft;
}

/** 复制草稿（不可变更新用）。 */
export function copyPeerDraft(draft: PeerDraft): PeerDraft {
  const copy: PeerDraft = {
    id: draft.id,
    publicKey: draft.publicKey,
    presharedKey: draft.presharedKey,
    allowedIPsText: draft.allowedIPsText,
    endpointText: draft.endpointText,
    keepaliveText: draft.keepaliveText,
    excludeLan: draft.excludeLan
  };
  return copy;
}

/** 配置中的 Peer → 草稿。 */
export function peerToDraft(peer: Peer): PeerDraft {
  const networks: string[] = [];
  for (const network of peer.allowedIPs) {
    networks.push(network.toString());
  }
  const draft: PeerDraft = {
    id: newDraftId(),
    publicKey: peer.publicKey,
    presharedKey: peer.presharedKey,
    allowedIPsText: networks.join(', '),
    endpointText: peer.endpoint === null ? '' : peer.endpoint.toString(),
    keepaliveText: peer.persistentKeepalive > 0 ? `${peer.persistentKeepalive}` : '',
    excludeLan: isExcludeLanExpanded(networks)
  };
  return draft;
}

/** 草稿 → Peer；非法输入抛 BadConfigException（message 即用户可见文案）。 */
export function draftToPeer(draft: PeerDraft): Peer {
  const peer = new Peer();
  peer.publicKey = draft.publicKey;
  peer.presharedKey = draft.presharedKey;
  peer.allowedIPs = isBlank(draft.allowedIPsText) ? [] : Peer.parseAllowedIPs(draft.allowedIPsText);
  peer.endpoint = isBlank(draft.endpointText) ? null : Peer.parseEndpoint(draft.endpointText.trim());
  peer.persistentKeepalive = isBlank(draft.keepaliveText)
    ? 0
    : Peer.parsePersistentKeepalive(draft.keepaliveText.trim());
  return peer;
}

/** 单个「本地（Interface）」的表单草稿。 */
export interface InterfaceDraft {
  privateKey: string;
  addressesText: string;
  listenPortText: string;
  dnsText: string;
  mtuText: string;
  /** 'none' | 'excluded' | 'included' */
  filterMode: string;
  filterApps: string[];
}

/** 空白的本地草稿。 */
export function emptyInterfaceDraft(): InterfaceDraft {
  const draft: InterfaceDraft = {
    privateKey: '',
    addressesText: '',
    listenPortText: '',
    dnsText: '',
    mtuText: '',
    filterMode: 'none',
    filterApps: []
  };
  return draft;
}

/** 配置中的 Interface → 草稿。 */
export function interfaceToDraft(iface: Interface): InterfaceDraft {
  const addresses: string[] = [];
  for (const network of iface.addresses) {
    addresses.push(network.toString());
  }
  const dns: string[] = [];
  for (const server of iface.dnsServers) {
    dns.push(server);
  }
  for (const domain of iface.dnsSearchDomains) {
    dns.push(domain);
  }
  let mode = 'none';
  let apps: string[] = [];
  if (iface.includedApplications.length > 0) {
    mode = 'included';
    apps = iface.includedApplications.slice();
  } else if (iface.excludedApplications.length > 0) {
    mode = 'excluded';
    apps = iface.excludedApplications.slice();
  }
  const draft: InterfaceDraft = {
    privateKey: iface.privateKey,
    addressesText: addresses.join(', '),
    listenPortText: iface.listenPort > 0 ? `${iface.listenPort}` : '',
    dnsText: dns.join(', '),
    mtuText: iface.mtu > 0 ? `${iface.mtu}` : '',
    filterMode: mode,
    filterApps: apps
  };
  return draft;
}

/** 草稿 → Interface；非法输入抛 BadConfigException。 */
export function draftToInterface(draft: InterfaceDraft): Interface {
  const iface = new Interface();
  iface.privateKey = draft.privateKey;
  iface.addresses = isBlank(draft.addressesText) ? [] : Interface.parseAddresses(draft.addressesText);
  let dns: DnsEntries;
  if (isBlank(draft.dnsText)) {
    dns = new DnsEntries();
  } else {
    dns = Interface.parseDns(draft.dnsText);
  }
  iface.dnsServers = dns.servers;
  iface.dnsSearchDomains = dns.searchDomains;
  iface.listenPort = isBlank(draft.listenPortText) ? 0 : Interface.parseListenPort(draft.listenPortText.trim());
  iface.mtu = isBlank(draft.mtuText) ? 0 : Interface.parseMtu(draft.mtuText.trim());
  if (draft.filterMode === 'included') {
    iface.includedApplications = draft.filterApps.slice();
  } else if (draft.filterMode === 'excluded') {
    iface.excludedApplications = draft.filterApps.slice();
  }
  return iface;
}

/**
 * 表单 → 通过完整校验的 Config。
 * 字段非法或必填缺失时抛 BadConfigException（message 为 spec 规定的中文文案）。
 */
export function draftToConfig(ifaceDraft: InterfaceDraft, peerDrafts: PeerDraft[]): Config {
  const peers: Peer[] = [];
  for (const draft of peerDrafts) {
    peers.push(draftToPeer(draft));
  }
  const config = Config.from(draftToInterface(ifaceDraft), peers);
  const error = config.validate();
  if (error !== null) {
    throw error;
  }
  return config;
}

/** 表单签名（判断是否有未保存改动；不做任何校验）。 */
export function formSignature(ifaceDraft: InterfaceDraft, peerDrafts: PeerDraft[]): string {
  const parts: string[] = [
    ifaceDraft.privateKey,
    ifaceDraft.addressesText,
    ifaceDraft.listenPortText,
    ifaceDraft.dnsText,
    ifaceDraft.mtuText,
    ifaceDraft.filterMode,
    ifaceDraft.filterApps.join(',')
  ];
  for (const draft of peerDrafts) {
    parts.push(`${draft.publicKey}|${draft.presharedKey}|${draft.allowedIPsText}|${draft.endpointText}|${draft.keepaliveText}|${draft.excludeLan}`);
  }
  return parts.join('\u0000');
}
