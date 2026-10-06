import { FileIO } from './FileIO';
import { InterfaceRecord, PeerRecord, TunnelRecord } from './TunnelRecord';

const FILE_NAME = 'tunnels.json';
const STORAGE_VERSION = 1;

/**
 * 隧道名称规则（spec specs/README.md 公共术语）：
 * 仅 ASCII 字母、数字及 _ = + . -，长度 1–15。
 *
 * 注意：config/ 模块合并后也有同名函数（docs/dev-contracts.md §3），
 * 此处自留一份以避免 repo/ 跨模块依赖 config/；两者规则必须保持一致，
 * 最终由 store/ 统一入口。
 */
export function isValidTunnelName(name: string): boolean {
  return new RegExp('^[A-Za-z0-9_=+.-]{1,15}$').test(name);
}

function asRecord(v: Object): Record<string, Object> | null {
  if (v === null || typeof v !== 'object' || v instanceof Array) {
    return null;
  }
  return v as Record<string, Object>;
}

function toStringArray(v: Object): string[] | null {
  if (!(v instanceof Array)) {
    return null;
  }
  const out: string[] = [];
  const arr = v as Object[];
  for (const item of arr) {
    if (typeof item !== 'string') {
      return null;
    }
    out.push(item);
  }
  return out;
}

function toNumber(v: Object): number | null {
  if (typeof v !== 'number' || !Number.isFinite(v)) {
    return null;
  }
  return v;
}

function toStringField(v: Object): string | null {
  return typeof v === 'string' ? v : null;
}

/** 解析并规范化一条 InterfaceRecord；非法返回 null。 */
function parseInterface(v: Object): InterfaceRecord | null {
  const r = asRecord(v);
  if (r === null) {
    return null;
  }
  const privateKey = toStringField(r['privateKey']);
  const addresses = toStringArray(r['addresses']);
  const listenPort = toNumber(r['listenPort']);
  const dnsServers = toStringArray(r['dnsServers']);
  const dnsSearchDomains = toStringArray(r['dnsSearchDomains']);
  const mtu = toNumber(r['mtu']);
  const excludedApplications = toStringArray(r['excludedApplications']);
  const includedApplications = toStringArray(r['includedApplications']);
  if (privateKey === null || addresses === null || listenPort === null ||
    dnsServers === null || dnsSearchDomains === null || mtu === null ||
    excludedApplications === null || includedApplications === null) {
    return null;
  }
  const out: InterfaceRecord = {
    privateKey: privateKey,
    addresses: addresses,
    listenPort: listenPort,
    dnsServers: dnsServers,
    dnsSearchDomains: dnsSearchDomains,
    mtu: mtu,
    excludedApplications: excludedApplications,
    includedApplications: includedApplications
  };
  return out;
}

/** 解析并规范化一条 PeerRecord；非法返回 null。 */
function parsePeer(v: Object): PeerRecord | null {
  const r = asRecord(v);
  if (r === null) {
    return null;
  }
  const publicKey = toStringField(r['publicKey']);
  const presharedKey = toStringField(r['presharedKey']);
  const allowedIPs = toStringArray(r['allowedIPs']);
  const endpoint = toStringField(r['endpoint']);
  const persistentKeepalive = toNumber(r['persistentKeepalive']);
  if (publicKey === null || presharedKey === null || allowedIPs === null ||
    endpoint === null || persistentKeepalive === null) {
    return null;
  }
  const out: PeerRecord = {
    publicKey: publicKey,
    presharedKey: presharedKey,
    allowedIPs: allowedIPs,
    endpoint: endpoint,
    persistentKeepalive: persistentKeepalive
  };
  return out;
}

/** 解析并规范化一条 JSON 中的 TunnelRecord（键名 name/interface/peers）；非法返回 null。 */
function parseTunnelJson(v: Object): TunnelRecord | null {
  const r = asRecord(v);
  if (r === null) {
    return null;
  }
  const name = toStringField(r['name']);
  if (name === null || !isValidTunnelName(name)) {
    return null;
  }
  const iface = parseInterface(r['interface']);
  if (iface === null) {
    return null;
  }
  const peers = parsePeers(r['peers']);
  if (peers === null) {
    return null;
  }
  const out: TunnelRecord = { name: name, iface: iface, peers: peers };
  return out;
}

