package;

import haxe.Json;
import tink.http.Fetch.fetch;
import tink.http.Header;
import tink.http.Method;
import tink.testrunner.*;
import tink.unit.*;
import tink.unit.Assert.*;

using haxe.Json;
using tink.CoreApi;

/**
  Shared Fetch helpers. Public test methods live only on case subclasses so
  SuiteAsm can register exactly the groups selected by `-D cases=` / endpoints.
**/
@:timeout(15000)
class FetchTest {
  final client:tink.http.Fetch.ClientType;
  final baseUrl:String;

  public function new(?client:tink.http.Fetch.ClientType, baseUrl:String) {
    this.client = client;
    this.baseUrl = baseUrl;
  }

  function testStatus(url:String, status = 200) {
    return fetch(url, {client: client}).all().next(function(res) {
      return assert(res.header.statusCode == status);
    });
  }

  function testChunked(url:String) {
    return fetch(url, {client: client}).all().next(function(res) {
      final lines = [for (line in res.body.toString().split('\n')) if (line.length > 0) line];
      final assertions:Array<Assertion> = [
        assert(res.header.statusCode == 200),
        assert(lines.length == 10),
      ];
      for (i in 0...lines.length)
        assertions.push(assert(lines[i].parse().id == i));
      return assertions;
    });
  }

  function testData(url:String, method:Method) {
    final body = 'Hello, World!';
    return fetch(url, {
      method: method,
      headers: [
        new HeaderField('content-type', 'text/plain'),
        new HeaderField('content-length', Std.string(body.length)),
      ],
      body: body,
      client: client,
    }).all().next(function(res):Array<Assertion> {
      return [
        assert(res.header.statusCode == 200),
        assert(res.body.toString().parse().data == body),
      ];
    });
  }

  function objectToHeader(obj:Dynamic) {
    return new Header([for (key in Reflect.fields(obj)) {
      final v:Dynamic = Reflect.field(obj, key);
      // httpbin.io returns header values as arrays
      final s = if (Std.isOfType(v, Array)) (v:Array<Dynamic>).map(Std.string).join(',') else Std.string(v);
      new HeaderField(key, s);
    }]);
  }
}

/** Case ids: `methods`, `body` (any triggers registration). */
@:timeout(15000)
class FetchTestMethods extends FetchTest {
  public function get() return testStatus(baseUrl + '/');
  public function post() return testData(baseUrl + '/post', POST);
  public function delete() return testData(baseUrl + '/delete', DELETE);
  public function patch() return testData(baseUrl + '/patch', PATCH);
  public function put() return testData(baseUrl + '/put', PUT);
}

/** Case id: `headers`. */
@:timeout(15000)
class FetchTestHeaders extends FetchTest {
  public function headers(buffer:AssertionBuffer) {
    final name = 'my-sample-header';
    final value = 'foobar';
    return fetch(baseUrl + '/headers', {
      headers: [
        new HeaderField(name, value),
      ],
      client: client,
    }).all().next(
      function(res) {
        buffer.assert(res.header.statusCode == 200);
        buffer.assert(Type.enumEq(objectToHeader(res.body.toString().parse().headers).byName(name), Success(value)));
        return buffer.done();
      });
  }
}

/** Case id: `chunked-response`. */
@:timeout(15000)
class FetchTestChunked extends FetchTest {
  public function chunked() return testChunked(baseUrl + '/stream/10');
}

/** Case id: `redirect`. Capability skip on cpp kept (known investigation). */
@:timeout(15000)
class FetchTestRedirect extends FetchTest {
  #if !cpp // TODO: investigate
  public function redirect() return testStatus(baseUrl + '/redirect/5');
  #end
}
