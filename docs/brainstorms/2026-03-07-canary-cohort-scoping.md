---
artifact_type: brainstorm
bead: iv-f7gsz
---
# Brainstorm: Canary Cohort Scoping & Overlap Blocking

**Bead:** iv-f7gsz — [interspect] Scope canary baselines and samples to routing cohorts and block confounded overlap

---

## Problem

Interspect canaries measure the effect of routing overrides (e.g., "switch fd-safety from Sonnet to Haiku"). But baselines and samples are computed from **all sessions globally** — no filtering by agent, model, phase, or project. This means:

1. **Baselines are diluted.** A canary for fd-safety computes its baseline from sessions where fd-safety may not have run at all, or ran on a different model.
2. **Samples are confounded.** During monitoring, all sessions contribute samples regardless of whether the routing override affected them.
3. **Overlapping canaries are unattributable.** If two overrides are active simultaneously (fd-safety→Haiku and fd-correctness→Opus), neither canary can isolate its own effect. Current behavior: advisory note only ("N other overrides active"), no blocking.

**Acceptance criteria from bead:** Canary verdicts are cohort-scoped and overlapping-confounded canaries are blocked or explicitly downgraded to advisory.

---

## Current Architecture

### Schema (SQLite in `.clavain/interspect/interspect.db`)

**canary table:** `id, file, commit_sha, group_id, applied_at, window_uses, uses_so_far, window_expires_at, baseline_override_rate, baseline_fp_rate, baseline_finding_density, baseline_window, status, verdict_reason`

- `group_id` = agent name (e.g., "fd-safety")
- No cohort, model, phase, or project context

**canary_samples:** `id, canary_id, session_id, ts, override_rate, fp_rate, finding_density`

- `UNIQUE(canary_id, session_id)` — one sample per session per canary
- No cohort filtering — ALL sessions generate samples for ALL active canaries

**sessions:** `session_id, start_ts, end_ts, project, run_id`

- No agent, model, phase, category, or complexity columns

**evidence:** `id, ts, session_id, seq, source, source_version, event, override_reason, context, project, project_lang, project_type`

- `source` = agent name; `context` JSON may contain `subagent_type` but not model
- No first-class model or cohort column

### Key Functions

| Function | Location (lib-interspect.sh) | Scope Issue |
|----------|------------------------------|-------------|
| `_interspect_compute_canary_baseline` | ~line 1714 | Filters by project only, always called with empty string |
| `_interspect_record_canary_sample` | ~line 1795 | Records samples from ALL sessions into ALL active canaries |
| `_interspect_evaluate_canary` | ~line 1854 | Computes avg metrics across all samples, notes overlap but doesn't block |
| `_interspect_apply_routing_override` | ~line 930 | Creates canary at apply time, passes `""` as project filter |

### What Defines a Routing Cohort

From `routing.yaml`, a routing decision is determined by:
- **Agent name** (e.g., fd-safety, fd-correctness)
- **Model** resolved from: agent override > complexity tier > phase default > global default
- **Complexity tier** (C1-C5)
- **Phase** (brainstorm, executing, etc.)

A **cohort** = the set of sessions where the same agent ran on the same model. The override changes the model for a specific agent — the canary should only compare sessions within that agent's cohort.

---

## Gap Analysis

| Gap | Severity | Root Cause |
|-----|----------|------------|
| Baseline not agent-scoped | HIGH | `_interspect_compute_canary_baseline` doesn't filter by agent |
| Samples not agent-scoped | HIGH | `_interspect_record_canary_sample` writes to all active canaries |
| No model context in sessions | HIGH | Sessions table lacks model/agent columns |
| No overlap blocking | MEDIUM | Only advisory note at verdict time |
| No cohort ID concept | HIGH | Neither canary nor sessions table has cohort identity |
| `subagent_type` in context JSON but not indexed | LOW | Available but not queryable for filtering |

---

## Proposed Solution

### Approach: Agent-Scoped Filtering (Minimal Viable Cohort)

Full cohort scoping (agent + model + phase + complexity) requires routing-context propagation that doesn't exist yet. But **agent-scoping** is achievable now — `group_id` already stores agent name, and `evidence.source` stores agent name. This gives us 80% of the value with 20% of the effort.

### Schema Changes

**canary table — add columns:**
```sql
ALTER TABLE canary ADD COLUMN project TEXT DEFAULT '';
ALTER TABLE canary ADD COLUMN cohort_key TEXT DEFAULT '';
-- cohort_key = "agent:project" or "agent:*" for global
-- Computed at creation time, used for overlap detection
```

**canary_samples — add column:**
```sql
ALTER TABLE canary_samples ADD COLUMN matched_agent INTEGER DEFAULT 1;
-- 1 if session produced evidence from this canary's agent, 0 if not
-- Allows filtering without breaking existing samples
```

No sessions table changes needed — we filter via evidence.source (agent name) joined against session_id.

### Function Changes

**1. `_interspect_compute_canary_baseline(before_ts, project, agent)`**

Add agent filter parameter. When non-empty:
- Only count sessions that have ≥1 evidence event with `source = $agent`
- Only count overrides/fp/findings from events with `source = $agent`
- Baseline becomes: "what was the override rate for fd-safety specifically, across sessions where fd-safety ran?"

SQL change:
```sql
-- Current (global):
SELECT COUNT(DISTINCT session_id) FROM evidence WHERE ts < $before_ts

-- Proposed (agent-scoped):
SELECT COUNT(DISTINCT session_id) FROM evidence
WHERE ts < $before_ts AND source = $agent
```

