# Changelog

All notable changes to **SRPS** (System Resource Protection Script) are documented here.

Repo: <https://github.com/Dicklesworthstone/system_resource_protection_script>

Versions are listed in reverse chronological order by tag date. Each release
links to the tagged commit. Where the v1.1.3--v1.1.8 Go TUI polish series was
tagged *after* v1.4.0 (on commits between v1.4.0 and v1.4.1), both tracks are
documented at their actual position in the linear history.

---

## [Unreleased]

Post-v1.4.1 work on `main` (not yet tagged).

### Licensing & governance
- Updated license to MIT with OpenAI/Anthropic Rider
  ([b76316b](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/b76316b467f81c4a835f4478e8a570b05b0c6f5e),
  [5f9f3ab](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5f9f3abd6b7c10b28489fd6138c3c3c19ccb162e)).
- Added formal MIT LICENSE file
  ([424118d](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/424118df89373ce4ea54d9700589bb5bf225272a)).

### Environment-variable cleanup
- Dropped all legacy `SRPS_SYSMON_*` env-var fallbacks; only `SRPS_SYSMONI_*` vars are recognized
  ([82f0196](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/82f01967994ec6c06baf86d58b84910e1ce8e706),
  [492f270](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/492f27045748ea311ee0ae0fe75a2bbc08504974)).
- Docs updated to reference `sysmoni` JSON env name
  ([d3fd0bc](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d3fd0bc5604fa80f88c995fb1d610014d52329af)).

### CI & infrastructure
- Added ACFS notification workflows for installer changes and lesson registry sync
  ([a9632da](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a9632da177cfd1c5c5fb7b6142be5b0a8d45b899),
  [a7045f0](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a7045f0edb65529c0b3233cdd1f0825529c0aa6b)).

### Packaging
- Bumped Homebrew formula to v1.4.1
  ([4920b63](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/4920b634b75aa3739238b2fe73e24b8cbb148278)).

### Housekeeping
- Beads configuration, scripts, and gitignore patterns for ephemeral files
  ([236f7c9](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/236f7c9dea4b2d632ae2d9a392864d52f1ed3fa5),
  [e012e7a](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e012e7a433bda71c64244253422c12f707efeac6),
  [0b77d15](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/0b77d1581cedb2c615fdfb08414acf0454329603),
  [7ddbd9f](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/7ddbd9f24ff6513750a45e5ae73fd3c9395db293),
  [837fba4](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/837fba4e291e28cb16069d434b4348ac8acd3822)).
- Gitignore updates for daemon logs and temp images
  ([d8c52f3](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d8c52f34674ad9a192a1cb6d3b0dd4b28c21053f)).

---

## [v1.4.1](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/85b485f63511a27f6172fdfe5c2a40f66a39fd9d) -- 2025-11-26 (Release)

**Breaking rename: sysmon -> sysmoni.** Avoids conflict with Microsoft Sysmon.

### Naming & branding
- Binary, installer, TUI title strings, env vars, and release assets all renamed
  from `sysmon`/`sysmon-go` to `sysmoni`/`sysmoni-go`
  ([1f69cc3](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1f69cc37881dcdd9c0d303300ecb5ccce3fa0fd2)).
- Release assets now publish `sysmoni-linux-{amd64,arm64}`.
- Legacy `SRPS_SYSMON_*` env vars still accepted for backward compatibility (removed later in unreleased).

### Integrity
- SHA256SUMS refreshed to match renamed installer
  ([85b485f](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/85b485f63511a27f6172fdfe5c2a40f66a39fd9d)).

---

## [v1.1.8](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/2088c3c2e3257cdec9fac6ecdacddab65749d55e) -- 2025-11-26 (Release)

Maintenance-only tag. No code changes since v1.1.7. Re-published release assets
with verified SHA256SUMS. Homebrew formula bumped
([2088c3c](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/2088c3c2e3257cdec9fac6ecdacddab65749d55e)).

---

## [v1.1.7](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/92723bd396d3e82aadd698294d402fee1aa415fc) -- 2025-11-26 (Release)

