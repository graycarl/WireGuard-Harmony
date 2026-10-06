/**
 * 隧道编辑器页（占位骨架）。
 *
 * 路由契约见 docs/dev-contracts.md §11：路由名 `editor`，
 * param 为 route/RouteStack 的 EditorParam（name 为空串表示新建）。
 * 由「隧道编辑器」任务替换为完整实现（specs/tunnel-editor.md）。
 */
import { EmptyParam } from './RouteStack';

@ComponentV2
export struct TunnelEditorPage {
  @Param param: object = new EmptyParam();

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
