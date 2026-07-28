package;

import MatrixCli.MatrixCases;
import MatrixCli.MatrixClient;
import MatrixCli.MatrixConfig;
import MatrixCli.MatrixEndpoint;
import MatrixCli.MatrixSuite;
import TestChunked.TestChunkedCodec;
import TestChunked.TestChunkedOutgoing;
import TestHeader.TestHeaderAccepts;
import TestHeader.TestHeaderAuth;
import TestHeader.TestHeaderBuild;
import TestHeader.TestHeaderContentLength;
import TestHeader.TestHeaderDates;
import TestHeader.TestHeaderRequestParse;
import TestHttp.Target;
import TestHttp.TestHttpChunked;
import TestHttp.TestHttpHeaders;
import TestHttp.TestHttpMethods;
import TestHttp.TestHttpOrigin;
import FetchTest.FetchTestChunked;
import FetchTest.FetchTestHeaders;
import FetchTest.FetchTestMethods;
import FetchTest.FetchTestRedirect;
import tink.core.Error;
import tink.core.Outcome;
import tink.testrunner.Batch;
import tink.testrunner.Suite;
import tink.unit.TestSuite;

/**
  Assembles tink_unittest suites from a parsed `MatrixConfig`.
  TestHttp / FetchTest / unit classes are gated by `-D cases=` (and endpoints for Fetch)
  via case-specific classes (suite assembly — not “ran but skipped”).
**/
class SuiteAsm {
  public static function build(config:MatrixConfig):Outcome<Batch, Error> {
    final suites:Array<Suite> = [];
    final wantsUnit = config.suites.indexOf(Unit) != -1;
    final wantsClient = config.suites.indexOf(Client) != -1;
    final wantsContainer = config.suites.indexOf(Container) != -1;

    if (wantsUnit)
      appendUnit(suites, config.cases);

    if (wantsClient || wantsContainer) {
      switch resolveClients(config.clients) {
        case Failure(e): return Failure(e);
        case Success(clients):
          if (wantsClient)
            appendClientLane(suites, clients, config.endpoints, config.cases);
          if (wantsContainer)
            appendContainerLane(suites, clients, config.endpoints, config.port, config.cases);
      }
    }

    return Success(new Batch(suites));
  }

  /**
    Unit case catalog (D1). Omitted `-D cases=` for unit-only defaults to `all`
    (= this full set) via MatrixCli.
  **/
  static function appendUnit(suites:Array<Suite>, cases:MatrixCases):Void {
    if (wantsCase(cases, 'header-build'))
      suites.push(TestSuite.make(new TestHeaderBuild()));
    if (wantsCase(cases, 'header-auth'))
      suites.push(TestSuite.make(new TestHeaderAuth()));
    if (wantsCase(cases, 'header-content-length'))
      suites.push(TestSuite.make(new TestHeaderContentLength()));
    if (wantsCase(cases, 'header-accepts'))
      suites.push(TestSuite.make(new TestHeaderAccepts()));
    if (wantsCase(cases, 'header-dates'))
      suites.push(TestSuite.make(new TestHeaderDates()));
    if (wantsCase(cases, 'request-parse'))
      suites.push(TestSuite.make(new TestHeaderRequestParse()));
    if (wantsCase(cases, 'chunked-codec'))
      suites.push(TestSuite.make(new TestChunkedCodec()));
    if (wantsCase(cases, 'chunked-outgoing'))
      suites.push(TestSuite.make(new TestChunkedOutgoing()));
    if (wantsCase(cases, 'response-framing'))
      suites.push(TestSuite.make(new TestResponseFraming()));
    if (wantsCase(cases, 'sse-codec'))
      suites.push(TestSuite.make(new Sses()));
  }

