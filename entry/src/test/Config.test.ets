/*
 * config/ 模块本地单测（纯逻辑，无平台 API）。
 *
 * 覆盖 specs/config-format.md 的全部规则与边界，以及 specs/tunnel-list.md 的排序规则、
 * specs/tunnel-editor.md 的「排除局域网」展开/折叠。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Attribute } from '../main/ets/config/Attribute';
import { Config } from '../main/ets/config/Config';
import { Interface } from '../main/ets/config/Interface';
import { Peer } from '../main/ets/config/Peer';
import { InetNetwork } from '../main/ets/config/InetNetwork';
import { InetEndpoint } from '../main/ets/config/InetEndpoint';
import { BadConfigException } from '../main/ets/config/Exceptions';
import { isHostname, isIpv4, isIpv6 } from '../main/ets/config/InetAddresses';
import { compareTunnelNames, isValidTunnelName } from '../main/ets/config/Names';
import {
  PUBLIC_NETWORKS_V4, IPV4_WILDCARD, dnsRoutesFor, expandExcludeLan, collapseExcludeLan,
  isExcludeLanExpanded, isExcludeLanApplicable, syncLanDnsRoutes
} from '../main/ets/config/PrivateNetworks';

// ===== 测试辅助 =====

const KEY1 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
const KEY2 = 'q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s=';
const KEY3 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const KEY4 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';

function repeatChar(ch: string, count: number): string {
  let result = '';
  for (let i = 0; i < count; i++) {
    result += ch;
  }
  return result;
}

/** 捕获动作抛出的错误消息；未抛错时返回哨兵值。 */
function messageOf(action: () => void): string {
  try {
    action();
  } catch (e) {
    return (e as Error).message;
  }
  return '__NO_EXCEPTION__';
}

/** 动作是否抛出 BadConfigException。 */
function isBadConfig(action: () => void): boolean {
  try {
    action();
  } catch (e) {
    return (e as Error).name === 'BadConfigException';
  }
  return false;
}

/** 动作是否抛出任意错误。 */
function throwsAnything(action: () => void): boolean {
  try {
    action();
  } catch (e) {
    return true;
  }
  return false;
}

function endpointText(endpoint: InetEndpoint | null): string {
  return endpoint === null ? '' : endpoint.toString();
}

function networkTexts(networks: InetNetwork[]): string[] {
  const result: string[] = [];
  for (const network of networks) {
    result.push(network.toString());
  }
  return result;
}

/** 取 validate() 结果的消息（无错误时返回哨兵值）。 */
function validationMessage(config: Config): string {
  const error = config.validate();
  return error === null ? '__NO_ERROR__' : error.message;
}

function interfaceValidationMessage(iface: Interface): string {
  const error = iface.validate();
  return error === null ? '__NO_ERROR__' : error.message;
}

function peerValidationMessage(peer: Peer): string {
  const error = peer.validate();
  return error === null ? '__NO_ERROR__' : error.message;
}

