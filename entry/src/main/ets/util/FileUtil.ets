/*
 * 文件读写小工具（设置页导出、日志导出共用）。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 创建目录（含父目录）；已存在不报错。 */
export function ensureDir(path: string): void {
  try {
    fs.mkdirSync(path, true);
  } catch (e) {
    // 已存在
  }
}

/** 全量写入文本（覆盖）。 */
export function writeTextFile(path: string, content: string): void {
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, content);
  } finally {
    fs.closeSync(file);
  }
}

/** 复制文件（src 可为沙箱路径或用户授权的 uri）。 */
export function copyFileTo(src: string, dest: string): void {
  const input = fs.openSync(src, fs.OpenMode.READ_ONLY);
  try {
    const output = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const chunk = new ArrayBuffer(64 * 1024);
      let read = 0;
      while ((read = fs.readSync(input.fd, chunk)) > 0) {
        fs.writeSync(output.fd, chunk.slice(0, read));
      }
    } finally {
      fs.closeSync(output);
    }
  } finally {
    fs.closeSync(input);
  }
}

/** 尽力删除文件/目录（忽略错误）。 */
export function removeAll(paths: string[]): void {
  for (const path of paths) {
    try {
      fs.rmdirSync(path);
    } catch (e) {
      try {
        fs.unlinkSync(path);
      } catch (inner) {
        // 忽略
      }
    }
  }
}

/** 错误信息（BusinessError 优先）。 */
export function errorMessage(error: Object): string {
  const businessError = error as BusinessError;
  if (businessError !== undefined && businessError.message !== undefined) {
    return businessError.message;
  }
  return `${error}`;
}
