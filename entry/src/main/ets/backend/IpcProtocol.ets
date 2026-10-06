/*
 * UI 进程 ↔ VPN 进程的公共事件协议（纯逻辑，禁 import @kit）。
 *
 * 依据 docs/decisions/0004：VPN 进程在状态迁移与统计更新时发布自定义公共事件，
 * 数据只含隧道名、状态、统计——**绝不含密钥/配置**。
 * payload 为 JSON 字符串，放在 CommonEventPublishData.parameters.payload。
 */

import { PeerStats } from '../model/PeerStats';

/** 自定义公共事件名（应用私有命名空间）。 */
export const TUNNEL_EVENT: string = 'me.graycarl.wireguard.event.TUNNEL';

/** 隧道状态（与 model/TunnelState 的字符串值一致）。 */
export type IpcState = 'up' | 'down';

export interface IpcPayload {
  /** 隧道名 */
  tunnel: string;
  state: IpcState;
  /** 各 Peer 实时统计；down 时为空数组 */
  peers: PeerStats[];
  /** 失败原因（仅「建立失败」时携带），供 UI 展示；正常断开不带 */
  error?: string;
}

/** 序列化（不含任何密钥字段）。 */
export function encodePayload(payload: IpcPayload): string {
  const wire: IpcPayload = {
    tunnel: payload.tunnel,
    state: payload.state,
    peers: payload.peers
  };
  if (payload.error !== undefined && payload.error.length > 0) {
    wire.error = payload.error;
  }
  return JSON.stringify(wire);
}

function asRecord(value: Object): Record<string, Object> | null {
  if (value === null || typeof value !== 'object' || value instanceof Array) {
    return null;
  }
  return value as Record<string, Object>;
}

function parsePeer(value: Object): PeerStats | null {
  const rec = asRecord(value);
  if (rec === null) {
    return null;
  }
  const publicKey = rec['publicKey'];
  const rxBytes = rec['rxBytes'];
  const txBytes = rec['txBytes'];
  const lastHandshakeMs = rec['lastHandshakeMs'];
  const endpoint = rec['endpoint'];
  if (typeof publicKey !== 'string' || typeof rxBytes !== 'number' || typeof txBytes !== 'number' ||
    typeof lastHandshakeMs !== 'number' || typeof endpoint !== 'string') {
    return null;
  }
  const stats: PeerStats = {
    publicKey: publicKey,
    rxBytes: rxBytes,
    txBytes: txBytes,
    lastHandshakeMs: lastHandshakeMs,
    endpoint: endpoint
  };
  return stats;
}

/** 防御式反序列化；非法输入返回 null（不抛错，避免坏事件打断 UI）。 */
export function decodePayload(text: string): IpcPayload | null {
  let parsed: Object;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (e) {
    return null;
  }
  const rec = asRecord(parsed);
  if (rec === null) {
    return null;
  }
  const tunnel = rec['tunnel'];
  const state = rec['state'];
  const peersRaw = rec['peers'];
  if (typeof tunnel !== 'string' || tunnel.length === 0) {
    return null;
  }
  if (typeof state !== 'string') {
    return null;
  }
  if (state !== 'up' && state !== 'down') {
    return null;
  }
  const peers: PeerStats[] = [];
  if (peersRaw instanceof Array) {
    const arr = peersRaw as Object[];
    for (const item of arr) {
      const peer = parsePeer(item);
      if (peer === null) {
        return null;
      }
      peers.push(peer);
    }
  } else if (peersRaw !== undefined) {
    return null;
  }
  const payload: IpcPayload = {
    tunnel: tunnel,
    state: state === 'up' ? 'up' : 'down',
    peers: peers
  };
  const error = rec['error'];
  if (typeof error === 'string' && error.length > 0) {
    payload.error = error;
  }
  return payload;
}
