---
artifact_type: correctness-review
reviewer: fd-correctness (Julik)
bead: sylveste-rsj.9
date: 2026-03-31
input: docs/plans/2026-03-31-discourse-fixative.md
---

# Correctness Review: Discourse Fixative Plan

## Invariants Established Before Review

From the codebase and prior plans:

1. **Convergence gate controls Phase 2.5 entry.** If `overlap_ratio > skip_if_convergence_above` (0.6), the entire reaction round is skipped. Nothing in Phase 2.5 runs.
2. **Sawyer health metrics are post-hoc and synthesis-time.** The authoritative Gini, novelty_rate, and response_relevance values live in `findings.json`, computed by the synthesis subagent in Phase 3. Any pre-synthesis metrics are estimates.
3. **Findings Indexes contain structured lines only.** The index format is `- SEVERITY | ID | "Section" | Title`. Prose evidence is in sections after the index.
4. **overlap_ratio counts P0/P1 findings only,** matched by ID or fuzzy title (3+ shared keywords), with "2+ agents reporting" as the threshold.
5. **Sawyer's novelty_rate** is defined in `discourse-sawyer.yaml` as post-synthesis; the brainstorm acknowledges the fixative's novelty_estimate is a "rough proxy" using total overlap over total findings.
6. **Fixative must be a no-op when healthy** (the sandalwood principle, PRD success criterion 1). Zero tokens added when no triggers fire.
7. **Template slot `{fixative_context}` must be resolved before Step 2.5.4 dispatch** — reaction prompts are built in Step 2.5.3 and dispatched in 2.5.4.

---

## Findings Index

- P1 | FX-001 | "Novelty Estimate" | Fixative novelty_estimate and Sawyer novelty_rate measure different populations — divergence can be extreme
- P1 | FX-002 | "Relevance Estimate" | Relevance estimate algorithm is undefined: no guidance on how to count "file:line references in titles or IDs"
- P1 | FX-003 | "Missing Config" | Silent no-op on missing discourse-fixative.yaml is correct in principle but the plan never states this invariant, leaving implementors free to error
- P2 | FX-004 | "Collapse Trigger" | ALL-three-simultaneously threshold makes collapse injection fire rarely in practice and can mask meaningful partial degradation
- P2 | FX-005 | "Gini Data Source" | Gini computation counts findings per agent from Findings Indexes, but Step 2.5.2 filters to P0/P1 only by default — Gini reflects high-severity finding distribution, not participation balance
- P3 | FX-006 | "max_injection_tokens has no enforcement path" | The config field is declared but no step in the plan checks or truncates injection text against it
- P3 | FX-007 | "Log placement" | Fixative log fires in Step 2.5.2b but synthesis report line is Step 2.5.5 — the log data must survive in scope across all of 2.5.3 and 2.5.4

Verdict: needs-changes

---

## Detailed Findings

### FX-001 — Novelty Estimate Population Mismatch (P1)

**The claim:** Step 2.5.2b says `novelty_estimate = 1 - overlap_ratio`. The `overlap_ratio` from the convergence gate (Step 2.5.0) counts P0/P1 findings where 2+ agents reported the same finding.

**The problem:** Sawyer's `novelty_rate_min: 0.1` is calibrated against *all* findings across all agents, not just the P0/P1 stratum. The fixative's `novelty_estimate_below: 0.1` threshold uses the same numeric value but is comparing against a narrower, more homogeneous population.

**Concrete failure case:** Suppose a review produces 20 findings total: 4 P0/P1 findings (3 of which overlap across agents) and 16 P2/P3 findings (all unique). True novelty_rate = 17/20 = 0.85 (healthy by Sawyer standards). Fixative's overlap_ratio = 3/4 = 0.75, so novelty_estimate = 0.25. That is above 0.1, so no injection fires — this particular case is fine.

Now flip it: 4 P0/P1 findings (all 4 unique, none overlapping) and 16 P2/P3 findings (12 of which are similar across agents). True novelty_rate = 8/20 = 0.40 (Sawyer would flag). Fixative's overlap_ratio = 0/4 = 0.0, novelty_estimate = 1.0. No convergence injection fires. The fixative sees a false-healthy signal while a real convergence problem exists in the lower-severity tier.

**The stakes:** The fixative's entire rationale is that it acts as an early-warning proxy for Sawyer. If the proxy systematically misses convergence in the P2/P3 tier — which is where stylistic pile-ons typically manifest — it fails on exactly the cases it was designed to catch.

**Minimal fix:** Compute a parallel `p2p3_overlap_ratio` by counting P2/P3 findings with 2+ agent matches (the same fuzzy-title logic). Use `min(p0p1_novelty_estimate, p2p3_novelty_estimate)` as the composite novelty_estimate, or use total-findings overlap across all severities. The brainstorm's pseudocode (`novelty_estimate = 1 - (overlap / total_findings)`) is closer to correct — the plan diverged from the brainstorm when it reused overlap_ratio from the convergence gate. The brainstorm version should be restored.

