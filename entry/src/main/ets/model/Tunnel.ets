import { TunnelRecord } from '../repo/TunnelRecord';

/**
 * 隧道领域模型（见 docs/dev-contracts.md §5）。
 *
 * 注意：按并行开发解耦约定，本类不引用 config/ 模块的 Config 类型——
 * 配置以 repo/ 定义的结构化记录 TunnelRecord 承载；
 * Config（wg-quick 对象）↔ TunnelRecord 的双向转换由 store/ 层负责
 * （config/ 与 repo/ 合并后统一实现）。
 */
export class Tunnel {
  name: string;
  record: TunnelRecord;

  constructor(name: string, record: TunnelRecord) {
    this.name = name;
    this.record = record;
  }
}
