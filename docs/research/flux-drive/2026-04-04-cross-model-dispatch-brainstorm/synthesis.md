# Synthesis Report: Cross-Model Dispatch Brainstorm — Track C (Distant)

**Review Date:** 2026-04-04
**Document Under Review:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
**Track:** C — Distant domain structural isomorphisms
**Agents:** 4 launched, 4 completed, 0 failed
**Verdict:** PROCEED-WITH-CHANGES

---

## Executive Summary

The brainstorm's core design is sound: evidence-proportional resource allocation (expansion score → model tier) with cost guardrails (budget pressure) and non-negotiable safety floors. The A+C hybrid recommendation is implementable and captures the most important signals available at dispatch time.

The distant-domain review reveals four structural gaps that are **invisible from within the dispatch domain** because they require seeing the brainstorm as a member of a class of resource-allocation systems, not as a novel AI routing problem. None of the four gaps block implementation. Two are P1/borderline-P1 issues that should be resolved before shipping; two are P2 gaps that degrade quality gradually and can be addressed post-launch.

The single most important finding: **tier assignment operates on one axis (evidence strength) when two axes are required (evidence strength × domain reasoning complexity)**. This is the tameshigiri insight reinforced by the wayfinding signal-complexity finding and partially anticipated by the glassblowing grade-validity concern.

---

## Verdict by Agent

| Agent | Specialty | Status | Highest Severity | Key Finding |
|-------|-----------|--------|-----------------|-------------|
| fd-venetian-glass-grading | Grade validity, synthesis contamination | PROCEED-WITH-CHANGES | P1 | Expansion score not validated for adjacency transfer; findings not tier-weighted in synthesis |
| fd-han-salt-monopoly | Centralized failure modes, reinvestment | PROCEED-WITH-CHANGES | P1 | No fallback guard in `routing_adjust_expansion_tier`; savings not recycled |
| fd-polynesian-wayfinding | Signal independence, commitment model | NEEDS-REVISION | P1 | Correlated signals inflate score; score=1 downgrade inverts the right response to complexity |
| fd-japanese-sword-testing | Domain-difficulty compatibility, ceilings | PROCEED-WITH-CHANGES | P2 | Two-axis tier decision missing; no `max_model` ceiling |

---

## Critical Findings (P1 — Should Resolve Before Implementation)

### 1. Correlated Signals Inflate Expansion Score Without Independent Evidence
**Source:** fd-polynesian-wayfinding (P1)

The expansion_score accumulates contributions from multiple evidence types. If two contributions (e.g., P0 adjacency from fd-architecture + domain injection match for fd-decisions) trace to the same root finding, the score is inflated. The agent is dispatched at a higher tier than the independent evidence warrants.

This is the most architecturally significant gap the distant-domain review found. It is invisible from within the dispatch domain because the problem is about *signal provenance*, not *signal magnitude*. Wayfinding navigators triangulate — they require independent signals to confirm a reading. Expansion scoring currently sums without independence checking.

**Recommendation:** Add `trigger_source_id` to each expansion score contribution. Before finalizing the score, deduplicate contributions sharing the same source ID. The score becomes `min(sum_of_independent_contributions, 3)`. One deduplication pass in Step 2.2b. No architecture change.

---

### 2. No Fallback Guard in `routing_adjust_expansion_tier`
**Source:** fd-han-salt-monopoly (P1)

`routing_adjust_expansion_tier` is a centralized single point of failure. If it returns an empty string (new agent not in agent-roles.yaml, missing safety floor table entry, `case` fall-through in bash), the Stage 2 dispatch receives a malformed model parameter. Bash function failures often return empty output rather than non-zero exit codes — a silent misconfiguration.

**Recommendation:** Add a two-line guard after the safety floor call: if the return value is empty or not in `{haiku, sonnet, opus}`, fall back to `current_model` and emit a warning log. Converts silent misconfiguration into logged degradation.

```bash
[[ -z "$model" || ! "$model" =~ ^(haiku|sonnet|opus)$ ]] && {
  echo "[routing] WARN: adjust returned invalid '$model' for $agent, using $2" >&2
  model="$2"
}
```

---

### 3. Expansion Score Adjacency Transfer Is Unvalidated
**Source:** fd-venetian-glass-grading (P1)

Score=3 triggered by a domain-specific P0 (e.g., a Go type-system invariant violation) causes a non-adjacent agent to be dispatched at full sonnet/opus tier, even though the triggering finding has no valid transfer to that domain. The brainstorm's risk table acknowledges "finding quality degrades on haiku" as a risk but does not identify "phantom adjacency inflation" as a distinct failure mode.

**Recommendation:** In Step 2.2b, before writing `expansion_score`, check `trigger_finding_domain ∩ candidate_domain != ∅`. If intersection is empty, cap expansion tier at haiku regardless of score. This is a domain-overlap check, not a full adjacency validator — a one-line guard in the expansion scoring loop.

