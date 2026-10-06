/*
 * 导入服务（specs/tunnel-import.md）：文件选择（.conf/.zip/图片）、zip 批量、
 * 相机扫码、图片二维码识别、隧道命名对话框、结果汇总提示。
 *
 * 平台能力：
 * - 文件选择/保存：CoreFileKit 的 picker + fileUri + fileIo；
 * - zip 解包：BasicServicesKit 的 zlib.decompressFile；
 * - 扫码/图片二维码：HMS ScanKit（scanBarcode/detectBarcode，见 SDK default/hms）；
 * - 相机可用性：CameraKit getSupportedCameras。
 *
 * 纯逻辑（类型判定、名称清理、汇总文案）在 ImportLogic，本地单测覆盖。
 */
import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore, detectBarcode } from '@kit.ScanKit';
import { camera } from '@kit.CameraKit';
import { buffer } from '@kit.ArkTS';
import { UIContext, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Config } from '../config/Config';
import { BadConfigException } from '../config/Exceptions';
import { isValidTunnelName } from '../config/Names';
import { AppStore } from '../store/AppStore';
import { Logger } from '../util/Logger';
import { NameDialogOptions, askTunnelName } from '../components/NameTunnelDialog';
import {
  ImportFileKind, baseName, classifyFileName, deriveTunnelName, importParseFailure,
  nameValidationError, sanitizeTunnelName, singleImportSuccess, summarizeBatch
} from './ImportLogic';

const DOMAIN = 0x0001;
const TAG = 'ImportService';
const MAX_TEXT_BYTES = 4 * 1024 * 1024;

/** 相机扫码可用性缓存（specs/tunnel-import.md：不可用时「+」面板不显示扫码入口）。 */
let scanReady: boolean = false;
let scanChecked: boolean = false;

export class ImportService {
  /** 扫码入口是否可用（refreshScanAvailability 之后有效）。 */
  static scanAvailable(): boolean {
    return scanReady;
  }

