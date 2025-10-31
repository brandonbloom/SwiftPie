# Plan Alignment Review — 2025-11-05

This refresh captures how the current roadmap (`context/plan.md`) lines up with
the SwiftPie concept and the httpie-go parity target after Phase 007.

## Concept Alignment
- ✅ **CLI foundation (Phases 001 – 006):** CLI scaffold, rich argument parsing,
  real `URLSessionTransport`, and the new auth/timeout/TLS flags satisfy the core
  “Swift HTTPie CLI” concept goals.
- ✅ **Peer-mode deliverable (Phase 007):** `PeerTransport`, shared responders,
  and the `PeerDemo` executable land the clientless workflow promised in
  `context/swiftpie.md`, with tests exercising the in-process adapter.
- ⚠️ **Developer experience guardrails:** We still lack documented best practices
  for integrating the peer transport into external apps (dependency lifecycle,
  logging, metrics). Capturing those patterns in DocC/README remains open.

## httpie-go Baseline Snapshot (P0 scope)
- **Delivered**
  - Request parser handles headers/data/query shorthands, escaping, header
    removals, duplicate fields, and multipart uploads when files are present
    (Phase 002 + `RequestPayloadEncoding`).
  - CLI flags for `-a/--auth`, bearer auth, password prompting, `--verify`,
    `--timeout`, `--http1`, and `--ignore-stdin` propagate cleanly into the
    transport (Phase 006, `CLIRunnerTests`).
  - Default transport bridges to `URLSession`, respecting timeout/TLS options and
    returning formatted output; peer transport and example executable verify the
    alternate execution path (Phases 005 – 007).

- **Partial / Divergent**
  - HTTP method handling infers GET/POST correctly but rejects custom verbs and
    keeps the default scheme at `http://`, whereas httpie-go accepts arbitrary
    methods and supports the `https` alias.
  - JSON request defaults still favour URL-encoded forms unless a `:=` field is
    present; httpie-go auto-emits JSON for bare `key=value` payloads and exposes
    `--json`.
  - `:=` JSON literals work, but `:=@file` falls back to the file-field path,
    and `@-` (stdin) expansion is unimplemented.
  - Response rendering prints a minimal status/header/body view and lacks
    `--print`, `-v`, and pretty controls.
  - `SwiftPie --help` shows a terse option list without HTTPie-style grouping,
    colors, or wording alignment.

- **Missing**
  - CLI surface for `--form`, `--json`, raw body flags, and stdin piping; these
    are essential for httpie-go parity on request construction.
  - Execution controls such as `--follow`, `--check-status`, and download/output
    management (`--download`, `--output`, overwrite safeguards) are absent.
  - Output/UX toggles (`--print`, `-v`, `--pretty`, quiet/history flags) and
    response heuristics (JSON/coercion) are unscheduled.
  - Configuration and session management (`--session`, proxy support, config
    files) remain future phases, matching the broader roadmap.

## Planning Adjustments
1. **Lock in the remaining P0 work.** Newly added Phases 008–012 cover help
   parity, download/output flows, method/URL behaviour, request body defaults,
   and redirect/status controls so all baseline gaps are scheduled before we
   return to P1 features.
2. **Add a milestone for method/default-scheme parity.** Track custom verb
   passthrough and the HTTPS alias so CLI behaviour matches httpie-go (captured
   in Phase 010).
3. **Document peer transport integration.** Extend Phase 007 follow-ups (or add
   a doc-focused sub-phase) to produce DocC/README guidance on embedding the peer
   adapter, satisfying the remaining concept DX gap.
4. **Keep `context/feature-checklist.md` in lockstep.** Update the checklist
   (already refreshed in this review) whenever new flags or behaviours land so
  parity gaps stay visible.
