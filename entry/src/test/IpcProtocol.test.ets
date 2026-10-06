import { describe, it, expect } from '@ohos/hypium';
import { decodePayload, encodePayload, IpcPayload, TUNNEL_EVENT } from '../main/ets/backend/IpcProtocol';
import { PeerStats } from '../main/ets/model/PeerStats';

function samplePeers(): PeerStats[] {
  const peers: PeerStats[] = [{
    publicKey: `${'D'.repeat(43)}=`,
    rxBytes: 1024,
    txBytes: 2048,
    lastHandshakeMs: 1700000000000,
    endpoint: 'vpn.example.com:51820'
  }];
  return peers;
}

export default function ipcProtocolTest() {
  describe('IpcProtocol', () => {
    it('事件名固定', 0, () => {
      expect(TUNNEL_EVENT).assertEqual('me.graycarl.wireguard.event.TUNNEL');
    });

    it('encode/decode 往返（up）', 0, () => {
      const payload: IpcPayload = { tunnel: 'wg0', state: 'up', peers: samplePeers() };
      const decoded = decodePayload(encodePayload(payload));
      expect(decoded !== null).assertTrue();
      const result = decoded as IpcPayload;
      expect(result.tunnel).assertEqual('wg0');
      expect(result.state).assertEqual('up');
      expect(result.peers.length).assertEqual(1);
      expect(result.peers[0].rxBytes).assertEqual(1024);
      expect(result.peers[0].txBytes).assertEqual(2048);
      expect(result.peers[0].endpoint).assertEqual('vpn.example.com:51820');
      expect(result.error === undefined).assertTrue();
    });

    it('encode/decode 往返（down + error）', 0, () => {
      const payload: IpcPayload = {
        tunnel: 'wg0',
        state: 'down',
        peers: [],
        error: '用户未授权 VPN 服务'
      };
      const decoded = decodePayload(encodePayload(payload));
      expect(decoded !== null).assertTrue();
      const result = decoded as IpcPayload;
      expect(result.state).assertEqual('down');
      expect(result.peers.length).assertEqual(0);
      expect(result.error).assertEqual('用户未授权 VPN 服务');
    });

    it('非法输入返回 null', 0, () => {
      expect(decodePayload('not json') === null).assertTrue();
      expect(decodePayload('{}') === null).assertTrue();
      expect(decodePayload('[]') === null).assertTrue();
      expect(decodePayload('{"tunnel":"a","state":"weird","peers":[]}') === null).assertTrue();
      expect(decodePayload('{"tunnel":"","state":"up","peers":[]}') === null).assertTrue();
      expect(decodePayload('{"tunnel":"a","state":"up","peers":[{"publicKey":1}]}') === null).assertTrue();
    });

    it('编码结果不含密钥字段', 0, () => {
      const text = encodePayload({ tunnel: 'wg0', state: 'up', peers: samplePeers() });
      expect(text.includes('privateKey')).assertFalse();
      expect(text.includes('presharedKey')).assertFalse();
      expect(text.includes('allowedIPs')).assertFalse();
    });
  });
}
