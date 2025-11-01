# SwiftPie

SwiftPie is a Swift-native, HTTPie-compatible CLI for making HTTP requests. It mirrors HTTPie's concise argument syntax, integrates with Swift's `swift-http-types`, and provides a clean transport abstraction so the CLI can target different execution environments.

## Project Layout

- `Sources/SwiftPie` — Reusable core library with request parsing, transport abstraction, and response formatting.
- `Sources/SwiftPieCLI` — Production command-line tool that performs real network traffic using `URLSessionTransport`.
- `Examples/PeerDemo` — Minimal CLI showcasing the new peer-mode (`PeerTransport`) that executes requests directly against Swift responders without opening a socket.
- `Tests/SwiftPieTests` — Unit and integration tests covering CLI flows, transports, and the reusable request parser.
- `Tests/TestSupport` — In-process HTTP server and shared responders used by tests and examples.

## Building & Testing

Requires Swift 6.2+ on macOS 14:

```bash
swift build
swift test
```

A convenience smoke script rebuilds the package and runs both executables:

```bash
scripts/smoke-cli.sh
```

## CLI Usage

The primary executable mirrors HTTPie's syntax. For example:

```bash
swift run spie https://httpbin.org/get foo=bar
```

Add headers or JSON payloads using familiar HTTPie shorthands:

```bash
swift run spie POST https://httpbin.org/post Authorization:"Bearer token" flag:=true message="hello"
```

## Peer Mode (In-Process Responders)

Peer mode lets the CLI forward requests directly to Swift responders without a network hop. The core pieces are:

```swift
import SwiftPie

SwiftPie.main { request in
    var headers = HTTPFields()
    headers[.contentType] = "text/plain; charset=utf-8"
    let response = HTTPResponse(status: .ok, headerFields: headers)
    return ResponsePayload(response: response, body: .text("peer response"))
}
```

Pair it with Vapor or custom responders to embed HTTP workflows directly inside your CLI. To bootstrap quickly, run the included peer demo:

```bash
swift run PeerDemo /get foo=bar
```

`PeerDemo` reuses the same responders that power the in-process test server, showing how production server logic can be shared with tooling.

## Documentation

API documentation lives in `Docs/SwiftPie.docc` and can be generated with:

```bash
swift package generate-documentation --target SwiftPieDocs
```

The docs cover the core library as well as the new peer-mode interfaces.

## License

SwiftPie is available under the BSD 3-Clause License. See `LICENSE` and `NOTICES` for details.
