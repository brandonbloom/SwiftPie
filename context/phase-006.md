# Phase 006 Notes — Authentication & Core Flags

## Objectives
- Implement the authentication and verification flags needed for parity with `httpie-go` (`-a/--auth`, prompt fallback, `--auth-type=` bearer).
- Surface TLS verification control (`--verify`), timeout configuration (`--timeout`), HTTP protocol selection (`--http1`), and stdin suppression (`--ignore-stdin`).
- Ensure new switches integrate cleanly with the existing request parsing and transport layers, including sensible error messaging and exit codes.

## Open Questions
- Should we support additional auth schemes (digest, NTLM) now or defer to a later parity phase?
- Confirm desired UX for password prompts on non-interactive stdin (match HTTPie’s failure mode or return a specific diagnostic).
- Decide whether TLS verification toggles require future certificate pinning hooks or just pass-through to `URLSessionConfiguration`.

## Decisions
- Defer non-basic/bearer auth schemes to a later parity phase once the CLI flag plumbing is in place.
- When a password is required but stdin is non-interactive (or `--ignore-stdin` is set), surface a clear CLI error explaining that prompting is unavailable.
- Treat `--verify` as a boolean flag for now: it toggles transport trust evaluation without CA bundle/file inputs. Future work can extend this to path-based overrides.
## Test Plan
- Unit-test credential parsing (username-only, escaped separators, bearer tokens) and option validation.
- CLI integration tests covering: auth prompts (interactive vs `--ignore-stdin`), TLS verify off/on, timeout enforcement, and HTTP/1-only requests against the local test server.
- Regression tests ensuring existing request parsing remains unchanged when new flags are absent.

## Progress
- Extended the option parser to cover `-a/--auth`, `--auth-type`, `--timeout`, `--verify`, `--http1`, and `--ignore-stdin`, wiring new errors into the CLI flow.
- Added interactive password prompting via `InputSource`, with explicit failures when stdin is non-interactive or ignored.
- Hardened the password prompt by disabling terminal echo (termios) when reading credentials so secrets are not displayed.
- Introduced `TransportOptions` so timeout, TLS verification, and HTTP/1 preferences reach `URLSessionTransport`; the transport now flips `Connection: close` for HTTP/1 and allows insecure trust when `--verify=false`.
- Exercised the new behaviors with `CLIRunnerTests` cases for auth headers, prompts, option validation, and transport propagation.
- Ran `swift test` (passes) after implementation.

## Follow-ups
- Update `context/feature-checklist.md` after each delivered flag to keep P0 parity signals accurate. ✅ (Phase 006 features marked complete.)
- Coordinate with Phase 007 to share any new streaming/timeout helpers so download mode can reuse them.
- Extend `--verify` handling to accept CA bundle paths and richer TLS tweaks once planned.
- Validate the HTTP/1 enforcement strategy against a confirmed HTTP/2-capable endpoint and revise if additional transport hooks are required.
