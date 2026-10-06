import localUnitTest from './LocalUnit.test';
import cryptoTest from './Crypto.test';
import repoTest from './Repo.test';

export default function testsuite() {
  localUnitTest();
  cryptoTest();
  repoTest();
}
