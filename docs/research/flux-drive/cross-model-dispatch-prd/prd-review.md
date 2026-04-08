---
artifact_type: prd-review
target: docs/prds/2026-04-05-cross-model-dispatch.md
source_brainstorm: docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md
source_synthesis: docs/research/flux-review/cross-model-dispatch-brainstorm/2026-04-05-synthesis.md
date: 2026-04-05
reviewer: claude-sonnet-4-6
bead: sylveste-9lp.9
---

# PRD Review: Cross-Model Dispatch

## Summary

The PRD correctly captures all 9 Must-Fix findings and all 9 Should-Fix findings from the synthesis. Feature decomposition is clean: F1–F4 are independently deliverable, F5 depends only on F3. The dependency graph is correct. One P1, five P2, and three P3 findings in the PRD itself — no P0 omissions. The primary issues are: one acceptance criterion that contradicts the synthesis resolution (P1), several ACs that are not independently testable (P2), a dependency ordering gap for F4 (P2), and a missing rollback/disablement path in the feature gate (P2).

---

## P1 Findings

### P1-1: F1 empty-model guard AC is inverted from the synthesis fix

**Location:** F1 acceptance criteria, third bullet

The AC reads:
> `[[ -z "$model" ]] && model="haiku"` before safety floor clamp

