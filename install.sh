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
    cat <<EOF
System Resource Protection Script

Usage:
  install.sh                Install / update protection
  install.sh --install      Same as above
  install.sh --uninstall    Remove protection and restore backups where possible
  install.sh --uninstall -y Non-interactive uninstall
  install.sh --plan         Show what would be changed (dry run)

Examples:
  curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/system_resource_protection_script/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/system_resource_protection_script/main/install.sh | bash -s -- --uninstall
EOF
}

print_banner() {
    local mode="$1"
    if [ -t 1 ]; then
        clear
    fi

    echo -e "${MAGENTA}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    if [ "$mode" = "install" ]; then
        echo "║      SYSTEM RESOURCE PROTECTION SETUP (SRPS)              ║"
        echo "║   Taming runaway dev processes & desktop resource hogs    ║"
    else
        echo "║      SYSTEM RESOURCE PROTECTION UNINSTALLER (SRPS)        ║"
        echo "║        Restoring your system to its previous state        ║"
    fi
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# --------------- Argument Parsing ----------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --install)
            ACTION="install"
            ;;
        --uninstall)
            ACTION="uninstall"
            ;;
        --plan)
            ACTION="plan"
            DRY_RUN=1
            ;;
        -y|--yes)
            FORCE="yes"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# --------------- System Detection ----------------------------
