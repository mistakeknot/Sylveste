# fd-ayurvedic-constitution Review: Cross-Model Dispatch Brainstorm

**Source:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
**Reviewed:** 2026-04-04
**Agent:** fd-ayurvedic-constitution (Ayurvedic vaidya — prakriti-based treatment intensity)
**Track:** D (Esoteric)
**Bead:** sylveste-9lp.9

---

## Findings Index

- P1 | AYU-01 | Implementation Sketch / routing_adjust_expansion_tier | Constitutional blindness: function ignores agent role when adjusting tier
- P1 | AYU-02 | Design Space / Option A | Dosha collapse: haiku assignment to planner-role agents risks worse-than-nothing findings
- P2 | AYU-03 | Current Architecture / agent-roles.yaml | Agni gap: no assessment of whether agent can process domain at downgraded tier
- P2 | AYU-04 | Open Questions / #3 | Rasayana absent: no feedback loop from tier-adjusted runs to recalibrate future adjustments
- P3 | AYU-05 | Design Space / Option A | Seasonal unawareness: tier adjustment does not vary by review phase (plan vs. diff)

---

## AYU-01 — Constitutional Blindness: Function Ignores Agent Role When Adjusting Tier (P1)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Implementation Sketch", `routing_adjust_expansion_tier()` function signature.

**Severity:** P1 — Required to exit quality gate. The function's input contract excludes a critical variable that determines whether a tier downgrade is safe.

**The Ayurvedic parallel:**
A vaidya who doses purely by disease severity — ignoring patient constitution — will harm a vata-type patient (thin, anxious, sensitive) with aggressive treatments suited for kapha-type patients (robust, stable, slow-metabolizing). In Ayurveda, the same fever demands different remedies for different constitutions. Disease severity sets the upper bound; constitution sets the safe lower bound.

