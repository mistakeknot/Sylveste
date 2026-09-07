#!/usr/bin/env bash
# Re-enable a plugin that was disabled via apply-plugin-disables.sh.
# Usage: rollback-plugins.sh <plugin-name> [<plugin-name> ...]
#
# <plugin-name> may be the short name ("vercel") or the fully qualified key
# ("vercel@claude-plugins-official"). Short names resolve by matching any
# enabledPlugins key whose prefix-before-@ matches case-insensitively.
set -euo pipefail

settings="${HOME}/.claude/settings.json"
[[ -f "$settings" ]] || { echo "no settings.json: $settings" >&2; exit 1; }
[[ $# -ge 1 ]] || { echo "usage: $(basename "$0") <plugin> [<plugin>...]" >&2; exit 1; }

ts=$(date +%Y%m%dT%H%M%S)
cp "$settings" "${settings}.bak.${ts}"

python3 - "$settings" "$@" <<'PY'
import json, os, sys
settings_path = sys.argv[1]
names = sys.argv[2:]
s = json.load(open(settings_path))
ep = s.get('enabledPlugins', {})
if not isinstance(ep, dict):
    raise SystemExit(f"enabledPlugins is {type(ep).__name__}")

changed = []
for n in names:
    # Direct key match first
    if n in ep:
        if not ep[n]:
            ep[n] = True
            changed.append(n)
        else:
            print(f"already enabled: {n}", file=sys.stderr)
        continue
    # Short-name match
    matches = [k for k in ep if k.split('@', 1)[0].lower() == n.lower()]
    if not matches:
        print(f"not found: {n} (no matching enabledPlugins key)", file=sys.stderr)
        continue
    for m in matches:
        if not ep[m]:
            ep[m] = True
            changed.append(m)
        else:
            print(f"already enabled: {m}", file=sys.stderr)

s['enabledPlugins'] = ep
tmp = settings_path + '.tmp'
with open(tmp, 'w') as f:
    json.dump(s, f, indent=2)
os.replace(tmp, settings_path)

for k in changed:
    print(f"re-enabled: {k}")
print(f"total changes: {len(changed)}")
PY

python3 -c "import json; json.load(open('$settings'))" || { echo "post-write settings.json invalid" >&2; exit 1; }
echo "ok: settings.json valid after rollback. Run /clear in Claude Code to re-initialize."