---

### FX-002 — Relevance Estimate Algorithm Undefined (P1)

**The claim:** Step 2.5.2b says: "Count how many P0/P1 findings have file:line references in their titles or IDs vs. generic observations."

**The problem:** The Findings Index format is `- SEVERITY | ID | "Section" | Title`. File:line references (`auth.go:47`) do not appear in titles or IDs by convention — they appear in the prose evidence sections after the index. The plan says "in their titles or IDs" but:

- Finding IDs follow the `[A-Z]{2,3}-\d{3}` pattern (`SAFE-01`, `AR-003`) — they never contain file paths.
- Titles are one-line descriptions: "Session tokens stored in localStorage" — not "auth.go:84: session tokens in localStorage".

An implementor following this instruction literally will find zero file:line references in any index and will always compute `relevance_estimate = 0.0`, firing the drift injection on every single review regardless of actual evidence quality. This is the opposite of the intended no-op behavior for healthy discourse.

**Minimal fix:** Replace the relevance estimate algorithm with one of:
- Count P0/P1 findings whose **prose evidence sections** contain at least one `file:line` pattern — but this requires reading prose, not just the index, which contradicts the plan's premise of working only with Findings Indexes.
- Use a simpler proxy: count the proportion of P0/P1 findings that have a Section Name other than generic placeholders (e.g., not "General" or "Overview"). This is an imperfect proxy but is correctly computable from the index alone.
- Defer relevance estimation to post-synthesis (where discourse-health.sh has the full evidence picture) and remove the inline relevance check from 2.5.2b entirely. The plan already notes this is approximate — removing the one metric that cannot be meaningfully approximated from indexes alone is the safest path.

---

### FX-003 — Missing Config File: Behavior Unspecified (P1)

**The claim:** Step 2.5.2b says "If `discourse-fixative.yaml` `fixative.enabled` is true: [compute metrics and potentially inject]." The plan creates the file in Task 1 and wires the check in Task 3.

**The problem:** The plan says "if enabled is true" but does not state what happens if the file is missing. In practice, the correct behavior is silent no-op (same as `enabled: false`) — this is consistent with the pattern established by the Lorenzen config in synthesize.md (`if the config file doesn't exist or parsing fails, omit LORENZEN_CONFIG`). But without that invariant stated, an implementor may raise an error when the file is absent, breaking reviews on any interflux installation that hasn't yet created the file.

This matters during rollout: Task 3 modifies `reaction.md` to add Step 2.5.2b, but Task 1 creates `discourse-fixative.yaml`. If Task 3 ships before Task 1 (out-of-order deploy or partial apply), every reaction round will attempt to read a file that doesn't exist.

**Minimal fix:** Add a single explicit sentence to Step 2.5.2b: "If `discourse-fixative.yaml` does not exist or cannot be parsed, treat as disabled — skip Step 2.5.2b entirely." This matches the Lorenzen precedent and makes the partial-deploy scenario safe.

---

### FX-004 — Collapse Trigger Semantics: ALL-three-simultaneously (P2)

**The claim:** The collapse injection fires "If ALL three fire simultaneously." This means gini > 0.3 AND novelty_estimate < 0.1 AND relevance_estimate < 0.5 must all be true at the same time.

**The concern:** In practice, each individual trigger addresses a distinct discourse failure mode:
- Imbalance (gini) = participation skew
- Convergence (novelty) = finding overlap
- Drift (relevance) = evidence absence

Two of these firing simultaneously is already a compound degradation signal meaningful enough to warrant a combined intervention. Three simultaneous triggers indicate full collapse, but by that point the three individual injections are already all firing — the collapse injection adds a fourth message on top of three existing ones, at maximum prompt overhead.

The design has an inversion: collapse fires when the situation is worst AND the system is already at maximum injection load. The intended use — early warning of compound collapse — would be better served by firing at two-out-of-three, before all three individual injections are already in play.

**Failure narrative:** A review where gini = 0.35 (imbalance fires) and novelty = 0.08 (convergence fires) but relevance = 0.6 (drift does not fire) has two of the three failure modes simultaneously. This is the AMOC tipping-point scenario described in the brainstorm. The collapse injection, which is explicitly about "echo-chamber risk," does not fire. Only the two individual injections fire, which are less pointed than the collapse message about challenging agreed-upon findings. The review proceeds without the strongest corrective signal.

**Minimal fix:** Change the collapse trigger to "if 2 or more individual triggers fire simultaneously." This fires earlier (at the compound degradation onset) and reserves the strongest signal for when it is most useful rather than when it is most redundant.

---

### FX-005 — Gini Reflects P0/P1 Distribution, Not Participation Balance (P2)

**The claim:** "Count findings per agent from the collected indexes." Step 2.5.2 collects findings filtered to P0/P1 by default (with `severity_filter_p2_light: true` for single-sentence P2 checks, not full inclusion).

