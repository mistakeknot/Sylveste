---
artifact_type: review-synthesis
method: flux-review
target: "docs/plans/2026-04-01-interflux-reaction-round-activation.md"
target_description: "Interflux reaction round activation — validate and wire Phase 2.5"
tracks: 4
track_a_agents: [fd-bash-structured-parsing, fd-convergence-gate-consensus, fd-discourse-topology-visibility, fd-prompt-template-engineering, fd-evidence-pipeline-integrity]
track_b_agents: [fd-broadcast-engineering, fd-intelligence-analysis, fd-clinical-quality-improvement, fd-newsroom-workflow]
track_c_agents: [fd-japanese-sword-polishing-togishi, fd-ottoman-waqf-endowment, fd-raga-melodic-grammar, fd-tibetan-terma-concealment]
track_d_agents: [fd-shipibo-kene-synesthetic-convergence, fd-ice-core-multiproxy-reconciliation, fd-talmudic-machloket-preserved-dissent]
date: 2026-04-02
---

# Cross-Track Synthesis: Reaction Round Activation Plan

## Critical Findings (P0/P1)

### 1. Convergence gate is degenerate for small agent populations
**Tracks:** A (P0-2), B (P1-1, P1-2), C (ARCH-01) — **3/4 tracks converge**
**Convergence score: 3/4**

The overlap_ratio formula (`findings_with_2plus_agents / total_p0_p1_findings`) produces near-1.0 values for N=2-3 agents (the common Stage 1 dispatch). With 2 agents, any shared finding pushes overlap above the 0.6 threshold, skipping reactions. Additionally, peer-findings.jsonl sharing in Phase 2 creates artificial convergence — agents that read peer findings and independently validate them are double-counted as "independent discovery."

- Track A frames this as a **mathematical degeneracy** (the formula is N-dependent)
- Track B frames this as an **uncalibrated signal switch** (broadcast engineering) and **untested threshold** (clinical QI)
- Track C frames this as a **missing deterministic implementation** (read-indexes doesn't compute overlap)

**Fix required:** Scale threshold with agent count, exclude peer-primed findings, or switch to Jaccard index. Add baseline measurement task using 3-5 past review outputs.

### 2. Evidence emission references data that doesn't exist yet
**Tracks:** A (P0-3, P1-2), B (P0-1), C (EVIDENCE-01, EVIDENCE-02) — **3/4 tracks converge**
**Convergence score: 3/4**

Task 5 specifies emitting `convergence_after`, `sycophancy_flags`, and `discourse_health` in the Interspect context JSON at the end of Phase 2.5. But `convergence_after` is never computed (no post-reaction overlap recalculation exists), and sycophancy/discourse health are computed during Phase 3 synthesis — after Phase 2.5 completes.

- Track A identifies the **temporal impossibility** (data computed in Phase 3, emitted in Phase 2.5)
- Track B identifies the **missing schema contract** (context JSON fields have no types/units/required spec)
- Track C identifies the **missing post-reaction measurement** (togishi: no "late-stage assessment")

**Fix required:** Split into two events: `reaction-dispatched` (Phase 2.5, with agents_dispatched + convergence_before) and `reaction-outcome` (after Phase 3, with convergence_after + sycophancy + discourse health).

### 3. findings-helper.sh read-indexes output doesn't support overlap computation
**Tracks:** A (P1-3), B (P1-1), C (ARCH-01) — **3/4 tracks converge**
**Convergence score: 3/4**

`read-indexes` outputs tab-separated lines but doesn't group, deduplicate, or count multi-agent overlap. The convergence gate needs overlap_ratio as a float. The gap between raw index lines and a float is currently filled by LLM interpretation — no deterministic path exists.

Additionally, the awk extraction (`/^### Findings Index/`) is case-sensitive and whitespace-sensitive (Track A, P1-3). LLM-generated agent output frequently deviates.

**Fix required:** Either extend findings-helper.sh with a `convergence` subcommand, or document the exact shell pipeline that transforms read-indexes output into overlap_ratio.

### 4. Sycophancy thresholds are inert for typical populations
**Tracks:** D (TALMUDIC-01) — **1/4 tracks (esoteric only)**
**Convergence score: 1/4 — but qualitatively novel**

With 5-10 agents, the 0.8 agreement threshold only fires when literally every agent agrees (the trivial case the convergence gate already handles). A single dissenting agent on any finding drops the rate below threshold.

This finding appeared **only in Track D** — the Talmudic agent's theory of "counted agreement" (a sage's assent only counts with independent reasoning, calibrated to academy size) surfaced a population-size dependency invisible to domain experts.

**Fix required:** Calibrate thresholds for actual agent populations (5-10). Consider per-finding sycophancy rather than per-review global scores.

### 5. No minority finding preservation test
**Tracks:** D (TALMUDIC-02) — **1/4 tracks (esoteric only)**
**Convergence score: 1/4 — but high severity**

Task 4 checks for reaction sections in synthesis but never verifies that a P0 finding surviving majority-disagree reactions is preserved as "contested" rather than dropped. A legitimate safety P0 contested by three non-safety agents could be suppressed.

The Talmudic lens ("Beit Shammai's opinions are recorded not as curiosities but as legal elements that future courts can reinstate") reveals this as a fundamental design requirement, not a test gap.

