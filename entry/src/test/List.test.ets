import localUnitTest from './LocalUnit.test';
import cryptoTest from './Crypto.test';
import repoTest from './Repo.test';
import configTest from './Config.test';
import recordMapperTest from './RecordMapper.test';
import formatTest from './Format.test';
import ipcProtocolTest from './IpcProtocol.test';
import tunnelDisplayTest from './TunnelDisplay.test';
import editorUtilsTest from './EditorUtils.test';
import importLogicTest from './ImportLogic.test';
import x25519Test from './X25519.test';
import screenModeTest from './ScreenMode.test';

export default function testsuite() {
  localUnitTest();
  cryptoTest();
  repoTest();
  configTest();
  recordMapperTest();
  formatTest();
  ipcProtocolTest();
  tunnelDisplayTest();
  editorUtilsTest();
  importLogicTest();
  x25519Test();
  screenModeTest();
}
