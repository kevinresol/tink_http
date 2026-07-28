package;

import tink.http.Client;
import tink.http.clients.*;

using tink.CoreApi;

/**
 * Maps kebab-case `-D clients=` tokens to concrete `Client` instances.
 *
 * Container-lane probe is always `node` (`NodeClient`); this factory still
 * supports the full client-lane token set for `suites=client`.
 *
 * Supported: `node`, `socket`, `curl`, `js`, `js-fetch`, `tcp`, `flash`.
 * Reserved (not implemented): `std`, `local-container`.
 */
class ClientFactory {

  /**
   * Create a client for an explicitly requested token.
   * Unavailable on this target → Failure (not a silent skip).
   * `std` / `local-container` → not-implemented Failure.
   */
  public static function create(token:String):Outcome<Client, Error>
    return switch token {
      case 'std' | 'local-container':
        Failure(new Error('Client token "$token" is not implemented'));

      case 'node':
        #if nodejs
        Success(new NodeClient());
        #else
        unavailable(token);
        #end

      case 'socket':
        #if sys
        Success(new SocketClient());
        #else
        unavailable(token);
        #end

      case 'curl':
        #if ((nodejs || sys) && !php && !lua)
        Success(new CurlClient());
        #else
        unavailable(token);
        #end

      case 'js':
        #if (js && !nodejs)
        Success(new JsClient());
        #else
        unavailable(token);
        #end

      case 'js-fetch':
        #if (js && !nodejs)
        Success(new JsFetchClient());
        #else
        unavailable(token);
        #end

      case 'tcp':
        #if tink_tcp
        Success(new TcpClient());
        #else
        unavailable(token);
        #end

      case 'flash':
        #if flash
        Success(new FlashClient());
        #else
        unavailable(token);
        #end

      case _:
        Failure(new Error('Unknown client token "$token"'));
    }

  static function unavailable(token:String):Outcome<Client, Error>
    return Failure(new Error('Client token "$token" is not available on this target'));
}