### TUI visual polish
- Global lipgloss styles applied consistently across panels (titles, badges, table headers).
- Count badges added for process and throttled lists.
- Pulsing critical badges for CPU/MEM/SWAP gauges.
- Load mini-gauge styling tidied.
- Help header padding fixed to keep the title centered without style conflicts
  ([92723bd](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/92723bd396d3e82aadd698294d402fee1aa415fc)).

---

## [v1.1.6](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/08b932a70498df6cb83c22b5df9427466e3ce282) -- 2025-11-26 (Release)

### Layout fixes
- Single-column dashboard auto-expands the Top pane and keeps the right column minimal.
- Width math tightened to prevent overflow
  ([d722517](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d72251702af9e32a9a6a7455e1c41917abdc6cd9)).

### Packaging
- Homebrew formula updated to v1.1.6
  ([08b932a](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/08b932a70498df6cb83c22b5df9427466e3ce282)).

---

## [v1.1.5](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/9b5600e09154bcbbe0f50236141e8841220285b6) -- 2025-11-25 (Release)

### Layout improvements
- Narrow layout auto-expands the Top pane to use remaining width; right column shrinks to the minimum needed, eliminating wasted space at startup
  ([9b5600e](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/9b5600e09154bcbbe0f50236141e8841220285b6)).

### Packaging
- Homebrew formula points to v1.1.5
  ([1e35f16](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1e35f16e4a75fa1d31435c91748da2568e56efe5)).

---

## [v1.1.4](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5607a11568b4294c53b76d5dffc6d9f3f3f44aec) -- 2025-11-25 (Release)

### TUI interactivity
- Top list is now scrollable with `j`/`k`, PgUp/PgDn, Home/End.
- Viewport clamping ensures no rows get clipped off the top.
- Dashboard wide layout dedicates ~75% width to processes and clamps card widths
  ([5607a11](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5607a11568b4294c53b76d5dffc6d9f3f3f44aec)).

### Packaging
- Homebrew formula bumped with updated checksum
  ([9dd57a2](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/9dd57a2bea35cd8194177084799bae57a7751915)).

---

## [v1.1.3](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e215aae9a425c6ba79ad8218fb16bc4f9325217a) -- 2025-11-25 (Release)

### IO awareness (new capability)
- Per-process IO throughput (read/write kB/s) and open FD counts exposed in TUI and JSON
  ([a902d5b](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a902d5b78c390fd724bef40860c7fb1100b062cf)).
- IO/FD leaders panel, per-device IO stats, cached memory display, FD burst detection
  ([1fa159e](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1fa159e255ad56a03059bfdc0e83763fb9dd3750)).
- Help overlay with `ionice` guidance for disk hogs
  ([87ce059](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/87ce059dfbcd2174aa8ec1ddc3d761b23333086c)).
- Guard against division-by-zero when IO rate interval is zero
  ([bdf7de9](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/bdf7de9d6e8d4438030641ef8f8e47e5da29789f)).

### Safety philosophy
- Documented safety-first behavior; removed all automated process killing; added
  gentle earlyoom guidance with ultra-conservative thresholds
  ([3bf5899](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/3bf58998c693eb4513f9a765bab49a9bcd6b9095)).

### Layout
- Multi-column width clamps prevent right-column overflow; power source (AC/Battery) reported
  ([e215aae](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e215aae9a425c6ba79ad8218fb16bc4f9325217a)).

### Packaging
- Homebrew formula updated with corrected checksum
  ([e2b5242](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e2b5242a20df694f4145b2021d92ad4e2ff882e1)).

---

## [v1.4.0](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/b2e02a7a103c8413ebc64756e56694c113ca5955) -- 2025-11-24 (Release: "The Interactive Update")

