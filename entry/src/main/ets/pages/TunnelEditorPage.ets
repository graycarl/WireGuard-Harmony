/*
 * 隧道编辑器页（specs/tunnel-editor.md）。
 *
 * 路由契约（docs/dev-contracts.md §11）：路由名 `editor`，param = { name?: string }，
 * 无 name 表示新建。页面自带标题栏（返回 / 标题 / 保存），宿主 NavDestination 应隐藏标题栏。
 *
 * 分层：纯逻辑在 components/EditorUtils.ets（可本地单测）；可观察 Peer 表单在
 * components/EditorPeerForm.ets；本文件只做 UI 装配与交互编排。
 */

import { common } from '@kit.AbilityKit';
import { AppStore } from '../store/AppStore';
import { AuthGuard, AuthResult, AuthResultKind } from '../backend/AuthGuard';
import { PrivacyMode } from '../backend/PrivacyMode';
import { AppCatalog, AppOption } from '../components/AppCatalog';
import { AppFilterDialog } from '../components/AppFilterDialog';
import { EditorPeerForm } from '../components/EditorPeerForm';
import {
  InterfaceDraft,
  PeerDraft,
  draftToConfig,
  filterBase64KeyInput,
  filterDigitsInput,
  filterTunnelNameInput,
  formSignature,
  interfaceToDraft,
  parseDnsServerText,
  splitListText
} from '../components/EditorUtils';
import { Config } from '../config/Config';
import { Interface } from '../config/Interface';
import { Peer } from '../config/Peer';
import {
  collapseExcludeLan,
  expandExcludeLan,
  isExcludeLanApplicable,
  syncLanDnsRoutes
} from '../config/PrivateNetworks';
import { Key } from '../crypto/Key';
import { KeyPair } from '../crypto/KeyPair';
import { Logger } from '../util/Logger';
import { Toast } from '../util/Toast';
import { Clipboard } from '../util/Clipboard';
import { editorParamName, goBack, replaceWithDetail } from './RouteStack';

const LABEL_WIDTH: number = 92;
const FIELD_LABEL_SIZE: number = 15;

@ComponentV2
export struct TunnelEditorPage {
  @Param param: object = new Object();

  /** 原隧道名；null 表示新建。 */
  @Local originalName: string | null = null;
  @Local tunnelName: string = '';
  @Local privateKey: string = '';
  /** 由私钥实时派生的公钥（空 = 未生成/非法）。 */
  @Local publicKey: string = '';
  @Local addressesText: string = '';
  @Local listenPortText: string = '';
  @Local dnsText: string = '';
  @Local mtuText: string = '';
  /** 'none' | 'excluded' | 'included' */
  @Local filterMode: string = 'none';
  @Local filterApps: string[] = [];
  @Local peers: EditorPeerForm[] = [];
  /** Peer 结构版本：增删时自增，用于强制重建 Peer 卡片（避免 ForEach 复用导致下标错位）。 */
  @Local peerEpoch: number = 0;
  /** 本次会话密钥是否已解锁（明文显示）。 */
  @Local keysRevealed: boolean = false;
  @Local showAppFilter: boolean = false;
  @Local appOptions: AppOption[] = [];
  /** DNS 服务器缓存（用于同步「排除局域网」自动补入的 /32 路由）。 */
  @Local dnsServersCache: string[] = [];
  @Local busy: boolean = false;

  private originalSignature: string = '';

  aboutToAppear(): void {
    const name = editorParamName(this.param);
    if (name !== null) {
      const config = AppStore.get().configOf(name);
      if (config !== null) {
        this.originalName = name;
        this.applyConfig(name, config.interface, config.peers);
      }
    }
    this.originalSignature = formSignature(this.interfaceDraft(), this.peerDrafts());
  }

  aboutToDisappear(): void {
    PrivacyMode.setEnabled(this.context(), false);
  }

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private applyConfig(name: string, iface: Interface, peers: Peer[]): void {
    const ifaceDraft = interfaceToDraft(iface);
    this.tunnelName = name;
    this.privateKey = ifaceDraft.privateKey;
    this.addressesText = ifaceDraft.addressesText;
    this.listenPortText = ifaceDraft.listenPortText;
    this.dnsText = ifaceDraft.dnsText;
    this.mtuText = ifaceDraft.mtuText;
    this.filterMode = ifaceDraft.filterMode;
    this.filterApps = ifaceDraft.filterApps;
    this.dnsServersCache = parseDnsServerText(ifaceDraft.dnsText);
    const forms: EditorPeerForm[] = [];
    for (const peer of peers) {
      forms.push(EditorPeerForm.fromPeer(peer));
    }
    this.peers = forms;
    this.updatePublicKey();
  }

