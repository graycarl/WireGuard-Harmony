/**
 * tunnels.json 的结构化记录类型（见 docs/dev-contracts.md §5）。
 *
 * 偏差说明：JSON 键名为 "interface"，但 interface 是 ArkTS 关键字语境词，
 * 故 TS 侧字段命名为 iface；TunnelRepository 序列化/解析时负责
 * iface ↔ "interface" 的映射，磁盘格式与契约完全一致。
 *
 * Config（config/ 模块的 wg-quick 对象）↔ TunnelRecord 的转换不在本层，
 * 由 store/ 负责。
 */

/** [Peer] 节记录 */
export interface PeerRecord {
  /** 对端公钥（base64，44 字符） */
  publicKey: string;
  /** 预共享密钥（base64）；空串 = 未设置 */
  presharedKey: string;
  /** 路由的 IP 段（CIDR 文本列表） */
  allowedIPs: string[];
  /** 对端地址 host:port；空串 = 未设置 */
  endpoint: string;
  /** 保活间隔秒；0 = 关闭 */
  persistentKeepalive: number;
}

/** [Interface] 节记录（JSON 键名 "interface"） */
export interface InterfaceRecord {
  /** 本机私钥（base64，44 字符） */
  privateKey: string;
  /** 局域网 IP 地址（CIDR 文本列表） */
  addresses: string[];
  /** UDP 监听端口；0 = 随机/未设置 */
  listenPort: number;
  /** DNS 服务器（IP 字面量列表） */
  dnsServers: string[];
  /** DNS 搜索域名列表 */
  dnsSearchDomains: string[];
  /** MTU；0 = 自动/未设置 */
  mtu: number;
  /** 不走 VPN 的应用标识列表（与 includedApplications 互斥） */
  excludedApplications: string[];
  /** 仅走 VPN 的应用标识列表（与 excludedApplications 互斥） */
  includedApplications: string[];
}

/** 单条隧道记录 */
export interface TunnelRecord {
  /** 隧道名称（规则见 TunnelRepository.isValidTunnelName） */
  name: string;
  /** 对应 JSON 键 "interface" */
  iface: InterfaceRecord;
  peers: PeerRecord[];
}
