/*
 * 隧道后端（单激活互斥，docs/decisions/0006；specs/tunnel-connection.md）。
 *
 * 职责：
 * - 维护「当前激活隧道名」单一真源（由 VPN 进程的公共事件驱动，UI 不维护意图态）；
 * - connect(B) 时若 A 已激活：先断开 A 再连接 B；B 失败则尽力恢复 A（切换隧道回滚）；
 * - 等待 up/down 事件以确认操作结果（带超时）。
 *
 * 上行事件由 VPN 进程发布（docs/decisions/0004），本类只订阅。
 */

import { commonEventManager } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { decodePayload, IpcPayload, IpcState, TUNNEL_EVENT } from './IpcProtocol';
import { VpnController } from './VpnController';
import { Logger } from '../util/Logger';

const TAG = 'Backend';
const CONNECT_TIMEOUT_MS = 15000;
const DISCONNECT_TIMEOUT_MS = 8000;

interface Waiter {
  tunnel: string;
  timer: number;
  resolve: () => void;
  reject: (error: Error) => void;
}

export class Backend {
  private static instance: Backend | null = null;
  private active: string | null = null;
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;
  private listeners: Array<(payload: IpcPayload) => void> = [];
  private upWaiter: Waiter | null = null;
  private downWaiter: Waiter | null = null;
  private initialized = false;

  static get(): Backend {
    if (Backend.instance === null) {
      Backend.instance = new Backend();
    }
    return Backend.instance;
  }

  /** 订阅 VPN 进程上行的隧道事件（幂等）。 */
  initIpc(context: common.Context): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    try {
      const info: commonEventManager.CommonEventSubscribeInfo = { events: [TUNNEL_EVENT] };
      this.subscriber = commonEventManager.createSubscriberSync(info);
      const handler = (data: commonEventManager.CommonEventData): void => {
        this.onEvent(data);
      };
      commonEventManager.subscribeToEvent(this.subscriber, handler)
        .catch((error: Error): void => {
          Logger.error(TAG, `订阅隧道事件失败：${error.message}`);
        });
    } catch (e) {
      Logger.error(TAG, `创建隧道事件订阅者失败：${(e as Error).message}`);
    }
  }

  /** 当前激活隧道名（来自真实事件；冷启动为 null）。 */
  activeName(): string | null {
    return this.active;
  }

  /** 由状态事件更新激活隧道（供事件处理与测试）。 */
  setActiveFromEvent(tunnel: string, state: IpcState): void {
    if (state === 'up') {
      this.active = tunnel;
    } else if (this.active === tunnel) {
      this.active = null;
    }
  }

  /** 连接隧道；必要时先断开当前激活隧道，失败时尽力回滚。 */
  async connect(name: string): Promise<void> {
    if (this.active === name) {
      return;
    }
    const previous = this.active;
    if (previous !== null) {
      await this.disconnect(previous);
    }
    let started = false;
    try {
      await VpnController.start(name);
      started = true;
      await this.waitForUp(name, CONNECT_TIMEOUT_MS);
      this.active = name;
    } catch (e) {
      if (started) {
        try {
          await VpnController.stop(name);
        } catch (ignored) {
          // 清理失败可忽略（系统会在 UI 进程退出时停止）
        }
      }
      if (previous !== null) {
        await this.restore(previous);
      }
      throw e as Error;
    }
  }

  /** 断开隧道；无论是否收到事件，超时后按已断开处理。 */
  async disconnect(name: string): Promise<void> {
    if (this.active !== name) {
      return;
    }
    await VpnController.stop(name);
    await this.waitForDown(name, DISCONNECT_TIMEOUT_MS);
    if (this.active === name) {
      this.active = null;
    }
  }

  addListener(listener: (payload: IpcPayload) => void): void {
    this.listeners.push(listener);
  }

  removeListener(listener: (payload: IpcPayload) => void): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  private async restore(name: string): Promise<void> {
    try {
      await VpnController.start(name);
      await this.waitForUp(name, CONNECT_TIMEOUT_MS);
      this.active = name;
      Logger.info(TAG, `已恢复原隧道 ${name}`);
    } catch (e) {
      Logger.error(TAG, `恢复原隧道 ${name} 失败：${(e as Error).message}`);
    }
  }

  private onEvent(data: commonEventManager.CommonEventData): void {
    const raw = data.data;
    if (typeof raw !== 'string' || raw.length === 0) {
      return;
    }
    const payload = decodePayload(raw);
    if (payload === null) {
      Logger.error(TAG, '收到无法解析的隧道事件');
      return;
    }
    if (payload.state === 'up') {
      this.active = payload.tunnel;
      const up = this.upWaiter;
      if (up !== null && up.tunnel === payload.tunnel) {
        clearTimeout(up.timer);
        this.upWaiter = null;
        up.resolve();
      }
    } else {
      if (this.active === payload.tunnel) {
        this.active = null;
      }
      const down = this.downWaiter;
      if (down !== null && down.tunnel === payload.tunnel) {
        clearTimeout(down.timer);
        this.downWaiter = null;
        down.resolve();
      }
      const up = this.upWaiter;
      if (up !== null && up.tunnel === payload.tunnel) {
        clearTimeout(up.timer);
        this.upWaiter = null;
        const reason = payload.error !== undefined && payload.error.length > 0
          ? payload.error
          : '无法启动 VPN 服务';
        up.reject(new Error(reason));
      }
    }
    for (const listener of this.listeners.slice()) {
      try {
        listener(payload);
      } catch (e) {
        Logger.error(TAG, `事件监听者异常：${(e as Error).message}`);
      }
    }
  }

  private waitForUp(tunnel: string, timeoutMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (error: Error) => void): void => {
      const timer: number = setTimeout((): void => {
        if (this.upWaiter !== null && this.upWaiter.tunnel === tunnel) {
          this.upWaiter = null;
        }
        reject(new Error('无法启动 VPN 服务'));
      }, timeoutMs);
      this.upWaiter = { tunnel: tunnel, timer: timer, resolve: resolve, reject: reject };
    });
  }

  private waitForDown(tunnel: string, timeoutMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      const timer: number = setTimeout((): void => {
        if (this.downWaiter !== null && this.downWaiter.tunnel === tunnel) {
          this.downWaiter = null;
        }
        resolve();
      }, timeoutMs);
      const reject = (): void => {
        resolve();
      };
      this.downWaiter = { tunnel: tunnel, timer: timer, resolve: resolve, reject: reject };
    });
  }
}