### TUI overhaul
- Replaced raw lipgloss rendering with Bubbles components: `table`, `viewport`, `textinput`, `help`.
- Interactive table with row selection and mouse support.
- Filter search bar with live text input (regex substring matching via `/`).
- Scrollable log viewport.
- Adaptive light/dark mode colors.
- Dynamic help footer showing available keybindings
  ([b2e02a7](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/b2e02a7a103c8413ebc64756e56694c113ca5955)).

---

## [v1.3.3](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e931584972ec3e82c97f1f09d174b905273e90ce) -- 2025-11-24 (Release: "UX Improvements")

### UX
- ESC key now quits the sysmon TUI in addition to `q` and Ctrl+C
  ([e931584](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e931584972ec3e82c97f1f09d174b905273e90ce)).

---

## [v1.3.2](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/80253d74ca6c4c338a70c4923b427f85711b24bb) -- 2025-11-24 (Release: "Smart Installer (Fixed)")

### Installer
- Fixed ShellCheck warning: quoted curl format string in smart installer logic
  ([80253d7](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/80253d74ca6c4c338a70c4923b427f85711b24bb)).

---

## [v1.3.1](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/29f4ef58cbbf51d76c0836e251c5e2ffaf9ae520) -- 2025-11-24 (Release: "Smart Installer")

### Installer intelligence
- Installer auto-resolves `main` to the latest GitHub release tag when fetching
  prebuilt Go binaries, avoiding unnecessary source builds
  ([29f4ef5](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/29f4ef58cbbf51d76c0836e251c5e2ffaf9ae520)).

### CI
- Lint job now enforces that SHA256SUMS is up to date
  ([ed5b67e](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/ed5b67ef641985662b515568caf3dc089efa1853)).

---

## [v1.3.0](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/6a26f0902e91b3643fc9b8d680cff9f72ec5b342) -- 2025-11-24 (Release: "Checksum Fix")

### Integrity
- SHA256SUMS updated to match current `install.sh`, resolving verification errors
  during integrity-first installation
  ([6a26f09](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/6a26f0902e91b3643fc9b8d680cff9f72ec5b342)).

---

## [v1.2.9](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/c38853a965492e61fcb963fc4560d11db7248649) -- 2025-11-24 (Release: "Fix Cursor Guard (Double Zero)")

### Bug fix
- Fixed `pgrep` usage in `cursor-guard` that produced a double-zero JSON syntax error
  ([c38853a](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/c38853a965492e61fcb963fc4560d11db7248649)).

---

## [v1.2.8](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/fe61f1d8efc97dc047f26941b72da3e84e2da30c) -- 2025-11-24 (Release)

### Testing
- Added verbose failure logging and relaxed assertions in smoke tests for CI diagnostics
  ([fe61f1d](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/fe61f1d8efc97dc047f26941b72da3e84e2da30c)).

---

## [v1.2.7](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/ef631096e31c99ccc9a3fdb8a80cacf503d72e37) -- 2025-11-24 (Release)

### Bug fix
- Hardened `cursor-guard` JSON output logic to avoid syntax errors in edge cases
  ([ef63109](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/ef631096e31c99ccc9a3fdb8a80cacf503d72e37)).

---

## v1.2.1 -- v1.2.6 -- 2025-11-24 (Smoke Test Fix Series)

Rapid-fire tags fixing smoke test extraction regressions introduced by the
v1.2.0 TUI rewrite. Each tag addressed one layer of the regex/heredoc extraction
problem:

| Tag | Fix | Commit |
|-----|-----|--------|
| [v1.2.6](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/b6c5c5da540c803069543f243a4e005803a4de06) | Handle whitespace in heredoc tokens | [b6c5c5d](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/b6c5c5da540c803069543f243a4e005803a4de06) |
| [v1.2.5](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e1a2dfe37d3e216cd79ee279f17728317756b7f3) | Exclude heredoc token from extraction markers | [e1a2dfe](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e1a2dfe37d3e216cd79ee279f17728317756b7f3) |
| [v1.2.4](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/85fad3a5cd5426fcbd2ed98deac45d4a75930a23) | Handle indented markers | [85fad3a](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/85fad3a5cd5426fcbd2ed98deac45d4a75930a23) |
| [v1.2.3](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/4972c3e682a228c46b860c9200456ac27e827334) | Use function name markers instead of line matching | [4972c3e](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/4972c3e682a228c46b860c9200456ac27e827334) |
| [v1.2.2](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e1e84ee3b0a48a99e38118d0310abe91af358219) | Improve extraction regex robustness | [e1e84ee](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/e1e84ee3b0a48a99e38118d0310abe91af358219) |
| [v1.2.1](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/c5bc098419f56908fe009ac8023fcd49335c01b9) | Fix extraction regex for sysmon bash script | [c5bc098](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/c5bc098419f56908fe009ac8023fcd49335c01b9) |

