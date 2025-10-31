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

### Phase 003 — Handler Execution and Response Rendering
- Objective: Execute parsed requests against a fake transport and render responses with HTTPie-style formatting.
- Proposed scope to confirm with user: Define a transport protocol, provide in-memory/fake implementations for tests, and build response/body formatting (colors, truncation, headers ordering).
- Candidate test plan: Use fake transports to drive success/error/status-line scenarios, snapshot assertions for formatted output, and verify stderr noise for failures/timeouts.
- Exit artifact: Document decisions/tests in `context/phase-003.md`.

### Phase 004 — Network Transport Integration
- Objective: Wire the transport protocol into a real HTTP client implementation.
- Proposed scope to confirm with user: Choose a concrete client (e.g., `URLSession` or `AsyncHTTPClient`), support streaming bodies, TLS/custom trust hooks, and map request/response metadata between layers.
- Candidate test plan: Integration tests hitting a local test server (or HTTPBin fixtures) validating verbs, headers, payload types, redirects, and error propagation; ensure the fake transport remains supported for deterministic tests.
- Exit artifact: Capture architecture decisions in `context/phase-004.md`.

### Phase 005 — Session Management, Downloads, and Auth Flags
- Objective: Reach parity with httpie-go for sessions, downloads, and authentication options.
- Proposed scope to confirm with user: Session persistence format/location, download streaming to files/stdout, credential parsing (basic, bearer, prompt) and related CLI switches; ensure compatibility with JSON/form payloads established in Phase 002.
- Candidate test plan: Integration tests exercising session reuse across invocations, download verification via fixtures, and auth flows including prompt suppression.
- Exit artifact: Track progress in `context/phase-005.md`.

### Phase 006 — Polish and Extended HTTPie Parity
- Objective: Layer on advanced HTTPie behaviors (verbose mode, streaming, colors) and stabilize for release.
- Proposed scope to confirm with user: Additional CLI flags (verbose, offline, pretty-print), UX refinements, documentation, and packaging/distribution.
- Candidate test plan: Regression suite covering critical flags, golden-file output comparisons, documentation linting, and smoke tests across macOS targets.
- Exit artifact: Summarize outcomes in `context/phase-006.md`.

Plan Maintenance
----------------
- Revisit this roadmap after every phase review to incorporate feedback, add or reorder phases, and prune completed items.
- Ensure `context/index.md` lists all active plan and phase documents so future agents can navigate them quickly.