export default function configTest() {
  describe('Config', () => {
    // ---------- Attribute ----------

    it('Attribute: parse/split/join', 0, () => {
      const attribute = Attribute.parse('PrivateKey = abc def');
      expect(attribute === null).assertFalse();
      if (attribute !== null) {
        expect(attribute.key).assertEqual('PrivateKey');
        expect(attribute.value).assertEqual('abc def');
      }
      expect(Attribute.parse('PrivateKey = ')).assertNull();
      expect(Attribute.parse('PrivateKey')).assertNull();
      expect(Attribute.parse('Private Key = x')).assertNull();
      const parts = Attribute.split('a, b ,c');
      expect(parts.length).assertEqual(3);
      expect(parts[1]).assertEqual('b');
      expect(Attribute.join([])).assertEqual('');
      expect(Attribute.join(['a', 'b'])).assertEqual('a, b');
    });

    // ---------- 解析：正常路径 ----------

    it('Config: 完整配置解析（Interface 与多个 Peer）', 0, () => {
      const text = `[Interface]
PrivateKey = ${KEY1}
Address = 10.0.0.2/32, fc00::2/128
DNS = 1.1.1.1, example.com
ListenPort = 51820
MTU = 1420
ExcludedApplications = com.foo.bar, com.baz.qux

[Peer]
PublicKey = ${KEY2}
PresharedKey = ${KEY3}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = vpn.example.com:51820
PersistentKeepalive = 25

[Peer]
PublicKey = ${KEY4}
AllowedIPs = 10.0.0.0/24
`;
      const config = Config.parse(text);
      expect(config.interface.privateKey).assertEqual(KEY1);
      expect(config.interface.addresses.length).assertEqual(2);
      expect(config.interface.addresses[0].toString()).assertEqual('10.0.0.2/32');
      expect(config.interface.addresses[1].toString()).assertEqual('fc00::2/128');
      expect(config.interface.dnsServers.length).assertEqual(1);
      expect(config.interface.dnsServers[0]).assertEqual('1.1.1.1');
      expect(config.interface.dnsSearchDomains.length).assertEqual(1);
      expect(config.interface.dnsSearchDomains[0]).assertEqual('example.com');
      expect(config.interface.listenPort).assertEqual(51820);
      expect(config.interface.mtu).assertEqual(1420);
      expect(config.interface.excludedApplications.length).assertEqual(2);
      expect(config.interface.includedApplications.length).assertEqual(0);
      expect(config.peers.length).assertEqual(2);
      expect(config.peers[0].publicKey).assertEqual(KEY2);
      expect(config.peers[0].presharedKey).assertEqual(KEY3);
      expect(config.peers[0].allowedIPs.length).assertEqual(2);
      expect(endpointText(config.peers[0].endpoint)).assertEqual('vpn.example.com:51820');
      expect(config.peers[0].persistentKeepalive).assertEqual(25);
      expect(config.peers[1].publicKey).assertEqual(KEY4);
      expect(config.peers[1].allowedIPs[0].toString()).assertEqual('10.0.0.0/24');
      expect(endpointText(config.peers[1].endpoint)).assertEqual('');
    });

    it('Config: 键与节标题大小写不敏感、等号两侧空白', 0, () => {
      const config = Config.parse(`[interface]
pRiVaTeKeY   =   ${KEY1}
ADDRESS=10.0.0.2/32
dns = 1.1.1.1
`);
      expect(config.interface.privateKey).assertEqual(KEY1);
      expect(config.interface.addresses[0].toString()).assertEqual('10.0.0.2/32');
      expect(config.interface.dnsServers[0]).assertEqual('1.1.1.1');
    });

    it('Config: 注释截断与空行忽略', 0, () => {
      const config = Config.parse(`# 文件头注释

[Interface]
PrivateKey = ${KEY1}   # 行内注释
Address = 10.0.0.2/32

# 节间注释
[Peer]
PublicKey = ${KEY2} # 注释
`);
      expect(config.interface.privateKey).assertEqual(KEY1);
      expect(config.peers.length).assertEqual(1);
    });

    it('Config: 多个 [Interface] 节合并（标量取最后、列表累加）', 0, () => {
      const config = Config.parse(`[Interface]
PrivateKey = ${KEY1}
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Interface]
PrivateKey = ${KEY2}
Address = 10.0.0.3/32
DNS = 8.8.8.8
`);
      expect(config.interface.privateKey).assertEqual(KEY2);
      expect(networkTexts(config.interface.addresses)).assertDeepEquals(['10.0.0.2/32', '10.0.0.3/32']);
      expect(config.interface.dnsServers).assertDeepEquals(['1.1.1.1', '8.8.8.8']);
    });

    it('Config: [Peer] 出现在 [Interface] 之前也合法', 0, () => {
      const config = Config.parse(`[Peer]
PublicKey = ${KEY2}

[Interface]
PrivateKey = ${KEY1}
`);
      expect(config.peers.length).assertEqual(1);
      expect(config.interface.privateKey).assertEqual(KEY1);
    });

    it('Config: 同一键重复时标量取最后、列表累加', 0, () => {
      const config = Config.parse(`[Interface]
PrivateKey = ${KEY1}
Address = 10.0.0.2/32
Address = 10.0.0.3/32
ListenPort = 1
ListenPort = 2
`);
      expect(config.interface.listenPort).assertEqual(2);
      expect(config.interface.addresses.length).assertEqual(2);
    });

    it('Config: 零个 Peer 合法（仅 Interface 节）', 0, () => {
      const config = Config.parse(`[Interface]
PrivateKey = ${KEY1}
`);
      expect(config.peers.length).assertEqual(0);
    });

    // ---------- 解析：错误路径 ----------

    it('Config: 缺失 [Interface] → 缺失节（整体）', 0, () => {
      const message = messageOf(() => {
        Config.parse(`[Peer]
PublicKey = ${KEY2}
`);
      });
      expect(message).assertEqual('在 整体 发生了 缺失节 的问题');
    });

    it('Config: 未知节与节前内容 → 未知节（整体）', 0, () => {
      expect(messageOf(() => {
        Config.parse('[Foo]\n');
      })).assertEqual('在 整体 发生了 未知节 的问题');
      expect(messageOf(() => {
        Config.parse(`Address = 10.0.0.2/32\n[Interface]\nPrivateKey = ${KEY1}\n`);
      })).assertEqual('在 整体 发生了 未知节 的问题');
    });

    it('Config: 未知属性 → 未知属性（本地/远程）', 0, () => {
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
Table = auto
`);
      })).assertEqual('在 本地 发生了 未知属性 的问题');
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
PublicKey = ${KEY2}
SaveConfig = true
`);
      })).assertEqual('在 远程 发生了 未知属性 的问题');
    });

    it('Config: 语法错误（缺等号 / 值为空）', 0, () => {
      expect(messageOf(() => {
        Config.parse('[Interface]\nPrivateKey\n');
      })).assertEqual('在 本地 发生了 语法错误 的问题');
      expect(messageOf(() => {
        Config.parse('[Interface]\nPrivateKey =\n');
      })).assertEqual('在 本地 发生了 语法错误 的问题');
    });

    it('Config: 缺失属性（Interface 无 PrivateKey、Peer 无 PublicKey）', 0, () => {
      expect(messageOf(() => {
        Config.parse('[Interface]\nAddress = 10.0.0.2/32\n');
      })).assertEqual('在 本地 的 私钥 字段发生了 缺失属性 的问题');
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
AllowedIPs = 0.0.0.0/0
`);
      })).assertEqual('在 远程 的 公钥 字段发生了 缺失属性 的问题');
    });

    it('Config: 密钥长度错误 / 密钥中含错误字符', 0, () => {
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${repeatChar('A', 43)}
`);
      })).assertEqual('在 本地 的 私钥 字段发生了 密钥长度错误 的问题：WireGuard 的 Base64 密钥长度必须为 44 个字符（32 字节）');
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = *${KEY1.substring(1)}
`);
      })).assertEqual('在 本地 的 私钥 字段发生了 密钥中含错误字符 的问题');
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1.substring(0, 42)}9=
`);
      })).assertEqual('在 本地 的 私钥 字段发生了 密钥中含错误字符 的问题');
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
PublicKey = ${repeatChar('B', 43)}
`);
      })).assertEqual('在 远程 的 公钥 字段发生了 密钥长度错误 的问题：WireGuard 的 Base64 密钥长度必须为 44 个字符（32 字节）');
    });

    it('Config: 监听端口（非整数 → 数字无效；越界 → 数值无效）', 0, () => {
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
ListenPort = abc
`);
      })).assertEqual('在 本地 的 监听端口 字段发生了 数字无效 的问题');
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
ListenPort = 65536
`);
      })).assertEqual('在 本地 的 监听端口 字段发生了 数值无效 的问题：必须为有效的 UDP 端口号');
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
ListenPort = -1
`);
      })).assertEqual('在 本地 的 监听端口 字段发生了 数值无效 的问题：必须为有效的 UDP 端口号');
      const zero = Config.parse(`[Interface]
PrivateKey = ${KEY1}
ListenPort = 0
`);
      expect(zero.interface.listenPort).assertEqual(0);
    });

    it('Config: MTU 越界报在 MTU 字段（上游缺陷修正）', 0, () => {
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
MTU = -1
`);
      })).assertEqual('在 本地 的 MTU 字段发生了 数值无效 的问题：必须为非负整数');
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
MTU = x
`);
      })).assertEqual('在 本地 的 MTU 字段发生了 数字无效 的问题');
    });

    it('Config: 应用过滤互斥使用明确表述（上游缺陷修正）', 0, () => {
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
IncludedApplications = com.foo
ExcludedApplications = com.bar
`);
      })).assertEqual('在 本地 的 应用过滤 字段发生了 应用过滤的两种模式不能同时设置 的问题');
    });

    it('Config: 地址无法解析 / 掩码越界 / 掩码非数字', 0, () => {
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
Address = 300.1.1.1/32
`);
      })).assertEqual(`在 本地 的 局域网 IP 地址 字段发生了 无法解析 IP 地址 '300.1.1.1' 的问题`);
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
Address = 10.0.0.2/33
`);
      })).assertEqual(`在 本地 的 局域网 IP 地址 字段发生了 无法解析 IP 网络 '10.0.0.2/33' 的问题`);
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
Address = 10.0.0.2/abc
`);
      })).assertEqual(`在 本地 的 局域网 IP 地址 字段发生了 无法解析数字 'abc' 的问题`);
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
Address = fc00::2/129
`);
      })).assertEqual(`在 本地 的 局域网 IP 地址 字段发生了 无法解析 IP 网络 'fc00::2/129' 的问题`);
    });

    it('Config: 路由段（AllowedIPs）无法解析', 0, () => {
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
PublicKey = ${KEY2}
AllowedIPs = 0.0.0.0/0, nope
`);
      })).assertEqual(`在 远程 的 路由的 IP 地址 字段发生了 无法解析 IP 地址 'nope' 的问题`);
    });

    it('Config: DNS 条目分类（IP → 服务器；主机名 → 搜索域名；其余报错）', 0, () => {
      const config = Config.parse(`[Interface]
PrivateKey = ${KEY1}
DNS = 1.1.1.1, 2001:db8::1, example.com, my-host.example.org
`);
      expect(config.interface.dnsServers).assertDeepEquals(['1.1.1.1', '2001:db8::1']);
      expect(config.interface.dnsSearchDomains).assertDeepEquals(['example.com', 'my-host.example.org']);
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}
DNS = not_a_hostname!
`);
      })).assertEqual(`在 本地 的 DNS 服务器 字段发生了 无法解析 IP 地址 'not_a_hostname!' 的问题`);
    });

    it('Config: 对端（域名 / IPv4 / [IPv6] / 端口 0 / 各类非法）', 0, () => {
      expect(InetEndpoint.parse('vpn.example.com:51820').toString()).assertEqual('vpn.example.com:51820');
      expect(InetEndpoint.parse('1.2.3.4:51820').toString()).assertEqual('1.2.3.4:51820');
      expect(InetEndpoint.parse('[2001:db8::1]:51820').toString()).assertEqual('[2001:db8::1]:51820');
      expect(InetEndpoint.parse('[::1]:0').port).assertEqual(0);
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
PublicKey = ${KEY2}
Endpoint = vpn.example.com
`);
      })).assertEqual(`在 远程 的 对端 字段发生了 无法解析对端 'vpn.example.com' 的问题`);
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
PublicKey = ${KEY2}
Endpoint = foo@bar.com:51820
`);
      })).assertEqual(`在 远程 的 对端 字段发生了 无法解析对端 'foo@bar.com:51820' 的问题`);
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
PublicKey = ${KEY2}
Endpoint = 1.2.3.4:65536
`);
      })).assertEqual(`在 远程 的 对端 字段发生了 无法解析对端 '1.2.3.4:65536' 的问题`);
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
PublicKey = ${KEY2}
Endpoint = 1.2.3.4:51a
`);
      })).assertEqual(`在 远程 的 对端 字段发生了 无法解析对端 '1.2.3.4:51a' 的问题`);
    });

    it('Config: 连接保活间隔', 0, () => {
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
PublicKey = ${KEY2}
PersistentKeepalive = 65536
`);
      })).assertEqual('在 远程 的 连接保活间隔 字段发生了 数值无效 的问题：必须为 0–65535 的整数');
      expect(messageOf(() => {
        Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
PublicKey = ${KEY2}
PersistentKeepalive = x
`);
      })).assertEqual('在 远程 的 连接保活间隔 字段发生了 数字无效 的问题');
      const zero = Config.parse(`[Interface]
PrivateKey = ${KEY1}

[Peer]
PublicKey = ${KEY2}
PersistentKeepalive = 0
`);
      expect(zero.peers[0].persistentKeepalive).assertEqual(0);
    });

    // ---------- 序列化 ----------

    it('Config: 序列化往返幂等且键名标准', 0, () => {
      const text = `[Interface]
PrivateKey = ${KEY1}
Address = 10.0.0.2/32, fc00::2/128
DNS = 1.1.1.1, example.com
ListenPort = 51820
MTU = 1420

[Peer]
PublicKey = ${KEY2}
PresharedKey = ${KEY3}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = vpn.example.com:51820
PersistentKeepalive = 25
`;
      const first = Config.parse(text);
      const serialized = first.toWgQuickString();
      const second = Config.parse(serialized);
      expect(second.toWgQuickString()).assertEqual(serialized);
      expect(serialized.includes(`PresharedKey = ${KEY3}`)).assertTrue();
      expect(serialized.includes(`PrivateKey = ${KEY1}`)).assertTrue();
      expect(serialized.includes('[Interface]')).assertTrue();
      expect(serialized.includes('[Peer]')).assertTrue();
      expect(serialized.includes('DNS = 1.1.1.1, example.com')).assertTrue();
    });

    it('Config: 仅搜索域名时也输出 DNS 行（上游缺陷修正）', 0, () => {
      const config = Config.parse(`[Interface]
PrivateKey = ${KEY1}
DNS = example.com
`);
      expect(config.interface.dnsServers.length).assertEqual(0);
      expect(config.interface.dnsSearchDomains.length).assertEqual(1);
      const serialized = config.toWgQuickString();
      expect(serialized.includes('DNS = example.com')).assertTrue();
      const roundTrip = Config.parse(serialized);
      expect(roundTrip.interface.dnsSearchDomains[0]).assertEqual('example.com');
    });

    it('Config: validate() 复用解析规则（编辑器保存校验）', 0, () => {
      const okInterface = new Interface();
      okInterface.privateKey = KEY1;
      expect(interfaceValidationMessage(okInterface)).assertEqual('__NO_ERROR__');

      const noKey = new Interface();
      noKey.privateKey = '';
      expect(interfaceValidationMessage(noKey)).assertEqual('在 本地 的 私钥 字段发生了 缺失属性 的问题');

      const badPort = new Interface();
      badPort.privateKey = KEY1;
      badPort.listenPort = 70000;
      expect(interfaceValidationMessage(badPort))
        .assertEqual('在 本地 的 监听端口 字段发生了 数值无效 的问题：必须为有效的 UDP 端口号');

      const okPeer = new Peer();
      okPeer.publicKey = KEY2;
      okPeer.allowedIPs = [InetNetwork.parse('0.0.0.0/0')];
      okPeer.endpoint = InetEndpoint.parse('vpn.example.com:51820');
      okPeer.persistentKeepalive = 25;
      expect(peerValidationMessage(okPeer)).assertEqual('__NO_ERROR__');

      const noPublicKey = new Peer();
      expect(peerValidationMessage(noPublicKey)).assertEqual('在 远程 的 公钥 字段发生了 缺失属性 的问题');

      const interfaceForConfig = new Interface();
      interfaceForConfig.privateKey = KEY1;
      expect(validationMessage(new Config(interfaceForConfig, [okPeer]))).assertEqual('__NO_ERROR__');
      expect(validationMessage(new Config(interfaceForConfig, [noPublicKey])))
        .assertEqual('在 远程 的 公钥 字段发生了 缺失属性 的问题');
    });

    // ---------- 工具类型 ----------

    it('InetNetwork: 掩码缺省补全、equals、IPv6 上限', 0, () => {
      expect(InetNetwork.parse('10.0.0.2').toString()).assertEqual('10.0.0.2/32');
      expect(InetNetwork.parse('fc00::2').toString()).assertEqual('fc00::2/128');
      expect(InetNetwork.parse('10.0.0.0/8').equals(InetNetwork.parse('10.0.0.0/8'))).assertTrue();
      expect(InetNetwork.parse('10.0.0.0/8').equals(InetNetwork.parse('10.0.0.0/9'))).assertFalse();
      expect(InetNetwork.parse('10.0.0.0/8').isIpv4).assertTrue();
      expect(InetNetwork.parse('fc00::/7').isIpv4).assertFalse();
      expect(throwsAnything(() => {
        InetNetwork.parse('10.0.0.0/33');
      })).assertTrue();
      expect(throwsAnything(() => {
        InetNetwork.parse('');
      })).assertTrue();
      expect(isBadConfig(() => {
        InetNetwork.parse('10.0.0.0/33');
      })).assertFalse();
    });

    it('InetAddresses: IPv4 / IPv6 / 主机名判定', 0, () => {
      expect(isIpv4('1.2.3.4')).assertTrue();
      expect(isIpv4('0.0.0.0')).assertTrue();
      expect(isIpv4('255.255.255.255')).assertTrue();
      expect(isIpv4('256.1.1.1')).assertFalse();
      expect(isIpv4('1.2.3')).assertFalse();
      expect(isIpv4('1.2.3.4.5')).assertFalse();
      expect(isIpv4('01.2.3.4')).assertFalse();
      expect(isIpv4('a.b.c.d')).assertFalse();
      expect(isIpv6('::1')).assertTrue();
      expect(isIpv6('::')).assertTrue();
      expect(isIpv6('2001:db8::1')).assertTrue();
      expect(isIpv6('1:2:3:4:5:6:7:8')).assertTrue();
      expect(isIpv6('1:2:3:4:5:6:7:8:9')).assertFalse();
      expect(isIpv6('::ffff:1.2.3.4')).assertTrue();
      expect(isIpv6('fe80::1%eth0')).assertTrue();
      expect(isIpv6('gggg::1')).assertFalse();
      expect(isIpv6('1::2::3')).assertFalse();
      expect(isHostname('example.com')).assertTrue();
      expect(isHostname('my-host.example.org.')).assertTrue();
      expect(isHostname('my_host')).assertFalse();
      expect(isHostname('a')).assertTrue();
      expect(isHostname(repeatChar('a', 256))).assertFalse();
    });

    // ---------- 名称规则与排序 ----------

    it('Names: 隧道名称规则', 0, () => {
      expect(isValidTunnelName('wg0')).assertTrue();
      expect(isValidTunnelName('A1_b=c+d-e.f')).assertTrue();
      expect(isValidTunnelName(repeatChar('a', 15))).assertTrue();
      expect(isValidTunnelName(repeatChar('a', 16))).assertFalse();
      expect(isValidTunnelName('')).assertFalse();
      expect(isValidTunnelName('中文')).assertFalse();
      expect(isValidTunnelName('a b')).assertFalse();
      expect(isValidTunnelName('a/b')).assertFalse();
      expect(isValidTunnelName('wg0 ')).assertFalse();
    });

    it('Names: 自然排序', 0, () => {
      expect(compareTunnelNames('wg2', 'wg10') < 0).assertTrue();
      expect(compareTunnelNames('wg10', 'wg2') > 0).assertTrue();
      expect(compareTunnelNames('wg2', 'wg2')).assertEqual(0);
      expect(compareTunnelNames('WG2', 'wg10') < 0).assertTrue();
      expect(compareTunnelNames('wg02', 'wg2') < 0).assertTrue();
      expect(compareTunnelNames('wg', 'wg0') < 0).assertTrue();
      expect(compareTunnelNames('WG2', 'wg2') < 0).assertTrue();
      const names = ['wg10', 'wg2', 'wg1'];
      names.sort((a: string, b: string): number => compareTunnelNames(a, b));
      expect(names).assertDeepEquals(['wg1', 'wg2', 'wg10']);
    });

    // ---------- 排除局域网 ----------

    it('PrivateNetworks: 公网段常量与 DNS 路由', 0, () => {
      expect(PUBLIC_NETWORKS_V4.length).assertEqual(30);
      expect(PUBLIC_NETWORKS_V4[0]).assertEqual('0.0.0.0/5');
      expect(PUBLIC_NETWORKS_V4[29]).assertEqual('208.0.0.0/4');
      expect(IPV4_WILDCARD).assertEqual('0.0.0.0/0');
      expect(dnsRoutesFor(['1.1.1.1', 'example.com', ' 8.8.8.8 ']))
        .assertDeepEquals(['1.1.1.1/32', '8.8.8.8/32']);
    });

    it('PrivateNetworks: 展开 / 等价判定 / 折叠', 0, () => {
      const expanded = expandExcludeLan([IPV4_WILDCARD], ['1.1.1.1', 'example.com']);
      expect(expanded.length).assertEqual(31);
      expect(expanded.includes('1.1.1.1/32')).assertTrue();
      expect(expanded.includes('example.com/32')).assertFalse();
      expect(isExcludeLanExpanded(expanded)).assertTrue();
      expect(isExcludeLanExpanded([IPV4_WILDCARD])).assertFalse();
      expect(isExcludeLanExpanded(PUBLIC_NETWORKS_V4.slice(0, 29))).assertFalse();
      expect(isExcludeLanApplicable([IPV4_WILDCARD], 1)).assertTrue();
      expect(isExcludeLanApplicable(expanded, 1)).assertTrue();
      expect(isExcludeLanApplicable([IPV4_WILDCARD], 2)).assertFalse();
      expect(isExcludeLanApplicable(['10.0.0.0/8'], 1)).assertFalse();
      expect(collapseExcludeLan(expanded, ['1.1.1.1'])).assertDeepEquals([IPV4_WILDCARD]);
    });

    it('PrivateNetworks: 展开保留其他路由段', 0, () => {
      const expanded = expandExcludeLan([IPV4_WILDCARD, '::/0'], []);
      expect(expanded.length).assertEqual(31);
      expect(expanded.includes('::/0')).assertTrue();
      expect(isExcludeLanExpanded(expanded)).assertTrue();
    });

    it('PrivateNetworks: DNS 变化时同步 /32 路由', 0, () => {
      const allowed = expandExcludeLan([IPV4_WILDCARD], ['1.1.1.1']);
      const synced = syncLanDnsRoutes(allowed, ['1.1.1.1'], ['8.8.8.8', 'example.com']);
      expect(synced.includes('1.1.1.1/32')).assertFalse();
      expect(synced.includes('8.8.8.8/32')).assertTrue();
      expect(synced.includes('example.com/32')).assertFalse();
      expect(synced.length).assertEqual(31);
    });
  });
}
