package;

/**
 * Compile-time client variants available on this target.
 * Runtime kebab-case token → instance mapping: `ClientFactory`
 * (`-D clients=`). Container-lane probe is always `node`; other tokens
 * are for the client lane.
 */
enum ClientType {

  #if sys
  Socket;
  #end

  #if (js && !nodejs)
  Js;
  JsFetch;
  #end

  #if nodejs
  Node;
  #end

  #if tink_tcp
  Tcp;
  #end

  #if ((nodejs || sys) && !php && !lua)
  // TODO: php fails to read from stdout of curl process
  // TODO: lua suffers from https://github.com/HaxeFoundation/haxe/issues/7544
  Curl;
  #end

  #if flash
  Flash;
  #end
}
