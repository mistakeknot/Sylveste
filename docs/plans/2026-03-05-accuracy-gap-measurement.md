# Accuracy Gap Measurement Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-u74sq
**PRD:** docs/prds/2026-03-05-accuracy-gap-measurement.md
**Goal:** Fix interstat hook deployment, run synthetic benchmark, produce gap decomposition analysis.

---

### Task 1: Fix interstat hook deployment — publish missing PostToolUse hooks

**Files:**
- Edit: `interverse/interstat/hooks/hooks.json` (verify source has the entries — it does)
- Verify: `interverse/interstat/hooks/post-tool-all.sh` exists
- Verify: `interverse/interstat/hooks/post-tool-failure.sh` exists

**What to do:**
The source `hooks.json` already includes `PostToolUse:*` and `PostToolUseFailure` entries. The issue is that the published plugin doesn't include these files. Republish interstat:

```bash
cd interverse/interstat && ic publish --patch
```

After publish, verify the installed cache has the hooks:
```bash
ls ~/.claude/plugins/cache/interagency-marketplace/interstat/*/hooks/post-tool-all.sh
```

**Done when:** The hook files and hooks.json entries exist in the installed plugin cache.

**Note:** This requires restarting the Claude Code session for hooks to take effect. We can verify by checking file presence, but actual data collection starts next session.

---

### Task 2: Verify hook will collect data — dry-run test

**Files:**
- Read: `interverse/interstat/scripts/init-db.sh`

**What to do:**
Ensure the database schema supports `tool_selection_events` table. Run:
```bash
sqlite3 ~/.claude/interstat/metrics.db ".schema tool_selection_events"
```

If the table doesn't exist, run `bash interverse/interstat/scripts/init-db.sh`.

Then manually test the hook script with synthetic input:
```bash
echo '{"session_id":"test-123","tool_name":"Read","tool_input":{"file_path":"/tmp/test"},"tool_output":"file contents"}' | bash interverse/interstat/hooks/post-tool-all.sh
sqlite3 ~/.claude/interstat/metrics.db "SELECT COUNT(*) FROM tool_selection_events WHERE session_id='test-123'"
```

**Done when:** The test INSERT produces count=1. Clean up: `sqlite3 ~/.claude/interstat/metrics.db "DELETE FROM tool_selection_events WHERE session_id='test-123'"`

---

### Task 3: Generate tool-surface output for benchmark injection

**Files:**
- Read: `os/clavain/config/tool-composition.yaml`

**What to do:**
Capture the formatted output that the SessionStart hook injects:
```bash
/home/mk/.claude/plugins/cache/interagency-marketplace/clavain/0.6.144/bin/clavain-cli tool-surface 2>/dev/null
```

Save this output — it's the "with composition" context for the benchmark. Also note the character count for the results doc.

**Done when:** tool-surface output captured and saved to a temp variable/file for Task 4.

---

### Task 4: Run synthetic benchmark — 15 tasks with and without composition context

**Files:**
- Create: `docs/research/accuracy-gap-measurement-results.md`

**What to do:**
Run 15 tasks as subagents. For each task, dispatch TWO subagents:
- One with the tool-surface output prepended to its prompt
- One without

Each subagent gets a task prompt and must respond with which tool(s) it would use and in what order. It does NOT actually call the tools — it's a selection test.

**Task prompts and expected answers:**

**Discovery (domain/curation group awareness):**
1. "Which MCP tool would you use to search this codebase semantically for functions related to authentication?" → intersearch or tldr-swinton
2. "Which tool checks if project documentation has drifted from the code?" → interwatch
3. "Which tool shows what other Claude Code agents are currently active?" → intermux
4. "Which tool tracks token usage and costs for this session?" → interstat
5. "Which tool creates visual architecture diagrams from code structure?" → interchart

**Sequencing (ordering awareness):**
6. "You need to reserve files for editing. Which tools do you use and in what order?" → interpath first (resolve paths), then interlock (reserve)
7. "You need to review a plan file before executing a sprint. Which tools and order?" → interflux first (flux-drive review), then clavain (sprint execute)
8. "You need to set up token tracking before starting sprint work. Tools and order?" → interstat first (set-bead-context), then clavain (sprint)
9. "You need to check file reservations and then review the code. Tools and order?" → interlock first (my-reservations), then interflux (flux-drive)
10. "You need to generate docs from beads then check for drift. Tools and order?" → interpath first (artifact-gen), then interwatch (watch)

**Scale (ambiguous prompts — multiple valid answers):**
11. "Help me understand this codebase's architecture" → any of: tldr-swinton, intermap, serena, intersearch (all valid)
12. "Make sure everything looks good before shipping" → any of: interflux, clavain:verify, intercheck (all valid)
13. "Find where this function is called from" → any of: serena, tldr-swinton, intermap, grep (all valid)
14. "Document what we just built" → any of: interdoc, interpath, interkasten, clavain:compound (all valid)
15. "Coordinate my work with the other running agent" → any of: interlock, intermux, intercom (all valid)

**Scoring rubric:**
- Discovery: 1 point if agent names a correct tool from the expected set
- Sequencing: 1 point if correct tools AND correct order; 0.5 if correct tools wrong order
- Scale: 1 point if agent names ANY valid tool (control — composition shouldn't help here)

Run all 30 subagents (15 x 2 variants) in parallel where possible.

**Done when:** Raw scores collected and written to the results doc.

---

### Task 5: Analyze results and write gap decomposition

**Files:**
- Edit: `docs/research/accuracy-gap-measurement-results.md`

**What to do:**
Calculate per-category accuracy with and without composition:
- Discovery accuracy: with vs without (out of 5)
- Sequencing accuracy: with vs without (out of 5)
- Scale accuracy: with vs without (out of 5)
- Overall accuracy: with vs without (out of 15)

Write the analysis section:
1. Delta per category
2. Map to R3 dialectic bands (discovery/sequencing/scale)
3. Recommendation for iv-mtf12:
   - If discovery + sequencing delta > 30%: "Composition layer is valuable. Expand coverage."
   - If discovery delta > 30% but sequencing low: "Domain metadata works, sequencing hints need improvement."
   - If all deltas < 20%: "Gap is primarily scale-driven. Model improvements are the path forward."

**Done when:** Results doc has the scores table, analysis, and a clear recommendation for iv-mtf12.
