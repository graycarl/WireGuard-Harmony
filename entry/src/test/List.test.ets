import localUnitTest from './LocalUnit.test';
import cryptoTest from './Crypto.test';
import repoTest from './Repo.test';
import configTest from './Config.test';

export default function testsuite() {
  localUnitTest();
  cryptoTest();
  repoTest();
  configTest();
}
