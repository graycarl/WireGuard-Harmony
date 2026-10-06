import { describe, it, expect } from '@ohos/hypium';
import {
  InterfaceDraft,
  TUNNEL_NAME_MAX_LENGTH,
  emptyPeerDraft,
  filterBase64KeyInput,
  filterDigitsInput,
  filterTunnelNameInput,
  formSignature,
  interfaceToDraft,
  draftToConfig,
  draftToInterface,
  peerToDraft,
  parseDnsServerText,
  splitListText
} from '../main/ets/components/EditorUtils';
import { Config } from '../main/ets/config/Config';
import { Interface } from '../main/ets/config/Interface';
import { Peer } from '../main/ets/config/Peer';

/** 生成一个合法的 44 字符 base64 密钥文本（内容无关，只要格式合法）。 */
function keyText(seed: string): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let text = '';
  let code = 0;
  for (let i = 0; i < seed.length; i++) {
    code += seed.charCodeAt(i);
  }
  for (let i = 0; i < 43; i++) {
    text += alphabet.charAt((code + i * 7) % 64);
  }
  // 32 字节 base64 的最后一位有效字符低 2 位必须为 0（保证格式校验通过）。
  const last = alphabet.charAt(Math.floor(((code + 42 * 7) % 64) / 4) * 4);
  text = text.substring(0, 42) + last + '=';
  return text;
}

