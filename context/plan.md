SwiftHTTPie Delivery Plan
=========================

Workflow Guardrails
-------------------
- Begin each phase by confirming with the user the desired outcomes and success criteria for that phase.
- Co-design a concrete test plan with the user before writing code, then implement the tests first (TDD).
- Record working notes for the phase in `context/phase-00N.md`, keeping one file per phase.
- When implementation for a phase is ready, request a user review, note follow-ups in the matching phase file, then revise this plan to reflect any new direction.
- After each review cycle, remind the user to run `/new` so the conversation context resets before the next phase.
- Keep the immediately upcoming phases richly detailed; allow later phases to stay high level until the plan is revisited post-review.
- Update `context/feature-checklist.md` and README/docs alongside each phase so parity status and user-facing guidance stay current.

Phase Roadmap
-------------

### Phase 001 — CLI Skeleton and Package Scaffolding ✅
- Outcome: SwiftPM workspace now includes `SwiftHTTPieCore` and `SwiftHTTPieCLI`, a placeholder `SwiftHTTPie.main` that terminates with the computed exit code, and a smoke test script (`scripts/smoke-cli.sh`). Details captured in `context/phase-001.md`.
- Follow-ups: None pending before Phase 002; CLI exits successfully and tooling is ready for request-parsing work.

### Phase 002 — Request Parsing and HTTP Request Construction
- Objective: Finish the end-to-end request builder that turns CLI arguments into a validated HTTP request payload.
- In-progress scope:
  - ✅ Core parsing helpers for verbs, query args, shorthands, and localhost normalization (ported into `RequestParser` with Swift Testing specs).
  - 🔜 Extend coverage for remaining HTTPie shorthands (file embeds, raw JSON/file references, duplicate headers/data arrays) and map to a richer request model compatible with `swift-http-types`.
  - 🔜 Surface validation diagnostics (unknown separators, invalid URLs, mutually exclusive flags) through `SwiftHTTPieCLI` with non-zero exit codes and stderr output.
  - 🔜 Bridge the parsed request into an internal representation that Phase 003 can hand to the transport layer.
- Candidate test plan: Expand unit specs for each shorthand permutation, add CLI-level tests that execute `SwiftHTTPie` via the Testing process APIs, and capture stderr/exit codes for invalid inputs.
- Exit artifact: Append findings and review notes to `context/phase-002.md`.

### Phase 003 — Transport Hook & Response Handling
- Objective: Define a transport abstraction that consumes `RequestPayload`, execute requests against a fake transport, and render responses with HTTPie-style formatting.
- Proposed scope to confirm with user: Introduce a RoundTripper-like protocol fed by the CLI’s `requestSink`, supply in-memory/fake transport implementations for tests, and build response/body formatting (status line, headers, color/pretty toggles placeholder).
- Candidate test plan: Use fake transports to simulate success/error/timeout scenarios, snapshot assertions for formatted output, and verify stderr/exit behavior for transport failures.
- Exit artifact: Document decisions/tests in `context/phase-003.md`.

### Phase 004 — Local Test Server
- Objective: Provide a deterministic HTTP target that runs inside the test suite so transport/integration tests never reach the public internet.
- Proposed scope to confirm with user: Stand up a lightweight server on top of SwiftNIO (matching Vapor’s stack) exposing the core endpoints we need immediately (`/get`, `/post`, `/headers`, `/status/{code}`, redirects, cookies). Package it so tests can start/stop it on demand and share helpers for request assertions. Defer TLS and streaming/timeout endpoints to later phases.
- Candidate test plan: Unit-test the handlers directly, furnish integration helpers that run against the in-process server, and confirm we can simulate success, client/server errors, redirects, and cookie handling without flakiness. Note follow-ups for TLS/streaming coverage once those endpoints arrive.
- Exit artifact: Capture setup instructions, endpoints, and extension guidelines in `context/phase-004.md`.

