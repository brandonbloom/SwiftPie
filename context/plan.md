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

### Phase 002 — Request Parsing and HTTP Request Construction ✅
- Delivered: CLI argument parsing now runs through `RequestParser` and `RequestBuilder`, producing `HTTPRequest` payloads compatible with `swift-http-types` and surfacing diagnostics on stderr with `EX_USAGE` exits. Unit coverage exercises HTTPie shorthands (escaped separators, file embeds, duplicate headers/data arrays), localhost normalization, and method inference.
- Follow-ups: Track escaping parity via GH-18 (separator edge cases) as we round out the remaining parser backlog.
- Exit artifact: `context/phase-002.md`.

### Phase 003 — Transport Hook & Response Handling ✅
- Delivered: Introduced the `RequestTransport` protocol with fake implementations for tests, added `ResponseFormatter`, and wired the CLI to render HTTPie-style status lines/headers/bodies with proper exit-code mapping for transport failures. `swift test` covers success, client/server error, and transport-error formatting paths.
- Follow-ups: Pretty/style toggles remain in later phases; ensure new output flags exercised in Phase 014/016 reuse this formatter.
- Exit artifact: `context/phase-003.md`.

### Phase 004 — Local Test Server ✅
- Delivered: Added the SwiftNIO-backed `SwiftPieTestSupport` server helpers plus httpbin-style endpoints (`/get`, `/post`, `/headers`, `/status/<code>`, redirects, cookies) and request-recording utilities. Integration tests run entirely in-process via `withTestServer`.
- Follow-ups: Chunked streaming, delay endpoints, and TLS fixtures remain open for Phases 009 and 005 follow-ups.
- Exit artifact: `context/phase-004.md`.

### Phase 005 — Real Network Transport ✅
- Delivered: Replaced the placeholder transport with `URLSessionTransport`, bridging multipart/JSON/form encoding to the network layer, normalising responses through `HTTPTypes`, and integrating the transport into the CLI. Added dedicated `URLSessionTransportTests` covering happy paths and network failures.
- Follow-ups: Add TLS fixtures, streaming uploads/downloads, and expose configuration knobs (timeouts, proxies) through the CLI when we extend Phase 009/016.
- Exit artifact: `context/phase-005.md`.

### Phase 006 — Authentication & Core Flags (Go Parity) ✅
- Delivered: Added `-a/--auth`, `--auth-type`, `--timeout`, `--verify`, `--http1`, and `--ignore-stdin`. Password prompts now disable terminal echo, transport options flow through `URLSessionTransport`, and CLI tests cover auth headers, prompt failure paths, and validation.
- Follow-ups: Extend TLS verification to accept CA bundle paths, add `--ignore-netrc` (GH-5), and revisit advanced auth schemes in later parity phases.
- Exit artifact: `context/phase-006.md`.

### Phase 007 — Peer Library & Example CLI ✅
- Delivered: Shipped `PeerTransport` and supporting helpers for in-process responders, refactored test server responders for reuse, added `PeerDemo` plus docs, and extended smoke tests to cover both executables.
- Follow-ups: Coordinate future transport capability warnings (Phase 015) so peer mode advertises unsupported flags clearly.
- Exit artifact: `context/phase-007.md`, including API diagrams and example wiring notes.

### Phase 008 — CLI Help & Usage Parity ✅
- Delivered: CLI help now renders HTTPie-style sections with Rainbow styling, surfaces every shipped flag, and falls back to plain formatting when stdout isn’t a TTY. Copy is centralised in the `CLIRunner` help builder so new options stay in sync.
- Validation: `CLIRunnerTests.displaysHelpForEmptyArguments` exercises the help path end-to-end; pretty-mode specs cover the same terminal detection the help output relies on. Manual `spie --help` checks are noted in `context/phase-010.md`.
- Follow-ups: Defer automated diffs against upstream HTTPie help until the CLI surface stabilises; continue to require help updates alongside any new flags.

### Phase 009 — Download Mode & Streaming
- Objective: Deliver `--download`, `--output`, and overwrite safeguards so large responses stream to disk similar to `httpie-go`.
- Proposed scope to confirm with user: Extend `RequestTransport` with streaming body support and progress hooks, add a file writer that uses temp files plus atomic moves, wire CLI parsing/rendering for the new flags, and expand the in-process server with chunked/large-payload fixtures.
- Candidate test plan: Transport unit specs covering chunked transfers and interrupted streams, integration tests saving responses to temporary directories (including overwrite/permission failures), and CLI assertions validating stdout/stderr separation plus exit codes.
- Targets: GH-6 (`--output`), GH-7 (`--download`), GH-9 (`--continue`), GH-22 (`--stream`).
- Exit artifact: Track progress in `context/phase-009.md`.

### Phase 010 — CLI Help Colorization ✅
- Delivered: Adopted Rainbow, refactored the help renderer to apply ANSI styling that mirrors HTTPie’s headings/flag colors, and kept non-TTY output plaintext. Manual `spie --help` runs verified readability across themes.
- Follow-ups: Consider future flags for forcing colors off/on once broader response colorization lands.
- Exit artifact: `context/phase-010.md`.

### Phase 011 — Method & URL Parity ✅
- Delivered: Parser now accepts arbitrary method tokens (with heuristics that keep GET/POST inference intact), localhost shorthands remain intact under a configurable default scheme, and the CLI exposes a `--ssl` switch that toggles the implicit scheme to `https://`. Help text nudges users toward either explicit protocols or the new switch, matching the agreed scope without reviving the `https` alias. Details live in `context/phase-011.md`.
- Follow-ups: Monitor bare-host heuristics and fold transport-capability warnings into the upcoming Phase 015 so peer mode can communicate unsupported options.

