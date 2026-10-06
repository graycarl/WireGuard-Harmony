/*
 * 全局状态门面（UI 唯一入口，docs/dev-contracts.md §6）。
 *
 * - 页面只与本类交互：读隧道列表/快照、执行增删改、订阅变化；
 * - 隧道连接状态是「外部真源」（VPN 进程事件），本类只维护快照，不做意图猜测；
 * - 普通类单例 + addListener/removeListener：页面用 `@Local version: number` 自增触发重渲
 *   （AGENTS.md 核心设计决策 4）。
 */

import { common } from '@kit.AbilityKit';
import { TunnelRepository } from '../repo/TunnelRepository';
import { TunnelRecord } from '../repo/TunnelRecord';
import { Tunnel } from '../model/Tunnel';
import { TunnelState } from '../model/TunnelState';
import { PeerStats } from '../model/PeerStats';
import { RecordMapper } from './RecordMapper';
import { Config } from '../config/Config';
import { compareTunnelNames, isValidTunnelName } from '../config/Names';
import { FsFileIO } from '../platform/FsFileIO';
import { Logger } from '../util/Logger';
import { Backend } from '../backend/Backend';
import { IpcPayload } from '../backend/IpcProtocol';

const TAG = 'AppStore';

export interface TunnelSnapshot {
  name: string;
  state: TunnelState;
  /** 各 Peer 实时统计；未连接时为空数组 */
  peers: PeerStats[];
}

export class AppStore {
  private static instance: AppStore | null = null;
  private repo: TunnelRepository | null = null;
  private initialized = false;
  private states: Map<string, TunnelState> = new Map();
  private stats: Map<string, PeerStats[]> = new Map();
  private toggling: Set<string> = new Set();
  private listeners: Array<() => void> = [];
  private ipcListener: ((payload: IpcPayload) => void) | null = null;

  static get(): AppStore {
    if (AppStore.instance === null) {
      AppStore.instance = new AppStore();
    }
    return AppStore.instance;
  }

