/**
 * 全局路由栈（Navigation 的 NavPathStack 进程内单例）。
 *
 * 设计目的：解耦「宿主页（pages/Index.ets）与各 NavDestination 页面」——
 * 页面不需要通过 @Param 层层传递 NavPathStack，直接 import 本模块即可导航。
 * 契约见 docs/dev-contracts.md §11。
 */

/** Navigation 绑定的路由栈（Index.ets 使用）。 */
export const pathStack: NavPathStack = new NavPathStack();

export const ROUTE_DETAIL: string = 'detail';
export const ROUTE_EDITOR: string = 'editor';
export const ROUTE_SETTINGS: string = 'settings';
export const ROUTE_LOG: string = 'log';
export const ROUTE_SCAN: string = 'scan';

/** 打开隧道详情页。 */
export function goDetail(tunnelName: string): void {
  pathStack.pushPath({ name: ROUTE_DETAIL, param: tunnelName });
}

/** 打开编辑器：不传名称=新建。 */
export function goEditor(tunnelName?: string): void {
  if (tunnelName === undefined) {
    pathStack.pushPath({ name: ROUTE_EDITOR, param: {} });
  } else {
    pathStack.pushPath({ name: ROUTE_EDITOR, param: { name: tunnelName } });
  }
}

/** 打开设置页。 */
export function goSettings(): void {
  pathStack.pushPath({ name: ROUTE_SETTINGS, param: {} });
}

/** 打开日志页。 */
export function goLog(): void {
  pathStack.pushPath({ name: ROUTE_LOG, param: {} });
}

/** 打开扫码页（如使用系统默认扫码 UI 则可不经此页）。 */
export function goScan(): void {
  pathStack.pushPath({ name: ROUTE_SCAN, param: {} });
}

/** 用详情页替换当前栈顶（编辑器保存后返回详情页用）。 */
export function replaceWithDetail(tunnelName: string): void {
  pathStack.replacePath({ name: ROUTE_DETAIL, param: tunnelName });
}

/** 返回上一页。 */
export function goBack(): void {
  pathStack.pop();
}

/** 从编辑器的 param 中取出隧道名（无 name 表示新建）。 */
export function editorParamName(param: object): string | null {
  const record = param as Record<string, Object>;
  const name = record['name'];
  if (typeof name === 'string' && name.length > 0) {
    return name;
  }
  return null;
}
