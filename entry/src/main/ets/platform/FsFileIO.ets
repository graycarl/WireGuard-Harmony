/*
 * FileIO 的平台实现：应用沙箱文件读写（docs/dev-contracts.md §5、决策 0003）。
 *
 * 原子写：写 `<path>.tmp` → fsync → rename 覆盖，保证崩溃时不产生半写的 tunnels.json。
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { FileIO } from '../repo/FileIO';
import { Logger } from '../util/Logger';

const TAG = 'FsFileIO';

export class FsFileIO implements FileIO {
  read(path: string): string | null {
    try {
      if (!fs.accessSync(path)) {
        return null;
      }
      return fs.readTextSync(path);
    } catch (e) {
      Logger.error(TAG, `读取 ${path} 失败：${(e as Error).message}`);
      return null;
    }
  }

  write(path: string, content: string): void {
    FsFileIO.ensureParent(path);
    const tmp = `${path}.tmp`;
    const file = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
    fs.renameSync(tmp, path);
  }

  rename(src: string, dst: string): void {
    fs.renameSync(src, dst);
  }

  private static ensureParent(path: string): void {
    const index = path.lastIndexOf('/');
    if (index <= 0) {
      return;
    }
    const dir = path.substring(0, index);
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      Logger.error(TAG, `创建目录 ${dir} 失败：${(e as Error).message}`);
    }
  }
}
