# Dependency Upgrade Log

Date: 2026-10-08
Project: system_resource_protection_script
Languages: Go, Bash; Nix and Docker distribution definitions

## Qualification status

No dependency upgrade has been qualified or adopted yet. The complete current Go manifest has 28 requirements. A live Go module-proxy audit found eight requirements already at their latest version and 20 with newer versions on their existing module paths. Three direct dependencies also have newer major module paths.

Each dependency will be researched, migrated, and tested separately. A passing compiler invocation alone does not establish real service behavior, terminal interaction, installer compatibility, or performance. Release publication remains gated on those checks.

## Baseline and remote admission

The frozen baseline is `b6b440f13ca45944ec534a501cfa5bb6e21c4f50`. Installer bytes at this commit have SHA-256 `a37fb479e261c22cff90fb9fcaab47366961c37474f546da79d232e90ac82d67`.

Two normal RCH attempts ended with `queue_timeout` and exit 103 before compilation; neither is a test receipt. The installed GoTest reservation classifier uses the build-slot default and ignores the test-slot default and Go `-p` option. The next genuine baseline invocation uses both per-invocation `RCH_BUILD_SLOTS=2` and `RCH_TEST_SLOTS=2`, forwarded `GOMAXPROCS=2`, and `go test -p 2 ./...`. Remote execution remains mandatory. These settings do not alter worker capacity, admission pressure, priority, or local fallback.

The project-scoped `.rch/config.toml` preserves the user's 14 existing allowed commands and adds only `go`. The merged configuration lint passes. The genuine baseline completed with exit 0 on `vmi1156319` at 2026-10-08T22:03:39Z, reserved exactly two slots, and downloaded Go 1.27.2 on the worker. All five packages reported `[no test files]`; this establishes the existing compiler/vet baseline, not runtime or service coverage. The clean-overlay receipt binds Git tree `ccc6288a7be1a9a8d7d5b41c9f3d000df99f8f22` and overlay fingerprint `fe0d5151031be8fda7951fe7fe1f42f7ce344018fdb3ed21e6ada866b230b195` to the frozen baseline commit.

