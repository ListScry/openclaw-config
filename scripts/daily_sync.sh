#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2;;
    -h|--help)
      cat <<USAGE
Usage: ./scripts/daily_sync.sh [--profile NAME]

1) Sync safe host artifacts into repo (workspace/monitoring/sites.json)
2) Commit if there are changes
3) Push to origin/main

Refuses to proceed if forbidden paths appear.
USAGE
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

cd "${ROOT_DIR}"

./scripts/sync_from_host.sh ${PROFILE:+--profile "${PROFILE}"}

# Hard guardrails: these must never be tracked.
FORBIDDEN_REGEX='^(credentials/|agents/|extensions/|sandboxes/|cron/jobs\.json$|.*keepalive_state\.json$|config/secrets/secrets\.local\.)'
TRACKED_FORBIDDEN="$(git ls-files | rg -n "${FORBIDDEN_REGEX}" || true)"
if [[ -n "${TRACKED_FORBIDDEN}" ]]; then
  echo "refusing: forbidden files are tracked:" >&2
  echo "${TRACKED_FORBIDDEN}" >&2
  exit 1
fi

git add -A

if git diff --cached --quiet; then
  echo "no changes" >&2
  exit 0
fi

MSG="daily sync $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git commit -m "${MSG}"

git push
