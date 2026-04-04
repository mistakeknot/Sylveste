# Ockham Vision Brainstorm — Synthesis Report (Rev 3 Re-Review)

**Date:** 2026-04-03  
**Document:** `docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md`  
**Revision:** 3 (post 16-agent 4-track flux-review, re-reviewed by 7 agents)  
**Mode:** flux-drive (review mode)  
**Context:** Verification of round-1 findings + assessment of new/revised sections

---

## Validation Summary

Validation: 7/7 agents valid  
All seven agents produced properly indexed findings with `### Findings Index` sections and complete verdict lines.

---

## Verdict Summary

| Agent | Track | Findings | P0 | P1 | P2 | P3 | Status |
|-------|-------|----------|----|----|----|----|--------|
| fd-architecture | Architecture | 7 new + 5 prior resolved | 1 | 2 | 2 | 1 | needs-changes |
| fd-correctness | Correctness | 8 (P0:1, P1:3, P2:3, P3:1) | 1 | 3 | 3 | 1 | fail |
| fd-decisions | Decision Quality | 8 (P0:0, P1:0, P2:6, P3:2) | 0 | 0 | 6 | 2 | needs-changes |
| fd-quality | Quality & Style | 8 (P0:0, P1:4, P2:4) | 0 | 4 | 4 | 0 | needs-changes |
| fd-resilience | Resilience | 5 (P0:0, P1:2, P2:2, P3:1) | 0 | 2 | 2 | 1 | needs-changes |
| fd-safety | Safety | 7 (P0:0, P1:3, P2:3, P3:1) | 0 | 3 | 3 | 1 | needs-changes |
| fd-systems | Systems Thinking | 8 (P0:0, P1:4, P2:1, P3:3) | 0 | 4 | 1 | 3 | needs-changes |

**Overall Verdict:** `needs-changes`

**Gate:** FAIL  
**Rationale:** 
- P0: 1 critical finding (missing orchestration layer — no owner for Scoring assembly)
- P1: 19 findings across all tracks (architecture, correctness, quality, resilience, safety, systems)
- Multiple P0/P1 findings are execution blockers (priority-inversion bound mathematically wrong, 30-day liveness never fires without daemon, policy immutability integrity hole)

---

## Finding Categories by Severity

### P0 Findings (1) — Blocking

**fd-architecture NEW-P0: Missing orchestration layer — Scoring assembly has no owner**
- **Section:** Key Decision 1 (subsystem table)
- **Issue:** The brainstorm specifies that Scoring receives `IntentVector + AuthorityState + AnomalyState` structs, but no component is named as the orchestrator that assembles these structs and invokes Scoring. If the CLI entrypoint does it, the CLI becomes a god module. If a new `governor` package does it, that package is undesigned and unnamed.
- **Convergence:** Single agent, critical architectural gap
- **Attribution:** fd-architecture

**fd-correctness OBR-01: Priority-inversion bound is mathematically wrong**
- **Section:** Section 3, dispatch integration
- **Issue:** The brainstorm claims "priority gap between adjacent tiers is ~24 points" but the actual gap in `score_bead()` is **12 points**. This means the ±12 offset bound does **not** prevent cross-tier inversions; the correct bound is ±6 when perturbation is accounted for.
- **Convergence:** Confirmed by fd-safety OCKHAM-02 (tier gap unverified)
- **Attribution:** fd-correctness, fd-safety

---

### P1 Findings (19) — Needs Attention

#### Architecture Track
- **NEW-P1: ±12 bound does not preserve priority ordering** (fd-architecture) — actual tier gap is 12, not 24; P3+12 can outrank P2+0
- **NEW-P1: Freeze as offset -999 conflicts with floor guard and lane-pause path** (fd-architecture) — freeze mechanism has both offset and lane-pause paths; they conflict without explicit precedence
- **NEW-P2: signals.db reconciliation contract unspecified** (fd-architecture, also fd-resilience N-01) — signals.db treated as ground truth but reconciliation with primary sources (interspect, beads, interstat) is undefined
- **NEW-P2: Feedback loop (Section 10) has no actuation path** (fd-architecture) — is monitoring, not a closed loop; principal must act on Tier 1 INFORM manually

