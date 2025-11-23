#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

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
SRPS_SYSMON_JSON=1 SRPS_SYSMON_INTERVAL=0.1 /usr/local/bin/sysmon >/tmp/sysmon.json
python3 -c "import json; json.load(open('/tmp/sysmon.json'))"

echo "[smoke] check-throttled JSON"
SRPS_JSON=1 /usr/local/bin/check-throttled >/tmp/check-throttled.json
python3 -c "import json; json.load(open('/tmp/check-throttled.json'))"

echo "[smoke] cursor-guard JSON"
SRPS_JSON=1 /usr/local/bin/cursor-guard >/tmp/cursor-guard.json
python3 -c "import json; json.load(open('/tmp/cursor-guard.json'))"

echo "[smoke] doctor JSON"
SRPS_JSON=1 /usr/local/bin/srps-doctor >/tmp/srps-doctor.json
python3 -c "import json; json.load(open('/tmp/srps-doctor.json'))"

echo "[smoke] reload-rules JSON"
SRPS_JSON=1 /usr/local/bin/srps-reload-rules >/tmp/srps-reload.json || true
python3 -c "import json; json.load(open('/tmp/srps-reload.json'))" || true

echo "[smoke] done"
