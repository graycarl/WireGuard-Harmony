/*
 * C 数据面的 ArkTS 类型安全薄封装（docs/dev-contracts.md §8）。
 *
 * 约定：NAPI 边界只传结构化配置与统计，协议细节不外泄；本文件负责
 * 配置 JSON 组装与错误码 → 用户可见文案映射（specs/tunnel-connection.md 错误文案表）。
 */

import { createUdpSocket, prepareTunnel, startTunnel, stopTunnel, getStats, getLastError, getVersion }
  from 'libentry.so';
import { Config } from '../config/Config';

/** 数据面成功返回码。 */
export const NATIVE_OK: number = 0;
/** 参数/内部错误。 */
export const NATIVE_ERR_INTERNAL: number = -1;
/** endpoint DNS 解析失败（getLastError() 为主机名）。 */
export const NATIVE_ERR_DNS: number = -2;
/** socket/bind 失败。 */
export const NATIVE_ERR_SOCKET: number = -3;
/** 线程/资源不足。 */
export const NATIVE_ERR_RESOURCE: number = -4;
/** 启动 KAT 自检失败。 */
export const NATIVE_ERR_KAT: number = -5;

/** Peer 统计快照（与 NAPI 的 WgPeerStats 字段一致）。 */
export interface NativePeerStats {
  publicKey: string;
  rxBytes: number;
  txBytes: number;
  lastHandshakeMs: number;
  endpoint: string;
}

/** 下发给数据面的单个 Peer 配置。 */
interface NativePeerConfig {
  publicKey: string;
  presharedKey: string;
  endpoint: string;
  allowedIPs: string[];
  persistentKeepalive: number;
}

/** 下发给数据面的隧道配置。 */
interface NativeTunnelConfig {
  privateKey: string;
  listenPort: number;
  peers: NativePeerConfig[];
}

export class NativeBridge {
  /** 创建 UDP socket（>=0 为 fd；<0 为错误码）。fd 归数据面所有：由 stop() 关闭。 */
  static createUdpSocket(): number {
    return createUdpSocket();
  }

  /**
   * 准备数据面：解析配置 + 解析全部 endpoint。
   * **必须在 VpnConnection.create() 之前调用**（决策 0010）：VPN 建起来后默认路由
   * 已被自己的 tun 接管，此时再用 getaddrinfo 解析域名，查询包会被送进尚未跑通的
   * 隧道，导致「有效的域名也报解析失败」。
   */
  static prepare(configJson: string): number {
    return prepareTunnel(configJson);
  }

  /** 启动数据面（bind + 起线程），返回 0 成功 / <0 错误码。须先 prepare() 与 createUdpSocket()。 */
  static start(tunFd: number): number {
    return startTunnel(tunFd);
  }

  static stop(): void {
    stopTunnel();
  }

  static getStats(): NativePeerStats[] {
    const raw = getStats();
    const out: NativePeerStats[] = [];
    for (const item of raw) {
      const stats: NativePeerStats = {
        publicKey: item.publicKey,
        rxBytes: item.rxBytes,
        txBytes: item.txBytes,
        lastHandshakeMs: item.lastHandshakeMs,
        endpoint: item.endpoint
      };
      out.push(stats);
    }
    return out;
  }

  static getLastError(): string {
    return getLastError();
  }

  /** 数据面版本串（设置页展示用）。 */
  static getVersion(): string {
    return getVersion();
  }

  /** 组装下发配置 JSON（不含任何日志输出，避免密钥泄漏）。 */
  static buildConfigJson(config: Config): string {
    const peers: NativePeerConfig[] = [];
    for (const peer of config.peers) {
      const allowedIPs: string[] = [];
      for (const network of peer.allowedIPs) {
        allowedIPs.push(network.toString());
      }
      const peerConfig: NativePeerConfig = {
        publicKey: peer.publicKey,
        presharedKey: peer.presharedKey,
        endpoint: peer.endpoint === null ? '' : peer.endpoint.toString(),
        allowedIPs: allowedIPs,
        persistentKeepalive: peer.persistentKeepalive
      };
      peers.push(peerConfig);
    }
    const tunnelConfig: NativeTunnelConfig = {
      privateKey: config.interface.privateKey,
      listenPort: config.interface.listenPort,
      peers: peers
    };
    return JSON.stringify(tunnelConfig);
  }

  /** 错误码 → 用户可见原因（specs/tunnel-connection.md 错误文案表）。 */
  static describeStartError(code: number): string {
    if (code === NATIVE_ERR_DNS) {
      const host = NativeBridge.getLastError();
      return `无法解析 DNS 主机名：'${host}'`;
    }
    // 其余（含 socket/bind、线程、KAT）均为隧道引擎启动失败，按 spec 的
    // 「无法开启隧道（错误码 <N>）」提示；「无法创建 tun 设备」只用于 vpnConnection.create 失败。
    return `无法开启隧道（错误码 ${code}）`;
  }
}
