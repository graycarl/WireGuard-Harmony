import { describe, it, expect } from '@ohos/hypium';
import {
  appFilterText, endpointText, handshakeText, joinNetworks, joinTexts,
  keepaliveText, mtuText, pskText, portText, trafficText, findStats
} from '../main/ets/util/TunnelDisplay';
import { Interface } from '../main/ets/config/Interface';
import { Peer } from '../main/ets/config/Peer';
import { InetNetwork } from '../main/ets/config/InetNetwork';
import { PeerStats } from '../main/ets/model/PeerStats';
import { paramAsTunnelName } from '../main/ets/util/RouteParams';

const NOW = 1700000000000;

function network(text: string): InetNetwork {
  return InetNetwork.parse(text);
}

function stats(rx: number, tx: number, handshakeMs: number): PeerStats {
  const value: PeerStats = {
    publicKey: 'k1',
    rxBytes: rx,
    txBytes: tx,
    lastHandshakeMs: handshakeMs,
    endpoint: ''
  };
  return value;
}

export default function tunnelDisplayTest() {
  describe('TunnelDisplay', () => {
    it('joinNetworks / joinTexts 空与非空', 0, () => {
      expect(joinNetworks([])).assertEqual('');
      expect(joinNetworks([network('10.0.0.2/32'), network('fc00::2/128')]))
        .assertEqual('10.0.0.2/32, fc00::2/128');
      expect(joinTexts([])).assertEqual('');
      expect(joinTexts(['1.1.1.1', '8.8.8.8'])).assertEqual('1.1.1.1, 8.8.8.8');
    });

    it('appFilterText 三种形态', 0, () => {
      const empty = new Interface();
      expect(appFilterText(null)).assertEqual('');
      expect(appFilterText(empty)).assertEqual('');
      const included = new Interface();
      included.includedApplications = ['a', 'b'];
      expect(appFilterText(included)).assertEqual('对 2 个应用生效');
      const excluded = new Interface();
      excluded.excludedApplications = ['a'];
      expect(appFilterText(excluded)).assertEqual('对 1 个应用不生效');
    });

    it('portText / mtuText / keepaliveText 0 表示隐藏', 0, () => {
      expect(portText(0)).assertEqual('');
      expect(portText(51820)).assertEqual('51820');
      expect(mtuText(0)).assertEqual('');
      expect(mtuText(1420)).assertEqual('1420');
      expect(keepaliveText(0)).assertEqual('');
      expect(keepaliveText(25)).assertEqual('每隔 25 秒');
    });

    it('pskText 只显示已启用', 0, () => {
      expect(pskText('')).assertEqual('');
      expect(pskText('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=')).assertEqual('已启用');
    });

    it('endpointText 空值与非空', 0, () => {
      const peer = new Peer();
      expect(endpointText(peer)).assertEqual('');
      peer.endpoint = Peer.parseEndpoint('vpn.example.com:51820');
      expect(endpointText(peer)).assertEqual('vpn.example.com:51820');
    });

    it('trafficText 全零隐藏，否则人类可读', 0, () => {
      expect(trafficText(null)).assertEqual('');
      expect(trafficText(stats(0, 0, 0))).assertEqual('');
      expect(trafficText(stats(1024, 0, 0))).assertEqual('接收：1.00 KiB，发送：0 B');
      expect(trafficText(stats(1500, 2048, 0))).assertEqual('接收：1.46 KiB，发送：2.00 KiB');
    });

    it('handshakeText 从未握手隐藏', 0, () => {
      expect(handshakeText(null, NOW)).assertEqual('');
      expect(handshakeText(stats(0, 0, 0), NOW)).assertEqual('');
      expect(handshakeText(stats(0, 0, NOW - 267000), NOW)).assertEqual('4 分钟 27 秒之前');
      expect(handshakeText(stats(0, 0, NOW), NOW)).assertEqual('现在');
    });

    it('findStats 按公钥匹配', 0, () => {
      expect(findStats([], 'k1')).assertEqual(null);
      const found = findStats([stats(1, 2, 3)], 'k1');
      expect(found !== null).assertTrue();
      expect(findStats([stats(1, 2, 3)], 'other')).assertEqual(null);
    });
  });

  describe('RouteParams', () => {
    it('兼容字符串 / {name} / 空值', 0, () => {
      const named: NameParam = { name: 'wg1' };
      const badName: BadNameParam = { name: 123 };
      const empty: NameParam = {};
      expect(paramAsTunnelName('wg0')).assertEqual('wg0');
      expect(paramAsTunnelName(named)).assertEqual('wg1');
      expect(paramAsTunnelName(empty)).assertEqual('');
      expect(paramAsTunnelName(undefined)).assertEqual('');
      expect(paramAsTunnelName(null)).assertEqual('');
      expect(paramAsTunnelName(badName)).assertEqual('');
    });
  });
}

interface NameParam {
  name?: string;
}

interface BadNameParam {
  name: number;
}
