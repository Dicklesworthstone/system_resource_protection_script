# Changelog

All notable changes to **SRPS** (System Resource Protection Script) are documented here.

Repo: <https://github.com/Dicklesworthstone/system_resource_protection_script>

Versions are listed in reverse chronological order by tag date. Where the
v1.1.x Go-TUI polish series and the v1.2.x--v1.4.x feature series ran in
parallel, both tracks are documented at their actual tag dates.

---

## [Unreleased]

Post-v1.4.1 work on `main` (not yet tagged).

### Changed
- **License** updated to MIT with OpenAI/Anthropic Rider ([b76316b], [5f9f3ab]).
- Dropped all legacy `SRPS_SYSMON_*` env-var fallbacks; only `SRPS_SYSMONI_*` vars are recognized now ([82f0196], [492f270]).
- Docs updated to reference `sysmoni` JSON env name ([d3fd0bc]).

### Housekeeping
- Homebrew formula bumped post-release ([4920b63]).
- Added ACFS notification workflows for installer changes and lesson-registry sync ([a9632da], [a7045f0]).
- Beads configuration, gitignore patterns, and ephemeral-file cleanup ([236f7c9], [e012e7a], [0b77d15], [837fba4], [7ddbd9f], [26acb2a], [d8c52f3]).
- MIT LICENSE file added ([424118d]).

---

## [v1.4.1] -- 2025-11-26

**Breaking rename: `sysmon` -> `sysmoni`** to avoid conflict with Microsoft Sysmon.

### Breaking
- Binary, installer, TUI strings, env vars, and release assets all renamed from `sysmon`/`sysmon-go` to `sysmoni`/`sysmoni-go` ([1f69cc3]).
- Release assets now publish `sysmoni-linux-{amd64,arm64}`.
- Legacy `SRPS_SYSMON_*` env vars still accepted in this release for migration (removed post-v1.4.1).

### Changed
- SHA256SUMS regenerated after install-script rename ([85b485f]).

[v1.4.1]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.4.0...v1.4.1

---

## [v1.1.8] -- 2025-11-26

Maintenance-only tag. No code changes since v1.1.7.

### Housekeeping
- Re-verified SHA256SUMS; re-published release assets ([2088c3c]).

[v1.1.8]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.1.7...v1.1.8

---

## [v1.1.7] -- 2025-11-26

### Improved
- Global style consistency across TUI panels (titles, badges, table headers) ([92723bd]).
- Count badges for process and throttled lists.
- Pulsing critical badges for CPU/MEM/SWAP; tidied load mini-gauge styling.
- Fixed help-header padding to keep title centered.

[v1.1.7]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.1.6...v1.1.7

---

## [v1.1.6] -- 2025-11-26

### Fixed
- Single-column dashboard width math tightened to prevent layout overflow ([d722517]).
- Top pane auto-expands; right column kept minimal.

### Housekeeping
- Homebrew formula updated ([08b932a]).

[v1.1.6]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.1.5...v1.1.6

---

## [v1.1.5] -- 2025-11-25

### Improved
- Narrow/single-pane layout auto-expands the Top pane to use remaining terminal width, eliminating wasted space ([9b5600e]).

### Housekeeping
- Homebrew formula updated ([1e35f16]).

[v1.1.5]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.1.4...v1.1.5

---

## [v1.1.4] -- 2025-11-25

### Added
- **Scrollable Top list** with `j`/`k`, PgUp/PgDn, Home/End; viewport-clamped so no rows clip off-screen ([5607a11]).

### Improved
- Dashboard wide layout dedicates ~75% width to processes; card widths clamped to reduce wasted space.

[v1.1.4]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.1.3...v1.1.4

---

## [v1.1.3] -- 2025-11-25

### Fixed
- Wide-layout panel overflow: right-column widths clamped; multi-column process tables respect available space ([e215aae]).

### Improved
- Installer reports power source (AC/Battery); shellcheck warning resolved.

[v1.1.3]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.4.0...v1.1.3

---

## [v1.4.0] -- 2025-11-24

**"The Interactive Update"** -- massive TUI overhaul.

### Added
- Interactive table with row selection ([b2e02a7]).
- Filter/search bar with live text input.
- Scrollable log viewport.
- Mouse support.
- Dynamic help footer.

### Improved
- Adaptive light/dark mode colors via Bubble Tea `lipgloss` adaptive palette.
- Upgraded to `bubbles` table, viewport, textinput, and help components.