  /** 探测扫码可用性（列表页出现时调用一次）。 */
  static async refreshScanAvailability(context: common.Context): Promise<void> {
    if (scanChecked) {
      return;
    }
    scanChecked = true;
    if (!canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) {
      scanReady = false;
      return;
    }
    try {
      const manager = camera.getCameraManager(context);
      scanReady = manager.getSupportedCameras().length > 0;
    } catch (e) {
      const error = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'camera probe failed: %{public}s', error.message);
      scanReady = false;
    }
  }

  /**
   * 打开系统文件选择并按类型导入（specs/tunnel-import.md 方式一/二/四）。
   * @returns 需要 Toast 的文案；用户取消返回 null。
   */
  static async pickAndImport(context: common.Context): Promise<string | null> {
    let uris: string[] = [];
    try {
      const viewPicker = new picker.DocumentViewPicker(context);
      const selectOptions = new picker.DocumentSelectOptions();
      selectOptions.maxSelectNumber = 1;
      uris = await viewPicker.select(selectOptions);
    } catch (e) {
      const error = e as BusinessError;
      Logger.info(TAG, `文件选择取消或失败：${error.message}`);
      return null;
    }
    if (uris.length === 0) {
      return null;
    }
    const uri = uris[0];
    const displayName = ImportService.displayNameOf(uri);
    const kind = await ImportService.classify(uri, displayName);
    Logger.info(TAG, `导入文件 ${displayName}，类型 ${kind}`);

    if (kind === ImportFileKind.CONF) {
      return ImportService.importConfFile(context, uri, displayName);
    }
    if (kind === ImportFileKind.ZIP) {
      return ImportService.importZipFile(context, uri);
    }
    if (kind === ImportFileKind.IMAGE) {
      return ImportService.importImageQr(context, uri);
    }
    return '仅支持 .conf、.zip 或图片文件';
  }

  /**
   * 打开扫码界面并导入识别到的配置（specs/tunnel-import.md 方式三）。
   * 必须在 ArkUI 页面上下文中调用。
   */
  static async scanAndImport(context: common.Context): Promise<string | null> {
    let text: string | null = null;
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: false
      };
      const result = await scanBarcode.startScanForResult(context, options);
      text = result.originalValue;
    } catch (e) {
      const error = e as BusinessError;
      Logger.info(TAG, `扫码取消或失败：${error.code} ${error.message}`);
      return null;
    }
    if (text === null || text.length === 0) {
      return null;
    }
    let config: Config;
    try {
      config = Config.parse(text);
    } catch (e) {
      return importParseFailure((e as BadConfigException).message);
    }
    return ImportService.importWithDialog(context, '从二维码导入隧道', '', config);
  }

  // ---------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------

  /** 取文件显示名（拿不到时用 uri 末段）。 */
  private static displayNameOf(uri: string): string {
    try {
      return new fileUri.FileUri(uri).name;
    } catch (e) {
      return baseName(uri);
    }
  }

  /**
   * 类型判定：扩展名优先（图片 → .conf → .zip，specs/tunnel-import.md）；
   * 拿不到扩展名时按内容嗅探（PK 头 / [Interface] / 二维码），保证选到无扩展名文件也能导入。
   */
  private static async classify(uri: string, displayName: string): Promise<ImportFileKind> {
    const byName = classifyFileName(displayName);
    if (byName !== ImportFileKind.UNKNOWN) {
      return byName;
    }
    try {
      const head = new Uint8Array(ImportService.readRaw(uri, 4));
      if (head.length >= 4 && head[0] === 0x50 && head[1] === 0x4B && head[2] === 0x03 && head[3] === 0x04) {
        return ImportFileKind.ZIP;
      }
    } catch (e) {
      // 继续按文本/二维码尝试
    }
    try {
      const text = ImportService.readText(uri);
      if (text.toLowerCase().includes('[interface]')) {
        return ImportFileKind.CONF;
      }
    } catch (e) {
      // 非文本
    }
    try {
      const results = await detectBarcode.decode({ uri: uri });
      if (results.length > 0) {
        return ImportFileKind.IMAGE;
      }
    } catch (e) {
      // 非二维码图片
    }
    return ImportFileKind.UNKNOWN;
  }

  /** 方式一：单个 .conf（名称非法时弹命名对话框，specs/tunnel-import.md）。 */
  private static async importConfFile(context: common.Context, uri: string,
                                      displayName: string): Promise<string | null> {
    let text: string;
    try {
      text = ImportService.readText(uri);
    } catch (e) {
      const error = e as BusinessError;
      return `无法导入隧道：${error.message}`;
    }
    let config: Config;
    try {
      config = Config.parse(text);
    } catch (e) {
      return importParseFailure((e as BadConfigException).message);
    }
    const derived = deriveTunnelName(displayName);
    const suggested = derived.length > 0 ? derived : '导入的隧道 1';
    return ImportService.importWithDialog(context, '隧道命名', suggested, config, true);
  }

  /** 方式二：zip 批量导入（逐条独立、始终附失败原因）。 */
  private static async importZipFile(context: common.Context, uri: string): Promise<string | null> {
    const tempDir = `${context.cacheDir}/wg-import-${Date.now()}`;
    const zipPath = `${tempDir}.zip`;
    const outDir = tempDir;
    try {
      fs.mkdirSync(outDir, true);
      ImportService.copyToPath(uri, zipPath);
      await zlib.decompressFile(zipPath, outDir);
    } catch (e) {
      const error = e as BusinessError;
      ImportService.cleanup([zipPath, outDir]);
      return `无法导入隧道：${error.message}`;
    }

    const confFiles: string[] = [];
    ImportService.collectConfFiles(outDir, confFiles);
    if (confFiles.length === 0) {
      ImportService.cleanup([zipPath, outDir]);
      return '无法导入隧道：未找到配置';
    }

    const succeededNames: string[] = [];
    const failureReasons: string[] = [];
    for (const path of confFiles) {
      const fileName = baseName(path);
      const name = deriveTunnelName(fileName);
      if (!isValidTunnelName(name)) {
        failureReasons.push('无法导入隧道：名称无效');
        continue;
      }
      let config: Config;
      try {
        config = Config.parse(ImportService.readText(path));
      } catch (e) {
        failureReasons.push(importParseFailure((e as BadConfigException).message));
        continue;
      }
      const error = await AppStore.get().importTunnel(name, config);
      if (error !== null) {
        failureReasons.push(error);
      } else {
        succeededNames.push(name);
      }
    }
    ImportService.cleanup([zipPath, outDir]);
    return summarizeBatch(succeededNames, failureReasons);
  }

  /** 方式四：图片二维码（specs/tunnel-import.md 的四种提示文案）。 */
  private static async importImageQr(context: common.Context, uri: string): Promise<string | null> {
    let values: string[] = [];
    try {
      const results = await detectBarcode.decode({ uri: uri });
      for (const item of results) {
        if (item.originalValue.length > 0) {
          values.push(item.originalValue);
        }
      }
    } catch (e) {
      const error = e as BusinessError;
      return `无法导入隧道：${error.message}`;
    }
    if (values.length === 0) {
      return '无法导入隧道：图片中未发现二维码';
    }
    let config: Config;
    try {
      config = Config.parse(values[0]);
    } catch (e) {
      return '无法导入隧道：二维码校验失败';
    }
    return ImportService.importWithDialog(context, '从二维码导入隧道', '', config);
  }

  /**
   * 命名 + 导入（specs/tunnel-import.md）：
   * - dialogOnlyIfInvalid=true（单文件）：派生名称合法 → 直接导入（重名按 spec 直接失败并提示
   *   「无法导入隧道：名称 '<名称>' 已存在」）；派生名称非法 → 弹命名对话框；
   * - dialogOnlyIfInvalid=false（二维码/图片）：始终弹命名对话框；
   * - 取消返回 null（不提示）。
   */
  private static async importWithDialog(context: common.Context, title: string, suggested: string,
                                        config: Config, dialogOnlyIfInvalid: boolean = false): Promise<string | null> {
    if (dialogOnlyIfInvalid && isValidTunnelName(suggested)) {
      const directError = await AppStore.get().importTunnel(suggested, config);
      if (directError !== null) {
        return directError;
      }
      return singleImportSuccess(suggested);
    }
    const existing: string[] = [];
    for (const record of AppStore.get().records()) {
      existing.push(record.name);
    }
    const uiContext = await ImportService.uiContextOf(context);
    if (uiContext === null) {
      return '无法导入隧道：无法显示命名对话框';
    }
    const options = new NameDialogOptions();
    options.title = title;
    options.initialName = isValidTunnelName(suggested) ? suggested : sanitizeTunnelName(suggested);
    options.onSubmit = (name: string): string | null => nameValidationError(name, existing);
    let chosen: string | null;
    try {
      chosen = await askTunnelName(uiContext, options);
    } catch (e) {
      const error = e as BusinessError;
      Logger.error(TAG, `命名对话框打开失败：${error.message}`);
      return '无法导入隧道：无法显示命名对话框';
    }
    if (chosen === null) {
      return null;
    }
    const error = await AppStore.get().importTunnel(chosen, config);
    if (error !== null) {
      return error;
    }
    return singleImportSuccess(chosen);
  }

  /** 取当前窗口的 UIContext（命名对话框用）。 */
  private static async uiContextOf(context: common.Context): Promise<UIContext | null> {
    try {
      const topWindow = await window.getLastWindow(context);
      return topWindow.getUIContext();
    } catch (e) {
      const error = e as BusinessError;
      Logger.error(TAG, `获取 UI 上下文失败：${error.message}`);
      return null;
    }
  }

  /** 读取文件全部文本（UTF-8）。 */
  private static readText(path: string): string {
    return buffer.from(ImportService.readRaw(path, MAX_TEXT_BYTES)).toString('utf-8');
  }

  /** 读取前 maxBytes 个字节（文件短于上限时读全部），返回实际读到的字节。 */
  private static readRaw(path: string, maxBytes: number): ArrayBuffer {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      let size = maxBytes;
      try {
        const stat = fs.statSync(file.fd);
        if (stat.size > 0 && stat.size < maxBytes) {
          size = stat.size;
        }
      } catch (e) {
        // 用默认上限
      }
      const raw = new ArrayBuffer(size);
      const read = fs.readSync(file.fd, raw);
      return raw.slice(0, read);
    } finally {
      fs.closeSync(file);
    }
  }

  /** 把用户选择的文件（可能是 content uri）复制到应用沙箱路径。 */
  private static copyToPath(uri: string, dest: string): void {
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const out = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const chunk = new ArrayBuffer(64 * 1024);
        let read = 0;
        while ((read = fs.readSync(src.fd, chunk)) > 0) {
          fs.writeSync(out.fd, chunk.slice(0, read));
        }
      } finally {
        fs.closeSync(out);
      }
    } finally {
      fs.closeSync(src);
    }
  }

  /** 递归收集目录下扩展名为 .conf 的文件（忽略目录与其他类型）。 */
  private static collectConfFiles(dir: string, out: string[]): void {
    let names: string[] = [];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      const full = `${dir}/${name}`;
      let isDirectory = false;
      try {
        isDirectory = fs.statSync(full).isDirectory();
      } catch (e) {
        continue;
      }
      if (isDirectory) {
        ImportService.collectConfFiles(full, out);
      } else if (name.toLowerCase().endsWith('.conf')) {
        out.push(full);
      }
    }
  }

  /** 清理临时文件/目录（尽力而为）。 */
  private static cleanup(paths: string[]): void {
    for (const path of paths) {
      try {
        fs.rmdirSync(path);
      } catch (e) {
        try {
          fs.unlinkSync(path);
        } catch (e2) {
          // 忽略
        }
      }
    }
  }
}
