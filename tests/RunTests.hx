package;

import tink.testrunner.Runner;

class RunTests {
  static function main() {
    HttpbinConfig.bootstrapSslCa();

    switch MatrixCli.parse() {
      case Failure(e):
        fail(e.message);
      case Success(config):
        switch SuiteAsm.build(config) {
          case Failure(e):
            fail(e.message);
          case Success(tests):
            Runner.run(tests).handle(Runner.exit);
        }
    }
  }

  static function fail(message:String):Void {
    Sys.println(message);
    if (message.indexOf('Test matrix flags') == -1) {
      Sys.println('');
      Sys.println(MatrixCli.help());
    }
    Sys.exit(1);
  }
}
