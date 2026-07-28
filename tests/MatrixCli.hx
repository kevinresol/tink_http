package;

import tink.core.Error;
import tink.core.Noise;
import tink.core.Outcome;

/** Parsed matrix selection from fail-closed kebab-case `-D` flags. */
typedef MatrixConfig = {
  final suites:Array<MatrixSuite>;
  final clients:Array<MatrixClient>;
  final endpoints:Array<MatrixEndpoint>;
  final cases:MatrixCases;
  final port:Null<Int>;
}

enum MatrixSuite {
  Unit;
  Client;
  Container;
}

enum MatrixClient {
  Node;
  Socket;
  Curl;
  Js;
  JsFetch;
  Tcp;
  Flash;
}

enum MatrixEndpoint {
  Httpbin;
  HttpbinSecure;
  Local;
}

enum MatrixCases {
  All;
  Selected(ids:Array<String>);
}

/**
  Fail-closed parser for test-matrix `-D` flags (`suites`, `clients`, `endpoints`, `cases`, `port`).
  Call sites land in M3; this module only parses and validates.
**/
class MatrixCli {
  static final KEBAB:EReg = new EReg('^[a-z][a-z0-9]*(-[a-z0-9]+)*$', '');
  static final HAS_UPPER:EReg = new EReg('[A-Z]', '');

  public static function help():String {
    return [
      'Test matrix flags (kebab-case only):',
      '  -D suites=unit|client|container[,...]',
      '  -D clients=node|socket|curl|js|js-fetch|tcp|flash[,...]',
      '  -D endpoints=httpbin|httpbin-secure|local[,...]',
      '  -D cases=all|<kebab-case-id>[,...]',
      '  -D port=<int>   (required for suites=container)',
      '',
      'Lane x endpoint:',
      '  unit       - endpoints omitted/ignored (no network)',
      '  client     - endpoints: httpbin and/or httpbin-secure (not local)',
      '  container  - endpoints: local only; requires port; clients=node',
      '',
      'Reserved (not implemented): suites=smoke; clients=std, local-container',
    ].join('\n');
  }

  public static function parse():Outcome<MatrixConfig, Error> {
    final suitesRaw = Env.getDefine('suites');
    final clientsRaw = Env.getDefine('clients');
    final endpointsRaw = Env.getDefine('endpoints');
    final casesRaw = Env.getDefine('cases');
    final portRaw = Env.getDefine('port');

    return switch parseSuites(suitesRaw) {
      case Failure(e): Failure(e);
      case Success(suites):
        final wantsClient = suites.indexOf(Client) != -1;
        final wantsContainer = suites.indexOf(Container) != -1;
        final needsNetwork = wantsClient || wantsContainer;

        switch parseClients(clientsRaw, needsNetwork, wantsContainer) {
          case Failure(e): Failure(e);
          case Success(clients):
            switch parseEndpoints(endpointsRaw, wantsClient, wantsContainer) {
              case Failure(e): Failure(e);
              case Success(endpoints):
                switch parseCases(casesRaw, needsNetwork) {
                  case Failure(e): Failure(e);
                  case Success(cases):
                    switch parsePort(portRaw, wantsContainer) {
                      case Failure(e): Failure(e);
                      case Success(port):
                        Success({
                          suites: suites,
                          clients: clients,
                          endpoints: endpoints,
                          cases: cases,
                          port: port,
                        });
                    }
                }
            }
        }
    };
  }

  static function parseSuites(raw:Null<String>):Outcome<Array<MatrixSuite>, Error> {
    return switch splitRequired('suites', raw) {
      case Failure(e): Failure(e);
      case Success(tokens):
        final out:Array<MatrixSuite> = [];
        for (token in tokens) switch parseSuiteToken(token) {
          case Failure(e): return Failure(e);
          case Success(s):
            if (out.indexOf(s) == -1) out.push(s);
        }
        if (out.length == 0)
          return Failure(missing('suites'));
        Success(out);
    };
  }

