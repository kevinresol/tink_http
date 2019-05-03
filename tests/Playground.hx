package;

import tink.http.containers.*;
// import tink.http.Client.*;
import tink.http.Response;

using tink.CoreApi;

class Playground {
	static function main() {
		var container = new TcpContainer(tink.tcp.uv.UvAcceptor.inst.bind.bind(7002));
		container.run(function(req) return Future.sync(('Done':OutgoingResponse)))
			.handle(function(o) trace(o));
	}
}