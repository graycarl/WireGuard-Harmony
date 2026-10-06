/*
 * WireGuard VPN 扩展能力（独立 VPN 服务进程，docs/decisions/0004/0005/0006）。
 *
 * 分层约定（docs/decisions/0002）：本类只做控制面——读配置、建虚拟网卡、
 * 把 tun fd 交给 C 数据面、向 UI 进程上抛状态事件；不含任何协议逻辑。
 *
 * 下行：UI startVpnExtensionAbility 时 want.parameters.tunnelName 带隧道名，
 *   本进程按名从共享存储（tunnels.json）自读全量配置（不做配置传输）。
 * 上行：commonEventManager 自定义事件推送状态与统计（无密钥）。
 */

import { VpnExtensionAbility, vpnExtension, connection } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { Logger } from '../util/Logger';
import { FsFileIO } from '../platform/FsFileIO';
import { TunnelRepository } from '../repo/TunnelRepository';
import { RecordMapper } from '../store/RecordMapper';
import { Config } from '../config/Config';
import { NativeBridge, NATIVE_OK } from '../platform/NativeBridge';
import { encodePayload, IpcPayload, TUNNEL_EVENT } from '../backend/IpcProtocol';
import { PeerStats } from '../model/PeerStats';
import { VpnController } from '../backend/VpnController';

const TAG = 'WgVpnAbility';
const STATS_INTERVAL_MS = 1000;
const TUN_IFACE = 'vpn-tun';

