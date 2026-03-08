---
artifact_type: plan
bead: iv-f7gsz
stage: done
---
# Plan: Canary Cohort Scoping & Overlap Blocking

**Bead:** iv-f7gsz | **Brainstorm:** [docs/brainstorms/2026-03-07-canary-cohort-scoping.md](../brainstorms/2026-03-07-canary-cohort-scoping.md)

---

## Goal

Scope interspect canary baselines and samples to agent-level cohorts, and block overlapping same-agent canaries. Single-file change in `interverse/interspect/hooks/lib-interspect.sh`.

## Tasks

### Task 1: Schema migration — add cohort columns
**File:** `interverse/interspect/hooks/lib-interspect.sh` (in `_interspect_ensure_schema`)
**Action:**
- Add `project TEXT DEFAULT ''` and `cohort_key TEXT DEFAULT ''` columns to `canary` table
- Use `ALTER TABLE ... ADD COLUMN` with `IF NOT EXISTS` pattern (or trap error for SQLite <3.37)
- `cohort_key` format: `"agent:project"` or `"agent:*"` for project-unscoped

- [x] Columns added to schema migration
- [x] Existing canary rows unaffected (defaults preserve backward compat)

### Task 2: Agent-scoped baseline computation
**File:** `interverse/interspect/hooks/lib-interspect.sh` (`_interspect_compute_canary_baseline`)
**Action:**
- Add third parameter `agent` (optional, default empty = global fallback)
- When `agent` is non-empty: filter evidence queries to `source = $agent`
- Session count: only sessions with ≥1 evidence event from `source = $agent`
- Override/fp/finding counts: only events from `source = $agent`
- SQL parameterization: use shell variable interpolation with proper escaping (existing pattern in file)

- [x] Function signature extended with `agent` parameter
- [x] SQL queries filter by `source = $agent` when non-empty
- [x] Empty agent falls back to global behavior (backward compat)

### Task 3: Agent-scoped sample recording
**File:** `interverse/interspect/hooks/lib-interspect.sh` (`_interspect_record_canary_sample`)
**Action:**
- For each active canary, read `group_id` (agent name)
- Before computing sample metrics, check if session has evidence from this agent: `SELECT COUNT(*) FROM evidence WHERE session_id = $sid AND source = $agent`
- If zero: skip this canary (session is outside its cohort)
- If non-zero: compute metrics filtered to `source = $agent`

- [x] Sample recording checks for agent presence in session
- [x] Sessions without matching agent evidence are skipped
- [x] Metrics computed per-agent, not globally

### Task 4: Overlap detection function
**File:** `interverse/interspect/hooks/lib-interspect.sh` (new function)
**Action:**
- Add `_interspect_check_canary_overlap(agent, project)` function
- Same agent + active canary → return `BLOCK` with error message
- Different agent + same project → return `WARN` (advisory)
- No overlap → return `OK`

- [x] Function implemented
- [x] Same-agent overlap returns BLOCK
- [x] Cross-agent overlap returns WARN

### Task 5: Wire overlap check + agent filter into override apply
**File:** `interverse/interspect/hooks/lib-interspect.sh` (`_interspect_apply_routing_override`)
**Action:**
- Before canary creation (~line 1017): call `_interspect_check_canary_overlap`
- If BLOCK: abort override apply with error message
- If WARN: proceed but append warning to canary's `verdict_reason`
- Pass agent name to `_interspect_compute_canary_baseline(ts, project, agent)`
- Store `cohort_key` and `project` in canary INSERT

- [x] Overlap check called before canary creation
- [x] BLOCK prevents canary creation
- [x] WARN recorded but doesn't block
- [x] Agent name passed to baseline computation
- [x] cohort_key stored on canary row

### Task 6: Enhance verdict with cohort context
**File:** `interverse/interspect/hooks/lib-interspect.sh` (`_interspect_evaluate_canary`)
**Action:**
- Include cohort_key in verdict JSON output
- Report matched sessions vs total sessions ("fd-safety: 12/20 matched")
- Upgrade overlap note from generic count to listing affected agents

- [x] Verdict includes cohort_key
- [x] Verdict shows matched/total session ratio
- [x] Overlap note lists specific conflicting agents

## Sequence

Tasks 1-3 are sequential (schema → baseline → samples).
Task 4 is independent.
Task 5 depends on Tasks 1-4.
Task 6 depends on Tasks 1-3.

## Verification

- [x] Baseline with agent filter returns different values than global baseline (verify with sqlite3 query)
- [x] Session without fd-safety evidence produces no sample for fd-safety canary
- [x] Attempting second canary for same agent while one is active → blocked with error
- [x] Cross-agent canary in same project → created with warning
- [x] `/interspect:status` shows cohort key and match ratio
- [x] Existing canaries (no cohort_key) continue to work with global fallback
