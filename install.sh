#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  System Resource Protection Script (SRPS)
#  - Ananicy-cpp + curated rules
#  - EarlyOOM tuned for dev workflows
#  - Sysctl kernel tweaks
#  - WSL2 / systemd limits (when applicable)
#  - Monitoring + helper utilities
#  - Install / uninstall friendly
# ============================================================

# --------------- Colors & Formatting -------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

TOTAL_STEPS=6

# Config defaults (can be overridden by srps.conf or env)
ENABLE_ANANICY=${ENABLE_ANANICY:-1}
ENABLE_EARLYOOM=${ENABLE_EARLYOOM:-1}
ENABLE_SYSCTL=${ENABLE_SYSCTL:-1}
ENABLE_WSL_LIMITS=${ENABLE_WSL_LIMITS:-1}
ENABLE_TOOLS=${ENABLE_TOOLS:-1}
ENABLE_SHELL_ALIASES=${ENABLE_SHELL_ALIASES:-1}
ENABLE_SAMPLER=${ENABLE_SAMPLER:-1}
ENABLE_HTML_REPORT=${ENABLE_HTML_REPORT:-1}
ENABLE_RULE_PULL=${ENABLE_RULE_PULL:-1}
ENABLE_DIAGNOSTICS=${ENABLE_DIAGNOSTICS:-1}
DRY_RUN=0
CONFIG_FILE="${SRPS_CONFIG_FILE:-./srps.conf}"

HAS_SYSTEMD=0
IS_WSL=0
HAS_APT=0
APT_UPDATED=0
SHELL_RC=""
ACTION="install"
FORCE="no"
ON_BATTERY=0

# --------------- Logging Helpers -----------------------------
print_step() {
    echo -e "\n${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "➤ $1"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

die() {
    print_error "$1"
    exit 1
}

usage() {
    cat <<'EOF'
System Resource Protection Script (SRPS)

Usage:
  bash install.sh [ACTION] [OPTIONS]

Actions (mutually exclusive; default is --install):
  --install        Perform installation (default)
  --plan           Dry-run only: show what would change, make no modifications
  --uninstall      Revert SRPS configuration and restore backups where possible

Options:
  -y, --yes        Non-interactive uninstall (assume "yes")
  -c, --config PATH
                   Override path to srps.conf
  -h, --help       Show this help and exit

You can also use ENABLE_* and SRPS_* environment variables to tweak behaviour.
EOF
}

print_banner() {
    local mode="$1"
    local label

    case "$mode" in
        install)
            if [ "${DRY_RUN:-0}" -eq 1 ]; then
                label="PLAN"
            else
                label="INSTALL"
            fi
            ;;
        uninstall)
            label="UNINSTALL"
            ;;
        *)
            label="$mode"
            ;;
    esac

    if [ -t 1 ]; then
        clear
    fi

    echo -e "${MAGENTA}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║   SYSTEM RESOURCE PROTECTION SCRIPT (SRPS)                 ║"
    printf "║   %-56s ║\n" "Mode: $label"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --plan)
                ACTION="plan"
                DRY_RUN=1
                ;;
            --install)
                ACTION="install"
                DRY_RUN=0
                ;;
            --uninstall|--remove)
                ACTION="uninstall"
                ;;
            -y|--yes)
                FORCE="yes"
                ;;
            -c|--config)
                if [ "$#" -lt 2 ]; then
                    die "--config requires a path argument"
                fi
                shift
                CONFIG_FILE="$1"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1 (see --help)"
                ;;
        esac
        shift
    done
}

# --------------- System Detection ----------------------------
detect_system() {
    if [ "$EUID" -eq 0 ]; then
        die "Don't run this script as root. Run as a regular user with sudo."
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        die "sudo is required. Please install/configure sudo for your user."
    fi

    print_info "Validating sudo credentials..."
    if sudo -n true 2>/dev/null; then
        print_info "sudo: passwordless access confirmed"
    else
        print_info "sudo: password required, validating credentials..."
        if ! sudo -v; then
            die "Failed to validate sudo privileges."
        fi
    fi

    if command -v apt-get >/dev/null 2>&1; then
        HAS_APT=1
    else
        die "This script currently supports only apt-based systems (Debian/Ubuntu/WSL)."
    fi

    if pidof systemd >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        HAS_SYSTEMD=1
    fi

    if grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL=1
    fi
}

detect_power_profile() {
    if command -v on_ac_power >/dev/null 2>&1; then
        if on_ac_power; then
            ON_BATTERY=0
        else
            ON_BATTERY=1
        fi
    elif command -v upower >/dev/null 2>&1; then
        local battery
        battery=$(upower -e 2>/dev/null | grep BAT | head -n1 || true)
        if [ -n "$battery" ] && upower -i "$battery" 2>/dev/null | grep -qi "state:.*discharging"; then
            ON_BATTERY=1
        fi
    fi
}

load_config() {
    local file="$CONFIG_FILE"
    if [ -f "$file" ]; then
        print_info "Loading configuration from $file"
        # shellcheck disable=SC1090
        . "$file"
    elif [ -f /etc/system-resource-protection.conf ]; then
        file=/etc/system-resource-protection.conf
        print_info "Loading configuration from $file"
        # shellcheck disable=SC1090
        . "$file"
    fi
}

maybe_dry_run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        print_info "[plan mode] $1"
        return 0
    fi
    return 1
}

retry_cmd() {
    local attempts=${2:-3}
    local delay=2
    local i
    for i in $(seq 1 "$attempts"); do
        : "$i"
        if eval "$1"; then
            return 0
        fi
        sleep "$delay"
        delay=$((delay * 2))
    done
    return 1
}

git_clone_retry() {
    local url="$1" dest="$2"
    retry_cmd "git clone -q --depth 1 $url $dest" 3
}

apt_install() {
    if [ "$HAS_APT" -ne 1 ]; then
        die "apt is not available but was expected."
    fi

    if [ "$APT_UPDATED" -eq 0 ]; then
        if maybe_dry_run "Would run: sudo apt-get update"; then
            :
        else
            print_info "Updating package index (apt-get update)..."
            sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
        fi
        APT_UPDATED=1
    fi

    print_info "Installing packages: $*"
    if maybe_dry_run "Would install: $*"; then
        return
    fi
    local quoted_pkgs
    quoted_pkgs=$(printf " %q" "$@")
    retry_cmd "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq${quoted_pkgs} >/dev/null" 3 || die "apt-get install failed for: $*"
}

# --------------- Step 1: Install Ananicy-cpp -----------------
install_ananicy_cpp() {
    print_step "[1/${TOTAL_STEPS}] Installing Ananicy-cpp (process auto-nicer)"

    if [ "$ENABLE_ANANICY" -ne 1 ]; then
        print_warning "Ananicy-cpp installation skipped by configuration."
        return
    fi

    if ! command -v git >/dev/null 2>&1; then
        apt_install git
    fi

    if command -v ananicy-cpp >/dev/null 2>&1; then
        print_success "ananicy-cpp already installed"
        return
    fi

    apt_install cmake build-essential libsystemd-dev libfmt-dev libspdlog-dev nlohmann-json3-dev pkg-config

    print_info "Building ananicy-cpp from source (GitLab)..."
    if maybe_dry_run "Would clone, build, and install ananicy-cpp from source"; then
        return
    fi
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT RETURN
    (
        cd "$tmpdir"
        git_clone_retry https://gitlab.com/ananicy-cpp/ananicy-cpp.git ananicy-cpp
        cd ananicy-cpp
        mkdir -p build
        cd build
        cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_SYSTEMD=ON -DUSE_EXTERNAL_JSON=ON \
            -DUSE_EXTERNAL_SPDLOG=ON -DUSE_EXTERNAL_FMTLIB=ON >/dev/null
        make -j"$(nproc)" >/dev/null
        sudo make install >/dev/null
    )
    rm -rf "$tmpdir"

    if command -v ananicy-cpp >/dev/null 2>&1; then
        print_success "ananicy-cpp installed successfully"
    else
        die "ananicy-cpp installation appears to have failed."
    fi
}

