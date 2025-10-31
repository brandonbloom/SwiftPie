# Building Peer Responders

Learn how to execute SwiftPie requests directly against in-process responders using ``SwiftPie.PeerTransport``.

## Overview

`PeerTransport` implements ``SwiftPie.RequestTransport`` and accepts a ``SwiftPie.PeerResponder`` closure. The closure receives a ``SwiftPie.PeerRequest`` (wrapping `HTTPRequest`, body data, and the active ``SwiftPie.TransportOptions``) and returns a ``SwiftPie.ResponsePayload``.

```swift
import HTTPTypes
import SwiftPie

let peerTransport = PeerTransport { request in
    var headers = HTTPFields()
    headers[.contentType] = "application/json"

    let response = HTTPResponse(status: .ok, headerFields: headers)
    let body = ResponseBody.text("{\"message\":\"Hello, peer!\"}")
    return ResponsePayload(response: response, body: body)
}

let context = CLIContext(transport: peerTransport)
let exitCode = SwiftPie.run(arguments: CommandLine.arguments, context: context)
```

## Sharing Responders

The project ships with ``SwiftPieTestSupport/TestPeerResponder-swift.enum`` which powers the in-process test server and the `PeerDemo` executable. You can follow the same pattern to point the CLI at Vapor route handlers or any Swift code that can generate `ResponsePayload` instances.

```swift
import SwiftPie
import SwiftPieTestSupport

let responder = TestPeerResponder.makePeerResponder()
let transport = PeerTransport(responder: responder)
let context = CLIContext(transport: transport)
```

This setup allows you to reuse production HTTP logic in developer tooling without reimplementing your routes or standing up a local server.

## Body Helpers

``PeerRequestBody`` exposes convenience accessors for common body transformations:

- ``SwiftPie.PeerRequestBody/data`` — Access the raw payload bytes.
- ``SwiftPie.PeerRequestBody/string(encoding:)`` — Decode the payload using a given string encoding.

Use these helpers to parse JSON, decode forms, or pipe input into Vapor’s `Content` decoders without managing temporary files.

## Exit Codes

``PeerTransport`` returns the responder’s `ResponsePayload` verbatim. The command-line runner maps HTTP status codes (≥ 400) to exit code `1`, matching HTTPie's behavior. Throwing an error from the responder surfaces as ``SwiftPie.TransportError/internalFailure(_:)``.
