package;

import MatrixCli.MatrixClient;
import MatrixCli.MatrixConfig;
import MatrixCli.MatrixEndpoint;
import MatrixCli.MatrixSuite;
import tink.core.Error;
import tink.core.Outcome;
import tink.testrunner.Batch;
import tink.testrunner.Suite;
import tink.unit.TestSuite;

/**
  Assembles tink_unittest suites from a parsed `MatrixConfig`.
  Until M4/M5, network case groups are attached wholesale (no method gating).
**/
class SuiteAsm {
  public static function build(config:MatrixConfig):Outcome<Batch, Error> {
    final suites:Array<Suite> = [];
    final wantsUnit = config.suites.indexOf(Unit) != -1;
    final wantsClient = config.suites.indexOf(Client) != -1;
    final wantsContainer = config.suites.indexOf(Container) != -1;

    if (wantsUnit)
      appendUnit(suites);

    if (wantsClient || wantsContainer) {
      switch resolveClients(config.clients) {
        case Failure(e): return Failure(e);
        case Success(clients):
          if (wantsClient)
            appendClientLane(suites, clients, config.endpoints);
          if (wantsContainer)
            appendContainerLane(suites, clients, config.endpoints, config.port);
      }
    }

    return Success(new Batch(suites));
  }

  static function appendUnit(suites:Array<Suite>):Void {
    suites.push(TestSuite.make(new TestHeader()));
    suites.push(TestSuite.make(new Sses()));
    suites.push(TestSuite.make(new TestChunked()));
    suites.push(TestSuite.make(new TestResponseFraming()));
  }

  static function appendClientLane(
    suites:Array<Suite>,
    clients:Array<ClientType>,
    endpoints:Array<MatrixEndpoint>
  ):Void {
    for (client in clients) {
      for (ep in endpoints) switch ep {
        case Httpbin:
          suites.push(TestSuite.make(
            new TestHttp(client, Httpbin(false)),
            '$client -> ${HttpbinConfig.url}'
          ));
        case HttpbinSecure:
          if (!skipSecureSocket(client))
            suites.push(TestSuite.make(
              new TestHttp(client, Httpbin(true)),
              '$client -> ${HttpbinConfig.secureUrl}'
            ));
        case Local:
          // Client lane never adds Local/DummyServer endpoints.
      }
    }
    // Wholesale until M5 gates FetchTest by cases/endpoints.
    suites.push(TestSuite.make(new FetchTest(#if php tink.http.ClientType.Php #end)));
  }

  static function appendContainerLane(
    suites:Array<Suite>,
    clients:Array<ClientType>,
    endpoints:Array<MatrixEndpoint>,
    port:Null<Int>
  ):Void {
    if (endpoints.indexOf(Local) == -1 || port == null)
      return;
    for (client in clients) {
      suites.push(TestSuite.make(
        new TestHttp(client, Local(port)),
        '$client -> http://localhost:$port'
      ));
    }
  }

  static function resolveClients(requested:Array<MatrixClient>):Outcome<Array<ClientType>, Error> {
    final out:Array<ClientType> = [];
    for (c in requested) switch resolveClient(c) {
      case Failure(e): return Failure(e);
      case Success(ct): out.push(ct);
    }
    return Success(out);
  }

  static function resolveClient(c:MatrixClient):Outcome<ClientType, Error> {
    final token = clientToken(c);
    return switch ClientFactory.create(token) {
      case Failure(e): Failure(e);
      case Success(_): toTestClientType(c);
    };
  }

  static function clientToken(c:MatrixClient):String
    return switch c {
      case MatrixClient.Node: 'node';
      case MatrixClient.Socket: 'socket';
      case MatrixClient.Curl: 'curl';
      case MatrixClient.Js: 'js';
      case MatrixClient.JsFetch: 'js-fetch';
      case MatrixClient.Tcp: 'tcp';
      case MatrixClient.Flash: 'flash';
    };

  /** Map matrix token to `tests.ClientType` after `ClientFactory` confirmed availability. */
  static function toTestClientType(c:MatrixClient):Outcome<ClientType, Error>
    return switch c {
      case MatrixClient.Node:
        #if nodejs
        Success(ClientType.Node);
        #else
        unavailable('node');
        #end
      case MatrixClient.Socket:
        #if sys
        Success(ClientType.Socket);
        #else
        unavailable('socket');
        #end
      case MatrixClient.Curl:
        #if ((nodejs || sys) && !php && !lua)
        Success(ClientType.Curl);
        #else
        unavailable('curl');
        #end
      case MatrixClient.Js:
        #if (js && !nodejs)
        Success(ClientType.Js);
        #else
        unavailable('js');
        #end
      case MatrixClient.JsFetch:
        #if (js && !nodejs)
        Success(ClientType.JsFetch);
        #else
        unavailable('js-fetch');
        #end
      case MatrixClient.Tcp:
        #if tink_tcp
        Success(ClientType.Tcp);
        #else
        unavailable('tcp');
        #end
      case MatrixClient.Flash:
        #if flash
        Success(ClientType.Flash);
        #else
        unavailable('flash');
        #end
    };

  static function unavailable(token:String):Outcome<ClientType, Error>
    return Failure(new Error('Client token "$token" is not available on this target'));

  /** Preserve pre-matrix skip: cs/lua have no SSL socket yet. */
  static function skipSecureSocket(client:ClientType):Bool {
    #if (cs || lua)
    return client == ClientType.Socket;
    #else
    return false;
    #end
  }
}
