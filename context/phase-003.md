# Phase 003 Notes — Transport & Responses

## Objectives
- Define a transport-facing protocol that accepts `RequestPayload` and produces a synthetic `ResponsePayload` used by the CLI.
- Provide fake/in-memory transport implementations that power the test suite and let Phase 002’s CLI path continue through the transport.
- Render HTTPie-style status line, headers, and body placeholders in CLI output while propagating failures via exit codes and stderr messaging.

## Test Plan
- Unit-test the transport protocol and fake implementations for success, non-success HTTP codes, and transport failures.
- Add CLI-level tests that execute the command with the fake transport, capturing stdout/stderr and exit codes for success and error cases.
- Include snapshot helpers (fixtures or inline expectations) for formatted responses to simplify future verification.

## Open Questions & Follow-ups
- Decide whether body formatting needs to support color/pretty toggles now or defer until Phase 006.
- Confirm how much metadata (timing, redirects) needs preserving for subsequent phases.

## 2025-10-30 Progress
- Introduced `RequestTransport` protocol and made `CLIContext` generic over the transport, with `PendingTransport` providing a placeholder 200 OK response for the default CLI workflow.
- Added `TransportError` to describe network/internal failures with CLI-friendly messaging.
- Implemented `ResponseFormatter` to render HTTP/1.1 status lines, headers, and text/binary body markers, used directly by `CLIRunner`.
- Updated CLI flow to invoke the transport, print formatted responses, and map status codes ≥400 or thrown `TransportError`s to exit code 1.
- Added `ResponseFormatterTests` and extended `CLIRunnerTests` to cover success, client/server error statuses, and transport failures.

## Test Runs
- `swift test` (passes)