# --------------- Step 2: Configure Ananicy Rules -------------
configure_ananicy_rules() {
    print_step "[2/${TOTAL_STEPS}] Configuring Ananicy rules (browsers, compilers, IDEs, etc.)"

    if [ "$ENABLE_ANANICY" -ne 1 ]; then
        print_warning "Ananicy rule configuration skipped by configuration."
        return
    fi

    if [ "$HAS_SYSTEMD" -ne 1 ]; then
        print_warning "Systemd not detected; ananicy-cpp service management may not work automatically."
    fi

    local backup_dir=""
    if maybe_dry_run "Would replace /etc/ananicy.d with backup and new rules"; then
        return
    fi

    # Download community rules FIRST to a temp dir to ensure we have them before wiping
    local tmp_rules_dir
    tmp_rules_dir=$(mktemp -d)
    # Trap to clean up tmp dir on return/exit, but we might mv it, so we handle cleanup manually
    
    print_info "Fetching community Ananicy rules (CachyOS)..."
    local fetch_success=0
    if retry_cmd "git clone -q --depth 1 https://github.com/CachyOS/ananicy-rules.git $tmp_rules_dir" 3; then
        fetch_success=1
    else
        print_warning "Failed to clone community rules. Proceeding with SRPS custom rules only."
        rm -rf "$tmp_rules_dir"
    fi

    # Now we touch the system config
    if [ -d /etc/ananicy.d ]; then
        if sudo test -f /etc/ananicy.d/.srps_backup 2>/dev/null; then
            backup_dir="$(sudo cat /etc/ananicy.d/.srps_backup 2>/dev/null | head -n1 || echo "")"
            print_info "Existing SRPS-managed Ananicy rules detected; using prior backup reference: ${backup_dir:-<none>}"
        else
            backup_dir="/etc/ananicy.d.backup-$(date +%Y%m%d-%H%M%S)"
            print_info "Backing up current /etc/ananicy.d to $backup_dir"
            sudo cp -a /etc/ananicy.d "$backup_dir"
        fi
        sudo rm -rf /etc/ananicy.d
    fi

    sudo mkdir -p /etc/ananicy.d
    
    if [ "$fetch_success" -eq 1 ]; then
        # Move fetched rules into place (using /. to include hidden files)
        sudo cp -a "$tmp_rules_dir"/. /etc/ananicy.d/ 2>/dev/null || true
        # Ensure strict root ownership (cp -a from user tmp might preserve user owner)
        sudo chown -R root:root /etc/ananicy.d
        rm -rf "$tmp_rules_dir"
    else
        # Ensure minimal structure if fetch failed
        sudo mkdir -p /etc/ananicy.d/{00-cgroups,00-types,00-default}
    fi

    print_info "Installing SRPS custom rules for heavyweight processes..."
    sudo tee /etc/ananicy.d/00-default/99-system-resource-protection.rules >/dev/null << 'EOF'
# ============================================================
#  system_resource_protection_script custom rules
#  Focus: compilers, browsers, IDEs, language servers, VMs, etc.
# ============================================================

# --- Rust / Cargo / C++ toolchain: push to background ----------
NAME=cargo                      NICE=19  SCHED=idle   IOCLASS=idle
NAME=rustc                      NICE=19  SCHED=idle   IOCLASS=idle
NAME=rust-analyzer              NICE=15  SCHED=batch  IOCLASS=best-effort
NAME=cc1plus                    NICE=15  SCHED=batch  IOCLASS=idle
NAME=cc1                        NICE=15  SCHED=batch  IOCLASS=idle
NAME=ld                         NICE=15  SCHED=batch  IOCLASS=idle
NAME=lld                        NICE=15  SCHED=batch  IOCLASS=idle
NAME=mold                       NICE=15  SCHED=batch  IOCLASS=idle
NAME=as                         NICE=15  SCHED=batch  IOCLASS=idle

# --- GNU / LLVM compilers, build tools ------------------------
NAME=gcc                        NICE=10  SCHED=batch  IOCLASS=idle
NAME=g++                        NICE=10  SCHED=batch  IOCLASS=idle
NAME=clang                      NICE=10  SCHED=batch  IOCLASS=idle
NAME=clang++                    NICE=10  SCHED=batch  IOCLASS=idle
NAME=make                       NICE=10  SCHED=batch  IOCLASS=idle
NAME=ninja                      NICE=10  SCHED=batch  IOCLASS=idle
NAME=cmake                      NICE=10  SCHED=batch  IOCLASS=idle

# --- Node.js and bundlers -------------------------------------
NAME=node                       NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=100
NAME=node.exe                   NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=100
NAME=npm                        NICE=10  SCHED=batch  IOCLASS=best-effort
NAME=yarn                       NICE=10  SCHED=batch  IOCLASS=best-effort
NAME=pnpm                       NICE=10  SCHED=batch  IOCLASS=best-effort
NAME=webpack                    NICE=10  SCHED=batch  IOCLASS=best-effort
NAME=rollup                     NICE=10  SCHED=batch  IOCLASS=best-effort
NAME=vite                       NICE=10  SCHED=batch  IOCLASS=best-effort

# --- Browsers (prevent them from dominating CPU/RAM) ----------
NAME=chrome                     NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=chromium                   NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=chrome.exe                 NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=brave                      NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=brave-browser              NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=firefox                    NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=firefox-esr                NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=msedge                     NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=150

# --- Electron apps --------------------------------------------
NAME=slack                      NICE=10  SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=200
NAME=discord                    NICE=10  SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=200
NAME=teams                      NICE=10  SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=200
NAME=zoom                       NICE=5   SCHED=other  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=code                       NICE=5   SCHED=other  IOCLASS=best-effort
NAME=vscode                     NICE=5   SCHED=other  IOCLASS=best-effort
NAME=electron                   NICE=5   SCHED=batch  IOCLASS=best-effort

# --- Cursor IDE (balanced, but not allowed to eat machine) ----
NAME=cursor                     NICE=2   SCHED=other  IOCLASS=best-effort  OOM_SCORE_ADJ=50
NAME=Cursor                     NICE=2   SCHED=other  IOCLASS=best-effort  OOM_SCORE_ADJ=50
NAME=cursor.exe                 NICE=2   SCHED=other  IOCLASS=best-effort  OOM_SCORE_ADJ=50

# --- Language servers & tooling -------------------------------
NAME=tsserver                   NICE=8   SCHED=batch  IOCLASS=best-effort
NAME=typescript-language-server NICE=10 SCHED=batch  IOCLASS=idle
NAME=eslint                     NICE=10  SCHED=batch  IOCLASS=idle
NAME=prettier                   NICE=10  SCHED=batch  IOCLASS=idle
NAME=pyright-langserver         NICE=10  SCHED=batch  IOCLASS=idle
NAME=rust-analyzer              NICE=15  SCHED=batch  IOCLASS=best-effort

# --- Python / data science ------------------------------------
NAME=python                     NICE=5   SCHED=other  IOCLASS=best-effort
NAME=python3                    NICE=5   SCHED=other  IOCLASS=best-effort
NAME=ipython                    NICE=5   SCHED=other  IOCLASS=best-effort
NAME=jupyter-notebook           NICE=5   SCHED=other  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=jupyter-lab                NICE=5   SCHED=other  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=pip                        NICE=10  SCHED=batch  IOCLASS=idle
NAME=pip3                       NICE=10  SCHED=batch  IOCLASS=idle

# --- Java / JVM-heavy builds ---------------------------------
NAME=java                       NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=java.exe                   NICE=5   SCHED=batch  IOCLASS=best-effort  OOM_SCORE_ADJ=150
NAME=gradle                     NICE=10  SCHED=batch  IOCLASS=idle
NAME=mvn                        NICE=10  SCHED=batch  IOCLASS=idle
NAME=sbt                        NICE=10  SCHED=batch  IOCLASS=idle

# --- Containers & virtualization ------------------------------
NAME=dockerd                    NICE=5   SCHED=other  IOCLASS=best-effort
NAME=containerd                 NICE=5   SCHED=other  IOCLASS=best-effort
NAME=podman                     NICE=5   SCHED=other  IOCLASS=best-effort
NAME=virt-qemu                  NICE=5   SCHED=batch  IOCLASS=best-effort
NAME=qemu-system-x86_64         NICE=5   SCHED=batch  IOCLASS=best-effort
NAME=virsh                      NICE=5   SCHED=batch  IOCLASS=best-effort

# --- Misc system-friendly tweaks ------------------------------
NAME=rg                         NICE=5   SCHED=other  IOCLASS=best-effort
NAME=ag                         NICE=5   SCHED=other  IOCLASS=best-effort
NAME=ripgrep                    NICE=5   SCHED=other  IOCLASS=best-effort
EOF

    printf '%s\n' "${backup_dir}" | sudo tee /etc/ananicy.d/.srps_backup >/dev/null

    if [ "$HAS_SYSTEMD" -eq 1 ]; then
        print_info "Enabling and starting ananicy-cpp service..."
        if maybe_dry_run "Would systemctl daemon-reload && enable --now ananicy-cpp"; then
            :
        else
            sudo systemctl daemon-reload
            if sudo systemctl enable --now ananicy-cpp >/dev/null 2>&1; then
            sleep 2
            local rule_count="?"
            if command -v journalctl >/dev/null 2>&1; then
                rule_count="$(sudo journalctl -u ananicy-cpp -n 50 --no-pager 2>/dev/null | grep -oP 'Worker initialized with \K[0-9]+' | tail -1 || echo '?')"
            fi
            print_success "ananicy-cpp is active (rules loaded: ${rule_count})"

            if systemctl is-active --quiet gamemoded.service 2>/dev/null; then
                print_warning "gamemoded.service is active. GameMode and ananicy-cpp both renice processes and can conflict; if you see odd scheduling behaviour, consider disabling one of them."
            fi
        else
            print_warning "Failed to enable/start ananicy-cpp; check with: sudo systemctl status ananicy-cpp"
        fi
        fi
    else
        print_warning "Skipping ananicy-cpp service enable (no systemd detected)."
    fi
}

# --------------- Step 3: EarlyOOM Setup ----------------------
install_and_configure_earlyoom() {
    print_step "[3/${TOTAL_STEPS}] Installing and configuring EarlyOOM"

    if [ "$ENABLE_EARLYOOM" -ne 1 ]; then
        print_warning "EarlyOOM installation/configuration skipped by configuration."
        return
    fi

    if ! command -v earlyoom >/dev/null 2>&1; then
        apt_install earlyoom
        print_success "earlyoom installed"
    else
        print_success "earlyoom already installed"
    fi

    if [ "$HAS_SYSTEMD" -eq 1 ] && systemctl is-active --quiet systemd-oomd.service 2>/dev/null; then
        print_warning "systemd-oomd.service is active; earlyoom + systemd-oomd can overlap. Consider disabling one of them if you see double OOM handling."
    fi

    if sudo test -f /etc/default/earlyoom 2>/dev/null && ! sudo grep -q "system_resource_protection_script" /etc/default/earlyoom 2>/dev/null; then
        if maybe_dry_run "Would back up /etc/default/earlyoom to /etc/default/earlyoom.srps-backup"; then
            :
        else
            print_info "Backing up existing /etc/default/earlyoom to /etc/default/earlyoom.srps-backup"
            sudo cp /etc/default/earlyoom /etc/default/earlyoom.srps-backup
        fi
    fi

    print_info "Writing SRPS EarlyOOM preferences..."
    local earlyoom_args_value earlyoom_args_comment earlyoom_args_escaped

    if [ -n "${SRPS_EARLYOOM_ARGS:-}" ]; then
        if printf '%s' "$SRPS_EARLYOOM_ARGS" | grep -q $'\n'; then
            print_warning "SRPS_EARLYOOM_ARGS contains newlines; collapsing to a single line."
            earlyoom_args_value=$(printf '%s' "$SRPS_EARLYOOM_ARGS" | tr '\n' ' ')
        else
            earlyoom_args_value="$SRPS_EARLYOOM_ARGS"
        fi

        if [ -z "${earlyoom_args_value//[[:space:]]/}" ]; then
            print_warning "SRPS_EARLYOOM_ARGS is empty after cleanup; falling back to SRPS defaults."
            earlyoom_args_value=""
        else
            earlyoom_args_comment="# Using custom EARLYOOM_ARGS from SRPS_EARLYOOM_ARGS"
        fi
    fi

    if [ -z "${earlyoom_args_value:-}" ]; then
        if [ "$ON_BATTERY" -eq 1 ]; then
            earlyoom_args_comment="# Default SRPS configuration (laptop/battery: slightly earlier intervention)"
            earlyoom_args_value="-r 300 -m 4 -s 8 \
  --avoid 'Xorg|gnome-shell|systemd|sshd|sway|wayland|plasmashell|kwin_x11|kwin_wayland|code|vscode' \
  --prefer 'chrome|chromium|firefox|brave|msedge|cargo|rustc|node|npm|yarn|pnpm|java|python3?|jupyter.*|cursor|slack|discord|teams|zoom' \
  --ignore-root-user -p"
        else
            earlyoom_args_comment="# Default SRPS configuration (tuned for interactive dev workloads)"
            earlyoom_args_value="-r 300 -m 2 -s 5 \
  --avoid 'Xorg|gnome-shell|systemd|sshd|sway|wayland|plasmashell|kwin_x11|kwin_wayland|code|vscode' \
  --prefer 'chrome|chromium|firefox|brave|msedge|cargo|rustc|node|npm|yarn|pnpm|java|python3?|jupyter.*|cursor|slack|discord|teams|zoom' \
  --ignore-root-user -p"
        fi
    fi

    earlyoom_args_escaped=$(printf '%q' "$earlyoom_args_value")

    if maybe_dry_run "Would write /etc/default/earlyoom with EARLYOOM_ARGS"; then
        :
    else
        sudo tee /etc/default/earlyoom >/dev/null <<EOF
# Generated by system_resource_protection_script
# -r 300 : log every 5 minutes
# -m 2   : act when free memory < 2%
# -s 5   : act when free swap < 5%
#   -p                 : keep earlyoom itself highly prioritized
#   --ignore-root-user : avoid killing root-owned system services
$earlyoom_args_comment
EARLYOOM_ARGS=$earlyoom_args_escaped
EOF
    fi

    if [ "$HAS_SYSTEMD" -eq 1 ]; then
        print_info "Enabling and restarting earlyoom..."
        if maybe_dry_run "Would systemctl enable --now earlyoom"; then
            :
        else
            if sudo systemctl enable --now earlyoom >/dev/null 2>&1; then
                print_success "earlyoom is active and protecting against OOM freezes"
            else
                print_warning "Failed to enable/start earlyoom; check with: sudo systemctl status earlyoom"
            fi
        fi
    else
        print_warning "Systemd not detected; you may need to start earlyoom manually."
    fi
}

