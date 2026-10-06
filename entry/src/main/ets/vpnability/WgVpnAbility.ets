import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'WgVpnAbility';

/**
 * WireGuard VPN 扩展能力（独立 VPN 服务进程）。
 *
 * 分层约定（docs/decisions/0002）：本类只做控制面——读配置、建虚拟网卡、
 * 把 tun fd 交给 C 数据面、向 UI 进程上抛状态事件；不含任何协议逻辑。
 *
 * 进程通信约定（docs/decisions/0004）：
 * - 下行：UI startVpnExtensionAbility 时 want.parameters.tunnelName 带隧道名，
 *   本进程按名从共享存储（tunnels.json）自读全量配置；
 * - 上行：状态迁移经 commonEventManager 自定义事件推送（TODO）。
 */
export default class WgVpnAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | null = null;

  onCreate(want: Want): void {
    const tunnelName: string = (want.parameters?.tunnelName ?? '') as string;
    hilog.info(DOMAIN, TAG, 'onCreate, tunnel=%{public}s', tunnelName);
    // TODO(0003/0004): 按 tunnelName 从 tunnels.json 读配置
    // TODO(核心决策1): createVpnConnection → build VpnConfig → create() 拿 tun fd
    // TODO(0001): tun fd + 结构化配置下发 C 数据面（NAPI startTunnel）
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy, tearing down');
    // TODO(0001): C 数据面 stopTunnel → destroy vpn 连接
    this.vpnConnection?.destroy().catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'destroy failed: %{public}s', err.message);
    });
    this.vpnConnection = null;
  }
}
