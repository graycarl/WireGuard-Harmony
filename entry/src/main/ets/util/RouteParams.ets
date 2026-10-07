/*
 * 路由参数提取工具（纯逻辑，可本地单测）。
 *
 * Navigation 的 NavDestination 参数类型是宽泛的 Object：
 * - 详情页：param = 隧道名字符串（见 pages/RouteStack.goDetail）
 * - 编辑器：param = { name?: string }（无 name 表示新建）
 * 本模块集中处理形态差异，避免各页面自行强转出错。
 */

/** 兼容的 param 形态：字符串 | 对象 | 空。 */
export type RouteParam = string | object | undefined | null;

/** 从详情页 param 中取出隧道名（兼容字符串与 { name } 对象两种形态）。 */
export function paramAsTunnelName(param: RouteParam): string {
  if (param === undefined || param === null) {
    return '';
  }
  if (typeof param === 'string') {
    return param;
  }
  const record = param as Record<string, Object>;
  const name = record['name'];
  if (typeof name === 'string') {
    return name;
  }
  return '';
}
