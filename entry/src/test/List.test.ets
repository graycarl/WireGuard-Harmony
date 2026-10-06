import localUnitTest from './LocalUnit.test';
import configTest from './Config.test';

export default function testsuite() {
  localUnitTest();
  configTest();
}
