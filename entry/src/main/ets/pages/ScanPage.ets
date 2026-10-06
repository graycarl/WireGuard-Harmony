/*
 * 扫码页（specs/tunnel-import.md 方式三）。
 *
 * 实际扫码由 HMS ScanKit 的系统默认扫码界面承担（ImportService.scanAndImport），
 * 本页作为路由承载：进入即打开扫码界面，处理完（含命名对话框）后返回并提示结果。
 */
import { common } from '@kit.AbilityKit';
import { Toast } from '../util/Toast';
import { ImportService } from '../services/ImportService';
import { EmptyParam, goBack } from './RouteStack';

@ComponentV2
export struct ScanPage {
  @Param param: object = new EmptyParam();
  @Local message: string = '正在打开扫码…';

  aboutToAppear(): void {
    this.start();
  }

  private async start(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.Context;
    const result = await ImportService.scanAndImport(context);
    if (result !== null) {
      Toast.show(result);
    }
    goBack();
  }

  build() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(48)
        .height(48)
      Text(this.message)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Text('提示：使用命令 `qrencode -t ansiutf8 < tunnel.conf` 生成二维码')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 24, right: 24 })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .justifyContent(FlexAlign.Center)
  }
}