#### Correctness Track  
- **OBR-02: 30-day re-confirmation never fires on a no-daemon CLI-only design** (fd-correctness) — time-based obligation that requires scheduler, but Ockham has no daemon; re-confirmation only fires if operator happens to invoke `ockham`
- **OBR-03: Weight-drift detection baseline is undefined at first launch** (fd-correctness) — 20% threshold is not computable when baseline is zero; no minimum sample size specified
- **OBR-04: Post-Tier-2 shadow demotion snaps back immediately** (fd-correctness) — re-promotion requires passing supervised guard, but the guard was already satisfied before demotion (evidence was not erased); domain snaps back after 1h stability window
- **OBR-06: Freeze (-999 offset) contradicts the S-08 neutrality floor** (fd-correctness, also fd-architecture NEW-P1, fd-safety OCKHAM-02) — floor says no offset exceeds -24, but freeze writes -999; no documented exception

#### Quality & Style Track
- **Q-01: Self-promotion invariant remains behavioral (CLI-enforced only), not structural** (fd-quality, also fd-safety OCKHAM-01) — synthesis recommended structural guards (bd set-state rejection, dispatch validation, signed tokens); none appear in brainstorm
- **Q-02: Tier 3 bypass channel has no Clavain-independent path** (fd-quality) — halt file exists but if Clavain is hung, signal goes unheard; brainstorm lists only existing Clavain mechanisms; synthesis identified this as P0
- **Q-03: CONSTRAIN precedence over intent weights is implicit, not specified** (fd-quality) — scoring formula does not specify whether CONSTRAIN produces dispatch-eligibility gate or is just another weight input
- **Q-04: Starvation floor and idle-capacity release absent from brainstorm** (fd-quality) — synthesis found low-budget themes can be starved permanently; brainstorm has no starvation guard, floor, or idle-release mechanism

#### Resilience Track
- **R-02-b: Authority snapshot has no named persistence store** (fd-resilience) — 5-minute staleness window is meaningless if snapshot is in-memory only; unclear whether snapshot survives CLI invocation
- **N-01: signals.db is an unacknowledged single point of failure** (fd-resilience) — all temporal state (Tier 2 windows, de-escalation windows, 30-day timer) depends on signals.db; corruption/clock-skew/loss not addressed; no failure-mode recovery path

#### Safety Track
- **OCKHAM-01: Self-promotion enforcement relies on agent-writable session identity** (fd-safety) — `$CLAUDE_SESSION_ID` is agent-controllable; agent can set `CLAUDE_SESSION_ID=$peer_id` to spoof peer identity in `--actor` flag check
- **OCKHAM-02: Weight neutrality floor stated backwards; ±12 tier gap unverified** (fd-safety) — invariant reads "cannot exceed -24" (would block positive offsets, opposite of intent); tier gap figure uncited in codebase
- **OCKHAM-03: Policy immutability during halt has no integrity mechanism** (fd-safety) — `factory-paused.json` can be deleted by agents in execution environment; file deletion bypasses INV-8 halt state

#### Systems Thinking Track
- **SYS-01 (residual): 30-day re-confirmation windows unsynchronized across domains** (fd-systems) — creates phase-shifted oscillation risk; all domains re-confirm simultaneously at T=30 days
- **SYS-02 (residual): In-flight supervised agents accumulate deferred failures** (fd-systems) — freeze→supervised continuation prevents abrupt termination but creates accumulation of gate failures that re-trigger CONSTRAIN
- **SYS-NEW-01: Two feedback loops with conflicting correction signals** (fd-systems) — SUBAK-01 (theme weight-drift) and ratchet (agent hit-rate) operate at different time scales and compound downward corrections; no interaction rule specified

---

### P2 Findings (18)

#### Decision Quality Track (6)
- **D-03: 20% Drift Threshold Without Derivation** — no sensitivity analysis; becomes self-confirming once implemented
- **D-04: ±12 Offset Bound: Assertion Without Reference** — "~24 points" asserted, not cited; unverified against actual scoring constants
- **D-05: Cross-Domain Min-Tier: Sour Spot in Complex Beads** — complex beads resolve to shadow due to min-tier rule, then produce shadow evidence rather than evidence for domains they exercise
- **D-06: Weight-Drift Feedback Loop: Missing Theory of Change Between Signal and Action** — detection without correction mechanism; causal chain from signal to weight adjustment unspecified
- **D-07: Cold-Start Conservatism Applied Once, Not Continuously** — treats cold start as one-time event; domain rename/split causes recurring cold-start-equivalent regressions
- **D-08: Intercept Integration: Staged Rollout Absent** — conflates stage 2 (detection) and stage 3 (calibration) into single Wave 1 deliverable; inconsistent with project's four-stage pattern

