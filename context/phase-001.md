# Phase 001 — CLI Skeleton and Package Scaffolding

## Objectives
- Create a SwiftPM package that exposes a reusable core module plus a CLI executable.
- Provide a placeholder `SwiftHTTPie.main` to route future CLI behavior.
- Add a simple smoke test to keep the CLI build runnable while features are stubbed.

## Decisions
- Split the package into `SwiftHTTPie` (library) and `SwiftHTTPieCLI` (executable) to keep CLI wiring thin and make the core testable in isolation later.
- Implemented a minimal argument handler that always shows help when no arguments are supplied and prints a construction notice otherwise.
- Introduced `scripts/smoke-cli.sh` for the Phase 001 validation check; this wraps `swift build` and a `swift run SwiftHTTPie --help` invocation.
- `SwiftHTTPie.main` now mirrors standard entry-point behavior by terminating the process, while `SwiftHTTPie.run` remains available for callers that need the exit code without exiting.

## Test Results
- `scripts/smoke-cli.sh` ✅
