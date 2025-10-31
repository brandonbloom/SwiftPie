# Phase 004 Notes — Local Test Server

## Objectives
- Build an in-process HTTP test server in pure Swift so `swift test` can spin it up without external dependencies.
- Expose deterministic endpoints needed by the transport stack: `/get`, `/post`, `/headers`, `/status/<code>`, redirect helpers, chunked/text bodies, and TLS variants.
- Provide lightweight fixtures/utilities that make it easy for integration tests to start the server, issue requests, and assert captured metadata.

## Test Plan Draft
- Unit-test individual handlers/serializers (echo payloads, cookie setters, chunked stream framing) using direct invocation of endpoint closures so logic failures surface without networking noise.
- Add server lifecycle tests that boot the SwiftNIO stack inside the test target, hit endpoints via `URLSession` to validate request recording, response payloads, redirect chains, and status handling.
- Provide TLS-specific tests that verify the helper exports the CA certificate, `URLSession`/future transport can trust it, and handshake failure paths are observable.
- Add stress-style tests (multiple sequential requests, parallel clients) to ensure request capture remains thread-safe.
- Include negative-path cases (unknown routes → 404 JSON body, aborted connections, latency timeouts) so the transport adapter can exercise its error handling in Phase 005.

## Design Considerations
- Build on top of SwiftNIO’s HTTP server primitives (same stack Vapor uses) so we get async handlers, streaming, and TLS support without external processes.
- Package the server as an internal-only module under `Tests/` (e.g. `TestSupport/TestHTTPServer`) with a `withTestServer` helper that spins up the event loop group, bootstraps the channel pipeline, and tears everything down automatically.
- Add request recording support so integration tests can assert on the inbound request (method, headers, body) via a thread-safe buffer exposed by the helper.
- Ensure TLS endpoints can be toggled via self-signed certificates bundled in the test target; document trust injection steps for the transport.
- Provide convenience wrappers so tests can run the server synchronously within `withServer { }` blocks and automatically clean up after assertions.

## Architecture Sketch
- **Module layout**: introduce `Tests/TestSupport/NIOHTTPTestServer.swift` to host the server implementation and expose fixtures to the rest of the test target.
- **Server startup**: `NIOHTTPTestServer.start(configuration:handlers:timeout:)` allocates a multi-threaded event loop group (default 1 loop for deterministic behaviour), binds to `localhost` on an ephemeral port, installs a custom `ChannelInboundHandler` that routes requests to registered endpoint handlers, and returns a handle containing `baseURL`, `close()` and `recordedRequests`.
- **Helper API**:
  ```swift
  struct TestServerHandle {
      let baseURL: URL
      func lastRequest(path: String) -> CapturedRequest?
  }

  func withTestServer(
      configuration: TestServerConfiguration = .standard,
      _ body: (TestServerHandle) throws -> Void
  ) rethrows
  ```
  `TestServerConfiguration` covers TLS toggle, default headers, latency injection, etc.
- **CapturedRequest**: Store method, path, headers (`[(HTTPField, String)]`), raw body (`ByteBuffer`/`Data`), optional trailers. Use a `NIOAtomic`/`NIOLockedValueBox` to handle concurrency.

## Endpoint Mapping
- **Implemented for Phase 004**
  - `/get`: echoes query params and headers in JSON (`{"args": {...}, "headers": {...}}`).
  - `/post`: accepts JSON/form payloads, echoes JSON with parsed fields similar to httpbin’s `/post`.
  - `/headers`: returns the request headers as JSON.
  - `/status/<code>`: responds with the provided status and optional message body override.
  - `/redirect-to?url=…` + `/redirect/<n>`: 302/307 redirects to exercise location handling.
  - `/cookies` + `/cookies/set`: cookie reflection and issuance mirroring HTTPie fixtures.
- **Deferred**
  - `/stream/<n>` chunked responses and `/delay/<seconds>` latency simulation (needed for streaming/timeouts).
  - TLS variant served via self-signed certificate with exported CA bundle for trust injection.

## Open Questions
- Do we need websocket/upgrade endpoints for future phases, or defer until session/download work?
- Should streaming payload assertions expose the raw chunks or buffer to `Data` for simpler tests?

## 2025-10-31 Progress
- Added a `SwiftHTTPieTestSupport` target powered by SwiftNIO with `withTestServer` helpers (sync + async) that spin up an on-process server and expose request recordings.
- Implemented core httpbin-like endpoints (`/get`, `/post`, `/headers`, `/status/<code>`, `/redirect-to`, `/redirect/<n>`, `/cookies`, `/cookies/set`) plus request/cookie/form parsing.
- Added `Tests/SwiftHTTPieTests/TestHTTPServerTests.swift` exercising happy-path GET/POST flows, status codes, cookie issuance, and redirect handling via `URLSession`.
- Deferred chunked streaming, delay endpoints, and TLS support to later phases (tracked in Phase 005 scope).
