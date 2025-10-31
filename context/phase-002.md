# Phase 002 Notes — Request Parsing

## Objectives
- Implement CLI argument parsing for method inference, URL normalization, headers, data, file embeds, and query params.
- Surface invalid combinations via non-zero exit codes backed by tests.

## Reference Test Suites
- `context/httpie/tests/test_cli.py#L22`: `TestItemParsing` exercises `KeyValueArgType` covering escaped separators, headers vs data classification, file embeds, JSON/raw payload markers, and duplicate fields.
- `context/httpie/tests/test_cli.py#L152`: `TestQuerystring` ensures query params are combined correctly when provided inline or via `==`.
- `context/httpie/tests/test_cli.py#L195`: `TestLocalhostShorthand` verifies colon-based localhost expansion and IPv6 handling.
- `context/httpie/tests/test_cli.py#L239`: `TestArgumentParser` covers method guessing based on positional arguments and inline items.
- `context/httpie/tests/test_cli.py#L320`: `TestNoOptions`/`TestStdin`/`TestSchemes` provide additional validation scenarios for `--no-*`, stdin handling, and scheme resolution.

## Porting Candidates
- Mirror `KeyValueArgType` behaviours to Swift helpers to ensure consistent parsing of `=`, `:=`, `==`, `:` and escaped separators.
- Recreate URL shorthand expansion (`:` → localhost) and method inference logic in unit tests.
- Add integration-style tests that simulate CLI invocation for invalid flags (`--no-war`), stdin suppression, and scheme resolution to validate exit paths.

## Gaps & Follow-ups
- `context/httpie-go` submodule currently mirrors the Python repository and does not contain Go sources or tests; unable to mine Go fixtures locally.
- Confirm with user if an alternative Go reference is available or if Python suite alignment is sufficient.

## 2025-10-30 Progress
- Added `SwiftHTTPieCoreTests/RequestParserTests.swift` scenarios mirroring `TestItemParsing`, `TestQuerystring`, `TestLocalhostShorthand`, and method inference cases via the Swift Testing `#expect` macro.
- Implemented `RequestParser` backing types to satisfy tests: separator discovery with escape handling, JSON value decoding, localhost shorthand expansion, and query merge behaviour.
- Adopted the toolchain-provided Testing module (macOS 14 baseline) so `swift test` runs cleanly without external dependencies or deprecation warnings.

## 2025-10-30 Completion
- Pulled in `swift-http-types` and introduced `RequestBuilder` to translate `ParsedRequest` into `HTTPRequest` plus body/files metadata exposed through a new `RequestPayload`.
- Replaced the CLI placeholder flow with `RequestParser` → `RequestBuilder`, surfaced parser/build errors on stderr with `EX_USAGE`, and provided injectable `CLIContext`/`Console` hooks for future transport integration.
- Extended parser coverage for duplicate headers/data and file embeds; added `RequestBuilderTests` and `CLIRunnerTests` to exercise success/error paths and ensure exit codes/output align with expectations (`swift test` now runs 12 specs).
- The current `requestSink` in `CLIContext` is intentionally one-way: Phase 002 stops after preparing a `RequestPayload`, leaving Phase 003 to define a RoundTripper/Handler-style abstraction that returns responses.
