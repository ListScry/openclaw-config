#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2;;
    -h|--help)
      cat <<USAGE
Usage: ./scripts/sync_from_host.sh [--profile NAME]

Copies ONLY the intended safe automation/config artifacts from your live machine
into this repo folder.

This script intentionally refuses to copy OpenClaw runtime state (credentials,
sessions, browser cookies, sandboxes, etc.).
USAGE
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -n "${PROFILE}" ]]; then
  HOST_STATE_DIR="${HOME}/.openclaw-${PROFILE}"
else
  HOST_STATE_DIR="${HOME}/.openclaw"
fi

SRC_MON="${HOST_STATE_DIR}/workspace/monitoring"
DST_MON="${ROOT_DIR}/workspace/monitoring"

mkdir -p "${DST_MON}"

if [[ -f "${SRC_MON}/sites.json" ]]; then
  cp -f "${SRC_MON}/sites.json" "${DST_MON}/sites.json"
else
  echo "missing: ${SRC_MON}/sites.json" >&2
  exit 1
fi

if [[ -f "${SRC_MON}/README.md" ]]; then
  cp -f "${SRC_MON}/README.md" "${DST_MON}/README.md"
fi

if [[ -f "${SRC_MON}/keepalive_state.json" ]]; then
  echo "note: not copying runtime state: ${SRC_MON}/keepalive_state.json" >&2
fi

# Explicitly warn if sensitive dirs exist (we never copy them).
for p in credentials agents extensions sandboxes; do
  if [[ -e "${HOST_STATE_DIR}/${p}" ]]; then
    echo "note: refusing to copy sensitive path: ${HOST_STATE_DIR}/${p}" >&2
  fi
done

echo "synced: workspace/monitoring/sites.json" >&2
