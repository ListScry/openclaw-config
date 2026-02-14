#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for ./scripts/test_docker.sh" >&2
  exit 1
fi

IMAGE_TAG="openclaw-config-smoke:local"

cd "${ROOT_DIR}"

docker build -t "${IMAGE_TAG}" --build-arg OPENCLAW_VERSION=2026.2.12 .

docker run --rm "${IMAGE_TAG}"