  // ---------------------------------------------------------------- 表单装配

  private interfaceDraft(): InterfaceDraft {
    const draft: InterfaceDraft = {
      privateKey: this.privateKey,
      addressesText: this.addressesText,
      listenPortText: this.listenPortText,
      dnsText: this.dnsText,
      mtuText: this.mtuText,
      filterMode: this.filterMode,
      filterApps: this.filterApps
    };
    return draft;
  }

  private peerDrafts(): PeerDraft[] {
    const drafts: PeerDraft[] = [];
    for (const form of this.peers) {
      drafts.push(form.toDraft());
    }
    return drafts;
  }

  private updatePublicKey(): void {
    this.publicKey = '';
    if (this.privateKey.length !== 44) {
      return;
    }
    try {
      const keyPair = new KeyPair(Key.fromBase64(this.privateKey));
      this.publicKey = keyPair.publicKey.toBase64();
    } catch (e) {
      // 诊断：派生失败不应静默（真机排查用；不含密钥材料）
      const error = e as Error;
      Logger.error('TunnelEditor', `公钥派生失败: ${error.message}`);
      this.publicKey = '';
    }
  }

  // ---------------------------------------------------------------- 私钥保护

  private maskKeys(): void {
    this.keysRevealed = false;
  }

  private async requestKeyReveal(value: string): Promise<void> {
    if (this.keysRevealed || value.length === 0) {
      return;
    }
    const result: AuthResult = await AuthGuard.authenticate('查看私钥前需要通过认证');
    if (result.kind === AuthResultKind.SUCCESS) {
      this.keysRevealed = true;
      await PrivacyMode.setEnabled(this.context(), true);
    } else if (result.kind === AuthResultKind.FAILED || result.kind === AuthResultKind.ERROR) {
      Toast.show(result.message);
    }
  }

  private generatePrivateKey(): void {
    try {
      this.privateKey = Key.generate().toBase64();
      this.updatePublicKey();
    } catch (e) {
      Toast.show(`生成密钥失败：${(e as Error).message}`);
    }
  }

  // ---------------------------------------------------------------- 应用过滤

  private filterButtonLabel(): string {
    if (this.filterApps.length === 0) {
      return '应用过滤';
    }
    return this.filterMode === 'included'
      ? `对 ${this.filterApps.length} 个应用生效`
      : `对 ${this.filterApps.length} 个应用不生效`;
  }

  private async openAppFilter(): Promise<void> {
    const result = await AppCatalog.listNetworkApps();
    if (result.error.length > 0) {
      Toast.show(`获取应用列表时出错：${result.error}`);
      return;
    }
    this.appOptions = result.apps;
    this.showAppFilter = true;
  }

  @Builder
  AppFilterSheet() {
    AppFilterDialog({
      initialMode: this.filterMode === 'included' ? 'included' : 'excluded',
      initialSelected: this.filterApps,
      apps: this.appOptions,
      onConfirm: (mode: string, selected: string[]): void => {
        if (selected.length === 0) {
          this.filterMode = 'none';
          this.filterApps = [];
        } else {
          this.filterMode = mode;
          this.filterApps = selected;
        }
        this.showAppFilter = false;
      },
      onCancel: (): void => {
        this.showAppFilter = false;
      }
    })
  }

  // ---------------------------------------------------------------- Peer 操作

  private addPeer(): void {
    const next = this.peers.slice();
    next.push(EditorPeerForm.empty());
    this.peers = next;
    this.peerEpoch++;
  }

  private removePeer(index: number): void {
    const next: EditorPeerForm[] = [];
    for (let i = 0; i < this.peers.length; i++) {
      if (i !== index) {
        next.push(this.peers[i]);
      }
    }
    this.peers = next;
    this.peerEpoch++;
  }

  /** 「排除局域网」勾选/取消。 */
  private setExcludeLan(index: number, enabled: boolean): void {
    const peer = this.peers[index];
    const dnsServers = parseDnsServerText(this.dnsText);
    const current = splitListText(peer.allowedIPsText);
    const next = enabled ? expandExcludeLan(current, dnsServers) : collapseExcludeLan(current, dnsServers);
    peer.excludeLan = enabled;
    peer.allowedIPsText = next.join(', ');
  }

