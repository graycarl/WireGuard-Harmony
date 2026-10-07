/*
 * 隧道列表项（specs/tunnel-list.md）。
 *
 * - 常规模式：点击行进入详情；点击开关连接/断开（开关自己处理，不进入详情）；
 * - 多选模式：点击行切换选中，开关隐藏；
 * - 长按任意行进入多选模式（并选中该项）。
 *
 * 多选态来自可观察单例 listSelection（ForEach 键值复用时 @Param 不刷新的规避手段）。
 */

import { TunnelSwitch } from './TunnelSwitch';
import { listSelection } from './ListSelection';

@ComponentV2
export struct TunnelListItem {
  @Param name: string = '';
  @Event onOpen: (name: string) => void = (name: string) => {};

  build() {
    Row({ space: 12 }) {
      if (listSelection.active) {
        Checkbox({ name: this.name, group: 'tunnel-selection' })
          .select(listSelection.has(this.name))
          .width(22)
          .height(22)
          .enabled(false)
      }
      Text(this.name)
        .fontSize(17)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (!listSelection.active) {
        TunnelSwitch({ name: this.name })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(listSelection.active && listSelection.has(this.name) ? $r('app.color.accent_tint') : Color.Transparent)
    .onClick(() => {
      if (listSelection.active) {
        listSelection.toggle(this.name);
      } else {
        this.onOpen(this.name);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          if (!listSelection.active) {
            listSelection.selectOnly(this.name);
          }
        })
    )
  }
}
