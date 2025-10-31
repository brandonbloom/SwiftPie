# Phase 009 Notes — Download Mode & Streaming

## Objectives
- Implement `--download` and `--output` so large responses stream to disk instead of stdout.
- Enforce overwrite safeguards and resume-friendly behavior aligned with HTTPie.
- Preserve CLI UX expectations for progress reporting, stdout/stderr separation, and exit codes.

## Proposed Scope
- Extend `RequestTransport` with streaming body support plus progress callbacks safe for both URLSession and peer transports.
- Introduce a file writer that streams to temporary files, enforces overwrite protections, and moves atomically into place on success (with hooks for future resume support).
- Teach the CLI parser about `--download`, `--output`, and related toggles, routing progress metadata to stderr while keeping stdout quiet.
- Expand `SwiftPieTestSupport` with chunked/large-payload endpoints to serve as deterministic fixtures.

## Test Plan Draft
- Transport unit specs covering chunked transfers, incomplete streams, and progress notifications.
- Integration tests that download responses to temporary directories, asserting file contents, metadata, and overwrite/permission failure handling.
- CLI assertions validating stdout/stderr separation, progress output, and exit codes for success and error paths.

## Open Questions
- Do we need resumable downloads in the first iteration or can we ship append-only safeguards first?
- Should progress reporting be textual (HTTPie-style) or structured for future TUI integrations?
- How should `--download` interact with streaming-only responses or transports that lack `Content-Length`?