  /** DNS 变化时同步自动补入的 /32 路由（specs/tunnel-editor.md）。 */
  private onDnsChanged(value: string): void {
    this.dnsText = value;
    const newServers = parseDnsServerText(value);
    const oldServers = this.dnsServersCache;
    this.dnsServersCache = newServers;
    if (this.peers.length === 0) {
      return;
    }
    for (const peer of this.peers) {
      if (peer.excludeLan) {
        const synced = syncLanDnsRoutes(splitListText(peer.allowedIPsText), oldServers, newServers);
        peer.allowedIPsText = synced.join(', ');
      }
    }
  }

  /** 路由段被手工修改后，若不再满足「排除局域网」显示条件则复位复选框。 */
  private onAllowedIPsChanged(index: number, value: string): void {
    const peer = this.peers[index];
    peer.allowedIPsText = value;
    if (peer.excludeLan && !isExcludeLanApplicable(splitListText(value), this.peers.length)) {
      peer.excludeLan = false;
    }
  }

  // ---------------------------------------------------------------- 保存 / 返回

  private isDirty(): boolean {
    return formSignature(this.interfaceDraft(), this.peerDrafts()) !== this.originalSignature;
  }

  private onBack(): void {
    if (!this.isDirty()) {
      goBack();
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '放弃更改？',
      message: '未保存的更改将丢失。',
      primaryButton: {
        value: '放弃',
        action: (): void => {
          goBack();
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {
        }
      }
    });
  }

  private async onSave(): Promise<void> {
    if (this.busy) {
      return;
    }
    let config: Config;
    try {
      config = draftToConfig(this.interfaceDraft(), this.peerDrafts());
    } catch (e) {
      Toast.show((e as Error).message);
      return;
    }
    const creating = this.originalName === null;
    this.busy = true;
    try {
      const store = AppStore.get();
      let result: string | null;
      if (creating) {
        result = await store.create(this.tunnelName, config);
      } else {
        result = await store.save(this.originalName as string, this.tunnelName, config);
      }
      if (result !== null) {
        Toast.show(result);
        return;
      }
      Toast.show(creating ? `成功创建隧道 '${this.tunnelName}'` : `已保存 '${this.tunnelName}' 的配置`);
      replaceWithDetail(this.tunnelName);
    } finally {
      this.busy = false;
    }
  }

  // ---------------------------------------------------------------- 界面

