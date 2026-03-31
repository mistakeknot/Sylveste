---
date: 2026-03-31
reviewer: fd-architecture
plan: docs/plans/2026-03-31-discourse-fixative.md
bead: sylveste-rsj.9
reviewed: true
---

# Architecture Review — Discourse Fixative

## Findings Index

- P1 | FIX-01 | "Metric Divergence" | Fixative thresholds contradict Sawyer thresholds — two calibration surfaces for the same concern
- P1 | FIX-02 | "Relevance Proxy Error" | file:line title-scan is a structurally invalid proxy for `evidence_sources`
- P2 | FIX-03 | "Convergence Gate Double-Count" | `novelty_estimate = 1 - overlap_ratio` conflates two different populations
- P2 | FIX-04 | "Collapse Injection Semantics" | "collapse" fires only when all three triggers fire, but the most dangerous collapse pattern fires on exactly two
- P3 | FIX-05 | "Config Surface Sprawl" | Fixative thresholds are a third home for values already governed by discourse-sawyer.yaml

**Verdict:** needs-changes

---

## Background and Scope

The plan adds a zero-dispatch coherence step (Step 2.5.2b) between the Findings Index collection step and prompt-building. When approximate discourse health metrics cross thresholds, corrective text is injected into per-agent reaction prompts via a `{fixative_context}` slot. The files touched are `reaction.md`, `reaction-prompt.md`, and a new `discourse-fixative.yaml`.

The key design question posed: Is computing approximate Sawyer metrics pre-synthesis architecturally sound?

The short answer is: the approximation is sound in principle but the plan introduces two metrics (`participation_gini` and `relevance`) using proxies that are structurally wrong, and it creates a calibration split with `discourse-sawyer.yaml` that will silently diverge.

---

## F-01 (P1) — Fixative Thresholds Contradict Sawyer Thresholds

### Location

`discourse-fixative.yaml` (proposed, lines 4-7) vs `discourse-sawyer.yaml` (lines 6-8).

### Finding

`discourse-sawyer.yaml` defines the authoritative health band as `participation_gini_max: 0.3`, `novelty_rate_min: 0.1`, and `response_relevance_min: 0.7`.

The proposed `discourse-fixative.yaml` uses identical threshold values for `participation_gini_above: 0.3` and `novelty_estimate_below: 0.1`, but then sets `relevance_estimate_below: 0.5` — which matches the Sawyer **degraded** band, not the **healthy** band.

This means:
- The fixative fires on "degraded" relevance (below 0.5) but the Sawyer report warns at "below 0.7".
- A session can show `flow_state: degraded` in synthesis (relevance = 0.6) with no fixative intervention, then show `flow_state: healthy` after changes but fixative fires (relevance = 0.48).
- The two config files will drift independently over time. Neither references the other. There is no mechanical coupling.

### Fix

Either:

1. The fixative config should reference `discourse-sawyer.yaml` thresholds directly, not duplicate them. The simplest form: add a `source: discourse-sawyer.yaml` key and read the Sawyer config at Step 2.5.2b startup, using its `degraded` thresholds as the trigger floor. This makes the fixative a consumer of Sawyer rather than a parallel calibration surface.

2. Or, merge the fixative trigger values into `discourse-sawyer.yaml` under a new `fixative:` key. Sawyer is already the canonical home for all discourse health numbers.

The `relevance_estimate_below: 0.5` value specifically must align with either the Sawyer `healthy.relevance_above: 0.7` or `degraded.relevance_above: 0.5`. Right now it matches degraded — if that is intentional (the fixative fires earlier than synthesis warns), that intent needs a comment; without it, the divergence looks accidental.

---

## F-02 (P1) — Relevance Proxy is Structurally Invalid

### Location

`reaction.md` Task 3, Step 2.5.2b point 1c (proposed): "Count how many P0/P1 findings have file:line references in their titles or IDs vs. generic observations."

### Finding

Sawyer `response_relevance` (synthesize-review.md Step 6.6.3) is defined as:

```
relevance = count(findings with non-empty `evidence_sources` array) / total_findings
```

The `evidence_sources` array is a structured field populated during synthesis dedup (Step 6). It contains normalized file:line references extracted from the Evidence field of each finding. It does not exist at Phase 2 output time.

The proposed proxy — scanning titles and IDs for the pattern `file:line` — is a fundamentally different measurement:

1. **What it measures:** whether an agent put a file path in the finding's title or index ID. That is a proxy for how verbose the index is, not for whether the finding has evidence.
2. **What Sawyer measures:** whether the merged, deduplicated finding has at least one evidence source extracted from the full prose Evidence field during synthesis.
3. **Failure mode:** An agent that writes `ARCH-01 | "src/auth.ts:45 — missing bound check"` passes the proxy check. An agent that writes `ARCH-01 | "Missing null check"` with a full `Evidence: src/auth.ts:45` field in the prose body passes the Sawyer check but fails the proxy. The proxy will systematically misclassify verbose-title agents as high-relevance and evidence-in-body agents as low-relevance.

This is not a minor approximation error — the proxy measures title verbosity, not evidence quality.

### Fix

Two viable options:

**Option A (preferred): Drop the relevance trigger.** The fixative already has two triggers that are well-grounded (Gini from finding counts, novelty from overlap_ratio). The `drift` injection ("anchor your reactions to concrete file:line references") is valuable behavior, but it can fire unconditionally at low cost — include it whenever the fixative is active, or fire it whenever any other trigger fires. This removes the need for a relevance proxy entirely.

**Option B: Use overlap_ratio as the only pre-synthesis approximation.** The plan already uses `novelty_estimate = 1 - overlap_ratio` from Step 2.5.0. This is the one metric that has genuine data available pre-synthesis. Use it for novelty only; do not attempt to approximate relevance.