**2. `_interspect_record_canary_sample(session_id)`**

Filter samples per canary's agent:
```sql
-- Current: counts ALL evidence for the session
SELECT COUNT(*) FROM evidence WHERE session_id = $sid AND event IN (...)

-- Proposed: counts evidence for THIS canary's agent only
SELECT COUNT(*) FROM evidence
WHERE session_id = $sid AND source = $canary_agent AND event IN (...)
```

If the session has zero evidence events for this canary's agent, set `matched_agent = 0` and still record (preserves denominator accuracy), OR skip the sample entirely (simpler, slightly less precise).

**Recommendation:** Skip the sample. A session where fd-safety didn't run tells us nothing about fd-safety's override.

**3. `_interspect_check_overlap(agent, project)` — NEW**

Before creating a new canary, check for conflicting active canaries:

```bash
_interspect_check_overlap() {
    local agent="$1" project="${2:-}"
    local db="$(_interspect_db_path)"

    # Check 1: Same agent already has active canary
    local same_agent
    same_agent=$(sqlite3 "$db" "SELECT id, file FROM canary
        WHERE group_id = '$agent' AND status = 'active' LIMIT 1")
    if [[ -n "$same_agent" ]]; then
        echo "BLOCK|same_agent|Canary #${same_agent%%|*} already active for $agent"
        return 1
    fi

    # Check 2: Different agent in same project (advisory, not blocking)
    local other_agents
    other_agents=$(sqlite3 "$db" "SELECT COUNT(*) FROM canary
        WHERE status = 'active' AND group_id != '$agent'
        AND (project = '$project' OR project = '')")
    if (( other_agents > 0 )); then
        echo "WARN|other_agents|$other_agents other canary(ies) active in overlapping scope"
        return 0  # Advisory, not blocking
    fi

    echo "OK"
    return 0
}
```

**Blocking policy:**
- Same agent → BLOCK (cannot attribute effect if same agent has two concurrent overrides)
- Different agent, same project → WARN (downgrade verdict confidence)
- Different agent, different project → OK (no overlap)

**4. `_interspect_evaluate_canary` — enhance verdict**

After computing metrics, annotate verdict with:
- Cohort key used for filtering
- Number of matched vs total sessions (cohort coverage)
- Overlap status at evaluation time (was another canary active during monitoring?)

### Integration Points

**Override apply (`_interspect_apply_routing_override`):**
1. Extract agent name from override file
2. Call `_interspect_check_overlap(agent, project)` — block or warn
3. Pass agent to `_interspect_compute_canary_baseline(ts, project, agent)`
4. Store `cohort_key` and `project` on canary row

**Session end (`_interspect_record_canary_sample`):**
1. For each active canary, check if session has evidence from that canary's agent
2. Skip sample if no matching evidence (session is outside this canary's cohort)

**Status display:**
1. Show cohort key and coverage (e.g., "fd-safety: 12/20 sessions matched")
2. Surface overlap warnings

---

## Alternatives Considered

### Full Cohort (agent + model + phase + complexity)

**Pros:** Most precise attribution. Canary for "fd-safety on Haiku in brainstorm phase" would only compare against that exact cohort.

**Cons:** Requires routing context propagation into evidence/sessions tables. The routing resolution happens in `lib-routing.sh` (bash) which doesn't currently emit model decisions as evidence events. Would need intercore routing decision capture (iv-godia, now shipped) to provide the data. Huge scope increase.

**Verdict:** Defer to Phase 2. Agent-scoping gets 80% of the value. Model-scoping requires plumbing that exists (iv-godia) but isn't integrated into interspect yet.

### Project-Only Filtering

**Pros:** Simplest change — just pass `project` to existing baseline function.

**Cons:** Doesn't address the main confounding issue (agent attribution). Two different agents in the same project still get mixed baselines.

**Verdict:** Insufficient. Project filtering is easy and should be included, but agent filtering is the real fix.

### Temporal Deconfliction (Sequential Canaries)

**Pros:** Force canaries to run one at a time. No overlap = no attribution problem.

**Cons:** Too restrictive. Can't monitor two independent agents (fd-safety and fd-correctness) simultaneously, even though they affect different code paths.

**Verdict:** Too coarse. Same-agent blocking + different-agent warning is the right granularity.

---

## Validation Criteria

1. **Agent-scoped baseline:** `_interspect_compute_canary_baseline("2026-03-07", "", "fd-safety")` returns metrics computed only from sessions where fd-safety ran
2. **Agent-scoped samples:** A session where only fd-correctness ran produces no sample for an fd-safety canary
3. **Same-agent overlap blocked:** Attempting to create a second canary for fd-safety while one is active fails with error
4. **Cross-agent overlap warned:** Creating a canary for fd-correctness while fd-safety canary is active succeeds with warning in verdict
5. **Status shows cohort:** `/interspect:status` displays cohort key and matched session count per canary
6. **Backward compatible:** Existing canary rows (no cohort_key) continue to work with global scope

---

## Scope Estimate

- **Schema migration:** 2 ALTER TABLE statements + migration function
- **Baseline refactor:** ~30 lines changed in `_interspect_compute_canary_baseline`
- **Sample filtering:** ~20 lines changed in `_interspect_record_canary_sample`
- **Overlap check:** ~40 lines new function
- **Integration:** ~15 lines in `_interspect_apply_routing_override`
- **Status update:** ~10 lines in `_interspect_get_canary_summary`
- **Tests:** Manual validation (bash functions, no unit test framework)

**Total:** ~120 lines changed/added across `lib-interspect.sh`. Single-file change. No cross-module dependencies.
