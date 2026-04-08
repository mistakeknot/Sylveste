# fd-japanese-sword-testing: Capability Verification & Service-Tier Match Review

**Reviewer:** fd-japanese-sword-testing (Edo tameshi — graded blade testing, service-tier certification)
**Document:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
**Date:** 2026-04-04
**Scope:** Assign-without-verify risk, agent-domain difficulty compatibility, wasteful over-assignment, retirement/exclusion criteria, overtesting cost
**Track:** C — Distant domain structural isomorphism

---

## Executive Summary

The tameshigiri lens asks a question the brainstorm does not: **is the assigned tier appropriate not just for the evidence that triggered the expansion, but for the domain the agent must reason about?**

A battlefield blade assigned to ceremonial duty is wasteful. A ceremonial blade assigned to battlefield duty is dangerous. The brainstorm addresses the dangerous case (safety floors ensure critical agents aren't under-resourced), but the wasteful case is entirely unexamined: an agent assigned to opus/sonnet tier because a high-score expansion triggered it may be doing work that haiku handles perfectly well in its domain.

More critically: a haiku agent on a domain that exceeds haiku's reasoning capacity will produce incoherent findings regardless of the expansion score that justified its launch. The score tells us the evidence was strong; it does not tell us the agent can handle the domain at the assigned tier.

---

## P2 Findings

### [P2] Tier assignment uses expansion score (evidence strength) but ignores agent-domain difficulty (reasoning requirement) — these are independent axes (brainstorm, "Design Space — Option A" section, lines 54–65; "Implementation Sketch" section, lines 119–142)

The brainstorm's tier decision function signature is:

```bash
routing_adjust_expansion_tier <agent> <current_model> <expansion_score> <budget_pressure>
```

The inputs are: the agent name, the B1-resolved model, the expansion score (evidence strength), and budget pressure. Absent from the function signature: any representation of the agent's domain difficulty or the complexity of the specific task it is being asked to perform.

In tameshigiri, a blade is tested on cutting targets that match its intended service tier (straw targets for ceremonial, multiple layered targets for battlefield). Tier certification comes from passing the test, not from the quality of the steel that went into the blade. A blade forged from excellent steel but poorly tempered for ceremonial work fails on ceremonial tests despite the quality inputs.

The brainstorm's function assigns tier based on evidence quality (expansion score = input quality) without verifying that the agent can perform at that tier for this domain (capability certification = output quality). This creates two failure modes:

**Failure mode A — haiku on complex domain:** `fd-decisions` is downgraded to haiku (score=1). `fd-decisions` must reason about a multi-hop agent dependency graph. Haiku's context window handling and multi-step reasoning for dependency traversal is insufficient. The finding is either incomplete or misattributes the dependency chain. A real P1 is reported as "no issues found."

**Failure mode B — sonnet/opus on trivial domain:** `fd-perception` is maintained at sonnet (score=3) because an adjacent P0 triggered a high expansion score. `fd-perception` must check whether a specific UI signal is properly debounced. This is a pattern match: does the code call `debounce(signal, 300)` before dispatch? Haiku handles this correctly. Sonnet tokens are spent on a search operation.

**Concrete scenario for failure mode A:** `fd-game-design` on a complex game-theory Nash equilibrium tradeoff. Score=1 (weak signal). Downgraded to haiku. Haiku evaluates only the surface-level game structure, not the second-order equilibrium implications. A P1 design tradeoff is missed because the reasoning chain required exceeds haiku's practical depth on this domain.

**Smallest fix:** Add a `domain_complexity` field to agent-roles.yaml: `low | medium | high`. The `routing_adjust_expansion_tier` function consults this field when computing the floor:

- `domain_complexity: high` agents cannot be downgraded below sonnet regardless of score (this is a reasoning floor, distinct from the safety floor)
- `domain_complexity: medium` agents can be downgraded one tier
- `domain_complexity: low` agents can be downgraded to haiku without concern

This is a two-axis decision: evidence strength (expansion score) × domain difficulty (`domain_complexity`). The resulting tier is `max(score_tier, complexity_floor_tier, safety_floor_tier)`. The brainstorm currently implements only the score axis and the safety-floor axis; the complexity axis is missing.

---

### [P2] The wasteful over-assignment case (high score on simple domain) is unaddressed (brainstorm, "Design Space — Option A" section, lines 54–65; "Risk Assessment" table, lines 206–212)

The risk table addresses under-resourcing (finding quality degrades on haiku) but not over-resourcing (high-expansion-score agent assigned to sonnet/opus on a pattern-match domain). The brainstorm's "keep or upgrade" for score=3 has no upper bound check.

In tameshigiri, a master swordsmith's finest blade is never used for straw-mat cutting practice. Wasteful deployment of high-capability blades is culturally prohibited. The brainstorm implicitly allows: score=3 + agent=fd-perception → agent runs at sonnet (or potentially opus after upgrade) → agent performs a regex search that haiku would complete correctly at 1/10th the cost.

The safety floors are one-directional (minimum): they prevent going below a threshold. There are no complexity ceilings (maximum): nothing prevents dispatching an opus agent to a `grep`-equivalent task because an adjacent P0 inflated the expansion score.

**Failure scenario:** Score=3 (adjacent P0). Agent=`fd-resilience`. Resilience check for this specific candidate: does the config file have a retry backoff entry? This is a key-exists check in a YAML file. Haiku performs this trivially. Sonnet is dispatched. 3K tokens on a file lookup.

**Smallest fix:** Use the same `domain_complexity` field above. For `domain_complexity: low` agents, cap the maximum tier at sonnet regardless of expansion score. The score justifies launching the agent; it does not justify upgrading a low-complexity-domain agent beyond its natural tier. Add a `max_model` constraint (symmetric to `min_model`) to `agent-roles.yaml`:

```yaml
fd-perception:
  role: checker
  model_tier: haiku
  min_model: null
  max_model: sonnet  # pattern-match domain; opus is never warranted
```

This is a one-line addition per agent and symmetric with the existing `min_model` constraint. It bounds tier in both directions.

---

## P3 Findings

### [P3] No retirement or long-term performance tracking for agents that consistently underperform at their assigned tier (brainstorm, "Open Questions" section, lines 199–203)

Open Question 3 asks whether tier adjustments should feed into interspect for calibration. The brainstorm answers "we could track (agent, original_tier, adjusted_tier, expansion_score, finding_severity)." This is correct but incomplete — the missing piece is the performance outcome: did the agent at haiku produce a finding that later proved accurate (via intertrust precision), or did it produce a false positive or missed finding?

Tameshigiri's retirement criteria are clear: a blade that fails repeated tests at a given service tier is downgraded or retired. The brainstorm's interspect tracking idea captures the inputs (what tier was assigned) but not the outcome (was the finding quality appropriate for that tier). Without the outcome, calibration is blind.

**Smallest fix:** When intertrust updates precision scores for an agent, cross-reference the agent's `adjusted_tier` from the run log. If an agent consistently underperforms at haiku (precision drops when adjusted down), this is a signal that the complexity floor for that agent is being set too low. Feed this cross-reference back to the `domain_complexity` classifier as a runtime update, not just a static YAML field. This is a Phase 2 interspect integration concern, not a blocking issue for the current brainstorm — but the data model should be designed now so the feedback loop is possible later.

### [P3] "Overtesting" — capability verification has a real token cost that should be budgeted (brainstorm, "Open Questions" section)

If a lightweight capability check (calibration prompt) is added as a pre-dispatch verification (see fd-japanese-sword-testing's test-before-deploy principle), that check itself consumes tokens. The brainstorm's success criteria measure savings from tier adjustment but do not budget for verification overhead. Even a 100-token calibration ping × N agents = meaningful overhead at scale. If capability verification is ever added, the budget pressure computation (lines 150–157) must include verification costs in the Stage 2 estimate.

---

## Summary

The tameshigiri lens contributes two P2 findings that are structurally independent from the other distant-domain reviewers:

1. **Two-axis tier decision (P2):** Expansion score (evidence strength) is only one axis. Domain complexity (reasoning requirement) is the second axis. Without it, haiku agents get deployed on domains that exceed haiku's reasoning capacity, and sonnet/opus agents get deployed on pattern-match tasks. The `domain_complexity` field in `agent-roles.yaml` addresses both failure modes with one mechanism.

2. **Missing max_model ceiling (P2):** The brainstorm has `min_model` floors but no `max_model` ceilings. A high expansion score can over-resource a low-complexity-domain agent. Adding `max_model` to `agent-roles.yaml` creates a symmetric bound.

These two gaps are distinct from the centralization critique (fd-han-salt-monopoly), the signal-independence problem (fd-polynesian-wayfinding), and the grading-validity concern (fd-venetian-glass-grading). Together they add the missing axis: not just *how strong was the evidence*, but *how hard is this domain to reason about*.
