#!/usr/bin/env bash
set -euo pipefail

PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
BIND="${OPENCLAW_GATEWAY_BIND:-loopback}"
TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
TAILSCALE_MODE="${OPENCLAW_TAILSCALE_MODE:-off}"

if [[ -z "${TOKEN}" ]]; then
  echo "OPENCLAW_GATEWAY_TOKEN is required (set it or put it in $OPENCLAW_STATE_DIR/.env)" >&2
  exit 2
fi

exec openclaw gateway run \
  --port "${PORT}" \
  --bind "${BIND}" \
  --auth token \
  --token "${TOKEN}" \
  --tailscale "${TAILSCALE_MODE}"