[v1.4.0]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.3.3...v1.4.0

---

## [v1.3.3] -- 2025-11-24

### Added
- ESC key now quits the TUI, matching `q` and Ctrl+C ([e931584]).

[v1.3.3]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.3.2...v1.3.3

---

## [v1.3.2] -- 2025-11-24

### Fixed
- Quoted `curl` format string to satisfy shellcheck ([80253d7]).

[v1.3.2]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.3.1...v1.3.2

---

## [v1.3.1] -- 2025-11-24

**"Smart Installer"**

### Added
- Installer auto-resolves `main` to the latest release tag when fetching pre-built binaries, avoiding unnecessary source builds ([29f4ef5]).
- CI lint job now enforces SHA256SUMS are up-to-date ([ed5b67e]).

[v1.3.1]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.3.0...v1.3.1

---

## [v1.3.0] -- 2025-11-24

### Fixed
- SHA256SUMS updated to match current `install.sh`, resolving verification errors during installation ([6a26f09]).

[v1.3.0]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.2.9...v1.3.0

---

## [v1.2.9] -- 2025-11-24

### Fixed
- `cursor-guard`: corrected `pgrep` usage that produced a double-zero, breaking JSON output ([c38853a]).

[v1.2.9]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.2.8...v1.2.9

---

## [v1.2.8] -- 2025-11-24

### Improved
- Smoke tests now emit verbose failure output for CI diagnosis; assertions relaxed where appropriate ([fe61f1d]).

[v1.2.8]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.2.7...v1.2.8

---

## [v1.2.7] -- 2025-11-24

### Fixed
- `cursor-guard`: hardened JSON output logic to prevent syntax errors in test environments ([ef63109]).

[v1.2.7]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.2.6...v1.2.7

---

## [v1.2.6] -- 2025-11-24

### Fixed
- Smoke-test extraction regex now handles whitespace in heredoc tokens ([b6c5c5d]).

[v1.2.6]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.2.5...v1.2.6

---

## [v1.2.5] -- 2025-11-24

### Fixed
- Smoke-test extraction markers corrected to exclude heredoc token ([e1a2dfe]).

[v1.2.5]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.2.4...v1.2.5

---

## [v1.2.4] -- 2025-11-24

### Fixed
- Smoke-test extraction regex handles indented markers ([85fad3a]).

[v1.2.4]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.2.3...v1.2.4

---

## [v1.2.3] -- 2025-11-24

### Fixed
- Smoke-test extraction switched to function-name markers for robustness ([4972c3e]).

[v1.2.3]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.2.2...v1.2.3

---

## [v1.2.2] -- 2025-11-24

### Fixed
- Further smoke-test extraction regex robustness ([e1e84ee]).

[v1.2.2]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.2.1...v1.2.2

---

## [v1.2.1] -- 2025-11-24

### Fixed
- Smoke-test extraction regex updated after installer variable renames ([c5bc098]).

[v1.2.1]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.2.0...v1.2.1

---

## [v1.2.0] -- 2025-11-23

**"New Modern TUI & Analysis Tools"** -- the release that introduced the Go-based `sysmon` TUI.

### Added -- Go TUI (`sysmon-go`)
- Full rewrite of sysmon as a Go binary using Bubble Tea + gopsutil ([1878498], [dc91ec0]).
- Modern grid layout with per-core sparklines and history ring buffers ([5cda5a7]).
- Sort (`s`) and filter (`/`, regex) controls for process list ([dc91ec0]).
- JSON stream writer (`SRPS_SYSMON_JSON_FILE`, toggle with `o`) ([dc91ec0]).
- Session statistics tab: uptime, sample count, peak CPU/MEM ([a93ddc0]).
- Kill-log (OOM) analysis tab ([a93ddc0]).
- GPU card display (nvidia-smi/rocm-smi, timeout-protected) and battery pill ([72039e3]).

### Added -- Installer
- Installer prefers pre-built `sysmon-go` binary from GitHub releases; falls back to local Go build, then bash sysmon ([6ae5162], [d261dc6]).
- Auto-installs Go if missing when building from source ([f8b37d3]).
- `ALLOW_BASH_SYSMON=1` env toggle to permit bash fallback explicitly ([306093b]).
- Release workflow builds CGO-free static binaries and uploads them ([d8f7cad], [a694a6c]).
- Configurable refresh interval via `SRPS_SYSMON_INTERVAL` with or without Go duration suffix ([126f8ff]).

