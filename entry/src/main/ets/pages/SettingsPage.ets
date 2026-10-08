/*
 * 设置页（specs/settings.md）：版本信息、导出隧道配置（含认证）、查看应用日志、暗色主题开关。
 */
import { common, bundleManager } from '@kit.AbilityKit';
import { picker, fileUri } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { Toast } from '../util/Toast';
import { Logger } from '../util/Logger';
import { copyFileTo, ensureDir, errorMessage, removeAll, writeTextFile } from '../util/FileUtil';
import { AuthResultKind, AuthGuard } from '../backend/AuthGuard';
import { PreferencesStore } from '../platform/PreferencesStore';
import { NativeBridge } from '../platform/NativeBridge';
import { AppStore } from '../store/AppStore';
import { RecordMapper } from '../store/RecordMapper';
import { screenState } from '../components/ScreenState';
import { Dimens } from '../util/ScreenMode';
import { EmptyParam, goLog } from './RouteStack';

@ComponentV2
export struct SettingsPage {
  @Param param: object = new EmptyParam();
  @Local versionText: string = 'WireGuard';
  @Local darkTheme: boolean = false;

  /** 尺寸档位（build/@Builder 中调用以读取 @Trace 依赖，决策 0009）。 */
  private get d(): Dimens {
    return new Dimens(screenState.compact);
  }

  aboutToAppear(): void {
    this.versionText = SettingsPage.buildVersionText();
    this.darkTheme = PreferencesStore.darkTheme();
  }

  private static buildVersionText(): string {
    let appVersion = '';
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      appVersion = info.versionName;
    } catch (e) {
      appVersion = '';
    }
    let backend = '';
    try {
      backend = NativeBridge.getVersion();
    } catch (e) {
      backend = '';
    }
    const left = appVersion.length > 0 ? `WireGuard v${appVersion}` : 'WireGuard';
    return backend.length > 0 ? `${left}，userspace backend ${backend}` : left;
  }

  build() {
    Column() {
      List() {
        ListItem() {
          this.SettingRow('版本', this.versionText, false)
        }

        ListItem() {
          this.SettingRow('导出隧道配置', '包含私钥，需锁屏认证', true)
        }
        .onClick(() => {
          this.exportTunnels();
        })

        ListItem() {
          this.SettingRow('查看应用日志', '', true)
        }
        .onClick(() => {
          goLog();
        })

        ListItem() {
          Row() {
            Column({ space: 4 }) {
              Text('暗色主题')
                .fontSize(16)
              Text('关闭时跟随系统')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.darkTheme })
              .selectedColor($r('app.color.accent'))
              .switchPointColor($r('app.color.on_accent'))
              .onChange((isOn: boolean) => {
                this.darkTheme = isOn;
                this.applyDarkTheme(isOn);
              })
          }
          .width('100%')
          .padding({ left: this.d.pagePadding, right: this.d.pagePadding, top: 12, bottom: 12 })
        }
      }
      .width('100%')
      .height('100%')
      .divider({ strokeWidth: 0.5, color: $r('app.color.divider') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }

  @Builder
  SettingRow(title: string, summary: string, clickable: boolean) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        if (summary.length > 0) {
          Text(summary)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(3)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (clickable) {
        Text('›')
          .fontSize(20)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .padding({ left: this.d.pagePadding, right: this.d.pagePadding, top: 12, bottom: 12 })
  }

  /** 用户实际保存到的文件名（拿不到时用建议文件名）。 */
  private static savedName(uri: string, fallback: string): string {
    try {
      const name = new fileUri.FileUri(uri).name;
      if (name.length > 0) {
        return decodeURIComponent(name);
      }
    } catch (e) {
      // 退化用建议文件名
    }
    return fallback;
  }

  private async applyDarkTheme(enabled: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    await PreferencesStore.setDarkTheme(enabled);
    PreferencesStore.applyColorMode(context);
  }

  /**
   * 导出全部隧道为 zip（specs/settings.md）：
   * 无隧道 → 直接提示、不认证；有隧道 → 认证后打包，用户选择保存位置。
   */
  private async exportTunnels(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    const records = AppStore.get().records();
    if (records.length === 0) {
      Toast.show('无法导出隧道配置：无隧道');
      return;
    }
    const auth = await AuthGuard.authenticate('导出配置前需要通过认证');
    if (auth.kind === AuthResultKind.FAILED) {
      Toast.show('认证失败');
      return;
    }
    if (auth.kind === AuthResultKind.ERROR) {
      Toast.show(auth.message);
      return;
    }
    if (auth.kind === AuthResultKind.CANCELLED) {
      return;
    }

    const stamp = Date.now();
    const fileName = `wireguard-${stamp}.zip`;
    const dir = `${context.cacheDir}/wg-export-${stamp}`;
    const zipPath = `${context.cacheDir}/wg-export-${stamp}.zip`;
    try {
      ensureDir(dir);
      const confPaths: string[] = [];
      for (const record of records) {
        const config = RecordMapper.toConfig(record);
        const path = `${dir}/${record.name}.conf`;
        writeTextFile(path, config.toWgQuickString());
        confPaths.push(path);
      }
      await zlib.compressFiles(confPaths, zipPath, {});

      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [fileName];
      let targets: string[] = [];
      try {
        targets = await new picker.DocumentViewPicker(context).save(saveOptions);
      } catch (e) {
        Logger.info('SettingsPage', '保存取消');
        return;
      }
      if (targets.length === 0) {
        return;
      }
      copyFileTo(zipPath, targets[0]);
      Toast.show(`已保存至 '${SettingsPage.savedName(targets[0], fileName)}'`);
    } catch (e) {
      Toast.show(`无法导出隧道配置：${errorMessage(e as Object)}`);
    } finally {
      removeAll([zipPath, dir]);
    }
  }
}
