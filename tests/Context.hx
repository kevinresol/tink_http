package;

#if tink_http
import tink.http.Handler;
#end

/**
  Shared test helpers. DummyServer looks up `servers` by `-D server=`.
  Master orchestration maps (`containers` / `targets`) were removed in M7.
**/
class Context {

  #if php
  static function __init__()
    untyped __call__('ini_set', 'xdebug.max_nesting_level', 100000);
  #end

  static inline var RUN = 'RUN_SERVER';

  #if tink_http
  public static var servers: Map<String, Int -> Handler -> Void> = [

    '' => null,

    #if php
    'php' => function (port, handler) {
      if (Sys.getEnv(RUN) != 'true') return;
      tink.http.containers.PhpContainer.inst.run(handler).eager();
    },
    #end

    #if neko
    'modneko' => function (port, handler) {
      if (Sys.getEnv(RUN) != 'true') return;
      tink.http.containers.ModnekoContainer.inst.run(handler).eager();
    },
    #end

    #if nodejs
    'node' => function (port, handler)
      new tink.http.containers.NodeContainer(port).run(handler).eager(),
    #end

    #if (tink_tcp && (nodejs || tink_runloop))
    'tcp' => function (port, handler)
      #if tink_runloop @:privateAccess tink.RunLoop.create(function() #end
        new tink.http.containers.TcpContainer(
          #if nodejs
            tink.tcp.nodejs.NodejsAcceptor.inst.bind.bind(port)
          #else
            #error "not implemented"
          #end
        )
        .run(handler).eager()
      #if tink_runloop ) #end,
    #end

  ];
  #end
}