The reservation defect and exercised workaround are tracked in [RCH #94](https://github.com/Dicklesworthstone/remote_compilation_helper/issues/94). New RCH invocations were subsequently held because installed transfer/pruning/clean-overlay teardown deletes files, contrary to the session's retention rule; see [RCH #95](https://github.com/Dicklesworthstone/remote_compilation_helper/issues/95). The already-submitted released-binary runtime job also ended with `queue_timeout` at 22:14:01Z before remote execution. It supplies no runtime or source-transfer proof. No dependency compiler retry is authorized until a retention-safe route is established.

## Direct dependencies and major migrations

| Current dependency | Existing-path latest | Latest stable major | Research and gate |
|---|---|---|---|
| `github.com/charmbracelet/bubbletea` 1.3.4 | 1.3.10 | `charm.land/bubbletea/v2` 2.1.0 | [Pinned upstream upgrade guide](https://github.com/charmbracelet/bubbletea/blob/v2.1.0/UPGRADE_GUIDE_V2.md). Changes include declarative `tea.View`, keyboard event/text handling, and mouse event APIs. Preserve Unicode input, scrolling, selection, and terminal restoration; compare rendering latency and allocations. Requires Go 1.26. |
| `github.com/charmbracelet/lipgloss` 1.1.0 | 1.1.0 | `charm.land/lipgloss/v2` 2.0.6 | [Pinned upstream upgrade guide](https://github.com/charmbracelet/lipgloss/blob/v2.0.6/UPGRADE_GUIDE_V2.md). Review color-profile handling and Bubble Tea interoperability before adopting. Requires Go 1.25. |
| `github.com/shirou/gopsutil/v3` 3.23.12 | 3.24.5 | `github.com/shirou/gopsutil/v4` 4.26.9 | [Pinned upstream README](https://github.com/shirou/gopsutil/blob/v4.26.9/README.md) and [v4 migration release notes](https://github.com/shirou/gopsutil/releases/tag/v4.24.5). v3 receives only serious security fixes. Initial v4 changes include unsigned UID/GID/group values, moving host temperatures to `sensors`, and memory extension structs. Review subsequent releases and collector errors; preserve sampling cadence, process visibility, CPU accounting, and platform behavior. Requires Go 1.26. |

The latest-major versions and minimum Go versions above were read from the official Go module proxy on 2026-10-08. They are research targets, not a statement of compatibility or successful adoption.

## Complete existing-path audit

The official registry endpoints are `https://proxy.golang.org/<module>/@latest` and the corresponding versioned `.mod` files. The retained audit records the exact URLs, timestamps, upstream commit hashes, and module contents.

| Module | Current | Registry latest | Status |
|---|---|---|---|
| `github.com/aymanbagabas/go-osc52/v2` | 2.0.1 | 2.0.1 | Already latest; retain |
| `github.com/charmbracelet/colorprofile` | 0.2.3-0.20250311203215-f60798e515dc | 0.4.3 | Existing Git-derived reference preserved pending explicit migration |
| `github.com/charmbracelet/x/ansi` | 0.8.0 | 0.11.9 | Research and isolated tests pending |
| `github.com/charmbracelet/x/cellbuf` | 0.0.13-0.20250311204145-2c3ea96c31dd | 0.0.15 | Existing Git-derived reference preserved pending explicit migration |
| `github.com/charmbracelet/x/term` | 0.2.1 | 0.2.2 | Research and isolated tests pending |
| `github.com/erikgeiser/coninput` | 0.0.0-20211004153227-1c3628e74d0f | Same reference | Preserve Git-derived reference |
| `github.com/go-ole/go-ole` | 1.2.6 | 1.3.0 | Research and isolated tests pending |
| `github.com/lucasb-eyer/go-colorful` | 1.2.0 | 1.4.1 | Research and isolated tests pending |
| `github.com/lufia/plan9stats` | 0.0.0-20211012122336-39d0f177ccd0 | 0.0.0-20260802145828-341c2f0c90b5 | Preserve Git-derived reference; platform qualification pending |
| `github.com/mattn/go-isatty` | 0.0.20 | 0.0.24 | Research and isolated tests pending |
| `github.com/mattn/go-localereader` | 0.0.1 | 0.0.1 | Already latest; retain |
| `github.com/mattn/go-runewidth` | 0.0.16 | 0.0.31 | Research Unicode width changes; isolated tests pending |
| `github.com/muesli/ansi` | 0.0.0-20230316100256-276c6243b2f6 | Same reference | Preserve Git-derived reference |
| `github.com/muesli/cancelreader` | 0.2.2 | 0.2.2 | Already latest; retain |
| `github.com/muesli/termenv` | 0.16.0 | 0.16.0 | Already latest; retain |
| `github.com/power-devops/perfstat` | 0.0.0-20210106213030-5aafc221ea8c | 0.0.0-20260916203055-22a1a467d9f0 | Preserve Git-derived reference; platform qualification pending |
| `github.com/rivo/uniseg` | 0.4.7 | 0.4.7 | Already latest; retain |
| `github.com/shoenig/go-m1cpu` | 0.1.6 | 0.2.4 | Go 1.26; Apple CPU sampling tests pending |
| `github.com/tklauser/go-sysconf` | 0.3.12 | 0.4.0 | Go 1.25; platform tests pending |
| `github.com/tklauser/numcpus` | 0.6.1 | 0.12.0 | Go 1.25; platform tests pending |
| `github.com/xo/terminfo` | 0.0.0-20220910002029-abceb7e1c41e | 1.2.0 | Existing Git-derived reference preserved pending explicit migration |
| `github.com/yusufpapurcu/wmi` | 1.2.3 | 1.2.4 | Windows/WSL-related platform tests pending |
| `golang.org/x/sync` | 0.11.0 | 0.23.0 | Go 1.26; isolated tests pending |
| `golang.org/x/sys` | 0.30.0 | 0.48.0 | Go 1.26; platform tests pending |
| `golang.org/x/text` | 0.3.8 | 0.42.0 | Go 1.26; Unicode behavior tests pending |

## Other distribution dependencies

- `flake.nix` pins the old `nixos-24.05` branch and has no committed lock file. NixOS 26.05 is the current stable research target. Preserve existing Git references until a real Nix evaluation/build confirms the migration.
- `Dockerfile` uses the moving `debian:stable-slim` tag. An existing prebuilt image may be used for isolated runtime qualification; no host service configuration or image cleanup is authorized.
- `HomebrewFormula/srps.rb` still points to 1.4.1, whereas the latest GitHub release is 1.4.2. Update the formula only to an existing qualified version with its actual archive checksum.
- End-user installation is expected to consume prebuilt binaries with the Bash fallback. The installer source-build fallback needs review against that policy before a new release.

## Remaining release gates

- Complete the genuine pinned baseline, then test each adopted dependency separately.
- Run real Linux and WSL fresh-install, upgrade, inherited `DRY_RUN`, explicit plan, ananicy overrides, large-RAM settings, and service behavior in an isolated environment.
- Compare performance against the frozen baseline on the same admitted worker; require no regression.
- Confirm Agentic Coding Flywheel Setup's pinned installer remains compatible through the owning agent's integration lane.
- Build performance-optimized supported-platform binaries through DSR/RCH and verify installer download paths and archive checksums.
- Publish only qualified tags/assets and applicable package venues. No GitHub Actions, existing tag replacement, or existing asset replacement is part of this qualification.

The open owned issue [#5](https://github.com/Dicklesworthstone/system_resource_protection_script/issues/5) tracks the release qualification and remains open. There are no open pull requests or bug-type Beads in the observed project state; two open enhancement/epic Beads remain untouched.

Closed security report [#4](https://github.com/Dicklesworthstone/system_resource_protection_script/issues/4) concerned GO-2026-5970 in the declared old `golang.org/x/text` dependency. Its reporter closed it after a v1.4.2 Govulncheck run reported no reachable vulnerabilities. That historical result does not replace a fresh vulnerability and reachability scan of the eventual updated release candidate.
