# Phase 011 Notes — Method & URL Parity

## Objectives
- Accept arbitrary HTTP method tokens while retaining default inference rules.
- Provide a user-facing knob to prefer `https://` when no scheme is supplied.
- Keep existing localhost shorthands functional under the new defaults.

## Scope & Decisions
- Introduced a flexible `HTTPMethod` wrapper and parser heuristics so uppercase/custom tokens (e.g. `PURGE`) are treated as explicit methods. Lowercase variants of the well-known verbs continue to work.
- Added `RequestParserOptions` with configurable default scheme and optional base URL; CLI now exposes scheme selection via `--ssl`, and peer mode can resolve relative paths without extra glue.
- Declined to add an `https` executable alias per user guidance; help text now nudges users toward `https://` URLs or `--ssl`.

## Tests
- `swift test` (2025-10-31)

## Follow-ups
- Monitor for edge cases where the method heuristic might misclassify bare hostnames without dots; consider richer detection if this surfaces.
- Plan Phase 017 work on transport capabilities so peer mode can warn on unsupported flags and still exercise timeout behaviour via task cancellation.
