/**
 * 扫码页（占位骨架）。
 *
 * 路由契约见 docs/dev-contracts.md §11：路由名 `scan`，无 param；
 * 识别成功后通过 NavPathStack.pop(result) 回传配置文本（或直接弹出命名对话框）。
 * 由「导入 + 设置 + 日志 + 隐私」任务替换（specs/tunnel-import.md 方式三）。
 */
@ComponentV2
export struct ScanPage {
  @Param param: object = new Object();

  build() {
    Column() {
      Text('扫描二维码')
        .fontSize(18)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