**Fix required:** Add negative test case to Task 6: insert a disagreement reaction for a P0 finding and verify it appears as contested in synthesis.

### 6. No skip-logging when convergence gate trips
**Tracks:** B (P1-2), C (togishi) — **2/4 tracks converge**
**Convergence score: 2/4**

When the gate skips reactions, no evidence event is emitted. Future analysis can't distinguish "disabled" from "skipped by gate." The 0.6 threshold can't be calibrated without data on when it fires.

**Fix required:** Emit a skip event with overlap_ratio, threshold, and finding count. Write reaction-skipped.json to OUTPUT_DIR.

## Cross-Track Convergence

| Finding | Track A | Track B | Track C | Track D | Score |
|---------|---------|---------|---------|---------|-------|
| Convergence gate degenerate for small N | P0-2 | P1-1,2 | ARCH-01 | — | **3/4** |
| Evidence emission temporal impossibility | P0-3, P1-2 | P0-1 | EVIDENCE-01,02 | — | **3/4** |
| read-indexes doesn't support overlap computation | P1-3 | P1-1 | ARCH-01 | — | **3/4** |
| No skip-logging for convergence gate | — | P1-2 | togishi | — | **2/4** |
| Corrupted flux-gen agent files | noted | P1-5 | noted | — | **3/4** |
| Sycophancy thresholds population-inert | — | — | — | TALMUDIC-01 | **1/4** |
| Minority finding preservation | — | — | — | TALMUDIC-02 | **1/4** |
| Lorenzen missing partial-distinction | — | — | — | TALMUDIC-03 | **1/4** |
| Fixative timing not enforced | — | — | — | SHIPIBO-01 | **1/4** |

## Domain-Expert Insights (Track A)

The adjacent-domain agents performed deep code tracing that no other track attempted:
- **fd-bash-structured-parsing** found the awk heading extraction is case/whitespace-sensitive (P1-3)
- **fd-convergence-gate-consensus** identified the mathematical degeneracy of the overlap formula for N=2 (P0-2)
- **fd-evidence-pipeline-integrity** traced the temporal impossibility of Phase 2.5 emission referencing Phase 3 data (P0-3)
- **fd-prompt-template-engineering** found that reaction prompts lack the initial review format spec for reactive additions (P1-5)

## Parallel-Discipline Insights (Track B)

- **Broadcast engineering**: No "rundown sheet" — agents entering the reaction round have no manifest of what was dispatched and what completed. Synthesis infers from file presence.
- **Intelligence analysis**: Peer-findings.jsonl creates "circular reporting" — agents validating peer findings produces artificial convergence indistinguishable from independent discovery.
- **Clinical QI**: The convergence gate skip requires documented justification (the "no-change decision path" principle from quality improvement methodology).
- **Newsroom workflow**: No correction propagation — if a reaction reveals an original finding was wrong, there's no mechanism to retract or update downstream references.

## Structural Insights (Track C)

- **Togishi (sword polishing)**: Missing "uchigumori stage" — a post-reaction crystallization measurement. The convergence gate measures before reactions; nothing measures after. If reactions degrade convergence, it's invisible.
- **Waqf (endowment)**: The hearsay rule operates post-hoc in synthesis, not during dispatch. Fabricated file:line evidence passes with full weight because no validation checks references against actual files.
- **Terma (concealment)**: No structured dispatch manifest. The system relies on filesystem glob to discover what happened rather than maintaining a definitive record.

## Frontier Patterns (Track D)

Track D produced the three most architecturally novel findings in the entire review:

1. **Talmudic sycophancy calibration** — the population-size dependency of agreement thresholds was invisible to all 13 other agents. The Talmudic tradition's explicit rules for when assent "counts" provided a formal framework for reasoning about threshold calibration.

2. **Talmudic minority preservation** — the principle that dissent must be structurally preserved (not just acknowledged) revealed that Task 4's verification is semantically shallow. Checking for "reaction sections" is not the same as checking for "minority findings preserved."

3. **Shipibo fixative timing** — the perceptual contamination model (melodic capture) identified a race condition invisible to implementation-focused agents: the LLM orchestrator might parallelize fixative computation and reaction dispatch, causing fixative context to be empty.

## Synthesis Assessment

- **Overall quality of the plan:** Structurally sound — correct execution order, right files identified, risks acknowledged. But the plan is a **Phase 1/2 plan** (defaults + collection) pretending to be a **Phase 3/4 plan** (calibration + feedback). Key thresholds are untested, evidence emission is temporally impossible as designed, and the convergence gate formula doesn't work for typical deployments.

- **Highest-leverage improvement:** Fix the convergence gate formula and add baseline measurement. Without this, reactions never fire in the most common scenario (2-3 agents), making the entire feature dead code.

- **Surprising finding:** The sycophancy threshold population-dependency (Track D, Talmudic). No domain expert or parallel-discipline agent identified this — it required a formal theory of "counted agreement" from a 3rd-5th century Babylonian legal tradition to surface a mathematical property of a 2026 agent configuration file.

- **Semantic distance value:** Track D contributed 3 qualitatively novel P1 findings that no other track surfaced. Track C provided structural metaphors that reframed known issues (togishi's post-reaction measurement, terma's dispatch manifest). Tracks A-B found the same core issues through different lenses. The outer tracks (C/D) justified their cost — they didn't restate known issues in different vocabulary; they found genuinely different things.
