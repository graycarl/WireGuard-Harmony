import { describe, it, expect } from '@ohos/hypium';
import {
  ImportFileKind, baseName, classifyFileName, deriveTunnelName, fileExtension,
  importParseFailure, isImageFileName, nameValidationError, sanitizeTunnelName,
  singleImportSuccess, summarizeBatch
} from '../main/ets/services/ImportLogic';

export default function importLogicTest() {
  describe('ImportLogic', () => {
    it('fileExtension / baseName / deriveTunnelName', 0, () => {
      expect(fileExtension('wg0.conf')).assertEqual('conf');
      expect(fileExtension('a/b/wg0.CONF')).assertEqual('conf');
      expect(fileExtension('photo.png')).assertEqual('png');
      expect(fileExtension('noext')).assertEqual('');
      expect(baseName('file://docs/storage/Users/currentUser/Documents/wg0.conf')).assertEqual('wg0.conf');
      expect(baseName('file://docs/a%20b.conf')).assertEqual('a b.conf');
      expect(deriveTunnelName('wg0.conf')).assertEqual('wg0');
      expect(deriveTunnelName('my.vpn.zip')).assertEqual('my.vpn');
      expect(deriveTunnelName('noext')).assertEqual('noext');
    });

    it('文件类型判定：图片优先于扩展名', 0, () => {
      expect(classifyFileName('shot.png')).assertEqual(ImportFileKind.IMAGE);
      expect(classifyFileName('wg0.conf')).assertEqual(ImportFileKind.CONF);
      expect(classifyFileName('bundle.zip')).assertEqual(ImportFileKind.ZIP);
      expect(classifyFileName('x.txt')).assertEqual(ImportFileKind.UNKNOWN);
      expect(isImageFileName('a.jpeg')).assertEqual(true);
      expect(isImageFileName('a.zip')).assertEqual(false);
    });

    it('sanitizeTunnelName：仅保留合法字符并截断 15', 0, () => {
      expect(sanitizeTunnelName('我的隧道wg0')).assertEqual('wg0');
      expect(sanitizeTunnelName('wg 0!@#')).assertEqual('wg0');
      expect(sanitizeTunnelName('abcdefghijklmnopqrstuvwxyz')).assertEqual('abcdefghijklmno');
      expect(sanitizeTunnelName('a_b-c=d+e.f')).assertEqual('a_b-c=d+e.f');
    });

    it('nameValidationError：非法/重名/通过', 0, () => {
      expect(nameValidationError('wg0', ['wg1'])).assertEqual(null);
      expect(nameValidationError('', ['wg1'])).assertEqual('名称无效');
      expect(nameValidationError('中文名', [])).assertEqual('名称无效');
      expect(nameValidationError('abcdefghijklmnop', [])).assertEqual('名称无效');
      expect(nameValidationError('wg0', ['wg0'])).assertEqual("名称 'wg0' 已存在");
    });

    it('summarizeBatch：全部成功/部分成功/全部失败/未找到配置', 0, () => {
      expect(summarizeBatch(['wg0'], [])).assertEqual("导入了 'wg0'");
      expect(summarizeBatch(['wg0', 'wg1'], [])).assertEqual('导入了 2 个隧道');
      expect(summarizeBatch([], [])).assertEqual('无法导入隧道：未找到配置');
      expect(summarizeBatch([], [importParseFailure('缺少节')]))
        .assertEqual('无法导入隧道：缺少节');
      expect(summarizeBatch(['wg0'], [importParseFailure('缺少节'), '无法导入隧道：名称无效']))
        .assertEqual('导入了 3 项中的 1 项，无法导入隧道：名称无效');
    });

    it('单条提示文案', 0, () => {
      expect(singleImportSuccess('wg0')).assertEqual("导入了 'wg0'");
      expect(importParseFailure('密钥长度错误')).assertEqual('无法导入隧道：密钥长度错误');
    });
  });
}
