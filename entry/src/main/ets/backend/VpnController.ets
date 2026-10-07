/*
 * vpnExtension 薄封装 + 错误码 → 用户可见原因映射
 * （specs/tunnel-connection.md 错误原因文案、docs/decisions/0004）。
 *
 * 下行控制：start/stop 只携带隧道名，VPN 进程按名自读配置（不传全量配置进 want）。
 */

import { vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../util/Logger';

const TAG = 'VpnController';
const BUNDLE_NAME = 'me.graycarl.wireguard';
const ABILITY_NAME = 'WgVpnAbility';

export class VpnController {
  /** 构造启动/停止 WgVpnAbility 的 Want。 */
  static want(tunnelName: string): Want {
    const want: Want = {
      deviceId: '',
      bundleName: BUNDLE_NAME,
      abilityName: ABILITY_NAME,
      parameters: { tunnelName: tunnelName }
    };
    return want;
  }

  /** 启动 VPN 扩展能力（首次会触发系统授权框）。失败抛已本地化的 Error。 */
  static async start(tunnelName: string): Promise<void> {
    try {
      await vpnExtension.startVpnExtensionAbility(VpnController.want(tunnelName));
    } catch (e) {
      const error = e as BusinessError;
      throw new Error(VpnController.mapStartError(error));
    }
  }

  /** 停止 VPN 扩展能力。失败抛已本地化的 Error。 */
  static async stop(tunnelName: string): Promise<void> {
    try {
      await vpnExtension.stopVpnExtensionAbility(VpnController.want(tunnelName));
    } catch (e) {
      const error = e as BusinessError;
      Logger.error(TAG, `stopVpnExtensionAbility 失败：code=${error.code} msg=${error.message}`);
      throw new Error('无法停止 VPN 服务');
    }
  }

  /** startVpnExtensionAbility 的错误映射。 */
  static mapStartError(error: BusinessError): string {
    const code = error.code;
    Logger.error(TAG, `startVpnExtensionAbility 失败：code=${code} msg=${error.message}`);
    if (code === 2203001) {
      return '用户未授权 VPN 服务';
    }
    if (code === 2203002) {
      return '系统同时只允许一条 VPN 连接，请先断开其他 VPN 后重试';
    }
    return '无法启动 VPN 服务';
  }

  /**
   * VpnConnection.create() 的错误映射（在 VPN 进程内调用）。
   * 2203001「用户未授权」；2203002「已有 VPN 占用」；其余创建类错误 → 无法创建 tun 设备。
   */
  static mapCreateError(error: BusinessError): string {
    const code = error.code;
    Logger.error(TAG, `createVpnConnection().create 失败：code=${code} msg=${error.message}`);
    if (code === 2203001) {
      return '用户未授权 VPN 服务';
    }
    if (code === 2203002) {
      return '系统同时只允许一条 VPN 连接，请先断开其他 VPN 后重试';
    }
    if (code === 2200001 || code === 2200002 || code === 2200003 || code === 401) {
      return '无法创建 tun 设备';
    }
    return `未知的 '${error.message}' 错误`;
  }
}