---

## Important Findings (P2 — Should Resolve in First Iteration)

### 4. Tier Assignment Is One-Dimensional — Domain Reasoning Complexity Is Missing
**Source:** fd-japanese-sword-testing (P2), reinforced by fd-polynesian-wayfinding (P2)

`routing_adjust_expansion_tier` takes: agent, current_model, expansion_score, budget_pressure. Absent: any representation of the agent's domain reasoning complexity. Two failure modes result:

- **Under-resourcing (haiku on complex domain):** `fd-decisions` downgraded to haiku on a multi-hop dependency reasoning task. Haiku produces an incomplete finding. A P1 is missed.
- **Over-resourcing (sonnet/opus on simple domain):** `fd-perception` maintained at sonnet on a key-exists check in a YAML file. Pattern-match task. 3K tokens on a file lookup haiku would complete correctly.

The brainstorm has `min_model` (safety floor, one-directional lower bound) but no complexity floor (reasoning-appropriate lower bound) and no `max_model` ceiling (upper bound for simple-domain agents).

**Recommendation:** Add two fields to `agent-roles.yaml`:
- `domain_complexity: low | medium | high` — minimum tier for coherent reasoning in this domain
- `max_model: haiku | sonnet | opus | null` — maximum tier warranted for this domain (optional)

In `routing_adjust_expansion_tier`, apply the complexity floor after the score-based adjustment, before the safety floor. The effective tier is `max(score_tier, complexity_floor_tier, safety_floor_tier)` capped at `max_model` if set.

This is additive to `agent-roles.yaml` and the tier function. No existing logic changes; two new checks added.

---

### 5. Score=1 Downgrade Is the Wrong Response for High-Complexity-Domain Agents
**Source:** fd-polynesian-wayfinding (P2)

Score=1 (weak signal) maps to "downgrade one tier" in the brainstorm. For low-complexity domains, this is correct. For high-complexity domains, a weak signal does not reduce the reasoning capability required — it only reduces the *confidence* that the expansion was warranted. If the agent launches, it still needs sufficient tier to reason coherently.

The downgrade-as-cost-reduction logic is inverted for complexity-sensitive agents: a weak signal on `fd-decisions` should not produce a haiku-tier decisions agent. The expansion evidence was weak; the reasoning requirement is unchanged.

**Recommendation:** This is addressed by the complexity floor from Finding 4. A `domain_complexity: high` agent has a complexity floor of sonnet — score=1 cannot downgrade below sonnet for this agent. The score=1 mapping still applies for `domain_complexity: low` agents. No separate fix required once Finding 4 is implemented.

---

### 6. Synthesis Treats All Tier-Adjusted Findings Equally (Batch Contamination)
**Source:** fd-venetian-glass-grading (P2)

The brainstorm scopes out flux-review changes. But haiku-tier Stage 2 findings flow into Phase 3 synthesis at equal weight with sonnet findings. A confused haiku finding on a complex domain (see Finding 4) can escalate a P2 to P0 in synthesis if synthesis has no tier weighting.

**Recommendation:** The brainstorm's logging section (lines 160–169) should emit `tier: haiku|sonnet|opus` per agent finding. No synthesis logic changes required now — the data field is present for future weighted synthesis. One field addition to the existing log format. Phase 3 ignores it initially; the feedback path exists for later use.

---

### 7. Token Savings Are Tracked but Not Recycled
**Source:** fd-han-salt-monopoly (P2)

The brainstorm's success criteria target 15–40K token savings per run. Budget accounting feeds savings back to `FLUX_BUDGET_REMAINING`. But remaining budget is only used as a downgrade gate (Option C: if < 50%, force downgrade). Savings are never used as an upgrade trigger.

This creates a systematic bias: cross-model dispatch consistently reduces quality investment without ever reinvesting savings in higher-value work. Over many runs, the budget tightens and savings compound — but no mechanism extracts value from them.

**Recommendation:** After the per-agent tier adjustment loop, compute `tokens_saved`. If `tokens_saved > threshold` (e.g., 10K), run one upgrade pass: upgrade the highest-scored score=2 agent that was kept (not upgraded) to the next tier. This is a single pass, not a recursive reallocation. No new infrastructure — one priority-ordered upgrade loop after the adjustment loop completes.

---

## Convergence and Conflicts

### Convergence Across Distant Domains

All four agents converge on one insight expressed through four different metaphors:

**The brainstorm treats tier assignment as a one-input problem (evidence strength) when it is inherently a two-input problem (evidence strength × task difficulty).**

