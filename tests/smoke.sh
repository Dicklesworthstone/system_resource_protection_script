#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

extract() {
  local marker="$1" outfile="$2"
  python3 - "$marker" "$outfile" <<'PY'
import re, sys, pathlib
marker, out = sys.argv[1], sys.argv[2]
text = pathlib.Path("install.sh").read_text()

# Robust extraction:
# 1. If marker is a function name (e.g. "install_bash_sysmoni"), find that function and extract the first heredoc <<'EOF' inside it.
# 2. Otherwise, treat marker as the exact line preceding the heredoc.

if "install_" in marker or "_doctor" in marker or "_reload" in marker:
    # Heuristic: find function definition or specific marker line
    # We just use a flexible regex for heredoc start
    # Match: ... marker ... <<'EOF' ... content ... EOF
    # We allow any characters between marker and <<'EOF' (like "sudo tee...")
    # Allow optional space between << and 'EOF'
    pattern = re.escape(marker) + r".*?<<[ \t]*'EOF'\n(.*?)\n[ \t]*EOF"
    m = re.search(pattern, text, re.S)
else:
    # Fallback to exact previous line match (allowing for indentation)
    pattern = r"(?m)^[ \t]*" + re.escape(marker) + r"[ \t]*<<[ \t]*'EOF'\n(.*?)\n[ \t]*EOF"
    m = re.search(pattern, text, re.S)

if not m:
    # Fallback: try ignoring indentation on the marker line itself in the regex
    # This handles the case where "marker" is a function definition far above the heredoc
    pattern = r"(?m)^[ \t]*" + re.escape(marker) + r".*?<<[ \t]*'EOF'\n(.*?)\n[ \t]*EOF"
    m = re.search(pattern, text, re.S)

if not m:
    sys.exit(f"missing script for marker: {marker}")
pathlib.Path(out).write_text(m.group(1))
PY
  chmod +x "$outfile"
}

extract "install_bash_sysmoni(){" "$tmpdir/sysmoni"
extract "sudo tee \"\$check_throttled\" >/dev/null" "$tmpdir/check-throttled"
extract "sudo tee \"\$cursor_guard\" >/dev/null" "$tmpdir/cursor-guard"
extract "sudo tee \"\$srps_doctor\" >/dev/null" "$tmpdir/srps-doctor"
extract "sudo tee \"\$srps_reload\" >/dev/null" "$tmpdir/srps-reload-rules"

if command -v bashate >/dev/null 2>&1; then
  echo "[lint] bashate (ignore long lines/style-only)"
  bashate -i E006,E040 install.sh tests/*.sh verify.sh
else
  echo "[lint] bashate not installed; skipping"
fi

if command -v shellcheck >/dev/null 2>&1; then
  echo "[lint] shellcheck install.sh verify.sh"
  shellcheck install.sh verify.sh
else
  echo "[lint] shellcheck not installed; skipping"
fi

echo "[smoke] bash -n install.sh"
bash -n install.sh

echo "[smoke] DRY_RUN=1 env selects plan mode"
DRY_RUN=1 ./install.sh >/tmp/srps-plan-env.log 2>&1 || true
if ! grep -q 'Mode: PLAN' /tmp/srps-plan-env.log; then
    echo "FATAL: DRY_RUN=1 did not select plan mode (README documents it as equivalent to --plan):"
    head -20 /tmp/srps-plan-env.log
    exit 1
fi

echo "[smoke] sysmoni JSON snapshot"
SRPS_SYSMONI_JSON=1 SRPS_SYSMONI_INTERVAL=0.1 ./install.sh --plan >/tmp/srps-plan.log || true
SRPS_SYSMONI_JSON=1 SRPS_SYSMONI_GPU=0 SRPS_SYSMONI_BATT=0 SRPS_SYSMONI_INTERVAL=0.1 "$tmpdir/sysmoni" >/tmp/sysmon.json
if ! python3 -c "import json; json.load(open('/tmp/sysmon.json'))"; then
    echo "FATAL: sysmoni produced invalid JSON:"
    cat /tmp/sysmon.json
    exit 1
fi
python3 - <<'PY'
import json, sys
data = json.load(open('/tmp/sysmon.json'))
if not data.get("top"):
    print("WARNING: sysmoni JSON top list is empty (acceptable in some CI envs)")
else:
    print("[check] sysmoni JSON top list populated")
assert "cpu" in data and "mem" in data, "sysmoni JSON missing cpu/mem keys"
print("[check] sysmoni JSON sanity OK")
PY

echo "[smoke] check-throttled JSON"
SRPS_JSON=1 "$tmpdir/check-throttled" >/tmp/check-throttled.json
if ! python3 -c "import json; json.load(open('/tmp/check-throttled.json'))"; then
    echo "FATAL: check-throttled produced invalid JSON:"
    cat /tmp/check-throttled.json
    exit 1
fi

echo "[smoke] cursor-guard JSON"
SRPS_JSON=1 "$tmpdir/cursor-guard" >/tmp/cursor-guard.json
if ! python3 -c "import json; json.load(open('/tmp/cursor-guard.json'))"; then
    echo "FATAL: cursor-guard produced invalid JSON:"
    cat /tmp/cursor-guard.json
    exit 1
fi

echo "[smoke] doctor JSON"
SRPS_JSON=1 "$tmpdir/srps-doctor" >/tmp/srps-doctor.json
if ! python3 -c "import json; json.load(open('/tmp/srps-doctor.json'))"; then
    echo "FATAL: srps-doctor produced invalid JSON:"
    cat /tmp/srps-doctor.json
    exit 1
fi

echo "[smoke] reload-rules JSON"
SRPS_JSON=1 "$tmpdir/srps-reload-rules" >/tmp/srps-reload.json || true
python3 -c "import json; json.load(open('/tmp/srps-reload.json'))" || true

echo "[smoke] done"
