---
artifact_type: flux-drive-findings
reviewer: flux-drive-architecture
bead: sylveste-4ct0
plan: docs/plans/2026-04-27-clavain-peer-coexistence-A.md
manifest: docs/plans/2026-04-27-clavain-peer-coexistence-A.exec.yaml
date: 2026-04-27
verdict: conditional-approve  # one P1 blocks auto-approve; see findings
---

# Flux-Drive Architecture Review — Clavain Peer-Coexistence Plan (A scope)

## Severity Summary

- P0: 0
- P1: 3
- P2: 2
- P3: 1

Auto-approve gate: BLOCKED by P1s. Resolve findings F2, F3, F5 before execution.

---

## P1 Findings

### F2 — Task 6: F6 hook registration targets wrong file

**Location:** `docs/plans/2026-04-27-clavain-peer-coexistence-A.md` Task 6 Step 4; manifest `task-6` file list.

**Finding:** The plan instructs adding a `"hooks"` array to `os/Clavain/.claude-plugin/plugin.json`. That file has no `hooks` key and the Claude Code plugin system does not read hooks from it. All Clavain hooks are registered in `os/Clavain/hooks/hooks.json` using the `{matcher, hooks:[{type, command, async}]}` format confirmed in the live file. If the executor follows the plan as written, `peer-telemetry.sh` will never fire at session start — the hook is silently unregistered.

**Why the verify doesn't catch it:** The Task 6 `<verify>` block only checks `test -x peer-telemetry.sh` and runs `test-peer-coexistence.sh`, which invokes the hook directly via `bash`. The formal verify passes even when registration is wrong. The failure only surfaces at Task 8 CUJ step 5 ("verify peer-telemetry.jsonl gained one line during the session"), which requires a fresh Claude Code session with no guidance on what to look for when it fails.

**Fix:** Replace `os/Clavain/.claude-plugin/plugin.json` with `os/Clavain/hooks/hooks.json` in both the Task 6 Step 4 instruction and the manifest `task-6` files list. The registration entry should follow the existing SessionStart pattern:

```json
{
  "matcher": "startup|resume|clear|compact",
  "hooks": [
    {
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/peer-telemetry.sh",
      "async": true
    }
  ]
}
```

`async: true` is required — omitting it would cause peer-telemetry.sh to block session startup. The existing `session-start.sh` entry uses `async: true` for the same reason.

**Add to Task 6 verify:**
```
- run: jq -e '.hooks.SessionStart | map(.hooks[]?.command) | any(contains("peer-telemetry.sh"))' os/Clavain/hooks/hooks.json
  expect: exit 0
```

---

### F3 — Task 5 manifest missing dependency on task-3

**Location:** `docs/plans/2026-04-27-clavain-peer-coexistence-A.exec.yaml` task-5 `depends` field.

**Finding:** `peers.md` (F4) instructs the agent to run `modpack-install.sh --dry-run --quiet --category=peers`. That category becomes valid only after task-3 (F2) adds the `peers` case to `process_category()` and the `--category=` allowlist. The current manifest has `task-5 depends: [task-2]` but not `task-3`. An executor treating the manifest as authoritative can start task-5 before task-3 completes. When that executor tests `/clavain:peers` before task-3 commits, the command exits with `{"error": "Unknown category: peers..."}`.

The Task 5 `<verify>` does not invoke `modpack-install.sh --category=peers` directly (the harness only checks that `peers.md` exists and contains "read-only"), so the per-task verify passes regardless. The gap only surfaces at Task 8.

**Fix:** Change `task-5 depends: [task-2]` to `task-5 depends: [task-2, task-3]`. This serializes task-5 after task-3, pulling it out of the four-way parallel block. The actual parallelism loss is minimal — task-4 and task-6 remain parallel; task-5 is documentation-only and fast once task-3 is done.

---

### F5 — Task 2 verify does not cover verify-config.sh update (false-PASS risk)

**Location:** `docs/plans/2026-04-27-clavain-peer-coexistence-A.md` Task 2 `<verify>` block.

