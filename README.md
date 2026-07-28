# Tink HTTP

[![Build Status](https://github.com/haxetink/tink_http/actions/workflows/ci.yml/badge.svg)](https://github.com/haxetink/tink_http/actions)
[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/haxetink/public)

Tink HTTP provides a cross platform abstraction over the server and client side of HTTP, based on asynchronous immutable streams. Its API is an attempt to expose the protocol as directly as possible. While it can be used directly, it is meant as an abstraction layer to build frameworks on.

Documentations: https://haxetink.github.io/tink_http

## Running tests

Matrix defines are Travix rest `-D` args (see `tests.hxml` → `tests.runner.hxml`). Local client defaults to public httpbin.io.

```bash
# Unit (no network)
lix run travix node -D suites=unit

# Client lane
lix run travix node \
  -D suites=client \
  -D clients=node,curl \
  -D endpoints=httpbin,httpbin-secure \
  -D cases=methods,headers,body

# Container lane (DummyServer under test; probe is always node)
PORT=8000
scripts/run-container.sh node "$PORT"
lix run travix node \
  -D suites=container \
  -D clients=node \
  -D endpoints=local \
  -D port="$PORT" \
  -D cases=methods,headers,body
curl -sf "http://127.0.0.1:${PORT}/close"
```
