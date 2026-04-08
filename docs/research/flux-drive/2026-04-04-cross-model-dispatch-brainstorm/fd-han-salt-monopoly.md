# fd-han-salt-monopoly: Centralized Control & Failure Mode Review

**Reviewer:** fd-han-salt-monopoly (Han Dynasty yantieshi — centralized resource tiering, mandatory reserves)
**Document:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
**Date:** 2026-04-04
**Scope:** Centralization point correctness, single-point-of-failure risk, mandatory vs. preferred floors, gaming of scoring, token savings reinvestment
**Track:** C — Distant domain structural isomorphism

---

## Executive Summary

The Han salt monopoly centralized quality grading into yantieshi (salt commissioners) who issued tier assignments to distributed production regions. The brainstorm makes an identical move: `routing_adjust_expansion_tier` is the single centralized decision point for all Stage 2 tier assignments. This reveals one structural gap invisible from within the dispatch domain:

**A centralized tier function with no per-agent fallback is a single point of failure.** The Han salt commission had regional defaults — each salt works knew its baseline quota even if the central commissioner was unavailable. The brainstorm's `routing_adjust_expansion_tier` has no equivalent: if the function errors, all Stage 2 agents are affected simultaneously with no documented recovery path.

---

## P1 Findings

### [P1] `routing_adjust_expansion_tier` is a single point of failure with no graceful degradation path (brainstorm, "New Function in lib-routing.sh" section, lines 119–142)

The implementation sketch defines `routing_adjust_expansion_tier` as the sole arbiter of Stage 2 model selection. The function receives agent, current_model, expansion_score, and budget_pressure and returns an adjusted model. No error handling is sketched. No fallback is specified for cases where the function returns an empty string, a non-existent model name, or encounters a missing safety-floor table entry.

In the Han salt system, a yantieshi commissioner who issued a corrupt quota ledger could freeze production across an entire region. The salt works had no authority to self-assign quotas; they required commission authorization. The brainstorm creates an identical dependency: if `routing_adjust_expansion_tier` fails silently (returns empty string), or if `_routing_apply_safety_floor` has a new agent name that isn't in `agent-roles.yaml`, the Stage 2 dispatch receives a malformed model parameter.

Shell function failures in bash are particularly dangerous: a function that sources a missing file or has a `case` fall-through will often return empty output rather than a non-zero exit code. The downstream Task dispatch that receives an empty `$model` parameter will either fail noisily (good) or default to whatever the runtime's fallback model is (silent misconfiguration).

**Failure scenario:** A new flux-gen expansion agent `fd-newly-generated` appears in an expansion pool. It is not yet in `agent-roles.yaml`. `_routing_apply_safety_floor` looks up the agent and finds no entry. The function silently skips the floor application and returns the raw score-adjusted model. If the score was 1 (haiku), this agent dispatches at haiku with no safety-floor protection. If the domain happens to require correctness review, a haiku-tier agent produces a missed P0.

**Smallest fix:** Add a single guard in `routing_adjust_expansion_tier`: if the function's return value is empty or not one of `{haiku, sonnet, opus}`, fall back to `current_model` (the pre-adjustment resolved model) and emit a warning log line. This is a two-line addition after the safety floor call:

```bash
[[ -z "$model" || ! "$model" =~ ^(haiku|sonnet|opus)$ ]] && {
  echo "[routing] WARN: adjust returned invalid model '$model' for $agent, using $2" >&2
  model="$2"
}
echo "$model"
```

This converts a silent misconfiguration into a logged degradation to the pre-adjustment default.

---

## P2 Findings

### [P2] Token savings from tier adjustment are tracked but not recycled — the tribute economy is unaddressed (brainstorm, "Logging" section, lines 160–169; "Success Criteria" section, lines 215–219)

The logging sketch shows "Estimated savings: ~35K tokens" per run. The success criteria define 15–40K tokens per run with expansion as the target. But the brainstorm does not specify what happens to those saved tokens. They are accounted for in budget tracking (constraint 4: "tier-adjusted costs fed back to budget tracker") but there is no mechanism to reallocate them.

