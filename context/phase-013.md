# Phase 013 Notes — Redirects & Status Controls

## Objectives
- Add `--follow` (and `--max-redirects`) so the CLI can chase redirect chains with loop protection.
- Wire `--check-status` to produce HTTPie-style exit codes for 3xx/4xx/5xx responses and surface stderr diagnostics.
- Ensure redirect chains render cleanly for the user while keeping the transport layer deterministic.

## Test Plan
- Unit-level coverage in `CLIRunnerTests` for:
  - Default success exits on 4xx/5xx without `--check-status`.
  - `--check-status` returning exit codes 3/4/5 with stderr warnings.
  - `--follow` reissuing requests and rendering every hop, including `--max-redirects` failures.
  - `--follow` + `--check-status` using the final response status.
- Response formatter tests validating multi-response output formatting.
- Full `swift test` regression run after implementation.

## 2025-11-01 Progress
- Extended `OptionParser`/`ParsedCLIOptions` with `--follow`, `--max-redirects`, and `--check-status` (including validation and help text updates).
- Added redirect management to `CLIRunner`: iteratively resends requests, clears bodies when required by RFC semantics, enforces hop limits, and maps errors to HTTPie exit codes with stderr messaging.
- Updated `ResponseFormatter` to print redirect histories and to derive reason phrases when the transport omits them.
- Hardened `URLSessionTransport` by disabling implicit redirect chasing so the CLI can manage history deterministically.
- Introduced targeted tests in `CLIRunnerTests` plus new formatter coverage; `swift test` passes.
- Feature checklist and plan documents updated; `swift test` (2025-11-01) captures the final validation run.
