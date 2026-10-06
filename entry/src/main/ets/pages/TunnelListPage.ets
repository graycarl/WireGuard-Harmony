/*
 * 隧道列表（首页内容，specs/tunnel-list.md）。
 *
 * 结构：
 * - 标题栏：应用名 + 设置入口；多选模式下替换为「已选择 N 个隧道」+ 全选/删除；
 * - 中部：隧道列表（自然排序，由 AppStore.records() 保证）；
 * - 右下角：圆形「+」浮动按钮（半模态面板：导入配置或压缩包 / 扫描二维码 / 手动创建）。
 *
 * 多选态放在可观察单例 listSelection（行组件直接读取），避免 ForEach 复用导致
 * 子组件 @Param 不刷新的问题；本页只维护「列表结构」（records）。
 */

import { AppStore } from '../store/AppStore';
import { TunnelRecord } from '../repo/TunnelRecord';
import { TunnelListItem } from '../components/TunnelListItem';
import { listSelection } from '../components/ListSelection';
import { ImportService } from '../services/ImportService';
import { Toast } from '../util/Toast';
import { goDetail, goEditor, goSettings, pathStack } from './RouteStack';

/**
 * 返回键处理注册表：列表是 Navigation 的首页内容（非 NavDestination），
 * 系统返回键由 @Entry 的 onBackPress 捕获后转交本类（多选模式退出）。
 */
export class ListBackHandler {
  private static handler: (() => boolean) | null = null;

  static register(handler: () => boolean): void {
    ListBackHandler.handler = handler;
  }

  static unregister(): void {
    ListBackHandler.handler = null;
  }

  static handleBack(): boolean {
    const handler = ListBackHandler.handler;
    if (handler === null) {
      return false;
    }
    return handler();
  }
}

@ComponentV2
export struct TunnelListPage {
  @Local records: TunnelRecord[] = [];
  @Local showAddSheet: boolean = false;
  @Local scanAvailable: boolean = false;
  private storeListener: () => void = () => {};

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      AppStore.get().init(context);
      ImportService.refreshScanAvailability(context).then(() => {
        this.scanAvailable = ImportService.scanAvailable();
      });
    }
    this.scanAvailable = ImportService.scanAvailable();
    this.storeListener = () => {
      this.refresh();
    };
    AppStore.get().addListener(this.storeListener);
    ListBackHandler.register(() => {
      // 若栈顶还有 NavDestination（详情/编辑器等），返回键交给 Navigation 处理；
      // 只有停在首页内容时才负责退出多选模式。
      if (pathStack.size() > 0) {
        return false;
      }
      return this.handleBack();
    });
    this.refresh();
  }

  aboutToDisappear(): void {
    AppStore.get().removeListener(this.storeListener);
    ListBackHandler.unregister();
  }

  /** 重新读取隧道集合（AppStore 变化时调用）。 */
  private refresh(): void {
    const records = AppStore.get().records();
    if (this.namesChanged(records)) {
      this.records = records;
    }
    const names: string[] = [];
    for (const record of records) {
      names.push(record.name);
    }
    listSelection.retain(names);
  }

  /** 隧道集合的名称序列是否变化（避免每秒统计事件触发无意义的列表重建）。 */
  private namesChanged(records: TunnelRecord[]): boolean {
    if (records.length !== this.records.length) {
      return true;
    }
    for (let i = 0; i < records.length; i++) {
      if (records[i].name !== this.records[i].name) {
        return true;
      }
    }
    return false;
  }

  private handleBack(): boolean {
    if (listSelection.active) {
      listSelection.clear();
      return true;
    }
    return false;
  }

  private selectAll(): void {
    const names: string[] = [];
    for (const record of this.records) {
      names.push(record.name);
    }
    listSelection.selectAll(names);
  }

  private async deleteSelected(): Promise<void> {
    const names = listSelection.names();
    if (names.length === 0) {
      return;
    }
    const message = await AppStore.get().remove(names);
    listSelection.clear();
    this.refresh();
    if (message === null) {
      Toast.show(`成功删除了 ${names.length} 项`);
    } else {
      Toast.show(message);
    }
  }

  private async importFromFile(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const message = await ImportService.pickAndImport(context);
    this.refresh();
    if (message !== null) {
      Toast.show(message);
    }
  }

  private async importFromScan(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const message = await ImportService.scanAndImport(context);
    this.refresh();
    if (message !== null) {
      Toast.show(message);
    }
  }

  @Builder
  TitleBar() {
    Row() {
      Text('WireGuard')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
      Button('设置')
        .fontSize(16)
        .fontColor('#0a59f7')
        .backgroundColor(Color.Transparent)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          goSettings();
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 4 })
  }

  @Builder
  SelectionBar() {
    Row({ space: 8 }) {
      Text(`已选择 ${listSelection.count()} 个隧道`)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
      Button('全选')
        .fontSize(16)
        .fontColor('#0a59f7')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.selectAll();
        })
      Button('删除')
        .fontSize(16)
        .fontColor('#e84026')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.deleteSelected();
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 4 })
  }

  @Builder
  AddSheet() {
    Column({ space: 0 }) {
      Text('添加隧道')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 8, bottom: 12 })
      Row() {
        Text('导入配置或压缩包').fontSize(17)
      }
      .width('100%')
      .height(56)
      .onClick(() => {
        this.showAddSheet = false;
        this.importFromFile();
      })
      if (this.scanAvailable) {
        Row() {
          Text('扫描二维码').fontSize(17)
        }
        .width('100%')
        .height(56)
        .onClick(() => {
          this.showAddSheet = false;
          this.importFromScan();
        })
      }
      Row() {
        Text('手动创建').fontSize(17)
      }
      .width('100%')
      .height(56)
      .onClick(() => {
        this.showAddSheet = false;
        goEditor();
      })
    }
    .width('100%')
    .padding({ left: 24, right: 24, bottom: 16 })
  }

  @Builder
  EmptyState() {
    Column() {
      Text('点击下方按钮添加隧道')
        .fontSize(15)
        .fontColor('#99000000')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  AddButton() {
    Button('+')
      .width(56)
      .height(56)
      .borderRadius(28)
      .fontSize(28)
      .fontColor(Color.White)
      .backgroundColor('#0a59f7')
      .margin({ right: 24, bottom: 24 })
      .onClick(() => {
        this.showAddSheet = true;
      })
  }

  build() {
    Column() {
      if (listSelection.active) {
        this.SelectionBar()
      } else {
        this.TitleBar()
      }
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.records.length === 0) {
          this.EmptyState()
        } else {
          List() {
            ForEach(this.records, (record: TunnelRecord) => {
              ListItem() {
                TunnelListItem({
                  name: record.name,
                  onOpen: (name: string) => {
                    goDetail(name);
                  }
                })
              }
            }, (record: TunnelRecord) => record.name)
          }
          .width('100%')
          .height('100%')
          .contentEndOffset(88)
          .divider({ strokeWidth: 1, color: '#1A000000', startMargin: 16, endMargin: 16 })
        }
        if (!listSelection.active) {
          this.AddButton()
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
      // 从详情/编辑器/设置页返回时刷新开关状态（spec tunnel-connection.md §状态一致性）
      if (isVisible) {
        this.refresh();
      }
    })
    .bindSheet(this.showAddSheet, this.AddSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: false,
      onDisappear: () => {
        this.showAddSheet = false;
      }
    })
  }
}
