# Phase 008 Notes — CLI Help & Usage Parity

## Objectives
- Mirror `http --help` with color-aware sections and wording that reflects all SwiftPie features delivered to date.
- Keep the help surface maintainable so every new CLI flag or behaviour updates the shared renderer and tests.

## Implementation Highlights
- Rebuilt the `helpText` generator in `CLIRunner` (see `Sources/SwiftPie/SwiftPie.swift`) to emit HTTPie-style sections with Rainbow styling for headings, flags, separators, and examples. Terminal detection falls back to plain output automatically.
- Consolidated help copy alongside the parser so new options (e.g. `--follow`, `--pretty`, `--ssl`) are documented in one place; contributors are now expected to touch this builder whenever CLI flags change.
- Grouped positional argument guidance into labeled blocks that match HTTPie’s terminology (`URL`, `REQUEST_ITEM`) while calling out SwiftPie-specific defaults such as JSON encoding and stdin shorthands.

## Test Coverage
- `CLIRunnerTests.displaysHelpForEmptyArguments` exercises the help path end-to-end, asserting the canonical sections appear and exit code 0 is returned when no arguments are provided.
- Additional CLI runner specs validate pretty-mode defaults for TTY/non-TTY consoles, indirectly confirming the color detection used by the help renderer.
- Manual `spie --help` spot checks (logged during Phase 010) confirmed ANSI styling renders legibly with Rainbow’s palette.

## Decisions & Follow-ups
- We intentionally document only shipped flags—no “coming soon” placeholders—so the help output always reflects real functionality.
- A snapshot/diff harness against upstream HTTPie help was deemed brittle; future parity audits can re-evaluate this once the CLI surface stabilises.
- Maintain the existing integration test coverage; expand with explicit snapshot tests only if future refactors make regressions likely.
