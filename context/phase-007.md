# Phase 007 Notes — Peer Library & Example CLI

## Objectives
- Provide a reusable peer-mode workflow that lets SwiftPie-style responders run in-process without hitting the network.
- Reuse the existing in-process test server responders to power an example executable showcasing the architecture.
- Document the public API surface with README guidance for users plus DocC coverage for the public symbols.

## Proposed Scope
- Define a `PeerAdapter` (or similar) that maps incoming `RequestPayload` values onto async responder closures returning `ResponsePayload`, and ship it as part of the public library surface.
- Ship an example executable (working name: `PeerDemo`) under `Examples/` backed by the shared responders from the test server.
- Ensure the CLI wiring supports swapping to the peer transport via dependency injection for tests/examples, without adding runtime flags or config toggles.
- For stateful dependencies, document recommended patterns but let adopters manage lifecycles themselves; no extra helpers needed in this phase.
- No dedicated “base context” hook is required; Vapor’s `Request` already carries `Application`, logger, service context, and request-local storage for dependency injection.

## Test Plan Draft
- Unit specs for the peer adapter mapping, covering success, error, and handler-throws cases.
- A smoke test proving the `PeerDemo` executable launches and exercises a happy-path request; all other behaviors can be validated via in-memory unit tests.
- Documentation snippets verified via doctests or executable previews so API usage stays in sync with the code.

## Tooling Notes
- Extend `scripts/smoke-cli.sh` so it also runs the `PeerDemo` executable (e.g. `swift run PeerDemo /get`) after the existing CLI help check, keeping a single entry point for manual smoke validation.

## Open Questions
- Keep the example CLI minimal, consuming only the public SwiftPie interface and reusing the test server’s entrypoint without private wiring.

## 2025-10-31 Progress
- Added `PeerTransport`, `PeerRequest`, and `PeerRequestBody` to `SwiftPie` with shared request-body encoding helpers extracted from `URLSessionTransport`.
- Refactored the in-process NIO test server to delegate to a shared `TestPeerResponder`, enabling responder reuse across tests and the new `PeerDemo` example.
- Introduced `PeerTransportTests` and updated existing integration tests to exercise the shared responder path; `swift test` now covers peer-mode flows.
- Created the `PeerDemo` executable plus README/DocC documentation and extended `scripts/smoke-cli.sh` to smoke both executables.
