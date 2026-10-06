/**
 * 全局路由栈（Navigation 的 NavPathStack 进程内单例）。
 *
 * 设计目的：解耦「宿主页（pages/Index.ets）与各 NavDestination 页面」——
 * 页面不需要通过 @Param 层层传递 NavPathStack，直接 import 本模块即可导航。
 * 契约见 docs/dev-contracts.md §11。
 *
 * 路由参数约定：
 * - detail：param 为隧道名（string）；
 * - editor：param 为 EditorParam（name 为空串表示新建）；
 * - settings / log / scan：param 为 ''（无参数）。
 */

/** Navigation 绑定的路由栈（Index.ets 使用）。 */
export const pathStack: NavPathStack = new NavPathStack();

export const ROUTE_DETAIL: string = 'detail';
export const ROUTE_EDITOR: string = 'editor';
export const ROUTE_SETTINGS: string = 'settings';
export const ROUTE_LOG: string = 'log';
export const ROUTE_SCAN: string = 'scan';

/** 无参数页面的占位参数（避免 ArkTS 禁止的对象字面量）。 */
export class EmptyParam {
}

/** 编辑器路由参数。 */
export class EditorParam {
  name: string = '';
}

/** 打开隧道详情页。 */
export function goDetail(tunnelName: string): void {
  pathStack.pushPathByName(ROUTE_DETAIL, tunnelName);
}

/** 打开编辑器：不传名称=新建。 */
export function goEditor(tunnelName?: string): void {
  const param = new EditorParam();
  if (tunnelName !== undefined) {
    param.name = tunnelName;
  }
  pathStack.pushPathByName(ROUTE_EDITOR, param);
}

/** 打开设置页。 */
export function goSettings(): void {
  pathStack.pushPathByName(ROUTE_SETTINGS, '');
}

/** 打开日志页。 */
export function goLog(): void {
  pathStack.pushPathByName(ROUTE_LOG, '');
}

/** 打开扫码页（如使用系统默认扫码 UI 则可不经此页）。 */
export function goScan(): void {
  pathStack.pushPathByName(ROUTE_SCAN, '');
}

/** 用详情页替换当前栈顶（编辑器保存后返回详情页用）。 */
export function replaceWithDetail(tunnelName: string): void {
  pathStack.replacePathByName(ROUTE_DETAIL, tunnelName);
}

/** 返回上一页。 */
export function goBack(): void {
  pathStack.pop();
}

/** 从编辑器的 param 中取出隧道名（空串/无 name 表示新建）。 */
export function editorParamName(param: object): string | null {
  const editorParam = param as EditorParam;
  if (editorParam !== undefined && editorParam.name !== undefined && editorParam.name.length > 0) {
    return editorParam.name;
  }
  return null;
}