  /** 初始化（幂等）。UIAbility 启动时调用。 */
  init(context: common.Context): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    Logger.init(context, 'ui');
    this.repo = new TunnelRepository(new FsFileIO(), context.filesDir, undefined,
      (message: string): void => Logger.info('repo', message));
    const backend = Backend.get();
    backend.initIpc(context);
    this.ipcListener = (payload: IpcPayload): void => {
      this.onIpc(payload);
    };
    backend.addListener(this.ipcListener);
    Logger.info(TAG, 'AppStore 初始化完成');
  }

  /** 全部隧道记录（按隧道名自然排序；每次从磁盘读取，量小）。 */
  records(): TunnelRecord[] {
    const repo = this.repo;
    if (repo === null) {
      return [];
    }
    const list = repo.load();
    list.sort((a: TunnelRecord, b: TunnelRecord): number => compareTunnelNames(a.name, b.name));
    return list;
  }

  /** 全部隧道领域对象（同上排序）。 */
  tunnels(): Tunnel[] {
    const out: Tunnel[] = [];
    for (const record of this.records()) {
      out.push(new Tunnel(record.name, record));
    }
    return out;
  }

  /** 隧道配置；不存在或不可解析返回 null。 */
  configOf(name: string): Config | null {
    const record = this.findRecord(name);
    if (record === null) {
      return null;
    }
    try {
      return RecordMapper.toConfig(record);
    } catch (e) {
      Logger.error(TAG, `解析隧道 ${name} 配置失败：${(e as Error).message}`);
      return null;
    }
  }

  /** 隧道快照（状态 + 统计）。 */
  snapshot(name: string): TunnelSnapshot {
    const state = this.states.get(name);
    const peers = this.stats.get(name);
    const snapshot: TunnelSnapshot = {
      name: name,
      state: state === undefined ? TunnelState.DOWN : state,
      peers: peers === undefined ? [] : peers
    };
    return snapshot;
  }

  /** 当前激活隧道名（真实事件驱动，冷启动为 null）。 */
  activeName(): string | null {
    return Backend.get().activeName();
  }

  /** 开关是否处于「结果未确定」的禁用态。 */
  isToggling(name: string): boolean {
    return this.toggling.has(name);
  }

  /**
   * 开关隧道。成功返回 null；失败返回已包装文案
   * （「建立连接时出错：<原因>」/「断开连接时出错：<原因>」）。
   */
  async toggle(name: string): Promise<string | null> {
    if (this.toggling.has(name)) {
      return null;
    }
    const currentlyUp = this.snapshot(name).state === TunnelState.UP;
    this.toggling.add(name);
    this.notify();
    try {
      if (currentlyUp) {
        await Backend.get().disconnect(name);
      } else {
        await Backend.get().connect(name);
      }
      return null;
    } catch (e) {
      const prefix = currentlyUp ? '断开连接时出错：' : '建立连接时出错：';
      return `${prefix}${AppStore.messageOf(e)}`;
    } finally {
      this.toggling.delete(name);
      this.notify();
    }
  }

  /** 新建隧道（specs/tunnel-editor.md 保存情形一）。 */
  async create(name: string, config: Config): Promise<string | null> {
    const repo = this.repo;
    if (repo === null) {
      return `无法保存 '${name}' 的配置：存储未初始化`;
    }
    if (!isValidTunnelName(name)) {
      return '无法创建隧道：名称无效';
    }
    try {
      if (this.findRecord(name) !== null) {
        return `无法创建隧道：名称 '${name}' 已存在`;
      }
      repo.add(RecordMapper.toRecord(name, config));
    } catch (e) {
      return `无法保存 '${name}' 的配置：${AppStore.messageOf(e)}`;
    }
    this.notify();
    return null;
  }

  /**
   * 保存已有隧道（改名 / 改配置；specs/tunnel-editor.md 保存情形二、三）。
   * 正在连接的隧道：先断开 → 保存 → 以新配置重连（短暂中断）。
   */
  async save(originalName: string, name: string, config: Config): Promise<string | null> {
    const repo = this.repo;
    if (repo === null) {
      return `无法保存 '${name}' 的配置：存储未初始化`;
    }
    const renaming = name !== originalName;
    if (renaming && !isValidTunnelName(name)) {
      return '无法重命名隧道：名称无效';
    }
    if (!renaming && !isValidTunnelName(name)) {
      return '无法创建隧道：名称无效';
    }
    const wasActive = this.activeName() === originalName;
    if (wasActive) {
      try {
        await Backend.get().disconnect(originalName);
      } catch (e) {
        return renaming
          ? `无法重命名隧道：${AppStore.messageOf(e)}`
          : `无法保存 '${name}' 的配置：${AppStore.messageOf(e)}`;
      }
    }
    try {
      if (renaming) {
        if (this.findRecord(name) !== null) {
          return `无法重命名隧道：名称 '${name}' 已存在`;
        }
        repo.rename(originalName, name);
      }
      repo.replace(name, RecordMapper.toRecord(name, config));
    } catch (e) {
      const reason = AppStore.messageOf(e);
      if (renaming) {
        const renamed = this.findRecord(name) !== null;
        return renamed ? `无法保存 '${name}' 的配置：${reason}` : `无法重命名隧道：${reason}`;
      }
      return `无法保存 '${name}' 的配置：${reason}`;
    }
    if (wasActive) {
      try {
        await Backend.get().connect(name);
      } catch (e) {
        this.notify();
        return renaming
          ? `无法重命名隧道：${AppStore.messageOf(e)}`
          : `建立连接时出错：${AppStore.messageOf(e)}`;
      }
    }
    this.notify();
    return null;
  }

  /** 导入隧道（specs/tunnel-import.md）：成功 null，失败「无法导入隧道：<原因>」。 */
  async importTunnel(name: string, config: Config): Promise<string | null> {
    const repo = this.repo;
    if (repo === null) {
      return '无法导入隧道：存储未初始化';
    }
    if (!isValidTunnelName(name)) {
      return '无法导入隧道：名称无效';
    }
    try {
      if (this.findRecord(name) !== null) {
        return `无法导入隧道：名称 '${name}' 已存在`;
      }
      repo.add(RecordMapper.toRecord(name, config));
    } catch (e) {
      return `无法导入隧道：${AppStore.messageOf(e)}`;
    }
    this.notify();
    return null;
  }

  /**
   * 批量删除（specs/tunnel-list.md、tunnel-connection.md）。
   * 已连接项先断开；断开失败的项计入失败数并跳过删除；整批继续。
   * 全部成功返回 null，否则「无法删除 N 项：<原因>」。
   */
  async remove(names: string[]): Promise<string | null> {
    const repo = this.repo;
    if (repo === null) {
      return `无法删除 ${names.length} 项：存储未初始化`;
    }
    let failed = 0;
    let lastReason = '';
    for (const name of names) {
      const isActive = this.activeName() === name;
      if (isActive) {
        try {
          await Backend.get().disconnect(name);
        } catch (e) {
          failed++;
          lastReason = AppStore.messageOf(e);
          continue;
        }
      }
      try {
        repo.remove([name]);
        this.states.delete(name);
        this.stats.delete(name);
      } catch (e) {
        failed++;
        lastReason = AppStore.messageOf(e);
        if (isActive) {
          try {
            await Backend.get().connect(name);
          } catch (ignored) {
            // 恢复连接失败：以真实状态呈现
          }
        }
      }
    }
    this.notify();
    if (failed === 0) {
      return null;
    }
    return `无法删除 ${failed} 项：${lastReason}`;
  }

  addListener(listener: () => void): void {
    this.listeners.push(listener);
  }

  removeListener(listener: () => void): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  private findRecord(name: string): TunnelRecord | null {
    const repo = this.repo;
    if (repo === null) {
      return null;
    }
    return repo.findByName(name);
  }

  private onIpc(payload: IpcPayload): void {
    if (payload.state === 'up') {
      this.states.set(payload.tunnel, TunnelState.UP);
      this.stats.set(payload.tunnel, payload.peers);
    } else {
      this.states.set(payload.tunnel, TunnelState.DOWN);
      this.stats.delete(payload.tunnel);
    }
    this.notify();
  }

  private notify(): void {
    for (const listener of this.listeners.slice()) {
      try {
        listener();
      } catch (e) {
        Logger.error(TAG, `状态监听者异常：${(e as Error).message}`);
      }
    }
  }

  private static messageOf(error: Object): string {
    const err = error as Error;
    if (err !== null && err !== undefined && typeof err.message === 'string' && err.message.length > 0) {
      return err.message;
    }
    return `${error}`;
  }
}
