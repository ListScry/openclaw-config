# openclaw-config

This repo folder is config-as-code for OpenClaw.

Goals:
- Sync a sanitized, portable OpenClaw configuration + workspace automation files into git.
- Bootstrap a fresh machine deterministically.
- Provide a Docker smoke test that validates bootstrap without real credentials.

## Quick start

Local bootstrap (creates/uses `~/.openclaw`, copies config/workspace, applies cron, starts gateway):

```bash
cd openclaw-config
./scripts/bootstrap.sh
```

Named profile (isolates state under `~/.openclaw-<name>`):

```bash
./scripts/bootstrap.sh --profile vps
```

Docker smoke test (requires Docker):

```bash
./scripts/test_docker.sh
```

Daily GitHub sync (safe files only):

```bash
./scripts/daily_sync.sh
```

## Secrets

Do not commit secrets.

Preferred: put secrets in `$OPENCLAW_STATE_DIR/.env` (OpenClaw auto-loads it).
A template is at `config/secrets/secrets.template.env`.

## What is committed

- Safe OpenClaw config entrypoints: `config/openclaw.local.json5`, `config/openclaw.ci.json5`
- Portable workspace files: `workspace/monitoring/sites.json` (copied from host)
- Declarative cron desired state: `cron/desired-jobs.json`

## What is never committed

Anything under the OpenClaw state dir that may contain secrets/private data, including:
- `credentials/**`
- `agents/**/sessions/**`
- `agents/**/agent/auth-profiles.json`
- `extensions/**`, `sandboxes/**`
- browser profiles/cookies
- runtime keepalive state (e.g. `keepalive_state.json`)
