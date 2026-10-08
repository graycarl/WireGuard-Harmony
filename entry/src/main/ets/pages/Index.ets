/*
 * 应用首页：Navigation 宿主 + 隧道列表（specs/tunnel-list.md、docs/dev-contracts.md §11）。
 *
 * - 列表是 Navigation 的首页内容（NavBar），详情/编辑器/设置/日志/扫码为 NavDestination；
 * - 路由表 PageMap 必须绑定组件内 @Builder 方法（AGENTS.md 已知坑）；
 * - 单栏显式 Stack 模式；隐藏默认标题栏/工具栏避免占位；正文延伸到底部用
 *   Navigation 级 ignoreLayoutSafeArea（AGENTS.md 已知坑）。
 */

import { AppStore } from '../store/AppStore';
import { screenState } from '../components/ScreenState';
import { ImportService } from '../services/ImportService';
import { paramAsTunnelName } from '../util/RouteParams';
import { ListBackHandler, TunnelListPage } from './TunnelListPage';
import { TunnelDetailPage } from './TunnelDetailPage';
import { TunnelEditorPage } from './TunnelEditorPage';
import { SettingsPage } from './SettingsPage';
import { LogPage } from './LogPage';
import { ScanPage } from './ScanPage';
import { pathStack, ROUTE_DETAIL, ROUTE_EDITOR, ROUTE_LOG, ROUTE_SCAN, ROUTE_SETTINGS } from './RouteStack';

@Entry
@ComponentV2
struct Index {
  @Local pageStack: NavPathStack = pathStack;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      AppStore.get().init(context);
      ImportService.refreshScanAvailability(context);
    }
  }

  /** 系统返回键：多选模式下先退出多选（列表页处理），否则走默认返回。 */
  onBackPress(): boolean {
    return ListBackHandler.handleBack();
  }

  @Builder
  PageMap(name: string, param: object) {
    if (name === ROUTE_DETAIL) {
      NavDestination() {
        TunnelDetailPage({ tunnelName: paramAsTunnelName(param) })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_EDITOR) {
      NavDestination() {
        TunnelEditorPage({ param: param })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_SETTINGS) {
      NavDestination() {
        SettingsPage()
      }
      .title('设置')
    } else if (name === ROUTE_LOG) {
      NavDestination() {
        LogPage()
      }
      .title('应用日志')
    } else if (name === ROUTE_SCAN) {
      NavDestination() {
        ScanPage()
      }
      .title('扫描二维码')
    }
  }

  build() {
    Navigation(this.pageStack) {
      TunnelListPage()
    }
    .navDestination(this.PageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
    .backgroundColor($r('app.color.page_bg'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    // 紧凑模式唯一测量点（决策 0009）：窗口尺寸（vp）变化驱动全局 screenState，
    // 覆盖折叠/展开、横竖屏、小窗缩放等一切窗口变化。
    .onAreaChange((oldValue: Area, newValue: Area) => {
      screenState.update(newValue.width as number, newValue.height as number);
    })
  }
}
