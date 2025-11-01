# Phase 012 Notes — Request Body Defaults & CLI Flags

## Objectives
- Align request-body inference with httpie-go so plain `key=value` arguments emit JSON by default unless overridden.
- Expose `--json`, `--form`, and `--raw` CLI flags to control encoding mode explicitly.
- Support header/data file expansion (`Header@file`, `field=@file`, `field:=@file`) plus `@-` stdin piping with helpful validation errors.
- Refresh CLI help and docs to describe the new behaviours.

## Test Plan
- Request parser specs covering new file/input tokens: `name=@file`, `name:=@file`, header `Header@file`, and stdin `@-`.
- Builder/encoding tests for each body mode:
  - default JSON inference from `key=value`.
  - forced form mode via `--form`.
  - forced JSON via `--json`.
  - raw body handling with `--raw` and stdin/file sources.
  - multipart when file uploads present.
- CLI integration tests ensuring flags drive encoding, invalid combinations raise usage errors, and stdin piping obeys `--ignore-stdin`.
- Update / add docs snapshots after behaviour changes.

## Implementation Notes
- Extend CLI option parsing to surface a `BodyMode` enum.
- Rework `RequestPayloadEncoding` to honor explicit mode while keeping multipart precedence when files are present.
- Introduce file/stdin loaders that integrate with existing `InputSource` abstraction for tests.

## 2025-11-01 Progress
- Added `InputSource.readAllData()` so CLI can materialize stdin for body fields, headers, and `--raw` payloads.
- Introduced `RequestPayload.BodyMode`/`RawBody` plus parser/build updates for `=@file`, `:=@file`, and `@-` handling; builder now validates form/json/raw conflicts.
- Implemented `--json`, `--form`, and `--raw` option parsing with conflict detection, stdin gating, and file-backed raw bodies.
- Updated transports to respect the new body modes; default `key=value` items now yield JSON, `--form` toggles URL encoding, and raw mode bypasses content-type defaults.
- `--json` now forces the classic HTTPie Accept header (`application/json, */*;q=0.5`) unless the user overrides it explicitly.
- Expanded tests across parser, builder, CLI runner, and `URLSessionTransport` to cover stdin/file embeds, body mode flags, and error conditions; `swift test` on 2025-11-01.