---

## [v1.2.0](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a93ddc0f1073d2bde0ebca6bf3b78b58cd3cd696) -- 2025-11-23 (Release: "New Modern TUI & Analysis Tools")

Major overhaul -- the bash sysmon was rewritten as a Go (Bubble Tea) binary and
the installer was rebuilt to prefer the Go binary with a bash fallback.

### Go TUI (new)
- Rewrote sysmon as a Go binary (`sysmon-go`) using
  [gopsutil](https://github.com/shirou/gopsutil) and
  [Bubble Tea](https://github.com/charmbracelet/bubbletea)
  ([1878498](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1878498d4fc784e541b54371b286b9efa8d3e675)).
- Modern grid layout, per-core sparklines, history ring buffers
  ([5cda5a7](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5cda5a7943503030a38cffa00de180365cdaca43)).
- Sort/filter controls, JSON stream writer
  ([dc91ec0](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/dc91ec0a7a9023d71866f96aec7f20b85a5147dc)).
- Session statistics tab with kill-log analysis
  ([a93ddc0](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a93ddc0f1073d2bde0ebca6bf3b78b58cd3cd696)).
- Safe slice handling to avoid mutating process data during sort/filter
  ([8cc4e90](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/8cc4e90b957d475f0741979ef0eda7fd2c3a5a0e)).

### Installer rebuild
- Installer prefers prebuilt `sysmon-go` binary from GitHub releases, falls back to bash
  ([6ae5162](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/6ae516240c257e5124d5be8549db67101ef68089),
  [d261dc6](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d261dc6273b7710fb7eb4166e0ae035e7f4cce3a)).
- Auto-installs Go toolchain if binary download fails and source build is needed
  ([f8b37d3](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/f8b37d3da21a315a4b214f60f76cba79b94193fc)).
- `ALLOW_BASH_SYSMON=1` env var to opt in to bash fallback; without it the installer fails
  if the Go binary is unavailable
  ([306093b](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/306093bc35d54c9a60f677944fbbf8840dce01ec)).
- Prevents bash fallback from overwriting a working `sysmon-go`
  ([ac3be75](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/ac3be75a790d06638f6a70b6782a8373867c2f79)).
- Logs download/build failures for visibility
  ([66e9c31](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/66e9c31a5e9f16cffc77ff15ab84a54ca7aa4a9f)).
- Handles tag tarballs; release builds are CGO-free
  ([a694a6c](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a694a6cf2d60509353074275c47a9aa5c454fcdc)).
- Accepts `SRPS_SYSMON_INTERVAL` with or without Go duration suffix
  ([126f8ff](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/126f8ff94c198c2751c556088fe3d050036dcf5c)).

### Bash sysmon improvements (pre-Go-rewrite, folded into this release)
- GPU (nvidia-smi / rocm-smi) and battery display with `--json` flag
  ([72039e3](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/72039e3ef2697ba43cfd915fa09ac40b54ce38d5)).
- Peak throughput tracking and JSON file export; ananicy errors surfaced
  ([a06316c](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a06316c88c516d128b70e9499b3089c7b88e4e8c)).
- Rich JSON/stream mode, helper help text, smoke tests
  ([1c60015](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1c6001521d610037de0e6df10ba8a85e5bcb6fcc),
  [4edce31](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/4edce31aa06491b603acced26e1d69cc7fd9db76)).
- Hardened JSON output from sysmon and helpers
  ([0a81cdb](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/0a81cdbf334b9dd103f4654fdc5212aa6f2638df)).
- Fixed multi-word comm parsing and throttled filter
  ([a443625](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a4436256d4e82d14927a3eba814b99d5d01326e9)).
- Fixed output stability and JSON formatting
  ([a322fad](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a322fad64dc2211a8236e2f09e16653cc68ba417)).

### Ananicy rule management
- Fixed ananicy rule format; stripped VCS metadata from rules
  ([814799c](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/814799cd227f3b2c114e1f76e29e6cffb77d8f1f)).
- Silenced cgroup warnings; kept loglevel=error
  ([3187357](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/3187357bc323f9eeb3877ce5ef11c8594273d9d6)).
- `srps-doctor` now filters ananicy noise instead of changing the loglevel
  ([a1ae7ad](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a1ae7ad6a71c08f5a6fb60a70a0f2211140caba0)).

### CI & release workflow
- Release workflow: test, build `sysmon-go`, upload platform binaries
  ([d8f7cad](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d8f7cad36be8369eb9a0811b7c71516da2c80bd5)).
- Go sysmon CI job added
  ([2a3917f](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/2a3917ff90a84f5071ca28af9f3c252e703b0f2f)).

### Integrity & testing
- Checksum pipeline for `main` with cache-busted `verify.sh`
  ([035e5a3](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/035e5a3c2a22133a8412043266828d16ef37479d)).
- Cache-busting added to curl install snippets in docs
  ([84030cf](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/84030cf8f9bfc306825697fa7a2fe5545ccbb2af)).
- Tests run bashate/shellcheck before smoke
  ([936df15](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/936df1569c3a5660bc48925d4a5ee13498e87088)).
- Self-extracting test helpers; GPU/battery toggles with timeouts
  ([552015c](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/552015c8831c8553f301597e75361e54153be871)).
- Sysmon JSON sanity check added to smoke tests
  ([2459272](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/2459272865c90ccd11af743fbdb35e647e758f4a)).

### Documentation
- README rewritten for Go TUI and installer flow
  ([dd0b3f6](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/dd0b3f6a3e98e222adf445e3a5f47f68018e11a2)).
- Installation flow diagram revised with color coding
  ([b2f9681](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/b2f96817e6d3521b54a71acf763642ea89736fba)).

---

## [v1.1.2](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a0477ca21e12b6ee5afda65b890e6369b3fee9dd) -- 2025-11-23 (Release)

### Installer robustness
- Passwordless sudo support: `install.sh` checks `sudo -n true` before prompting
  so users with NOPASSWD never see unnecessary password prompts
  ([881b817](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/881b817ffd09e5016a4e75cca7e0903106cfdf6e)).

### Verification tooling
- `verify.sh` rewritten with proper CLI parsing and clearer error handling
  ([a4b2e29](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/a4b2e2902501aba8c7d855a80a9037c48f198d23)).
- Fixed checksum instructions and integrity example
  ([5295ff2](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5295ff2383084b3a330c27075ada52905fea2eb8)).

### Documentation
- README flowcharts enhanced with color coding for visual clarity
  ([586d01c](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/586d01c713b0ea656836dbd3236522cb8654b21d),
  [9285cda](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/9285cdade7095fde6baa5fde4ded050bbfd8828c)).
- Deployment options and integrity map added
  ([84ed0a2](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/84ed0a23dd8b4706b5d2025c0dc5b57e98c8a149)).

### Packaging
- Homebrew formula bumped for v1.1.1 and v1.1.2
  ([3e469f6](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/3e469f633985835ab6a26779f5fa83e21dac0da5)).

---

## [v1.1.1](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/92efc9e0080aa9329cf6c1dc18b655f93d2eb17c) -- 2025-11-22 (Release)

### Release automation
- Fixed release-assets workflow permissions so GitHub Actions uploads succeed
  ([92efc9e](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/92efc9e0080aa9329cf6c1dc18b655f93d2eb17c)).
- No code changes from v1.1.0. Prefer v1.1.1 over v1.1.0.

---

## [v1.1.0](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5a164ad3cadc26533dd5b36c4b9c1d0dcd05b3f7) -- 2025-11-22 (Pre-release, superseded by v1.1.1)

### Distribution channels (new)
- Homebrew (Linuxbrew/macOS) formula: `brew install srps`
  ([542130d](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/542130ddf53e82b2ebcedea62c8361670e721bea),
  [5a164ad](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/5a164ad3cadc26533dd5b36c4b9c1d0dcd05b3f7)).
- Nix flake with `nix run` / `nix develop` support.
- Docker toolbox image for isolated plan-mode testing.

### Integrity tooling
- `verify.sh` with SHA256 checksum validation pipeline
  ([fe4db7e](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/fe4db7e3125ce43413370b1b5657a58bee69a4c7)).

### CI
- Added nix flake check, docker build, shellcheck for `verify.sh`
  ([1d083c1](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/1d083c10276ab632753cc3c0824a5d70d561280f)).
- Bumped Nix installer action to v27
  ([eacb583](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/eacb5837845c4cb136f49a0ca549568fe3588de8)).
- Aligned brew release, verifier deps, flake version
  ([fc0527b](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/fc0527b2af40f70ebb1e939af54afb279922d564)).

---

## [v1.0.0](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/9dcdd7d186a97d482c8957a9c5147a57e8096df7) -- 2025-11-21 (Release: "SRPS v1.0.0")

First stable release.

### Core installer (`install.sh`)
- Five-step idempotent installation: ananicy-cpp build/enable, rules deployment,
  sysctl tuning, systemd manager limits, helper tools.
- Safe to re-run; backups preserved; services restarted as needed.
- Full `--uninstall` support (interactive and `--yes` non-interactive).
- Configurable modules via `srps.conf` / env vars: `ENABLE_ANANICY`, `ENABLE_SYSCTL`,
  `ENABLE_WSL_LIMITS`, `ENABLE_TOOLS`, `ENABLE_SHELL_ALIASES`, `ENABLE_RULE_PULL`,
  `ENABLE_HTML_REPORT`.
- `--plan` / `DRY_RUN=1` dry-run mode for preview without changes
  ([3227de5](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/3227de5fece19f6cc19bfdd44ad0902634ba2feb)).

### Kernel & system tuning
- Sysctl conf for swap pressure, dirty ratios, inotify watches, TCP, max_map_count.
- Systemd manager limits (FD/NPROC bumps, accounting) especially for WSL2.
- Ananicy-cpp rules for compilers, browsers, IDEs, language servers, containers.

### Helper tools
- `sysmon` bash TUI with CPU/MEM gauges, load averages, top processes.
- `check-throttled` for thermal/power throttle detection.
- `cursor-guard` (log/renice-only, never kills).
- `kill-cursor` (manual-only termination tool).
- `srps-doctor` diagnostics, `srps-reload-rules`, optional `srps-pull-rules`.
- `srps-report` HTML snapshot.
- Shell aliases: `limited`, `limited-mem`, `cargo-limited`, `make-limited`, `node-limited`.
- Bash completions at `/etc/bash_completion.d/srps`.

### CI
- GitHub Actions with shellcheck lint and dry-run install step
  ([0cd72a1](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/0cd72a12decc3404f780f0b1ec781f17ec78577b),
  [9dcdd7d](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/9dcdd7d186a97d482c8957a9c5147a57e8096df7)).

### Documentation
- README with badges, mermaid diagrams, TLDR value summary
  ([97e57d2](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/97e57d2b019a95024d4358281c1eee7242c45186),
  [d5158b6](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/d5158b65cd7c0ecb1a785eb934cb7caf9057a31d),
  [dc8a1ce](https://github.com/Dicklesworthstone/system_resource_protection_script/commit/dc8a1ce0a772346adba6d176dd364a0d05a5d684)).