**Finding:** The PRD acceptance criterion explicitly warns: "Peers are expected-present, not expected-disabled — the verifier must not report a false PASS by reading an empty `conflicts` list." The current `verify-config.sh` line 48 reads `.plugins.conflicts[]?.source`. After the F1 schema rename that key disappears; jq returns an empty string; `conf_total=0`; `conf_ok=0`; the script prints `0/0 disabled` and exits 0 — a silent false PASS on conflict detection.

The Task 2 `<verify>` block checks that `peers length >= 3`, `conflicts == null`, the superpowers disable line is gone, and the test harness passes. None of those four checks exercise `verify-config.sh` behavior. The test harness (`test-peer-coexistence.sh`) has no F1.x test case for verify-config at all.

**Fix (two parts):**

1. Add a verify-config test case to the harness in Task 2 Step 4:
```bash
# F1.6: verify-config.sh reads hard_conflicts, not conflicts (no false-PASS)
output=$(bash "$SCRIPT_DIR/verify-config.sh" 2>&1)
echo "$output" | grep -q "hard_conflicts\|hard conflicts" || fail "verify-config.sh not updated for hard_conflicts"
pass "F1.6 verify-config.sh reads hard_conflicts"
```
2. Add to Task 2 `<verify>`:
```
- run: grep -c "hard_conflicts" os/Clavain/scripts/verify-config.sh
  expect: contains "1"
```

This also closes the broader concern about detecting missed consumers: if the implementer runs the augmented harness before committing, a forgotten `verify-config.sh` edit fails F1.6 immediately.

---

## P2 Findings

### F1 — Wave 3 write contention on test-peer-coexistence.sh

**Location:** `docs/plans/2026-04-27-clavain-peer-coexistence-A.exec.yaml` Wave 3; `docs/plans/2026-04-27-clavain-peer-coexistence-A.md` Tasks 3, 5, 6.

**Finding:** Tasks 3, 5, and 6 all append test cases to `os/Clavain/scripts/test-peer-coexistence.sh` as their first step. The manifest places all three in Wave 3 with `max_parallel: 4`. If an executor runs them concurrently (which the manifest permits), all three writers race on the same file. Task 4 is the only Wave 3 task with no conflict on that file.

**Assessment:** This is a real conflict, not coincidental ordering. All three tasks include `os/Clavain/scripts/test-peer-coexistence.sh` in their manifest `files` list. The plan says "F3, F5, F6 are independent of F1/F2/F4 and can be implemented in any order or in parallel" but that independence is for feature logic — not for the shared test file.

**Practical impact:** The executing-plans skill runs tasks sequentially by default unless it detects explicit parallelism signals. With `max_parallel: 4`, a sophisticated executor could parallelize. The correct fix is narrow.

