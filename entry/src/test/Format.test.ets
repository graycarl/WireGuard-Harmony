import { describe, it, expect } from '@ohos/hypium';
import { formatBytes, formatTimeAgo } from '../main/ets/util/Format';

const NOW = 1700000000000;

export default function formatTest() {
  describe('Format', () => {
    it('formatBytes 单位边界与小数位', 0, () => {
      expect(formatBytes(0)).assertEqual('0 B');
      expect(formatBytes(1023)).assertEqual('1023 B');
      expect(formatBytes(1024)).assertEqual('1.00 KiB');
      expect(formatBytes(1536)).assertEqual('1.50 KiB');
      expect(formatBytes(1024 * 1024)).assertEqual('1.00 MiB');
      expect(formatBytes(1024 * 1024 + 512 * 1024)).assertEqual('1.50 MiB');
      expect(formatBytes(1024 * 1024 * 1024)).assertEqual('1.00 GiB');
      expect(formatBytes(1024 * 1024 * 1024 * 1024)).assertEqual('1.00 TiB');
      expect(formatBytes(-5)).assertEqual('0 B');
    });

    it('formatTimeAgo 逐段拼接', 0, () => {
      expect(formatTimeAgo(NOW - 267000, NOW)).assertEqual('4 分钟 27 秒之前');
      expect(formatTimeAgo(NOW - 90000, NOW)).assertEqual('1 分钟 30 秒之前');
      expect(formatTimeAgo(NOW - 1000, NOW)).assertEqual('1 秒之前');
      expect(formatTimeAgo(NOW - 3600000, NOW)).assertEqual('1 小时之前');
      expect(formatTimeAgo(NOW - 86400000, NOW)).assertEqual('1 天之前');
      expect(formatTimeAgo(NOW - 86400000 - 5000, NOW)).assertEqual('1 天 5 秒之前');
      expect(formatTimeAgo(NOW - 90000 * 1000, NOW)).assertEqual('1 天 1 小时之前');
    });

    it('formatTimeAgo 未来/相同 → 现在', 0, () => {
      expect(formatTimeAgo(NOW, NOW)).assertEqual('现在');
      expect(formatTimeAgo(NOW + 5000, NOW)).assertEqual('现在');
    });
  });
}
