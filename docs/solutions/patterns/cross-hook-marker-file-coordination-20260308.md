---
title: "Cross-Hook Marker-File Coordination"
category: patterns
tags: [clavain, hooks, cross-hook, event-bridge, compaction]
created: 2026-03-08
severity: low
confidence: verified
trigger: "Need to pass state between two hook events that can't share memory (e.g., PreCompact → UserPromptSubmit)"
lastConfirmed: 2026-03-08
provenance: assessed-from:post_compact_reminder (iv-ewjom)
review_count: 0
---

# Cross-Hook Marker-File Coordination

## Context

Claude Code hooks run in separate shell processes — they share no memory, environment variables, or file descriptors. When one hook event (e.g., PreCompact) needs to trigger behavior in a later hook event (e.g., UserPromptSubmit), the only reliable bridge is a filesystem marker file.

This pattern was identified during assessment of [post_compact_reminder](https://github.com/Dicklesworthstone/post_compact_reminder) (iv-ewjom), which uses it to inject a compaction recovery reminder. Clavain doesn't currently need this pattern (its SessionStart hook handles compact events directly via `additionalContext`), but the pattern is a general-purpose tool for future cross-hook coordination.

## The Pattern

```
Hook A (early event) → write marker file → [time passes / event occurs] → Hook B (later event) → read marker → act → delete marker
```

### Properties

1. **Temporal decoupling**: Hook A and Hook B can fire minutes or hours apart
2. **One-shot consumption**: Delete the marker after reading — the action fires exactly once per trigger
3. **Crash-safe**: If Hook B never fires (session killed), stale markers accumulate. Add TTL cleanup.
4. **Filesystem is the state bus**: No database, no IPC, just a file existence check

### Implementation Template

**Hook A (writer):**
```bash
#!/usr/bin/env bash
MARKER_DIR="${HOME}/.local/state/my-feature"
mkdir -p "$MARKER_DIR"
echo "$(date +%s)" > "${MARKER_DIR}/pending"
```

**Hook B (reader):**
```bash
#!/usr/bin/env bash
MARKER="${HOME}/.local/state/my-feature/pending"
[[ -f "$MARKER" ]] || exit 0

# Act on the marker
timestamp=$(cat "$MARKER")
echo "Event detected (triggered at $timestamp). Taking action."

# One-shot: consume the marker
rm -f "$MARKER"
```

**TTL cleanup (in SessionStart or cron):**
```bash
find "${HOME}/.local/state/my-feature" -name 'pending' -mmin +120 -delete 2>/dev/null || true
```

## When to Use

- **Two hook events that can't share state directly** — PreCompact can't inject context (fires too early), but UserPromptSubmit can (fires on next user message)
- **Cross-session signaling** — SessionEnd writes a marker that the next SessionStart reads
- **Tool event → prompt event bridges** — PostToolUse writes state that UserPromptSubmit aggregates

## When NOT to Use

- **Same hook event**: If both writer and reader run in the same hook, pass state via variables or function returns
- **SessionStart handles the event directly**: Clavain's SessionStart fires on `startup|resume|clear|compact` and injects `additionalContext`. If the target event is one of these, use SessionStart directly — no marker needed
- **State needs to be queryable**: If multiple consumers need the state, or it needs to survive restarts, use `ic state` (intercore) or `bd set-state` (beads) instead of ephemeral marker files

## Clavain's Approach vs. This Pattern

Clavain's compaction recovery uses SessionStart's `additionalContext` injection on `_hook_source == "compact"` (session-start.sh:394). This works because Claude Code fires SessionStart with `source: "compact"` after compaction, and `additionalContext` is injected into the conversation — bypassing the stdout-injection bug (#15174) that post_compact_reminder works around.

The marker-file bridge is only necessary when:
1. The trigger event (Hook A) can't inject context itself
2. The injection event (Hook B) is a different hook type than the trigger

## Prior Art

- **post_compact_reminder** (iv-ewjom): PreCompact → `~/.local/state/claude-compact-reminder/compact-pending` → UserPromptSubmit. Core mechanism is ~20 lines of bash; ships with a 2938-line installer.
- **Clavain sentinel files** (`/tmp/clavain-heartbeat-*`, `/tmp/clavain-bead-*`): Similar filesystem-as-state-bus pattern, but for heartbeat signaling rather than event bridging. TTL cleanup added in session-start.sh (iv-1quv).
- **Clavain inflight-agents manifest** (`.clavain/scratch/inflight-agents.json`): SessionEnd writes agent state → SessionStart reads and consumes it. Same one-shot pattern, different purpose.