**The concern:** The Sawyer Gini is intended to measure participation balance — whether agents are contributing roughly equally or whether a few dominate. But if the Gini is computed only over P0/P1 findings, an agent that produced 8 P2/P3 findings and 0 P0/P1 findings appears identical to an agent that produced nothing. A 6-agent review where 1 agent found all 4 P0 issues (gini approaches 1.0) and 5 agents found only P2/P3 issues would correctly fire the imbalance injection. But a 6-agent review where all 4 P0 findings are evenly distributed (gini = 0) while agent participation in P2/P3 is highly skewed would show gini = 0 and not fire imbalance — missing the actual participation skew.

**The stakes:** This is less severe than FX-001 because Gini over P0/P1 is a meaningful signal even if not a complete one. The imbalance injection is about who is contributing substantive findings, and P0/P1 are the substantive findings. But the plan should be explicit that the Gini is measuring high-severity finding distribution, not overall participation, so future readers calibrate thresholds accordingly.

**Minimal fix:** If `severity_filter_p2_light: true`, include P2 findings in the Gini count (they are already collected, just given lighter prompt treatment). Add a comment in Step 2.5.2b: "Note: Gini reflects P0/P1/P2 finding distribution per agent, not overall agent verbosity."

---

### FX-006 — max_injection_tokens Has No Enforcement Path (P3)

**The claim:** The config declares `max_injection_tokens: 150`. No step in the plan counts tokens or truncates injection text.

**The concern:** Each injection string in the config is approximately 30-50 words (40-70 tokens). With three injections plus collapse, total injection text is 120-280 tokens. The `max_injection_tokens: 150` budget can be exceeded if all four fire. The config value creates a false expectation of a budget ceiling that does not exist in the implementation.

**Minimal fix:** Either remove `max_injection_tokens` from the config (the real limit is the number of injections times the longest injection text, which is controlled in the YAML directly) or add a truncation step: "Concatenate fired injections; if the combined text exceeds `max_injection_tokens` characters, include the highest-priority injections and omit lower-priority ones (priority order: collapse > convergence > imbalance > drift)."

---

### FX-007 — Log Data Lifetime: Step 2.5.2b to Step 2.5.5 (P3)

**The claim:** Step 2.5.2b logs `Fixative: {active|inactive} ({N} injections: {injection_names})`. Step 2.5.5 (Report) appends `Fixative: {active|inactive} ({N} injections)`. These are two separate output points with steps 2.5.3 and 2.5.4 (parallel agent dispatch) in between.

**The concern:** This is a state-lifetime issue. In LLM orchestration, intermediate computation state (the list of fired injections and their count) must remain available in the host agent's context from Step 2.5.2b all the way through Step 2.5.5. With dispatch (Step 2.5.4) running background agents in between, a context-heavy review could cause the fixative state variables to fall out of the active working context of a distracted orchestrator.

**The concern is real but low-severity** because the fixative log line in 2.5.2b is explicitly the immediate output, and 2.5.5 just needs a count. Any orchestrator should retain this in working memory. The risk is negligible in practice but the plan could make it explicit: "Retain fixative_status string (e.g., `active: imbalance, convergence`) in scope for Step 2.5.5 report."

---

## Addressed Concerns (Questions From the Prompt)

**Q1: If the convergence gate skips the reaction round, the fixative never runs. Is this correct?**

Yes, this is correct and is an invariant, not a bug. The convergence gate fires when overlap_ratio > 0.6, meaning >60% of P0/P1 findings already converge. In that state, no reaction round runs and the fixative's job — improving reaction discourse quality — has no substrate. There is no reaction round to fix. The fixative is not a health monitor; it is a prompt modifier. Prompt modification with no prompts is a no-op by definition. No action needed.

**Q2: Could the novelty_estimate diverge significantly from Sawyer's novelty_rate?**

Yes, and the divergence can be in either direction (see FX-001). The brainstorm acknowledges this explicitly ("rough proxy"). The issue is that the plan's current formulation — reusing `overlap_ratio` from the convergence gate, which is P0/P1-only — is a narrower estimate than what the brainstorm intended (`overlap / total_findings` across all findings). The plan should be corrected to use total-findings overlap, not the convergence gate's P0/P1-only ratio. Filed as FX-001.

**Q3: Is Findings Index data sufficient for Gini computation?**

For Gini: yes, with the caveat in FX-005. Finding count per agent is directly available from the parsed index lines. The plan does not require reading prose sections for Gini.

For relevance estimation: no, the Findings Index format does not carry file:line evidence (FX-002). This is the more serious problem of the two.

**Q4: Should collapse require ALL three simultaneous triggers?**

No. Two-out-of-three is the correct threshold. See FX-004 for the full argument. The current design fires the strongest signal at the worst moment (when three individual injections are already running) rather than at the onset of compound degradation.

**Q5: What if discourse-fixative.yaml doesn't exist?**

The plan does not state this invariant. The correct behavior (silent no-op, matching the Lorenzen precedent in synthesize.md) should be made explicit. Filed as FX-003.

---

Verdict: needs-changes
