/**
 * 剪贴板薄封装（spec privacy-security.md §7：只写入用户点击的具体字段，不读取剪贴板）。
 */
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Toast } from './Toast';

const DOMAIN = 0x0001;
const TAG = 'Clipboard';

export class Clipboard {
  /** 写入纯文本；失败静默记日志（不打扰用户）。 */
  static async write(text: string): Promise<void> {
    try {
      const data = pasteboard.createPlainTextData(text);
      await pasteboard.getSystemPasteboard().setData(data);
    } catch (e) {
      const error = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'setData failed: %{public}s', error.message);
    }
  }

  /**
   * 复制字段值并提示「<字段名> 已复制到剪贴板」（spec tunnel-detail.md §一键复制）。
   * 值为空时不提示（调用方应保证空值行不渲染）。
   */
  static async copyField(fieldName: string, text: string): Promise<void> {
    await Clipboard.write(text);
    Toast.show(`${fieldName} 已复制到剪贴板`);
  }
}
