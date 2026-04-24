---
artifact_type: research
bead: sylveste-h1w1
depends_on: sylveste-ynh7
date: 2026-04-23
stage: complete
---

# sylveste-h1w1 Results — SessionStart Hook Output Audit

## Summary (projected — awaits fresh-session remeasurement)

Single change: `.beads/PRIME.md` trimmed 86 → 29 lines (3,855 → 1,396 bytes stdout).

- **Projected savings: ~5,017 bytes / ≈ 1,320 tokens per session** on the SessionStart hook bucket.
- Acceptance floor (≥ 500 tokens combined SessionStart + async_hook) → **projected PASS by 2.6×**.
- `async_hook_response` unchanged — its entries are "Output truncated" infrastructure and weren't the real lever.

A validation pass in the next fresh session will confirm actual numbers; see §Remeasurement.

## Per-hook breakdown (pre-trim, ynh7 post session 73c86818)

SessionStart bucket: 16,566 bytes across 10 hook_success entries.

| rank | hook source                        |  line bytes | stdout bytes | note |
|-----:|------------------------------------|------------:|-------------:|------|
|    1 | beads `bd prime`                   |       8,515 |        3,855 | `.beads/PRIME.md` content **← target** |
|    2 | explanatory-mode `hooks-handlers/` |       1,758 |        1,129 | Claude Code built-in, not Sylveste |
|    3 | interkasten `hooks/setup.sh`       |       1,022 |          201 | "Notion token not configured" notice |
|    4 | intership `hooks/session-start.sh` |         807 |           96 | "loaded 253 spinner verbs" |
|    5 | tool-time `hooks/hook.sh`          |         786 |            0 | silent logger, wrapper-only cost |
|    6 | intermem `hooks/session-start.sh`  |         771 |           78 | MEMORY.md budget warning |
|    7 | intermux/interstat `session-start` |         742 |           63 | "Session started: <uuid>" |
|    8 | interflux `hooks/session-start.sh` |         732 |            0 | budget-signal reader, wrapper-only |
|    9 | interknow `hooks/session-start.sh` |         726 |          105 | "N knowledge entries" status ping |
|   10 | intertrack `hooks/session-start.sh`|         707 |           46 | "0 metrics tracked, 0 observations" |
|      | **TOTAL**                          |  **16,566** |    **5,573** | |

### Two structural findings

1. **`bd prime` dominates**: 51 % of SessionStart bytes come from one hook emitting `.beads/PRIME.md`. That file was 86 lines of command reference + workflow examples — most of it available via `bd --help`.

2. **Duplicate `content` / `stdout` fields**: each hook_success JSONL entry emits both a `content` field and a `stdout` field that are byte-identical (modulo one trailing newline). So every byte of hook stdout counts **twice** in session preamble cost. This is a Claude Code harness-level waste, not something Sylveste plugins can fix. Worth filing upstream as a 2× compression opportunity across every hook.

3. **~700-byte JSON wrapper per hook entry**: the envelope (`hookName`, `hookEvent`, `command`, `toolUseID`, `content`, `stdout`, `stderr`, `exitCode`, `durationMs`, `type`) costs ~700 bytes regardless of whether the hook emits anything. Two hooks (tool-time `hook.sh`, interflux `session-start.sh`) emit 0 bytes of stdout but still pay ~760-byte wrapper each = 1,518 bytes of pure envelope per session. Cannot be eliminated at the plugin level — the harness emits the wrapper whenever a hook fires.

## What shipped this pass

### `.beads/PRIME.md` trim (commit `7d2a39b7`)

Old: 86 lines / 3,855 bytes (content emitted twice per session = 7,710 bytes line-cost)

Kept (load-bearing):
- 8-step session-close checklist (the rule that made ynh7 ship correctly: `bd backup` + `bash .beads/push.sh` + `git push`)
- Core prohibition: track in beads, no TodoWrite/TaskCreate
- Core semantics: `bd search` before `bd create`, priority 0–4, `bd edit` blocks agents

Dropped (deferred to `bd --help`):
- Full command enumeration (finding / creating / deps / sync / health)
- "Common Workflows" examples — duplicated by `/clavain:work` and `/sprint` skill content

New: 29 lines / 1,396 bytes stdout.

### Not shipped this pass

