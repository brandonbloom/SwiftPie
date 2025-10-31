# Phase 008 Notes — CLI Help & Usage Parity

## Objectives
- Rebuild the CLI help/usage output so it mirrors `http --help` for all delivered
  features, including colorized sections and consistent wording.
- Ensure help text evolves alongside new functionality by codifying review
  checklists and test coverage.

## Proposed Scope
- Introduce a styled help renderer that outputs colorized sections similar to
  HTTPie (headers, argument groups, option lists) with terminal detection.
- Sync existing option descriptions with HTTPie phrasing for matching features
  and introduce placeholders for not-yet-implemented flags.
- Add developer tooling/tests that diff SwiftPie’s help output against captured
  expectations and optionally against the system `http --help` for overlapping
  sections.
- Document a contribution guideline requiring every new CLI flag or behaviour to
  update help text and associated tests.

## Test Plan Draft
- Snapshot/spec tests asserting the formatted help output (including ANSI
  sequences when colors are enabled and plain output otherwise).
- Integration smoke test invoking `SwiftPie --help` through the CLI runner to
  ensure exit code, stdout, and stderr align with expectations.
- Optional comparison harness that fetches `http --help` at test time (or via a
  fixture) to verify shared sections stay aligned.

## Open Questions
- Do we surface unreleased flags with “Coming soon” notes or hide them until
  implementation?
- How strict should the help-vs-HTTPie diffing be when HTTPie changes upstream?
