# Test matrix gap map — current suites → `cases=`

Maps today’s registered tests onto future `-D cases=` tokens (kebab-case).
No runner changes in D1; this doc feeds M4 / M5 gating and C1+ coverage fill.

**Lanes:** `suites=unit|client|container` (see roadmap Decisions).
**Case tokens:** comma-list or `all`. Spelling below is canonical.

---

## Canonical case id catalog

### Network (`suites=client` | `suites=container`)

| Case id | Intent |
|---------|--------|
| `methods` | HTTP verbs (GET/POST/PATCH/DELETE/PUT, …) |
| `query` | Query-string round-trip |
| `headers` | Request header echo (single value per name) |
| `headers-multi` | Multiple values for the same header name (document coalescing) |
| `body` | Request body echo |
| `chunked-response` | Chunked / streamed response body |
| `chunked-request` | Chunked request body |
| `status` | Non-trivial / explicit status-code handling |
| `origin` | Client IP / origin echo (`/ip`) |
| `tls` | TLS / secure peer behavior beyond “same cases on `httpbin-secure`” |
| `errors` | Connection / transport failures |
| `redirect` | Follow redirects (**Fetch-only**) |
| `lifecycle` | Container process start / `/active` / `/close` (container lane) |
| `concurrent` | Concurrent requests |
| `multipart` | Multipart body parse/echo where claimed |
| `sse-produce` | Server-sent events from container |
| `upgrade` | Protocol upgrade smoke (Node) |

Reserved / deferred (not in M0–V1 matrix; listed for C1+): `local-container`, `smoke`.

### Unit (`suites=unit`)

| Case id | Intent |
|---------|--------|
| `header-build` | Build / concat / serialize request & response headers |
| `header-auth` | `Authorization` parse / `basicAuth` |
| `header-content-length` | `Content-Length` helpers |
| `header-accepts` | `Accept` matching |
| `header-dates` | `HeaderValue.ofDate` |
| `request-parse` | `IncomingRequest` framing / Host / chunked TE |
| `chunked-codec` | `Chunked.encode` / `Chunked.decode` |
| `chunked-outgoing` | `OutgoingResponse.chunked` / `withChunkedEncoding` |
| `response-framing` | `Helpers.frameResponseBody` |
| `sse-codec` | `SseStream.encode` / `decode` (offline) |

---

## 1. `TestHttp` → case ids

**Suites:** `client` (endpoints `httpbin` / `httpbin-secure`) and `container` (endpoint `local`).
Same class methods today; secure peer is endpoint selection, not a separate case token (see Gaps for dedicated `tls`).

| Method | Variants / notes | Case id(s) |
|--------|------------------|------------|
| `method` | `@:variant` GET, POST, PATCH, DELETE, PUT; URL includes `?a=1&b=2`; non-GET sends body | `methods` (primary); also asserts `query`; non-GET asserts `body` |
| `headers` | single: `x-custom-tink: tink_http` | `headers` |
| `headers` | multi: `x-custom-tink: tink_http1, tink_http2` | `headers-multi` |
| `origin` | GET `/ip`, asserts non-empty origin | `origin` |
| `chunked` | GET `/stream/10`, status 200 + 10 JSON lines | `chunked-response` (asserts status 200 only as setup — not full `status` coverage) |

**Registration note (M4):** one physical method may back multiple case ids. Prefer registering the method when **any** mapped case is requested; document that `method` fires for `methods`, `query`, or `body`, and `headers` fires for `headers` or `headers-multi`.

---

## 2. `FetchTest` → case ids

**Suites:** `client` only (M5). Not used for `container`.
`redirect` is Fetch-only (not in `TestHttp`).

| Method | Endpoint peer | Case id(s) |
|--------|---------------|------------|
| `get` | `httpbin` | `methods` |
| `post`, `delete`, `patch`, `put` | `httpbin` | `methods`, `body` |
| `headers` | `httpbin` | `headers` |
| `chunked` | `httpbin` | `chunked-response` |
| `redirect` | `httpbin` | `redirect` (`#if !cpp`) |
| `secureGet` | `httpbin-secure` | `methods` (+ secure endpoint) |
| `securePost`, `secureDelete`, `securePatch`, `securePut` | `httpbin-secure` | `methods`, `body` |
| `secureChunked` | `httpbin-secure` | `chunked-response` |
| `secureRedirect` | `httpbin-secure` | `redirect` (`#if !cpp`) |

Secure methods are also gated by `endpoints=httpbin-secure` (M5), not by inventing a separate case per `secure*` name. They do **not** by themselves satisfy a dedicated `tls` case (see Gaps).

---

## 3. Unit suites → `suites=unit` + case ids

Registered today in `RunTests` when not `container_only`: `TestHeader`, `Sses`, `TestChunked`, `TestResponseFraming`.

