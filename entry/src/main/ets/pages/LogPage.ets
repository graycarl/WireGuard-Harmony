/*
 * 应用日志页（specs/settings.md §查看应用日志）：
 * 展示应用自身日志（旧→新）、仅当用户未上滑时自动滚到底部、支持导出与分享。
 */
import { common } from '@kit.AbilityKit';
import { picker, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { Toast } from '../util/Toast';
import { Logger } from '../util/Logger';
import { errorMessage } from '../util/FileUtil';
import { BusinessError } from '@kit.BasicServicesKit';
import { EmptyParam } from './RouteStack';

@ComponentV2
export struct LogPage {
  @Param param: object = new EmptyParam();
  @Local logs: string[] = [];
  @Local autoScroll: boolean = true;
  private scroller: Scroller = new Scroller();
  private logListener: () => void = (): void => {
    this.reload();
  };

  aboutToAppear(): void {
    this.reload();
    Logger.subscribe(this.logListener);
  }

  aboutToDisappear(): void {
    Logger.unsubscribe(this.logListener);
  }

  private reload(): void {
    this.logs = Logger.readAll();
    if (this.autoScroll) {
      this.scrollToBottom();
    }
  }

  private scrollToBottom(): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      // Scroller 尚未绑定组件时忽略（AGENTS.md 已知坑）
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('导出日志文件')
          .fontSize(14)
          .layoutWeight(1)
          .onClick(() => {
            this.exportLogs();
          })
        Button('分享日志文件')
          .fontSize(14)
          .layoutWeight(1)
          .onClick(() => {
            this.shareLogs();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      if (this.logs.length === 0) {
        Column() {
          Text('暂无日志')
            .fontSize(14)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.scroller }) {
          ForEach(this.logs, (line: string) => {
            ListItem() {
              Text(line)
                .fontSize(12)
                .fontFamily('monospace')
                .textAlign(TextAlign.Start)
                .width('100%')
            }
            .padding({ left: 12, right: 12, top: 2, bottom: 2 })
          }, (line: string, index: number) => `${index}-${line}`)
        }
        .width('100%')
        .layoutWeight(1)
        .onScrollIndex((start: number, end: number) => {
          this.autoScroll = end >= this.logs.length - 1;
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 导出日志文件（用户选择保存位置）。 */
  private async exportLogs(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    const fileName = `wireguard-logs-${Date.now()}.txt`;
    try {
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [fileName];
      let targets: string[] = [];
      try {
        targets = await new picker.DocumentViewPicker(context).save(saveOptions);
      } catch (e) {
        return;
      }
      if (targets.length === 0) {
        return;
      }
      await Logger.exportTo(targets[0]);
      Toast.show(`已保存至 '${LogPage.savedName(targets[0], fileName)}'`);
    } catch (e) {
      Toast.show(`无法导出日志：${errorMessage(e as Object)}`);
    }
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

  /** 通过系统分享把日志文件发给其他应用。 */
  private async shareLogs(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const path = `${context.cacheDir}/wireguard-logs-${Date.now()}.txt`;
    try {
      await Logger.exportTo(path);
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.FILE,
        uri: fileUri.getUriFromPath(path),
        title: 'WireGuard 应用日志'
      };
      const shareData = new systemShare.SharedData(record);
      const controller = new systemShare.ShareController(shareData);
      await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE });
    } catch (e) {
      const error = e as BusinessError;
      Toast.show(`无法分享日志：${error.message}`);
    }
  }
}
