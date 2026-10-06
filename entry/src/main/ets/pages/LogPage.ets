/**
 * 日志查看页（占位骨架）。
 *
 * 路由契约见 docs/dev-contracts.md §11：路由名 `log`，无 param。
 * 由「导入 + 设置 + 日志 + 隐私」任务替换为完整实现（specs/settings.md §查看应用日志）。
 */
@ComponentV2
export struct LogPage {
  @Param param: object = new Object();

  build() {
    Column() {
      Text('应用日志')
        .fontSize(18)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
