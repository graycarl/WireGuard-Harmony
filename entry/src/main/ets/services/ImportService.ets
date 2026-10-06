/**
 * 导入服务（供「+」面板调用；specs/tunnel-import.md）。
 *
 * ⚠️ 本文件在骨架阶段是**占位实现**：由「导入功能」任务替换为完整实现
 * （文件选择 .conf/.zip/图片、zip 解包、扫码、图片二维码识别、命名对话框）。
 * 调用方（list 页的「+」面板）只依赖以下签名，替换实现时不得修改签名。
 */
import { common } from '@kit.AbilityKit';

export class ImportService {
  private static scanReady: boolean = false;

  /** 相机扫码是否可用（决定「+」面板是否显示「扫描二维码」，specs/tunnel-import.md）。 */
  static scanAvailable(): boolean {
    return ImportService.scanReady;
  }

  /** 探测扫码可用性（应用启动/列表页出现时调用一次即可）。 */
  static async refreshScanAvailability(context: common.Context): Promise<void> {
    ImportService.scanReady = false;
  }

  /**
   * 打开系统文件选择：按「图片类型 → .conf → .zip」判定并导入。
   * @returns 需要展示的提示文案（成功/失败，含 spec 规定的「导入失败：<原因>」）；
   *          用户取消时返回 null（不提示）。
   */
  static async pickAndImport(context: common.Context): Promise<string | null> {
    return null;
  }

  /**
   * 打开扫码界面并导入识别到的配置（含命名对话框）。
   * @returns 提示文案；用户取消/扫码不可用返回 null。
   */
  static async scanAndImport(context: common.Context): Promise<string | null> {
    return null;
  }
}
