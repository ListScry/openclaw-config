FROM node:22-bookworm-slim

ARG OPENCLAW_VERSION=2026.2.12

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash ca-certificates curl python3 \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g "openclaw@${OPENCLAW_VERSION}"

WORKDIR /repo/openclaw-config
COPY . /repo/openclaw-config

CMD ["bash", "-lc", "./tests/smoke.sh"]
