/**
 * 数据面 NAPI 接口（薄控制面，见 docs/dev-contracts.md §8 与 docs/decisions/0001/0002）。
 *
 * 使用顺序（VPN 进程 WgVpnAbility）：
 *   1) createUdpSocket() 拿 fd；
 *   2) vpnConnection.protect(fd) 保护隧道 socket；
 *   3) startTunnel(tunFd, sockFd, configJson)。
 */

/** 单个 Peer 的实时统计快照。 */
export interface WgPeerStats {
  /** 对端公钥（base64，44 字符）。 */
  publicKey: string;
  /** 累计接收字节数（有效载荷，不含封装开销）。 */
  rxBytes: number;
  /** 累计发送字节数（有效载荷）。 */
  txBytes: number;
  /** 最近一次成功握手的 epoch 毫秒；0 = 从未握手。 */
  lastHandshakeMs: number;
  /** 当前实际对端地址（roaming 后更新）；空串 = 未知。 */
  endpoint: string;
}

/**
 * 创建 UDP socket（双栈）。返回值 >= 0 为 fd；< 0 为错误码（-3 socket 失败）。
 * 调用方须在 startTunnel 前对其调用 vpnConnection.protect(fd)。
 */
export const createUdpSocket: () => number;

/**
 * 启动数据面（同步完成：KAT 自检 → 解析配置 → 解析全部 endpoint → bind → 起线程）。
 *
 * configJson 结构：
 * {
 *   "privateKey": "<base64>",
 *   "listenPort": 0,
 *   "peers": [ { "publicKey": "<base64>", "presharedKey": "", "endpoint": "host:port",
 *                "allowedIPs": ["0.0.0.0/0"], "persistentKeepalive": 0 } ]
 * }
 *
 * @returns 0 成功；-1 参数/内部错误；-2 endpoint DNS 解析失败（getLastError() 为主机名）；
 *          -3 socket/bind 失败；-4 线程创建失败；-5 启动 KAT 自检失败。
 */
export const startTunnel: (tunFd: number, sockFd: number, configJson: string) => number;

/** 停止数据面（幂等）：停线程、关 UDP fd、清会话；不关闭 tunFd（归 vpnConnection）。 */
export const stopTunnel: () => void;

/** 各 Peer 统计快照（线程安全）。 */
export const getStats: () => WgPeerStats[];

/** 最近一次错误的细节（如 DNS 解析失败的主机名）；无错误时为空串。 */
export const getLastError: () => string;

/** 数据面版本串。 */
export const getVersion: () => string;