  static function parseSuiteToken(token:String):Outcome<MatrixSuite, Error>
    return switch token {
      case 'unit': Success(Unit);
      case 'client': Success(Client);
      case 'container': Success(Container);
      case 'smoke':
        Failure(notImplemented('suites', token, 'smoke suite is reserved for a later chunk'));
      case _:
        Failure(unknownToken('suites', token, 'unit, client, container'));
    };

  static function parseClients(
    raw:Null<String>,
    required:Bool,
    wantsContainer:Bool
  ):Outcome<Array<MatrixClient>, Error> {
    if (!required) {
      if (raw == null || StringTools.trim(raw) == '') return Success([]);
      // Present but unused for unit-only: still validate tokens fail-closed.
    }
    return switch (required ? splitRequired('clients', raw) : splitOptional(raw)) {
      case Failure(e): Failure(e);
      case Success(tokens):
        if (required && tokens.length == 0)
          return Failure(missing('clients'));
        final out:Array<MatrixClient> = [];
        for (token in tokens) switch parseClientToken(token) {
          case Failure(e): return Failure(e);
          case Success(c):
            if (out.indexOf(c) == -1) out.push(c);
        }
        // Multi-suite (e.g. client,container): container still forces clients=node only.
        if (wantsContainer) {
          if (out.length != 1 || out[0] != Node)
            return Failure(err(
              'suites=container requires -D clients=node (probe is always NodeClient); got: ${tokens.join(',')}'
            ));
        }
        Success(out);
    };
  }

  static function parseClientToken(token:String):Outcome<MatrixClient, Error>
    return switch token {
      case 'node': Success(Node);
      case 'socket': Success(Socket);
      case 'curl': Success(Curl);
      case 'js': Success(Js);
      case 'js-fetch': Success(JsFetch);
      case 'tcp': Success(Tcp);
      case 'flash': Success(Flash);
      case 'std' | 'local-container':
        Failure(notImplemented('clients', token, 'supported later; use node, socket, curl, js, js-fetch, tcp, flash'));
      case _:
        Failure(unknownToken('clients', token, 'node, socket, curl, js, js-fetch, tcp, flash'));
    };

  static function parseEndpoints(
    raw:Null<String>,
    wantsClient:Bool,
    wantsContainer:Bool
  ):Outcome<Array<MatrixEndpoint>, Error> {
    final needsEndpoints = wantsClient || wantsContainer;
    if (!needsEndpoints) {
      // unit-only: omitted/ignored; if present, still reject unknown/PascalCase tokens.
      if (raw == null || StringTools.trim(raw) == '') return Success([]);
      return switch splitOptional(raw) {
        case Failure(e): Failure(e);
        case Success(tokens):
          for (token in tokens) switch parseEndpointToken(token) {
            case Failure(e): return Failure(e);
            case Success(_):
          }
          Success([]);
      };
    }

    return switch splitRequired('endpoints', raw) {
      case Failure(e): Failure(e);
      case Success(tokens):
        final out:Array<MatrixEndpoint> = [];
        for (token in tokens) switch parseEndpointToken(token) {
          case Failure(e): return Failure(e);
          case Success(ep):
            if (out.indexOf(ep) == -1) out.push(ep);
        }

        final hasHttpbin = out.indexOf(Httpbin) != -1;
        final hasSecure = out.indexOf(HttpbinSecure) != -1;
        final hasLocal = out.indexOf(Local) != -1;
        final hasPeer = hasHttpbin || hasSecure;

        if (wantsClient) {
          if (!hasPeer)
            return Failure(err(
              'suites=client requires endpoints httpbin and/or httpbin-secure; got: ${tokens.join(',')}'
            ));
          if (hasLocal && !wantsContainer)
            return Failure(err(
              'suites=client does not allow endpoints=local (use suites=container with endpoints=local)'
            ));
        }

        if (wantsContainer) {
          if (!hasLocal)
            return Failure(err(
              'suites=container requires endpoints=local; got: ${tokens.join(',')}'
            ));
          if (hasPeer && !wantsClient)
            return Failure(err(
              'suites=container allows only endpoints=local; got: ${tokens.join(',')}'
            ));
          // When both client + container: keep full list; callers filter per lane.
          if (!wantsClient && out.length != 1)
            return Failure(err(
              'suites=container requires endpoints=local only; got: ${tokens.join(',')}'
            ));
        }

        // Drop unused unit mention — endpoints list is the network selection.
        Success(out);
    };
  }

