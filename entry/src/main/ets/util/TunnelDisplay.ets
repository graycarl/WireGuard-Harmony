/*
 * 隧道详情页的展示文案（纯逻辑，可本地单测）。
 *
 * 规则来自 specs/tunnel-detail.md：
 * - 空值字段整行隐藏（本模块返回空串表示不展示）；
 * - 流量「接收：X，发送：Y」，累计收发均为 0 时隐藏；
 * - 上次握手时间：相对时间，从未握手（0）时隐藏；
 * - 应用过滤「对 N 个应用生效」/「对 N 个应用不生效」；
 * - 连接保活「每隔 N 秒」（0 = 关闭，隐藏）。
 */

import { Interface } from '../config/Interface';
import { Peer } from '../config/Peer';
import { InetNetwork } from '../config/InetNetwork';
import { PeerStats } from '../model/PeerStats';
import { formatBytes, formatTimeAgo } from './Format';

/** 逗号分隔的网络列表（空列表返回空串）。 */
export function joinNetworks(networks: InetNetwork[]): string {
  const parts: string[] = [];
  for (const network of networks) {
    parts.push(network.toString());
  }
  return parts.join(', ');
}

/** 逗号分隔的文本列表（空列表返回空串）。 */
export function joinTexts(items: string[]): string {
  return items.join(', ');
}

/** 应用过滤文案；未配置返回空串。 */
export function appFilterText(iface: Interface | null): string {
  if (iface === null) {
    return '';
  }
  if (iface.includedApplications.length > 0) {
    return `对 ${iface.includedApplications.length} 个应用生效`;
  }
  if (iface.excludedApplications.length > 0) {
    return `对 ${iface.excludedApplications.length} 个应用不生效`;
  }
  return '';
}

/** 监听端口（0 = 未设置，隐藏）。 */
export function portText(port: number): string {
  return port > 0 ? `${port}` : '';
}

/** MTU（0 = 自动，隐藏）。 */
export function mtuText(mtu: number): string {
  return mtu > 0 ? `${mtu}` : '';
}

/** 预共享密钥：只显示「已启用」，永不显示内容。 */
export function pskText(presharedKey: string): string {
  return presharedKey.length > 0 ? '已启用' : '';
}

/** 对端文本（未配置返回空串）。 */
export function endpointText(peer: Peer): string {
  return peer.endpoint === null ? '' : peer.endpoint.toString();
}

/** 连接保活（0 = 关闭，隐藏）。 */
export function keepaliveText(seconds: number): string {
  return seconds > 0 ? `每隔 ${seconds} 秒` : '';
}

/** 按公钥在统计快照中查找对应 Peer 的统计。 */
export function findStats(peers: PeerStats[], publicKey: string): PeerStats | null {
  for (const stats of peers) {
    if (stats.publicKey === publicKey) {
      return stats;
    }
  }
  return null;
}

/** 流量文案；累计收发均为 0（或读取失败）返回空串。 */
export function trafficText(stats: PeerStats | null): string {
  if (stats === null) {
    return '';
  }
  if (stats.rxBytes <= 0 && stats.txBytes <= 0) {
    return '';
  }
  return `接收：${formatBytes(stats.rxBytes)}，发送：${formatBytes(stats.txBytes)}`;
}

/** 上次握手时间文案；从未成功握手返回空串。 */
export function handshakeText(stats: PeerStats | null, nowMs: number): string {
  if (stats === null || stats.lastHandshakeMs <= 0) {
    return '';
  }
  return formatTimeAgo(stats.lastHandshakeMs, nowMs);
}
