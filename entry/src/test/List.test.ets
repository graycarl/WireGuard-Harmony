import localUnitTest from './LocalUnit.test';
import repoTest from './Repo.test';

export default function testsuite() {
  localUnitTest();
  repoTest();
}