### Added -- Bash helpers & testing
- Smoke tests with self-extracting helpers, GPU/battery toggles, JSON sanity checks ([552015c], [2459272], [936df15]).
- Checksum pipeline for `main` branch with cache-busted `verify.sh` ([035e5a3]).
- Cache-busting `?cb=` parameter in curl install snippets ([84030cf]).

### Improved
- sysmon bash TUI: peaks, JSON file output, ananicy error surfacing ([a06316c], [0a81cdb]).
- Rich JSON output and helper help/logging ([4edce31], [1c60015]).
- Ananicy rule format fixed; VCS metadata stripped; cgroup warnings silenced; srps-doctor filters noise ([814799c], [3187357], [a1ae7ad]).
- sysmon parsing: multi-word `comm` and throttled-filter fixes ([a443625], [a322fad]).
- UI: immutable process-slice sorting/filtering ([8cc4e90]).
- README rewritten for Go TUI and installer flow ([dd0b3f6]).

### Changed
- Installer logs download/build failures for visibility ([66e9c31]).
- Installer never overwrites `sysmon-go` with bash fallback ([ac3be75]).

[v1.2.0]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.1.2...v1.2.0

---

## [v1.1.2] -- 2025-11-23

### Added
- Passwordless `sudo` detection -- installer checks `sudo -n true` before prompting, so NOPASSWD users are never asked for a password ([881b817]).
- Deployment-matrix docs with checksum workflow and improved flowchart visuals ([84ed0a2], [586d01c], [9285cda]).

### Fixed
- `verify.sh` gained proper CLI parsing and clearer error handling ([a4b2e29]).
- Checksum instructions and integrity example corrected ([5295ff2]).

### Housekeeping
- Homebrew formula aligned to v1.1.1 assets ([3e469f6]).

[v1.1.2]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.1.1...v1.1.2

---

## [v1.1.1] -- 2025-11-22

### Fixed
- Release-assets workflow permissions corrected so asset uploads succeed ([92efc9e]).
- No code changes from v1.1.0 besides release automation.

[v1.1.1]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.1.0...v1.1.1

---

## [v1.1.0] -- 2025-11-22

*Superseded by v1.1.1 (asset fix only). Prefer v1.1.1+.*

### Added -- Distribution & integrity
- **Homebrew** tap formula (`brew install srps`) ([542130d], [5a164ad]).
- **Nix flake** (`nix run github:...`) ([fe4db7e]).
- **Docker** toolbox image with plan-mode default ([fe4db7e]).
- `verify.sh` integrity verifier and `SHA256SUMS` pipeline ([fe4db7e]).

### Improved
- CI: added Nix flake check, Docker build, shellcheck on `verify.sh` ([1d083c1]).
- CI: bumped Nix installer action to v27 ([eacb583]).
- Brew formula pointed to main tarball; GHCR notes clarified ([542130d]).
- Brew release, verifier deps, and flake version aligned ([fc0527b]).

[v1.1.0]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.0.0...v1.1.0

---

## [v1.0.0] -- 2025-11-21

**Initial stable release.**

### Added -- Core
- `install.sh` installer with `--plan` (dry-run), `--install`, and `--uninstall` modes ([97e57d2]).
- **ananicy-cpp** build/install and curated rule sets for compilers, browsers, IDEs, language servers, containers ([97e57d2]).
- **Sysctl tuning** (`/etc/sysctl.d/99-system-resource-protection.conf`) for swap, dirty ratios, inotify, TCP, max_map_count ([97e57d2]).
- **Systemd manager limits** (`/etc/systemd/system.conf.d/10-system-resource-protection.conf`) with FD/NPROC bumps, especially for WSL2 ([97e57d2]).

### Added -- Helpers & tooling
- `sysmon` bash TUI monitor with CPU/MEM gauges, process tables, and load averages ([97e57d2]).
- `check-throttled`, `cursor-guard` (log/renice-only), `kill-cursor` (manual termination).
- `srps-doctor` diagnostics, `srps-reload-rules`, optional `srps-pull-rules`, `srps-report` HTML snapshot.
- Shell aliases: `limited`, `limited-mem`, `cargo-limited`, `make-limited`, `node-limited`.
- Bash completion at `/etc/bash_completion.d/srps`.
- Configurable via `srps.conf` or env toggles (`ENABLE_ANANICY`, `ENABLE_SYSCTL`, etc.).
- Laptop-aware EarlyOOM defaults with override support ([3227de5]).

