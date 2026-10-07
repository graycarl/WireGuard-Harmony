/*
 * 应用过滤的可选应用清单（specs/tunnel-editor.md「应用过滤对话框」）。
 *
 * 平台事实（已核实）：普通应用无法枚举已安装应用——bundleManager 的批量查询接口
 * （getAllBundleInfo 等）在本 SDK 中不存在，getBundleInfo/getLauncherAbilityInfo
 * 需要 ohos.permission.GET_BUNDLE_INFO_PRIVILEGED（system_basic），普通应用拿不到。
 * 因此这里返回空清单，对话框按 spec 定案显示空态「未找到可用应用」；
 * 若后续平台开放能力，只需在本类内实现枚举，对话框与编辑器无需改动。
 */

/** 可选应用（应用过滤对话框列表项）。 */
export interface AppOption {
  bundleName: string;
  label: string;
  icon?: Resource;
}

/** 清单查询结果。 */
export interface AppCatalogResult {
  apps: AppOption[];
  /** 非空表示「枚举失败」（对话框应提示并关闭）；空串表示正常（可能为空清单）。 */
  error: string;
}

export class AppCatalog {
  /** 查询可参与应用过滤的应用（图标 + 名称，按名称排序）。 */
  static async listNetworkApps(): Promise<AppCatalogResult> {
    const result: AppCatalogResult = { apps: [], error: '' };
    return result;
  }
}