**Fix (minimal):** Extract the test-case append steps into a single "add remaining test cases" step at the start of whichever task runs first (task-3, since it's the only one with a hard dependency). Tasks 5 and 6 then skip the append step. Alternatively, accept sequential execution of tasks 3, 5, 6 and document that the test file is not parallelizable; only task-4 is truly parallel in Wave 3.

---

### F4 — Task 7 Step 2 grep produces confusing non-zero count

**Location:** `docs/plans/2026-04-27-clavain-peer-coexistence-A.md` Task 7 Step 2.

**Finding:** The instruction `grep -rn "Never create TODO files" .` is described as "Should be 0 matches outside generated/cache files." After the AGENTS.md edit, the phrase still appears in three committed files:

- `docs/plans/2026-04-27-clavain-peer-coexistence-A.md` (the plan itself, quoting the old text)
- `docs/prds/2026-04-27-clavain-peer-coexistence.md` (the PRD, quoting the old text)
- `docs/research/flux-research/ai-factory-work-orchestration-lessons/git-history-analyzer.md`

None of these are generated or cache files. An executor following Step 2 literally will see 3+ matches and may interpret this as verification failure and loop trying to remove a prohibition that doesn't need to be removed from those locations.

**Mitigation:** The formal `<verify>` block correctly scopes the check to `grep -c "Never create TODO files" AGENTS.md` — that check is safe. The Step 2 grep is informational only and will not block the formal verify.

**Fix:** Reword Step 2 to: `grep -rn "Never create TODO files" . --include="*.md" | grep -v "docs/plans/\|docs/prds/\|docs/research/"` — or simply remove Step 2 and rely on the verify block alone, since the verify already captures the only meaningful check.

---

## P3 Findings

### F6 — compound-engineering bridge_skill points to interop-with-superpowers

**Location:** `docs/plans/2026-04-27-clavain-peer-coexistence-A.md` Task 2 Step 1.

**Finding:** The `compound-engineering` peer entry has `"bridge_skill": "skills/interop-with-superpowers"`. The `interop-with-superpowers` skill documents Clavain's vocabulary overlap with obra/superpowers specifically. compound-engineering has distinct vocabulary and is described as "predecessor of several Clavain skills." The bridge_skill field is used by `/clavain:peers` to route users to methodology documentation — pointing compound-engineering users to the superpowers skill is misleading.

The F1.5 test (`all(.bridge_skill != null)`) passes regardless of which skill is referenced, so this is not caught by any test.

**Fix options (in order of cost):** (a) Accept the imprecision for A-scope and file a follow-up bead for a dedicated `interop-with-compound-engineering` skill in B-scope. (b) Add a stub `interop-with-compound-engineering/SKILL.md` as a third bridge skill in F3. The A-scope budget is tight so option (a) is appropriate — just note the known gap in the agent-rig.json comment.

---

## Other Observations (not blocking)

**Wave structure dependency correctness:** F1 → F2/F4 is correctly enforced. task-2 gates task-3 (F2) and task-5 (F4, after the P1 fix). task-4 (F3) and task-6 (F6) correctly depend only on task-1. task-7 (F5) is correctly independent. task-8 gates on all Wave 3 tasks plus task-7.

**F2 process_peers double-fill analysis:** No double-fill risk. Within a single script invocation, `process_peers()` is called exactly once — either via the `all` branch (after `process_category("hard_conflicts")`) or via the `peers` branch (routed through `process_category("peers")`). The test harness invokes the script as a subprocess per test case, so accumulator arrays are fresh per invocation.

**F6 telemetry capture point:** Session start is the correct choice. The hook reads `.plugins.peers[]?.source` from agent-rig.json rather than probing live plugin state. This means `peers_detected` lists configured peers from the rig file, not actually-installed plugins detected at runtime. The `using_skill_invoked: null` field is always null because the hook fires before any routing decision. This limitation is documented in the plan notes and is acceptable for A-scope; the field is a placeholder for B-scope refinement.

**F1 schema migration detection window:** If `verify-config.sh` is missed (the P1 finding above), the failure mode is "silent false PASS on conflict detection." There is no crash, no error, no failed test — just a health check that stops checking anything useful. The window for detection is the next time someone runs `verify-config.sh` and notices the 0/0 count. Adding the F1.6 test case (P1 fix above) closes this window to the Task 2 commit itself.

**Step 7 count in setup.md:** The plan says to update the "Conflicts disabled: [X/8 disabled]" count from 10 to 8. The live `setup.md` line 198 already reads `[X/8 disabled]`, so Task 3 Step 5 is a no-op. No change needed; no harm if the executor inspects and moves on.

**Task 7 (F5) AGENTS.md edit scope:** The plan correctly identifies both the "Conventions → Work tracking" paragraph and the `<!-- BEGIN BEADS INTEGRATION v:1 -->` block's Rules section as needing updates. The block's Rule 1 (`"Use bd for ALL task tracking — do NOT use TodoWrite..."`) contradicts the proposed softening. The plan addresses this but the `<verify>` block only checks AGENTS.md; it does not verify the BEADS INTEGRATION block was updated consistently. Low risk since both are in the same file and the executor reads the diff before committing.