#### Correctness Track (3)
- **OBR-05: Cross-domain resolution depends on undefined domain-to-bead mapping** — domains are path-based, beads use lanes; mapping rule missing
- **OBR-07: Promotion confirmation window duration unspecified; cold-start conservatism is non-falsifiable** — unspecified window length makes the safety property unmeasurable
- **OBR-08: Offset + perturbation composition widens effective swing to -12..+17** — effective swing is 29 points, not 12; inversion analysis does not account for perturbation

#### Quality & Style Track (4)
- **Q-05: Intercept declared as Wave 1 dependency but absent from subsystem table** — weight-outcome feedback ships Wave 1 with intercept, but intercept not listed in allowed-deps
- **Q-06: Ratchet promotion guard retains wall-clock confirmation window** — synthesis recommended evidence-quantity replacement (distinct evaluation windows); wall-clock only measures absence-of-failure, not competence
- **Q-07: Intent YAML schema lacks expiry fields** — synthesis recommended `valid_until` and `until_bead_count`; plan lists these as Wave 1 items but brainstorm schema omits them
- **Q-08: Evidence gaming deferred to Wave 3 while ratchet also ships Wave 3** — P0-convergence finding (Open Question 2) deferred with no blocking gate or named mitigation

#### Resilience Track (2)
- **N-02: Weight-drift detection threshold is a single fixed Goodhart target** — Goodhart pressure will cause agents to game the 20% threshold; multi-signal ensemble not specified
- **N-03: Policy immutability during halt can trap a partially-frozen factory indefinitely** — read-only invariant prevents correction of misconfiguration that triggered halt; recovery ordering undocumented

#### Safety Track (3)
- **OCKHAM-04: Min-tier constraint reason not recorded; feedback loop attributes shadow-constrained delays to theme perf** — weight-outcome loop will misattribute authority-constrained slowness to theme degradation
- **OCKHAM-05: freeze and focus constraint lists not validated against known theme names** — typo in freeze list silently fails to freeze; no error reported
- **OCKHAM-06: Weight-outcome feedback loop baseline undefined for new themes** — no minimum sample size; false signals during ramp-up; threshold applied to sparse data

#### Systems Thinking Track (1)
- **SYS-NEW-02: Min-Tier Rule Creates Shadow-Domain Starvation Trap** — agents rationally avoid shadow-domain beads → domains receive less dispatch → less evidence → can't promote → stay in shadow (Schelling trap)
- **SYS-NEW-03: SUBAK-01 Baseline is Ockham-Contaminated** — predicted baseline derived from historical data shaped by Ockham's own dispatch decisions; measurement endogeneity; intercept training data biased

---

### P3 Findings (6)

- **fd-architecture NEW-P3: AGENTS.md package naming diverges from brainstorm** (low-severity drift)
- **fd-correctness OBR-08 (P3 component): Offset + perturbation composition unacknowledged** (amplification of priority-inversion risk)
- **fd-quality Q-08:** Evidence gaming deferral lacks blocking gate (P3 if gate is implicit, P0 if genuinely unresolved)
- **fd-resilience N-04: Cross-domain resolution min-tier has no degradation path when domain evidence absent** (silent revert to shadow after 90-day evidence expiry)
- **fd-safety OCKHAM-07: Tier 3 restart sequence has no timeout for principal unavailability** (file-delete resume path ambiguous with attack surface)
- **fd-systems SYS-NEW-04: Min-Tier computed at dispatch, not locked at claim** (mid-sprint tier changes not specified in audit trail)

---

## Prior Findings Verification

### Round 1 Fixes Verified as Correct

**Bead-to-theme mapping (P0):** RESOLVED  
All agents confirm: `theme = bead.lane` with fallback to `open` for unlaned beads.

**Dispatch renamed to Scoring with typed structs (P1):** PARTIALLY RESOLVED  
Brainstorm names the package correctly. AGENTS.md/CLAUDE.md still use `dispatch`. Documentation/implementation alignment gap identified (fd-architecture NEW-P3, low-severity).

