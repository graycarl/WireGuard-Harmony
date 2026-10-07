/*
 * 连接开关（列表页与详情页共用；specs/tunnel-connection.md、specs/tunnel-list.md）。
 *
 * 自订阅 AppStore（不依赖父组件透传状态，避免 ForEach 键值复用导致 @Param 不刷新）：
 * - 操作期间（toggling）禁用开关；
 * - 结果以「外部真源」快照为准，失败自动弹回原位并提示。
 */

import { AppStore } from '../store/AppStore';
import { TunnelState } from '../model/TunnelState';
import { Toast } from '../util/Toast';

@ComponentV2
export struct TunnelSwitch {
  /** 隧道名。 */
  @Param name: string = '';
  /** 外部真源的连接状态（自订阅维护）。 */
  @Local up: boolean = false;
  /** 连接结果是否未确定（未确定时禁用）。 */
  @Local toggling: boolean = false;
  /** 显示态（乐观翻转，最终以快照校正）。 */
  @Local isOn: boolean = false;
  private storeListener: () => void = () => {};

  aboutToAppear(): void {
    this.storeListener = () => {
      this.refresh();
    };
    AppStore.get().addListener(this.storeListener);
    this.refresh();
  }

  aboutToDisappear(): void {
    AppStore.get().removeListener(this.storeListener);
  }

  private refresh(): void {
    const snapshot = AppStore.get().snapshot(this.name);
    const up = snapshot.state === TunnelState.UP;
    const toggling = AppStore.get().isToggling(this.name);
    if (up !== this.up) {
      this.up = up;
      this.isOn = up;
    }
    if (toggling !== this.toggling) {
      this.toggling = toggling;
    }
  }

  private async doToggle(): Promise<void> {
    const message = await AppStore.get().toggle(this.name);
    // 无论成功失败都以真实快照校正显示态
    this.isOn = AppStore.get().snapshot(this.name).state === TunnelState.UP;
    this.refresh();
    if (message !== null) {
      Toast.show(message);
    }
  }

  build() {
    Toggle({ type: ToggleType.Switch, isOn: this.isOn })
      .selectedColor($r('app.color.accent'))
      .switchPointColor($r('app.color.on_accent'))
      .enabled(!this.toggling)
      .onChange((isOn: boolean) => {
        this.isOn = isOn;
        if (isOn === this.up) {
          // 程序性同步（非用户操作），不发起连接动作
          return;
        }
        this.doToggle();
      })
  }
}
