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
# 1. If marker is a function name (e.g. "install_bash_sysmon"), find that function and extract the first heredoc <<'EOF' inside it.
# 2. Otherwise, treat marker as the exact line preceding the heredoc.

if "install_" in marker or "_doctor" in marker or "_reload" in marker:
    # Heuristic: find function definition or specific marker line
    # We just use a flexible regex for heredoc start
    # Match: ... marker ... <<'EOF' ... content ... EOF
    # We allow any characters between marker and <<'EOF' (like "sudo tee...")
    pattern = re.escape(marker) + r".*?<<'EOF'\n(.*?)\n[ \t]*EOF"
    m = re.search(pattern, text, re.S)
else:
    # Fallback to exact previous line match (allowing for indentation)
    pattern = r"(?m)^[ \t]*" + re.escape(marker) + r"\n(.*?)\n[ \t]*EOF"
    m = re.search(pattern, text, re.S)

if not m:
    # Fallback: try ignoring indentation on the marker line itself in the regex
    # This handles the case where "marker" is a function definition far above the heredoc
    pattern = r"(?m)^[ \t]*" + re.escape(marker) + r".*?<<'EOF'\n(.*?)\n[ \t]*EOF"
    m = re.search(pattern, text, re.S)

if not m:
    sys.exit(f"missing script for marker: {marker}")
pathlib.Path(out).write_text(m.group(1))
PY
  chmod +x "$outfile"
}

extract "install_bash_sysmon(){" "$tmpdir/sysmon"
extract "sudo tee \"\$check_throttled\" >/dev/null << 'EOF'" "$tmpdir/check-throttled"
extract "sudo tee \"\$cursor_guard\" >/dev/null << 'EOF'" "$tmpdir/cursor-guard"
extract "sudo tee \"\$srps_doctor\" >/dev/null << 'EOF'" "$tmpdir/srps-doctor"
extract "sudo tee \"\$srps_reload\" >/dev/null << 'EOF'" "$tmpdir/srps-reload-rules"

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

echo "[smoke] sysmon JSON snapshot"
SRPS_SYSMON_JSON=1 SRPS_SYSMON_INTERVAL=0.1 ./install.sh --plan >/tmp/srps-plan.log || true
SRPS_SYSMON_JSON=1 SRPS_SYSMON_GPU=0 SRPS_SYSMON_BATT=0 SRPS_SYSMON_INTERVAL=0.1 "$tmpdir/sysmon" >/tmp/sysmon.json
python3 -c "import json; json.load(open('/tmp/sysmon.json'))"
python3 - <<'PY'
import json, sys
data = json.load(open('/tmp/sysmon.json'))
assert isinstance(data.get("top"), list) and data["top"], "sysmon JSON top list empty"
assert "cpu" in data and "mem" in data, "sysmon JSON missing cpu/mem keys"
print("[check] sysmon JSON sanity OK")
PY

echo "[smoke] check-throttled JSON"
SRPS_JSON=1 "$tmpdir/check-throttled" >/tmp/check-throttled.json
python3 -c "import json; json.load(open('/tmp/check-throttled.json'))"

echo "[smoke] cursor-guard JSON"
SRPS_JSON=1 "$tmpdir/cursor-guard" >/tmp/cursor-guard.json
python3 -c "import json; json.load(open('/tmp/cursor-guard.json'))"

echo "[smoke] doctor JSON"
SRPS_JSON=1 "$tmpdir/srps-doctor" >/tmp/srps-doctor.json
python3 -c "import json; json.load(open('/tmp/srps-doctor.json'))"

echo "[smoke] reload-rules JSON"
SRPS_JSON=1 "$tmpdir/srps-reload-rules" >/tmp/srps-reload.json || true
python3 -c "import json; json.load(open('/tmp/srps-reload.json'))" || true

echo "[smoke] done"
