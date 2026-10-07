/*
 * 应用偏好（目前只有暗色主题开关，specs/settings.md §暗色主题）。
 *
 * 开 = 使用暗色主题；关 = 跟随系统（默认）。切换后即时生效并持久化。
 */

import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Logger } from '../util/Logger';

const TAG = 'PreferencesStore';
const STORE_NAME = 'app_settings';
const KEY_DARK_THEME = 'darkTheme';

export class PreferencesStore {
  private static store: preferences.Preferences | null = null;
  private static cachedDarkTheme: boolean = false;

  static async init(context: common.Context): Promise<void> {
    try {
      const options: preferences.Options = { name: STORE_NAME };
      const store = await preferences.getPreferences(context, options);
      PreferencesStore.store = store;
      const value = store.getSync(KEY_DARK_THEME, false);
      PreferencesStore.cachedDarkTheme = value === true;
    } catch (e) {
      Logger.error(TAG, `打开偏好存储失败：${(e as Error).message}`);
    }
  }

  /** 当前是否启用暗色主题（关 = 跟随系统）。 */
  static darkTheme(): boolean {
    const store = PreferencesStore.store;
    if (store === null) {
      return PreferencesStore.cachedDarkTheme;
    }
    try {
      return store.getSync(KEY_DARK_THEME, false) === true;
    } catch (e) {
      return PreferencesStore.cachedDarkTheme;
    }
  }

  static async setDarkTheme(enabled: boolean): Promise<void> {
    PreferencesStore.cachedDarkTheme = enabled;
    const store = PreferencesStore.store;
    if (store === null) {
      return;
    }
    try {
      store.putSync(KEY_DARK_THEME, enabled);
      await store.flush();
    } catch (e) {
      Logger.error(TAG, `保存主题偏好失败：${(e as Error).message}`);
    }
  }

  /** 把当前偏好应用到应用全局（暗色 = COLOR_MODE_DARK，否则跟随系统）。 */
  static applyColorMode(context: common.Context): void {
    try {
      const mode = PreferencesStore.darkTheme()
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      context.getApplicationContext().setColorMode(mode);
    } catch (e) {
      Logger.error(TAG, `应用主题失败：${(e as Error).message}`);
    }
  }
}
