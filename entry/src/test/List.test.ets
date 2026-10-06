import localUnitTest from './LocalUnit.test';
import cryptoTest from './Crypto.test';

export default function testsuite() {
  localUnitTest();
  cryptoTest();
}