- **Wrapper elimination for silent hooks** (tool-time hook.sh, interflux session-start.sh). Would require unregistering their SessionStart entries, which breaks their real work (tool-time analytics logging, interflux budget-signal reads). Out of scope; would need per-hook budget review upstream.
- **interkasten / intertrack / intership message trim**. Each emits < 200 bytes stdout — not worth the risk of dropping load-bearing status ("Notion token not configured" is actionable, "0 metrics tracked" signals intertrack isn't running, etc.). Flag as low-priority follow-up.
- **`content` / `stdout` duplicate-field removal**. Harness-level; file upstream.

## Projected pre/post

| bucket                               |    pre    | projected post |   Δ bytes | Δ tokens |
|--------------------------------------|----------:|---------------:|----------:|---------:|
| SessionStart (bd prime entry only)   |    8,515  |         ~3,500 |    −5,015 |   −1,320 |
| SessionStart (other 9 entries)       |    8,051  |          8,051 |         0 |        0 |
| **SessionStart total**               | **16,566**|     **~11,549**| **−5,017**| **−1,320**|
| async_hook_response                  |    4,869  |          4,869 |         0 |        0 |
| **Combined target (floor ≥ 500 tok)**| **21,435**|     **~16,418**| **−5,017**| **−1,320**|

Projected TIER: **ACCEPTABLE** (≥ 500 tokens savings floor met, with 2.6× headroom).

## Remeasurement

The current session can't self-measure the post-trim SessionStart bucket — its SessionStart hooks already fired against the old PRIME.md. Validation requires a fresh `/clear` session reading the new file.

### Next-session procedure (same pattern as ynh7 Task 6)

```bash
# In the fresh session, capture the sid:
NEW_SID=$(ls -t ~/.claude/projects/-home-mk-projects-Sylveste/*.jsonl | head -1 | xargs basename | sed 's/.jsonl//')
echo "$NEW_SID" > /tmp/sylveste-h1w1-post-sid.txt

# Measure:
POST_SID=$(cat /tmp/sylveste-h1w1-post-sid.txt)
bash scripts/perf/measure-preamble.sh --session-id="$POST_SID" > /tmp/h1w1-post.json

# Verify per-hook breakdown:
python3 - <<'PY'
import json
path = f"/home/mk/.claude/projects/-home-mk-projects-Sylveste/{open('/tmp/sylveste-h1w1-post-sid.txt').read().strip()}.jsonl"
rows = []
with open(path) as f:
    for line in f:
        try: m = json.loads(line)
        except: continue
        if m.get("type") == "assistant": break
        att = m.get("attachment") or (m.get("message") or {}).get("attachment") or {}
        if isinstance(att, dict) and att.get("type") == "hook_success" and att.get("hookEvent") == "SessionStart":
            rows.append((att.get("command","")[:50], len(line), len(att.get("stdout","") or "")))
for c,lb,ob in sorted(rows, key=lambda x: -x[1]):
    print(f"  {lb:>6,}b line  {ob:>5,}b out  {c}")
print(f"TOTAL: {sum(r[1] for r in rows):,} bytes")
PY
```

Expected `bd prime` entry: ~3,500 bytes (down from 8,515). Expected SessionStart total: ~11,500 bytes (down from 16,566). If within ±500 bytes of projection, close bead as ACCEPTABLE.

## Follow-up suggestions

- **Upstream (Claude Code harness)**: the `content` / `stdout` duplicate-field waste is a 2× compression opportunity across every hook entry in session jsonl. File via normal channel.
- **Sylveste low-priority**: intertrack / intership / interknow could gate their "no change since last session" status messages to silent. Small bytes (46–105 each) but across many sessions adds up. P4.
- **Sylveste low-priority**: tool-time SessionStart registration could be removed if the analytics.db's session count is reconstructable from PostToolUse events alone. Saves 786 wrapper bytes per session. P4.
- **Measurement hygiene (already filed under ynh7 follow-ups)**: `measure-preamble.sh` currently conflates user-prompt body into total_preamble_bytes. Split it out.

## Post-remeasurement (2026-04-24, fresh session `ff08ad22`)

Projections held. Single fresh-session measurement:

| hook source                        | line bytes | stdout bytes | vs pre  |
|-----------------------------------:|-----------:|-------------:|--------:|
| beads `bd prime`                   |      3,537 |        1,375 | −4,978  |
| explanatory-mode `hooks-handlers/` |      1,758 |        1,129 |      0  |
| interkasten `hooks/setup.sh`       |      1,022 |          201 |      0  |
| intership `hooks/session-start.sh` |        807 |           96 |      0  |
| tool-time `hooks/hook.sh`          |        786 |            0 |      0  |
| intermem `hooks/session-start.sh`  |        771 |           78 |      0  |
| intermux/interstat `session-start` |        741 |           63 |     −1  |
| interflux `hooks/session-start.sh` |        732 |            0 |      0  |
| interknow `hooks/session-start.sh` |        726 |          105 |      0  |
| intertrack `hooks/session-start.sh`|        709 |           47 |     +2  |
| **TOTAL**                          | **11,589** |    **3,094** | **−4,977** |

Actual delta: **−4,977 bytes / ≈ −1,310 tokens per session** (÷ 3.8).

Projection variance: −5,017 projected vs −4,977 measured = 40 bytes / 0.8 %. Per-hook: `bd prime` landed at 3,537 vs projected ~3,500 (within 37 bytes). Other 9 entries unchanged (±2 bytes noise on two status-ping hooks).

**TIER: ACCEPTABLE** — 2.6× headroom over the 500-token floor. Combined bucket (SessionStart + async_hook_response) now 16,458 bytes vs 21,435 pre.

## Files

- Modified: `.beads/PRIME.md` (86 → 29 lines)
- Created: this doc
- Implementation commit: `7d2a39b7` perf(beads): trim PRIME.md
- Remeasurement session: `ff08ad22-cd9e-4bb6-b854-8bd7ffdfa0fa`
