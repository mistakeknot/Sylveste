#!/usr/bin/env bash
# Apply the plugin disables listed in docs/research/2026-04-21-plugin-disable-decisions.yaml
# to ~/.claude/settings.json. Idempotent — re-running leaves the file unchanged
# once disables are applied. Creates a backup at ~/.claude/settings.json.bak.<timestamp>
# before any change.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
decisions="${1:-$repo_root/docs/research/2026-04-21-plugin-disable-decisions.yaml}"
settings="${HOME}/.claude/settings.json"

[[ -f "$decisions" ]] || { echo "no decisions file: $decisions" >&2; exit 1; }
[[ -f "$settings"  ]] || { echo "no settings.json: $settings" >&2; exit 1; }

# Validate JSON before touching
python3 -c "import json; json.load(open('$settings'))" || { echo "settings.json invalid JSON" >&2; exit 1; }

ts=$(date +%Y%m%dT%H%M%S)
backup="${settings}.bak.${ts}"
cp "$settings" "$backup"
echo "backup: $backup"

python3 - "$decisions" "$settings" <<'PY'
import json, os, sys, yaml
decisions_path, settings_path = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(decisions_path))
s = json.load(open(settings_path))
ep = s.get('enabledPlugins', {})
if not isinstance(ep, dict):
    raise SystemExit(f"enabledPlugins is {type(ep).__name__}, expected dict")

changed = []
for item in d.get('decisions', []):
    if item.get('action') != 'disable':
        continue
    key = item['key']
    if key in ep and ep[key]:
        ep[key] = False
        changed.append(key)
    elif key not in ep:
        print(f"skip: {key} not in enabledPlugins (already absent)", file=sys.stderr)
    else:
        print(f"skip: {key} already disabled", file=sys.stderr)

s['enabledPlugins'] = ep

# Atomic write
tmp = settings_path + '.tmp'
with open(tmp, 'w') as f:
    json.dump(s, f, indent=2)
os.replace(tmp, settings_path)

for k in changed:
    print(f"disabled: {k}")
print(f"total changes: {len(changed)}")
PY

# Re-validate
python3 -c "import json; json.load(open('$settings'))" || { echo "post-write settings.json invalid" >&2; cp "$backup" "$settings"; exit 1; }
echo "ok: settings.json valid after apply"