export default class WgVpnAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null;
  private tunnelName: string = '';
  private statsTimer: number = -1;
  private destroyed: boolean = false;

  onCreate(want: Want): void {
    const parameter = want.parameters?.tunnelName;
    this.tunnelName = typeof parameter === 'string' ? parameter : '';
    Logger.init(this.context, 'vpn');
    Logger.info(TAG, `onCreate tunnel=${this.tunnelName}`);
    this.startAsync().catch((error: Error): void => {
      Logger.error(TAG, `建立隧道失败：${error.message}`);
      this.teardown();
      this.publishDown(error.message);
    });
  }

  onDestroy(): void {
    this.destroyed = true;
    Logger.info(TAG, `onDestroy tunnel=${this.tunnelName}`);
    this.teardown();
    this.publishDown('');
  }

  private async startAsync(): Promise<void> {
    if (this.tunnelName.length === 0) {
      throw new Error('尝试在无配置情况下建立连接');
    }
    const repo = new TunnelRepository(new FsFileIO(), this.context.filesDir, undefined,
      (message: string): void => Logger.info('repo', message));
    const record = repo.findByName(this.tunnelName);
    if (record === null) {
      throw new Error('尝试在无配置情况下建立连接');
    }
    let config: Config;
    try {
      config = RecordMapper.toConfig(record);
    } catch (e) {
      Logger.error(TAG, `配置无法解析：${(e as Error).message}`);
      throw new Error('无法启动 VPN 服务');
    }

    const vpnConfig = WgVpnAbility.buildVpnConfig(config);
    const vpnConn = vpnExtension.createVpnConnection(this.context);
    this.vpnConnection = vpnConn;
    let tunFd: number;
    try {
      tunFd = await vpnConn.create(vpnConfig);
    } catch (e) {
      throw new Error(VpnController.mapCreateError(e as BusinessError));
    }
    if (this.destroyed) {
      return;
    }
    const sockFd = NativeBridge.createUdpSocket();
    if (sockFd < 0) {
      throw new Error(NativeBridge.describeStartError(sockFd));
    }
    try {
      await vpnConn.protect(sockFd);
    } catch (e) {
      Logger.error(TAG, `protect 失败：${(e as Error).message}`);
      throw new Error('无法启动 VPN 服务');
    }
    const code = NativeBridge.start(tunFd, sockFd, NativeBridge.buildConfigJson(config));
    if (code !== NATIVE_OK) {
      throw new Error(NativeBridge.describeStartError(code));
    }
    if (this.destroyed) {
      return;
    }
    Logger.info(TAG, `隧道已启动 tunnel=${this.tunnelName} tunFd=${tunFd}`);
    this.publishUp();
    this.startStatsTimer();
  }

  /** 停止数据面与 VPN 连接（幂等）。 */
  private teardown(): void {
    this.stopStatsTimer();
    try {
      NativeBridge.stop();
    } catch (e) {
      Logger.error(TAG, `停止数据面失败：${(e as Error).message}`);
    }
    const vpnConn = this.vpnConnection;
    this.vpnConnection = null;
    if (vpnConn !== null) {
      vpnConn.destroy().catch((error: Error): void => {
        Logger.error(TAG, `destroy 失败：${error.message}`);
      });
    }
  }

  private startStatsTimer(): void {
    this.stopStatsTimer();
    this.statsTimer = setInterval((): void => {
      if (this.destroyed) {
        return;
      }
      this.publishUp();
    }, STATS_INTERVAL_MS);
  }

  private stopStatsTimer(): void {
    if (this.statsTimer >= 0) {
      clearInterval(this.statsTimer);
      this.statsTimer = -1;
    }
  }

  private publishUp(): void {
    const payload: IpcPayload = {
      tunnel: this.tunnelName,
      state: 'up',
      peers: this.readStats()
    };
    this.publish(payload);
  }

  private publishDown(error: string): void {
    const payload: IpcPayload = {
      tunnel: this.tunnelName,
      state: 'down',
      peers: []
    };
    if (error.length > 0) {
      payload.error = error;
    }
    this.publish(payload);
  }

  private publish(payload: IpcPayload): void {
    try {
      const options: commonEventManager.CommonEventPublishData = { data: encodePayload(payload) };
      commonEventManager.publish(TUNNEL_EVENT, options, (error: BusinessError): void => {
        if (error) {
          Logger.error(TAG, `发布隧道事件失败：${error.message}`);
        }
      });
    } catch (e) {
      Logger.error(TAG, `发布隧道事件异常：${(e as Error).message}`);
    }
  }

  private readStats(): PeerStats[] {
    const out: PeerStats[] = [];
    try {
      const stats = NativeBridge.getStats();
      for (const item of stats) {
        const peerStats: PeerStats = {
          publicKey: item.publicKey,
          rxBytes: item.rxBytes,
          txBytes: item.txBytes,
          lastHandshakeMs: item.lastHandshakeMs,
          endpoint: item.endpoint
        };
        out.push(peerStats);
      }
    } catch (e) {
      // 统计读取失败：返回空数组（spec：隐藏统计行）
    }
    return out;
  }

  /** 构建系统 VPN 配置（官方字段见 net-vpnExtension.md「VPN Config参数说明」）。 */
  private static buildVpnConfig(config: Config): vpnExtension.VpnConfig {
    const addresses: connection.LinkAddress[] = [];
    let hasIpv6 = false;
    for (const network of config.interface.addresses) {
      const family = network.isIpv4 ? 1 : 2;
      if (family === 2) {
        hasIpv6 = true;
      }
      const link: connection.LinkAddress = {
        address: { address: network.address, family: family },
        prefixLength: network.mask
      };
      addresses.push(link);
    }

    const routes: connection.RouteInfo[] = [];
    const seen = new Set<string>();
    for (const peer of config.peers) {
      for (const network of peer.allowedIPs) {
        const key = network.toString();
        if (seen.has(key)) {
          continue;
        }
        seen.add(key);
        const family = network.isIpv4 ? 1 : 2;
        if (family === 2) {
          hasIpv6 = true;
        }
        const route: connection.RouteInfo = {
          interface: TUN_IFACE,
          destination: {
            address: { address: network.address, family: family },
            prefixLength: network.mask
          },
          gateway: { address: family === 1 ? '0.0.0.0' : '::', family: family },
          hasGateway: false,
          isDefaultRoute: network.mask === 0
        };
        routes.push(route);
      }
    }

    const vpnConfig: vpnExtension.VpnConfig = {
      addresses: addresses,
      routes: routes,
      dnsAddresses: config.interface.dnsServers.slice(),
      searchDomains: config.interface.dnsSearchDomains.slice(),
      isIPv4Accepted: true,
      isIPv6Accepted: hasIpv6
    };
    if (config.interface.mtu > 0) {
      vpnConfig.mtu = config.interface.mtu;
    }
    if (config.interface.includedApplications.length > 0) {
      vpnConfig.trustedApplications = config.interface.includedApplications.slice();
    }
    if (config.interface.excludedApplications.length > 0) {
      vpnConfig.blockedApplications = config.interface.excludedApplications.slice();
    }
    return vpnConfig;
  }
}