detect_system() {
    if [ "$EUID" -eq 0 ]; then
        die "Don't run this script as root. Run as a regular user with sudo."
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        die "sudo is required. Please install/configure sudo for your user."
    fi

    print_info "Validating sudo credentials..."
    if ! sudo -v; then
        die "Failed to validate sudo privileges."
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

    sudo mkdir -p /etc/ananicy.d/{00-cgroups,00-types,00-default}
    (
        cd /etc/ananicy.d
        print_info "Fetching community Ananicy rules (CachyOS)..."
        if ! retry_cmd "sudo git clone -q --depth 1 https://github.com/CachyOS/ananicy-rules.git temp_rules" 3; then
            print_warning "Failed to clone community rules; proceeding with SRPS custom rules only."
        fi
        if [ -d temp_rules ]; then
            sudo mv temp_rules/* . 2>/dev/null || true
            sudo rm -rf temp_rules
        fi
    )

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
watch -n 1 -c '
printf "\033[1;36m=== System Resource Monitor (SRPS) ===\033[0m\n\n"
printf "\033[1;33mLoad averages:\033[0m %s\n" "$(uptime | awk -F"load average:" "{print \\$2}")"
printf "\033[1;33mMemory:\033[0m %s\n\n" "$(free -h | awk "/Mem/ {printf \\\"%s/%s (%.0f%%)\\\", \\$3, \\$2, \\$3/\\$2*100}")"

printf "\033[1;31m=== Top CPU Hogs ===\033[0m\n"
ps aux | sort -nrk 3,3 | head -5 | awk "{printf \\\"%-20s %5s%% NI:%3s MEM:%5s%%\\\\n\\\", substr(\\$11,1,20), \\$3, \\$18, \\$4}"

printf "\n\033[1;32m=== Throttled (positive nice) processes ===\033[0m\n"
ps -eo pid,ni,comm,%cpu,%mem --sort=-ni | awk "\\$2 > 0 {printf \\\"%-7s NI:%3s CPU:%5s%% MEM:%5s%% %s\\\\n\\\", \\$1, \\$2, \\$4, \\$5, \\$3}" | head -20
'
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
echo -e "\033[1;36m=== Currently Throttled Processes (nice > 0) ===\033[0m"
echo "Format: PROCESS CPU% MEM% NICE IO_CLASS"
echo "---------------------------------------------"

ps -eo pid,comm,%cpu,%mem,ni --sort=-%cpu | awk '$3 > 1.0 && $5 > 0 {print $1, $2, $3, $4, $5}' | while read -r pid cmd cpu mem nice; do
    io_info=$(ionice -p "$pid" 2>/dev/null | grep -oE 'idle|best-effort|rt|prio [0-9]+' | head -1)
    printf "%-20s CPU:%5.1f%% MEM:%5.1f%% NI:%3d IO:%s\n" "$cmd" "$cpu" "$mem" "$nice" "${io_info:-unknown}"
done
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

node_count=$(pgrep -c -f "node(\.exe)?(\s|$)" 2>/dev/null || echo 0)
cpu_usage=$(awk -F'[, ]+' '/Cpu\(s\)/ {print 100-$8; exit}' < <(LC_ALL=C top -bn1) 2>/dev/null || echo 0)

if [ "$node_count" -gt "$MAX_NODE" ] 2>/dev/null; then
    echo "[$(date)] WARNING: $node_count Node processes detected (limit: $MAX_NODE). Killing oldest extras..."
    pids=$(ps -eo pid,lstart,comm | grep -E "node(\.exe)?$" | sort -k2,6 | awk '{print $1}')
    keep=$MAX_NODE
    kill_list=$(echo "$pids" | head -n -"${keep}" 2>/dev/null || true)
    if [ -n "$kill_list" ]; then
        echo "$kill_list" | xargs -r kill -TERM 2>/dev/null
        sleep 1
        echo "$kill_list" | xargs -r kill -KILL 2>/dev/null
    fi
fi

if [ "$cpu_usage" -gt "$MAX_CPU" ] 2>/dev/null; then
    echo "[$(date)] High CPU usage ($cpu_usage%). Renicing top CPU hogs..."
    ps -eo pid,%cpu,ni,comm --sort=-%cpu | head -n 10 | awk '{print $1}' | xargs -r renice 19 -p 2>/dev/null
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
echo -e "\033[1;31mKilling all Cursor and related Node/Electron processes...\033[0m"
pkill -f cursor 2>/dev/null || true
pkill -f "node.*cursor" 2>/dev/null || true
pkill -f "electron.*cursor" 2>/dev/null || true
sleep 1
pkill -9 -f cursor 2>/dev/null || true
pkill -9 -f "node.*cursor" 2>/dev/null || true
pkill -9 -f "electron.*cursor" 2>/dev/null || true
echo -e "\033[1;32mDone. Cursor-related processes terminated (as far as pkill can see).\033[0m"
EOF
    sudo chmod +x "$kill_cursor"

    # --- srps-doctor -----------------------------------------
    local srps_doctor="/usr/local/bin/srps-doctor"
    sudo tee "$srps_doctor" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
section() { echo -e "\n$(color "1;34" "==>") $*"; }

section "sudo freshness"
if sudo -n true 2>/dev/null; then
  echo "sudo: ok (cached or passwordless)"
else
  echo "sudo: needs password (run sudo -v)"
fi

section "conflicts & services"
if systemctl is-active --quiet systemd-oomd.service 2>/dev/null; then
  echo "⚠ systemd-oomd active (can overlap with EarlyOOM)"
else
  echo "systemd-oomd: inactive"
fi
if systemctl is-active --quiet gamemoded.service 2>/dev/null; then
  echo "⚠ gamemoded active (may conflict with ananicy-cpp)"
else
  echo "gamemoded: inactive"
fi
if systemctl is-active --quiet ananicy-cpp 2>/dev/null; then
  echo "ananicy-cpp: active"
else
  echo "ananicy-cpp: inactive"
fi
if systemctl is-active --quiet earlyoom 2>/dev/null; then
  echo "earlyoom: active"
else
  echo "earlyoom: inactive"
fi

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
  echo "ananicy-cpp restarted; rules loaded: ${count}"
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
echo "Fetching latest CachyOS ananicy rules..."
git clone -q --depth 1 https://github.com/CachyOS/ananicy-rules.git "$tmpdir/ananicy-rules"
backup="/etc/ananicy.d.backup-$(date +%Y%m%d-%H%M%S)-pull"
sudo cp -a /etc/ananicy.d "$backup" || true
sudo rm -rf /etc/ananicy.d
sudo mkdir -p /etc/ananicy.d
sudo cp -a "$tmpdir/ananicy-rules"/* /etc/ananicy.d/
if [ -d "$backup/10-local" ]; then
  sudo cp -a "$backup/10-local" /etc/ananicy.d/ || true
fi
echo "Rules refreshed. Backup at $backup"
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
cat > "$out" <<'HTML'
<html><head><meta charset="utf-8"><title>SRPS Snapshot</title></head><body>
<h1>SRPS Snapshot</h1>
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
    if [ -n "${ZDOTDIR:-}" ] && [ -f "${ZDOTDIR}/.zshrc" ]; then
        SHELL_RC="${ZDOTDIR}/.zshrc"
    elif [ -f "$HOME/.zshrc" ]; then
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
if [ "$ACTION" = "install" ] || [ "$ACTION" = "plan" ]; then
    main_install
else
    main_uninstall
fi