---

## F-03 (P2) — `novelty_estimate = 1 - overlap_ratio` Conflates Different Populations

### Location

`reaction.md` Task 3, Step 2.5.2b point 1b (proposed).

### Finding

The convergence gate `overlap_ratio` (Step 2.5.0) is computed as:

```
overlap_ratio = findings_with_2plus_agents / total_p0_p1_findings
```

This measures how many P0/P1 findings were reported by more than one agent. The population is only P0/P1 findings.

Sawyer `novelty_rate` (synthesize-review.md Step 6.6.2) is computed as:

```
novelty_rate = count(findings where effective_convergence == 1) / total_findings
```

The population is all findings (P0 through IMP). The denominator is different, and `effective_convergence` uses `convergence_corrected` from stemma analysis when available — meaning it accounts for shared-source amplification.

The proposed `novelty_estimate = 1 - overlap_ratio` overstates novelty when there are many P2/IMP findings unique to individual agents (they are not in the denominator of overlap_ratio but would be in Sawyer's denominator). It understates novelty when P2/IMP findings dominate convergence.

### Assessment

This approximation is directionally reasonable for the intended use: a high P0/P1 overlap is a meaningful signal of convergence pressure regardless of the P2/IMP distribution. The plan should document the approximation contract explicitly: "This is a P0/P1-only approximation of novelty; the authoritative metric is in synthesis." As written it presents the approximation as equivalent to Sawyer novelty, which it is not.

This is a documentation/comment issue more than a structural bug. The behavior is acceptable; the framing is misleading.

---

## F-04 (P2) — "Collapse" Injection Semantics are Inverted

### Location

`discourse-fixative.yaml` (proposed, lines 18-22) and `reaction.md` Step 2.5.2b point 2.

### Finding

The plan fires the `collapse` injection "if ALL three triggers fire simultaneously." The accompanying text says "compound degradation."

The echo-chamber pattern that `collapse` warns about — where agents confirm each other without independent analysis — is precisely what the sycophancy detector targets in synthesis. But the failure mode the fixative is trying to prevent at the pre-synthesis stage is when **novelty is already low AND participation is imbalanced**, which can occur with only two triggers firing. If relevance is high (agents are grounding findings in evidence) but Gini is high and novelty is low, that is still an echo chamber — it just has file citations. The three-trigger-coincidence requirement means collapse is actually the hardest injection to fire, even though it is the most urgent intervention.

Additionally, the `collapse` injection text ("Re-read the original review prompt. Challenge at least one peer finding you initially agreed with.") is a different class of directive from the other three — it is a behavioral override, not a focus note. Firing it only on all-three-triggers means it is nearly guaranteed to never fire in practice, because three-way degradation is a rare scenario that would likely already have triggered the convergence gate skip in Step 2.5.0.

### Fix

Consider decoupling `collapse` from the three-trigger compound rule. A more defensible trigger: fire `collapse` when `novelty_estimate` is below threshold AND `overall_conformity` from the previous run is available and high (>0.8). If no prior conformity data is available, fire `collapse` when both Gini and novelty trigger simultaneously (two-of-two on the most signal-bearing metrics).

Alternatively, remove `collapse` from the config entirely and treat it as a permanent injection — the cost is 150 tokens regardless, and the "challenge at least one peer finding" directive is healthy behavior in all cases.

---

## F-05 (P3) — Config Surface Sprawl

### Location

`discourse-fixative.yaml` (proposed), `discourse-sawyer.yaml`, `reaction.yaml` (discourse section).

### Finding

`reaction.yaml` already names Sawyer and Lorenzen as the two discourse config surfaces (`discourse.sawyer`, `discourse.lorenzen`). The plan adds a third config file without wiring it into that registry. The `discourse:` section in `reaction.yaml` is the logical home for a `fixative: discourse-fixative.yaml` entry — the same way Sawyer and Lorenzen are registered there.

Without this registration, Step 2.5.2b has a hardcoded filename reference to `discourse-fixative.yaml` rather than resolving it via the discourse registry, which breaks the established pattern. Future maintainers will not know to look in the `discourse:` section of `reaction.yaml` to understand what discourse configs are active.

### Fix

Add `fixative: discourse-fixative.yaml` under the `discourse:` key in `reaction.yaml`. Step 2.5.2b should resolve the config path via that key.

---

## Summary: The Central Question

**Is computing approximate health metrics pre-synthesis architecturally sound?**

Yes — with one metric. The convergence gate data (`overlap_ratio`) is already computed at Step 2.5.0 and is a legitimate pre-synthesis signal. Using `1 - overlap_ratio` as an approximate novelty estimate is acceptable provided the approximation contract is documented. The Gini computation from finding counts is also legitimate: the Findings Indexes are in memory, the math is unambiguous, and it uses the same formula as the authoritative Sawyer computation.

The unsound piece is the relevance approximation. There is no valid proxy for `evidence_sources` at this point in the pipeline because the structured evidence extraction happens during synthesis dedup. Any title-scanning proxy measures something else.

The plan can ship with two of its three trigger axes fully grounded. The third (relevance/drift) should either be dropped from the trigger system or made unconditional.

---

## Verdict

needs-changes

P1 issues (FIX-01 and FIX-02) must be resolved before implementation. FIX-01 is a config coherence problem that will cause silent calibration drift. FIX-02 is a measurement validity problem — the proposed proxy for relevance measures title verbosity, not evidence quality. The remaining findings are optional cleanup that improves long-term maintainability.

The smallest viable change: (a) remove the `relevance_estimate` trigger and unconditionally include the `drift` injection, and (b) add a `source: discourse-sawyer.yaml` comment or direct coupling so the Gini and novelty thresholds stay synchronized with Sawyer.
