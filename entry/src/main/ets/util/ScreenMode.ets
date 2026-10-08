/*
 * 屏幕紧凑模式：判定规则与尺寸档位（specs/cover-screen.md、docs/decisions/0009）。
 *
 * 纯逻辑：不 import @kit → 可本地单测（决策 0007 第一层）。
 * 状态分发见 components/ScreenState.ets（@ObservedV2 单例，装饰器不进单测）。
 */

/** 触发紧凑模式的窗口高度阈值（vp）：Pura X 外屏约 356–392vp 见方；常规手机竖屏 ≥640vp。 */
export const COMPACT_MAX_HEIGHT_VP: number = 560;
/** 触发紧凑模式的窗口宽度阈值（vp）。 */
export const COMPACT_MAX_WIDTH_VP: number = 360;

/** 窗口是否进入紧凑布局（高度为主判据：外屏/横屏/小窗的共同特征是矮）。 */
export function isCompactWindow(widthVp: number, heightVp: number): boolean {
  return heightVp < COMPACT_MAX_HEIGHT_VP || widthVp < COMPACT_MAX_WIDTH_VP;
}

/**
 * 界面尺寸档位：常规 / 紧凑（数值依据 docs/decisions/0009 §决策内容 1）。
 * 页面在 build 中以 `new Dimens(screenState.compact)` 取用，不集中缓存实例
 * （@Trace 依赖必须在渲染期间读取才能被跟踪）。
 */
export class Dimens {
  readonly compact: boolean;

  constructor(compact: boolean) {
    this.compact = compact;
  }

  /** 页面级水平内边距（列表行、标题栏、滚动区、对话框按钮条）。 */
  get pagePadding(): number {
    return this.compact ? 10 : 16;
  }

  /** 自绘标题栏高度。 */
  get titleBarHeight(): number {
    return this.compact ? 46 : 56;
  }

  /** 列表行高（隧道列表、添加面板菜单项）。 */
  get rowHeight(): number {
    return this.compact ? 46 : 56;
  }

  /** 一级标题字号（首页应用名）。 */
  get titleFont(): number {
    return this.compact ? 20 : 24;
  }

  /** 页面标题字号（详情/编辑器标题）。 */
  get headerFont(): number {
    return this.compact ? 16 : 18;
  }

  /** 详情字段标签列宽（详情页 / PeerCard）。 */
  get fieldLabelWidth(): number {
    return this.compact ? 88 : 120;
  }

  /** 编辑器字段标签列宽。 */
  get editorLabelWidth(): number {
    return this.compact ? 64 : 92;
  }

  /** 卡片内边距（详情卡片 / PeerCard）。 */
  get cardPadding(): number {
    return this.compact ? 10 : 16;
  }

  /** 字段行垂直间距（详情 8→6，编辑器 6→4 由调用方差分）。 */
  get fieldRowVPad(): number {
    return this.compact ? 6 : 8;
  }

  /** 编辑器字段行垂直间距。 */
  get editorRowVPad(): number {
    return this.compact ? 4 : 6;
  }

  /** 编辑器卡片内边距。 */
  get editorCardPadding(): number {
    return this.compact ? 10 : 12;
  }

  /** 浮动「+」按钮直径。 */
  get fabSize(): number {
    return this.compact ? 48 : 56;
  }

  /** 浮动「+」按钮外边距。 */
  get fabMargin(): number {
    return this.compact ? 16 : 24;
  }
}