# --------------- Step 4: Sysctl Tweaks -----------------------
configure_sysctl() {
    print_step "[4/${TOTAL_STEPS}] Applying kernel (sysctl) responsiveness tweaks"

    if [ "$ENABLE_SYSCTL" -ne 1 ]; then
        print_warning "Sysctl tweaks skipped by configuration."
        return
    fi

    local sysctl_file="/etc/sysctl.d/99-system-resource-protection.conf"

    if sudo test -f "$sysctl_file" 2>/dev/null && ! sudo grep -q "system_resource_protection_script" "$sysctl_file" 2>/dev/null; then
        if maybe_dry_run "Would back up $sysctl_file to ${sysctl_file}.srps-backup"; then
            :
        else
            print_info "Backing up existing $sysctl_file to ${sysctl_file}.srps-backup"
            sudo cp "$sysctl_file" "${sysctl_file}.srps-backup"
        fi
    fi

    if maybe_dry_run "Would write $sysctl_file"; then
        :
    else
        sudo tee "$sysctl_file" >/dev/null << 'EOF'
# Generated by system_resource_protection_script
# Better desktop / dev-box responsiveness under high load

# Memory / writeback behavior
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

# Inotify limits (for IDEs / file watchers)
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024

# Network defaults (ok to be no-op if unavailable)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Allow many memory mappings (large codebases, containers, etc.)
vm.max_map_count = 2147483642
EOF
    fi

    if maybe_dry_run "Would apply sysctl -p $sysctl_file"; then
        :
    else
        if sudo sysctl -p "$sysctl_file" >/dev/null 2>&1; then
            print_success "Sysctl parameters applied"
        else
            print_warning "sysctl -p returned an error; some tunables may be unsupported by your kernel."
        fi
    fi
}

# --------------- Step 5: WSL2 / systemd Limits ---------------
configure_wsl_limits() {
    print_step "[5/${TOTAL_STEPS}] Configuring WSL2/systemd default limits (if applicable)"

    if [ "$ENABLE_WSL_LIMITS" -ne 1 ]; then
        print_warning "WSL/systemd limits skipped by configuration."
        return
    fi

    if [ "$HAS_SYSTEMD" -ne 1 ]; then
        print_warning "No systemd detected; skipping system.conf.d limits."
        return
    fi

    if [ "$IS_WSL" -ne 1 ]; then
        print_info "Not running under WSL; applying generic systemd manager limits instead."
    else
        print_info "WSL environment detected; applying systemd manager limits tuned for dev workloads."
    fi

    local conf_dir="/etc/systemd/system.conf.d"
    local conf_file="${conf_dir}/10-system-resource-protection.conf"

    if maybe_dry_run "Would ensure $conf_dir"; then
        :
    else
        sudo mkdir -p "$conf_dir"
    fi

    if sudo test -f "$conf_file" 2>/dev/null && ! sudo grep -q "system_resource_protection_script" "$conf_file" 2>/dev/null; then
        if maybe_dry_run "Would back up $conf_file to ${conf_file}.srps-backup"; then
            :
        else
            print_info "Backing up existing $conf_file to ${conf_file}.srps-backup"
            sudo cp "$conf_file" "${conf_file}.srps-backup"
        fi
    fi

    if maybe_dry_run "Would write $conf_file"; then
        :
    else
        sudo tee "$conf_file" >/dev/null << 'EOF'
# Generated by system_resource_protection_script
[Manager]
DefaultCPUAccounting=yes
DefaultMemoryAccounting=yes
DefaultTasksAccounting=yes
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=32768
EOF
    fi

    if maybe_dry_run "Would systemctl daemon-reload"; then
        :
    else
        sudo systemctl daemon-reload
        print_success "Systemd manager limits configured (effective after next boot of PID 1)"
    fi
}