**ockham_weight injection timing (P1):** RESOLVED  
Bulk pre-fetch, placement before perturbation and floor guard, logging of raw/final scores. All correct.

**CLI temporal model (P1):** RESOLVED  
signals.db for persistent timestamps. Correct mechanism, but failure modes unaddressed (fd-resilience N-01 P1).

**Tier 3 write/notify ordering (P1):** RESOLVED  
Write factory-paused.json first, then notify. Correct.

**Ratchet transition guards (P1):** RESOLVED  
Explicit guards on all promotion rows with specificity (hit_rate, sessions, confidence thresholds).

**De-escalation semantics (P1):** RESOLVED  
Both windows must simultaneously drop, then stability window equal to short window must pass with no re-fire.

### Round 1 Issues with Residual Gaps

**Weight multiplier/priority inversion (C-02, now OBR-01):** REGRESSED  
Round 1 correctly switched from multipliers to additive offsets. Round 2 claimed this prevented inversion. Round 3 reveals the ±12 bound is mathematically wrong (tier gap is 12, not 24); the bound does NOT prevent cross-tier inversion. This is a **factual error** in the safety analysis, not a design regression.

**Interspect unavailability (R-02):** PARTIALLY RESOLVED  
5-minute staleness window and fail-closed behavior specified. Persistence location of authority snapshot not named; creates ambiguity about whether snapshot survives CLI invocation (fd-resilience R-02-b P1).

**Policy-only as permanent identity (D-01):** RESOLVED  
"Phase 1-3 constraint, re-evaluate at Phase 4" framing is now explicit and correctly frames it as load-bearing for interface cleanliness.

**1h/24h windows without calibration path (D-02):** PARTIALLY RESOLVED  
De-escalation logic added, but calibration path for window lengths themselves remains unspecified. Weight-drift threshold (20%) gains calibration path (intercept distillation), creating an inconsistency: one numeric parameter has a closed-loop calibration, two others (1h, 24h) remain open-loop.

---

## Cross-Agent Convergences

**Priority-Inversion Bound (OBR-01, fd-correctness P0)**  
- fd-correctness: tier gap 12, not 24; ±12 bound crosses tiers
- fd-architecture: ±12 can cross one-tier boundary
- fd-safety: ±12 tier gap unverified against code
- **Convergence:** 3/7 agents identified same core issue; consensus that correct bound is ±6 when perturbation accounted for

**30-Day Re-Confirmation Liveness (OBR-02, fd-correctness P1)**  
- fd-correctness: re-confirmation never fires without daemon or scheduler
- fd-systems SYS-01: all domains re-confirm simultaneously at T=30 days (synchronized demotion cascade risk)
- **Convergence:** 2/7 agents identified; fd-systems adds residual phase-shifting oscillation risk

**Freeze Mechanism Conflict (fd-architecture NEW-P1, fd-correctness OBR-06, fd-safety OCKHAM-02 & OCKHAM-03)**  
- fd-architecture: freeze as -999 offset conflicts with floor guard; existing lane-pause path already implemented
- fd-correctness: -999 contradicts -24 floor; no documented exception
- fd-safety: floor stated backwards; -999 offset ineffective due to floor guard rescuing to score 1
- **Convergence:** 3/7 agents identified same conflict; multiple solution paths proposed

**signals.db Single Point of Failure (fd-resilience N-01, also noted by fd-architecture NEW-P2)**  
- fd-resilience: corruption/clock-skew/loss not addressed; temporal state has no failure-mode recovery
- fd-architecture: reconciliation contract between signals.db and primary sources (interspect, beads, interstat) undefined
- **Convergence:** 2/7 agents identified; combined gap spans both persistence failure and state coherence

**Self-Promotion Enforcement Gap (fd-quality Q-01, fd-safety OCKHAM-01, synthesis F1 reference)**  
- fd-quality: behavioral enforcement (CLI-boundary check) without structural guards
- fd-safety: `$CLAUDE_SESSION_ID` is agent-writable; peer-ID spoofing attack remains viable
- **Convergence:** 2/7 agents; synthesis flagged this as 8/16-agent P0 finding (highest confidence)

