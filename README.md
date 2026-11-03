<div align="center">

# 🛡️ System Resource Protection Script (SRPS)

**Keep your Linux dev box (or WSL2) responsive under load with priority tuning, sysctl tweaks, and a polished TUI monitor — without killing your workloads.**

[![Linux](https://img.shields.io/badge/Linux-Debian%2FUbuntu-orange?logo=linux)](https://www.debian.org/)
[![WSL2](https://img.shields.io/badge/WSL2-Supported-blue?logo=microsoft)](https://learn.microsoft.com/windows/wsl/)
[![TUI](https://img.shields.io/badge/TUI-Bubble%20Tea-7b5ea7?logo=gnu-bash&logoColor=white)](#%EF%B8%8F-live-system-monitor)
[![Install](https://img.shields.io/badge/Install-curl%20%7C%20brew%20%7C%20nix-0f9d58)](#-quickstart)
[![License](https://img.shields.io/badge/License-MIT%2BOpenAI%2FAnthropic%20Rider-blue.svg)](LICENSE)

</div>

---

## 🎯 What SRPS Does

SRPS is a single script + helpers that assemble a tuned stack for developer/workstation responsiveness:

- **ananicy-cpp** with curated rules for compilers, browsers, IDEs, language servers, containers, etc.
- **Kernel (sysctl) tuning** for interactive workloads (swap, dirty ratios, inotify, TCP).
- **Systemd manager limits** (especially for WSL2) to prevent FD/process explosions.
- **Helper tools & aliases** for monitoring, throttling, diagnostics.
- **Modern TUI monitor (`sysmoni`)** written in Go (Bubble Tea) with live gauges, tables, per-core sparklines, filters, JSON/NDJSON export. Legacy bash TUI kept as fallback.
- **IO awareness:** per-process IO throughput (read/write kB/s) and open FD counts surfaced in the TUI/JSON so you can spot runaway file handles or disk hogs and `ionice` them manually.

**Safety-first philosophy:** SRPS never ships an automated process killer. Helpers are log/renice-only; the only termination tool is `kill-cursor`, and you must run it manually. If you choose to run an OOM daemon (e.g., earlyoom), use ultra-conservative thresholds (example below) so action happens only when the machine is effectively out of resources.

Everything is idempotent, safe to re-run, and reversible via `--uninstall`.

---

## 🚀 Quickstart

**Integrity-first (recommended):**
```bash
cb=$(date +%s)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/system_resource_protection_script/main/verify.sh?cb=$cb" -o verify.sh
bash verify.sh            # downloads install.sh + SHA256SUMS and verifies
bash install.sh --plan    # dry-run
bash install.sh --install # apply
```

**Fast path (pipe):**
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/system_resource_protection_script/main/install.sh?cb=$(date +%s)" | bash
```

**Uninstall (non-interactive):**
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/system_resource_protection_script/main/install.sh?cb=$(date +%s)" -o install.sh
bash install.sh --uninstall --yes
```

---

## 📦 Other Install Options

- **Homebrew (Linuxbrew/macOS):**
  ```bash
  brew tap Dicklesworthstone/system_resource_protection_script https://github.com/Dicklesworthstone/system_resource_protection_script
  brew install srps               # latest tagged release
  # brew install --HEAD srps       # track main
  srps-verify latest && srps-install --plan
  ```
- **Nix / Flakes:**
  ```bash
  nix run github:Dicklesworthstone/system_resource_protection_script -- --plan
  nix develop github:Dicklesworthstone/system_resource_protection_script
  ```
- **Docker toolbox (plan mode):**
  ```bash
  docker build -t srps-tools .
  docker run --rm -it srps-tools            # defaults to --plan
  # docker run --rm -it --privileged -v /:/host srps-tools --plan   # risky; plan only
  ```

---

## 🛠️ What Happens on Install (5 steps)
1. **Build/Install ananicy-cpp** (if missing) and enable service.
2. **Rules:** Replace/augment `/etc/ananicy.d` with community + SRPS rules (backup recorded in `.srps_backup`).
3. **Sysctl:** Apply `/etc/sysctl.d/99-system-resource-protection.conf` (swap, dirty ratios, inotify, net, max_map_count).
4. **Systemd limits (WSL-friendly):** `/etc/systemd/system.conf.d/10-system-resource-protection.conf` with FD/NPROC bumps and accounting.
5. **Helpers:** Install `sysmoni` (Go TUI binary, with bash fallback), `check-throttled`, `cursor-guard` (log/renice-only), `kill-cursor` (manual), `srps-doctor`, `srps-reload-rules`, optional `srps-pull-rules`, `srps-report`; add shell aliases and completions.

Re-running is safe: idempotent writes, backups preserved, services restarted as needed.

---

## 🧊 Requirements

| Requirement | Description |
|-------------|-------------|
| OS          | Debian/Ubuntu/derivatives or WSL2 with Debian/Ubuntu rootfs |
| sudo        | Required (run as regular user with sudo, not root) |
| apt-get     | Package manager |
| bash        | Shell (installer uses bash) |
| systemd     | Recommended; without it, some features (services/aliases) are skipped |

---

## ⚙️ Config & Flags

- Optional config file: `./srps.conf` or `/etc/system-resource-protection.conf` or `-c /path`.
- Feature toggles (env or config, 1=enable, 0=disable): `ENABLE_ANANICY`, `ENABLE_SYSCTL`, `ENABLE_WSL_LIMITS`, `ENABLE_TOOLS`, `ENABLE_SHELL_ALIASES`, `ENABLE_RULE_PULL`, `ENABLE_HTML_REPORT`.
- Plan-only: `install.sh --plan` or `DRY_RUN=1`.
- Go TUI JSON file stream: `SRPS_SYSMONI_JSON_FILE=/tmp/sysmoni.ndjson` and toggle inside TUI with `o`.

### Build storage in Bash and Zsh

SRPS preserves an already-set `TMPDIR` or `CARGO_TARGET_DIR`, including an explicit
empty value. An unset `CARGO_TARGET_DIR` stays unset so Cargo can use repository
configuration and project `target` directories or symlinks. Resource-control
aliases do not require a global Cargo target or a change to temporary storage.

For persistent defaults, create your own
`${XDG_CONFIG_HOME:-$HOME/.config}/srps/storage.sh` (or select a file with
`SRPS_STORAGE_CONFIG` in your shell configuration before the SRPS block):

```bash
# The directory must already exist and be writable/searchable by this user.
SRPS_TMPDIR=/data/build/tmp/shell

# Optional: set this ONLY if you intentionally want a global Cargo target.
# SRPS_CARGO_TARGET_DIR=/data/build/cargo-target
```

This is trusted shell code, sourced by both Bash and Zsh at startup; use syntax
both understand. SRPS never creates or rewrites this file. These defaults fill
only unset standard variables, so values from the incoming environment or
earlier shell configuration take precedence. Ordinary assignments placed after
the managed block also keep their usual shell precedence. Installer environment
variables are **not** captured into the rc file: ACFS uses a private, temporary
`TMPDIR` during verified installation and removes it afterward.

To retain the aliases while disabling all SRPS storage defaults, set
`SRPS_STORAGE_POLICY=preserve` in that file or before the managed block. An empty
`SRPS_TMPDIR` disables automatic temporary-directory selection alone. A nonempty
but unavailable `SRPS_TMPDIR` produces a warning and leaves `TMPDIR` unset; SRPS
does not silently substitute another volume or create directories.
An explicitly selected storage config that is missing or unreadable also leaves
storage unchanged with a warning.

Without explicit configuration, SRPS considers `/data/build/tmp/shell` first,
then `/data/tmp`, **only when `TMPDIR` is unset**. A candidate must already be
writable/searchable, have a device identity different from `/` according to both
`stat` and `findmnt`, and have a recognized persistent filesystem type (ext2/3/4,
XFS, Btrfs, or ZFS). A directory on the OS filesystem, a bind mount of it, tmpfs,
an unknown filesystem, or missing/failed probes cannot qualify. If no candidate
qualifies, `TMPDIR` stays unset and tools use their host defaults. Filesystem
separation does not establish available space or quota headroom; use explicit
configuration for your quota-managed build directory.

Upgrades recognize the old `# Rust / Cargo env` footer. Unmodified upstream
defaults are replaced; customized storage code is preserved verbatim immediately
before the refreshed managed block and is not evaluated by the installer. That
preserved code remains operator-owned on subsequent reinstalls and uninstall.
Simple storage-only blocks are handled too. An unrecognized compound custom
block is left intact with a warning rather than risking loss of operator code.
Existing `.srps-bak` files are not silently restored: they may contain settings
that an operator intentionally removed. Before replacing a different previous
backup, SRPS retains it as `<rc>.srps-bak.<unique suffix>` and reports the path.
This preserves recovery data from earlier updates while `<rc>.srps-bak` remains
the immediately preceding rc file. An unchanged reinstall creates no new backup.

Already-running processes retain their old environment. If a parent shell still
exports legacy paths, set the intended variables in operator configuration or
start a clean login session; SRPS cannot distinguish an inherited old default
from an intentional override based on its pathname alone.

---

## 🖥️ Live System Monitor (`sysmoni`)

Powered by Go + Bubble Tea (static binary). Bash TUI remains as fallback if binary download fails.

Key UI features:
- CPU/MEM gauges, load averages.
- IO & NET throughput with peaks.
- GPU cards (nvidia-smi/rocm-smi best-effort, timeout-protected).
- Battery pill (sysfs/upower).
- Top tables: sortable (CPU/MEM) via `s`, filter with `/` (regex substring), throttled (NI>0), cgroup CPU summary.
- Per-core sparklines (history ring).
- JSON/NDJSON export toggle (`o` when `SRPS_SYSMONI_JSON_FILE` set).
- Quit with `q` / `Ctrl+C`. Runs in alt-screen for a polished, flicker-free experience.

Non-TTY: auto emits JSON one-shot. `--json` / `--json-stream` also available.

---

## 🔒 Integrity & Verification

- Release assets include `install.sh`, `install.sh.sha256`, and `verify.sh`.
- `verify.sh <tag|latest>` downloads `install.sh` + `SHA256SUMS` and validates.
- Installer always backs up existing configs before overwriting:
  - `/etc/ananicy.d` → `/etc/ananicy.d.backup-*` + `.srps_backup` marker
  - `/etc/sysctl.d/99-system-resource-protection.conf` → `.srps-backup`
  - `/etc/systemd/system.conf.d/10-system-resource-protection.conf` → `.srps-backup`
- Go binary fetched from GitHub releases; if download fails, bash sysmoni is installed instead.

---

## 🧩 Helpers & Aliases

- `sysmoni` (Go TUI) / `sys` alias
- `check-throttled`, `cursor-guard` (log/renice-only), `kill-cursor` (manual)
- `srps-doctor`, `srps-reload-rules`, optional `srps-pull-rules`, `srps-report`
- Aliases (when systemd-run available): `limited`, `limited-mem`, `cargo-limited`, `make-limited`, `node-limited`
- Bash completion at `/etc/bash_completion.d/srps`

IO tip: when you spot a disk hog or FD explosion in `sysmoni`, manually drop it to idle IO priority with `sudo ionice -c3 -p <pid>` (log/renice-only helpers ensure no automatic killing).

---

## 🔧 Troubleshooting

- Services inactive?  
`systemctl status ananicy-cpp`
- Ananicy rules?  
  `ls /etc/ananicy.d` and inspect `zz-srps/system-resource-protection.rules`. ananicy-cpp loads
  rule files in unsorted readdir order and the last definition of a name wins, so the installer
  comments out (`# [srps-override]`) every community rule for a name SRPS defines instead of
  relying on file placement; `10-local/` rules take precedence over SRPS the same way.
  Check what actually applies with `sudo ananicy-cpp dump rules` (the installer verifies `sshd`).
- GPU/ROCm timeouts?  
  `SRPS_SYSMONI_GPU=0 sysmoni` to skip probing.

---

## 🗑️ Uninstall

```bash
bash install.sh --uninstall        # interactive
bash install.sh --uninstall --yes  # non-interactive
```
Restores backups where available, removes SRPS-owned files/helpers, leaves packages (`ananicy-cpp`) installed.

---

## 🔄 Upgrading / Re-running

Safe to re-run the installer any time; it re-applies configs, restores backups once, and recreates helpers if missing.

---

## 🧭 Files Touched

| File/Dir | Notes |
|----------|-------|
| `/etc/ananicy.d` | Rules + `.srps_backup` marker; backups kept |
| `/etc/sysctl.d/99-system-resource-protection.conf` | Kernel tuning |
| `/etc/systemd/system.conf.d/10-system-resource-protection.conf` | Manager limits |
| `/usr/local/bin/sysmoni` | Go binary (link to `sysmoni-go`) or bash fallback |
| `/usr/local/bin/sysmoni-go` | Downloaded TUI binary |
| `/usr/local/bin/*` | Helpers: check-throttled, cursor-guard (log/renice-only), kill-cursor (manual), srps-* |
| `/etc/bash_completion.d/srps` | Completion |
| `~/.zshrc` / `~/.bashrc` | Aliases block (with markers) |

---

## 🧪 Dev & Release Notes

- Go TUI lives in `cmd/sysmoni`; static builds shipped via releases (binary URL used by installer).
- Legacy bash sysmoni remains embedded for fallback.
- DSR is the only automation path; GitHub Actions must not be run (see
  [AGENTS.md](AGENTS.md)). Existing workflow definitions remain available as local
  DSR/`act` inputs for the broader Nix, Docker, and Go qualification gates.
- Run the storage/installer shell qualification lane with Bash, Zsh, Python 3,
  ShellCheck, and DSR installed:

  ```bash
  DSR_CONFIG_DIR="$PWD/.dsr" dsr quality --tool srps-shell --work-dir "$PWD"
  ```

- Run verified ACFS reinstall coverage against an existing ACFS checkout:

  ```bash
  SRPS_ACFS_SOURCE=/path/to/agentic_coding_flywheel_setup \
    DSR_CONFIG_DIR="$PWD/.dsr" dsr quality --tool srps-acfs --work-dir "$PWD"
  ```

  This offline test executes the real ACFS checksum verifier, target environment,
  installer entry point, temporary-directory cleanup, and repeated shell-block
  refreshes. Transport and account-home metadata are fixtures, and an explicit
  installer config disables host changes. Fresh Bash/Zsh sessions check settings,
  aliases, and preserved rc content; a corrupted payload must be refused. This
  lane does not replace privileged Linux/WSL service or full release qualification.

---

## 📜 License

MIT License (with OpenAI/Anthropic Rider). See [LICENSE](LICENSE).

---

<div align="center">

**Responsive dev boxes. Zero drama.**  
_Run `sysmoni`, kick off a build, and keep your shell snappy. If you enable an OOM daemon, set it to act only when the system is effectively out of memory (e.g., `EARLYOOM_ARGS="-r 300 -m 1 -s 1 --avoid 'systemd|sshd|Xorg|gnome-shell|kwin|plasmashell' -p"`)._

</div>
