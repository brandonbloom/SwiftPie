# Context Overview

## Documents
- [./concept.md](./concept.md) -- High-level SwiftPie project concept.
- [./swiftpie.md](./swiftpie.md) -- Working vision, workflow, and feature priorities.
- [./naming.md](./naming.md) -- Notes on project branding decisions and executable naming.
- [./feature-checklist.md](./feature-checklist.md) -- HTTPie vs httpie-go feature parity checklist with Swift priorities.
- [./plan.md](./plan.md) -- Incremental delivery plan and phase workflow checkpoints.
- [./coding-guidelines.md](./coding-guidelines.md) -- Language and contribution guidelines.
- [./plan-alignment.md](./plan-alignment.md) -- Snapshot of how the phase roadmap tracks against the concept and feature checklist.
- `./phase-00N.md` -- Phase-specific notes, tests, and review outcomes captured per phase (create on demand).
- [./phase-001.md](./phase-001.md) -- Phase 001 notes capturing CLI scaffold decisions and test results.
- [./phase-002.md](./phase-002.md) -- Phase 002 notes on request parsing scope, reference tests, and follow-ups.
- [./phase-003.md](./phase-003.md) -- Phase 003 notes covering transport abstraction, fake implementations, and CLI response rendering.
- [./phase-004.md](./phase-004.md) -- Phase 004 notes on the in-process Swift HTTP test server design, endpoints, and fixtures.
- [./phase-005.md](./phase-005.md) -- Phase 005 notes on the real network transport and CLI integration.
- [./phase-006.md](./phase-006.md) -- Phase 006 notes on authentication, verification, and timeout flags.
- [./phase-007.md](./phase-007.md) -- Phase 007 notes on the peer-mode library and example CLI workflow.
- [./phase-008.md](./phase-008.md) -- Phase 008 notes on download mode, file streaming, and overwrite safeguards.

## Submodules

Several context subdirectories are Git submodules containing related codebases
to be used for reference.

- [./httpie](./httpie) -- Official Python implementation of HTTPie.
- [./httpie-go](./httpie-go) -- Port of HTTPie to Go.
- [./pier](./pier) -- Extension to HTTPie adding "clientless" operation.
- [./vapor](./vapor) -- Swift web framework.
