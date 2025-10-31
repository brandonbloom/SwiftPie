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

### Phase 001 — CLI Skeleton and Package Scaffolding
- Objective: Establish a Swift Package that builds a runnable CLI entry point invoking a placeholder `SwiftHTTPie.main`.
- Proposed scope to confirm with user: SwiftPM package layout, minimal command-line parsing, stub handler invocation, automation hook for running upcoming tests.
- Candidate test plan: `swift test` target verifying the CLI module wires up `SwiftHTTPie.main`, plus a smoke test driving `swift run` to ensure exit status 0.
- Exit artifact: Create `context/phase-001.md` capturing decisions, test results, and review notes.

### Phase 002 — Request Parsing and HTTP Request Construction
- Objective: Implement argument parsing needed for HTTP verb, URL, headers, and JSON body shorthands mirroring the baseline HTTPie feature set.
- Proposed scope to confirm with user: Input normalization utilities, request model, and mapping to `swift-http-types` structures.
- Candidate test plan: Unit tests for argument parsing permutations and conversions, plus integration tests invoking the CLI with fixture inputs.
- Exit artifact: Append findings and review notes to `context/phase-002.md`.

### Phase 003 — Handler Execution and Response Rendering
- Objective: Execute Vapor (or protocol-conforming) handlers via `SwiftHTTPie.main`, render responses with status line, headers, and body formatting.
- Proposed scope to confirm with user: Handler protocol, dependency injection surface, response formatting with optional color output.
- Candidate test plan: TDD around fake handlers to cover success/error responses, streaming fallback behavior, and CLI output snapshots.
- Exit artifact: Document decisions/tests in `context/phase-003.md`.

### Phase 004 — Session Management, Downloads, and Auth Flags
- Objective: Reach parity with httpie-go for sessions, downloads, and authentication options.
- Proposed scope to confirm with user: Session persistence strategy, file download handling, credential parsing, and related CLI switches.
- Candidate test plan: Integration tests around persisted sessions, download output validation, and auth flag coverage.
- Exit artifact: Track progress in `context/phase-004.md`.

### Phase 005 — Polish and Extended HTTPie Parity
- Objective: Layer on advanced HTTPie behaviors (verbose mode, streaming, colors) and stabilize for release.
- Proposed scope to confirm with user: Additional CLI flags, UX refinements, documentation, and packaging.
- Candidate test plan: Regression suite covering critical flags, golden-file output comparisons, and documentation validation.
- Exit artifact: Summarize outcomes in `context/phase-005.md`.

Plan Maintenance
----------------
- Revisit this roadmap after every phase review to incorporate feedback, add or reorder phases, and prune completed items.
- Ensure `context/index.md` lists all active plan and phase documents so future agents can navigate them quickly.