function parsePeers(v: Object): PeerRecord[] | null {
  if (!(v instanceof Array)) {
    return null;
  }
  const peers: PeerRecord[] = [];
  const peersArr = v as Object[];
  for (const p of peersArr) {
    const peer = parsePeer(p);
    if (peer === null) {
      return null;
    }
    peers.push(peer);
  }
  return peers;
}

/** 校验内存中的 TunnelRecord（TS 字段名 iface）；非法返回 false。 */
function validateRecord(t: TunnelRecord): boolean {
  if (!isValidTunnelName(t.name)) {
    return false;
  }
  if (t.iface === null || t.iface === undefined) {
    return false;
  }
  if (parseInterface(t.iface as Object) === null) {
    return false;
  }
  if (t.peers === null || t.peers === undefined) {
    return false;
  }
  return parsePeers(t.peers as Object) !== null;
}

function ifaceToJson(iface: InterfaceRecord): Record<string, Object> {
  const obj: Record<string, Object> = {
    'privateKey': iface.privateKey,
    'addresses': iface.addresses,
    'listenPort': iface.listenPort,
    'dnsServers': iface.dnsServers,
    'dnsSearchDomains': iface.dnsSearchDomains,
    'mtu': iface.mtu,
    'excludedApplications': iface.excludedApplications,
    'includedApplications': iface.includedApplications
  };
  return obj;
}

function peerToJson(peer: PeerRecord): Record<string, Object> {
  const obj: Record<string, Object> = {
    'publicKey': peer.publicKey,
    'presharedKey': peer.presharedKey,
    'allowedIPs': peer.allowedIPs,
    'endpoint': peer.endpoint,
    'persistentKeepalive': peer.persistentKeepalive
  };
  return obj;
}

function tunnelToJson(t: TunnelRecord): Record<string, Object> {
  const peers: Record<string, Object>[] = t.peers.map((p: PeerRecord): Record<string, Object> => peerToJson(p));
  const obj: Record<string, Object> = {
    'name': t.name,
    'interface': ifaceToJson(t.iface),
    'peers': peers
  };
  return obj;
}

/**
 * 隧道配置仓库：tunnels.json 的读写与集合操作（见 docs/dev-contracts.md §5、决策 0003）。
 *
 * - 纯逻辑模块：不 import @kit，文件 I/O 经 FileIO 注入，时间戳经 clock 注入，
 *   日志经 logger 回调注入 → 本地单测可全覆盖。
 * - 读取容错（spec specs/README.md 升级兼容）：
 *   · 文件不存在 → 空列表；
 *   · JSON 损坏 / 顶层结构非法 / version > 1 → 原文件备份为 tunnels.json.corrupt-<ts>，
 *     返回空列表并记日志（不崩溃）；
 *   · 单条记录非法 → 跳过该条并记日志，其余正常加载。
 * - 写路径：全部变更最终经 saveAll 整体序列化；原子性由 FileIO.write 实现方保证。
 */
export class TunnelRepository {
  private io: FileIO;
  private dirPath: string;
  private clock: () => number;
  private logger: (msg: string) => void;

  constructor(io: FileIO, dirPath: string, clock?: () => number, logger?: (msg: string) => void) {
    this.io = io;
    this.dirPath = dirPath;
    this.clock = clock !== undefined ? clock : (): number => Date.now();
    this.logger = logger !== undefined ? logger : (msg: string): void => {};
  }

  private filePath(): string {
    return `${this.dirPath}/${FILE_NAME}`;
  }

  private backupCorrupt(reason: string): void {
    const path = this.filePath();
    const backupPath = `${path}.corrupt-${this.clock()}`;
    try {
      this.io.rename(path, backupPath);
      this.logger(`隧道配置存储损坏（${reason}），原文件已备份为 ${backupPath}`);
    } catch (e) {
      this.logger(`隧道配置存储损坏（${reason}），备份失败：${(e as Error).message}`);
    }
  }

