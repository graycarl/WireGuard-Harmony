/*
 * 应用日志（specs/settings.md §查看应用日志、specs/privacy-security.md §5）。
 *
 * 设计要点：
 * - 每个进程写自己的文件（ui.log / vpn.log），避免两进程并发写同一文件互相破坏；
 * - 行格式：`2026-10-07 12:00:00.123 [I] tag: msg`，前缀时间戳可直接字典序排序；
 * - 单文件超过 256KB 时保留后半并重写（环形截断），避免无限增长；
 * - **绝不记录私钥/预共享密钥**：提供 redactSecrets() 供调用方兜底（见 privacy-security 待办）。
 * - 平台不可用时（本地单测/未初始化）静默降级为 hilog。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const MAX_BYTES = 256 * 1024;
const LOG_SUFFIX = '.log';

function pad(value: number, width: number): string {
  let text = `${value}`;
  while (text.length < width) {
    text = `0${text}`;
  }
  return text;
}

function timestamp(now: number): string {
  const date = new Date(now);
  const y = date.getFullYear();
  const mo = pad(date.getMonth() + 1, 2);
  const d = pad(date.getDate(), 2);
  const h = pad(date.getHours(), 2);
  const mi = pad(date.getMinutes(), 2);
  const s = pad(date.getSeconds(), 2);
  const ms = pad(date.getMilliseconds(), 3);
  return `${y}-${mo}-${d} ${h}:${mi}:${s}.${ms}`;
}

export class Logger {
  private static context: common.Context | null = null;
  private static processName: string = 'app';
  private static listeners: Array<() => void> = [];

  /** 初始化（幂等）。processName 用于区分进程日志文件（'ui' / 'vpn'）。 */
  static init(context: common.Context, processName: string): void {
    Logger.context = context;
    Logger.processName = processName;
    Logger.ensureDir();
  }

  static info(tag: string, message: string): void {
    Logger.write('I', tag, message);
  }

  static error(tag: string, message: string): void {
    Logger.write('E', tag, message);
  }

  /** 合并 logs/ 下全部日志文件，按时间戳（旧→新）排序返回。 */
  static readAll(): string[] {
    const dir = Logger.dir();
    if (dir === null) {
      return [];
    }
    let names: string[] = [];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      return [];
    }
    const lines: string[] = [];
    for (const name of names) {
      if (!name.endsWith(LOG_SUFFIX)) {
        continue;
      }
      const path = name.startsWith('/') ? name : `${dir}/${name}`;
      try {
        const content = fs.readTextSync(path);
        for (const line of content.split('\n')) {
          if (line.length > 0) {
            lines.push(line);
          }
        }
      } catch (e) {
        // 忽略读失败的文件
      }
    }
    lines.sort((a: string, b: string): number => {
      if (a === b) {
        return 0;
      }
      return a < b ? -1 : 1;
    });
    return lines;
  }

  /** 日志目录（context 未初始化时返回 null）。 */
  static logDir(): string | null {
    return Logger.dir();
  }

  /** 把所有日志合并导出为一个文本文件。 */
  static async exportTo(destPath: string): Promise<void> {
    const lines = Logger.readAll();
    const file = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, lines.length > 0 ? `${lines.join('\n')}\n` : '');
    } finally {
      fs.closeSync(file);
    }
  }

  /** 订阅「有新日志」通知（日志页自动滚动用）。 */
  static subscribe(callback: () => void): void {
    Logger.listeners.push(callback);
  }

  static unsubscribe(callback: () => void): void {
    const index = Logger.listeners.indexOf(callback);
    if (index >= 0) {
      Logger.listeners.splice(index, 1);
    }
  }

  /** 清空本应用日志文件。 */
  static clear(): void {
    const dir = Logger.dir();
    if (dir === null) {
      return;
    }
    let names: string[] = [];
    try {
      names = fs.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      if (!name.endsWith(LOG_SUFFIX)) {
        continue;
      }
      const path = name.startsWith('/') ? name : `${dir}/${name}`;
      try {
        fs.unlinkSync(path);
      } catch (e) {
        // 忽略
      }
    }
    Logger.notify();
  }

  /** 把疑似密钥的 base64 串替换为占位符（调用方在记录外部文本前调用）。 */
  static redactSecrets(text: string): string {
    return text.replace(/[A-Za-z0-9+/]{43}=/g, '[REDACTED]');
  }

  private static dir(): string | null {
    const context = Logger.context;
    if (context === null) {
      return null;
    }
    return `${context.filesDir}/logs`;
  }

  private static ensureDir(): void {
    const dir = Logger.dir();
    if (dir === null) {
      return;
    }
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      // 目录已存在或无权限：忽略，写日志时会降级
    }
  }

  private static write(level: string, tag: string, message: string): void {
    if (level === 'E') {
      hilog.error(DOMAIN, tag, '%{public}s', message);
    } else {
      hilog.info(DOMAIN, tag, '%{public}s', message);
    }
    const dir = Logger.dir();
    if (dir === null) {
      return;
    }
    Logger.ensureDir();
    const filePath = `${dir}/${Logger.processName}.log`;
    const line = `${timestamp(Date.now())} [${level}] ${tag}: ${message}`;
    try {
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
      try {
        fs.writeSync(file.fd, `${line}\n`);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return;
    }
    Logger.truncateIfNeeded(filePath);
    Logger.notify();
  }

  private static truncateIfNeeded(filePath: string): void {
    try {
      const stat = fs.statSync(filePath);
      if (stat.size <= MAX_BYTES) {
        return;
      }
      const content = fs.readTextSync(filePath);
      const lines = content.split('\n');
      const kept = lines.slice(Math.floor(lines.length / 2)).join('\n');
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, kept);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      // 截断失败不影响主流程
    }
  }

  private static notify(): void {
    for (const listener of Logger.listeners.slice()) {
      try {
        listener();
      } catch (e) {
        // 监听者异常不影响日志写入
      }
    }
  }
}