  static function appendClientLane(
    suites:Array<Suite>,
    clients:Array<ClientType>,
    endpoints:Array<MatrixEndpoint>,
    cases:MatrixCases
  ):Void {
    for (client in clients) {
      for (ep in endpoints) switch ep {
        case Httpbin:
          appendTestHttp(suites, client, Httpbin(false), 'httpbin', cases);
        case HttpbinSecure:
          if (!skipSecureSocket(client))
            appendTestHttp(suites, client, Httpbin(true), 'httpbin-secure', cases);
        case Local:
          // Client lane never adds Local/DummyServer endpoints.
      }
    }
    appendFetch(suites, endpoints, cases);
  }

  /** FetchTest is client-lane only; plain vs secure gated by endpoints. */
  static function appendFetch(
    suites:Array<Suite>,
    endpoints:Array<MatrixEndpoint>,
    cases:MatrixCases
  ):Void {
    final fetchClient = #if php tink.http.Fetch.ClientType.Php #else null #end;
    if (endpoints.indexOf(Httpbin) != -1)
      appendFetchForUrl(suites, fetchClient, HttpbinConfig.url, 'httpbin', cases);
    if (endpoints.indexOf(HttpbinSecure) != -1) {
      // True capability skip: Fetch HTTPS broken / untrusted on these targets.
      #if (!python && !cs && !interp && !lua)
      appendFetchForUrl(suites, fetchClient, HttpbinConfig.secureUrl, 'httpbin-secure', cases);
      #end
    }
  }

  static function appendFetchForUrl(
    suites:Array<Suite>,
    fetchClient:Null<tink.http.Fetch.ClientType>,
    baseUrl:String,
    endpoint:String,
    cases:MatrixCases
  ):Void {
    final name = 'Fetch -> $endpoint';
    if (wantsAny(cases, ['methods', 'body']))
      suites.push(TestSuite.make(new FetchTestMethods(fetchClient, baseUrl), name));
    if (wantsCase(cases, 'headers'))
      suites.push(TestSuite.make(new FetchTestHeaders(fetchClient, baseUrl), name));
    if (wantsCase(cases, 'chunked-response'))
      suites.push(TestSuite.make(new FetchTestChunked(fetchClient, baseUrl), name));
    if (wantsCase(cases, 'redirect')) {
      #if !cpp // TODO: investigate — true capability skip
      suites.push(TestSuite.make(new FetchTestRedirect(fetchClient, baseUrl), name));
      #end
    }
  }

  static function appendContainerLane(
    suites:Array<Suite>,
    clients:Array<ClientType>,
    endpoints:Array<MatrixEndpoint>,
    port:Null<Int>,
    cases:MatrixCases
  ):Void {
    if (endpoints.indexOf(Local) == -1 || port == null)
      return;
    for (client in clients)
      appendTestHttp(suites, client, Local(port), 'local', cases);
  }

  /** Register only TestHttp case classes matching `-D cases=` (D1 ids). */
  static function appendTestHttp(
    suites:Array<Suite>,
    client:ClientType,
    target:Target,
    endpoint:String,
    cases:MatrixCases
  ):Void {
    final name = '$client -> $endpoint';
    if (wantsAny(cases, ['methods', 'query', 'body']))
      suites.push(TestSuite.make(new TestHttpMethods(client, target), name));
    if (wantsAny(cases, ['headers', 'headers-multi']))
      suites.push(TestSuite.make(new TestHttpHeaders(client, target), name));
    if (wantsCase(cases, 'origin'))
      suites.push(TestSuite.make(new TestHttpOrigin(client, target), name));
    if (wantsCase(cases, 'chunked-response'))
      suites.push(TestSuite.make(new TestHttpChunked(client, target), name));
  }

  static function wantsCase(cases:MatrixCases, id:String):Bool
    return switch cases {
      case All: true;
      case Selected(ids): ids.indexOf(id) != -1;
    };

  static function wantsAny(cases:MatrixCases, ids:Array<String>):Bool {
    for (id in ids) if (wantsCase(cases, id)) return true;
    return false;
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
