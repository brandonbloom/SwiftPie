SwiftPie Delivery Plan
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
- Ensure every CLI-facing change updates the `--help` output (including colorized formatting) and adds/updates tests; compare against `http --help` for matching features to keep wording aligned.

Phase Roadmap
-------------

### Phase 001 — CLI Skeleton and Package Scaffolding ✅
- Outcome: SwiftPM workspace now includes `SwiftPie` and `SwiftPieCLI`, a placeholder `SwiftPie.main` that terminates with the computed exit code, and a smoke test script (`scripts/smoke-cli.sh`). Details captured in `context/phase-001.md`.
- Follow-ups: None pending before Phase 002; CLI exits successfully and tooling is ready for request-parsing work.

### Phase 002 — Request Parsing and HTTP Request Construction
- Objective: Finish the end-to-end request builder that turns CLI arguments into a validated HTTP request payload.
- In-progress scope:
  - ✅ Core parsing helpers for verbs, query args, shorthands, and localhost normalization (ported into `RequestParser` with Swift Testing specs).
  - 🔜 Extend coverage for remaining HTTPie shorthands (file embeds, raw JSON/file references, duplicate headers/data arrays) and map to a richer request model compatible with `swift-http-types`.
  - 🔜 Surface validation diagnostics (unknown separators, invalid URLs, mutually exclusive flags) through `SwiftPieCLI` with non-zero exit codes and stderr output.
  - 🔜 Bridge the parsed request into an internal representation that Phase 003 can hand to the transport layer.
- Candidate test plan: Expand unit specs for each shorthand permutation, add CLI-level tests that execute `SwiftPie` via the Testing process APIs, and capture stderr/exit codes for invalid inputs.
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

### Phase 007 — Peer Library & Example CLI
- Objective: Deliver the reusable peer-mode workflow described in `context/swiftpie.md` and showcase it with a Vapor-backed example that reuses the in-process test server responders.
- Proposed scope to confirm with user: Define the public API for embedding responders (swift-http-types based) and create an example executable (`Examples/PeerDemo` or similar) that runs the test server endpoints in peer mode.
- Candidate test plan: Unit specs for the peer adapter, a smoke test for the example CLI, and documentation snippets validated via doctests or executable previews.
- Exit artifact: Track progress in `context/phase-007.md`, including API diagrams and example wiring notes.

### Phase 008 — CLI Help & Usage Parity (Remaining P0)
- Objective: Align `SwiftPie --help` with `http --help`, including colorized formatting and accurate descriptions for all delivered features.
- Proposed scope to confirm with user: Implement a styled help renderer with ANSI colors mirroring HTTPie sections, sync existing option text with HTTPie wording, and add tooling/tests ensuring future flag additions update help text. Introduce a doc guideline that help must be updated with every CLI-facing change.
- Candidate test plan: Snapshot/spec tests for colored and plain help output, CLI integration tests invoking `--help`, and a harness that compares shared sections to `http --help`.
- Exit artifact: Track progress in `context/phase-008.md`.

### Phase 009 — Download Mode & Streaming
- Objective: Deliver `--download`, `--output`, and overwrite safeguards so large responses stream to disk similar to `httpie-go`.
- Proposed scope to confirm with user: Extend `RequestTransport` with streaming body support and progress hooks, add a file writer that uses temp files plus atomic moves, wire CLI parsing/rendering for the new flags, and expand the in-process server with chunked/large-payload fixtures.
- Candidate test plan: Transport unit specs covering chunked transfers and interrupted streams, integration tests saving responses to temporary directories (including overwrite/permission failures), and CLI assertions validating stdout/stderr separation plus exit codes.
- Exit artifact: Track progress in `context/phase-009.md`.

### Phase 010 — CLI Help Colorization
- Objective: Adopt Rainbow so the default `spie --help` output ships with ANSI styling consistent with HTTPie.
- Proposed scope to confirm with user: Add Rainbow as a dependency, teach the CLI help generator to emit colored sections/flags, and keep wording aligned with the current help copy.
- Candidate test plan: Manual verification of the help text in a color-capable terminal; no automated assertions planned because the output mirrors the literal source.
- Exit artifact: Track decisions and follow-ups in `context/phase-010.md`.

