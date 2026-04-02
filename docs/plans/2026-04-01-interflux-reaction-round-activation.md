---
artifact_type: plan
bead: sylveste-g3b
stage: plan
revision: 2
review: docs/research/flux-review/reaction-round-activation/2026-04-02-synthesis.md
---

# Plan: Interflux Reaction Round Activation (v2)

## Overview

Validate and activate the interflux reaction round (Phase 2.5). All design artifacts exist — this is wiring, fixing, and testing. Revised after 4-track flux-review (16 agents) that surfaced 6 critical gaps.

## Tasks

### Task 0: Hook ID allowlist + fix corrupted agents
**Files:** `interverse/interspect/hooks/lib-interspect.sh`, `.claude/agents/fd-*.md`
**Why first:** Everything downstream depends on evidence emission being wirable. Corrupted agents will waste tokens in end-to-end tests.
1. Add `interspect-reaction` to `_interspect_validate_hook_id()` case statement
2. Delete corrupted flux-gen agents (character-per-line bug in "What NOT to Flag" / "Success Criteria" sections)

### Task 1: Harden findings-helper.sh + add convergence subcommand
**Files:** `interverse/interflux/scripts/findings-helper.sh`
**Review findings:** A(P1-3), B(P1-1), C(ARCH-01) — 3/4 tracks converged on this gap

1. Fix awk heading extraction to be case-insensitive and whitespace-tolerant:
   `/^#{2,4}\s*[Ff]indings\s+[Ii]ndex/`
2. Add `convergence` subcommand that:
   - Calls `read-indexes` internally
   - Parses severity from each line (P0/P1/P2/etc.)
   - Groups findings by normalized title (lowercase, strip punctuation)
   - Counts how many agents report each finding
   - Computes `overlap_ratio = findings_with_2plus_agents / total_p0_p1_findings`
   - Outputs: `overlap_ratio<TAB>total_findings<TAB>overlapping_findings<TAB>agent_count`
3. Test with synthetic agent outputs (known overlap) and verify correct ratio

### Task 2: Fix convergence gate formula for small N
**Files:** `interverse/interflux/skills/flux-drive/phases/reaction.md`
**Review findings:** A(P0-2), B(P1-1,P1-2), C(ARCH-01) — 3/4 tracks converged

The overlap_ratio formula is degenerate for N=2-3 agents. Two fixes:

1. **Scale threshold with agent count:** `effective_threshold = config_threshold * (agent_count / 5)`. For N=2: threshold becomes 0.24 (reactions almost always fire). For N=5: threshold stays at 0.6. For N=8: threshold becomes 0.96 (reactions rarely fire for large fleets with natural overlap).
2. **Exclude peer-primed findings:** If `peer-findings.jsonl` exists, read it. Any finding whose first report timestamp in peer-findings.jsonl precedes a second agent's Findings Index entry is flagged as potentially primed. Discount primed findings from overlap count.
3. **Use the new `findings-helper.sh convergence` subcommand** (from Task 1) instead of LLM-interpreted shell.
4. **Add skip-logging:** When gate trips, emit `interspect-reaction` event with context `{"type": "skip", "overlap_ratio": X, "threshold": Y, "agent_count": N, "finding_count": M}`. Also write `{OUTPUT_DIR}/reaction-skipped.json`.
5. **Add sequencing note** to reaction.md: "Step 2.5.2b MUST complete before Step 2.5.3 begins — do not parallelize."

### Task 3: Split Interspect evidence emission into two events
**Files:** `interverse/interspect/hooks/lib-interspect.sh`, `phases/reaction.md`, `interverse/intersynth/agents/synthesize-review.md`
**Review findings:** A(P0-3, P1-2), B(P0-1), C(EVIDENCE-01, EVIDENCE-02) — 3/4 tracks converged

The original plan emitted one event at Phase 2.5 with data from Phase 3. Fix: two events.

**Event 1: `reaction-dispatched`** (emitted at end of Phase 2.5, Step 2.5.5)
- Add `_interspect_emit_reaction_dispatched()` to lib-interspect.sh
- Context JSON schema:
  ```
  {
    "type": "dispatched",         // string, required
    "review_id": "...",           // string, OUTPUT_DIR basename
    "input_path": "...",          // string, reviewed file
    "agents_dispatched": 5,       // integer, count
    "reactions_produced": 4,      // integer, count
    "reactions_empty": 0,         // integer, count
    "reactions_errors": 1,        // integer, count
    "convergence_before": 0.45,   // float, overlap_ratio from gate
    "agent_count": 5,             // integer, Phase 2 agents
    "fixative_injections": 2      // integer, count of fired injections
  }
  ```