**Weight-Outcome Feedback Loop Incomplete (fd-architecture NEW-P2, fd-resilience N-02, fd-quality D-06, fd-systems SYS-NEW-01)**  
- fd-architecture: has no actuation path; is monitoring, not closed loop
- fd-resilience: 20% threshold is Goodhart target; threshold becomes self-confirming
- fd-quality: missing theory of change between signal and weight adjustment
- fd-systems: compounding loops (SUBAK-01 + ratchet) operate at different time scales without interaction rule
- **Convergence:** 4/7 agents identified; unified theme of incomplete feedback loop closure

**Cross-Domain Min-Tier Creates Starvation/Sour Spots (fd-quality D-05, fd-systems SYS-NEW-02)**  
- fd-quality: complex beads resolve to shadow, then produce shadow evidence rather than appropriate-tier evidence
- fd-systems: shadow domains starved of dispatch because agents rationally avoid them (Schelling trap)
- **Convergence:** 2/7 agents identified; related but distinct manifestations of same architectural sour spot

---

## Discourse Quality Assessment

### Sawyer Flow Envelope

**Participation Gini (agent finding counts):**
- fd-architecture: 7, fd-correctness: 8, fd-decisions: 8, fd-quality: 8, fd-resilience: 5, fd-safety: 7, fd-systems: 8
- Gini coefficient: 0.12 (healthy; max 1.0)
- Assessment: **healthy participation** — findings distributed across all agents

**Novelty Rate (unique findings / total):**
- Total findings across all agents: ~51 (some duplicates for convergence tracking)
- Unique findings (deduped by core issue): ~31
- Novelty rate: 61% (deduped / raw)
- Assessment: **elevated novelty** — rev 3 introduced substantial new content (SUBAK-01, cross-domain resolution) relative to round-1 review

**Response Relevance (findings with evidence sources / total):**
- All findings cite specific sections, key decisions, or invariant numbers
- All findings have concrete failure scenarios or code references
- Relevance: **100%**
- Assessment: **strong**

**Flow State:** Degraded  
- Gini healthy, novelty elevated, relevance strong
- However: P0 finding indicates core architectural gap uncaught by round-1 review; suggests inadequate round-1 depth
- Convergence quality on priority-inversion suggests round-1 analysis missed quantitative verification step

### Lorenzen Move Validation

No reactions present in this review, so move legality analysis N/A.

### Sycophancy Analysis

No reactions present; sycophancy scoring N/A.

---

## Stemma Analysis

Grouped by core issue (transitive closure on evidence source sets):

1. **Priority-inversion bound error** → OBR-01, fd-architecture NEW-P1, fd-safety OCKHAM-02
2. **Freeze mechanism conflict** → fd-architecture NEW-P1, fd-correctness OBR-06, fd-safety OCKHAM-03
3. **signals.db failure modes** → fd-architecture NEW-P2, fd-resilience N-01
4. **Self-promotion attack surface** → fd-quality Q-01, fd-safety OCKHAM-01
5. **Feedback loop incomplete** → fd-architecture NEW-P2, fd-resilience N-02, fd-quality D-06, fd-systems SYS-NEW-01
6. **Cross-domain starvation** → fd-quality D-05, fd-systems SYS-NEW-02
7. **Baseline/baseline-less issues** → fd-correctness OBR-03, fd-safety OCKHAM-06

**Convergence by stemma group:**
- Most convergent: priority-inversion (3 agents), freeze conflict (3 agents)
- Moderate convergence: self-promotion (2 agents), signals.db (2 agents), starvation (2 agents)
- Novel issues (single-agent): most P2/P3 findings from fd-decisions, fd-systems

---

## Key Recommendations for Next Revision

### Blockers (Must Resolve Before Wave 1 Wiring Spec)

1. **[P0] Name the orchestration layer for Scoring assembly** — is it `cmd/ockham`, a new `governor` package, or something else? Specify the component and its interface.

2. **[P0] Fix the priority-inversion bound analysis** — the tier gap is 12, not 24. Recalculate the maximum safe offset magnitude accounting for perturbation. Current ±12 is not safe; ±6 is the conservative choice.

3. **[P1] Specify the freeze implementation** — use the existing `ic lane update --metadata="paused:true"` path (already correct) OR use offset -999 (requires floor guard exception). Choose one, update validation logic, remove the other from the design.