### Phase 005 — Real Network Transport
- Objective: Wire the transport protocol into a production HTTP client implementation.
- Proposed scope to confirm with user: Choose a concrete client (`URLSession`, `AsyncHTTPClient`, etc.), support streaming bodies, TLS/custom trust hooks, and map metadata cleanly between layers. Expand the local test server as needed (TLS certs, streaming endpoints) to exercise these behaviors.
- Candidate test plan: Integration tests hitting the local test server validating verbs, headers, payload types, redirects, and error propagation; retain fake transport support for deterministic tests.
- Exit artifact: Capture architecture decisions in `context/phase-005.md`.
- ✅ `URLSessionTransport` now powers the default CLI context with JSON/form/multipart body support and response decoding. Network error propagation and CLI integration are covered by new tests (`URLSessionTransportTests`, updated `swift test` run on 2025-10-31).
- 🔜 Add TLS fixtures, streaming uploads/downloads, and expose configuration knobs (timeouts, proxies) through the CLI once scoped.

### Phase 006 — Authentication & Core Flags (Go Parity)
- Objective: Implement the authentication, verification, and timeout switches shipped by `httpie-go` so the CLI reaches baseline feature parity.
- Proposed scope to confirm with user: Support `-a/--auth` with prompt fallback, `--auth-type=bearer`, `--verify`, `--timeout`, `--http1`, and `--ignore-stdin` behaviours aligned with Go.
- Candidate test plan: Unit tests for credential parsing and option validation, CLI integration tests covering prompts/stdin handling and exit codes.
- Exit artifact: Track progress in `context/phase-006.md`.

### Phase 007 — Download Mode & Streaming
- Objective: Deliver `--download`, `--output`, and overwrite safeguards so large responses stream to disk similar to `httpie-go`.
- Proposed scope to confirm with user: Add streaming body support in the transport, file writer utilities, CLI progress/exit semantics, and tests guarding overwrite protections.
- Candidate test plan: Integration tests piping responses from the in-process server to temp files, failure-mode tests for existing-file overwrites, and CLI assertions for stdout/stderr redirects.
- Exit artifact: Track progress in `context/phase-007.md`.

### Phase 008 — Clientless Library & Example CLI
- Objective: Deliver the reusable “clientless” library workflow described in `context/swifthttpie.md` and showcase it with a Vapor-backed example that reuses the in-process test server handlers.
- Proposed scope to confirm with user: Define the public API for embedding handlers (swift-http-types based), provide lifecycle hooks for dependency bootstrapping, and create an example executable (`Examples/PeerDemo` or similar) that runs the test server endpoints in peer mode.
- Candidate test plan: Unit specs for the handler adapter, integration tests that run the example CLI against the shared test server implementation, and documentation snippets validated via doctests or executable previews.
- Exit artifact: Track progress in `context/phase-008.md`, including API diagrams and example wiring notes.

### Phase 009 — Documentation & Release Readiness
- Objective: Prepare the project for an open-source initial release with clear positioning, onboarding docs, and publishing automation.
- Proposed scope to confirm with user: Author a comprehensive `README.md` (purpose, install/run, CLI usage, library embedding), surface feature parity status from `context/feature-checklist.md`, add licensing/CONTRIBUTING notes, and script basic release tasks (version bumps, changelog seed).
- Candidate test plan: Lint documentation links/examples, run `swift build`/`swift test` in release mode, and exercise the example CLI walkthrough end to end.
- Exit artifact: Capture doc/release decisions in `context/phase-009.md`.

### Phase 010 — Sessions & Cookie Persistence
- Objective: Introduce `--session`, read-only sessions, and cookie jar management to begin covering HTTPie doc parity beyond Go’s subset.
- Proposed scope to confirm with user: Design session file format, persistence locations, concurrency guarantees, and ensure cookies/auth headers survive between invocations.
- Candidate test plan: Integration tests that write session files, reuse them across invocations, and verify cookie jar updates; unit tests for serialization/deserialization edge cases.
- Exit artifact: Track progress in `context/phase-010.md`.

### Phase 011 — Polish & Extended Parity
- Objective: Layer on advanced HTTPie behaviors (verbose mode, streaming output formatting, colors) and stabilize for release.
- Proposed scope to confirm with user: Additional CLI flags (verbose, offline, pretty-print), UX refinements, documentation, and packaging/distribution.
- Candidate test plan: Regression suite covering critical flags, golden-file output comparisons, documentation linting, and smoke tests across macOS targets.
- Exit artifact: Summarize outcomes in `context/phase-011.md`.

Plan Maintenance
----------------
- Revisit this roadmap after every phase review to incorporate feedback, add or reorder phases, and prune completed items.
- Ensure `context/index.md` lists all active plan and phase documents so future agents can navigate them quickly.