### Added -- CI
- GitHub Actions with shellcheck and dry-run install step ([0cd72a1], [9dcdd7d]).

[v1.0.0]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/97e57d2b019a95024d4358281c1eee7242c45186...v1.0.0

---

<!-- commit shortlinks -->
[97e57d2]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/97e57d2b019a95024d4358281c1eee7242c45186
[3227de5]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/3227de5fece19f6cc19bfdd44ad0902634ba2feb
[0cd72a1]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/0cd72a12decc3404f780f0b1ec781f17ec78577b
[9dcdd7d]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/9dcdd7d186a97d482c8957a9c5147a57e8096df7
[fe4db7e]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/fe4db7e3125ce43413370b1b5657a58bee69a4c7
[542130d]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/542130ddf53e82b2ebcedea62c8361670e721bea
[1d083c1]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1d083c10276ab632753cc3c0824a5d70d561280f
[eacb583]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/eacb5837845c4cb136f49a0ca549568fe3588de8
[fc0527b]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/fc0527b2af40f70ebb1e939af54afb279922d564
[5a164ad]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5a164ad3cadc26533dd5b36c4b9c1d0dcd05b3f7
[92efc9e]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/92efc9e0080aa9329cf6c1dc18b655f93d2eb17c
[3e469f6]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/3e469f633985835ab6a26779f5fa83e21dac0da5
[84ed0a2]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/84ed0a23dd8b4706b5d2025c0dc5b57e98c8a149
[5295ff2]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5295ff2383084b3a330c27075ada52905fea2eb8
[a4b2e29]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a4b2e2902501aba8c7d855a80a9037c48f198d23
[586d01c]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/586d01c713b0ea656836dbd3236522cb8654b21d
[9285cda]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/9285cdade7095fde6baa5fde4ded050bbfd8828c
[881b817]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/881b817ffd09e5016a4e75cca7e0903106cfdf6e
[b2f9681]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/b2f96817e6d3521b54a71acf763642ea89736fba
[4edce31]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/4edce31aa06491b603acced26e1d69cc7fd9db76
[1c60015]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1c6001521d610037de0e6df10ba8a85e5bcb6fcc
[0a81cdb]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/0a81cdbf334b9dd103f4654fdc5212aa6f2638df
[a06316c]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a06316c88c516d128b70e9499b3089c7b88e4e8c
[814799c]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/814799cd227f3b2c114e1f76e29e6cffb77d8f1f
[3187357]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/3187357bc323f9eeb3877ce5ef11c8594273d9d6
[a1ae7ad]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a1ae7ad6a71c08f5a6fb60a70a0f2211140caba0
[72039e3]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/72039e3ef2697ba43cfd915fa09ac40b54ce38d5
[936df15]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/936df1569c3a5660bc48925d4a5ee13498e87088
[84030cf]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/84030cf8f9bfc306825697fa7a2fe5545ccbb2af
[035e5a3]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/035e5a3c2a22133a8412043266828d16ef37479d
[552015c]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/552015c8831c8553f301597e75361e54153be871
[a322fad]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a322fad64dc2211a8236e2f09e16653cc66ba417
[2459272]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/2459272865c90ccd11af743fbdb35e647e758f4a
[a443625]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a4436256d4e82d14927a3eba814b99d5d01326e9
[126f8ff]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/126f8ff94c198c2751c556088fe3d050036dcf5c
[1878498]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1878498d4fc784e541b54371b286b9efa8d3e675
[dc91ec0]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/dc91ec0a7a9023d71866f96aec7f20b85a5147dc
[8cc4e90]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/8cc4e90b957d475f0741979ef0eda7fd2c3a5a0e
[6ae5162]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/6ae516240c257e5124d5be8549db67101ef68089
[dd0b3f6]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/dd0b3f6a3e98e222adf445e3a5f47f68018e11a2
[d261dc6]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d261dc6273b7710fb7eb4166e0ae035e7f4cce3a
[d8f7cad]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d8f7cad36be8369eb9a0811b7c71516da2c80bd5
[a694a6c]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a694a6cf2d60509353074275c47a9aa5c454fcdc
[f8b37d3]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/f8b37d3da21a315a4b214f60f76cba79b94193fc
[66e9c31]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/66e9c31a5e9f16cffc77ff15ab84a54ca7aa4a9f
[ac3be75]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/ac3be75a790d06638f6a70b6782a8373867c2f79
[306093b]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/306093bc35d54c9a60f677944fbbf8840dce01ec
[5cda5a7]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5cda5a7943503030a38cffa00de180365cdaca43
[a93ddc0]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a93ddc0f1073d2bde0ebca6bf3b78b58cd3cd696
[c5bc098]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/c5bc098419f56908fe009ac8023fcd49335c01b9
[e1e84ee]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e1e84ee3b0a48a99e38118d0310abe91af358219
[4972c3e]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/4972c3e682a228c46b860c9200456ac27e827334
[85fad3a]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/85fad3a5cd5426fcbd2ed98deac45d4a75930a23
[e1a2dfe]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e1a2dfe37d3e216cd79ee279f17728317756b7f3
[b6c5c5d]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/b6c5c5da540c803069543f243a4e005803a4de06
[ef63109]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/ef631096e31c99ccc9a3fdb8a80cacf503d72e37
[fe61f1d]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/fe61f1d8efc97dc047f26941b72da3e84e2da30c
[c38853a]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/c38853a965492e61fcb963fc4560d11db7248649
[6a26f09]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/6a26f0902e91b3643fc9b8d680cff9f72ec5b342
[ed5b67e]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/ed5b67ef641985662b515568caf3dc089efa1853
[29f4ef5]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/29f4ef58cbbf51d76c0836e251c5e2ffaf9ae520
[80253d7]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/80253d74ca6c4c338a70c4923b427f85711b24bb
[e931584]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e931584972ec3e82c97f1f09d174b905273e90ce
[b2e02a7]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/b2e02a7a103c8413ebc64756e56694c113ca5955
[e215aae]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e215aae9a425c6ba79ad8218fb16bc4f9325217a
[5607a11]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5607a11568b4294c53b76d5dffc6d9f3f3f44aec
[9b5600e]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/9b5600e09154bcbbe0f50236141e8841220285b6
[1e35f16]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1e35f16e4a75fa1d31435c91748da2568e56efe5
[d722517]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d72251702af9e32a9a6a7455e1c41917abdc6cd9
[08b932a]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/08b932a70498df6cb83c22b5df9427466e3ce282
[92723bd]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/92723bd396d3e82aadd698294d402fee1aa415fc
[2088c3c]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/2088c3c2e3257cdec9fac6ecdacddab65749d55e
[1f69cc3]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1f69cc37881dcdd9c0d303300ecb5ccce3fa0fd2
[85b485f]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/85b485f63511a27f6172fdfe5c2a40f66a39fd9d
[4920b63]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/4920b634b75aa3739238b2fe73e24b8cbb148278
[d3fd0bc]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d3fd0bc5604fa80f88c995fb1d610014d52329af
[82f0196]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/82f01967994ec6c06baf86d58b84910e1ce8e706
[492f270]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/492f27045748ea311ee0ae0fe75a2bbc08504974
[b76316b]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/b76316b467f81c4a835f4478e8a570b05b0c6f5e
[5f9f3ab]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5f9f3abd6b7c10b28489fd6138c3c3c19ccb162e
[424118d]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/424118df89373ce4ea54d9700589bb5bf225272a
[a9632da]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a9632da177cfd1c5c5fb7b6142be5b0a8d45b899
[a7045f0]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a7045f0edb65529c0b3233cdd1f0825529c0aa6b
[837fba4]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/837fba4e291e28cb16069d434b4348ac8acd3822
[236f7c9]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/236f7c9dea4b2d632ae2d9a392864d52f1ed3fa5
[e012e7a]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e012e7a433bda71c64244253422c12f707efeac6
[0b77d15]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/0b77d1581cedb2c615fdfb08414acf0454329603
[7ddbd9f]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/7ddbd9f24ff6513750a45e5ae73fd3c9395db293
[26acb2a]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/26acb2a41c221c09a795724651ac32257706f235
[d8c52f3]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d8c52f34674ad9a192a1cb6d3b0dd4b28c21053f
[4df262e]: https://github.com/Dicklesworthstone/system_resource_protection_script/commit/4df262ef01ca0faea531b19d7b8ee2fc3ccb97a5
[Unreleased]: https://github.com/Dicklesworthstone/system_resource_protection_script/compare/v1.4.1...HEAD