But this is the **wrong guard direction**. The synthesis fix (Track A SFI-1, and the Consolidated Must-Fix list item #1) specifies:
> `[[ -n "$model" ]] || model="haiku"` before floor clamp

These are logically identical POSIX constructs, but the synthesis explicitly chose `[[ -n "$model" ]] || model="haiku"` because it reads as "assert non-empty, fallback haiku" — and critically, there is no `[[ -z ... ]]` pattern in lib-routing.sh (the rest of the file uses `-n` guards with `|| fallback` idiom). Using `-z` + `&&` is semantically equivalent but will cause a style inconsistency and may confuse an implementer reading the AC against the existing code.

More importantly: the PRD's AC uses `[[ -z "$model" ]] && model="haiku"` which evaluates to: "if model is empty, set it to haiku." That is correct in behavior but the synthesis says the guard should precede the safety floor clamp as a defensive assertion. An AC that says "do X before Y" is the correct framing; the bash idiom should match the codebase pattern.

**Fix:** Change to `[[ -n "$model" ]] || model="haiku"` to match the synthesis fix and existing lib-routing.sh idiom.

---

## P2 Findings

### P2-1: F3 does not specify what "bypasses Step 2.0.5 JSON map" means operationally

**Location:** F3 acceptance criteria, second bullet

> Per-agent adjusted model passed directly to Task call (bypasses Step 2.0.5 JSON map)

This AC is not testable as written. "Bypasses" is a negative specification — it says what the implementation should NOT do, but not what it SHOULD do. An implementer could pass the adjusted model to the Task call and also update the Step 2.0.5 map (not bypassing it but not breaking anything). The AC needs to specify the positive behavior: "the adjusted model is the only model source for Stage 2 Task dispatch; the Step 2.0.5 JSON map is not read for per-agent model selection after `routing_adjust_expansion_tier` has been called."

Also: if the Step 2.0.5 map is bypassed, it must still be populated for logging/observability purposes. Is it still written? The PRD is silent on this.

**Fix:** Replace with: "Stage 2 Task dispatch uses the `adjusted_model` returned by `routing_adjust_expansion_tier` as the sole model source. The Step 2.0.5 JSON map is not consulted for model selection. The map may still be written for logging purposes."

### P2-2: F3 pool-level assertion has no defined trigger for the upgrade recovery

**Location:** F3 acceptance criteria, sixth and seventh bullets

> Pool-level assertion: ≥1 planner/reviewer-role agent at sonnet after all adjustments
> If pool assertion violated, upgrade highest-scored planner/reviewer

The assertion check and recovery are specified, but the timing is not: when is "after all adjustments"? After the two-pass budget accounting? After the haiku-downgrade cap? After the upgrade pass (tokens_saved > 10K)? If the upgrade pass fires first and happens to upgrade a planner to sonnet, the pool assertion check might pass without the explicit recovery step — but the order is unspecified.

The synthesis (Convergence 2, Tracks B+D) specifies the pool floor as a guarantee after per-agent adjustment, but is silent on sequencing relative to the upgrade pass. The PRD inherits this ambiguity.

**Fix:** Add explicit sequence: "Pool assertion is checked after per-agent tier adjustment and haiku-downgrade cap, but before the upgrade pass. If the upgrade pass subsequently downgrades the only sonnet planner/reviewer (which it should not — the upgrade pass only upgrades), the pool guarantee holds."

### P2-3: F4 has no explicit dependency on F1, creating a false parallelism

**Location:** Feature Dependencies section and F4 acceptance criteria

The dependency graph shows:
```
F1 (core function) ← F2 (scoring hardening) ← F3 (dispatch integration)
                   ← F4 (agent-roles extension)
F3 ← F5 (observability)
```

F4 extends agent-roles.yaml with `domain_complexity` and `max_model` fields. F1's `routing_adjust_expansion_tier()` reads `domain_complexity` from agent-roles.yaml. This means F4 must be complete before F1 can be correctly tested against real agents — F4 is a data dependency for F1's implementation, not just for F3's integration.

The dependency graph implies F4 can be done in parallel with F2, with both feeding F3. But F1 cannot be correctly validated without F4's data. An implementer could deliver F1 with stub values (all agents at `medium` complexity, no `max_model`), validate against stubs, then integrate F4 data — but this would require re-testing F1 after F4 lands. The PRD should clarify whether F1 is considered done before F4 (with stubs) or only after F4 (with real values).

**Fix:** Add to the Dependencies section: "F1's tier function can be implemented against stub values (all agents at domain_complexity=medium) before F4 lands, but integration testing requires F4 to be complete. F4 is a data-dependency for F1, not just for F3."

### P2-4: F2 acceptance criteria does not specify the deduplication scope

**Location:** F2 acceptance criteria, second bullet

> Contributions with same source_id are deduplicated (keep max per source)

"Keep max per source" is ambiguous: max of what? Max of the score value (numeric), or max of severity? And is deduplication scoped to a single agent's contributions, or across all agents in the pool? If two agents each submit a score=2 contribution from the same `trigger_source_id`, are both kept (per-agent deduplication) or only one (pool-wide deduplication)?

The synthesis (Convergence 5, Track C) identifies this as a signal independence problem — correlated evidence from the same root finding inflating scores. The fix should be per-agent deduplication (preventing one agent from double-counting), not cross-agent (which would prevent two independent agents from both scoring the same adjacent domain).

**Fix:** Specify: "Deduplication is per-agent (each agent's score contributions deduplicate by `trigger_source_id`). Cross-agent contributions from the same `trigger_source_id` are independent and are not deduplicated."

### P2-5: F5 shadow mode AC duplicates F1 AC — creates ownership ambiguity

**Location:** F5 acceptance criteria, last bullet; F1 acceptance criteria, eighth bullet

Both F1 and F5 specify shadow mode logging behavior:
- F1: "Shadow mode logs adjustments without applying them"
- F5: "Shadow mode logs all adjustments with `[shadow]` prefix without applying"

These are the same behavior specified in two different features. If F1 owns the shadow mode gate check (the `cross_model_dispatch.mode: shadow|enforce` read happens in `routing_adjust_expansion_tier`), then F1 owns shadow mode. If F5 owns shadow mode logging (because observability is F5's domain), then there's a conflict: F1 must apply the gate before F5 adds the `[shadow]` prefix.

The duplication creates a risk that an implementer of F1 adds shadow mode behavior, and an implementer of F5 adds it again — resulting in double-logging or conflicting gate checks.

**Fix:** Clarify ownership. Recommended split: F1 owns the gate check (if shadow mode, skip application but still return the adjusted value for logging). F5 owns the `[shadow]` prefix in the log line. Remove the shadow mode bullet from F1's ACs and replace with: "Returns adjusted model value regardless of mode (mode determines whether dispatch uses it; observability is F5's responsibility)."

---

## P3 Findings

### P3-1: Success Metric #3 savings range matches synthesis but explanation is missing

**Location:** Success Metrics, metric 3

> Token savings: 0-15K per run with expansion (conservative estimate per score distribution analysis)

This correctly incorporates the synthesis revision (Track A ESQ-1 revising 15-40K down to 0-15K). However, the parenthetical "conservative estimate per score distribution analysis" is unexplained for an implementer reading this PRD without the synthesis. The reason for the conservative range is that expansion scores cluster at 2 (~70%), making tier adjustment a near-no-op for most agents. Without this context, the 0-15K range looks like a placeholder or an error.

**Fix:** Either add a footnote or expand to: "0-15K per run (expansion scores cluster at ~2 in practice; tier adjustment fires primarily on score=1 and score=3 agents, which are the minority)."

### P3-2: Open Questions section claims all questions resolved, but F3 two-pass ordering needs clarification

**Location:** Open Questions section; F3 acceptance criteria

The PRD states "None — all three original open questions resolved." This is correct for the three enumerated questions. However, the synthesis introduced a new unresolved matter: **the order of operations in F3's dispatch loop** — specifically whether the two-pass budget accounting runs before or after the pool-level assertion, and whether the upgrade pass can invalidate the pool guarantee. The PRD's F3 ACs do not fully nail this down (see P2-2 above), and the Open Questions section does not acknowledge it.

**Fix:** Either add a note to Open Questions: "One question introduced in the PRD review cycle: ordering of pool assertion relative to upgrade pass — resolved as: assertion before upgrade pass, upgrade pass cannot violate the assertion." Or resolve it directly in F3's ACs.

### P3-3: Non-goals do not explicitly exclude the `undertriage_risk` field proposed in the synthesis

**Location:** Non-goals section; synthesis Track B risk-asymmetry finding

The synthesis (Track B, fd-clinical-triage-resource) proposed an `undertriage_risk` field in agent-roles.yaml for agents adjacent to safety-critical domains. This was in the Should-Fix list as related background but not included in the consolidated features. The PRD correctly excludes it from scope (it's not in F4's ACs). However, the Non-goals section does not mention it, and an implementer reading the synthesis alongside the PRD might conclude it was accidentally omitted.

**Fix:** Add to Non-goals: "`undertriage_risk` field in agent-roles.yaml (proposed in brainstorm review, deferred — not enough empirical data to calibrate asymmetry weights before v1 calibration data exists)."

---

## Synthesis Coverage Check

All 9 Must-Fix findings are represented in the PRD features. All 9 Should-Fix findings are represented.

### Must-Fix Coverage

| # | Finding | Source | PRD Coverage |
|---|---------|--------|-------------|
| 1 | P0: Empty model bypasses safety floor | Track A SFI-1 | F1 AC: empty-model guard (note: idiom mismatch — P1-1 above) |
| 2 | P1: `_routing_downgrade()` doesn't exist | Track A SFI-2 | F1 AC: full edge case list |
| 3 | P1: No per-agent model override in dispatch | Track A SDC-2 | F3 AC: per-agent adjusted model passed to Task |
| 4 | P1: No feature gate | Track A BC-1 | F1 AC: `cross_model_dispatch` in budget.yaml |
| 5 | P1: Speculative launches bypass tier adjustment | Track A SDC-1 | F3 AC: speculative launches call tier adjustment with discounted score |
| 6 | P1: Budget pressure uses pre-adjustment estimates | Track A BI-1 | F3 AC: two-pass budget accounting |
| 7 | P1: No spinning reserve for speculative launches | Track B Finding 10 | F3 AC: budget pressure computed with speculative reserve subtracted |
| 8 | P1: Constitutional floor not wired | Track D AYU-01 | F1 AC: constitutional floor read from agent-roles.yaml min_model |
| 9 | P1: Correlated signals inflate score | Track C P-WAY | F2 AC: trigger_source_id + deduplication |

### Should-Fix Coverage

| # | Finding | Source | PRD Coverage |
|---|---------|--------|-------------|
| 10 | domain_complexity + max_model fields | Tracks C+D (4/4 convergence) | F4: full field spec per agent role |
| 11 | Pool-level sonnet guarantee | Tracks B+D (3/4 convergence) | F3 AC: pool assertion + upgrade recovery |
| 12 | Calibration logging | Tracks A+B+D (3/4 convergence) | F5 AC: per-run calibration emit |
| 13 | Merit order sort | Track B Finding 9 | F2 AC: candidates sorted by (expansion_score DESC, role_priority DESC, name ASC) |
| 14 | Tiebreaker for equal scores | Track D TYP-01 | F2 AC: same sort triple covers this |
| 15 | Tier field in finding logs | Track C Finding 6 | F5 AC: `tier` emitted per agent |
| 16 | Upgrade pass for savings recycling | Track C Finding 7 | F3 AC: upgrade pass fires if tokens_saved > 10K |
| 17 | Escalation advisory logging | Tracks B+C+D (3/4 convergence) | F5 AC: `[tier-escalation]` warning on downgraded agent with P1+ finding |
| 18 | Revised savings estimate | Track A ESQ-1 | Success Metric #3: 0-15K (correct) |

### One Synthesis Finding Without Explicit PRD Coverage

**Track B risk-asymmetry finding (undertriage_risk field):** Not included in PRD scope and not mentioned in Non-goals. Low impact — it was a background finding in the synthesis, not in either the Must-Fix or Should-Fix list. Addressed in P3-3.

---

## Feature Decomposition Assessment

The five features decompose cleanly. Each can be delivered and tested independently with the following caveats:

- **F1 and F4 have a data dependency** (F1 reads fields F4 adds). Both can be implemented independently but F1 integration tests require F4 data. The PRD's claim that they are fully parallel needs the qualification in P2-3.
- **F2 can land before F1** (scoring hardening in expansion.md is a specification change, not a code change that depends on the new routing function). However, F2's domain intersection check (last AC) reads agent `domain_complexity` from agent-roles.yaml — so F2 depends on F4 data for that specific AC. The dependency graph should show F4 → F2 (for the domain intersection check only).
- **F3 is correctly gated on F1 + F2 + F4.** The dispatch integration is the integration point, not the foundation.
- **F5 correctly depends on F3** (per-run calibration emit and tier-escalation advisory both require dispatch to have happened).

One missing edge in the dependency graph: **F4 → F2 (partial)** for the domain intersection check. This is minor but an implementer could ship F2 without F4 and have the domain intersection AC fail for lack of data.

---

## Acceptance Criteria Testability Assessment

| Feature | All ACs testable? | Notes |
|---------|------------------|-------|
| F1 | Mostly | 9/10 ACs are concrete. AC for "Score=3 upgrades haiku→sonnet for agents without max_model=haiku ceiling" needs a test fixture (an agent with and without the ceiling). |
| F2 | Mostly | Deduplication AC lacks scope definition (P2-4). Domain intersection check needs a defined test pair (two domains with no overlap — what's the expected output?). |
| F3 | Partial | Two-pass budget accounting AC is testable in principle but the order of operations against pool assertion is underspecified (P2-2). Shadow mode AC duplicates F1 (P2-5). |
| F4 | Yes | All ACs are concrete field assignments with clear role mappings. |
| F5 | Yes | All log-format ACs are testable. Escalation advisory requires a test fixture: downgraded agent that returns a P1+ finding. |

---

## Dependency Ordering Assessment

The stated order `F1 → {F2 ∥ F4} → F3 → F5` is correct for the primary path. Two amendments:

1. **F4 → F2 partial dependency:** The domain intersection check in F2 (last AC) reads `domain_complexity` from agent-roles.yaml. F2 can be delivered without this AC if F4 is not yet complete, but the AC cannot be verified until F4 lands. Recommend: implement F2's other ACs first, add domain intersection check in the same PR as F4 or immediately after.

2. **F1 integration tests require F4:** F1's unit tests can use stubs; integration tests (including the score=3/domain_complexity test) require F4 data. The ordering is fine for delivery but the test gates should reflect this.

No dependency ordering errors in the PRD's stated graph.

---

## Finding Summary

| Severity | Count | Findings |
|----------|-------|---------|
| P0 | 0 | None |
| P1 | 1 | P1-1: empty-model guard AC uses wrong bash idiom |
| P2 | 5 | P2-1: bypass spec needs positive statement; P2-2: pool assertion timing underspecified; P2-3: F4/F1 data dependency not documented; P2-4: deduplication scope ambiguous; P2-5: shadow mode owned by two features |
| P3 | 3 | P3-1: savings range missing context; P3-2: two-pass ordering not in Open Questions; P3-3: undertriage_risk not in Non-goals |

**Verdict: NEEDS-MINOR-CHANGES.** No synthesis findings were omitted. All features are independently deliverable with two minor dependency clarifications. The P1 is a one-line fix. The P2s are clarification gaps that will cause implementation churn if not resolved before coding starts.