### `TestHeader`

| Method(s) | Case id |
|-----------|---------|
| `buildOutgoingRequestHeader`, `buildResponseHeader`, `concat` | `header-build` |
| `getAuth`, `getAuthError`, `basicAuth` | `header-auth` |
| `getContentLength`, `getContentLengthError`, `getMissingContentLength` | `header-content-length` |
| `accepts` | `header-accepts` |
| `ofDate` | `header-dates` |
| `parseBodyPrefersTransferEncoding`, `parseHeadRequestHasNoBody`, `parsePostWithoutFramingHasEmptyBody`, `parseHttp11MissingHost`, `parseHttp11WithHost`, `parseHttp10MissingHost`, `parseChunkedTransferEncodingBeforeMethod` | `request-parse` |
| `parseIncomingRequestHeader`, `parseIncomingResponseHeader` | **not registered** (`@:exclude`) — no case mapping until re-enabled |

### `TestChunked`

| Method(s) | Case id |
|-----------|---------|
| `encode`, `decode`, `decodeLarge` | `chunked-codec` |
| `factoryDefault`, `factoryCustomStatus`, `withChunkedEncoding*` | `chunked-outgoing` |

### `TestResponseFraming`

| Method(s) | Case id |
|-----------|---------|
| `headIgnoresContentLength`, `headIgnoresTransferEncoding`, `noBodyStatuses`, `contentLengthLimitsBody`, `prefersChunkedTransferEncoding`, `chunkedInCommaSeparatedList`, `readsUntilClose` | `response-framing` |

### `Sses`

| Method(s) | Case id |
|-----------|---------|
| `encode`, `decode` | `sse-codec` |

**Suggested unit default for `cases=` (M5 decides):**  
`header-build,header-auth,header-content-length,header-accepts,header-dates,request-parse,chunked-codec,chunked-outgoing,response-framing,sse-codec`  
(or `all` with the same set documented as the unit universe).

---

## 4. Objective coverage → gaps

Objective items from the roadmap with **no** current dedicated network/container assertion:

| Objective | Proposed case id | Current coverage |
|-----------|------------------|------------------|
| Container lifecycle | `lifecycle` | **Gap** — `/active` + `/close` exist on DummyServer / Master only; no matrix case |
| Chunked **request** body | `chunked-request` | **Gap** — only response streaming (`/stream/N`) is tested |
| Explicit status matrix | `status` | **Gap** — only incidental `200` checks inside other cases |
| Concurrent requests | `concurrent` | **Gap** |
| Multipart (where claimed) | `multipart` | **Gap** — DummyServer has `Parsed` branch; no client/container test hits it |
| SSE **produce** (container) | `sse-produce` | **Gap** — unit `sse-codec` only |
| Upgrade smoke (Node) | `upgrade` | **Gap** |
| TLS / bind where API exposes | `tls` | **Gap** as dedicated case — secure httpbin runs reuse other cases; no failure/bind assertions |
| Connection errors | `errors` | **Gap** |
| Headers multi (document coalescing) as first-class gate | `headers-multi` | **Partial** — covered by `TestHttp.headers` multi variant; needs own case token for M4 gating |
| Query as first-class gate | `query` | **Partial** — asserted inside `TestHttp.method` only |
| Body as first-class gate | `body` | **Partial** — inside `TestHttp.method` (non-GET) and Fetch `*Data` methods |
| Fetch redirects | `redirect` | **Covered** (Fetch-only; cpp excluded) |
| Methods | `methods` | **Covered** (`TestHttp` + `FetchTest`) |
| Headers (single) | `headers` | **Covered** |
| Chunked response | `chunked-response` | **Covered** (`TestHttp.chunked`, Fetch `chunked` / `secureChunked`) |
| Origin echo | `origin` | **Covered** (`TestHttp.origin`) — not in original objective list; keep as case |

### Excluded from this map (not test suites)

- `Playground.hx`, `Test.hx` — manual / non-runner entrypoints
- `Master.hx` — orchestration, not a case suite
- `DummyServer` routes — infrastructure for container lane, not cases themselves

---

## 5. Quick reference — all case ids in use

**Present today (map to existing tests):**  
`methods`, `query`, `headers`, `headers-multi`, `body`, `chunked-response`, `origin`, `redirect`,  
`header-build`, `header-auth`, `header-content-length`, `header-accepts`, `header-dates`, `request-parse`,  
`chunked-codec`, `chunked-outgoing`, `response-framing`, `sse-codec`

**Gaps (objective / no current test):**  
`lifecycle`, `chunked-request`, `status`, `concurrent`, `multipart`, `sse-produce`, `upgrade`, `tls`, `errors`

**Reserved later:** `local-container`, `smoke`
