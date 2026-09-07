---
bead: sylveste-b49
title: "Plan: Durable reflect & compound"
date: 2026-03-29
type: plan
---

# Plan: Durable Reflect & Compound

## Summary

Rewrite reflect.md and compound.md to produce durable behavioral changes instead of standalone files. Update sprint.md Step 9/10 gates. 3 files changed, no Go code changes needed.

## Design: Learning Router

The core concept is a **learning router** — instead of "write a reflection file," the agent extracts learnings and routes each one to its durable target:

| Target | When to use | How |
|--------|------------|-----|
| `CLAUDE.md` / `AGENTS.md` | Project-level gotchas, conventions, tool behaviors | Append to relevant section |
| Auto-memory | Cross-project user preferences, workflow patterns | Write memory file + MEMORY.md entry |
| Code comment | Implementation-specific gotcha near the fix site | Add inline comment |
| Config change | Default values, thresholds, feature flags | Edit config file |
| Hook rule | Behavioral enforcement (prevent mistake from recurring) | Suggest `/hookify` |
| `PHILOSOPHY.md` | Design principle insights | Append to relevant section |

Classification heuristic:
- "Don't do X when Y" → CLAUDE.md or hook
- "Tool X behaves unexpectedly when Y" → CLAUDE.md gotcha or code comment
- "User prefers X over Y" → auto-memory
- "The design should prioritize X" → PHILOSOPHY.md
- "We learned that the code at path P has issue I" → code comment at P

## Tasks

### Task 1: Rewrite reflect.md (F1)
**Bead:** sylveste-62i
**File:** `os/Clavain/commands/reflect.md`
**Changes:**

Replace Step 3 ("Capture learnings") with a learning router:

**New Step 3: Extract and route learnings**

1. Extract 1-5 learnings from the sprint conversation. For each, produce:
   - `learning`: 1-2 sentence description
   - `target`: one of `claude-md`, `agents-md`, `memory`, `code`, `hook`, `philosophy`
   - `location`: specific file path or section
   - `content`: the exact text to write

2. For each learning, write to the target:
   - `claude-md`: Read the project CLAUDE.md, find the relevant section, append the learning. If no section fits, add to a `## Sprint Learnings` section.
   - `agents-md`: Same pattern for AGENTS.md.
   - `memory`: Write a memory file with proper frontmatter, update MEMORY.md index.
   - `code`: Add a comment at the specified location using Edit tool.
   - `hook`: Suggest the hook rule and offer to run `/hookify`. Do NOT auto-create hooks.
   - `philosophy`: Append to PHILOSOPHY.md in the relevant section.

3. After writing, display a summary:
   ```
   Durable changes:
   - [target] location: learning summary
   - [target] location: learning summary
   ```

**Replace Step 4** ("Register artifact") with:
- Register the list of changes as the reflection artifact (as a JSON string in bd state, not a file path)
- Format: `clavain-cli set-artifact "<sprint_id>" "reflection" "durable:<N>-changes"`
- This satisfies the artifact existence check without needing a standalone file

**Keep Steps 1-2, 5-9 unchanged.** Transcript export, drift check, cost calibration, and routing calibration remain as-is.

**Remove:** The `clavain:engineering-docs` invocation for C3+. All complexities use the same learning router. The 7-step engineering-docs workflow is excessive for sprint learnings.

**Remove:** The `docs/reflections/` output path. No standalone reflection files.

**Remove:** The frontmatter requirement (`artifact_type: reflection`). No file is produced.

**Keep:** C1-C2 can still write a brief memory note if the only learning is a complexity calibration adjustment.

### Task 2: Rewrite compound.md (F2)
**Bead:** sylveste-zba
**File:** `os/Clavain/commands/compound.md`
**Changes:**

Replace Step 2 ("Capture the solution" via engineering-docs) with targeted patching:

**New Step 2: Route the solution to point of use**

1. Identify what was learned:
   - `root_cause`: What caused the problem
   - `fix_site`: Where the fix was applied (file:line)
   - `prevention`: How to avoid it in future

2. Route to the most useful target:
   - If `fix_site` is a code file: add a code comment at the fix explaining the gotcha
   - If the prevention is a project-wide rule: append to CLAUDE.md or AGENTS.md
   - If the prevention is a behavioral pattern: suggest `/hookify`
   - If the problem spans multiple projects: write auto-memory

3. Optionally: if the problem is complex enough (> 3 investigation steps), also write a `docs/solutions/` file as archive. But the primary output is always the durable change.

**Keep Step 1** (cass search for similar past sessions).

**Remove:** The `clavain:engineering-docs` invocation. Compound no longer delegates to the 7-step workflow.

### Task 3: Update sprint.md gates (F3)
**Bead:** sylveste-jh1
**File:** `os/Clavain/commands/sprint.md`
**Changes:**

**Step 9 (Reflect):** No change needed — it just invokes `/reflect` which now uses the learning router.

**Step 10 (Ship) — Reflect gate:**

Replace the current gate:
```bash
# OLD: Check for reflection file with >= 3 lines
reflect_artifact=$(clavain-cli get-artifact "$CLAVAIN_BEAD_ID" "reflection" 2>/dev/null)
body_lines=$(awk ... "$reflect_artifact")
```

With:
```bash
# NEW: Check for durable changes
reflect_artifact=$(clavain-cli get-artifact "$CLAVAIN_BEAD_ID" "reflection" 2>/dev/null)
if [[ "$reflect_artifact" == durable:* ]]; then
    # Learning router ran, check change count
    change_count="${reflect_artifact#durable:}"
    change_count="${change_count%-changes}"
    if [[ "$change_count" -ge 1 ]]; then
        echo "Reflect gate: $change_count durable changes recorded"
    else
        echo "ERROR: Reflect produced 0 durable changes. Run /reflect again." >&2
        exit 1
    fi
elif [[ -f "$reflect_artifact" ]]; then
    # Backward compatible: old-style reflection file still accepted
    body_lines=$(awk 'BEGIN{fm=0; count=0} /^---$/{fm++; next} fm>=2 && /[^ \t]/{count++} END{print count}' "$reflect_artifact")
    [[ "$body_lines" -lt 3 ]] && { echo "ERROR: Reflect artifact too short" >&2; exit 1; }
else
    echo "ERROR: No reflect artifact. Run /reflect first." >&2
    exit 1
fi
```

This is backward-compatible: old reflection files still pass the gate, but new durable changes are the preferred path.

**`recent-reflect-learnings` in bootstrap:** This is Go code in `clavain-cli`. For now, leave it reading reflection files — it still works for old beads. Future iteration can read CLAUDE.md commit history instead.

## Execution Order

Task 1 (reflect.md) → Task 3 (sprint.md gate) → Task 2 (compound.md)

Task 1 is the critical path. Task 3 must be updated to accept the new artifact format before the next sprint. Task 2 is lower priority and can land separately.

## Risk

- **Learning router quality depends on the agent's judgment** — classification of "where does this learning go" is inherently subjective. Mitigation: provide clear heuristics in the command, review the first few runs manually.
- **CLAUDE.md bloat** — if every sprint appends learnings, CLAUDE.md grows unbounded. Mitigation: add a note that learnings should be integrated into existing sections when possible, not always appended.
