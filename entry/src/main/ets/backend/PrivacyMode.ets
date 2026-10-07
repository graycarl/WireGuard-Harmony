/*
 * 防截屏/防录屏（specs/privacy-security.md §3）。
 *
 * 密钥在编辑器中明文显示后调用 setEnabled(context, true)，离开编辑器时关闭。
 * 权限 ohos.permission.PRIVACY_WINDOW（system_grant + normal）已在 module.json5 声明。
 */

import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Logger } from '../util/Logger';

const TAG = 'PrivacyMode';

export class PrivacyMode {
  static async setEnabled(context: common.Context, enabled: boolean): Promise<void> {
    try {
      const win = await window.getLastWindow(context);
      await win.setWindowPrivacyMode(enabled);
      Logger.info(TAG, `防截屏已${enabled ? '开启' : '关闭'}`);
    } catch (e) {
      Logger.error(TAG, `设置防截屏失败：${(e as Error).message}`);
    }
  }
}