**Event 2: `reaction-outcome`** (emitted after Phase 3 synthesis completes)
- Add `_interspect_emit_reaction_outcome()` to lib-interspect.sh
- Add emission call to `phases/synthesize.md` after Step 3.8
- Context JSON schema:
  ```
  {
    "type": "outcome",            // string, required
    "review_id": "...",           // string, same as dispatched event
    "convergence_after": 0.72,    // float, recomputed from synthesis findings
    "sycophancy_flags": [...],    // array of agent names flagged
    "discourse_health": {...},    // object from Sawyer envelope
    "hearsay_count": 2,           // integer, reactions classified as hearsay
    "independent_count": 8,       // integer, independent confirmations
    "contested_count": 1,         // integer, findings with divergent reactions
    "minority_preserved": true    // boolean, any contested P0/P1 retained
  }
  ```

### Task 4: Fix reaction prompt and Lorenzen taxonomy gaps
**Files:** `config/flux-drive/reaction-prompt.md`, `config/flux-drive/discourse-lorenzen.yaml`
**Review findings:** A(P1-5), D(TALMUDIC-03)

1. Add compact finding output format to reaction prompt (from shared-contracts.md) so reactive additions use a parseable structure
2. Add `partially-agree` → `distinction` move type mapping to reaction-prompt.md
3. Add `distinction` as a valid move in discourse-lorenzen.yaml with scoring weight

### Task 5: Calibrate sycophancy thresholds for actual populations
**Files:** `config/flux-drive/reaction.yaml`
**Review findings:** D(TALMUDIC-01) — esoteric-only finding, novel

1. Lower `agreement_threshold` from 0.8 to 0.65 (sensitive to 5-10 agent populations)
2. Add a comment documenting the population-size rationale
3. Consider per-finding sycophancy as a future enhancement (note in config, don't implement now)

### Task 6: End-to-end test with negative cases
**Files:** All of the above
**Review findings:** D(TALMUDIC-02), B(P1-3), C(togishi)

Run a real flux-drive review. Verify the full pipeline. Checklist:

- [ ] `.reactions.md` files produced in OUTPUT_DIR
- [ ] `synthesis.md` has Reaction Analysis / Contested Findings sections
- [ ] `findings.json` has `reactions` arrays on findings with stances and move types
- [ ] Interspect evidence table has a `reaction-dispatched` event (from Phase 2.5)
- [ ] Interspect evidence table has a `reaction-outcome` event (from Phase 3)
- [ ] **Minority preservation test:** Verify a P0/P1 finding with net-negative reaction score appears in synthesis.md as contested, not dropped
- [ ] **Skip-logging test:** Force convergence gate to trip (e.g., 2 agents, high overlap). Verify `reaction-skipped.json` written and Interspect skip event emitted
- [ ] **Fixative timing test:** Create a scenario with high Gini / low novelty. Verify fixative_context is non-empty in the reaction prompts sent to agents
- [ ] Total cost overhead measured against baseline (target: <10%)

## Execution Order

Task 0 first (unblocks everything). Tasks 1-2 sequential (2 depends on 1's convergence subcommand). Task 3 independent. Task 4 independent. Task 5 independent. Task 6 depends on all.

```
[Task 0] ─→ [Task 1] → [Task 2] ─┐
             [Task 3] ─────────────┤
             [Task 4] ─────────────┼─→ [Task 6]
             [Task 5] ─────────────┘
```

## Risks (updated)

- **Convergence gate over-correction:** Scaling threshold with N may make reactions fire too often for large fleets. Mitigation: cap effective_threshold at original config value.
- **Token cost from two evidence events:** Marginal — each is one SQLite INSERT.
- **findings-helper.sh convergence dedup is imperfect:** Title normalization can't catch semantically identical findings with different wording. Acceptable — false negatives (missing overlap) cause unnecessary reactions (more signal), not false positives (skipped reactions).
- **Negative test cases require manual fixture creation:** The minority preservation test needs a hand-crafted `.reactions.md` with a disagreement. Document the fixture format.