### Phase 011 — Method & URL Parity ✅
- Delivered: Parser now accepts arbitrary method tokens (with heuristics that keep GET/POST inference intact), localhost shorthands remain intact under a configurable default scheme, and the CLI exposes a `--ssl` switch that toggles the implicit scheme to `https://`. Help text nudges users toward either explicit protocols or the new switch, matching the agreed scope without reviving the `https` alias. Details live in `context/phase-011.md`.
- Follow-ups: Monitor bare-host heuristics and fold transport-capability warnings into the upcoming Phase 017 so peer mode can communicate unsupported options.

### Phase 012 — Request Body Defaults & CLI Flags ✅
- Delivered: JSON is now the default encoding for `key=value` items, with `--form` and `--raw` flipping to URL-encoded and pass-through bodies. Parser/builder support `=@file`, `:=@file`, header `:@file`, and `@-` stdin shorthands; transports respect the selected mode, and the CLI auto-emits HTTPie’s JSON `Accept` header unless callers override it. Help/docs updated per scope, and coverage recorded in `context/phase-012.md`.
- Follow-ups: Monitor stdin-heavy workflows for performance (streaming might be preferable in future) and revisit multipart defaulting when we add richer file metadata.

### Phase 013 — Redirects & Status Controls (Next P0)
- Objective: Implement `--follow`, `--check-status`, and related exit-code handling to reach httpie-go’s execution parity.
- Proposed scope to confirm with user: Add redirect following with loop protection and `--max-redirects`, wire `--check-status` exit mapping (including 3xx handling without follow), update response formatting for redirect chains, and expose stderr diagnostics for status failures.
- Candidate test plan: Integration tests using the in-process server to exercise redirect loops, 3xx/4xx/5xx cases with/without follow, and transport error boundaries; CLI assertions for exit codes and stderr messages.
- Exit artifact: Record redirects/status behaviour in `context/phase-013.md`.

### Phase 014 — Documentation & Release Readiness
- Objective: Prepare the project for an open-source initial release with polished onboarding and automation.
- Proposed scope to confirm with user: Rework the README and quick-start sections for both network and peer transports, surface feature parity status, integrate DocC generation into tooling, and script version bump/changelog scaffolding.
- Candidate test plan: Documentation linting/link checks, `swift build --configuration release`, and scripted walkthroughs of the published examples.
- Exit artifact: Capture doc/release decisions in `context/phase-014.md`.

### Phase 015 — Sessions & Cookie Persistence
- Objective: Introduce `--session`, read-only sessions, and cookie jar management to begin covering HTTPie doc parity beyond Go’s subset.
- Proposed scope to confirm with user: Define session file format and storage locations, persist cookies/auth headers between runs, expose CLI flags/help text, and ensure peer mode stays deterministic without session bleed.
- Candidate test plan: Integration tests that write/read session files across invocations (network and peer transports), unit specs for serialization edge cases, and CLI cases for read-only versus mutable sessions.
- Exit artifact: Track progress in `context/phase-015.md`.

### Phase 016 — Polish & Extended Parity
- Objective: Layer on advanced HTTPie behaviors (verbose mode, streaming output formatting, colors) and stabilize for release.
- Proposed scope to confirm with user: Additional CLI flags (verbose, offline, pretty-print), UX refinements, documentation, and packaging/distribution.
- Candidate test plan: Regression suite covering critical flags, golden-file output comparisons, documentation linting, and smoke tests across macOS targets.
- Exit artifact: Summarize outcomes in `context/phase-016.md`.

### Phase 017 — Transport Capabilities & Peer Parity (Queued P0)
- Objective: Introduce a capability model for transports so the CLI can warn on unsupported flags in peer mode and tighten behaviour around timeouts and protocol toggles.
- Scope to confirm: Define a `TransportCapabilities` surface for transports, push warnings through the CLI when options are ignored, wire peer-mode timeouts via Task cancellation, and update docs/help to spell out peer-specific differences.
- Test plan: Unit tests for capability negotiation, peer transport timeout exercises, and CLI integration coverage ensuring warnings appear (and options still function) when capabilities differ.
- Exit artifact: Track outcomes in `context/phase-017.md`, including guidance on when unsupported options should escalate to errors.

Plan Maintenance
----------------
- Revisit this roadmap after every phase review to incorporate feedback, add or reorder phases, and prune completed items.
- Ensure `context/index.md` lists all active plan and phase documents so future agents can navigate them quickly.
