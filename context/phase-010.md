# Phase 010 Notes — CLI Help Colorization

## Objectives
- Adopt the Rainbow package so the CLI can emit ANSI-styled help text.
- Highlight the `usage:` and `options:` sections plus individual flags to align with HTTPie’s colored help experience.
- Keep the color selections conservative (readable on both dark and light terminals) and default to Rainbow’s automatic detection for TTY support.

## Agreed Scope
- Add Rainbow as a dependency of `SwiftPie`.
- Update the CLI help generator to build its output with Rainbow styles while preserving the existing copy.
- Leave broader output colorization (`--print`, `--pretty`, response highlights) for future phases.

## Test Plan
- Rely on the existing CLI smoke coverage; no additional automated assertions for the colorized help output.
- Manually run `spie --help` to confirm formatting reads correctly in a standard ANSI-capable terminal.

## Notes
- Consider exposing a future flag to disable colors explicitly once broader colorization lands.
- Reorganized the help copy into sections (Usage, Positional Arguments, Authentication, Transport) to mirror HTTPie’s structure while reflecting current feature support.
- Updated the color palette to mirror HTTPie’s defaults (green section headings, magenta switches, cool-toned metavars) so output stays legible on light themes.

## Validation
- `swift test`
