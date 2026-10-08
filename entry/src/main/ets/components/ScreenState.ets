/*
 * 屏幕紧凑模式状态（@ObservedV2 可观察单例；specs/cover-screen.md、docs/decisions/0009）。
 *
 * 由 Index 根组件 onAreaChange 测量窗口尺寸并驱动；页面/组件直接读取 @Trace
 * 属性，框架按属性级依赖精准刷新——与 ListSelection 同一模式
 * （AGENTS.md 已知坑：@Param + ForEach 复用不刷新，不能靠父组件透传）。
 * 判定规则是纯函数 util/ScreenMode.isCompactWindow（可本地单测），本文件只做分发。
 */

import { isCompactWindow } from '../util/ScreenMode';

@ObservedV2
export class ScreenState {
  /** 当前是否紧凑布局。 */
  @Trace compact: boolean = false;

  /** 由根组件 onAreaChange 调用；仅在档位变化时写入（避免无关尺寸抖动触发重渲）。 */
  update(widthVp: number, heightVp: number): void {
    const next = isCompactWindow(widthVp, heightVp);
    if (next !== this.compact) {
      this.compact = next;
    }
  }
}

export const screenState: ScreenState = new ScreenState();