4. **[P1] Implement the 30-day re-confirmation trigger** — either add `ockham check` to session-start hook (preferred), or add a systemd timer / cron job. The CLI-only design has no scheduler; the brainstorm cannot claim a time-based guarantee without one.

5. **[P1] Specify authority snapshot persistence** — write it to signals.db after each interspect read, or explicitly accept the 5-minute cache resets on every CLI invocation. The current language ("last-known") is ambiguous.

### Major Gaps (Should Resolve Before Vision Document)

6. **[P1] Name the self-promotion enforcement structural guard** — synthesized agents recommended `bd set-state` rejection, dispatch validation, or signed tokens. Pick one and specify where it lives (intercore layer, interspect, or Clavain dispatch).

7. **[P1] Specify CONSTRAIN/BYPASS precedence** — are they dispatch-eligibility gates (computed before scoring) or weight inputs (part of the formula)? Current language is ambiguous.

8. **[P1] Define weight-drift baseline and minimum sample size** — baseline formula (rolling 30-day p50 with >= N beads minimum). Without this, the feedback loop will emit false positives on factory launch and sparse data.

9. **[P1] Add shadow-domain bootstrapping mechanism** — specify minimum dispatch cadence or explicit acceleration mode, or accept the Schelling trap as documented risk. The min-tier rule starves shadow domains of evidence needed for promotion.

10. **[P1] Specify feedback-loop interaction rule** — SUBAK-01 (theme weight-drift) and ratchet (agent hit-rate) compound without coordination. Define whether SUBAK-01 fires when ratchet is simultaneously demoting, or specify a floor below which weight suppression cannot go.

### Specification Gaps (Can Address in Vision Document Authorship)

11. **[P2] Add expiry fields to Intent YAML schema** — `valid_until` and `until_bead_count` per synthesis recommendation F8.

12. **[P2] Specify ratchet promotion window duration** — confidence calibration for cold-start conservatism depends on this. Currently unspecified.

13. **[P2] Add `ockham_constraint_reason` state alongside `ockham_offset`** — allows feedback loop to filter out authority-constrained beads from performance baseline.

14. **[P2] Document Tier 3 recovery sequence** — specify whether `ockham resume --supervised-only` mode exists, or explicit ordering for resume-then-correct.

15. **[P2] Validate freeze/focus theme names in Intent YAML** — add to validation step; reject misspellings with error.

---

## Files Reviewed

- `/home/mk/projects/Sylveste/docs/research/flux-drive/ockham-vision-brainstorm/fd-architecture.md`
- `/home/mk/projects/Sylveste/docs/research/flux-drive/ockham-vision-brainstorm/fd-correctness.md`
- `/home/mk/projects/Sylveste/docs/research/flux-drive/ockham-vision-brainstorm/fd-decisions.md`
- `/home/mk/projects/Sylveste/docs/research/flux-drive/ockham-vision-brainstorm/fd-quality.md`
- `/home/mk/projects/Sylveste/docs/research/flux-drive/ockham-vision-brainstorm/fd-resilience.md`
- `/home/mk/projects/Sylveste/docs/research/flux-drive/ockham-vision-brainstorm/fd-safety.md`
- `/home/mk/projects/Sylveste/docs/research/flux-drive/ockham-vision-brainstorm/fd-systems.md`

---

## Summary

**Validation:** 7/7 agents valid, comprehensive coverage across 7 tracks  
**Verdict:** needs-changes (FAIL gate due to P0)  
**P0:** 1 architectural blocker (orchestration layer)  
**P1:** 19 findings (5 round-1 residuals + 14 new issues)  
**P2:** 18 findings (specification gaps and decision-quality concerns)  
**P3:** 6 findings (low-priority or partially mitigated)

**Key Finding:** Round 1's verification of the priority-inversion safety claim (C-02) was incomplete. The ±12 bound rests on a factual error (tier gap is 12, not 24), invalidating the core safety guarantee of Section 3. This is not a regression in rev 3, but an error in round-1 analysis that was carried forward. Rev 3's new sections (SUBAK-01, cross-domain resolution, 30-day re-confirmation) are architecturally sound in concept but introduce 14 new P1/P2 issues related to persistence, failure modes, interaction effects, and incomplete feedback loops. The document is close to plan-ready on the foundational layer (policy, authority, anomaly subsystems are well-specified) but requires resolution of specification gaps before Wave 1 wiring begins.

