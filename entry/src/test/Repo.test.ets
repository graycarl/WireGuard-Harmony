import { describe, it, expect } from '@ohos/hypium';
import { FileIO } from '../main/ets/repo/FileIO';
import { TunnelRecord } from '../main/ets/repo/TunnelRecord';
import { isValidTunnelName, TunnelRepository } from '../main/ets/repo/TunnelRepository';

/** 内存 FileIO：模拟原子写 + rename，并记录 write 调用次数与最后一次内容。 */
class MemFileIO implements FileIO {
  files: Map<string, string> = new Map();
  writeCount: number = 0;
  lastWritten: string = '';

  read(path: string): string | null {
    return this.files.has(path) ? (this.files.get(path) as string) : null;
  }

  write(path: string, content: string): void {
    this.writeCount++;
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

function makeRecord(name: string): TunnelRecord {
  return {
    name: name,
    iface: {
      privateKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      addresses: ['10.0.0.2/32'],
      listenPort: 51820,
      dnsServers: ['1.1.1.1'],
      dnsSearchDomains: ['example.com'],
      mtu: 1420,
      excludedApplications: [],
      includedApplications: []
    },
    peers: [{
      publicKey: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
      presharedKey: '',
      allowedIPs: ['0.0.0.0/0'],
      endpoint: 'vpn.example.com:51820',
      persistentKeepalive: 25
    }]
  };
}

function expectThrowMsg(fn: () => void, msg: string): void {
  let thrown = '';
  try {
    fn();
  } catch (e) {
    thrown = (e as Error).message;
  }
  expect(thrown).assertEqual(msg);
}

export default function repoTest() {
  describe('TunnelRepository', () => {
    it('load_returns_empty_when_file_missing', 0, () => {
      const io = new MemFileIO();
      const repo = new TunnelRepository(io, '/data');
      expect(repo.load().length).assertEqual(0);
    });

    it('isValidTunnelName_rules', 0, () => {
      expect(isValidTunnelName('wg0')).assertTrue();
      expect(isValidTunnelName('a_B=C+D.E-F')).assertTrue();
      expect(isValidTunnelName('')).assertFalse();
      expect(isValidTunnelName('1234567890123456')).assertFalse(); // 16 字符超长
      expect(isValidTunnelName('中文名')).assertFalse();
      expect(isValidTunnelName('has space')).assertFalse();
      expect(isValidTunnelName('a/b')).assertFalse();
    });

    it('add_and_load_roundtrip', 0, () => {
      const io = new MemFileIO();
      const repo = new TunnelRepository(io, '/data');
      repo.add(makeRecord('wg0'));
      repo.add(makeRecord('wg1'));
      // 用新实例重新加载，验证真的落了盘
      const reloaded = new TunnelRepository(io, '/data').load();
      expect(reloaded.length).assertEqual(2);
      expect(reloaded[0].name).assertEqual('wg0');
      expect(reloaded[0].iface.privateKey).assertEqual('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
      expect(reloaded[0].iface.addresses).assertDeepEquals(['10.0.0.2/32']);
      expect(reloaded[0].iface.listenPort).assertEqual(51820);
      expect(reloaded[0].iface.dnsServers).assertDeepEquals(['1.1.1.1']);
      expect(reloaded[0].iface.dnsSearchDomains).assertDeepEquals(['example.com']);
      expect(reloaded[0].iface.mtu).assertEqual(1420);
      expect(reloaded[0].peers.length).assertEqual(1);
      expect(reloaded[0].peers[0].publicKey).assertEqual('BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=');
      expect(reloaded[0].peers[0].allowedIPs).assertDeepEquals(['0.0.0.0/0']);
      expect(reloaded[0].peers[0].endpoint).assertEqual('vpn.example.com:51820');
      expect(reloaded[0].peers[0].persistentKeepalive).assertEqual(25);
    });

    it('corrupt_json_backed_up_and_returns_empty', 0, () => {
      const io = new MemFileIO();
      const logs: string[] = [];
      const repo = new TunnelRepository(io, '/data', (): number => 12345, (msg: string): void => {
        logs.push(msg);
      });
      io.files.set('/data/tunnels.json', '{not valid json!!!');
      expect(repo.load().length).assertEqual(0);
      // 原文件被 rename 成带时间戳的备份
      expect(io.files.has('/data/tunnels.json')).assertFalse();
      expect(io.files.has('/data/tunnels.json.corrupt-12345')).assertTrue();
      expect(io.files.get('/data/tunnels.json.corrupt-12345')).assertEqual('{not valid json!!!');
      expect(logs.length).assertEqual(1);
      expect(logs[0]).assertContain('损坏');
    });

    it('version_greater_than_1_treated_as_corrupt', 0, () => {
      const io = new MemFileIO();
      const logs: string[] = [];
      const repo = new TunnelRepository(io, '/data', (): number => 7, (msg: string): void => {
        logs.push(msg);
      });
      io.files.set('/data/tunnels.json', '{"version":2,"tunnels":[]}');
      expect(repo.load().length).assertEqual(0);
      expect(io.files.has('/data/tunnels.json.corrupt-7')).assertTrue();
      expect(logs.length).assertEqual(1);
    });

    it('version_missing_or_1_accepted', 0, () => {
      const io = new MemFileIO();
      const repo = new TunnelRepository(io, '/data');
      io.files.set('/data/tunnels.json', '{"tunnels":[]}');
      expect(repo.load().length).assertEqual(0);
      io.files.set('/data/tunnels.json', '{"version":1,"tunnels":[]}');
      expect(repo.load().length).assertEqual(0);
      // 两种情形都不应产生备份
      expect(io.files.has('/data/tunnels.json')).assertTrue();
    });

    it('invalid_entries_skipped_others_loaded', 0, () => {
      const io = new MemFileIO();
      const logs: string[] = [];
      const repo = new TunnelRepository(io, '/data', undefined, (msg: string): void => {
        logs.push(msg);
      });
      const good = makeRecord('wg0');
      // 手工拼 JSON：一条缺 name、一条名称非法、一条 peers 字段类型错、一条正常
      const goodJson = '{"name":"wg0","interface":{' +
        '"privateKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","addresses":["10.0.0.2/32"],' +
        '"listenPort":51820,"dnsServers":["1.1.1.1"],"dnsSearchDomains":["example.com"],"mtu":1420,' +
        '"excludedApplications":[],"includedApplications":[]},' +
        '"peers":[{"publicKey":"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=","presharedKey":"",' +
        '"allowedIPs":["0.0.0.0/0"],"endpoint":"vpn.example.com:51820","persistentKeepalive":25}]}';
      const noName = '{"interface":{},"peers":[]}';
      const badName = '{"name":"中文","interface":{},"peers":[]}';
      const badPeers = '{"name":"wg1","interface":{},"peers":"oops"}';
      io.files.set('/data/tunnels.json',
        `{"version":1,"tunnels":[${noName},${badName},${badPeers},${goodJson}]}`);
      const loaded = repo.load();
      expect(loaded.length).assertEqual(1);
      expect(loaded[0].name).assertEqual('wg0');
      expect(loaded[0]).assertDeepEquals(good);
      expect(logs.length).assertEqual(3);
      // 单条非法不触发整文件备份
      expect(io.files.has('/data/tunnels.json')).assertTrue();
    });

    it('add_duplicate_name_throws', 0, () => {
      const repo = new TunnelRepository(new MemFileIO(), '/data');
      repo.add(makeRecord('wg0'));
      expectThrowMsg((): void => {
        repo.add(makeRecord('wg0'));
      }, "名称 'wg0' 已存在");
    });

    it('add_invalid_name_throws', 0, () => {
      const repo = new TunnelRepository(new MemFileIO(), '/data');
      expectThrowMsg((): void => {
        repo.add(makeRecord('中文名'));
      }, '名称无效');
      expectThrowMsg((): void => {
        repo.add(makeRecord('1234567890123456'));
      }, '名称无效');
    });

    it('add_invalid_record_shape_throws', 0, () => {
      const repo = new TunnelRepository(new MemFileIO(), '/data');
      const bad = makeRecord('wg0');
      bad.iface.listenPort = 'not-a-number' as Object as number; // 故意破坏类型
      expectThrowMsg((): void => {
        repo.add(bad);
      }, '隧道配置无效');
    });

    it('findByName_found_and_missing', 0, () => {
      const repo = new TunnelRepository(new MemFileIO(), '/data');
      repo.add(makeRecord('wg0'));
      expect(repo.findByName('wg0')?.name).assertEqual('wg0');
      expect(repo.findByName('wg9')).assertNull();
      // 重名判定区分大小写（spec 公共术语）
      expect(repo.findByName('WG0')).assertNull();
    });

    it('rename_success', 0, () => {
      const io = new MemFileIO();
      const repo = new TunnelRepository(io, '/data');
      repo.add(makeRecord('wg0'));
      repo.rename('wg0', 'wg1');
      expect(repo.findByName('wg0')).assertNull();
      expect(repo.findByName('wg1')?.name).assertEqual('wg1');
    });

    it('rename_errors', 0, () => {
      const repo = new TunnelRepository(new MemFileIO(), '/data');
      repo.add(makeRecord('wg0'));
      repo.add(makeRecord('wg1'));
      expectThrowMsg((): void => {
        repo.rename('wg0', 'wg1');
      }, "名称 'wg1' 已存在");
      expectThrowMsg((): void => {
        repo.rename('wg0', 'bad name');
      }, '名称无效');
      expectThrowMsg((): void => {
        repo.rename('nope', 'wg2');
      }, '隧道不存在');
    });

    it('remove_mixed_existing_and_missing', 0, () => {
      const repo = new TunnelRepository(new MemFileIO(), '/data');
      repo.add(makeRecord('wg0'));
      repo.add(makeRecord('wg1'));
      repo.add(makeRecord('wg2'));
      repo.remove(['wg0', 'wg2', 'ghost']);
      const names = repo.load().map((t: TunnelRecord): string => t.name);
      expect(names).assertDeepEquals(['wg1']);
    });

    it('replace_success_and_missing_throws', 0, () => {
      const repo = new TunnelRepository(new MemFileIO(), '/data');
      repo.add(makeRecord('wg0'));
      const updated = makeRecord('wg0');
      updated.iface.listenPort = 1234;
      repo.replace('wg0', updated);
      expect(repo.findByName('wg0')?.iface.listenPort).assertEqual(1234);
      expectThrowMsg((): void => {
        repo.replace('ghost', makeRecord('ghost'));
      }, '隧道不存在');
      // record.name 与目标名不一致视为配置无效（改名须走 rename）
      expectThrowMsg((): void => {
        repo.replace('wg0', makeRecord('other'));
      }, '隧道配置无效');
    });

    it('saveAll_writes_parseable_json_with_version_1', 0, () => {
      const io = new MemFileIO();
      const repo = new TunnelRepository(io, '/data');
      repo.saveAll([makeRecord('wg0'), makeRecord('wg1')]);
      expect(io.writeCount).assertEqual(1);
      const root = JSON.parse(io.lastWritten) as Record<string, Object>;
      expect(root['version']).assertEqual(1);
      const tunnels = root['tunnels'] as Object[];
      expect(tunnels.length).assertEqual(2);
      // 磁盘 JSON 键名必须是 "interface"（契约 §5 schema）
      const first = tunnels[0] as Record<string, Object>;
      expect(first['name']).assertEqual('wg0');
      expect(first['interface'] !== undefined).assertTrue();
      expect(first['interface'] !== null).assertTrue();
    });

    it('saveAll_rejects_invalid_without_writing', 0, () => {
      const io = new MemFileIO();
      const repo = new TunnelRepository(io, '/data');
      expectThrowMsg((): void => {
        repo.saveAll([makeRecord('wg0'), makeRecord('wg0')]);
      }, "名称 'wg0' 已存在");
      expectThrowMsg((): void => {
        repo.saveAll([makeRecord('bad name')]);
      }, '名称无效');
      expect(io.writeCount).assertEqual(0);
    });
  });
}