  static function parseEndpointToken(token:String):Outcome<MatrixEndpoint, Error>
    return switch token {
      case 'httpbin': Success(Httpbin);
      case 'httpbin-secure': Success(HttpbinSecure);
      case 'local': Success(Local);
      case _:
        Failure(unknownToken('endpoints', token, 'httpbin, httpbin-secure, local'));
    };

  static function parseCases(raw:Null<String>, required:Bool):Outcome<MatrixCases, Error> {
    if (!required) {
      if (raw == null || StringTools.trim(raw) == '') return Success(All);
      // Optional for unit-only until M5 documents defaults; validate if present.
    } else if (raw == null || StringTools.trim(raw) == '') {
      return Failure(missing('cases'));
    }

    return switch splitOptional(raw) {
      case Failure(e): Failure(e);
      case Success(tokens):
        if (tokens.length == 0) {
          if (required) return Failure(missing('cases'));
          return Success(All);
        }
        if (tokens.length == 1 && tokens[0] == 'all') return Success(All);
        final ids:Array<String> = [];
        for (token in tokens) {
          if (token == 'all')
            return Failure(err('cases=all cannot be combined with other case ids'));
          switch rejectNonKebab(token) {
            case Failure(e): return Failure(e);
            case Success(_):
          }
          if (ids.indexOf(token) == -1) ids.push(token);
        }
        Success(Selected(ids));
    };
  }

  static function parsePort(raw:Null<String>, wantsContainer:Bool):Outcome<Null<Int>, Error> {
    if (!wantsContainer) {
      if (raw == null || StringTools.trim(raw) == '') return Success(null);
      return switch parsePortValue(raw) {
        case Failure(e): Failure(e);
        case Success(p): Success(p); // ignored by unit/client lanes
      };
    }
    if (raw == null || StringTools.trim(raw) == '')
      return Failure(err('suites=container requires -D port=<int>'));
    return switch parsePortValue(raw) {
      case Failure(e): Failure(e);
      case Success(p): Success(p);
    };
  }

  static function parsePortValue(raw:String):Outcome<Int, Error> {
    final trimmed = StringTools.trim(raw);
    final n = Std.parseInt(trimmed);
    if (n == null || Std.string(n) != trimmed || n <= 0)
      return Failure(err('Invalid -D port=$raw (expected positive integer)'));
    return Success(n);
  }

  static function splitRequired(flag:String, raw:Null<String>):Outcome<Array<String>, Error> {
    if (raw == null || StringTools.trim(raw) == '') return Failure(missing(flag));
    return splitOptional(raw);
  }

  static function splitOptional(raw:Null<String>):Outcome<Array<String>, Error> {
    if (raw == null) return Success([]);
    final parts = raw.split(',');
    final out:Array<String> = [];
    for (part in parts) {
      final token = StringTools.trim(part);
      if (token == '') continue;
      switch rejectNonKebab(token) {
        case Failure(e): return Failure(e);
        case Success(_):
      }
      out.push(token);
    }
    return Success(out);
  }

  /** Reject PascalCase / non-kebab before unknown-token messages. */
  static function rejectNonKebab(token:String):Outcome<Noise, Error> {
    if (KEBAB.match(token)) return Success(Noise);
    if (HAS_UPPER.match(token))
      return Failure(err(
        'PascalCase / mixed-case not allowed (`$token`); use kebab-case (e.g. js-fetch, httpbin-secure)'
      ));
    return Failure(err(
      'Invalid token `$token`; use kebab-case (lowercase letters, digits, hyphens)'
    ));
  }

  static function unknownToken(flag:String, token:String, allowed:String):Error
    return err('Unknown -D $flag token `$token`; allowed: $allowed');

  static function notImplemented(flag:String, token:String, detail:String):Error
    return err('Not implemented: -D $flag=$token ($detail)');

  static function missing(flag:String):Error
    return err('Missing required -D $flag=…\n\n${help()}');

  static function err(message:String):Error
    return new Error(message);
}
