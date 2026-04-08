### Findings Index
- P1 | ESQ-1 | "Design Space" | Expansion score distribution likely clusters at 2, making tier differentiation a no-op for most runs
- P2 | ESQ-2 | "Design Space" | Score=3 via three domain-injection matches is treated identically to score=3 via one P0 finding — different evidence quality, same tier
- P2 | ESQ-3 | "Open Questions" | No validation that haiku-tier agents maintain acceptable finding recall
- P3 | ESQ-4 | "Open Questions" | Trust multiplier interaction with tier adjustment is unspecified
Verdict: needs-changes

## Summary

The brainstorm maps expansion scores (0-3) to model tier adjustments. The mapping is sound for the extreme cases (score=3 keeps model, score=1 downgrades), but the middle case (score=2, "keep model") is likely where most agents land — making the entire cross-model dispatch a no-op in practice. The signal has insufficient entropy for meaningful tier differentiation unless the scoring algorithm is refined.

## Issues Found

### 1. [P1] ESQ-1: Score distribution clusters at 2, nullifying tier differentiation

**File:** `interverse/interflux/skills/flux-drive/phases/expansion.md`, lines 142-149 (expansion scoring algorithm)
**Brainstorm ref:** "Design Space" Option A, lines 55-58

The expansion scoring algorithm:
```
P0 in adjacent domain: +3
P1 in adjacent domain: +2
Stage 1 disagreement:  +2
Domain injection match: +1
```

For a typical flux-drive run with 3 Stage 1 agents producing mixed P1/P2 findings:
- Most Stage 2 agents will have at least one adjacent P1 finding (+2) or a domain injection match (+1)
- Score=3 requires a P0 finding OR (P1 + domain injection), which is uncommon
- Score=1 requires only a domain injection match with no adjacent findings, which only happens for distant agents
- Score=0 never reaches dispatch (expansion blocks it)

**Practical distribution estimate:** 60-70% of expansion candidates will score exactly 2. The brainstorm maps score=2 to "keep model" — so for most agents, cross-model dispatch changes nothing.

**Evidence:** The brainstorm's own logging example (line 163-168) shows 3 agents: score=3 (keep), score=1 (downgrade), score=2 (keep). Only 1 of 3 agents was adjusted. This is consistent with the clustering hypothesis.

**Impact:** The "15-40K token savings per run" success criterion (line 217) depends on enough agents being downgraded. If 70% score=2 (unchanged), savings come only from the rare score=1 agents — likely 0-1 per run. Expected savings: 0-15K, not 15-40K.

**Smallest fix:** Refine the tier mapping to differentiate within score=2:
- Score=2 from P1 finding: keep model
- Score=2 from disagreement: keep model (arbitration needs capability)
- Score=2 from (domain injection + domain injection): downgrade (weak compound signal)

This requires the scoring algorithm to expose the *composition* of the score, not just the total. See ESQ-2.

### 2. [P2] ESQ-2: Score composition matters but is discarded

**File:** brainstorm "Design Space" Option B, lines 68-80
**Codebase ref:** expansion.md lines 142-149

The brainstorm acknowledges this in Option B ("Finding-Driven Tier Selection") but dismisses it as "redundant with Option A." It is not redundant — it is the missing dimension.

A score of 3 can arise from:
- One P0 finding in adjacent domain (+3)
- One P1 finding (+2) + one domain injection match (+1)
- Three domain injection matches (+1+1+1) — impossible, each agent has at most 1 injection match

A score of 2 can arise from:
- One P1 finding in adjacent domain (+2)
- One Stage 1 disagreement (+2)
- Two domain injection matches (+1+1) — impossible (max 1)
- One domain injection (+1) + ??? — no, +1 alone is score=1

So score=2 is always from exactly one signal (P1 or disagreement). This means the score IS the signal type for score=2. The brainstorm could map: P1-triggered score=2 -> keep model, disagreement-triggered score=2 -> keep or upgrade (disagreement implies complexity worth investigating).

**Recommendation:** Annotate each expansion candidate with `trigger_type` (p0_adjacent, p1_adjacent, disagreement, domain_injection) and use this as a secondary signal when the score alone doesn't differentiate. This is a lighter version of Option B that doesn't require full finding-severity tracking.

### 3. [P2] ESQ-3: No validation of haiku-tier recall

**File:** brainstorm "Risk Assessment", line 210; "Open Questions" item 1

The brainstorm identifies "Finding quality degrades on haiku" as medium-likelihood, medium-impact risk, with mitigation via intertrust precision scores. But:

- intertrust tracks per-agent precision (false positive rate), not recall (missed findings)
- A haiku-tier agent that produces fewer findings looks *more precise* to intertrust (fewer false positives), even though it's missing real issues
- The success criterion "No regression in P0/P1 finding recall" (line 218) has no measurement mechanism

**Question:** How will P0/P1 recall be measured? Options: (a) run both tiers in shadow mode and compare findings, (b) use interspect correction evidence when a haiku agent misses something a sonnet agent catches in a later review, (c) manual spot-checks.

### 4. [P3] ESQ-4: Trust multiplier interaction

**File:** brainstorm "What We Have to Work With" item 5, line 36

Trust multipliers from intertrust are listed as available signals but not used in the tier adjustment. AgentDropout already uses trust_score < 0.5 as a +0.1 redundancy signal. Should low-trust agents be downgraded more aggressively in tier adjustment?

Arguments for: low-trust agents waste tokens regardless of tier.
Arguments against: trust is already handled by dropout; double-penalizing creates a death spiral (low trust -> downgrade -> worse findings -> lower trust).

The brainstorm should state explicitly: "Trust multipliers are NOT used in tier adjustment — they are handled by AgentDropout."

## Improvements

1. Add a "Score Distribution Analysis" section with expected distributions for common run types (small doc review, large diff, repo review). This would validate whether the 0-3 range provides enough differentiation.
2. Consider expanding the scale to 0-5 if the current 0-3 clusters too tightly.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 4 (P0: 0, P1: 1, P2: 2, P3: 1)
SUMMARY: Expansion score distribution likely clusters at 2, making cross-model dispatch a no-op for most agents. Expected savings are 0-15K, not the projected 15-40K. Score composition (trigger_type) could differentiate within the same numeric score.
---
<!-- flux-drive:complete -->
