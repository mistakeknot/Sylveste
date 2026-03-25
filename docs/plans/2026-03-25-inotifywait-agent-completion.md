---
artifact_type: plan
bead: Demarch-uboy.4
stage: planned
---
# Plan: Replace polling with inotifywait for agent completion

**Bead:** Demarch-uboy.4
**Goal:** Replace 5s sleep-loop polling with inotifywait filesystem events for agent completion detection. Fallback to polling if inotifywait unavailable.

## Task 1: Create flux-watch.sh helper script

**File:** `interverse/interflux/scripts/flux-watch.sh`
**New file.** Thin wrapper around inotifywait:

```bash
#!/usr/bin/env bash
# Watch OUTPUT_DIR for agent .md file completions using inotifywait.
# Falls back to 5s polling if inotifywait unavailable.
# Usage: flux-watch.sh <output_dir> [expected_count] [timeout_secs]
# Output: prints each completed filename to stdout as it appears
```

Behavior:
- If `inotifywait` available: `inotifywait -m -t $TIMEOUT -e close_write --format '%f' "$OUTPUT_DIR"` piped through a filter for `.md` (not `.md.partial`)
- If unavailable: fall back to 5s `ls` polling loop
- Prints each completed filename to stdout as it appears
- Exits when `expected_count` files seen or timeout reached
- Exit code 0 = all expected, 1 = timeout (some missing)

## Task 2: Update shared-contracts.md monitoring contract

**File:** `interverse/interflux/skills/flux-drive/phases/shared-contracts.md` (lines 104-111)
**Change:** Replace polling instructions with:

```markdown
## Monitoring Contract

After dispatching agents, monitor for completion using filesystem events:

1. **Preferred (inotifywait):** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/flux-watch.sh {OUTPUT_DIR} {N} {TIMEOUT}` where N = expected agent count, TIMEOUT = 300 (Task) or 600 (Codex). The script prints each filename as it appears. Parse output line-by-line to report completions.

2. **Fallback (polling):** If flux-watch.sh exits with error or inotifywait unavailable, check `{OUTPUT_DIR}/` for `.md` files every 5 seconds via `ls`.

- Report each completion with elapsed time
- Report running count: `[N/M agents complete]`
- Timeout: 5 minutes (Task), 10 minutes (Codex)
```

## Task 3: Update launch.md Step 2.3 polling loop

**File:** `interverse/interflux/skills/flux-drive/phases/launch.md` (lines 835-874)
**Change:** Replace the "Polling loop (every 30 seconds)" section with inotifywait-based monitoring. Keep the completion verification and retry logic unchanged — only the detection mechanism changes.

## Task 4: Update SKILL-compact.md references

**File:** `interverse/interflux/skills/flux-drive/SKILL-compact.md`
**Change:** If any polling references exist, update to mention inotifywait. Likely just a one-line note at Step 2.2 or similar.

## Build Sequence

Task 1 → Task 2 → Task 3 → Task 4 (sequential — each builds on the prior)
