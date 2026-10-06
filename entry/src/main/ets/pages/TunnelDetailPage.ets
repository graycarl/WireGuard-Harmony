/*
 * 隧道详情页（specs/tunnel-detail.md）。
 *
 * - 只读展示配置（空值字段整行隐藏），预共享密钥只显示「已启用」且不可复制；
 * - 每张远程卡片自订阅统计刷新（流量 / 上次握手时间）；
 * - 任意字段值点击复制并提示；
 * - 右上「编辑」进入编辑器；隧道被删除后自动关闭本页。
 */

import { AppStore } from '../store/AppStore';
import { Config } from '../config/Config';
import { Peer } from '../config/Peer';
import { Key } from '../crypto/Key';
import { KeyPair } from '../crypto/KeyPair';
import { TunnelSwitch } from '../components/TunnelSwitch';
import { PeerCard } from '../components/PeerCard';
import { Clipboard } from '../util/Clipboard';
import { appFilterText, joinNetworks, joinTexts, mtuText, portText } from '../util/TunnelDisplay';
import { goBack, goEditor, pathStack, ROUTE_DETAIL } from './RouteStack';

@ComponentV2
export struct TunnelDetailPage {
  @Param tunnelName: string = '';
  @Local config: Config | null = null;
  @Local publicKey: string = '';
  private storeListener: () => void = () => {};

  aboutToAppear(): void {
    this.storeListener = () => {
      this.checkExists();
    };
    AppStore.get().addListener(this.storeListener);
    this.loadConfig();
    this.checkExists();
  }

  aboutToDisappear(): void {
    AppStore.get().removeListener(this.storeListener);
  }

  private loadConfig(): void {
    const config = AppStore.get().configOf(this.tunnelName);
    this.config = config;
    if (config === null) {
      this.publicKey = '';
      return;
    }
    this.publicKey = TunnelDetailPage.derivePublicKey(config.interface.privateKey);
  }

  /** 由私钥派生公钥（设备侧 X25519；失败则不显示）。 */
  private static derivePublicKey(privateKey: string): string {
    if (privateKey.length === 0) {
      return '';
    }
    try {
      return new KeyPair(Key.fromBase64(privateKey)).publicKey.toBase64();
    } catch (e) {
      return '';
    }
  }

  /** 隧道是否仍存在于存储（被删除后自动关闭本页）。 */
  private existsInStore(): boolean {
    for (const record of AppStore.get().records()) {
      if (record.name === this.tunnelName) {
        return true;
      }
    }
    return false;
  }

  private checkExists(): void {
    if (!this.existsInStore()) {
      this.closeIfTop();
    }
  }

  /** 仅当本页位于路由栈顶时关闭（避免误弹掉上层编辑器）。 */
  private closeIfTop(): void {
    const names = pathStack.getAllPathName();
    if (names.length > 0 && names[names.length - 1] === ROUTE_DETAIL) {
      pathStack.pop();
    }
  }

  // ---- 展示取值（空串表示隐藏该行） ----

  private addressesText(): string {
    const config = this.config;
    return config === null ? '' : joinNetworks(config.interface.addresses);
  }

  private dnsText(): string {
    const config = this.config;
    return config === null ? '' : joinTexts(config.interface.dnsServers);
  }

  private searchDomainsText(): string {
    const config = this.config;
    return config === null ? '' : joinTexts(config.interface.dnsSearchDomains);
  }

  private portValue(): string {
    const config = this.config;
    return config === null ? '' : portText(config.interface.listenPort);
  }

  private mtuValue(): string {
    const config = this.config;
    return config === null ? '' : mtuText(config.interface.mtu);
  }

  private appFilterValue(): string {
    const config = this.config;
    return config === null ? '' : appFilterText(config.interface);
  }

  private peersOfConfig(): Peer[] {
    const config = this.config;
    return config === null ? [] : config.peers;
  }

  @Builder
  Header() {
    Row() {
      Button() {
        Image($r('sys.media.ohos_ic_public_arrow_left'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
      }
      .backgroundColor(Color.Transparent)
      .width(48)
      .height(48)
      .onClick(() => {
        goBack();
      })
      Text(this.tunnelName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Button('编辑')
        .fontSize(16)
        .fontColor($r('app.color.accent'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          goEditor(this.tunnelName);
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4 })
  }

  /** 可复制字段行（点击复制并提示「<字段名> 已复制到剪贴板」）。 */
  @Builder
  Field(label: string, value: string, singleLine: boolean) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width(120)
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(singleLine ? 1 : 3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      Clipboard.copyField(label, value);
    })
  }

  @Builder
  InterfaceCard() {
    Column() {
      Row() {
        Text('本地')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        TunnelSwitch({ name: this.tunnelName })
      }
      .width('100%')
      .padding({ top: 2, bottom: 2 })
      this.Field('名称', this.tunnelName, false)
      if (this.publicKey.length > 0) {
        this.Field('公钥', this.publicKey, true)
      }
      if (this.addressesText().length > 0) {
        this.Field('局域网 IP 地址', this.addressesText(), false)
      }
      if (this.dnsText().length > 0) {
        this.Field('DNS 服务器', this.dnsText(), false)
      }
      if (this.searchDomainsText().length > 0) {
        this.Field('搜索域名', this.searchDomainsText(), false)
      }
      if (this.portValue().length > 0) {
        this.Field('监听端口', this.portValue(), false)
      }
      if (this.mtuValue().length > 0) {
        this.Field('MTU', this.mtuValue(), false)
      }
      if (this.appFilterValue().length > 0) {
        this.Field('应用过滤', this.appFilterValue(), false)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_bg'))
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 12 }) {
          this.InterfaceCard()
          ForEach(this.peersOfConfig(), (peer: Peer) => {
            PeerCard({ tunnelName: this.tunnelName, peer: peer })
          }, (peer: Peer, index: number) => `${peer.publicKey}-${index}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
      if (isVisible) {
        // 从编辑器返回或重新显示时刷新配置与存在性
        this.loadConfig();
        this.checkExists();
      }
    })
  }
}
