import { describe, it, expect } from '@ohos/hypium';
import { Config } from '../main/ets/config/Config';
import { RecordMapper } from '../main/ets/store/RecordMapper';
import { FileIO } from '../main/ets/repo/FileIO';
import { TunnelRecord } from '../main/ets/repo/TunnelRecord';
import { TunnelRepository } from '../main/ets/repo/TunnelRepository';

// 44 字符 base64 密钥（末位有效字符的 6bit 值需为 4 的倍数，见 config/KeyText.ets）
const PRIVATE_KEY = `${'A'.repeat(43)}=`;
const PUBLIC_KEY = `${'E'.repeat(43)}=`;
const PRESHARED_KEY = `${'I'.repeat(43)}=`;

/** 内存 FileIO（与 Repo.test 中的实现等价，测试独立）。 */
class MemFileIO implements FileIO {
  files: Map<string, string> = new Map();
  lastWritten: string = '';

  read(path: string): string | null {
    return this.files.has(path) ? (this.files.get(path) as string) : null;
  }

  write(path: string, content: string): void {
    this.lastWritten = content;
    this.files.set(path, content);
  }

  rename(src: string, dst: string): void {
    if (!this.files.has(src)) {
      throw new Error('no such file');
    }
    this.files.set(dst, this.files.get(src) as string);
    this.files.delete(src);
  }
}

function sampleConfig(): Config {
  const text = [
    '[Interface]',
    `PrivateKey = ${PRIVATE_KEY}`,
    'Address = 10.0.0.2/32, fc00::2/128',
    'DNS = 1.1.1.1, example.com',
    'ListenPort = 51820',
    'MTU = 1420',
    'ExcludedApplications = com.example.app',
    '',
    '[Peer]',
    `PublicKey = ${PUBLIC_KEY}`,
    `PresharedKey = ${PRESHARED_KEY}`,
    'AllowedIPs = 0.0.0.0/0, ::/0',
    'Endpoint = vpn.example.com:51820',
    'PersistentKeepalive = 25'
  ].join('\n');
  return Config.parse(text);
}

export default function recordMapperTest() {
  describe('RecordMapper', () => {
    it('Config → TunnelRecord 字段映射', 0, () => {
      const record = RecordMapper.toRecord('wg0', sampleConfig());
      expect(record.name).assertEqual('wg0');
      expect(record.iface.privateKey).assertEqual(PRIVATE_KEY);
      expect(record.iface.addresses.join(',')).assertEqual('10.0.0.2/32,fc00::2/128');
      expect(record.iface.dnsServers.join(',')).assertEqual('1.1.1.1');
      expect(record.iface.dnsSearchDomains.join(',')).assertEqual('example.com');
      expect(record.iface.listenPort).assertEqual(51820);
      expect(record.iface.mtu).assertEqual(1420);
      expect(record.iface.excludedApplications.join(',')).assertEqual('com.example.app');
      expect(record.iface.includedApplications.length).assertEqual(0);
      expect(record.peers.length).assertEqual(1);
      expect(record.peers[0].publicKey).assertEqual(PUBLIC_KEY);
      expect(record.peers[0].presharedKey).assertEqual(PRESHARED_KEY);
      expect(record.peers[0].allowedIPs.join(',')).assertEqual('0.0.0.0/0,::/0');
      expect(record.peers[0].endpoint).assertEqual('vpn.example.com:51820');
      expect(record.peers[0].persistentKeepalive).assertEqual(25);
    });

    it('Config ↔ TunnelRecord 往返保持序列化一致', 0, () => {
      const config = sampleConfig();
      const restored = RecordMapper.toConfig(RecordMapper.toRecord('wg0', config));
      expect(restored.toWgQuickString()).assertEqual(config.toWgQuickString());
    });

    it('零 Peer 往返', 0, () => {
      const config = Config.parse(`[Interface]\nPrivateKey = ${PRIVATE_KEY}\n`);
      const record = RecordMapper.toRecord('empty', config);
      expect(record.peers.length).assertEqual(0);
      const restored = RecordMapper.toConfig(record);
      expect(restored.peers.length).assertEqual(0);
      expect(restored.interface.privateKey).assertEqual(PRIVATE_KEY);
    });

    it('对端缺省 → 空串 → null 往返', 0, () => {
      const config = Config.parse(
        `[Interface]\nPrivateKey = ${PRIVATE_KEY}\n\n[Peer]\nPublicKey = ${PUBLIC_KEY}\n`);
      const record = RecordMapper.toRecord('noendpoint', config);
      expect(record.peers[0].endpoint).assertEqual('');
      const restored = RecordMapper.toConfig(record);
      expect(restored.peers[0].endpoint === null).assertTrue();
    });

    it('IPv6 对端与地址往返', 0, () => {
      const config = Config.parse([
        '[Interface]',
        `PrivateKey = ${PRIVATE_KEY}`,
        'Address = fc00::2/128',
        '',
        '[Peer]',
        `PublicKey = ${PUBLIC_KEY}`,
        'AllowedIPs = ::/0',
        'Endpoint = [2001:db8::1]:51820'
      ].join('\n'));
      const record = RecordMapper.toRecord('v6', config);
      expect(record.iface.addresses.join(',')).assertEqual('fc00::2/128');
      expect(record.peers[0].endpoint).assertEqual('[2001:db8::1]:51820');
      const restored = RecordMapper.toConfig(record);
      expect(restored.toWgQuickString()).assertEqual(config.toWgQuickString());
    });

    it('持久化 JSON 键为 interface（磁盘格式契约）', 0, () => {
      const io = new MemFileIO();
      const repo = new TunnelRepository(io, '/data');
      repo.saveAll([RecordMapper.toRecord('wg0', sampleConfig())]);
      expect(io.lastWritten.includes('"interface"')).assertTrue();
      expect(io.lastWritten.includes('"peers"')).assertTrue();
      expect(io.lastWritten.includes('"privateKey"')).assertTrue();
    });

    it('仓库读写往返（经 RecordMapper）', 0, () => {
      const io = new MemFileIO();
      const repo = new TunnelRepository(io, '/data');
      repo.add(RecordMapper.toRecord('wg0', sampleConfig()));
      const found = repo.findByName('wg0');
      expect(found !== null).assertTrue();
      const config = RecordMapper.toConfig(found as TunnelRecord);
      expect(config.interface.listenPort).assertEqual(51820);
      expect(config.peers[0].persistentKeepalive).assertEqual(25);
    });
  });
}