# --------------- Step 6: Monitoring & Utilities --------------
create_monitoring_and_tools() {
    print_step "[6/${TOTAL_STEPS}] Creating monitoring tools and helpers"

    if [ "$ENABLE_TOOLS" -ne 1 ]; then
        print_warning "Monitoring tools skipped by configuration."
        return
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        print_info "[plan mode] Would install sysmon, check-throttled, cursor-guard, kill-cursor, srps-doctor, srps-reload-rules, srps-pull-rules, srps-report"
        return
    fi

    # --- sysmon ------------------------------------------------
    local sysmon="/usr/local/bin/sysmon"
    if sudo test -f "$sysmon" 2>/dev/null && ! sudo grep -q "system_resource_protection_script" "$sysmon" 2>/dev/null; then
        print_info "Backing up existing $sysmon to ${sysmon}.srps-backup"
        sudo cp "$sysmon" "${sysmon}.srps-backup"
    fi

    print_info "Installing sysmon (live system monitor)..."
    sudo tee "$sysmon" >/dev/null << 'EOF'
#!/usr/bin/env bash
# Generated by system_resource_protection_script
# Colorful, low-dependency TUI with live + historical hogs, per-core bars,
# disk/net throughput, optional focus highlighting, and JSON snapshot/stream.

set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
sysmon - live system monitor
Env flags:
  SRPS_SYSMON_INTERVAL       Base refresh interval (default 1s)
  SRPS_SYSMON_PERCORE        1=show per-core bars (default 1)
  SRPS_SYSMON_FOCUS          Regex to pre-filter top list (optional)
  SRPS_SYSMON_JSON           1=one-shot JSON snapshot, then exit
  SRPS_SYSMON_JSON_STREAM    1=NDJSON stream each interval
  SRPS_SYSMON_JSON_FILE      Path to write JSON (overwrites; streams append)
  SRPS_SYSMON_ADAPTIVE       1=double interval when not on a TTY
USAGE
  exit 0
fi

interval=${SRPS_SYSMON_INTERVAL:-1}
rows=$(tput lines 2>/dev/null || echo 24)
cols=$(tput cols 2>/dev/null || echo 80)
bar_width=$((cols/3)); [ "$bar_width" -lt 12 ] && bar_width=12
percore=${SRPS_SYSMON_PERCORE:-1}
focus_re="${SRPS_SYSMON_FOCUS:-}"
json_mode=${SRPS_SYSMON_JSON:-0}
json_stream=${SRPS_SYSMON_JSON_STREAM:-0}
adaptive=${SRPS_SYSMON_ADAPTIVE:-0}
json_file=${SRPS_SYSMON_JSON_FILE:-}

if [ "$json_stream" = "1" ] && [ "$json_mode" = "0" ]; then json_mode=1; fi
[ -n "$json_file" ] && json_mode=1

# State
declare -A cpu_accu max_mem max_cpu prev_core_total prev_core_idle prev_dev_r prev_dev_w
prev_net_rx=""; prev_net_tx=""; prev_disk_r=""; prev_disk_w=""; dev_metrics_json="[]"
last_cpu_pct=0; mem_pct_last=0; start_ts=$(date +%s)
peak_rd_mb=0; peak_wr_mb=0; peak_rx_mbps=0; peak_tx_mbps=0

# Colors
if command -v tput >/dev/null 2>&1; then
  c(){ tput setaf "$1"; }; b(){ tput bold; }; r(){ tput sgr0; }
else
  c(){ printf '[0;3%sm' "$1"; }; b(){ printf '[1m'; }; r(){ printf '[0m'; }
fi

bar(){
  local pct=${1:-0} width=${2:-20} filled
  filled=$(( pct * width / 100 ))
  printf '['
  if [ "$filled" -gt 0 ]; then printf '%0.s#' $(seq 1 "$filled"); fi
  if [ $((width-filled)) -gt 0 ]; then printf '%0.s-' $(seq 1 $((width-filled))); fi
  printf '] %3s%%' "$pct"
}

read_cpu_counters(){ read -r _ u n s i io irq si st _ < /proc/stat; echo $((i+io)) $((u+n+s+irq+si+st)); }

adapt_interval_if_needed(){ if [ "$adaptive" -eq 1 ] && { [ ! -t 1 ] || [ -z "${PS1:-}" ]; }; then interval=$(awk -v i="$interval" 'BEGIN{printf "%.2f", i*2}'); fi; }

cpu_line(){
  read t i <<<"$(read_cpu_counters)"
  if [ -z "${prev_total:-}" ]; then
    pct=0
  else
    dt=$((t-prev_total)); di=$((i-prev_idle))
    pct=$(awk -v dt="$dt" -v di="$di" 'BEGIN{if(dt<=0)print 0; else printf "%.0f", (1-di/dt)*100}')
  fi
  prev_total=$t; prev_idle=$i; last_cpu_pct=$pct
  [ "$json_mode" = "1" ] && return
  printf "%sCPU%s   " "$(c 4)" "$(r)"; bar "$pct" "$bar_width"; printf "  load %s
" "$(awk '{printf "%s %s %s", $1, $2, $3}' /proc/loadavg)"
}

mem_line(){
  read -r total avail <<<"$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END{print t,a}' /proc/meminfo)"
  used=$((total-avail)); pct=$(awk -v u="$used" -v t="$total" 'BEGIN{if(t==0)print 0; else printf "%.0f", (u/t)*100}')
  mem_pct_last=$pct
  read -r st sf <<<"$(awk '/SwapTotal/{t=$2} /SwapFree/{f=$2} END{print t,f}' /proc/meminfo)"; su=$((st-sf))
  spct=$(awk -v u="$su" -v t="$st" 'BEGIN{if(t==0)print 0; else printf "%.0f", (u/t)*100}')
  [ "$json_mode" = "1" ] && return
  printf "%sMEM%s  " "$(c 3)" "$(r)"; bar "$pct" "$bar_width"; printf "  %5.1f/%5.1f GiB | Swap %3s%%
" "$(awk -v v="$used" 'BEGIN{printf "%.1f", v/1048576}')" "$(awk -v v="$total" 'BEGIN{printf "%.1f", v/1048576}')" "$spct"
}

collect_cgroups(){ cgroup_txt=""; cgroup_json="["; cf=1; ps -eo cgroup,%cpu --sort=-%cpu --no-headers | head -n 50 | awk '{cg=$1; gsub(/^.+:/,"",cg); if(cg=="-") cg="unknown"; n=split(cg,a,"/"); name=a[n]; if(name=="") name="/"; cpu=$2; sum[name]+=cpu} END{for(n in sum) print sum[n],n}' | sort -nr | head -n 5 | while read -r cpu name; do cgroup_txt+=$(printf "%-20s CPU:%5.1f%%
" "$name" "$cpu"); [ $cf -eq 1 ] || cgroup_json+=","; cf=0; cgroup_json+=$(printf '{"cgroup":"%s","cpu":%.1f}' "$name" "$cpu"); done; cgroup_json+="]"; }

print_cgroups(){ if [ "$percore" -eq 1 ] && [ -n "$cgroup_txt" ]; then printf "%sTop cgroups (CPU)%s
%s
" "$(c 5)" "$(r)" "$cgroup_txt"; fi; }

print_top_cpu(){ printf "%sTop CPU (live)%s  comm pid ni cpu mem
" "$(c 1)" "$(r)"; printf "%-18s %-6s %-5s %-7s %-7s
" "------------------" "------" "-----" "-------" "-------"; while IFS='|' read -r pid ni cpu mem comm; do [ -z "$comm" ] && continue; printf "%-18s %-6s NI:%3s CPU:%5s%% MEM:%5s%%
" "$comm" "$pid" "$ni" "$cpu" "$mem"; done <<< "${view:-$snapshot}"; printf "
"; }

print_throttled(){ printf "%sThrottled (nice>0, live)%s
" "$(c 2)" "$(r)"; ps -eo comm,pid,ni,%cpu,%mem --sort=-ni --no-headers | awk '$3>0 {printf "%-18s %-6s NI:%3s CPU:%5s%% MEM:%5s%%
", $1, $2, $3, $4, $5}' | head -n 8; }

print_historical(){ printf "
%sHistorical hogs (since start)%s
" "$(c 5)" "$(r)"; if [ ${#cpu_accu[@]} -eq 0 ]; then echo "(no samples yet)"; return; fi; for k in "${!cpu_accu[@]}"; do printf "%s %s
" "${cpu_accu[$k]}" "$k"; done | sort -nr | head -n 6 | while read -r score name; do cpu_int=$(awk -v s="$score" 'BEGIN{printf "%.1f", s/10}'); printf "%-18s CPU∫:%6.1f  maxCPU:%5s%%  maxMEM:%5s%%
" "$name" "$cpu_int" "${max_cpu[$name]:-0}" "${max_mem[$name]:-0}"; done; }

print_per_core(){ [ "$percore" -eq 1 ] || return; printf "
%sPer-core CPU%s
" "$(c 4)" "$(r)"; while read -r label user nice system idle iowait irq softirq steal _; do case "$label" in cpu) continue ;; cpu*) ;; *) continue;; esac; core=${label#cpu}; total=$((user+nice+system+idle+iowait+irq+softirq+steal)); idle_all=$((idle+iowait)); prev_t=${prev_core_total[$core]:-0}; prev_i=${prev_core_idle[$core]:-0}; if [ "$prev_t" -eq 0 ]; then pct=0; else dt=$((total-prev_t)); di=$((idle_all-prev_i)); pct=$(awk -v dt="$dt" -v di="$di" 'BEGIN{if(dt<=0){print 0}else{printf "%.0f", (1-di/dt)*100}}'); fi; prev_core_total[$core]=$total; prev_core_idle[$core]=$idle_all; printf "cpu%-3s " "$core"; bar "$pct" 20; printf "
"; done < /proc/stat; }

delta_counter(){ local prev="$1" cur="$2"; if [ -z "$prev" ]; then _delta=0; else _delta=$((cur-prev)); fi; }

disk_net_lines(){
  local read_sectors=0 write_sectors=0 dev
  local dev_json="["; local dev_first=1
  if [ -r /proc/diskstats ]; then
    while read -r _ _ dev rIO rmerge rsect _ wIO wmerge wsect _ _ _ _; do
      case "$dev" in sd*|nvme*n*|vd*)
        read_sectors=$((read_sectors + rsect)); write_sectors=$((write_sectors + wsect))
        delta_counter "${prev_dev_r[$dev]:-}" "$rsect"; rd_d=$_delta; prev_dev_r[$dev]=$rsect
        delta_counter "${prev_dev_w[$dev]:-}" "$wsect"; wr_d=$_delta; prev_dev_w[$dev]=$wsect
        dev_r_mb=$(awk -v s="$rd_d" -v iv="$interval" 'BEGIN {printf "%.2f", s*512/1048576/iv}')
        dev_w_mb=$(awk -v s="$wr_d" -v iv="$interval" 'BEGIN {printf "%.2f", s*512/1048576/iv}')
        if [ "$json_mode" = "1" ] || [ "$json_stream" = "1" ]; then
          [ $dev_first -eq 1 ] || dev_json+=","; dev_first=0
          dev_json+=$(printf '{"dev":"%s","read_mb_s":%s,"write_mb_s":%s}' "$dev" "$dev_r_mb" "$dev_w_mb")
        fi
      ;; esac
    done < /proc/diskstats
  fi
  dev_json+="]"; dev_metrics_json=$dev_json

  delta_counter "$prev_disk_r" "$read_sectors"; rd=$_delta; prev_disk_r=$read_sectors
  delta_counter "$prev_disk_w" "$write_sectors"; wr=$_delta; prev_disk_w=$write_sectors
  rd_mb=$(awk -v s="$rd" -v iv="$interval" 'BEGIN {printf "%.1f", s*512/1048576/iv}')
  wr_mb=$(awk -v s="$wr" -v iv="$interval" 'BEGIN {printf "%.1f", s*512/1048576/iv}')

  local rx_bytes=0 tx_bytes=0
  if [ -r /proc/net/dev ]; then
    while read -r iface rest; do
      rx=$(echo "$rest" | awk '{print $1}'); tx=$(echo "$rest" | awk '{print $9}')
      rx_bytes=$((rx_bytes + rx)); tx_bytes=$((tx_bytes + tx))
    done < <(sed -n '3,$p' /proc/net/dev | tr -s ' ')
  fi

  delta_counter "$prev_net_rx" "$rx_bytes"; rx_d=$_delta; prev_net_rx=$rx_bytes
  delta_counter "$prev_net_tx" "$tx_bytes"; tx_d=$_delta; prev_net_tx=$tx_bytes
  rx_mbps=$(awk -v b="$rx_d" -v iv="$interval" 'BEGIN {printf "%.1f", (b*8/1e6)/iv}')
  tx_mbps=$(awk -v b="$tx_d" -v iv="$interval" 'BEGIN {printf "%.1f", (b*8/1e6)/iv}')

  last_rd_mb=$rd_mb; last_wr_mb=$wr_mb; last_rx_mbps=$rx_mbps; last_tx_mbps=$tx_mbps
  peak_rd_mb=$(awk -v cur="$rd_mb" -v prev="$peak_rd_mb" 'BEGIN{if(cur>prev)print cur; else print prev}')
  peak_wr_mb=$(awk -v cur="$wr_mb" -v prev="$peak_wr_mb" 'BEGIN{if(cur>prev)print cur; else print prev}')
  peak_rx_mbps=$(awk -v cur="$rx_mbps" -v prev="$peak_rx_mbps" 'BEGIN{if(cur>prev)print cur; else print prev}')
  peak_tx_mbps=$(awk -v cur="$tx_mbps" -v prev="$peak_tx_mbps" 'BEGIN{if(cur>prev)print cur; else print prev}')
}

print_io_net(){
  printf "%sIO%s   R:%5.1fMB/s W:%5.1fMB/s (peak %5.1f/%5.1f)   %sNET%s RX:%5.1fMb/s TX:%5.1fMb/s (peak %5.1f/%5.1f)
"     "$(c 6)" "$(r)" "$last_rd_mb" "$last_wr_mb" "$peak_rd_mb" "$peak_wr_mb" "$(c 6)" "$(r)" "$last_rx_mbps" "$last_tx_mbps" "$peak_rx_mbps" "$peak_tx_mbps"
}

print_footer(){ runtime=$(( $(date +%s) - start_ts )); printf "
%sTip:%s SRPS_SYSMON_INTERVAL=2 to slow refresh; SRPS_SYSMON_FOCUS='node' to focus; Ctrl+C to exit.  Uptime: %ss
" "$(c 6)" "$(r)" "$runtime"; }

prev_total=""; prev_idle=""; json_warmup=0; adapt_interval_if_needed

while true; do
  snapshot=$(ps -eo pid,ni,pcpu,pmem,comm --sort=-pcpu --no-headers | awk '{printf "%s|%s|%s|%s|%s\\n",$1,$2,$3,$4,$5}' | head -n 8)
  view="$snapshot"

  while IFS='|' read -r pid ni cpu mem comm; do
    [ -z "$comm" ] && continue
    cpu10=$(awk -v c="$cpu" 'BEGIN {printf "%d", c*10}')
    inc=$(awk -v c10="$cpu10" -v iv="$interval" 'BEGIN {printf "%d", c10*iv}')
    cpu_accu["$comm"]=$(( ${cpu_accu[$comm]:-0} + inc ))
    cur_cpu_int=$(awk -v c="$cpu" 'BEGIN {printf "%.1f", c}')
    cur_mem_int=$(awk -v m="$mem" 'BEGIN {printf "%.1f", m}')
    awk -v cur="$cur_cpu_int" -v max="${max_cpu[$comm]:-0}" 'BEGIN {exit !(cur>max)}' && max_cpu[$comm]=$cur_cpu_int
    awk -v cur="$cur_mem_int" -v max="${max_mem[$comm]:-0}" 'BEGIN {exit !(cur>max)}' && max_mem[$comm]=$cur_mem_int
  done <<< "$snapshot"

  if [ "$json_mode" != "1" ]; then
    clear 2>/dev/null || true
    printf "%s%sSYSTEM RESOURCE MONITOR%s
" "$(b)" "$(c 6)" "$(r)"
    printf "%s%(%a %b %d %H:%M:%S %Z %Y)T%s
" "$(b)" -1 "$(r)"
    disk_net_lines; print_io_net
    cpu_line; mem_line; collect_cgroups; printf "
"

    if [ -n "$focus_re" ]; then
      focus_view=$(echo "$snapshot" | grep -E "$focus_re" || true)
      printf "%sFocus (re: %s)%s
" "$(c 6)" "$focus_re" "$(r)"
      if [ -n "$focus_view" ]; then
        while IFS='|' read -r pid ni cpu mem comm; do
          [ -z "$comm" ] && continue
          printf "%-18s %-6s NI:%3s CPU:%5s%% MEM:%5s%%
" "$comm" "$pid" "$ni" "$cpu" "$mem"
        done <<< "$focus_view"
        printf "
"; view="$focus_view"
      else
        echo "(no matches)
"
      fi
    fi

    print_top_cpu; print_throttled; print_historical; print_per_core; print_cgroups; print_footer
  else
    disk_net_lines; cpu_line; mem_line; collect_cgroups
  fi

  if [ "$json_mode" = "1" ]; then
    if [ $json_warmup -eq 0 ]; then json_warmup=1; sleep "$interval"; continue; fi
    esc(){ printf '%s' "$1" | sed 's/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g'; }
    top_json="["; tf=1
    while IFS='|' read -r pid ni cpu mem comm; do
      [ -n "$comm" ] || continue
      [ $tf -eq 1 ] || top_json+=","; tf=0
      top_json+=$(printf '{"cmd":"%s","pid":%s,"nice":%s,"cpu":%s,"mem":%s}' "$(esc "$comm")" "$pid" "$ni" "$cpu" "$mem")
    done <<< "$view"
    top_json+="]"

    hist_json="["; hf=1
    for k in "${!cpu_accu[@]}"; do
      [ $hf -eq 1 ] || hist_json+=","; hf=0
      cpu_int=$(awk -v s="${cpu_accu[$k]}" 'BEGIN {printf "%.1f", s/10}')
      hist_json+=$(printf '{"cmd":"%s","cpu_integral":%s,"max_cpu":%s,"max_mem":%s}' "$(esc "$k")" "$cpu_int" "${max_cpu[$k]:-0}" "${max_mem[$k]:-0}")
    done; hist_json+="]"

    percore_json="[]"
    if [ "$percore" -eq 1 ]; then
      pc_tmp=""
      while read -r label user nice system idle iowait irq softirq steal _; do
        case "$label" in cpu) continue ;; cpu*) ;; *) continue;; esac
        core=${label#cpu}
        total=$((user+nice+system+idle+iowait+irq+softirq+steal)); idle_all=$((idle+iowait))
        prev_t=${prev_core_total[$core]:-0}; prev_i=${prev_core_idle[$core]:-0}
        if [ "$prev_t" -eq 0 ]; then pct=0; else dt=$((total - prev_t)); di=$((idle_all - prev_i)); pct=$(awk -v dt="$dt" -v di="$di" 'BEGIN { if (dt<=0){print 0}else{printf "%.0f", (1-di/dt)*100}}'); fi
        prev_core_total[$core]=$total; prev_core_idle[$core]=$idle_all
        pc_tmp+=$(printf '{"core":"%s","cpu":%s},' "$core" "$pct")
      done < /proc/stat
      percore_json="[${pc_tmp%,}]"
    fi

    io_json=$(printf '{"disk_read_mb_s":%.1f,"disk_write_mb_s":%.1f,"net_rx_mbps":%.1f,"net_tx_mbps":%.1f,"per_device":%s}'       "$rd_mb" "$wr_mb" "$rx_mbps" "$tx_mbps" "$dev_metrics_json")

    temps_json="["; tfz=1
    for tfpath in /sys/class/thermal/thermal_zone*/temp; do
      [ -f "$tfpath" ] || continue
      t_raw=$(cat "$tfpath" 2>/dev/null || true); [ -z "$t_raw" ] && continue
      t_c=$(awk -v t="$t_raw" 'BEGIN {printf "%.1f", t/1000}')
      zone=$(basename "$(dirname "$tfpath")")
      [ $tfz -eq 1 ] || temps_json+=","; tfz=0
      temps_json+=$(printf '{"zone":"%s","temp_c":%s}' "$zone" "$t_c")
    done; temps_json+="]"

    max_w=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)
    max_i=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)
    nr_w=$(cat /proc/sys/fs/inotify/nr_watches 2>/dev/null || echo 0)
    inotify_json=$(printf '{"max_user_watches":%s,"max_user_instances":%s,"nr_watches":%s}' "$max_w" "$max_i" "$nr_w")

    json_blob=$(printf '{"timestamp":%s,"cpu":%s,"mem":%s,"top":%s,"historical":%s,"per_core":%s,"io":%s,"temps":%s,"inotify":%s,"cgroups":%s}
'       "$(date +%s)" "$last_cpu_pct" "$mem_pct_last" "$top_json" "$hist_json" "$percore_json" "$io_json" "$temps_json" "$inotify_json" "$cgroup_json")
    if [ -n "$json_file" ]; then
      if [ "$json_stream" = "1" ]; then printf "%s" "$json_blob" >>"$json_file"; else printf "%s" "$json_blob" >"$json_file"; fi
    else
      printf "%s" "$json_blob"
    fi
    [ "$json_stream" = "1" ] || exit 0
  fi

  sleep_time="$interval"
  if [ "$json_stream" != "1" ]; then
    jitter=$(awk 'BEGIN {srand(); printf "%.2f", rand()*0.15}'); sleep_time=$(awk -v b="$interval" -v j="$jitter" 'BEGIN {printf "%.2f", b+j}')
  fi
  sleep "$sleep_time"
done
EOF
    sudo chmod +x "$sysmon"

    # --- check-throttled --------------------------------------
    local check_throttled="/usr/local/bin/check-throttled"
    if sudo test -f "$check_throttled" 2>/dev/null && ! sudo grep -q "system_resource_protection_script" "$check_throttled" 2>/dev/null; then
        print_info "Backing up existing $check_throttled to ${check_throttled}.srps-backup"
        sudo cp "$check_throttled" "${check_throttled}.srps-backup"
    fi

    print_info "Installing check-throttled..."
    sudo tee "$check_throttled" >/dev/null << 'EOF'
#!/usr/bin/env bash
# Generated by system_resource_protection_script
set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
check-throttled - list processes with nice > 0
Env:
  SRPS_JSON=1   Output JSON and exit
USAGE
  exit 0
fi

if command -v tput >/dev/null 2>&1; then
  c(){ tput setaf "$1"; }; b(){ tput bold; }; r(){ tput sgr0; }
else
  c(){ printf '\033[0;3%sm' "$1"; }; b(){ printf '\033[1m'; }; r(){ printf '\033[0m'; }
fi

if [ "${SRPS_JSON:-0}" = "1" ]; then
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  printf '{"throttled":['
  first=1
  while read -r pid ni cpu mem cmd; do
    [[ "$ni" =~ ^-?[0-9]+$ ]] || continue
    [ "${ni:-0}" -gt 0 ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    io=$(ionice -p "$pid" 2>/dev/null | grep -oE 'idle|best-effort|rt|prio [0-9]+' | head -1 || true)
    printf '{"pid":%s,"cmd":"%s","nice":%s,"cpu":%.1f,"mem":%.1f,"io":"%s"}' \
      "$pid" "$(esc "$cmd")" "$ni" "$cpu" "$mem" "$(esc "${io:-}")"
  done < <(ps -eo pid,ni,%cpu,%mem,comm --sort=-%cpu --no-headers)
  printf ']}'
  exit 0
fi

printf "%s%sCurrently Throttled (nice>0)%s\n" "$(b)" "$(c 6)" "$(r)"
printf "%-22s %-6s %-6s %-8s %-8s %-10s\n" "PROCESS" "PID" "NI" "CPU%" "MEM%" "IO"
printf "%-22s %-6s %-6s %-8s %-8s %-10s\n" "----------------------" "------" "------" "------" "------" "----------"

found=0; count=0
while read -r pid ni cpu mem cmd; do
  [[ "$ni" =~ ^-?[0-9]+$ ]] || continue
  [ "${ni:-0}" -gt 0 ] || continue
  found=1
  io=$(ionice -p "$pid" 2>/dev/null | grep -oE 'idle|best-effort|rt|prio [0-9]+' | head -1 || true)
  printf "%-22s %-6s %-6s %-8.1f %-8.1f %-10s\n" "$cmd" "$pid" "$ni" "$cpu" "$mem" "${io:-?}"
  count=$((count+1)); [ $count -lt 8 ] || break
done < <(ps -eo pid,ni,%cpu,%mem,comm --sort=-%cpu --no-headers)
[ "$found" -eq 0 ] && printf "%s(no throttled processes)%s\n" "$(c 3)" "$(r)"
EOF
    sudo chmod +x "$check_throttled"

    # --- cursor-guard -----------------------------------------
    local cursor_guard="/usr/local/bin/cursor-guard"
    if sudo test -f "$cursor_guard" 2>/dev/null && ! sudo grep -q "system_resource_protection_script" "$cursor_guard" 2>/dev/null; then
        print_info "Backing up existing $cursor_guard to ${cursor_guard}.srps-backup"
        sudo cp "$cursor_guard" "${cursor_guard}.srps-backup"
    fi

    print_info "Installing cursor-guard (Node/Cursor process guard)..."
    sudo tee "$cursor_guard" >/dev/null << 'EOF'
#!/usr/bin/env bash
# Generated by system_resource_protection_script
MAX_NODE=${MAX_NODE:-25}
MAX_CPU=${MAX_CPU:-85}

node_count=$(pgrep -c -f "node(\.exe)?([[:space:]]|$)" 2>/dev/null || echo 0)
cpu_usage=$(awk -F'[, ]+' '/Cpu\(s\)/ {print 100-$8; exit}' < <(LC_ALL=C top -bn1) 2>/dev/null || echo 0)

if command -v tput >/dev/null 2>&1; then
  c(){ tput setaf "$1"; }; b(){ tput bold; }; r(){ tput sgr0; }
else
  c(){ printf '\033[0;3%sm' "$1"; }; b(){ printf '\033[1m'; }; r(){ printf '\033[0m'; }
fi

logit() {
  if command -v logger >/dev/null 2>&1; then
    logger -t srps-cursor-guard "$*"
  else
    echo "$*" >&2
  fi
}

if [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
cursor-guard - constrain runaway node/cursor processes
Env:
  MAX_NODE       Max node procs before trimming (default 25)
  MAX_CPU        CPU% threshold to renice top hogs (default 85)
  SRPS_JSON=1    Emit JSON summary instead of text
USAGE
  exit 0
fi

if [ "${SRPS_JSON:-0}" = "1" ]; then
  trimmed=0
  if [ "$node_count" -gt "$MAX_NODE" ] 2>/dev/null; then
    pids=$(ps -eo pid,lstart,comm | grep -E "node(\.exe)?$" | sort -k2,6 | awk '{print $1}')
    keep=$MAX_NODE
    kill_list=$(echo "$pids" | head -n -"${keep}" 2>/dev/null || true)
    if [ -n "$kill_list" ]; then
        trimmed=$(printf "%s\n" "$kill_list" | wc -l)
        printf "%s\n" "$kill_list" | xargs -r kill -TERM 2>/dev/null
        sleep 1
        printf "%s\n" "$kill_list" | xargs -r kill -KILL 2>/dev/null
    fi
  fi
  reniced=0
  if [ "$cpu_usage" -gt "$MAX_CPU" ] 2>/dev/null; then
    reniced=$(ps -eo pid,%cpu,ni,comm --sort=-%cpu | head -n 10 | awk '{print $1}' | wc -l)
    ps -eo pid,%cpu,ni,comm --sort=-%cpu | head -n 10 | awk '{print $1}' | xargs -r renice 19 -p 2>/dev/null
  fi
  printf '{"node_count":%s,"max_node":%s,"trimmed":%s,"cpu_usage":%s,"max_cpu":%s,"reniced":%s}' \
    "$node_count" "$MAX_NODE" "$trimmed" "$cpu_usage" "$MAX_CPU" "$reniced"
  exit 0
fi

printf "%s%sCursor/Node guard%s (MAX_NODE=%s MAX_CPU=%s)\n" "$(b)" "$(c 6)" "$(r)" "$MAX_NODE" "$MAX_CPU"

if [ "$node_count" -gt "$MAX_NODE" ] 2>/dev/null; then
    echo "$(c 1)[$(date)] Node swarm detected: $node_count (limit $MAX_NODE). Trimming oldest...$(r)"
    pids=$(ps -eo pid,lstart,comm | grep -E "node(\.exe)?$" | sort -k2,6 | awk '{print $1}')
    keep=$MAX_NODE
    kill_list=$(echo "$pids" | head -n -"${keep}" 2>/dev/null || true)
    if [ -n "$kill_list" ]; then
        echo "$kill_list" | xargs -r kill -TERM 2>/dev/null
        sleep 1
        echo "$kill_list" | xargs -r kill -KILL 2>/dev/null
        trimmed=$(printf "%s\n" "$kill_list" | wc -l)
        logit "trimmed=$trimmed node_count=$node_count limit=$MAX_NODE"
    fi
else
    echo "$(c 2)Node count OK ($node_count/$MAX_NODE)$(r)"
fi

if [ "$cpu_usage" -gt "$MAX_CPU" ] 2>/dev/null; then
    echo "$(c 1)[$(date)] High CPU $cpu_usage%% → renice top hogs to 19$(r)"
    renice_list=$(ps -eo pid,%cpu,ni,comm --sort=-%cpu | head -n 10 | awk '{print $1}')
    printf "%s\n" "$renice_list" | xargs -r renice 19 -p 2>/dev/null
    reniced=$(printf "%s\n" "$renice_list" | wc -l)
    logit "reniced=$reniced cpu_usage=$cpu_usage threshold=$MAX_CPU"
else
    echo "$(c 2)CPU usage OK ($cpu_usage%% <= $MAX_CPU%%)$(r)"
fi
EOF
    sudo chmod +x "$cursor_guard"

    # --- kill-cursor ------------------------------------------
    local kill_cursor="/usr/local/bin/kill-cursor"
    if sudo test -f "$kill_cursor" 2>/dev/null && ! sudo grep -q "system_resource_protection_script" "$kill_cursor" 2>/dev/null; then
        print_info "Backing up existing $kill_cursor to ${kill_cursor}.srps-backup"
        sudo cp "$kill_cursor" "${kill_cursor}.srps-backup"
    fi

    print_info "Installing kill-cursor (emergency kill)..."
    sudo tee "$kill_cursor" >/dev/null << 'EOF'
#!/usr/bin/env bash
# Generated by system_resource_protection_script
if command -v tput >/dev/null 2>&1; then
  c(){ tput setaf "$1"; }; b(){ tput bold; }; r(){ tput sgr0; }
else
  c(){ printf '\033[0;3%sm' "$1"; }; b(){ printf '\033[1m'; }; r(){ printf '\033[0m'; }
fi

if [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
kill-cursor - force kill cursor/node/electron processes
USAGE
  exit 0
fi

logit() {
  if command -v logger >/dev/null 2>&1; then logger -t srps-kill-cursor "$*"; else echo "$*" >&2; fi
}

echo "$(b)$(c 1)Killing Cursor / related node/electron processes...$(r)"
targets=("cursor" "node.*cursor" "electron.*cursor")
for sig in TERM KILL; do
  for t in "${targets[@]}"; do
    pkill -$sig -f "$t" 2>/dev/null || true
  done
  [ "$sig" = "TERM" ] && sleep 1
done
logit "signal_sequence=TERM,KILL targets=${targets[*]}"
echo "$(c 2)Done. If anything remains, try rerunning with root privileges.$(r)"
EOF
    sudo chmod +x "$kill_cursor"

    # --- srps-doctor -----------------------------------------
    local srps_doctor="/usr/local/bin/srps-doctor"
    sudo tee "$srps_doctor" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
section() { echo -e "\n$(color "1;34" "==>") $*"; }

if [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
srps-doctor - quick diagnostics
Env:
  SRPS_JSON=1  Output JSON summary
USAGE
  exit 0
fi

if [ "${SRPS_JSON:-0}" = "1" ]; then
  j_active(){ systemctl is-active --quiet "$1" 2>/dev/null && echo true || echo false; }
  j_file(){ [ -f "$1" ] && echo true || echo false; }
  an_errs="[]"
  if command -v journalctl >/dev/null 2>&1; then
    mapfile -t ERR_LINES < <(journalctl -u ananicy-cpp -n 50 --no-pager 2>/dev/null | grep -i -E 'error|invalid' | head -5)
    if [ ${#ERR_LINES[@]} -gt 0 ]; then
      an_errs="["
      first=1
      for line in "${ERR_LINES[@]}"; do
        esc=$(printf '%s' "$line" | sed 's/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g')
        [ $first -eq 1 ] || an_errs+=","
        an_errs+="\"$esc\""
        first=0
      done
      an_errs+="]"
    fi
  fi
  cat <<JSON
{
  "sudo_cached": $( { sudo -n true 2>/dev/null && echo true; } || echo false ),
  "services": {
    "systemd_oomd": $(j_active systemd-oomd.service),
    "gamemoded": $(j_active gamemoded.service),
    "ananicy_cpp": $(j_active ananicy-cpp),
    "earlyoom": $(j_active earlyoom)
  },
  "ananicy_errors": $an_errs,
  "user_systemd": $( { systemctl --user show-environment >/dev/null 2>&1 && echo true; } || echo false ),
  "configs": {
    "earlyoom": $(j_file /etc/default/earlyoom),
    "ananicy_rules": $(j_file /etc/ananicy.d/00-default/99-system-resource-protection.rules),
    "sysctl": $(j_file /etc/sysctl.d/99-system-resource-protection.conf)
  },
  "etc_world_writable": $( { stat -c "%a" /etc 2>/dev/null | grep -qE '^[0-7]6[0-7]'; } && echo true || echo false ),
  "in_docker_group": $( { id -nG "$USER" | grep -qw docker; } && echo true || echo false )
}
JSON
  exit 0
fi

section "sudo freshness"
if sudo -n true 2>/dev/null; then
  echo "sudo: ok (cached or passwordless)"
else
  echo "sudo: needs password (run sudo -v)"
fi

section "conflicts & services"
status_line() {
  local svc="$1" label="$2" warn="$3"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo "$(color 32 "✔") $label: active"
  else
    prefix=$( [ -n "$warn" ] && echo "$(color 33 "⚠")" || echo "$(color 31 "✘")" )
    echo "$prefix $label: inactive"
  fi
}

status_line systemd-oomd.service "systemd-oomd" warn
status_line gamemoded.service "gamemoded" warn
status_line ananicy-cpp "ananicy-cpp" warn
status_line earlyoom "earlyoom" warn

section "systemd user session"
if systemctl --user show-environment >/dev/null 2>&1; then
  echo "systemd --user: available"
else
  echo "⚠ systemd --user not reachable (limited* aliases may fail)"
fi

section "config files"
if [ -f /etc/default/earlyoom ]; then echo "earlyoom config present"; else echo "⚠ /etc/default/earlyoom missing"; fi
if [ -f /etc/ananicy.d/00-default/99-system-resource-protection.rules ]; then echo "SRPS ananicy rules present"; else echo "⚠ SRPS ananicy rules missing"; fi
if [ -f /etc/sysctl.d/99-system-resource-protection.conf ]; then echo "sysctl config present"; else echo "sysctl config missing"; fi

section "ananicy recent errors (last 50 lines)"
if command -v journalctl >/dev/null 2>&1; then
  errs=$(journalctl -u ananicy-cpp -n 50 --no-pager 2>/dev/null | grep -i -E 'error|invalid' | head -5)
  if [ -z "$errs" ]; then
    echo "none seen"
  else
    echo "$errs"
  fi
else
  echo "journalctl not available"
fi

section "permissions & groups"
if stat -c "%a" /etc 2>/dev/null | grep -qE '^[0-7]6[0-7]'; then
  echo "⚠ /etc has group/world write bits; tighten permissions"
else
  echo "/etc perms: ok"
fi
if id -nG "$USER" | grep -qw docker; then
  echo "⚠ user in docker group (container cgroups can behave differently)"
else
  echo "docker group: not a member"
fi

section "recent errors"
journalctl -p err -b -n 20 --no-pager 2>/dev/null || true

section "recommendations"
echo "- Disable one of systemd-oomd/earlyoom if both active"
echo "- Disable gamemoded if scheduling conflicts appear"
echo "- Ensure systemd user session is running for limited* aliases"
EOF
    sudo chmod +x "$srps_doctor"

    # --- srps-reload-rules -----------------------------------
    local srps_reload="/usr/local/bin/srps-reload-rules"
    sudo tee "$srps_reload" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
srps-reload-rules - restart ananicy-cpp and report rule count
Env:
  SRPS_JSON=1  Emit JSON summary
USAGE
  exit 0
fi
if [ "${SRPS_JSON:-0}" = "1" ]; then
  if command -v ananicy-cpp >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    sudo systemctl daemon-reload
    ok=$(sudo systemctl restart ananicy-cpp >/dev/null 2>&1 && echo true || echo false)
    sleep 2
    count=$(sudo journalctl -u ananicy-cpp -n 20 --no-pager 2>/dev/null | grep -oP 'Worker initialized with \K[0-9]+' | head -1 || echo '?')
    printf '{"restarted":%s,"rules":"%s"}\n' "$ok" "$count"
  else
    printf '{"restarted":false,"error":"ananicy/systemctl missing"}\n'
    exit 1
  fi
  exit 0
fi

echo "Reloading ananicy-cpp rules..."
if [ ! -d /etc/ananicy.d ]; then
  echo "No /etc/ananicy.d found" >&2
  exit 1
fi

if command -v ananicy-cpp >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  sudo systemctl daemon-reload
  sudo systemctl restart ananicy-cpp
  sleep 2
  count=$(sudo journalctl -u ananicy-cpp -n 20 --no-pager 2>/dev/null | grep -oP 'Worker initialized with \K[0-9]+' | head -1 || echo '?')
  echo "$(tput bold 2>/dev/null || true)ananicy-cpp restarted$(tput sgr0 2>/dev/null || true); rules loaded: ${count}"
else
  echo "ananicy-cpp/systemctl not available" >&2
  exit 1
fi
EOF
    sudo chmod +x "$srps_reload"

    # --- srps-pull-rules -------------------------------------
    if [ "$ENABLE_RULE_PULL" -eq 1 ]; then
        local srps_pull="/usr/local/bin/srps-pull-rules"
        sudo tee "$srps_pull" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
if command -v tput >/dev/null 2>&1; then
  c(){ tput setaf "$1"; }; b(){ tput bold; }; r(){ tput sgr0; }
else
  c(){ printf '\033[0;3%sm' "$1"; }; b(){ printf '\033[1m'; }; r(){ printf '\033[0m'; }
fi

if [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
srps-pull-rules - refresh ananicy community rules with backup
USAGE
  exit 0
fi

echo "$(b)$(c 6)Fetching latest CachyOS ananicy rules...$(r)"
git clone -q --depth 1 https://github.com/CachyOS/ananicy-rules.git "$tmpdir/ananicy-rules"
backup="/etc/ananicy.d.backup-$(date +%Y%m%d-%H%M%S)-pull"
echo "$(c 3)Backup -> $backup$(r)"
sudo cp -a /etc/ananicy.d "$backup" || true
sudo rm -rf /etc/ananicy.d
sudo mkdir -p /etc/ananicy.d
sudo cp -a "$tmpdir/ananicy-rules"/* /etc/ananicy.d/
if [ -d "$backup/10-local" ]; then
  sudo cp -a "$backup/10-local" /etc/ananicy.d/ || true
fi
echo "$(c 2)Rules refreshed$(r) | backup: $backup"
EOF
        sudo chmod +x "$srps_pull"
    fi

        # --- srps-report (HTML snapshot) -------------------------
    if [ "$ENABLE_HTML_REPORT" -eq 1 ]; then
        local srps_report="/usr/local/bin/srps-report"
        sudo tee "$srps_report" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
out="/tmp/srps-report.html"
load=$(uptime)
mem=$(free -h)
topcpu=$(ps aux --sort=-%cpu | head -5)
topmem=$(ps aux --sort=-%mem | head -5)
status=$(systemctl is-active ananicy-cpp 2>/dev/null || true)
status2=$(systemctl is-active earlyoom 2>/dev/null || true)

if [ "${1:-}" = "--help" ]; then
  cat <<'USAGE'
srps-report - write HTML snapshot to /tmp/srps-report.html
USAGE
  exit 0
fi

cat > "$out" <<HTML
<html><head><meta charset="utf-8"><title>SRPS Snapshot</title></head><body>
<h1 style="font-family: sans-serif; color:#4c6ef5;">SRPS Snapshot</h1>
<h2>System</h2><pre>$load</pre>
<h2>Memory</h2><pre>$mem</pre>
<h2>Services</h2><pre>ananicy-cpp: $status
earlyoom: $status2</pre>
<h2>Top CPU</h2><pre>$topcpu</pre>
<h2>Top MEM</h2><pre>$topmem</pre>
</body></html>
HTML
echo "Wrote $out"
EOF
        sudo chmod +x "$srps_report"
    fi

    # --- bash completion --------------------------------------
    local completion_file="/etc/bash_completion.d/srps"
    sudo tee "$completion_file" >/dev/null << 'EOF'
_srps_install_complete() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=( $(compgen -W "--install --uninstall --plan -y --yes" -- "$cur") )
}
complete -F _srps_install_complete install.sh
complete -W "srps-doctor srps-reload-rules srps-pull-rules srps-report sysmon check-throttled cursor-guard kill-cursor" srps-doctor srps-reload-rules srps-pull-rules srps-report sysmon check-throttled cursor-guard kill-cursor
EOF

    print_info "Bash completions installed at $completion_file"

    # --- WSL helper note -------------------------------------
    if [ "$IS_WSL" -eq 1 ]; then
        local wsl_helper="/usr/local/share/srps-wsl-earlyoom.ps1"
        sudo tee "$wsl_helper" >/dev/null << 'EOF'
# Run from an elevated PowerShell prompt to kick earlyoom inside WSL
$distro = wsl.exe -l -q | Select-Object -First 1
$cmd = "wsl.exe -d $distro sh -c 'sudo systemctl start earlyoom'"
Start-Process -WindowStyle Hidden -Verb RunAs -FilePath powershell -ArgumentList $cmd
EOF
        print_info "WSL PowerShell helper written to $wsl_helper (run elevated in Windows to start earlyoom)"
    fi

    print_success "Monitoring and helper tools installed (sysmon, check-throttled, cursor-guard, kill-cursor, srps-doctor, srps-reload-rules${ENABLE_RULE_PULL:+, srps-pull-rules}${ENABLE_HTML_REPORT:+, srps-report})"
}
# --------------- Shell Aliases / Environment -----------------
detect_shell_rc() {
    # 1. Trust ZDOTDIR if set (explicit zsh setup)
    if [ -n "${ZDOTDIR:-}" ] && [ -f "${ZDOTDIR}/.zshrc" ]; then
        SHELL_RC="${ZDOTDIR}/.zshrc"
        return
    fi

    # 2. Check current user shell
    local shell_name
    shell_name=$(basename "${SHELL:-bash}")

    if [ "$shell_name" = "zsh" ] && [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
        return
    elif [ "$shell_name" = "bash" ] && [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
        return
    fi

    # 3. Fallback heuristics
    if [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
    else
        SHELL_RC="$HOME/.bashrc"
    fi
}

configure_shell_aliases() {
    if [ "$ENABLE_SHELL_ALIASES" -ne 1 ]; then
        print_warning "Shell alias configuration skipped by configuration."
        return
    fi

    detect_shell_rc
    print_info "Using shell rc file: $SHELL_RC"

    mkdir -p "$(dirname "$SHELL_RC")"
    touch "$SHELL_RC"

    if grep -q ">>> system_resource_protection_script >>>" "$SHELL_RC"; then
        print_success "Shell aliases already present in $SHELL_RC"
        return
    fi

    if command -v systemd-run >/dev/null 2>&1; then
        if command -v systemctl >/dev/null 2>&1 && ! systemctl --user show-environment >/dev/null 2>&1; then
            print_warning "systemd-run is available but the user systemd instance looks inactive; 'limited*' aliases may show bus errors until a user systemd session is running (e.g., login via a systemd-managed session or enable lingering)."
        fi
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        print_info "[plan mode] Would append SRPS aliases to $SHELL_RC"
        return
    fi

    print_info "Adding resource-limited helpers and aliases to $SHELL_RC"
    cat >> "$SHELL_RC" << 'EOF'

# >>> system_resource_protection_script >>>
# Resource-limited command runners using systemd user scopes (if available)
if command -v systemd-run >/dev/null 2>&1; then
  alias limited="systemd-run --user --scope -p CPUQuota=50% --"
  alias limited-mem="systemd-run --user --scope -p MemoryMax=8G --"
  alias cargo-limited="systemd-run --user --scope -p CPUQuota=75% -p MemoryMax=50G cargo"
  alias make-limited="systemd-run --user --scope -p CPUQuota=75% make -j$(nproc)"
  alias node-limited="systemd-run --user --scope -p CPUQuota=75% -p MemoryMax=8G node"
fi

# Monitoring helpers (only if helpers are available)
if command -v sysmon >/dev/null 2>&1; then
  alias sys='sysmon'
fi
if command -v check-throttled >/dev/null 2>&1; then
  alias throttled='check-throttled'
fi

# Rust / Cargo env
export TMPDIR=/tmp
export CARGO_TARGET_DIR=/tmp/cargo-target
# <<< system_resource_protection_script <<<
EOF

    print_success "Shell aliases added to $SHELL_RC"
}

# --------------- Final Summary (Install) ---------------------
show_final_summary_install() {
    echo -e "\n${CYAN}${BOLD}Service status summary:${NC}"

    if [ "$HAS_SYSTEMD" -eq 1 ]; then
        local ananicy_status earlyoom_status
        if systemctl is-active --quiet ananicy-cpp; then
            ananicy_status="${GREEN}active${NC}"
        else
            ananicy_status="${RED}inactive${NC}"
        fi

        if systemctl is-active --quiet earlyoom; then
            earlyoom_status="${GREEN}active${NC}"
        else
            earlyoom_status="${RED}inactive${NC}"
        fi

        echo -e "  ananicy-cpp:   $ananicy_status"
        echo -e "  earlyoom:      $earlyoom_status"
    else
        echo -e "  ${YELLOW}Systemd not detected; service status unknown.${NC}"
    fi

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗"
    echo -e   "║                  ✅ SETUP COMPLETE ✅                      ║"
    echo -e   "╚════════════════════════════════════════════════════════════╝${NC}"

    echo -e "\n${YELLOW}${BOLD}New commands:${NC}"
    echo -e "  ${CYAN}sysmon${NC}          - Live system resource monitor"
    echo -e "  ${CYAN}check-throttled${NC} - Show currently throttled processes"
    echo -e "  ${CYAN}cursor-guard${NC}    - Guard against runaway Node/Cursor"
    echo -e "  ${CYAN}kill-cursor${NC}     - Hard-kill Cursor/Node/Electron"
    echo -e "  ${CYAN}limited <cmd>${NC}   - Run any command with 50% CPU cap"
    echo -e "  ${CYAN}limited-mem <cmd>${NC}- Run any command with 8G mem cap"
    echo -e "  ${CYAN}cargo-limited${NC}   - Run cargo with CPU/RAM limits"
    echo -e "  ${CYAN}make-limited${NC}    - Run make with CPU limits"
    echo -e "  ${CYAN}node-limited${NC}    - Run node with CPU/RAM limits"

    echo -e "\n${YELLOW}${BOLD}Protection is biased towards:${NC}"
    echo -e "  • Compilers / build systems (Rust, C/C++, Java, Node)"
    echo -e "  • Browsers and Electron apps (Chrome, Firefox, Slack, Discord, etc.)"
    echo -e "  • Cursor, VS Code, and heavy IDE tooling"
    echo -e "  • Containers / virtualization (Docker, QEMU, etc.)"

    echo -e "\n${MAGENTA}${BOLD}Final step:${NC}"
    echo -e "  Run ${CYAN}source \"$SHELL_RC\"${NC} or open a new shell to use the new aliases.\n"
}

sample_service_logs() {
    if [ "$DRY_RUN" -eq 1 ]; then
        return
    fi
    if [ "$HAS_SYSTEMD" -eq 1 ]; then
        print_info "Recent ananicy-cpp log tail:"
        sudo journalctl -u ananicy-cpp -n 10 --no-pager 2>/dev/null || true
        print_info "Recent earlyoom log tail:"
        sudo journalctl -u earlyoom -n 10 --no-pager 2>/dev/null || true
    fi
}

# --------------- Uninstall Logic -----------------------------
uninstall_shell_snippets() {
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ] && grep -q ">>> system_resource_protection_script >>>" "$rc"; then
            print_info "Removing SRPS shell block from $rc"
            sed -i '/^# >>> system_resource_protection_script >>>$/,/^# <<< system_resource_protection_script <<</d' "$rc"
            print_success "Removed SRPS shell aliases from $rc"
        fi
    done
}

uninstall_monitoring_tools() {
    print_step "[1/4] Removing monitoring and helper utilities"

    for bin in /usr/local/bin/sysmon /usr/local/bin/check-throttled /usr/local/bin/cursor-guard /usr/local/bin/kill-cursor /usr/local/bin/srps-doctor /usr/local/bin/srps-reload-rules /usr/local/bin/srps-pull-rules /usr/local/bin/srps-report; do
        if sudo test -f "$bin" 2>/dev/null; then
            if sudo grep -q "system_resource_protection_script" "$bin" 2>/dev/null; then
                print_info "Removing $bin"
                sudo rm -f "$bin"
                print_success "Removed $bin"
            else
                print_warning "$bin exists but does not look SRPS-managed; leaving in place."
            fi
        fi
        if sudo test -f "${bin}.srps-backup" 2>/dev/null; then
            print_info "Restoring backup ${bin}.srps-backup"
            sudo mv "${bin}.srps-backup" "$bin"
            sudo chmod +x "$bin" || true
            print_success "Restored ${bin} from backup"
        fi
    done

    if sudo test -f /etc/bash_completion.d/srps 2>/dev/null; then
        print_info "Removing bash completion file /etc/bash_completion.d/srps"
        sudo rm -f /etc/bash_completion.d/srps
    fi

    if sudo test -f /usr/local/share/srps-wsl-earlyoom.ps1 2>/dev/null; then
        print_info "Removing WSL helper script /usr/local/share/srps-wsl-earlyoom.ps1"
        sudo rm -f /usr/local/share/srps-wsl-earlyoom.ps1
    fi
}

uninstall_ananicy_config() {
    print_step "[2/4] Reverting Ananicy configuration (where possible)"

    if [ ! -d /etc/ananicy.d ]; then
        print_info "/etc/ananicy.d does not exist; nothing to revert."
        return
    fi

    local backup_file="/etc/ananicy.d/.srps_backup"
    if sudo test -f "$backup_file" 2>/dev/null; then
        local backup_dir
        backup_dir="$(sudo cat "$backup_file" 2>/dev/null | head -n1 || echo "")"
        if [ -n "$backup_dir" ] && sudo test -d "$backup_dir" 2>/dev/null; then
            print_info "Restoring Ananicy rules from $backup_dir"
            sudo rm -rf /etc/ananicy.d
            sudo mv "$backup_dir" /etc/ananicy.d
            print_success "Restored /etc/ananicy.d from backup"
        else
            print_warning "Recorded Ananicy backup directory is invalid; removing SRPS rules only."
            sudo rm -f /etc/ananicy.d/00-default/99-system-resource-protection.rules || true
        fi
        sudo rm -f "$backup_file"
    else
        print_info "No SRPS backup file found; removing SRPS rules file if present."
        sudo rm -f /etc/ananicy.d/00-default/99-system-resource-protection.rules || true
    fi

    if [ "$HAS_SYSTEMD" -eq 1 ] && systemctl is-active --quiet ananicy-cpp; then
        print_info "Reloading Ananicy service after config changes..."
        sudo systemctl restart ananicy-cpp || print_warning "Failed to restart ananicy-cpp; check status manually."
    fi
}

uninstall_earlyoom_and_sysctl() {
    print_step "[3/4] Reverting EarlyOOM and sysctl configuration"

    # EarlyOOM config
    if sudo test -f /etc/default/earlyoom.srps-backup 2>/dev/null; then
        print_info "Restoring /etc/default/earlyoom from SRPS backup"
        sudo mv /etc/default/earlyoom.srps-backup /etc/default/earlyoom
        print_success "Restored previous EarlyOOM configuration"
    elif sudo test -f /etc/default/earlyoom 2>/dev/null && sudo grep -q "system_resource_protection_script" /etc/default/earlyoom 2>/dev/null; then
        print_info "Removing SRPS-generated /etc/default/earlyoom (no backup found)"
        sudo rm -f /etc/default/earlyoom
        print_success "Removed SRPS EarlyOOM configuration"
    else
        print_info "No SRPS-managed EarlyOOM configuration detected."
    fi

    # Sysctl config
    local sysctl_file="/etc/sysctl.d/99-system-resource-protection.conf"
    if sudo test -f "${sysctl_file}.srps-backup" 2>/dev/null; then
        print_info "Restoring $sysctl_file from backup"
        sudo mv "${sysctl_file}.srps-backup" "$sysctl_file"
        print_success "Restored sysctl config from backup"
    elif sudo test -f "$sysctl_file" 2>/dev/null; then
        print_info "Removing SRPS sysctl file $sysctl_file"
        sudo rm -f "$sysctl_file"
        print_success "Removed SRPS sysctl configuration"
    else
        print_info "No SRPS-managed sysctl config detected."
    fi

    if command -v sysctl >/dev/null 2>&1; then
        print_info "Reloading kernel sysctl configuration..."
        sudo sysctl --system >/dev/null 2>&1 || print_warning "sysctl --system reported errors; review sysctl configuration if needed."
    fi
}

uninstall_systemd_limits() {
    print_step "[4/4] Reverting systemd manager limits"

    if [ "$HAS_SYSTEMD" -ne 1 ]; then
        print_info "No systemd detected; nothing to revert."
        return
    fi

    local conf_file="/etc/systemd/system.conf.d/10-system-resource-protection.conf"

    if sudo test -f "${conf_file}.srps-backup" 2>/dev/null; then
        print_info "Restoring $conf_file from backup"
        sudo mv "${conf_file}.srps-backup" "$conf_file"
        print_success "Restored systemd manager config from backup"
        sudo systemctl daemon-reload
    elif sudo test -f "$conf_file" 2>/dev/null && sudo grep -q "system_resource_protection_script" "$conf_file" 2>/dev/null; then
        print_info "Removing SRPS systemd manager config $conf_file"
        sudo rm -f "$conf_file"
        sudo systemctl daemon-reload
        print_success "Removed SRPS systemd manager config"
    else
        print_info "No SRPS-managed systemd manager config detected."
    fi
}

show_final_summary_uninstall() {
    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗"
    echo -e   "║               ✅ UNINSTALL COMPLETE ✅                     ║"
    echo -e   "╚════════════════════════════════════════════════════════════╝${NC}"

    echo -e "\n${YELLOW}${BOLD}Notes:${NC}"
    echo -e "  • Packages (ananicy-cpp, earlyoom) were NOT removed; only config and helpers."
    echo -e "  • If you want them gone entirely:"
    echo -e "      ${CYAN}sudo apt-get remove --purge earlyoom${NC}"
    echo -e "      ${CYAN}sudo rm /usr/local/bin/ananicy-cpp  # if built from source${NC}"
    echo -e "  • Restart your shell to ensure aliases/functions are gone.\n"
}

# --------------- Main Flows ----------------------------------
main_install() {
    print_banner "install"
    load_config
    detect_system
    detect_power_profile

    print_info "Environment:"
    local systemd_str="no" wsl_str="no"
    if [ "$HAS_SYSTEMD" -eq 1 ]; then
        systemd_str="yes"
    fi
    if [ "$IS_WSL" -eq 1 ]; then
        wsl_str="yes"
    fi

    echo -e "  Systemd:  $systemd_str"
    echo -e "  WSL:      $wsl_str"
    echo -e "  Package:  apt-get\n"

    install_ananicy_cpp
    configure_ananicy_rules
    install_and_configure_earlyoom
    configure_sysctl
    configure_wsl_limits
    create_monitoring_and_tools
    configure_shell_aliases
    sample_service_logs
    show_final_summary_install
}

main_uninstall() {
    print_banner "uninstall"
    load_config
    detect_system

    if [ "$FORCE" != "yes" ] && [ -t 0 ]; then
        echo -ne "${YELLOW}This will remove SRPS configuration, helpers, and restore backups where possible.${NC}\n"
        read -rp "$(echo -e "${YELLOW}Proceed? [y/N]: ${NC}")" reply
        case "$reply" in
            y|Y|yes|YES) ;;
            *) print_warning "Uninstall aborted by user."; exit 0 ;;
        esac
    fi

    uninstall_monitoring_tools
    uninstall_ananicy_config
    uninstall_earlyoom_and_sysctl
    uninstall_systemd_limits
    uninstall_shell_snippets
    show_final_summary_uninstall
}

# --------------- Entry Point ---------------------------------
parse_args "$@"

if [ "$ACTION" = "install" ] || [ "$ACTION" = "plan" ]; then
    main_install
else
    main_uninstall
fi