In the Han tribute economy, salt production revenue funded the military. Surplus production was not banked — it was redistributed. The brainstorm's equivalent surplus (tokens saved by downgrading) is banked in `FLUX_BUDGET_REMAINING` but never reinvested: the "remaining budget" check (Option C hybrid, lines 100–113) only uses remaining budget as a gate for further downgrading, never as a trigger for launching additional agents or upgrading borderline cases.

This is a P2 because it is an optimization opportunity rather than a correctness failure. But it represents a systematic bias: cross-model dispatch consistently reduces quality investment without ever reinvesting savings into quality improvement. Over many runs, this creates a ratchet effect where budgets tighten but savings are never recycled into higher-value work.

**Smallest fix:** In the expansion.md changes (lines 145–158), after the per-agent tier adjustment loop, compute `tokens_saved = sum(original_tier_cost - adjusted_tier_cost)`. If `tokens_saved > threshold` (e.g., 10K), consider upgrading the highest-scored borderline candidate (score=2 agents that were kept, not upgraded). This is a single reallocation pass after the adjustment loop — no new infrastructure, just a priority-ordered upgrade sweep with the saved budget.

---

### [P2] The preferred-floor tier — agents that should prefer sonnet but are not required to run at sonnet — is missing (brainstorm, "Constraints" section, lines 172–176)

The brainstorm establishes hard safety floors (fd-safety and fd-correctness always ≥ sonnet) and exemptions (exempt agents bypass cross-model dispatch). There is no intermediate tier: agents that should prefer sonnet but can tolerate haiku if budget pressure is high.

The Han salt system had mandatory state reserves (always maintained) and strategic reserves (maintained when possible). The brainstorm only has mandatory reserves (safety floors) and no-reserve (all other agents). Agents like `fd-resilience` or `fd-decisions` are classified as checkers with haiku tier. But a `fd-decisions` agent on a complex multi-agent tradeoff scenario may need sonnet reasoning even if it isn't a safety-critical domain.

**Smallest fix:** Add a `preferred_model` field to `agent-roles.yaml` entries alongside `min_model`. When cross-model dispatch downgrade would push an agent below `preferred_model`, log a warning and emit a `preferred_floor_violated` flag in the logging output. Do not block the downgrade (preferred floors are not mandatory) but make the violation observable. This is additive to `agent-roles.yaml` and costs one line of YAML per agent.

---

## P3 Findings

### [P3] Centralization point may be too late in the pipeline — tier decisions require expansion score, but expansion score is finalized too late to influence the speculative launch (brainstorm, "Current Architecture" section, lines 17–28)

The architecture shows speculative launches at Step 2.2a.6 (incremental expansion) using the same model map from Step 2.0.5. The brainstorm states (constraint 5): "Speculative launches use the same logic." But speculative launches happen *before* expansion scoring is complete — Step 2.2a.6 precedes Step 2.2b. This means `routing_adjust_expansion_tier` cannot be applied to speculative launches at Step 2.2a.6 because the `expansion_score` is not yet available.

The brainstorm assumes speculative launches and expansion-scored launches use the same tier adjustment logic, but they cannot — speculative launches have no score at the time they're dispatched. This is a timing inconsistency, not a blocking issue, but the implementation sketch (lines 145–158) should explicitly note that speculative launches (Step 2.2a.6) use the *pre-score* model map, and only post-score launches (Step 2.2c) use `routing_adjust_expansion_tier`. The current text implies they use the same code path, which is incorrect.

---

## Summary

The centralization critique reveals one real P1: `routing_adjust_expansion_tier` needs a two-line fallback guard to prevent silent misconfiguration from becoming a dispatch error. The token reinvestment gap (P2) is a systematic optimization omission — savings are tracked but never recycled. The preferred-floor tier (P2) would prevent haiku downgrades from silently under-resourcing agents whose domains require sonnet reasoning even if they aren't safety-critical.