  @Builder
  Header() {
    Row() {
      Text('返回')
        .fontSize(16)
        .fontColor($r('app.color.accent'))
        .onClick(() => {
          this.onBack();
        })
      Text(this.originalName === null ? '创建 WireGuard 隧道' : `编辑 ${this.tunnelName}`)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button(this.busy ? '保存中' : '保存')
        .fontSize(16)
        .fontColor($r('app.color.accent'))
        .backgroundColor(Color.Transparent)
        .enabled(!this.busy)
        .onClick(() => {
          this.onSave();
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  CardTitle(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .padding({ bottom: 8 })
  }

  @Builder
  InterfaceCard() {
    Column() {
      this.CardTitle('本地（Interface）')

      // 名称
      Row() {
        Text('名称')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        TextInput({ text: this.tunnelName, placeholder: '仅字母/数字/._=+-，最长 15' })
          .layoutWeight(1)
          .maxLength(15)
          .onChange((value: string) => {
            this.tunnelName = filterTunnelNameInput(value);
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // 私钥 + 生成
      Row() {
        Text('私钥')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        TextInput({ text: this.privateKey, placeholder: '44 字符 Base64 密钥' })
          .layoutWeight(1)
          .maxLength(44)
          .type(this.keysRevealed ? InputType.Normal : InputType.Password)
          .onChange((value: string) => {
            this.privateKey = filterBase64KeyInput(value);
            this.updatePublicKey();
          })
          .onClick(() => {
            this.requestKeyReveal(this.privateKey);
          })
        Button('生成')
          .fontSize(14)
          .margin({ left: 8 })
          .onClick(() => {
            this.generatePrivateKey();
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // 公钥（只读派生 + 点击复制）
      Row() {
        Text('公钥')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        Text(this.publicKey.length > 0 ? this.publicKey : '（生成）')
          .fontSize(14)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => {
            if (this.publicKey.length > 0) {
              Clipboard.copyField('公钥', this.publicKey);
            }
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // 局域网 IP 地址
      Row() {
        Text('局域网 IP 地址')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        TextInput({ text: this.addressesText, placeholder: '10.0.0.2/32, fc00::2/128' })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.addressesText = value;
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // 监听端口
      Row() {
        Text('监听端口')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        TextInput({ text: this.listenPortText, placeholder: '（随机）' })
          .layoutWeight(1)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.listenPortText = filterDigitsInput(value, 5);
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // DNS 服务器
      Row() {
        Text('DNS 服务器')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        TextInput({ text: this.dnsText, placeholder: '1.1.1.1, example.com' })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.onDnsChanged(value);
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // MTU
      Row() {
        Text('MTU')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        TextInput({ text: this.mtuText, placeholder: '（自动）' })
          .layoutWeight(1)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.mtuText = filterDigitsInput(value, 6);
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // 应用过滤
      Row() {
        Text('应用过滤')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        Button(this.filterButtonLabel())
          .layoutWeight(1)
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.chip_selected_bg'))
          .onClick(() => {
            this.openAppFilter();
          })
          .bindSheet(this.showAppFilter, this.AppFilterSheet(), {
            height: SheetSize.LARGE,
            dragBar: true,
            title: { title: '应用过滤' },
            onDisappear: (): void => {
              this.showAppFilter = false;
            }
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  @Builder
  PeerCard(index: number) {
    Column() {
      Row() {
        Text(`远程（Peer）${index + 1}`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Button('删除')
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.removePeer(index);
          })
      }
      .width('100%')

      // 公钥
      Row() {
        Text('公钥')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        // 对端公钥不是敏感信息：specs/tunnel-editor.md 只要求预共享密钥/本机私钥遮蔽。
        TextInput({ text: this.peers[index].publicKey, placeholder: '44 字符 Base64 密钥' })
          .layoutWeight(1)
          .maxLength(44)
          .type(InputType.Normal)
          .onChange((value: string) => {
            this.peers[index].publicKey = filterBase64KeyInput(value);
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // 预共享密钥
      Row() {
        Text('预共享密钥')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        TextInput({ text: this.peers[index].presharedKey, placeholder: '（可选）' })
          .layoutWeight(1)
          .maxLength(44)
          .type(this.keysRevealed ? InputType.Normal : InputType.Password)
          .onChange((value: string) => {
            this.peers[index].presharedKey = filterBase64KeyInput(value);
          })
          .onClick(() => {
            this.requestKeyReveal(this.peers[index].presharedKey);
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // 连接保活间隔
      Row() {
        Text('连接保活间隔')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        TextInput({ text: this.peers[index].keepaliveText, placeholder: '（可选，不建议设置）' })
          .layoutWeight(1)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.peers[index].keepaliveText = filterDigitsInput(value, 5);
          })
        Text('秒')
          .fontSize(FIELD_LABEL_SIZE)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // 对端
      Row() {
        Text('对端')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        TextInput({ text: this.peers[index].endpointText, placeholder: 'vpn.example.com:51820' })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.peers[index].endpointText = value;
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // 路由的 IP 地址（段）
      Row() {
        Text('路由的 IP 地址（段）')
          .fontSize(FIELD_LABEL_SIZE)
          .width(LABEL_WIDTH)
        TextInput({ text: this.peers[index].allowedIPsText, placeholder: '0.0.0.0/0, ::/0' })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.onAllowedIPsChanged(index, value);
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      // 排除局域网（条件显示）
      if (isExcludeLanApplicable(splitListText(this.peers[index].allowedIPsText), this.peers.length)) {
        Row() {
          Text('排除局域网')
            .fontSize(FIELD_LABEL_SIZE)
            .layoutWeight(1)
          Checkbox()
            .select(this.peers[index].excludeLan)
            .onChange((checked: boolean) => {
              this.setExcludeLan(index, checked);
            })
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 12 }) {
          this.InterfaceCard()
          ForEach(this.peers, (peer: EditorPeerForm, index: number) => {
            this.PeerCard(index)
          }, (peer: EditorPeerForm) => `${peer.id}#${this.peerEpoch}`)
          Button('添加节点')
            .width('100%')
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.chip_selected_bg'))
            .onClick(() => {
              this.addPeer();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .onVisibleAreaChange([0.0], (isVisible: boolean) => {
      if (!isVisible) {
        this.maskKeys();
      }
    })
  }
}
