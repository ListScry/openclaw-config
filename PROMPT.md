PROMPT.md — OpenClaw config-as-code repo (GitHub sync + reproducible restore + VM smoke test)

Mission

Build and maintain a Git repo whose only job is to keep my OpenClaw “configuration/automation” reproducible across machines:
	•	I can move to a new Mac/VPS, git clone, run one command, and have:
	•	the same OpenClaw gateway configuration (local loopback bind, port, auth mode, etc.)
	•	the same workspace automation files (monitoring/keepalive configs, etc.)
	•	the same cron job definitions (recreated consistently)
	•	Secrets and private runtime state must not be committed (tokens, credentials, transcripts, browser cookies, etc.). OpenClaw explicitly warns that anything under ~/.openclaw/ may contain secrets or private data (config tokens, credentials, session transcripts, sandbox artifacts, etc.).  

This repo should support:
	1.	Sync from “live machine” → GitHub (sanitized, deterministic)
	2.	Bootstrap from GitHub → “fresh machine” (deterministic)
	3.	A virtual-environment smoke test (Docker-based) that proves the bootstrap works without real credentials

⸻

Ground rules from OpenClaw docs (non-negotiable)

Do NOT commit your whole ~/.openclaw/

OpenClaw stores sensitive data under the state dir, including:
	•	credentials/** (channel creds, pairing allowlists, OAuth imports)
	•	agents/<agentId>/sessions/** (session transcripts)
	•	agents/<agentId>/agent/auth-profiles.json (API keys / OAuth tokens)
	•	extensions/**, sandboxes/**, etc.  

Config location + overrides
	•	Default config path: ~/.openclaw/openclaw.json
	•	Override with OPENCLAW_CONFIG_PATH
	•	Override state directory with OPENCLAW_STATE_DIR
	•	OpenClaw also loads a global .env at ~/.openclaw/.env (aka $OPENCLAW_STATE_DIR/.env) without overriding existing vars (useful for secrets-on-host).  

Config modularization

Use config includes ($include) so the repo can separate:
	•	safe, committed config
	•	local-only secrets and machine-specific overrides

Include merge behavior matters:
	•	single include file replaces the containing object
	•	array of include files deep-merges in order (later wins)
	•	sibling keys override included values  

Cron jobs persistence + safe management

Cron jobs persist at ~/.openclaw/cron/jobs.json by default and the gateway rewrites it; manual edits are only safe when the gateway is stopped. Prefer openclaw cron add/edit or cron tool calls.  

Gateway startup invariants
	•	openclaw gateway runs the gateway; openclaw gateway run is a foreground alias.
	•	By default, gateway refuses to start unless gateway.mode=local is set in config.
	•	Non-loopback binds without auth are blocked.
	•	Useful flags: --port, --bind, --auth, --token, --allow-unconfigured, etc.  

Health check surface
	•	openclaw health fetches health from the running gateway.  
	•	openclaw gateway health --url ws://127.0.0.1:<port> is also available.  

⸻

Repo outputs (what “done” looks like)

When finished, this repo contains:
	1.	A committed OpenClaw config entrypoint that is safe to publish
	2.	A bootstrap command that:
	•	installs OpenClaw (or verifies it exists)
	•	puts config in the right place (or points OpenClaw at it)
	•	ensures workspace automations are present
	•	recreates cron jobs
	•	starts the gateway (foreground or service)
	3.	A Docker smoke test that starts a gateway with CI-safe config and confirms:
	•	gateway starts
	•	gateway health responds
	•	expected cron jobs exist (or are created)
	4.	A .gitignore and (optional but recommended) secret scanning guardrails

⸻

What we are capturing from the current setup

From the current machine snapshot (source-of-truth intent):
	•	Gateway: local loopback-only, port 18789, token auth, tailscale off
	•	Default model: openai-codex/gpt-5.3-codex (model keys are secrets; don’t commit)
	•	Workspace automations under ~/.openclaw/workspace/monitoring/:
	•	sites.json (committed)
	•	keepalive_state.json (treat as runtime state; do not commit)
	•	One cron job: keepalive-websites-every-8m (recreated by name + schedule + payload)

Important realism constraint:
	•	Browser-based “keepalive” automations rely on logged-in browser state (cookies) stored locally in the OpenClaw browser profile. That state must not be committed. After restore on a new machine, you should expect to re-login once per site/profile.

⸻

Proposed repo layout

Use a structure that makes “safe vs secret vs state” obvious:

openclaw-config/
  README.md
  PROMPT.md                # this file

  config/
    openclaw.local.json5   # main config entrypoint (NO raw secrets committed)
    openclaw.ci.json5      # CI-safe config (channels disabled, no external creds)
    parts/
      gateway.json5
      agents.json5
      channels.telegram.json5         # committed but references env vars for token
      channels.disabled.json5         # used by CI
      cron.json5
      browser.json5
      monitoring.json5               # points to workspace paths, etc.

    secrets/
      secrets.template.env            # doc-only: what env vars must exist
      secrets.local.env               # gitignored (optional pattern)
      secrets.local.json5             # gitignored if you choose include-file secrets

  workspace/
    monitoring/
      sites.json
      HEARTBEAT.md (if you have it)
      ... any other automation config files meant to be portable ...

  cron/
    desired-jobs.json                 # declarative desired state (committed)

  scripts/
    bootstrap.sh                      # one-command install/restore
    sync_from_host.sh                 # copy/sanitize from ~/.openclaw into repo
    apply_cron.sh                     # reconcile cron desired state
    start_gateway.sh                  # start gateway in foreground/service
    verify.sh                          # runs health + basic checks
    test_docker.sh                    # virtual env smoke test

  tests/
    smoke.sh                          # docker entrypoint test logic

  .github/
    workflows/
      ci.yml                          # runs docker smoke test

  .gitignore

⸻

(See the original prompt in chat for the remaining design notes and acceptance checklist.)
