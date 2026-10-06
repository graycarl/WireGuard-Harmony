/*
 * 列表多选状态（@ObservedV2 可观察单例）。
 *
 * 背景（AGENTS.md 已知坑 / ArkUI ForEach 语义）：ForEach 对键值未变的子组件不会
 * 重新下发 @Param，因此「多选态」不能靠父组件透传；改为放进可观察单例，
 * 行组件与页面直接读取 @Trace 属性，框架按属性级依赖精准刷新。
 */

@ObservedV2
export class ListSelection {
  @Trace active: boolean = false;
  @Trace selected: string[] = [];

  count(): number {
    return this.selected.length;
  }

  has(name: string): boolean {
    return this.selected.includes(name);
  }

  names(): string[] {
    return this.selected.slice();
  }

  /** 长按进入多选并只选中该项。 */
  selectOnly(name: string): void {
    this.active = true;
    this.selected = [name];
  }

  /** 点击行切换选中；全部取消后自动退出多选。 */
  toggle(name: string): void {
    if (this.selected.includes(name)) {
      this.selected = this.selected.filter((item: string): boolean => item !== name);
    } else {
      this.selected = this.selected.concat([name]);
    }
    if (this.selected.length === 0) {
      this.active = false;
    }
  }

  /** 「全选」：始终选中全部。 */
  selectAll(names: string[]): void {
    this.active = names.length > 0;
    this.selected = names.slice();
  }

  /** 退出多选并清空选择。 */
  clear(): void {
    this.active = false;
    this.selected = [];
  }

  /** 剔除已不存在的隧道（删除/外部变更后调用）。 */
  retain(names: string[]): void {
    const kept: string[] = [];
    for (const name of this.selected) {
      if (names.includes(name)) {
        kept.push(name);
      }
    }
    if (kept.length !== this.selected.length) {
      this.selected = kept;
      if (kept.length === 0) {
        this.active = false;
      }
    }
  }
}

/** 进程内单例（列表页与其行组件共用）。 */
export const listSelection: ListSelection = new ListSelection();
