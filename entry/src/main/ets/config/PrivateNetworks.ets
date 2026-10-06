/*
 * 「排除局域网」的地址段展开/折叠（specs/tunnel-editor.md）。
 *
 * 上游把这段逻辑放在 ui 层（PeerProxy.kt 的 IPV4_PUBLIC_NETWORKS），本项目按契约
 * docs/dev-contracts.md §3 下沉为 config/ 的纯函数，便于本地单测。
 *
 * 与上游的差异（tunnel-editor.md）：上游以「不含冒号」判定 IPv4 DNS 条目，
 * 会把搜索域名也补成 `域名/32`；本项目仅对真实 IPv4 字面量补入。
 */

import { isIpv4 } from './InetAddresses';

/** 0.0.0.0/0 等价的公网 IPv4 段（共 30 条，上游 PeerProxy.kt 同源）。 */
export const PUBLIC_NETWORKS_V4: string[] = [
  '0.0.0.0/5', '8.0.0.0/7', '11.0.0.0/8', '12.0.0.0/6', '16.0.0.0/4', '32.0.0.0/3',
  '64.0.0.0/2', '128.0.0.0/3', '160.0.0.0/5', '168.0.0.0/6', '172.0.0.0/12',
  '172.32.0.0/11', '172.64.0.0/10', '172.128.0.0/9', '173.0.0.0/8', '174.0.0.0/7',
  '176.0.0.0/4', '192.0.0.0/9', '192.128.0.0/11', '192.160.0.0/13', '192.169.0.0/16',
  '192.170.0.0/15', '192.172.0.0/14', '192.176.0.0/12', '192.192.0.0/10',
  '193.0.0.0/8', '194.0.0.0/7', '196.0.0.0/6', '200.0.0.0/5', '208.0.0.0/4',
];

export const IPV4_WILDCARD = '0.0.0.0/0';

/** 依据 DNS 服务器中的 IPv4 字面量生成需要补入的 /32 主机路由。 */
export function dnsRoutesFor(dnsServers: string[]): string[] {
  const routes: string[] = [];
  for (const server of dnsServers) {
    const trimmed = server.trim();
    if (isIpv4(trimmed)) {
      const route = `${trimmed}/32`;
      if (!routes.includes(route)) {
        routes.push(route);
      }
    }
  }
  return routes;
}

/** 当前路由段是否已展开为完整公网段列表（且不含 0.0.0.0/0）。 */
export function isExcludeLanExpanded(allowedIPs: string[]): boolean {
  if (allowedIPs.includes(IPV4_WILDCARD)) {
    return false;
  }
  for (const network of PUBLIC_NETWORKS_V4) {
    if (!allowedIPs.includes(network)) {
      return false;
    }
  }
  return true;
}

/** 是否应显示「排除局域网」复选框（仅单个 Peer，且路由段包含通配或已展开）。 */
export function isExcludeLanApplicable(allowedIPs: string[], peerCount: number): boolean {
  if (peerCount !== 1) {
    return false;
  }
  if (allowedIPs.includes(IPV4_WILDCARD)) {
    return true;
  }
  return isExcludeLanExpanded(allowedIPs);
}

/** 勾选「排除局域网」：0.0.0.0/0 → 公网段列表，并补入 DNS 的 IPv4 /32 路由。 */
export function expandExcludeLan(allowedIPs: string[], dnsServers: string[]): string[] {
  const result: string[] = [];
  let replaced = false;
  for (const network of allowedIPs) {
    if (network === IPV4_WILDCARD) {
      if (!replaced) {
        for (const publicNetwork of PUBLIC_NETWORKS_V4) {
          if (!result.includes(publicNetwork)) {
            result.push(publicNetwork);
          }
        }
        replaced = true;
      }
    } else if (!result.includes(network)) {
      result.push(network);
    }
  }
  for (const route of dnsRoutesFor(dnsServers)) {
    if (!result.includes(route)) {
      result.push(route);
    }
  }
  return result;
}

/** 取消勾选：恢复 0.0.0.0/0 并移除自动补入的 DNS /32 路由。 */
export function collapseExcludeLan(allowedIPs: string[], dnsServers: string[]): string[] {
  const result: string[] = [];
  let replaced = false;
  for (const network of allowedIPs) {
    if (PUBLIC_NETWORKS_V4.includes(network)) {
      if (!replaced) {
        if (!result.includes(IPV4_WILDCARD)) {
          result.push(IPV4_WILDCARD);
        }
        replaced = true;
      }
    } else if (!result.includes(network)) {
      result.push(network);
    }
  }
  const routes = dnsRoutesFor(dnsServers);
  const filtered: string[] = [];
  for (const network of result) {
    if (!routes.includes(network)) {
      filtered.push(network);
    }
  }
  return filtered;
}

/** DNS 字段变化时同步自动补入的 /32 路由（对应上游 PeerProxy.setInterfaceDns）。 */
export function syncLanDnsRoutes(allowedIPs: string[], oldDnsServers: string[],
                                 newDnsServers: string[]): string[] {
  const oldRoutes = dnsRoutesFor(oldDnsServers);
  const newRoutes = dnsRoutesFor(newDnsServers);
  const result: string[] = [];
  for (const network of allowedIPs) {
    if (!oldRoutes.includes(network) || newRoutes.includes(network)) {
      if (!result.includes(network)) {
        result.push(network);
      }
    }
  }
  for (const route of newRoutes) {
    if (!result.includes(route)) {
      result.push(route);
    }
  }
  return result;
}
