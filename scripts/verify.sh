#!/usr/bin/env bash
set -euo pipefail

URL="${OPENCLAW_GATEWAY_URL:-}"
TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="$2"; shift 2;;
    --token) TOKEN="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -z "${URL}" ]]; then
  echo "OPENCLAW_GATEWAY_URL (or --url) is required" >&2
  exit 2
fi
if [[ -z "${TOKEN}" ]]; then
  echo "OPENCLAW_GATEWAY_TOKEN (or --token) is required" >&2
  exit 2
fi

openclaw gateway health --url "${URL}" --token "${TOKEN}" >/dev/null