### Phase 012 — Request Body Defaults & CLI Flags ✅
- Delivered: JSON is now the default encoding for `key=value` items, with `--form` and `--raw` flipping to URL-encoded and pass-through bodies. Parser/builder support `=@file`, `:=@file`, header `:@file`, and `@-` stdin shorthands; transports respect the selected mode, and the CLI auto-emits HTTPie’s JSON `Accept` header unless callers override it. Help/docs updated per scope, and coverage recorded in `context/phase-012.md`.
- Follow-ups: Monitor stdin-heavy workflows for performance (streaming might be preferable in future), revisit multipart defaulting when we add richer file metadata, and expose custom boundaries via `--boundary` (GH-17).

### Phase 013 — Redirects & Status Controls ✅
- Delivered: CLI exposes `--follow`/`-F`, `--max-redirects`, and `--check-status`; redirect chains now render hop-by-hop, loop limits raise exit code 6 with stderr diagnostics, and HTTP 3xx/4xx/5xx map to HTTPie exit codes when requested. URLSession transport no longer auto-follows so history stays deterministic. Notes captured in `context/phase-013.md`.
- Follow-ups: Future phases should add redirect history printing controls (`--all`, `--history-print`) and streaming-friendly output once broader output tooling lands (see Phases 014/016).

### Phase 014 — Pretty Output Controls ✅
- Delivered: Added `--pretty` CLI flag and `PrettyMode` plumbing so colors/JSON formatting track HTTPie expectations with terminal-aware defaults; `ResponseFormatter` now formats JSON and applies ANSI styling when appropriate.
- Validation: New `CLIRunner` and `ResponseFormatter` tests exercise each mode and terminal heuristic; attempted `swift test --disable-sandbox` inside this environment but URLSession transport specs fail when binding sockets (`Operation not permitted`). Run the suite locally to confirm network-dependent tests.
- Follow-ups: Consider richer syntax highlighting and streaming-aware formatting alongside future `--print`/`--style` work.

### Phase 015 — Pluggable Transports & SwiftNIO (Queued P0)
- Objective: Deliver runtime-selectable HTTP transports so SwiftPie can exercise both FoundationNetworking and SwiftNIO on Darwin today and hit Linux parity without container friction, while keeping peer transports viable.
- Scope to confirm with user: Introduce a transport registry/capability surface, ship a SwiftNIO-backed transport alongside the existing `URLSessionTransport`, ensure both compile on Darwin/Linux, add a `--transport={foundation|nio}` CLI flag with defaults/validation, and refactor peer transports to plug into the same capability model (static selection only).
- Candidate test plan: Unit tests for capability negotiation/selection, integration tests that run the CLI against the in-process server using each transport on Darwin, peer transport smoke tests, and Linux build checks to catch compile-time gaps even if execution remains local for now.
- Exit artifact: Track outcomes and follow-ups in `context/phase-015.md`, including documentation on selecting transports and any Linux-specific blockers.

### Phase 016 — Sessions & Cookie Persistence
- Objective: Introduce `--session`, read-only sessions, and cookie jar management to begin covering HTTPie doc parity beyond Go’s subset.
- Proposed scope to confirm with user: Define session file format and storage locations, persist cookies/auth headers between runs, expose CLI flags/help text, and ensure peer mode stays deterministic without session bleed.
- Candidate test plan: Integration tests that write/read session files across invocations (network and peer transports), unit specs for serialization edge cases, and CLI cases for read-only versus mutable sessions.
- Exit artifact: Track progress in `context/phase-016.md`.

### Phase 017 — Polish & Extended Parity
- Objective: Layer on advanced HTTPie behaviors (verbose mode, streaming output formatting, colors) and stabilize for release.
- Proposed scope to confirm with user: Additional CLI flags (verbose, offline, pretty-print), UX refinements, documentation, and packaging/distribution.
- Candidate test plan: Regression suite covering critical flags, golden-file output comparisons, documentation linting, and smoke tests across macOS targets.
- Targets: GH-1/GH-14 (`--unsorted`/`--sorted`), GH-20 (`--all`), GH-13 (`--print` family), GH-4 (`--style`), GH-15 (`--format-options`), GH-16 (`--response-mime`), GH-12 (`--response-charset`), GH-21 (help completeness), GH-23 (`--version` flag).
- Exit artifact: Summarize outcomes in `context/phase-017.md`.

### Phase 018 — Linux Packaging & CI
- Objective: Finish the cross-platform story so SwiftPie builds, tests, and ships cleanly on Linux alongside macOS.
- Proposed scope to confirm with user: Audit dependencies for Linux compatibility, wire up CI runners, document toolchain requirements, and produce release artifacts or install scripts targeting common distros.
- Candidate test plan: Stand up Linux CI (swift test + smoke invocations), run packaging scripts locally in a container, and verify CLI behaviours that depend on Darwin APIs gracefully degrade or are guarded.
- Targets: GH-27 (Linux support).
- Exit artifact: Capture findings and distro-specific notes in `context/phase-018.md`.

Plan Maintenance
----------------
- Revisit this roadmap after every phase review to incorporate feedback, add or reorder phases, and prune completed items.
- Ensure `context/index.md` lists all active plan and phase documents so future agents can navigate them quickly.
