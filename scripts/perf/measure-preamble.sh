#!/usr/bin/env bash
# Emits JSON with preamble-component byte counts from a session jsonl.
# Defaults to the newest jsonl in the project dir; override with --session-id
# (explicit ID avoids the ls -t race when the current session is still writing).
set -euo pipefail
project_dir="${HOME}/.claude/projects/-home-mk-projects-Sylveste"
session_id=""
for arg in "$@"; do
  case "$arg" in
    --session-id=*) session_id="${arg#--session-id=}" ;;
    --project-dir=*) project_dir="${arg#--project-dir=}" ;;
  esac
done

if [[ -n "$session_id" ]]; then
  target="$project_dir/$session_id.jsonl"
  [[ -f "$target" ]] || { echo "{\"error\":\"no jsonl for $session_id\"}"; exit 1; }
else
  # Use Python glob to pick newest; avoids ls|head SIGPIPE under `pipefail`
  target=$(python3 -c "
import glob, os, sys
files = sorted(glob.glob(os.path.join(sys.argv[1], '*.jsonl')), key=os.path.getmtime, reverse=True)
print(files[0] if files else '')
" "$project_dir")
  [[ -z "$target" ]] && { echo '{"error":"no session jsonl"}'; exit 1; }
fi

python3 - "$target" <<'PY'
import json, sys
path = sys.argv[1]
buckets = {
  "skill_listing_bytes": 0,
  "deferred_tools_delta_bytes": 0,
  "mcp_instructions_bytes": 0,
  "sessionstart_bytes": 0,
  "total_preamble_bytes": 0,
  "sampled_session_id": path.split("/")[-1].replace(".jsonl",""),
  "attachment_types_seen": [],
}
seen_types = []
with open(path) as f:
    for line in f:
        try:
            m = json.loads(line)
        except Exception:
            buckets["total_preamble_bytes"] += len(line)
            continue
        if m.get("type") == "assistant":
            break
        buckets["total_preamble_bytes"] += len(line)
        att = m.get("attachment") or (m.get("message") or {}).get("attachment") or {}
        if not isinstance(att, dict):
            msg_att = m.get("message", {}).get("attachment")
            if isinstance(msg_att, dict):
                att = msg_att
        t = att.get("type", "")
        if t and t not in seen_types:
            seen_types.append(t)
        if t == "skill_listing":
            buckets["skill_listing_bytes"] += len(line)
        elif t == "deferred_tools_delta":
            buckets["deferred_tools_delta_bytes"] += len(line)
        elif t == "mcp_instructions_delta":
            buckets["mcp_instructions_bytes"] += len(line)
        elif t == "hook_success" and att.get("hookEvent") == "SessionStart":
            buckets["sessionstart_bytes"] += len(line)

buckets["attachment_types_seen"] = seen_types
if buckets["skill_listing_bytes"] == 0:
    buckets["warning"] = "skill_listing attachment not found — check --session-id or re-run after /clear"
print(json.dumps(buckets, indent=2))
PY
