SwiftPie Feature Checklist
=============================

Legend:
- Priorities — **P0**: match httpie-go baseline, **P1**: close gaps highlighted by HTTPie docs/examples, **P2**: broader HTTPie parity, **P3**: stretch/extensibility.
- Status icons — HTTPie ✅, httpie-go ✅/⚠️/❌.

## HTTP Method & URL Handling
- [x] **P0 Methods & verb inference** — HTTPie ✅ | httpie-go ✅ — Custom verbs plus GET/POST defaults based on body presence. (Phase 011 added method-token heuristics on top of the Phase 002 inference.)
- [ ] **P0 URL defaults & localhost shortcuts** — HTTPie ✅ | httpie-go ⚠️ — Default scheme, `https` alias, `:/` shorthand; Go lacks `--default-scheme` and `--path-as-is`. (Phase 011 introduced the `--ssl` default-scheme toggle and base-URL support; the playful `https` alias remains intentionally omitted.)
- [ ] **P2 Additional URL controls (`--default-scheme`, `--path-as-is`)** — HTTPie ✅ | httpie-go ❌ — Expose explicit scheme override and disable path normalization.

## Request Item Syntax & Payload Shorthands
- [x] **P0 Header/data/parameter items (`:`, `=`, `==`)** — HTTPie ✅ | httpie-go ✅ — Colon headers, JSON fields, and query parameter shorthand. (Phase 002 parser + tests cover duplicates and escaping.)
- [ ] **P0 Raw JSON fields (`:=`, `:=@`)** — HTTPie ✅ | httpie-go ✅ — Preserve non-string JSON types and embed JSON files verbatim. (`:=` supported; file embeds `:=@` still route through the file field path.)
- [ ] **P0 File value expansion (`@file`, `@-`)** — HTTPie ✅ | httpie-go ✅ — Read values from files/stdin across headers, params, and data fields. (`@file` works; stdin `@-` and header-from-file plumbing missing.)
- [ ] **P0 Form data (`--form`) with auto-multipart on file fields** — HTTPie ✅ | httpie-go ✅ — URL-encoded forms by default, multipart when uploads present. (No CLI flag yet; defaults differ from HTTPie/httpie-go.)
- [x] **P0 Basic multipart file upload (`field@file`)** — HTTPie ✅ | httpie-go ✅ — Stream file parts with inferred MIME type. (Multipart encoding kicks in when files are present; MIME override support later.)
- [ ] **P0 Raw body via piped stdin** — HTTPie ✅ | httpie-go ✅ — Treat piped stdin as body when no key/value items are supplied. (Standard input currently unused for request bodies.)
- [x] **P2 Request item escaping (`\`)** — HTTPie ✅ | httpie-go ❌ — Allow literal separators by escaping `:` `=` `@`. (Escaped separators covered by Phase 002 parser.)
- [ ] **P2 Nested JSON path syntax (`foo[bar]=baz`)** — HTTPie ✅ | httpie-go ❌ — Build nested objects and arrays inline.
- [ ] **P2 Explicit raw body flags (`--raw`, `--data`, scalar JSON bodies)** — HTTPie ✅ | httpie-go ❌ — Accept arbitrary payloads without constructing objects.
- [ ] **P2 Explicit multipart control (`--multipart`, `--boundary`)** — HTTPie ✅ | httpie-go ❌ — Force multipart form and customize boundary strings.
- [ ] **P2 File content-type overrides (`field@file;type=mime`)** — HTTPie ✅ | httpie-go ❌ — Respect explicit MIME hints on uploads.

## JSON & Output Defaults
- [ ] **P0 Default JSON behavior & `--json` flag** — HTTPie ✅ | httpie-go ✅ — Auto `Content-Type: application/json` and allow forcing Accept header. (Current encoder falls back to form bodies unless JSON types are explicit; CLI flag TBD.)
- [ ] **P2 JSON response detection with faulty `Content-Type`** — HTTPie ✅ | httpie-go ❌ — Heuristically format JSON even when servers mislabel payloads.

## Headers & Cookies
- [x] **P0 Custom headers & multi-value support** — HTTPie ✅ | httpie-go ✅ — Override defaults, set repeated headers, and customize Host. (Phase 002 builder keeps duplicates and header removals.)
- [ ] **P0 Header values from files (`Header:@file`)** — HTTPie ✅ | httpie-go ✅ — Expand file content directly into header fields.
- [x] **P2 Header removal & empty headers (`Header:` / `Header;`)** — HTTPie ✅ | httpie-go ❌ — Unset defaults or send explicit empty values. (Phase 002 parser + builder propagate removals and explicit blanks.)
- [ ] **P2 Response header limit control (`--max-headers`)** — HTTPie ✅ | httpie-go ❌ — Abort when the response sends too many headers.
- [ ] **P1 Cookie persistence via sessions** — HTTPie ✅ | httpie-go ❌ — Manage cookie jars tied to session files and host binding.

## Authentication & Security
- [x] **P0 Basic auth `-a user:pass` with password prompt** — HTTPie ✅ | httpie-go ✅ — Prompt for missing password when username provided. (Phase 006 ✅)
- [x] **P0 TLS verification toggle (`--verify`)** — HTTPie ✅ | httpie-go ✅ — Allow disabling certificate validation. (Phase 006 ✅)
- [x] **P0 Force HTTP/1.1 (`--http1`)** — HTTPie ✅ | httpie-go ✅ — Disable HTTP/2 upgrades where needed. (Phase 006 ✅ — ensure behaviour against HTTP/2 servers.)
- [x] **P0 Timeout control (`--timeout`)** — HTTPie ✅ | httpie-go ✅ — Cap total request duration (infinite when downloading). (Phase 006 ✅)
- [ ] **P2 Extended auth (`--auth-type`, bearer, digest, plugins)** — HTTPie ✅ | httpie-go ❌ — Support additional credential strategies beyond basic. (Bearer implemented in Phase 006; digest/plugins pending.)
- [ ] **P2 Client certificates & TLS tuning (`--cert`, `--cert-key`, `--ssl`)** — HTTPie ✅ | httpie-go ❌ — Supply client certs/keys and tweak TLS versions/ciphers.

## Transport & Execution Controls
- [x] **P0 Follow redirects (`--follow`)** — HTTPie ✅ | httpie-go ✅ — Honor 30x responses with loop protection. (Phase 013 added `--follow`/`-F` with `--max-redirects` and CLI-rendered redirect history.)
- [x] **P0 Exit on HTTP errors (`--check-status`)** — HTTPie ✅ | httpie-go ✅ — Map 3xx–5xx statuses to non-zero exit codes. (Phase 013 wired HTTPie exit codes and stderr diagnostics.)
- [x] **P0 Ignore stdin (`--ignore-stdin`)** — HTTPie ✅ | httpie-go ✅ — Avoid unintended stdin consumption. (Phase 006 ✅)
- [ ] **P0 Download mode (`--download`, `--output`, `--overwrite`)** — HTTPie ✅ | httpie-go ✅ — Save bodies to files with progress and naming rules. (➡️ Phase 007)
- [ ] **P1 Offline mode (`--offline`)** — HTTPie ✅ | httpie-go ❌ — Render requests without sending them (doc example parity).
- [ ] **P1 Session management (`--session`, `--session-read-only`, upgrade)** — HTTPie ✅ | httpie-go ❌ — Persist headers/auth/cookies between runs. (➡️ Phase 010)
- [ ] **P1 Download resume (`--continue`)** — HTTPie ✅ | httpie-go ❌ — Resume partial downloads when supported by server.
- [ ] **P2 Proxy support (`--proxy`, env vars)** — HTTPie ✅ | httpie-go ❌ — Route traffic through HTTP/SOCKS proxies.
- [ ] **P2 Streamed responses (`--stream`)** — HTTPie ✅ | httpie-go ❌ — Flush response chunks incrementally even when prettified.
- [ ] **P2 Chunked & compressed request options (`--chunked`, `--compress`)** — HTTPie ✅ | httpie-go ❌ — Control transfer encoding for requests.

## Output & UX
- [ ] **P0 Print selection (`--print`, `--headers`, `--body`)** — HTTPie ✅ | httpie-go ✅ — Choose which parts of the exchange to display.
- [ ] **P0 Verbose request/response (`-v`)** — HTTPie ✅ | httpie-go ✅ — Show full request and response messages.
- [x] **P0 Pretty formatting toggles (`--pretty=all|colors|format|none`)** — HTTPie ✅ | httpie-go ✅ — Control formatting and color usage. (Phase 014 ✅)
- [ ] **P1 Extra verbose & metadata (`--meta`, `-vv`)** — HTTPie ✅ | httpie-go ❌ — Report timing and connection metadata.
- [ ] **P1 Quiet mode (`--quiet`, `-qq`)** — HTTPie ✅ | httpie-go ❌ — Suppress output except errors (and optionally warnings).
- [ ] **P1 History printing (`--history-print`, `--all`)** — HTTPie ✅ | httpie-go ❌ — Display intermediate redirects or multiple responses.
- [ ] **P2 Custom styles & themes (`--style`, `--pretty=colors`, `--format-options`)** — HTTPie ✅ | httpie-go ❌ — Offer palette and formatting customization.
- [ ] **P2 Response charset override (`--response-charset`)** — HTTPie ✅ | httpie-go ❌ — Force output encoding when auto-detection fails.
- [ ] **P2 Binary body handling controls** — HTTPie ✅ | httpie-go ❌ — Mirror HTTPie’s binary suppression warnings and toggles.

## Config & Extensibility
- [ ] **P2 Config file support (`config.json`, defaults)** — HTTPie ✅ | httpie-go ❌ — Honor per-user defaults (e.g., implicit form mode).
- [ ] **P3 Plugin manager commands (`httpie cli plugins ...`)** — HTTPie ✅ | httpie-go ❌ — Install, list, upgrade, and uninstall CLI plugins.
- [ ] **P2 Update warning opt-outs** — HTTPie ✅ | httpie-go ❌ — Surface release notifications with config knob to disable.