- Venetian glassblowing: purity grade must be validated against actual process requirements, not just assumed accurate
- Han salt monopoly: centralized grading needs domain-specific defaults, not one-size-fits-all tiers
- Polynesian wayfinding: signal strength must be distinguished from signal difficulty to interpret
- Japanese sword testing: evidence quality (expansion score) and task complexity (domain_complexity) are independent axes that must both be considered

No two agents conflict on recommendations. The four P2 findings are each distinct and non-overlapping.

### No Contradictions

The distant-domain agents do not contradict each other or the brainstorm's core design. The brainstorm's A+C hybrid is sound. The four gaps are additive refinements, not architectural alternatives.

---

## Positive Findings Worth Preserving

The following brainstorm elements are validated by the distant-domain review:

1. **Grade-before-invest is the right principle.** All four domains confirm that differential investment based on evidence quality is correct. The principle is structurally sound; the execution needs refinement.

2. **Safety floors as mandatory reserves are correct.** The Han monopoly's mandatory state reserves confirm that non-negotiable floors (fd-safety, fd-correctness ≥ sonnet) are architecturally appropriate. The floors are implemented correctly.

3. **Budget pressure as a secondary constraint is appropriate.** Budget as a continuous signal (not a binary gate) is validated by the tribute economy model: surplus budget is a real resource that should drive secondary decisions.

4. **One-shot tier assignment is a reasonable constraint.** The thermal commitment principle confirms that mid-run tier switching is risky. The brainstorm's explicit exclusion of "Dynamic model switching mid-review" is correct. The single first-checkpoint re-evaluation (venetian P2) is an optional enhancement, not a requirement.

5. **Logging tier adjustments is correct and should be extended.** The brainstorm's logging sketch is the right approach. It should be extended to emit `tier` per finding for future synthesis weighting.

---

## Recommended Changes Before Implementation

### Must-Have (P1 — Required)

1. **Deduplication pass in expansion scoring (Step 2.2b):** Add `trigger_source_id` to expansion score contributions. Deduplicate before summing. Cost: one-pass grouping in expansion scoring loop.

2. **Fallback guard in `routing_adjust_expansion_tier` (lib-routing.sh):** Add two-line guard after safety floor call. Cost: 4 lines of bash.

3. **Adjacency transfer check in expansion scoring (Step 2.2b):** Before writing `expansion_score`, check domain intersection. Cap tier at haiku if intersection is empty. Cost: one-line domain-overlap guard.

### Should-Have (P2 — High Value)

4. **`domain_complexity` and `max_model` fields in `agent-roles.yaml`:** Adds reasoning-complexity axis to tier decision. Resolves Findings 4 and 5 together. Cost: 2 fields × N agents in YAML; 2 additional checks in `routing_adjust_expansion_tier`.

5. **`tier` field in per-finding log output (logging section):** Enables future tier-weighted synthesis. Cost: one field addition to log format.

6. **Upgrade pass after adjustment loop (expansion.md, Step 2.2c):** Recycles token savings into borderline-case upgrades. Cost: one priority-ordered pass after the adjustment loop.

### Deferred (P3 — Future)

7. Progressive commitment checkpoint (first tool-call re-evaluation for haiku agents)
8. Preferred-floor tier in `agent-roles.yaml` (preferred but not mandatory floors)
9. Retirement/performance tracking cross-referencing intertrust precision with `adjusted_tier`
10. Speculative launch tier timing clarification (explicit note that 2.2a.6 uses pre-score model map)

---

## Files Referenced

- Reviewed document: `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
- Agent reports in `docs/research/flux-drive/2026-04-04-cross-model-dispatch-brainstorm/`:
  - `fd-venetian-glass-grading.md` — grade validity, synthesis contamination, thermal commitment
  - `fd-han-salt-monopoly.md` — centralized failure modes, reinvestment, preferred floors
  - `fd-polynesian-wayfinding.md` — signal independence, commitment model, dead reckoning
  - `fd-japanese-sword-testing.md` — domain-difficulty axis, max_model ceiling, retirement criteria

---

## Final Verdict

**Status:** PROCEED-WITH-CHANGES

**Summary:** The brainstorm's A+C hybrid design is architecturally sound. The distant-domain review reveals four gaps that are invisible from within the dispatch domain:

1. Expansion score can be inflated by correlated signals (same root, multiple evidence channels) — add deduplication
2. `routing_adjust_expansion_tier` has no fallback for silent failure — add a two-line guard
3. Tier assignment is one-dimensional (evidence strength only) — add domain complexity as a second axis via `domain_complexity` and `max_model` in `agent-roles.yaml`
4. Synthesis and savings have no feedback paths — emit `tier` in finding log; recycle savings in upgrade pass

None of these block the approach. Items 1 and 2 should be resolved before landing. Items 3 and 4 are high-value P2s appropriate for the first iteration. The brainstorm can proceed to implementation with these changes incorporated.
