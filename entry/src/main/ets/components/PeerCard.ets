/*
 * 远程（Peer）卡片（specs/tunnel-detail.md）。
 *
 * 自订阅 AppStore 刷新「流量」「上次握手时间」（不依赖父组件的 ForEach 重下发），
 * 其余字段为静态配置。预共享密钥只显示「已启用」且不可复制。
 */

import { AppStore } from '../store/AppStore';
import { Peer } from '../config/Peer';
import { Clipboard } from '../util/Clipboard';
import { endpointText, findStats, handshakeText, joinNetworks, keepaliveText, pskText,
  trafficText } from '../util/TunnelDisplay';

@ComponentV2
export struct PeerCard {
  @Param tunnelName: string = '';
  @Param peer: Peer = new Peer();
  @Local traffic: string = '';
  @Local handshake: string = '';
  private storeListener: () => void = () => {};

  aboutToAppear(): void {
    this.storeListener = () => {
      this.refreshStats();
    };
    AppStore.get().addListener(this.storeListener);
    this.refreshStats();
  }

  aboutToDisappear(): void {
    AppStore.get().removeListener(this.storeListener);
  }

  private refreshStats(): void {
    const stats = findStats(AppStore.get().snapshot(this.tunnelName).peers, this.peer.publicKey);
    const traffic = trafficText(stats);
    const handshake = handshakeText(stats, Date.now());
    if (traffic !== this.traffic) {
      this.traffic = traffic;
    }
    if (handshake !== this.handshake) {
      this.handshake = handshake;
    }
  }

  private allowedIPsText(): string {
    return joinNetworks(this.peer.allowedIPs);
  }

  @Builder
  Field(label: string, value: string, singleLine: boolean) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#99000000')
        .width(120)
      Text(value)
        .fontSize(15)
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
  PlainField(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#99000000')
        .width(120)
      Text(value)
        .fontSize(15)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  build() {
    Column() {
      Text('远程')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ top: 12, bottom: 4 })
      if (this.peer.publicKey.length > 0) {
        this.Field('公钥', this.peer.publicKey, true)
      }
      if (pskText(this.peer.presharedKey).length > 0) {
        this.PlainField('预共享密钥', pskText(this.peer.presharedKey))
      }
      if (this.allowedIPsText().length > 0) {
        this.Field('路由的 IP 地址（段）', this.allowedIPsText(), false)
      }
      if (endpointText(this.peer).length > 0) {
        this.Field('对端', endpointText(this.peer), false)
      }
      if (keepaliveText(this.peer.persistentKeepalive).length > 0) {
        this.Field('连接保活间隔', keepaliveText(this.peer.persistentKeepalive), false)
      }
      if (this.traffic.length > 0) {
        this.Field('流量', this.traffic, false)
      }
      if (this.handshake.length > 0) {
        this.Field('上次握手时间', this.handshake, false)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor('#F1F3F5')
  }
}
