---
artifact_type: reflection
bead: sylveste-rsj.9
date: 2026-03-31
---

# Reflect: Discourse Fixative (rsj.9)

## What shipped

A discourse fixative mechanism that injects corrective context into reaction round prompts when pre-synthesis health metrics indicate discourse degradation. The fixative is a strict no-op when discourse is healthy — the sandalwood principle.

**New files (1):**
- `discourse-fixative.yaml` — trigger thresholds and injection texts

**Modified files (3):**
- `reaction-prompt.md` — `{fixative_context}` template slot
- `reaction.md` — Step 2.5.2b (health check, trigger evaluation, injection building)
- `reaction.yaml` — registered fixative in discourse config section

## Key design decisions

1. **Drift injection is unconditional.** The plan review (FX-002/FIX-02) caught that relevance cannot be estimated pre-synthesis — Findings Index titles don't contain file:line references. Rather than building a broken proxy, the drift injection ("anchor to file:line") fires whenever any fixative trigger activates. It's always useful and low-cost.

2. **Collapse fires at 2-of-2 strongest signals.** The review (FX-004/FIX-04) identified that all-three-simultaneously is too late — the individual injections are already active. Collapse fires when both Gini and novelty degrade, catching compound onset rather than full failure.

3. **All-severity Gini and novelty.** Both reviews (FX-001/FX-005) caught that P0/P1-only metrics miss real skew in lower severities. The fixative uses all collected findings (P0 + P1 + P2 when enabled) for both metrics.

4. **Missing config = disabled.** Explicit graceful degradation (FX-003): if `discourse-fixative.yaml` doesn't exist, the fixative is silently disabled.

## What went well

- The rsj.7 → rsj.9 pipeline is clean: rsj.7 shipped health monitoring, rsj.9 ships the mechanism that responds to it. Each bead has a single responsibility.
- The review caught the relevance proxy issue before implementation — would have been a subtle always-fire bug.

## Lessons learned

1. **Pre-synthesis metrics are inherently approximate.** The fixative operates before synthesis and therefore cannot access structured evidence data. Acknowledging this limitation (making drift unconditional rather than building a broken proxy) is better engineering than a false metric.
2. **The sandalwood principle is architecturally powerful.** A mechanism that is invisible when not needed and adds minimal overhead when active is a good pattern for optional pipeline stages.
3. **Review agent convergence on the same bug (relevance proxy) across architectural and correctness lenses gives high confidence.**

## Follow-up

- Monitor fixative activation rate across reviews — if it fires on >50%, thresholds may be too sensitive
- Phase 2: Adaptive thresholds via Interspect feedback loop
- Phase 2: Per-agent tailoring (different messages to dominant vs. quiet agents)
