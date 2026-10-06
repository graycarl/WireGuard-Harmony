/**
 * 数据面 NAPI 接口（薄控制面，见 docs/decisions/0002）。
 */

/** 启动数据面：tunFd 为 vpnConnection.create() 返回的虚拟网卡 fd；configJson 为结构化隧道配置。返回 0 成功，<0 错误码。 */
export const startTunnel: (tunFd: number, configJson: string) => number;

/** 停止数据面并释放会话/线程。 */
export const stopTunnel: () => void;

/** 数据面版本串（冒烟验证用）。 */
export const getVersion: () => string;
