/**
 * 底部提示（Toast）薄封装。
 *
 * spec 中的操作反馈统一走这里（文案由调用方按 spec 逐字给出）。
 */
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'Toast';

export class Toast {
  /** 展示 2 秒提示；失败降级为日志（不抛错）。 */
  static show(message: string): void {
    try {
      promptAction.showToast({ message: message, duration: 2000 });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'showToast failed: %{public}s', JSON.stringify(e));
    }
  }
}