export default function editorUtilsTest() {
  describe('EditorUtils', () => {
    it('名称输入过滤：非法字符剔除、超长截断', 0, () => {
      expect(filterTunnelNameInput('wg0')).assertEqual('wg0');
      expect(filterTunnelNameInput('wg_0=+.-')).assertEqual('wg_0=+.-');
      expect(filterTunnelNameInput('中文名')).assertEqual('');
      expect(filterTunnelNameInput('a b\tc')).assertEqual('abc');
      expect(filterTunnelNameInput('abcdefghijklmnopqrstuvwxyz')).assertEqual('abcdefghijklmno');
      expect(filterTunnelNameInput('abcdefghijklmnopqrstuvwxyz').length).assertEqual(TUNNEL_NAME_MAX_LENGTH);
      expect(filterTunnelNameInput('a#b@c!d')).assertEqual('abcd');
    });

    it('密钥输入过滤：字符集、第 44 位 = 与长度上限', 0, () => {
      const base = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456';
      expect(filterBase64KeyInput('ab+/')).assertEqual('ab+/');
      expect(filterBase64KeyInput('ab-_.')).assertEqual('ab');
      expect(filterBase64KeyInput(base)).assertEqual(base.substring(0, 44));
      // 43 个字符时允许补 '='
      const fortyThree = base.substring(0, 43);
      expect(filterBase64KeyInput(`${fortyThree}=`)).assertEqual(`${fortyThree}=`);
      expect(filterBase64KeyInput(`${fortyThree}=`).length).assertEqual(44);
      // '=' 出现在非第 44 位被剔除
      expect(filterBase64KeyInput('a=b')).assertEqual('ab');
      // 超长截断至 44
      expect(filterBase64KeyInput(`${base}XYZ`).length).assertEqual(44);
      expect(filterBase64KeyInput('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa').length).assertEqual(44);
    });

    it('数字输入过滤', 0, () => {
      expect(filterDigitsInput('51820', 5)).assertEqual('51820');
      expect(filterDigitsInput('518201', 5)).assertEqual('51820');
      expect(filterDigitsInput('51a8b2', 5)).assertEqual('5182');
      expect(filterDigitsInput('-1', 5)).assertEqual('1');
      expect(filterDigitsInput('', 5)).assertEqual('');
    });

    it('逗号列表拆分与空片段剔除', 0, () => {
      expect(splitListText('a, b ,c')).assertDeepEquals(['a', 'b', 'c']);
      expect(splitListText(' a ,, ,b,')).assertDeepEquals(['a', 'b']);
      expect(splitListText('')).assertDeepEquals([]);
      expect(splitListText('   ')).assertDeepEquals([]);
    });

    it('DNS IPv4 字面量提取（搜索域名与非 IPv4 忽略）', 0, () => {
      expect(parseDnsServerText('1.1.1.1, example.com, 2001:db8::1, 8.8.8.8'))
        .assertDeepEquals(['1.1.1.1', '8.8.8.8']);
      expect(parseDnsServerText('')).assertDeepEquals([]);
    });

    it('Interface ↔ 草稿往返（含应用过滤模式）', 0, () => {
      const iface = new Interface();
      iface.privateKey = keyText('iface');
      iface.addresses = Interface.parseAddresses('10.0.0.2/32, fc00::2/128');
      const dns = Interface.parseDns('1.1.1.1, example.com');
      iface.dnsServers = dns.servers;
      iface.dnsSearchDomains = dns.searchDomains;
      iface.listenPort = 51820;
      iface.mtu = 1420;
      iface.excludedApplications = ['com.example.a'];

      const draft = interfaceToDraft(iface);
      expect(draft.privateKey).assertEqual(iface.privateKey);
      expect(draft.addressesText).assertEqual('10.0.0.2/32, fc00::2/128');
      expect(draft.dnsText).assertEqual('1.1.1.1, example.com');
      expect(draft.listenPortText).assertEqual('51820');
      expect(draft.mtuText).assertEqual('1420');
      expect(draft.filterMode).assertEqual('excluded');
      expect(draft.filterApps).assertDeepEquals(['com.example.a']);

      const roundTrip = draftToInterface(draft);
      expect(roundTrip.addresses.length).assertEqual(2);
      expect(roundTrip.dnsServers).assertDeepEquals(['1.1.1.1']);
      expect(roundTrip.dnsSearchDomains).assertDeepEquals(['example.com']);
      expect(roundTrip.listenPort).assertEqual(51820);
      expect(roundTrip.mtu).assertEqual(1420);
      expect(roundTrip.excludedApplications).assertDeepEquals(['com.example.a']);
    });

    it('草稿空值：0/空串语义（不写监听端口与 MTU）', 0, () => {
      const iface = draftToInterface({
        privateKey: keyText('empty'),
        addressesText: '',
        listenPortText: '',
        dnsText: '',
        mtuText: '',
        filterMode: 'none',
        filterApps: []
      });
      expect(iface.addresses.length).assertEqual(0);
      expect(iface.dnsServers.length).assertEqual(0);
      expect(iface.listenPort).assertEqual(0);
      expect(iface.mtu).assertEqual(0);
      expect(iface.excludedApplications.length).assertEqual(0);
      expect(iface.includedApplications.length).assertEqual(0);
    });

    it('Peer ↔ 草稿往返（endpoint 空、保活 0、排除局域网识别）', 0, () => {
      const peer = new Peer();
      peer.publicKey = keyText('peer');
      peer.presharedKey = '';
      peer.allowedIPs = Peer.parseAllowedIPs('0.0.0.0/0');
      peer.endpoint = null;
      peer.persistentKeepalive = 0;

      const draft = peerToDraft(peer);
      expect(draft.publicKey).assertEqual(peer.publicKey);
      expect(draft.endpointText).assertEqual('');
      expect(draft.keepaliveText).assertEqual('');
      expect(draft.allowedIPsText).assertEqual('0.0.0.0/0');
      expect(draft.excludeLan).assertFalse();

      const roundTrip = draftToConfig(
        {
          privateKey: keyText('iface'),
          addressesText: '10.0.0.2/32',
          listenPortText: '',
          dnsText: '',
          mtuText: '',
          filterMode: 'none',
          filterApps: []
        },
        [draft]
      );
      expect(roundTrip.peers.length).assertEqual(1);
      expect(roundTrip.peers[0].endpoint).assertNull();
      expect(roundTrip.peers[0].persistentKeepalive).assertEqual(0);
    });

    it('已展开的公网段被识别为「排除局域网」状态', 0, () => {
      const peer = new Peer();
      peer.publicKey = keyText('peer');
      peer.allowedIPs = Peer.parseAllowedIPs(
        '0.0.0.0/5, 8.0.0.0/7, 11.0.0.0/8, 12.0.0.0/6, 16.0.0.0/4, 32.0.0.0/3, 64.0.0.0/2, 128.0.0.0/3, ' +
        '160.0.0.0/5, 168.0.0.0/6, 172.0.0.0/12, 172.32.0.0/11, 172.64.0.0/10, 172.128.0.0/9, 173.0.0.0/8, ' +
        '174.0.0.0/7, 176.0.0.0/4, 192.0.0.0/9, 192.128.0.0/11, 192.160.0.0/13, 192.169.0.0/16, ' +
        '192.170.0.0/15, 192.172.0.0/14, 192.176.0.0/12, 192.192.0.0/10, 193.0.0.0/8, 194.0.0.0/7, ' +
        '196.0.0.0/6, 200.0.0.0/5, 208.0.0.0/4'
      );
      const draft = peerToDraft(peer);
      expect(draft.excludeLan).assertTrue();
    });

    it('表单签名：改动可被检测', 0, () => {
      const peer = emptyPeerDraft();
      const iface: InterfaceDraft = {
        privateKey: keyText('sig'),
        addressesText: '',
        listenPortText: '',
        dnsText: '',
        mtuText: '',
        filterMode: 'none',
        filterApps: []
      };
      const before = formSignature(iface, [peer]);
      const changedPeer = emptyPeerDraft();
      changedPeer.publicKey = keyText('changed');
      const after = formSignature(iface, [changedPeer]);
      expect(before === after).assertFalse();
    });

    it('配置校验：缺失私钥/公钥被拒绝，合法配置通过', 0, () => {
      const badIface: InterfaceDraft = {
        privateKey: '',
        addressesText: '',
        listenPortText: '',
        dnsText: '',
        mtuText: '',
        filterMode: 'none',
        filterApps: []
      };
      let failed = false;
      try {
        draftToConfig(badIface, []);
      } catch (e) {
        failed = true;
        expect((e as Error).message.indexOf('私钥') >= 0).assertTrue();
      }
      expect(failed).assertTrue();

      const goodIface: InterfaceDraft = {
        privateKey: keyText('good'),
        addressesText: '10.0.0.2/32',
        listenPortText: '',
        dnsText: '',
        mtuText: '',
        filterMode: 'none',
        filterApps: []
      };
      const goodPeer = emptyPeerDraft();
      goodPeer.publicKey = keyText('goodpeer');
      goodPeer.allowedIPsText = '0.0.0.0/0';
      const config: Config = draftToConfig(goodIface, [goodPeer]);
      expect(config.peers.length).assertEqual(1);
    });
  });
}
