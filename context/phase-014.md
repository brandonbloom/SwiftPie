# Phase 014 Notes — Pretty Output Controls

## Objectives
- Add `--pretty` CLI flag matching HTTPie’s modes (`all`, `colors`, `format`, `none`).
- Default to prettified output for terminal sessions while emitting raw responses for redirected output.
- Respect the selected mode throughout response rendering, covering colorization and JSON indentation.

## Implementation Highlights
- Extended the CLI option parser to accept `--pretty`, validate the supplied mode, and surface explicit usage errors for unknown values.
- Introduced `PrettyMode` plumbing in `CLIRunner` so defaults key off the console’s TTY status and the value flows into the formatter.
- Updated `ResponseFormatter` to gate ANSI styling and JSON pretty printing according to the resolved mode.
- Refreshed the help output and feature checklist to document the new flag and defaults.

## Test Plan
- Response formatter unit tests cover color/formatting combinations and ensure raw output for `--pretty=none`.
- CLI runner integration tests verify default behaviour for TTY/non-TTY consoles, explicit mode overrides, and invalid values.
- `swift test --disable-sandbox`; expect to run locally when the harness allows binding loopback sockets.

## Validation
- Added new specs in `CLIRunnerTests` and `ResponseFormatterTests` covering all pretty-mode permutations and terminal heuristics.
- `CLANG_MODULE_CACHE_PATH=.cache/clang swift test --disable-sandbox` runs were attempted; transport suites fail to bind loopback sockets under the harness (`Operation not permitted`). Re-run the test suite locally to confirm passing status.

## Follow-ups
- Consider adding richer syntax highlighting for JSON bodies once `--print`/`--style` lands.
- Evaluate caching vendored SwiftPM dependencies locally so tests can run without internet access.
