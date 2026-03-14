---
artifact_type: brainstorm
bead: Demarch-g4ja
stage: discover
---

# Wiring Interspect Hooks to Interrank Routing Tools

## The Problem

Three systems exist in isolation:

1. **Interspect** collects evidence about agent performance (PostToolUse hook → SQLite), detects patterns, and writes routing proposals to `.claude/routing-overrides.json`. Nobody reads this file at routing time.

2. **Clavain lib-routing.sh** resolves which model to use for each subagent via a B1→B2→B3 cascade (static routing.yaml → complexity routing → calibration file). It reads routing.yaml and routing-calibration.json, but not routing-overrides.json.

3. **Interrank** exposes MCP tools (`resolve_routing_name`, `routing_compare`) that return domain scores, cost data, and model family metadata from AgMoDB snapshots. Nobody calls these at routing decision time.

The feedback loop that makes "the system learns" work requires connecting all three: interspect proposes → interrank validates → lib-routing.sh applies.

## Current Architecture

```
Evidence collection (works):
  PostToolUse hook → interspect.db → /interspect:propose → routing-overrides.json

Routing resolution (works, but blind):
  lib-routing.sh → routing.yaml → routing-calibration.json → model choice
  (does NOT read routing-overrides.json)
  (does NOT call interrank)

Model scoring (works, but unused):
  interrank MCP → resolve_routing_name → domain scores, cost, speed
  (nobody calls this at routing time)
```

## Five Gaps to Close

### Gap 1: Override consumption (critical)
lib-routing.sh `routing_resolve_model()` doesn't read `.claude/routing-overrides.json`. Interspect writes exclusions and model recommendations, but they have no effect on actual routing. This is the most impactful gap — fixing it alone would make interspect overrides functional.

**Fix:** Add a read step in `routing_resolve_model()` between the per-agent override check (B1) and the phase lookup. If an override with `action: exclude` matches the current agent, skip it. If `action: propose` with `status: approved`, use the `recommended_model`.

### Gap 2: Interrank at decision time (valuable but optional)
No MCP call to interrank during routing resolution. lib-routing.sh resolves "sonnet" or "opus" as abstract tier names without knowing their actual performance characteristics, cost, or speed.

**Fix options:**
- **A (Reactive):** Call `resolve_routing_name` during `routing_resolve_model()`. Adds ~500ms per decision. Too slow for per-subagent routing.
- **B (Proactive, recommended):** Call interrank once during `_routing_load_cache()` to build a model-family lookup table. Zero latency at decision time. Table maps tier names to domain scores and cost.
- **C (Hybrid):** Use cached scores at decision time, refresh via background task every 5 min.

### Gap 3: Calibration validation
Interspect proposes calibrations based on evidence (agent X underperforms → recommend model downgrade). Currently, proposals are validated only by counting rules (N dismissals → propose exclusion). Interrank could validate: "is haiku actually capable enough for this agent's domain?" before the override is applied.

**Fix:** In `/interspect:approve`, before converting a proposal to active, call `resolve_routing_name` for the proposed model and check its domain scores against the agent's declared capability requirements.

### Gap 4: Routing decision feedback
Routing decisions are not recorded as interspect evidence. After choosing model X for agent Y, there's no record of whether that choice was good until the agent's output is reviewed (which may not happen).

**Fix:** Add a lightweight event: after `routing_resolve_model()` returns, write a `routing_decision` event to interspect.db with agent name, chosen model, decision source (B1/B2/B3), and confidence.

### Gap 5: Override scope and TTL
Overrides in routing-overrides.json have no expiration. An exclusion created 3 weeks ago may no longer be valid (the agent may have been updated, the project domain may have shifted).

**Fix:** Add `expires_at` to override entries. lib-routing.sh ignores expired overrides. `/interspect:status` warns about stale overrides.

## Recommended Approach: Gap 1 First

Gap 1 (override consumption) is the highest leverage, lowest risk change. It makes the existing interspect → override pipeline functional without adding new dependencies. The other gaps build on this foundation.

**Implementation scope for Gap 1:**
- Edit: `os/Clavain/scripts/lib-routing.sh` — add `_routing_read_overrides()` function
- Read: `.claude/routing-overrides.json` (already created by interspect)
- Apply: exclusions (skip agent) and model recommendations (override tier)
- Validate: schema check, handle missing/malformed file gracefully
- Test: existing routing smoke tests + new override-specific tests

**Estimated complexity:** 2/5 (simple). The override file format exists, the routing function has clear extension points, and the change is additive (no existing behavior changes unless overrides are present).

## What This Unblocks

With Gap 1 closed:
- `/interspect:propose` + `/interspect:approve` actually changes routing behavior
- The manual feedback loop works end-to-end: evidence → propose → approve → route differently
- CUJ "Multi-Agent Code Review" success signal "Interspect adjusts routing based on review outcomes" becomes testable (currently marked "planned")

With Gaps 1-4 closed:
- Full measurement → evidence → calibration → routing → measurement cycle
- Automated calibration (Phase 2) becomes possible because the plumbing exists
- Cost-per-landable-change metric can incorporate routing efficiency data

## Open Questions

1. **Performance:** Should `_routing_read_overrides()` cache the file or read fresh each call? lib-routing.sh already reads routing-calibration.json fresh each call (line 562-590), so same pattern.
2. **Conflict resolution:** If routing.yaml says "sonnet" but routing-overrides.json says "haiku" for the same agent, which wins? Override should win (more recent, evidence-based) but needs a clear precedence rule.
3. **Scope:** Should overrides apply globally or per-project? Current file is project-local (`.claude/routing-overrides.json`). Global overrides would need a different location.
4. **Interrank dependency:** Gap 2 makes interrank a runtime dependency for routing. If interrank MCP is down, routing must still work. Fallback to static routing.yaml is essential.
