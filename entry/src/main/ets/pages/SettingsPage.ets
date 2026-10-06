/**
 * 设置页（占位骨架）。
 *
 * 路由契约见 docs/dev-contracts.md §11：路由名 `settings`，无 param。
 * 由「导入 + 设置 + 日志 + 隐私」任务替换为完整实现（specs/settings.md）。
 */
@ComponentV2
export struct SettingsPage {
  @Param param: object = {};

  build() {
    Column() {
      Text('设置')
        .fontSize(18)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