The brainstorm's `routing_adjust_expansion_tier` takes `(agent, current_model, expansion_score, budget_pressure)`. The `agent` name is present, but inspection of the function body shows it is only used for `_routing_apply_safety_floor` — the known hard-coded list of safety/correctness agents. The function does not look up `agent_roles.yaml` to retrieve `model_tier` (the agent's constitutional type) or `min_model` (the agent's constitutional floor).

**Concrete failure scenario:** `fd-architecture` has `model_tier: opus` and `min_model: sonnet` in `agent-roles.yaml`. When launched as a Stage 2 expansion agent with `expansion_score=1` and `budget_pressure=high`, the function downgrades:
- Score 1 → `_routing_downgrade(sonnet)` → haiku
- Budget high → `_routing_downgrade(haiku)` → haiku (already floor)
- Safety floor check: `fd-architecture` is not on the safety-floored list → no correction

`fd-architecture` runs at haiku. The agent receives a complex multi-service interaction pattern and produces a finding that identifies a symptom ("high coupling") but cannot reason about the architectural cause (dependency inversion violation across service boundaries requires reasoning about abstract design principles — a haiku-tier task failure mode documented in interstat data). Synthesis receives a finding it cannot act on.

**Evidence:** `routing_adjust_expansion_tier()` body in Implementation Sketch: `_routing_apply_safety_floor "$agent" "$model" "expansion"` — safety floor is the *only* place `$agent` is used to look up role constraints. The function does not call any `agent-roles.yaml` lookup. The brainstorm acknowledges `agent-roles.yaml` has `min_model` for planners and reviewers, but does not wire this into the tier adjustment.

**Smallest fix:** Before score-based downgrade, read `min_model` from `agent-roles.yaml` for the agent. Use it as the constitutional floor, distinct from the safety floor:

```bash
routing_adjust_expansion_tier() {
  local agent="$1" model="$2" score="${3:-2}" pressure="${4:-low}"

  # Read constitutional floor from agent-roles.yaml
  local constitutional_floor
  constitutional_floor=$(yq ".agents[] | select(.name == \"$agent\") | .min_model" \
    os/Clavain/config/agent-roles.yaml 2>/dev/null)

  # Score-based adjustment (existing logic)
  case "$score" in
    3) ;; 2) ;; 1) model=$(_routing_downgrade "$model") ;; 0) model="haiku" ;;
  esac

  # Budget pressure (existing logic)
  [[ "$pressure" == "high" ]] && model=$(_routing_downgrade "$model")

  # Constitutional floor (NEW — respects agent-roles.yaml min_model)
  if [[ -n "$constitutional_floor" ]]; then
    model=$(_routing_max "$model" "$constitutional_floor")
  fi

  # Safety floor (always last, existing)
  model=$(_routing_apply_safety_floor "$agent" "$model" "expansion")
  echo "$model"
}
```

---

## AYU-02 — Dosha Collapse: Haiku Planners Risk Worse-Than-Nothing Findings (P1)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Design Space / Option A", "Risk Assessment" table.

**Severity:** P1 — The risk table acknowledges "Finding quality degrades on haiku" as Medium/Medium, but mislabels the failure mode. Confidently wrong findings are worse than absent findings.

**The Ayurvedic parallel:**
In Ayurveda, treating a strongly pitta-type patient (sharp, transformative, intense) with excessive heat-generating treatments does not merely fail — it *worsens* the condition by amplifying existing imbalance. A kapha patient given too light a dose simply sees no effect (neutral failure). The pitta patient given the wrong treatment gets sicker (negative failure). The failure modes are categorically different.

The risk table entry "Finding quality degrades on haiku — Medium/Medium — Monitor via intertrust precision scores" treats the failure as a *quality degradation* (neutral failure mode). The actual failure mode for planner-role agents downgraded to haiku is *confidently incorrect architectural findings* that mislead synthesis (negative failure mode).

**Evidence from interstat baseline:** The brainstorm references `estimate-costs.sh`, `budget.yaml`, and `interstat historical data`. If interstat tracks per-(agent, model) precision scores, the data would show that planner-role agents (fd-architecture, fd-systems) have disproportionately high false-confidence rates at haiku versus sonnet. The brainstorm does not query this; it estimates savings (15-40K tokens) without estimating the false-confidence cost.

**Concrete failure scenario:** `fd-architecture` at haiku finds "tight coupling between services A and B" and recommends "introduce interface layer." At sonnet, the same agent would recognize that A and B share a transaction boundary and that an interface layer would break transactional integrity — a nuanced architectural constraint invisible at haiku reasoning depth. Synthesis accepts the haiku finding (it passes format checks). The implementation follows the recommendation. The transaction boundary is broken in production.

**Evidence:** Risk table in brainstorm: "Finding quality degrades on haiku — Monitor via intertrust precision scores." No mention of suppressing or weighting haiku findings from planner-role agents. Success criteria: "No regression in P0/P1 finding recall (measured via intertrust)" — this measures *recall* (did we find what was there), not *precision* (were what we found correct). Confidently wrong findings do not affect recall.

**Smallest fix:** Add a finding-confidence filter for downgraded planner-role agents. When `fd-architecture` or `fd-systems` runs at haiku due to tier adjustment, their findings should be marked `downgraded: true` in the synthesis input, and synthesis should apply a confidence penalty. This is one field addition to the per-agent logging:

```
Cross-model dispatch (Stage 2):
  fd-architecture: opus → haiku (score=1, weak signal) ⚠️ PLANNER-DOWNGRADED
```

Synthesis prompt: "Findings from PLANNER-DOWNGRADED agents carry reduced confidence. Do not escalate P1+ severity based solely on their output without corroboration from a non-downgraded agent."

---

## AYU-03 — Agni Gap: No Assessment of Whether Agent Can Process Domain at Downgraded Tier (P2)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Current Architecture / What We Have to Work With", items 1-6.

**Severity:** P2 — Systematic capability-domain mismatch degrades quality over time without immediate failure signal.

**The Ayurvedic parallel:**
Before prescribing, a vaidya assesses *agni* — the patient's digestive capacity, their ability to metabolize treatment. A patient with weak agni cannot process strong medicines regardless of what their disease demands. The vaidya adapts the treatment to what the patient can actually absorb, not what the ideal dose would be.

The brainstorm lists 6 data sources available for the tier adjustment decision: expansion scores, agent roles, safety floors, cost estimates, trust multipliers, redundancy scores. Missing from this list: *domain-tier compatibility data*. Not all agents can produce meaningful output at haiku for all domains. `fd-resilience` at haiku reviewing a distributed transaction protocol is agni-insufficient. `fd-people` at haiku reviewing user communication clarity is not — haiku is perfectly capable of that domain.

**Concrete failure scenario:** `fd-resilience` is downgraded to haiku (score=1, weak signal). Its domain — resilience patterns in distributed systems — requires reasoning about failure propagation, partial failures, and eventual consistency. At haiku, the agent produces findings about missing timeouts and retry logic (visible surface symptoms) but cannot model the cascade failure paths that justify *why* those retries matter in this topology. The finding is syntactically correct, semantically shallow, and indistinguishable from a correct finding in the log.

**Evidence:** The 6 "What We Have to Work With" items include `Trust multipliers — per-agent precision scores from intertrust`. This is the closest proxy for agni assessment, but it is a static per-agent score, not a per-(agent, model-tier, domain) score. An agent's precision at its native tier is not the same as its precision at a downgraded tier.

**Smallest fix:** Introduce `min_tier_for_domain` metadata to `agent-roles.yaml`. For each agent, specify which tiers are viable for their domain:

```yaml
- name: fd-resilience
  model_tier: haiku
  domain_complexity: high  # distributed systems reasoning
  min_viable_tier: haiku   # haiku is viable (surface-level checks)
  min_trusted_tier: sonnet # sonnet required for cascade analysis
```

`routing_adjust_expansion_tier` can then check: if target tier < `min_trusted_tier`, flag the agent output as `tier-insufficient` rather than blocking dispatch. Synthesis applies appropriate confidence reduction.

---

## AYU-04 — Rasayana Absent: No Feedback Loop From Tier-Adjusted Runs (P2)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Open Questions / #3".

**Severity:** P2 — The mechanism exists to support learning; not wiring it in creates calibration drift.

**The Ayurvedic parallel:**
After aggressive treatment, Ayurveda prescribes rasayana — rejuvenating therapies that restore baseline capacity and inform the next treatment cycle. The rasayana cycle is where clinical learning occurs: the vaidya observes how the patient responded and adjusts the *next* treatment protocol accordingly. Without rasayana, each treatment episode starts from the same prior, ignoring what was learned.

Open Question #3 from the brainstorm: "Should tier adjustments feed into interspect for long-term calibration? If we track (agent, original_tier, adjusted_tier, expansion_score, finding_severity) we could learn optimal mappings."

This is correctly identified as an open question, but it is answered *implicitly* as "optional future work." The brainstorm has the infrastructure: interspect is already wired for calibration signals, intertrust provides per-agent precision scores, and the logging format already captures `(original_tier, adjusted_tier, expansion_score)`. The missing link is: *track finding quality from downgraded runs and feed it back*.

**Concrete impact:** The brainstorm estimates 15-40K token savings per run. If the downgrade logic is mis-calibrated (e.g., score=1 is too aggressive — it downgrades agents that actually produce valuable P2 findings), the quality loss compounds over many runs without correction. The system drifts toward under-investing with no signal.

**Evidence:** Success Criteria item 4: "No regression in P0/P1 finding recall (measured via intertrust)." This is a static threshold check, not a learning loop. Intertrust already tracks per-agent precision; adding `tier` as a dimension to intertrust's tracking schema would enable the rasayana loop.

**Smallest fix:** Add one interspect event per tier-adjusted agent launch:

```bash
_interspect_emit "cross-model-dispatch" \
  agent="$agent" \
  original_tier="$original_model" \
  adjusted_tier="$final_model" \
  expansion_score="$score" \
  budget_pressure="$pressure"
```

After synthesis, add one correlating emit:
```bash
_interspect_emit "cross-model-dispatch-outcome" \
  agent="$agent" \
  adjusted_tier="$final_model" \
  finding_count="$N" \
  finding_severity_max="$max_sev"
```

This pairs input conditions with outcomes, enabling interspect to learn optimal tier-score mappings over time. The brainstorm already suggests this; it just needs to be in-scope.

---

## AYU-05 — Seasonal Unawareness: Tier Adjustment Does Not Vary by Review Phase (P3)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Scope / Out of Scope".

**Severity:** P3 — Improvement for future iteration.

**The Ayurvedic parallel:**
Ritucharya (seasonal regimen) recognizes that the same dosha is stronger in some seasons than others. Vata is highest in autumn, pitta in summer. Treatment intensity appropriate in winter may be excessive in summer. The *same constitutional type* requires *different doses* at different times.

The brainstorm's Out of Scope section: "flux-review changes (no expansion pool in review mode)." But `routing.yaml` already implements phase-based routing differences. Stage 2 expansion agents in plan-review mode (reviewing architectural plans before implementation) face different domain complexity than in diff-review mode (reviewing concrete code changes). An architectural plan review requires more speculative reasoning (higher haiku-failure risk) than a diff review of a concrete implementation.

**Evidence:** `routing.yaml` is referenced as the existing phase-aware mechanism. The brainstorm's tier adjustment adds a new layer but doesn't consult the current phase mode. `budget_pressure` is the only environmental variable in the function signature.

**Smallest fix:** Pass review phase as an input to `routing_adjust_expansion_tier`:

```bash
routing_adjust_expansion_tier "$agent" "$model" "$score" "$pressure" "${FLUX_PHASE:-diff-review}"
```

Apply a phase-based conservatism modifier: plan-review downgrades are more conservative (don't downgrade planners in plan-review mode regardless of score). This is a one-conditional addition once phase is passed through.

---

## Summary

| ID | Severity | Domain | Status |
|----|----------|--------|--------|
| AYU-01 | P1 | Constitutional floor missing from function | BLOCKING — min_model from agent-roles.yaml not read |
| AYU-02 | P1 | Worse-than-nothing planner failure mode | BLOCKING — risk table mislabels failure mode type |
| AYU-03 | P2 | No domain-tier compatibility assessment | Important — capability-domain mismatch silent |
| AYU-04 | P2 | No rasayana feedback loop | Important — interspect emit path specified but out-of-scope |
| AYU-05 | P3 | No phase-aware tier adjustment | Improvement — review phase not in function signature |

**Verdict: needs-changes** — two P1 gaps: constitutional floor not read from agent-roles.yaml, and planner-downgrade failure mode is categorically worse than the risk table acknowledges.
