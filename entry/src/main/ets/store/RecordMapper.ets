/*
 * Config（config/ 模块的 wg-quick 对象）↔ TunnelRecord（repo/ 的持久化结构）双向映射。
 *
 * 纯逻辑模块（禁 import @kit），把 config/ 与 repo/ 两个叶子模块粘到 store/ 层，
 * 磁盘格式仍由 TunnelRecord 决定（JSON 键 "interface"）。
 */

import { Config } from '../config/Config';
import { Interface } from '../config/Interface';
import { Peer } from '../config/Peer';
import { InetNetwork } from '../config/InetNetwork';
import { InetEndpoint } from '../config/InetEndpoint';
import { InterfaceRecord, PeerRecord, TunnelRecord } from '../repo/TunnelRecord';

function networkTexts(networks: InetNetwork[]): string[] {
  const out: string[] = [];
  for (const network of networks) {
    out.push(network.toString());
  }
  return out;
}

function parseNetworks(texts: string[]): InetNetwork[] {
  const out: InetNetwork[] = [];
  for (const text of texts) {
    out.push(InetNetwork.parse(text));
  }
  return out;
}

export class RecordMapper {
  /** Config → TunnelRecord（用于持久化）。 */
  static toRecord(name: string, config: Config): TunnelRecord {
    const iface: InterfaceRecord = {
      privateKey: config.interface.privateKey,
      addresses: networkTexts(config.interface.addresses),
      listenPort: config.interface.listenPort,
      dnsServers: config.interface.dnsServers.slice(),
      dnsSearchDomains: config.interface.dnsSearchDomains.slice(),
      mtu: config.interface.mtu,
      excludedApplications: config.interface.excludedApplications.slice(),
      includedApplications: config.interface.includedApplications.slice()
    };
    const peers: PeerRecord[] = [];
    for (const peer of config.peers) {
      const record: PeerRecord = {
        publicKey: peer.publicKey,
        presharedKey: peer.presharedKey,
        allowedIPs: networkTexts(peer.allowedIPs),
        endpoint: peer.endpoint === null ? '' : peer.endpoint.toString(),
        persistentKeepalive: peer.persistentKeepalive
      };
      peers.push(record);
    }
    const tunnel: TunnelRecord = {
      name: name,
      iface: iface,
      peers: peers
    };
    return tunnel;
  }

  /** TunnelRecord → Config（用于展示/编辑/下发）。 */
  static toConfig(record: TunnelRecord): Config {
    const iface = new Interface();
    iface.privateKey = record.iface.privateKey;
    iface.addresses = parseNetworks(record.iface.addresses);
    iface.listenPort = record.iface.listenPort;
    iface.dnsServers = record.iface.dnsServers.slice();
    iface.dnsSearchDomains = record.iface.dnsSearchDomains.slice();
    iface.mtu = record.iface.mtu;
    iface.excludedApplications = record.iface.excludedApplications.slice();
    iface.includedApplications = record.iface.includedApplications.slice();

    const peers: Peer[] = [];
    for (const peerRecord of record.peers) {
      const peer = new Peer();
      peer.publicKey = peerRecord.publicKey;
      peer.presharedKey = peerRecord.presharedKey;
      peer.allowedIPs = parseNetworks(peerRecord.allowedIPs);
      peer.endpoint = peerRecord.endpoint.length === 0 ? null : InetEndpoint.parse(peerRecord.endpoint);
      peer.persistentKeepalive = peerRecord.persistentKeepalive;
      peers.push(peer);
    }
    return Config.from(iface, peers);
  }
}
