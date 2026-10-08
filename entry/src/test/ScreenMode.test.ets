import { describe, it, expect } from '@ohos/hypium';
import {
  COMPACT_MAX_HEIGHT_VP,
  COMPACT_MAX_WIDTH_VP,
  Dimens,
  isCompactWindow
} from '../main/ets/util/ScreenMode';

export default function screenModeTest() {
  describe('ScreenMode', () => {
    it('判定：高度为主判据（外屏/横屏/小窗的共同特征是矮）', 0, () => {
      // 常规手机竖屏（高 ≥ 640vp）不触发
      expect(isCompactWindow(360, 780)).assertFalse();
      expect(isCompactWindow(430, 900)).assertFalse();
      // 阔折叠外屏（约 356–392vp 见方）触发
      expect(isCompactWindow(392, 392)).assertTrue();
      expect(isCompactWindow(356, 356)).assertTrue();
      // 手机横屏（矮）触发
      expect(isCompactWindow(780, 360)).assertTrue();
      // 悬浮小窗（又窄又矮）触发
      expect(isCompactWindow(320, 400)).assertTrue();
      // 折叠屏展开竖屏（宽且高）不触发
      expect(isCompactWindow(528, 848)).assertFalse();
    });

    it('判定：阈值边界', 0, () => {
      expect(isCompactWindow(400, COMPACT_MAX_HEIGHT_VP)).assertFalse();
      expect(isCompactWindow(400, COMPACT_MAX_HEIGHT_VP - 1)).assertTrue();
      expect(isCompactWindow(COMPACT_MAX_WIDTH_VP, 800)).assertFalse();
      expect(isCompactWindow(COMPACT_MAX_WIDTH_VP - 1, 800)).assertTrue();
    });

    it('尺寸档位：紧凑各项均收紧，常规保持原值', 0, () => {
      const normal = new Dimens(false);
      const compact = new Dimens(true);
      // 常规档位保持适配前的设计值
      expect(normal.pagePadding).assertEqual(16);
      expect(normal.titleBarHeight).assertEqual(56);
      expect(normal.rowHeight).assertEqual(56);
      expect(normal.titleFont).assertEqual(24);
      expect(normal.headerFont).assertEqual(18);
      expect(normal.fieldLabelWidth).assertEqual(120);
      expect(normal.editorLabelWidth).assertEqual(92);
      expect(normal.cardPadding).assertEqual(16);
      expect(normal.fieldRowVPad).assertEqual(8);
      expect(normal.editorRowVPad).assertEqual(6);
      expect(normal.editorCardPadding).assertEqual(12);
      expect(normal.fabSize).assertEqual(56);
      expect(normal.fabMargin).assertEqual(24);
      // 紧凑档位全部收紧（不增大任何一项）
      expect(compact.pagePadding < normal.pagePadding).assertTrue();
      expect(compact.titleBarHeight < normal.titleBarHeight).assertTrue();
      expect(compact.rowHeight < normal.rowHeight).assertTrue();
      expect(compact.titleFont < normal.titleFont).assertTrue();
      expect(compact.headerFont < normal.headerFont).assertTrue();
      expect(compact.fieldLabelWidth < normal.fieldLabelWidth).assertTrue();
      expect(compact.editorLabelWidth < normal.editorLabelWidth).assertTrue();
      expect(compact.cardPadding < normal.cardPadding).assertTrue();
      expect(compact.fieldRowVPad < normal.fieldRowVPad).assertTrue();
      expect(compact.editorRowVPad < normal.editorRowVPad).assertTrue();
      expect(compact.editorCardPadding < normal.editorCardPadding).assertTrue();
      expect(compact.fabSize < normal.fabSize).assertTrue();
      expect(compact.fabMargin < normal.fabMargin).assertTrue();
    });
  });
}
