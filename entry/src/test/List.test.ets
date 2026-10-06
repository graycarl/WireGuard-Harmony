import localUnitTest from './LocalUnit.test';
import cryptoTest from './Crypto.test';
import repoTest from './Repo.test';
import configTest from './Config.test';
import recordMapperTest from './RecordMapper.test';
import formatTest from './Format.test';
import ipcProtocolTest from './IpcProtocol.test';
import editorUtilsTest from './EditorUtils.test';

export default function testsuite() {
  localUnitTest();
  cryptoTest();
  repoTest();
  configTest();
  recordMapperTest();
  formatTest();
  ipcProtocolTest();
  editorUtilsTest();
}
