/**
 * 文件 I/O 注入接口（见 docs/dev-contracts.md §5 / 决策 0003）。
 *
 * repo/ 是纯逻辑模块（禁 import @kit），文件读写由调用方注入：
 * - UI 进程（store/）与 VPN 进程（vpnability/）各自用 @kit.CoreFileKit 的 fs 实现；
 * - 本地单测注入内存实现。
 *
 * 原子写约定：write() 的实现方必须保证原子性（写 tmp 文件 + flush + rename），
 * 本模块不感知 tmp/rename 细节；崩溃时不得产生半写的 tunnels.json。
 */
export interface FileIO {
  /** 读取文件全部内容；文件不存在返回 null（不抛错）。 */
  read(path: string): string | null;

  /** 全量覆写文件内容（实现方保证原子写）。 */
  write(path: string, content: string): void;

  /** 重命名/移动文件（同目录内原子替换）。 */
  rename(src: string, dst: string): void;
}
