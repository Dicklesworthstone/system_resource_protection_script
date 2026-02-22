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
  `ls /etc/ananicy.d` and inspect `00-default/99-system-resource-protection.rules`
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
- CI runs lint, nix flake check, docker toolbox build, and Go build/test.

---

## 📜 License

MIT License (with OpenAI/Anthropic Rider). See [LICENSE](LICENSE).

---

<div align="center">

**Responsive dev boxes. Zero drama.**  
_Run `sysmoni`, kick off a build, and keep your shell snappy. If you enable an OOM daemon, set it to act only when the system is effectively out of memory (e.g., `EARLYOOM_ARGS="-r 300 -m 1 -s 1 --avoid 'systemd|sshd|Xorg|gnome-shell|kwin|plasmashell' -p"`)._

</div>
