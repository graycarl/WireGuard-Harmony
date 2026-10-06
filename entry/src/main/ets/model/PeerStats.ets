/**
 * 单个 Peer 的运行统计快照（见 docs/dev-contracts.md §5/§8/§9）。
 *
 * 数据来源：C 数据面 getStats() → VPN 进程公共事件 → AppStore 快照。
 * 纯数据接口，可被任意层引用，不依赖 @kit。
 */
export interface PeerStats {
  /** 对端公钥（base64） */
  publicKey: string;
  /** 累计接收字节数 */
  rxBytes: number;
  /** 累计发送字节数 */
  txBytes: number;
  /** 最近一次握手完成的 epoch 毫秒；0 = 从未成功握手 */
  lastHandshakeMs: number;
  /** 当前实际对端地址（roaming 后可能变化）；空串 = 无 */
  endpoint: string;
}
