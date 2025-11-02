# Phase 015 — Pluggable Transports & SwiftNIO

This phase introduces runtime-selectable transports so FoundationNetworking and SwiftNIO can both back the CLI on Darwin today, while keeping peer transports viable and paving the way for Linux validation. Work begins on macOS to keep iteration fast; Linux compilation/testing follow once the surface is stable.

## Objectives
- Ship a transport registry/capability model that lets the CLI choose between Foundation and NIO at runtime.
- Update existing transports (Foundation, peer fake/in-memory) to participate in that model.
- Implement a SwiftNIO-backed HTTP transport that matches current `RequestTransport` semantics.
- Surface a `--transport={foundation|nio}` flag, defaulting to Foundation when available, with validation and help text updates.
- Ensure both transports compile and pass tests on Darwin; document any gaps blocking Linux enablement.

## Darwin-First Execution Plan

1. **Audit current transport surface**
   - Trace how `RequestTransport` is constructed within `SwiftPieCLI` and how peer transports are injected.
   - Capture expectations around request/response mapping, error types, and concurrency (respecting Sendable guidance).
   - Identify any Foundation-specific assumptions (e.g., URLSession-specific configuration structs) that need abstraction.

2. **Define capability & registration scaffolding**
   - Sketch a lightweight `TransportDescriptor` (id, display name, capabilities) and `TransportCapabilities` enum/option set covering HTTP protocols, streaming, cookie/session support, etc.
   - Provide a registry/factory (likely static on `TransportManager`) that maps identifiers to builders.
   - Ensure peer transports can register statically even if they are not runtime-selectable.

3. **Plumb CLI selection**
   - Extend argument parsing to accept `--transport=<id>` with validation and user-friendly diagnostics.
   - Default to Foundation on platforms where it is available; fall back to NIO otherwise.
   - Update help text, `--help` output, and any usage docs touched in previous phases.
   - Add configuration flow that hands capability metadata to downstream components for warnings (sets up future flag gating).

4. **Refactor Foundation transport integration**
   - Wrap existing `URLSessionTransport` construction behind the registry, ensuring it advertises accurate capabilities.
   - Confirm concurrency annotations (Sendable, actor usage) align with the new abstraction.
   - Adapt tests so they select the transport via the registry rather than direct instantiation where possible.

5. **Implement SwiftNIO transport**
   - Choose primitives (likely `NIOHTTPClient` from AsyncHTTPClient or custom pipeline) that work on macOS today and Linux later.
   - Map `HTTPRequest`/`HTTPResponse` structures to NIO equivalents, handling streaming bodies in parity with Foundation transport.
   - Mirror error mapping (timeouts, TLS issues, DNS) so CLI exit codes remain consistent.
   - Manage lifecycle: event loop group ownership, connection reuse, graceful shutdown (especially important for CLI exit).

6. **Peer transport alignment**
   - Register peer transports with static identifiers to keep API coherent, even if selection stays compile-time.
   - Expose capabilities so the CLI can warn when runtime-only options are ignored.

7. **Documentation & developer ergonomics**
   - Record usage guidance in README/docs (or a dedicated transports doc) plus `context/phase-015.md`.
   - Capture any Linux blockers (e.g., missing TLS cert store hooks) discovered during macOS work.

## Test Strategy (Darwin)
- **Unit tests**
  - Registry/selector validation (unknown id, default selection, capability queries).
  - Capability warnings for peer transports and any flag interactions introduced during this phase.
  - Foundation and NIO transports: request construction, response normalization, error pathways.
- **Integration tests**
  - CLI invocations against the in-process SwiftNIO test server using both transports, asserting identical output/exit codes.
  - Peer transport smoke tests to ensure abstraction changes do not regress existing behaviour.
- **Platform checks**
  - `swift build` / `swift test` on macOS with `--enable-test-discovery` to confirm async and concurrency annotations hold.
  - Optional `swift build --triple x86_64-unknown-linux-gnu` (or similar) to catch compile-time gaps once Swift toolchain is configured.

