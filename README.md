# SwiftHTTPie

SwiftHTTPie is a Swift-native reimagining of the popular [HTTPie](https://httpie.io/) CLI for making HTTP requests. It mirrors HTTPie's concise argument syntax, integrates with Swift's `swift-http-types`, and provides a clean transport abstraction so the CLI can target different execution environments.

## Project Layout

- `Sources/SwiftHTTPie` — Reusable core library with request parsing, transport abstraction, and response formatting.
- `Sources/SwiftHTTPieCLI` — Production command-line tool that performs real network traffic using `URLSessionTransport`.
- `Examples/PeerDemo` — Minimal CLI showcasing the new peer-mode (`PeerTransport`) that executes requests directly against Swift responders without opening a socket.
- `Tests/SwiftHTTPieTests` — Unit and integration tests covering CLI flows, transports, and the reusable request parser.
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
swift run swift-httpie https://httpbin.org/get foo=bar
```

Add headers or JSON payloads using familiar HTTPie shorthands:

```bash
swift run swift-httpie POST https://httpbin.org/post Authorization:"Bearer token" flag:=true message="hello"
```

## Peer Mode (In-Process Responders)

Peer mode lets the CLI forward requests directly to Swift responders without a network hop. The core pieces are:

```swift
import SwiftHTTPie

let transport = PeerTransport { request in
    // Inspect request.request (HTTPTypes.HTTPRequest) and request.body
    var headers = HTTPFields()
    headers[.contentType] = "text/plain; charset=utf-8"
    let response = HTTPResponse(status: .ok, headerFields: headers)
    return ResponsePayload(response: response, body: .text("peer response"))
}

let context = CLIContext(transport: transport)
let exitCode = SwiftHTTPie.run(arguments: CommandLine.arguments, context: context)
```

Pair it with Vapor or custom responders to embed HTTP workflows directly inside your CLI. To bootstrap quickly, run the included peer demo:

```bash
swift run PeerDemo /get foo=bar
```

`PeerDemo` reuses the same responders that power the in-process test server, showing how production server logic can be shared with tooling.

## Documentation

API documentation lives in `Docs/SwiftHTTPie.docc` and can be generated with:

```bash
swift package generate-documentation --target SwiftHTTPieDocs
```

The docs cover the core library as well as the new peer-mode interfaces.

## License

SwiftHTTPie is available under the BSD 3-Clause License. See `LICENSE` and `NOTICES` for details.
