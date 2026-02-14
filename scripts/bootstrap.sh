#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROFILE=""
MODE="local"   # local | ci
SERVICE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --service) SERVICE="true"; shift 1;;
    -h|--help)
      cat <<USAGE
Usage: ./scripts/bootstrap.sh [--profile NAME] [--mode local|ci] [--service]

Bootstraps a safe OpenClaw config + workspace + cron desired state.

Defaults:
- profile: none (uses ~/.openclaw)
- mode: local
- start mode: foreground (unless --service)
USAGE
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ "${MODE}" != "local" && "${MODE}" != "ci" ]]; then
  echo "--mode must be local|ci" >&2
  exit 2
fi

if ! command -v openclaw >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "+ brew install openclaw" >&2
    brew install openclaw
  else
    echo "openclaw not found and Homebrew missing; install OpenClaw first" >&2
    exit 1
  fi
fi

if [[ -n "${PROFILE}" ]]; then
  STATE_DIR="${HOME}/.openclaw-${PROFILE}"
else
  STATE_DIR="${HOME}/.openclaw"
fi

export OPENCLAW_STATE_DIR="${STATE_DIR}"
mkdir -p "${OPENCLAW_STATE_DIR}"
chmod 700 "${OPENCLAW_STATE_DIR}" || true

copy_tree() {
  local src="$1"
  local dst="$2"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$src" "$dst"
  else
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
  fi
}

# Ensure .env exists, and ensure a gateway token exists.
ENV_FILE="${OPENCLAW_STATE_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  umask 077
  cat >"${ENV_FILE}" <<'EOV'
# OpenClaw host secrets. Do not commit.
# This file is auto-loaded by OpenClaw.
EOV
  chmod 600 "${ENV_FILE}" || true
fi

# Resolve OPENCLAW_GATEWAY_TOKEN from env or .env; if missing, generate and append.
if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  TOKEN_FROM_FILE="$(sed -n 's/^OPENCLAW_GATEWAY_TOKEN=//p' "${ENV_FILE}" | tail -n 1 || true)"
  if [[ -n "${TOKEN_FROM_FILE}" ]]; then
    export OPENCLAW_GATEWAY_TOKEN="${TOKEN_FROM_FILE}"
  fi
fi

if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  # Not cryptographic; sufficient for shared-secret local gateway auth.
  TOKEN="bootstrap-$(date +%s)-$RANDOM$RANDOM"
  printf '\nOPENCLAW_GATEWAY_TOKEN=%s\n' "${TOKEN}" >>"${ENV_FILE}"
  chmod 600 "${ENV_FILE}" || true
  export OPENCLAW_GATEWAY_TOKEN="${TOKEN}"
fi

# Copy config bundle into state dir (do not run directly from repo).
CONFIG_DIR="${OPENCLAW_STATE_DIR}/config"
mkdir -p "${CONFIG_DIR}"
if command -v rsync >/dev/null 2>&1; then
  rsync -a \
    --exclude 'secrets/secrets.local.*' \
    "${ROOT_DIR}/config/" \
    "${CONFIG_DIR}/"
else
  copy_tree "${ROOT_DIR}/config" "${CONFIG_DIR}"
fi

# Copy workspace automation files.
WORKSPACE_DIR="${OPENCLAW_STATE_DIR}/workspace"
mkdir -p "${WORKSPACE_DIR}"
if command -v rsync >/dev/null 2>&1; then
  rsync -a \
    --exclude '*/keepalive_state.json' \
    "${ROOT_DIR}/workspace/" \
    "${WORKSPACE_DIR}/"
else
  copy_tree "${ROOT_DIR}/workspace" "${WORKSPACE_DIR}"
  find "${WORKSPACE_DIR}" -type f -name 'keepalive_state.json' -delete 2>/dev/null || true
fi

export OPENCLAW_CONFIG_PATH="${CONFIG_DIR}/openclaw.${MODE}.json5"

# Gateway connection parameters.
export OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
export OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-loopback}"
export OPENCLAW_TAILSCALE_MODE="${OPENCLAW_TAILSCALE_MODE:-off}"
export OPENCLAW_GATEWAY_URL="ws://127.0.0.1:${OPENCLAW_GATEWAY_PORT}"

# Tighten permissions for config files on real machines.
chmod 700 "${CONFIG_DIR}" || true
chmod 600 "${OPENCLAW_CONFIG_PATH}" || true

if [[ "${SERVICE}" == "true" ]]; then
  if "${ROOT_DIR}/scripts/verify.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}" 2>/dev/null; then
    "${ROOT_DIR}/scripts/apply_cron.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}"
    "${ROOT_DIR}/scripts/verify.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}"
    echo "Gateway already running as a service at ${OPENCLAW_GATEWAY_URL}" >&2
    exit 0
  fi

  echo "+ openclaw gateway install" >&2
  openclaw gateway install

  echo "+ openclaw gateway start" >&2
  openclaw gateway start

  # Wait for health.
  for _ in $(seq 1 30); do
    if "${ROOT_DIR}/scripts/verify.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}"; then
      break
    fi
    sleep 1
  done

  "${ROOT_DIR}/scripts/apply_cron.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}"
  "${ROOT_DIR}/scripts/verify.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}"

  echo "Gateway running as a service at ${OPENCLAW_GATEWAY_URL}" >&2
  exit 0
fi

# Foreground bootstrap: start temporarily in background for cron reconcile + verify,
# then restart in the foreground.

if "${ROOT_DIR}/scripts/verify.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}" 2>/dev/null; then
  "${ROOT_DIR}/scripts/apply_cron.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}"
  "${ROOT_DIR}/scripts/verify.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}"
  echo "Gateway already running at ${OPENCLAW_GATEWAY_URL}" >&2
  exit 0
fi

port_in_use() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -lnt | awk '{print $4}' | grep -q ":${port}$" 2>/dev/null
    return $?
  fi
  return 1
}

if port_in_use "${OPENCLAW_GATEWAY_PORT}"; then
  echo "Port ${OPENCLAW_GATEWAY_PORT} is already in use, but health check failed with the token from ${ENV_FILE}." >&2
  echo "Either:" >&2
  echo "- update OPENCLAW_GATEWAY_TOKEN in ${ENV_FILE} to match the running gateway, or" >&2
  echo "- stop the running gateway (openclaw gateway stop), then re-run bootstrap." >&2
  exit 1
fi

echo "+ openclaw gateway run (background for provisioning)" >&2
openclaw gateway run \
  --port "${OPENCLAW_GATEWAY_PORT}" \
  --bind "${OPENCLAW_GATEWAY_BIND}" \
  --auth token \
  --token "${OPENCLAW_GATEWAY_TOKEN}" \
  --tailscale "${OPENCLAW_TAILSCALE_MODE}" \
  --force \
  >/dev/null 2>&1 &
GW_PID=$!

cleanup() {
  if kill -0 "${GW_PID}" >/dev/null 2>&1; then
    kill "${GW_PID}" >/dev/null 2>&1 || true
    wait "${GW_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for _ in $(seq 1 30); do
  if "${ROOT_DIR}/scripts/verify.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}"; then
    break
  fi
  sleep 1
done

"${ROOT_DIR}/scripts/apply_cron.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}"
"${ROOT_DIR}/scripts/verify.sh" --url "${OPENCLAW_GATEWAY_URL}" --token "${OPENCLAW_GATEWAY_TOKEN}"

# Stop background gateway, then run in foreground.
cleanup
trap - EXIT

echo "+ openclaw gateway run (foreground)" >&2
exec "${ROOT_DIR}/scripts/start_gateway.sh"
