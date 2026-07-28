import haxe.io.Input;
import sys.io.Process;
import neko.vm.Thread;
import haxe.io.Eof;

class ProcessTools {

  static final DUMMY_SERVER_HXML = 'dummy-server.hxml';

  public static function streamAll(cmd: String, ?args: Array<String>): Process {
    final process = new Process(cmd, args);
    stream(process.stderr);
    stream(process.stdout);
    return process;
  }

  /**
   * Run Travix for `target` with extra hxml-style args.
   * Never rewrites `tests.hxml`, `tests.runner.hxml`, or `dummy-server.hxml`.
   * DummyServer builds set `TRAVIX_HXML=dummy-server.hxml` so Travix uses that
   * entry instead of the committed runner baseline.
   */
  public static function travix(target: String, args: Array<String>): Process {
    if (isDummyServer(args)) {
      Sys.putEnv('TRAVIX_HXML', DUMMY_SERVER_HXML);
      return streamAll('lix', ['run', 'travix', target].concat(flattenArgs(dummyServerExtraArgs(args))));
    }

    Sys.putEnv('TRAVIX_HXML', '');
    return streamAll('lix', ['run', 'travix', target].concat(flattenArgs(args)));
  }

  static function isDummyServer(args: Array<String>): Bool {
    for (a in args)
      if (a.indexOf('DummyServer') >= 0)
        return true;
    return false;
  }

  static function dummyServerExtraArgs(args: Array<String>): Array<String> {
    final out = [];
    for (a in args) {
      final t = StringTools.trim(a);
      if (t.length == 0)
        continue;
      if (t == '-main DummyServer' || StringTools.startsWith(t, '-main '))
        continue;
      if (t == '-lib tink_http_middleware')
        continue;
      if (StringTools.startsWith(t, '-cp'))
        continue;
      out.push(t);
    }
    return out;
  }

  static function flattenArgs(lines: Array<String>): Array<String> {
    final out = [];
    for (line in lines) {
      final trimmed = StringTools.trim(line);
      if (trimmed.length == 0)
        continue;
      final idx = trimmed.indexOf(' ');
      if (idx < 0)
        out.push(trimmed);
      else {
        out.push(trimmed.substr(0, idx));
        out.push(StringTools.trim(trimmed.substr(idx + 1)));
      }
    }
    return out;
  }

  static function stream(input: Input): Void {
    final stdout = Sys.stdout();
    Thread.create(() -> {
      while (true)
        try
          Sys.println(input.readLine())
        catch (e: Eof)
          break;
    });
  }

}