  /** 加载全部隧道记录（容错规则见类注释）。 */
  load(): TunnelRecord[] {
    const content = this.io.read(this.filePath());
    if (content === null) {
      return [];
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(content) as Object;
    } catch (e) {
      this.backupCorrupt(`JSON 解析失败：${(e as Error).message}`);
      return [];
    }
    const root = asRecord(parsed);
    if (root === null) {
      this.backupCorrupt('顶层结构不是对象');
      return [];
    }
    const version = root['version'];
    if (version !== undefined) {
      const v = toNumber(version);
      if (v === null || v > STORAGE_VERSION) {
        this.backupCorrupt(`不支持的存储版本：${JSON.stringify(version)}`);
        return [];
      }
    }
    const tunnelsRaw = root['tunnels'];
    if (!(tunnelsRaw instanceof Array)) {
      this.backupCorrupt('缺少 tunnels 数组');
      return [];
    }
    const out: TunnelRecord[] = [];
    const arr = tunnelsRaw as Object[];
    for (const item of arr) {
      const record = parseTunnelJson(item);
      if (record === null) {
        this.logger(`跳过无法读取的隧道记录：${JSON.stringify(item)}`);
        continue;
      }
      out.push(record);
    }
    return out;
  }

  /** 全量覆写（先校验全部记录：任一非法则抛出且不写盘）。 */
  saveAll(records: TunnelRecord[]): void {
    const seen = new Set<string>();
    for (const r of records) {
      if (!isValidTunnelName(r.name)) {
        throw new Error('名称无效');
      }
      if (!validateRecord(r)) {
        throw new Error('隧道配置无效');
      }
      if (seen.has(r.name)) {
        throw new Error(`名称 '${r.name}' 已存在`);
      }
      seen.add(r.name);
    }
    const tunnels: Record<string, Object>[] =
      records.map((t: TunnelRecord): Record<string, Object> => tunnelToJson(t));
    const root: Record<string, Object> = {
      'version': STORAGE_VERSION,
      'tunnels': tunnels
    };
    this.io.write(this.filePath(), JSON.stringify(root));
  }

  /** 按名查找；不存在返回 null。 */
  findByName(name: string): TunnelRecord | null {
    const all = this.load();
    for (const t of all) {
      if (t.name === name) {
        return t;
      }
    }
    return null;
  }

  /** 新增隧道；名称非法抛「名称无效」，重名抛「名称 '<名称>' 已存在」，记录缺字段抛「隧道配置无效」。 */
  add(record: TunnelRecord): void {
    if (!isValidTunnelName(record.name)) {
      throw new Error('名称无效');
    }
    if (!validateRecord(record)) {
      throw new Error('隧道配置无效');
    }
    const all = this.load();
    if (this.containsName(all, record.name)) {
      throw new Error(`名称 '${record.name}' 已存在`);
    }
    all.push(record);
    this.saveAll(all);
  }

  /** 批量删除；不存在的名称静默忽略。 */
  remove(names: string[]): void {
    const toRemove = new Set<string>(names);
    const all = this.load();
    const kept = all.filter((t: TunnelRecord): boolean => !toRemove.has(t.name));
    this.saveAll(kept);
  }

  /**
   * 重命名；新名称非法抛「名称无效」，新名称与其他隧道重名抛「名称 '<名称>' 已存在」，
   * 旧名称不存在抛「隧道不存在」。
   */
  rename(oldName: string, newName: string): void {
    if (!isValidTunnelName(newName)) {
      throw new Error('名称无效');
    }
    const all = this.load();
    if (newName !== oldName && this.containsName(all, newName)) {
      throw new Error(`名称 '${newName}' 已存在`);
    }
    for (const t of all) {
      if (t.name === oldName) {
        t.name = newName;
        this.saveAll(all);
        return;
      }
    }
    throw new Error('隧道不存在');
  }

  /**
   * 替换指定隧道的配置记录（record.name 必须与 name 一致；改名请先用 rename）。
   * 隧道不存在抛「隧道不存在」，记录缺字段抛「隧道配置无效」。
   */
  replace(name: string, record: TunnelRecord): void {
    if (record.name !== name || !validateRecord(record)) {
      throw new Error('隧道配置无效');
    }
    const all = this.load();
    for (let i = 0; i < all.length; i++) {
      if (all[i].name === name) {
        all[i] = record;
        this.saveAll(all);
        return;
      }
    }
    throw new Error('隧道不存在');
  }

  private containsName(all: TunnelRecord[], name: string): boolean {
    for (const t of all) {
      if (t.name === name) {
        return true;
      }
    }
    return false;
  }
}
