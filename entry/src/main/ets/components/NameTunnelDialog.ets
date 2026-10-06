/*
 * 隧道命名对话框（specs/tunnel-import.md §隧道命名对话框）。
 *
 * 用于：二维码/图片二维码导入、单文件导入派生名称非法时的现场命名。
 * 服务层不是组件、无法持有 CustomDialogController，故通过 UIContext 的
 * openCustomDialog + ComponentContent 以弹窗形式打开（API 12+ 推荐用法）。
 */
import { ComponentContent, UIContext } from '@kit.ArkUI';

/** 命名对话框参数与回调。 */
export class NameDialogOptions {
  /** 标题（如「从二维码导入隧道」/「隧道命名」） */
  title: string = '隧道命名';
  /** 输入框预填名称（已按隧道名规则清理） */
  initialName: string = '';
  /** 点击「创建隧道」：返回行内错误文案；返回 null 表示通过（由服务层关闭对话框） */
  onSubmit: (name: string) => string | null = (name: string): string | null => null;
  /** 点击「取消」 */
  onCancel: () => void = (): void => {};
}

@ComponentV2
export struct NameTunnelDialog {
  @Param options: NameDialogOptions = new NameDialogOptions();
  @Local name: string = '';
  @Local error: string = '';

  aboutToAppear(): void {
    this.name = this.options.initialName;
  }

  build() {
    Column({ space: 14 }) {
      Text(this.options.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      TextInput({ text: this.name, placeholder: '隧道名称' })
        .maxLength(15)
        .inputFilter('[A-Za-z0-9_=+.-]')
        .onChange((value: string) => {
          this.name = value;
          this.error = '';
        })
        .width('100%')

      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(12)
          .fontColor('#E84026')
          .width('100%')
      }

      Row({ space: 12 }) {
        Button('取消')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)
          .onClick(() => {
            this.options.onCancel();
          })
        Button('创建隧道')
          .layoutWeight(1)
          .onClick(() => {
            const message = this.options.onSubmit(this.name);
            if (message !== null) {
              this.error = message;
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('sys.color.ohos_id_color_dialog_bg'))
    .borderRadius(16)
  }
}

/** 全局构建函数（wrapBuilder 只接受全局 @Builder）。 */
@Builder
function nameTunnelDialogBuilder(options: NameDialogOptions) {
  NameTunnelDialog({ options: options })
}

const nameTunnelDialogWrapped: WrappedBuilder<[NameDialogOptions]> =
  wrapBuilder<[NameDialogOptions]>(nameTunnelDialogBuilder);

/**
 * 弹出命名对话框；返回用户确认的名称，取消返回 null。
 * 弹窗无法打开时抛错（由调用方转为「无法导入隧道：无法显示命名对话框」）。
 */
export async function askTunnelName(uiContext: UIContext, options: NameDialogOptions): Promise<string | null> {
  let resolveFn: (value: string | null) => void = (value: string | null): void => {};
  const decision = new Promise<string | null>((resolve: (value: string | null) => void) => {
    resolveFn = resolve;
  });
  const originalSubmit = options.onSubmit;
  options.onSubmit = (name: string): string | null => {
    const message = originalSubmit(name);
    if (message === null) {
      resolveFn(name);
    }
    return message;
  };
  options.onCancel = (): void => {
    resolveFn(null);
  };

  const content = new ComponentContent(uiContext, nameTunnelDialogWrapped, options);
  await uiContext.getPromptAction().openCustomDialog(content, { isModal: true, autoCancel: false });
  const chosen = await decision;
  try {
    await uiContext.getPromptAction().closeCustomDialog(content);
  } catch (e) {
    // 已关闭则忽略
  }
  return chosen;
}
