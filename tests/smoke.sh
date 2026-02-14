#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export OPENCLAW_STATE_DIR="/tmp/openclaw-state"
export OPENCLAW_CONFIG_PATH="${OPENCLAW_STATE_DIR}/config/openclaw.ci.json5"

PORT="18789"
TOKEN="ci-$(date +%s)-${RANDOM}${RANDOM}"

export OPENCLAW_GATEWAY_TOKEN="${TOKEN}"
export OPENCLAW_GATEWAY_URL="ws://127.0.0.1:${PORT}"

rm -rf "${OPENCLAW_STATE_DIR}"
mkdir -p "${OPENCLAW_STATE_DIR}/config" "${OPENCLAW_STATE_DIR}/workspace"

# Config/workspace bundle.
cp -a "${ROOT_DIR}/config/." "${OPENCLAW_STATE_DIR}/config/"
cp -a "${ROOT_DIR}/workspace/." "${OPENCLAW_STATE_DIR}/workspace/"
find "${OPENCLAW_STATE_DIR}/workspace" -type f -name 'keepalive_state.json' -delete 2>/dev/null || true

# Minimal secrets-on-host surface (.env is auto-loaded by OpenClaw; keep it empty here).
cat >"${OPENCLAW_STATE_DIR}/.env" <<EOF_ENV
OPENCLAW_GATEWAY_TOKEN=${TOKEN}
EOF_ENV
chmod 600 "${OPENCLAW_STATE_DIR}/.env" || true

# Start gateway in background.
openclaw gateway run \
  --bind loopback \
  --auth token \
  --token "${TOKEN}" \
  --tailscale off \
  --force \
  >/tmp/openclaw-gateway.log 2>&1 &
GW_PID=$!

cleanup() {
  if kill -0 "${GW_PID}" >/dev/null 2>&1; then
    kill "${GW_PID}" >/dev/null 2>&1 || true
    wait "${GW_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Wait for health.
for _ in $(seq 1 30); do
  if "${ROOT_DIR}/scripts/verify.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${TOKEN}"; then
    break
  fi
  sleep 1
done

"${ROOT_DIR}/scripts/apply_cron.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${TOKEN}"

# Assert the desired job exists.
JOBS_JSON="$(openclaw cron list --json --url "${OPENCLAW_GATEWAY_URL}" --token "${TOKEN}")"
export JOBS_JSON
python3 - <<'PY'
import json, os, sys
jobs = json.loads(os.environ["JOBS_JSON"])
want = "keepalive-websites-every-8m"
if not any(isinstance(j, dict) and j.get("name") == want for j in jobs):
    print(f"missing expected cron job: {want}")
    sys.exit(1)
PY

echo "smoke ok" >/dev/null
