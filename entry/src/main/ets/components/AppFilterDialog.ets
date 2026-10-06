/*
 * 应用过滤对话框（specs/tunnel-editor.md「应用过滤对话框」）。
 *
 * 由编辑器页在 bindSheet 中实例化：两个标签页「不生效」/「生效」互斥，
 * 勾选集合两页共享；「全选」在「全不选/全选」间切换；确定按钮文案随选择变化。
 */

import { AppOption } from './AppCatalog';

@ComponentV2
export struct AppFilterDialog {
  /** 打开时定位到的模式（'excluded' | 'included'）。 */
  @Param initialMode: string = 'excluded';
  /** 打开时已有的勾选集合。 */
  @Param initialSelected: string[] = [];
  /** 可枚举到的应用（可能为空 → 空态）。 */
  @Param apps: AppOption[] = [];
  @Event onConfirm: (mode: string, selected: string[]) => void =
    (mode: string, selected: string[]): void => {};
  @Event onCancel: () => void = (): void => {};

  @Local mode: string = 'excluded';
  @Local selected: string[] = [];

  aboutToAppear(): void {
    this.mode = this.initialMode === 'included' ? 'included' : 'excluded';
    this.selected = this.initialSelected.slice();
  }

  private isSelected(bundleName: string): boolean {
    return this.selected.includes(bundleName);
  }

  private toggleApp(bundleName: string): void {
    const next: string[] = [];
    let removed = false;
    for (const item of this.selected) {
      if (item === bundleName) {
        removed = true;
      } else {
        next.push(item);
      }
    }
    if (!removed) {
      next.push(bundleName);
    }
    this.selected = next;
  }

  private allSelected(): boolean {
    return this.apps.length > 0 && this.selected.length === this.apps.length;
  }

  /** 「全选」按钮：全选 ↔ 全不选。 */
  private toggleAll(): void {
    if (this.allSelected()) {
      this.selected = [];
      return;
    }
    const all: string[] = [];
    for (const app of this.apps) {
      all.push(app.bundleName);
    }
    this.selected = all;
  }

  private confirmLabel(): string {
    return this.selected.length === 0 ? '不设定过滤' : `选定 ${this.selected.length} 个应用`;
  }

  @Builder
  AppList() {
    if (this.apps.length === 0) {
      Column() {
        Text('未找到可用应用')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column() {
          ForEach(this.apps, (app: AppOption) => {
            Row() {
              if (app.icon !== undefined) {
                Image(app.icon)
                  .width(32)
                  .height(32)
                  .margin({ right: 12 })
              }
              Text(app.label)
                .fontSize(16)
                .layoutWeight(1)
              Checkbox()
                .select(this.isSelected(app.bundleName))
                .onChange(() => {
                  this.toggleApp(app.bundleName);
                })
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
          }, (app: AppOption) => app.bundleName)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.Start, index: this.mode === 'included' ? 1 : 0 }) {
        TabContent() {
          this.AppList()
        }.tabBar('不生效')

        TabContent() {
          this.AppList()
        }.tabBar('生效')
      }
      .layoutWeight(1)
      .onChange((index: number) => {
        this.mode = index === 1 ? 'included' : 'excluded';
      })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.chip_bg'))
          .onClick(() => {
            this.onCancel();
          })
        Button('全选')
          .layoutWeight(1)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.chip_bg'))
          .onClick(() => {
            this.toggleAll();
          })
        Button(this.confirmLabel())
          .layoutWeight(2)
          .onClick(() => {
            this.onConfirm(this.mode, this.selected);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
  }
}
