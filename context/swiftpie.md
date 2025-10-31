SwiftPie Concept
===================

Overview
--------
- Provide for Swift what Pier/httpie-go delivers for Go: an HTTPie-style CLI that runs handlers locally without an HTTP server.
- Support two deliverables: a reusable Swift library and an executable CLI that showcase the library.

Developer Workflow
------------------
- Developers factor Vapor route logic into reusable modules.
- A CLI target depends on the library and invokes `SwiftPie.main`.
- `SwiftPie.main` boots required dependencies, then runs the handler for requests issued via `swift run my-cli METHOD /path`.

Library Direction
-----------------
- Expose an entry point that accepts a callable handler and manages lifecycle internally.
- Initial handler focus: Vapor REST APIs, while staying adaptable so other Swift frameworks can integrate later.
- Favor `swift-http-types` primitives (`HTTPRequest`, `HTTPResponse`) as the lowest common denominator where practical.
- Allow CLI authors to inject dependencies (databases, middleware) before passing the handler to `SwiftPie.main`.

CLI Behavior Expectations
-------------------------
- Emulate HTTPie's argument syntax: verbs, headers, JSON shorthand, files, auth flags, sessions, downloads, verbose output, etc.
- Initial output can be plain text, but aim for colorized, nicely formatted responses and stream support.
- Support HTTPie's authentication flags (e.g., `-a user:pass`) rather than requiring manual headers.
- Handle sessions and downloads in parity with httpie-go, persisting data and honoring response metadata.

Feature Priorities
------------------
1. Match the subset implemented by `context/httpie-go` as the baseline for parity.
2. Cover HTTPie documentation examples:
   - Custom methods, headers, JSON bodies.
   - Form submissions with `-f`.
   - Verbose output (`-v`), offline mode (`--offline`), redirected input/output, `--download`, `--session`, custom `Host`.
3. Layer on enhanced UX (colors, streaming, full HTTPie parity) after achieving the Go subset.

Next Steps
----------
- Audit `context/httpie-go` to catalog the supported subset and translate it into SwiftPie's roadmap.
- Decide on concrete handler signature and Vapor integration details using `swift-http-types`.
- Prototype the core library API and a reference CLI target to validate the workflow end to end.
