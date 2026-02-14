#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESIRED_FILE="${ROOT_DIR}/cron/desired-jobs.json"

URL="${OPENCLAW_GATEWAY_URL:-}"
TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="$2"; shift 2;;
    --token) TOKEN="$2"; shift 2;;
    --desired) DESIRED_FILE="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ ! -f "${DESIRED_FILE}" ]]; then
  echo "desired jobs file missing: ${DESIRED_FILE}" >&2
  exit 2
fi
if [[ -z "${URL}" ]]; then
  echo "OPENCLAW_GATEWAY_URL (or --url) is required" >&2
  exit 2
fi
if [[ -z "${TOKEN}" ]]; then
  echo "OPENCLAW_GATEWAY_TOKEN (or --token) is required" >&2
  exit 2
fi

# Fetch existing jobs (JSON)
EXISTING_JSON="$(openclaw cron list --json --url "${URL}" --token "${TOKEN}")"

export DESIRED_FILE="${DESIRED_FILE}"
export URL="${URL}"
export TOKEN="${TOKEN}"
export EXISTING_JSON="${EXISTING_JSON}"

python3 - <<'PY'
import json, os, shlex, subprocess, sys

desired_path = os.environ["DESIRED_FILE"]
url = os.environ["URL"]
token = os.environ["TOKEN"]
existing_json = os.environ["EXISTING_JSON"]

try:
    desired = json.load(open(desired_path, "r"))
except Exception as e:
    print(f"failed to parse desired jobs: {e}", file=sys.stderr)
    sys.exit(2)

jobs = desired.get("jobs")
if not isinstance(jobs, list):
    print("desired-jobs.json must contain a top-level 'jobs' array", file=sys.stderr)
    sys.exit(2)

try:
    existing = json.loads(existing_json)
except Exception as e:
    print(f"failed to parse openclaw cron list --json output: {e}", file=sys.stderr)
    sys.exit(2)

if not isinstance(existing, list):
    print("unexpected cron list output (expected JSON array)", file=sys.stderr)
    sys.exit(2)

by_name = {}
for j in existing:
    if isinstance(j, dict) and isinstance(j.get("name"), str):
        by_name[j["name"]] = j

def run(cmd):
    print("+", " ".join(shlex.quote(c) for c in cmd))
    subprocess.check_call(cmd)

for d in jobs:
    if not isinstance(d, dict):
        continue
    name = d.get("name")
    if not isinstance(name, str) or not name:
        continue

    enabled = bool(d.get("enabled", True))
    desc = d.get("description")

    schedule = d.get("schedule", {})
    sk = schedule.get("kind")

    session_target = d.get("sessionTarget")
    payload = d.get("payload", {})
    pk = payload.get("kind")

    wake_mode = d.get("wakeMode")

    common = ["--url", url, "--token", token]

    if sk not in ("every", "cron", "at"):
        print(f"skip {name}: unsupported schedule.kind={sk}", file=sys.stderr)
        continue

    if session_target not in ("main", "isolated"):
        print(f"skip {name}: unsupported sessionTarget={session_target}", file=sys.stderr)
        continue

    # Build desired args (used for add/edit)
    desired_args = []
    desired_args += ["--name", name]
    if isinstance(desc, str) and desc:
        desired_args += ["--description", desc]

    if sk == "every":
        every = schedule.get("every")
        if not every:
            print(f"skip {name}: schedule.every is required for kind=every", file=sys.stderr)
            continue
        desired_args += ["--every", str(every)]
    elif sk == "cron":
        cron = schedule.get("cron")
        if not cron:
            print(f"skip {name}: schedule.cron is required for kind=cron", file=sys.stderr)
            continue
        desired_args += ["--cron", str(cron)]
        tz = schedule.get("tz")
        if isinstance(tz, str) and tz:
            desired_args += ["--tz", tz]
    elif sk == "at":
        at = schedule.get("at")
        if not at:
            print(f"skip {name}: schedule.at is required for kind=at", file=sys.stderr)
            continue
        desired_args += ["--at", str(at)]

    desired_args += ["--session", session_target]

    if pk == "systemEvent":
        se = payload.get("systemEvent")
        if not se:
            print(f"skip {name}: payload.systemEvent is required for kind=systemEvent", file=sys.stderr)
            continue
        desired_args += ["--system-event", str(se)]
    elif pk == "agentTurn":
        msg = payload.get("message")
        if not msg:
            print(f"skip {name}: payload.message is required for kind=agentTurn", file=sys.stderr)
            continue
        desired_args += ["--message", str(msg)]
    else:
        print(f"skip {name}: unsupported payload.kind={pk}", file=sys.stderr)
        continue

    if isinstance(wake_mode, str) and wake_mode:
        desired_args += ["--wake", wake_mode]

    existing_job = by_name.get(name)

    if existing_job is None:
        cmd = ["openclaw", "cron", "add"] + common + desired_args
        if not enabled:
            cmd += ["--disabled"]
        run(cmd)
        continue

    job_id = existing_job.get("jobId") or existing_job.get("id")
    if not isinstance(job_id, str) or not job_id:
        print(f"skip edit {name}: missing id in cron list output", file=sys.stderr)
        continue

    cmd = ["openclaw", "cron", "edit"] + common + desired_args
    if enabled:
        cmd += ["--enable"]
    else:
        cmd += ["--disable"]
    cmd += [job_id]
    run(cmd)
PY
