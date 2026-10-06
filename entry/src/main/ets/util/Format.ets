/*
 * 展示格式化工具（纯逻辑，禁 import @kit）。
 *
 * - formatBytes：specs/tunnel-detail.md「流量」——B 为整数，KiB/MiB/GiB/TiB 保留两位小数；
 * - formatTimeAgo：specs/tunnel-detail.md「上次握手时间」——按「天/小时/分钟/秒」逐段拼接
 *   后加「之前」，未来或相同显示「现在」。
 *   逐段规则对齐上游 ui/.../util/QuantityFormatter.kt#formatEpochAgo：从大到小
 *   逐步扣减，只有剩余时长达到该单位阈值才输出该段（因此 1 天 0 时 0 分 5 秒 → 「1 天 5 秒之前」）。
 */

const SECONDS_PER_MINUTE = 60;
const SECONDS_PER_HOUR = 60 * 60;
const SECONDS_PER_DAY = 24 * 60 * 60;

/** 人类可读字节数。 */
export function formatBytes(bytes: number): string {
  const value = Number.isFinite(bytes) ? Math.max(0, Math.floor(bytes)) : 0;
  if (value < 1024) {
    return `${value} B`;
  }
  if (value < 1024 * 1024) {
    return `${(value / 1024).toFixed(2)} KiB`;
  }
  if (value < 1024 * 1024 * 1024) {
    return `${(value / (1024 * 1024)).toFixed(2)} MiB`;
  }
  if (value < 1024 * 1024 * 1024 * 1024) {
    return `${(value / (1024 * 1024 * 1024)).toFixed(2)} GiB`;
  }
  return `${(value / (1024 * 1024 * 1024 * 1024)).toFixed(2)} TiB`;
}

/** 相对时间：`lastHandshakeMs` 距 `nowMs` 的「X 之前」。 */
export function formatTimeAgo(lastHandshakeMs: number, nowMs: number): string {
  if (!Number.isFinite(lastHandshakeMs) || !Number.isFinite(nowMs)) {
    return '现在';
  }
  let span = Math.floor((nowMs - lastHandshakeMs) / 1000);
  if (span <= 0) {
    return '现在';
  }
  const parts: string[] = [];
  if (span >= SECONDS_PER_DAY) {
    const days = Math.floor(span / SECONDS_PER_DAY);
    parts.push(`${days} 天`);
    span -= days * SECONDS_PER_DAY;
  }
  if (span >= SECONDS_PER_HOUR) {
    const hours = Math.floor(span / SECONDS_PER_HOUR);
    parts.push(`${hours} 小时`);
    span -= hours * SECONDS_PER_HOUR;
  }
  if (span >= SECONDS_PER_MINUTE) {
    const minutes = Math.floor(span / SECONDS_PER_MINUTE);
    parts.push(`${minutes} 分钟`);
    span -= minutes * SECONDS_PER_MINUTE;
  }
  if (span > 0) {
    parts.push(`${span} 秒`);
  }
  return `${parts.join(' ')}之前`;
}
