/**
 * 隧道编辑器页（占位骨架）。
 *
 * 路由契约见 docs/dev-contracts.md §11：路由名 `editor`，
 * param = { name?: string }（无 name 表示新建）。
 * 由「隧道编辑器」任务替换为完整实现（specs/tunnel-editor.md）。
 */
@ComponentV2
export struct TunnelEditorPage {
  @Param param: object = new Object();

  build() {
    Column() {
      Text('隧道编辑器')
        .fontSize(18)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
