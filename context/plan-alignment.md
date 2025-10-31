# Plan Alignment Review — 2025-11-02

This note captures how the current phase roadmap (`context/plan.md`) lines up with
the original SwiftHTTPie concept and the HTTPie/httpie-go feature checklist.

## Concept Deliverables
- ✅ Phases 001 – 005 focus on bringing the CLI from scaffold to a working
  transport that can hit real HTTP endpoints, matching the “Swift implementation
  of an HTTPie-like CLI tool” portion of `context/concept.md`.
- ⚠️ No phase presently targets the companion library needed for “clientless”
  HTTPie-style CLIs in Vapor. The roadmap lacks milestones for defining the
  reusable request/response handler API or demonstrating it inside a sample
  Vapor target (a core part of `context/swifthttpie.md`).
- ⚠️ Developer experience goals called out in the concept (bootstrapping
  dependencies, handler lifecycle, Vapor integration) have no assigned owner or
  acceptance tests in the plan yet.

## Feature Checklist Coverage Snapshot
- **HTTP Method & URL Handling (P0)** — Method inference and localhost shorthands
  landed in Phase 002, but support remains limited to the fixed
  `HTTPMethod` cases (`TRACE`, `CONNECT`, custom verbs are rejected) and the
  `:alias` shorthand currently produces `http://localhost:alias` instead of
  HTTPie’s `https://alias` behaviour.
- **Request Item Syntax & Payload Shorthands (P0)** — Core separators (`:`, `=`,
  `:=`, `==`) and basic file embeds are implemented, yet HTTPie’s stdin piping
  (`@-`), header-from-file (`Header:@file`), and `--form`/`--json` toggles are
  absent. The transport defaults to URL-encoded form bodies for plain `=` items,
  diverging from HTTPie’s JSON-first default.
- **JSON & Output Defaults (P0)** — Pretty/JSON flags are unimplemented and
  heuristics for mislabeled responses are deferred; current output is a minimal
  status/header dump without formatting controls.
- **Headers & Cookies (P0/P1)** — Header overrides/removals work, but header
  file expansion, cookie jars, and session-backed persistence (P1) are untreated.
- **Authentication & Security (P0)** — No CLI surface for `-a/--auth`,
  `--verify`, `--timeout`, or HTTP/1.1 forcing; TLS knobs are unscheduled.
- **Transport Controls (P0)** — Redirect following, `--check-status`,
  download/output management, and stdin suppression remain unplanned despite
  being baseline behaviours in HTTPie/httpie-go.
- **Output & UX (P0/P1)** — Verbose/quiet/print selectors, color/pretty flags,
  and history/meta options are not yet on the roadmap.
- **Config & Extensibility (P2+)** — No phases address config files, proxy
  support, streams, plugins, or update notifications.

## Recommended Adjustments
- Introduce a dedicated phase for the library/clientless deliverable (API shape,
  Vapor integration example, handler lifecycle tests) so the project satisfies
  the core concept, not just the CLI.
- Re-sequence upcoming CLI phases to burn down the remaining P0 checklist items
  (auth flags, redirect controls, download/session basics, stdin handling)
  before stretching into P1/P2 ergonomics.
- Update `context/feature-checklist.md` alongside each phase to mark delivered
  behaviours, keeping gaps visible for future planning.
