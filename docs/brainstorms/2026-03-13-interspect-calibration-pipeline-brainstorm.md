---
artifact_type: brainstorm
bead: Sylveste-g3a
stage: discover
---
# Interspect Calibration Pipeline: Evidence → Routing Overrides

## What We're Building

Close the flywheel loop: make quality-gates agent verdicts flow into routing-calibration.json so future sprints automatically adjust which model tier each agent runs on. Today the pipeline is plumbed end-to-end but the evidence table has **zero `verdict_outcome` events** — the recording step in quality-gates (Step 5a) fails silently because `lib-interspect.sh` isn't being sourced or the discovery function can't find the plugin. This sprint fixes the broken link and upgrades the calibration output to v2 with source weighting and phase awareness.

## Why This Approach

The existing infrastructure is ~95% complete:
- `_interspect_record_verdict()` writes `verdict_outcome` events to SQLite
- `_interspect_compute_agent_scores()` aggregates scores from those events
- `_interspect_write_routing_calibration()` writes `routing-calibration.json`
- `lib-routing.sh` reads calibration data during model resolution (B3 path)

The gap is a **broken signal path**: quality-gates Step 5a attempts to source `lib-interspect.sh` via `_discover_interspect_plugin`, but in practice this discovery fails (empty `interspect_root`), so `_interspect_record_verdict` never fires. Additionally, the calibration schema is v1 (flat agent→model mapping) and needs v2 features.

## Key Decisions

### 1. Fix the verdict recording gap first
Rather than rebuilding the pipeline, **diagnose and fix why `_discover_interspect_plugin` returns empty** in the quality-gates context. The function looks for `hooks/lib-interspect.sh` in several paths — likely the plugin cache path differs from what the function expects. This is a 1-file fix.

### 2. Routing-calibration.json v2 schema
Add to the existing schema:
- **`source_weights`**: per-source multipliers (bootstrap sessions → 0.5x, self-building → 0.7x, normal → 1.0x)
- **`phase_scores`**: per-agent, per-phase hit rates (an agent might be good at plan-review but useless at quality-gates)
- **`min_non_bootstrap_sessions`**: threshold (20) before plugin/docs routing weights updated
- **`weighted_hit_rate`**: replaces raw `hit_rate` — accounts for source weights

### 3. Source classification for sessions
Add a `source` column to the sessions table (or derive from evidence):
- `bootstrap` — sessions from `source:bootstrap` or during initial setup
- `self-building` — sessions where the agent was building/modifying interspect itself
- `normal` — everything else

Classification logic: check bead metadata or session context for markers.

### 4. Shadow → enforce graduation path
Keep `calibration.mode: shadow` as default. Add a `calibration.enforce_threshold` in routing.yaml (default: 20 non-bootstrap sessions). When threshold is met, `/calibrate` prompts to switch to enforce mode. No automatic mode switch.

### 5. Verdict recording moves to PostToolUse hook
Instead of relying on quality-gates skill text to source the library and call the function, **enhance `interspect-evidence.sh` (PostToolUse hook)** to detect verdict JSON files in `.clavain/verdicts/` after quality-gates runs. This is more reliable than depending on skill text execution.

Actually — the PostToolUse hook fires on Task tool use. Quality-gates writes verdicts to files, then the synthesis agent reads them. The more robust path is: keep the existing approach but fix the discovery function. The PostToolUse hook can serve as a backup check.

**Decision: Fix discovery + add a backup sweep in the SessionStart hook that checks for unrecorded verdicts from the previous session.**

## Open Questions

1. **Phase awareness granularity**: Should phase scores be `plan-review` vs `quality-gates` (2 phases where agents run), or finer-grained per sprint step?
   → Recommendation: Just 2 phases. Agents only run in plan-review and quality-gates contexts. Finer granularity has no signal.

2. **Self-building session detection**: How to reliably detect that a session was modifying interspect itself?
   → Recommendation: Check if the sprint bead has `[interspect]` prefix in title or if changed files include `interverse/interspect/`. Can be derived from git diff at session end.

3. **Backfill from existing verdicts**: The `.clavain/verdicts/` directory has 5 verdict JSON files from previous quality-gates runs. Should we backfill these?
   → Recommendation: Yes, one-time backfill script. Small enough to do manually.