## Open Questions / Follow-ups
- How aggressively should the NIO transport optimize connection pooling versus sticking to simple per-request clients initially?
- Do we need transport-specific timeout configurations in this phase, or defer to Phase 017 (capability warnings) to expose differences?
- What is the minimal capability vocabulary needed now versus future streaming/session work to avoid premature complexity?
- Are there existing integration tests that will need transport-selection parameters, or can defaults keep them stable?

## Audit Notes (Darwin Baseline)
- `RequestTransport` is a synchronous protocol returning `ResponsePayload`; `CLIContext` is generic over the transport and defaults to `URLSessionTransport()`.
- `TransportOptions` currently covers timeout, TLS verification, and HTTP/1 preference; CLI maps `--timeout`, `--verify`, and `--http1` directly into these fields.
- `URLSessionTransport` owns secure/insecure `URLSession` instances, handles request encoding via `RequestPayloadEncoding`, and mirrors options by adjusting headers/timeouts; errors are normalized to `TransportError`.
- `PeerTransport` reuses the same encoding helpers, enforces `Connection: close` when HTTP/1 is requested, and executes async responders via a semaphore bridge.
- CLI option parsing (`OptionParser`) lacks transport selection today; help text lists transport-related flags but nothing about a transport selector.
- Tests instantiate transports either through `CLIContext()` (default URLSessionTransport) or custom `TransportRecorder`; integration tests rely on `SwiftPieTestSupport`’s in-process server for real `URLSessionTransport` behaviour.

## Registry & Capability Design Draft
- Introduce `TransportID` (wrapper around the CLI identifier string) plus static well-known IDs (`foundation`, `nio`, `peer`).
- Add `TransportCapabilities` as an `OptionSet` capturing:
  - `.supportsTLSVerificationToggle`
  - `.supportsHTTP2`
  - `.supportsStreamingUpload`
  - `.supportsStreamingDownload`
  - `.supportsCookies`
  - `.supportsPeerMode` (maps to transports that never touch the network)
- Define `TransportDescriptor` with:
  - `id: TransportID`
  - `label: String` (for help/diagnostics)
  - `kind: TransportKind` enum (`runtimeSelectable`, `peerOnly`) controlling CLI exposure
  - `capabilities: TransportCapabilities`
  - `isSupported: () -> Bool` closure so descriptors can advertise platform availability
  - `makeTransport: () throws -> AnyRequestTransport`
- Provide `TransportRegistry` owning the descriptor list plus helper methods:
  - `defaultID` (prefer `foundation` when supported, fall back to `nio`)
  - `descriptor(for:)` and `runtimeSelectableDescriptors()`
  - Mutation APIs hidden; registry is constructed once through static `standard` but tests/peer entry points can supply custom registries.
- Update `CLIContext` to accept a registry (defaulting to `.standard`) and to expose a mutable `transport: AnyRequestTransport` so CLIRunner can swap implementations after parsing options.
- Extend CLI parsing so `OptionParser` receives allowable IDs from the registry, validates `--transport=<id>`, and records `selectedTransportID`.
- Adjust help text to list available runtime transports dynamically (e.g., “--transport {foundation|nio}” when both are present).
- Provide command diagnostics: unknown transport values, attempts to select peer transports via CLI, and friendly error if requested transport is unavailable on the current platform.

## Work Log — Step 2
- Added `AnyRequestTransport`, `TransportID`, `TransportCapabilities`, `TransportDescriptor`, and `TransportRegistry` so transports can be described, capability-tagged, and instantiated by identifier (`Sources/SwiftPie/Transport.swift`).
- Reworked `CLIContext`/`CLIRunner` to be transport-agnostic (type-erased) and to carry a registry for runtime selection (`Sources/SwiftPie/SwiftPie.swift`).
- Exposed `--transport` in argument parsing with validation/error messaging, plus dynamic help output listing available runtime transports (`Sources/SwiftPie/SwiftPie.swift`).
- Introduced CLI tests covering transport selection success/failure paths and ensured help output references the new flag (`Tests/SwiftPieTests/CLIRunnerTests.swift`).
- Validated with `swift test --cache-path .cache --disable-sandbox` (passes under sandbox configuration without network access).
