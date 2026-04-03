# Ockham Vision -- Cross-Track Synthesis Report

Reviewed: 2026-04-03
Mode: flux-drive (4-track, 16 agents)
Context: Multi-track deep review of Ockham vision brainstorm (16 agents across 4 semantic-distance tracks)

## Verdict Summary

| Agent | Track | Verdict | P0 | P1 | P2 | P3 | Status |
|-------|-------|---------|----|----|----|----|--------|
| fd-distributed-governance-consensus | A-adjacent | needs-changes | 0 | 2 | 2 | 1 | NEEDS_ATTENTION |
| fd-cybernetic-control-feedback | A-adjacent | needs-changes | 1 | 2 | 1 | 1 | NEEDS_ATTENTION |
| fd-sre-alerting-escalation | A-adjacent | needs-changes | 1 | 2 | 2 | 0 | NEEDS_ATTENTION |
| fd-agent-trust-authority | A-adjacent | needs-changes | 1 | 2 | 2 | 0 | NEEDS_ATTENTION |
| fd-dispatch-optimization-fairness | A-adjacent | needs-changes | 0 | 2 | 2 | 1 | NEEDS_ATTENTION |
| fd-or-scheduling | B-orthogonal | needs-changes | 0 | 2 | 2 | 1 | NEEDS_ATTENTION |
| fd-atc-flow | B-orthogonal | needs-changes | 0 | 2 | 2 | 1 | NEEDS_ATTENTION |
| fd-grid-dispatch | B-orthogonal | risky | 1 | 1 | 2 | 1 | NEEDS_ATTENTION |
| fd-central-bank | B-orthogonal | risky | 0 | 2 | 2 | 1 | NEEDS_ATTENTION |
| fd-venetian-glass-batch-formulation | C-distant | needs-changes | 0 | 2 | 1 | 1 | NEEDS_ATTENTION |
| fd-ethiopian-tabot-custody | C-distant | needs-changes | 1 | 2 | 1 | 1 | NEEDS_ATTENTION |
| fd-song-dynasty-keju-examination | C-distant | needs-changes | 1 | 1 | 2 | 1 | NEEDS_ATTENTION |
| fd-balinese-subak-irrigation | C-distant | needs-changes | 0 | 2 | 1 | 2 | NEEDS_ATTENTION |
| fd-carolingian-missi-dominici-governance | D-esoteric | needs-changes | 0 | 2 | 2 | 1 | NEEDS_ATTENTION |
| fd-balinese-subak-water-temple-governance | D-esoteric | needs-changes | 1 | 2 | 1 | 1 | NEEDS_ATTENTION |
| fd-hadza-camp-fission-fusion-egalitarianism | D-esoteric | needs-changes | 1 | 2 | 1 | 1 | NEEDS_ATTENTION |

**Overall: risky** (8 P0 findings across 8 agents)

---

## Cross-Track Convergence Analysis

The highest-confidence findings are those discovered independently in 2+ tracks. Ranked by track breadth:

### 4-Track Convergence (All Tracks Agree)

**F1. Safety invariants are behavioral, not structural -- agents can bypass them**
- Track A: ATA-02 (P1), DGC-01 (P1)
- Track B: GRID-1 (P0)
- Track D: CAROL-02 (P1), HADZA-02 (P1)
- Track C: SK-01 (P0, self-selection aspect), ET-01 (P0, cross-domain aspect)
- Convergence: 8/16 agents, all 4 tracks
- Synthesis: Every track independently identified that the five safety invariants depend on Ockham's own compliance rather than structural rejection by consuming systems (lib-dispatch.sh, bd set-state). The adjacent experts framed it as "behavioral vs. structural enforcement." The esoteric tracks added independent framing: Carolingian missi required paired confirmation (structural), Hadza leveling is immediate structural response (not post-hoc audit). The grid-dispatch agent elevated this to P0 by showing that individually-valid grants can produce globally-invalid aggregate authority.
- Recommended severity: **P0**
- Fix: Push invariant enforcement to the execution path. `bd set-state` rejects self-promotion writes. lib-dispatch.sh validates aggregate authority before dispatch. Authority writes require signed tokens.

**F2. Promotion gaming through bead self-selection / difficulty bias**
- Track A: ATA-01 (P0)
- Track B: CB-1 (P1, endogeneity framing)
- Track C: SK-01 (P0), ET-02 (P1)
- Track D: SUBAK-04 (P2), HADZA-04 (P2)
- Convergence: 6/16 agents, all 4 tracks
- Synthesis: Adjacent agents identified agents can cherry-pick easy beads to inflate hit rates. Central-bank added feedback endogeneity: Ockham's own weight decisions create favorable conditions that agents benefit from. Song-dynasty keju provided the deepest framing: promotion evidence comes from agent-selected tasks, like letting examination candidates choose which questions to answer. Tabot custody added that wall-clock windows are not evidence of competence.
- Recommended severity: **P0**
- Fix: Normalize pass_rate by difficulty. Require minimum bead complexity coverage. Filter out weight-skewed evidence periods. Replace wall-clock windows with evidence-quantity requirements.

**F3. Low-budget themes permanently starved by multiplicative weight composition**
- Track A: DOF-02 (P1)
- Track B: OR-1 (P1)
- Track C: BS-01 (P1), VG-02 (P1)
- Track D: SUBAK-05 (P3)
- Convergence: 5/16 agents, all 4 tracks
- Synthesis: All tracks independently discovered that `final_score = raw_score * ockham_weight` with no floor produces effective starvation for low-budget themes. OR-scheduling added the idle-capacity dimension: when a high-budget theme exhausts its queue, the capacity sits idle rather than being released. The subak irrigation agent provided the most vivid framing: "upstream terraces monopolize water; the temple imposes a guaranteed minimum."
- Recommended severity: **P1**
- Fix: Define a weight floor (0.6). Add starvation detection with minimum dispatch cadence guarantees. Release idle theme capacity to the open pool.

### 3-Track Convergence

**F4. Algedonic bypass channel depends on the system it bypasses**
- Track A: CCF-01 (P0), SRE-01 (P0)
- Track B: OR-2 (P1), CB-5 (P3)
- Track D: CAROL-03 (P2), HADZA-03 (P1)
- Convergence: 6/16 agents, 3 tracks (A, B, D)
- Synthesis: The Tier 3 BYPASS writes `factory-paused.json` inside Clavain's own config directory. If Clavain is hung, it never reads the file. Adjacent SRE added signal flooding: cascading failure produces O(agents * domains) signals. Carolingian missi added the missus-vs-palace distinction: the missus recommends the ban, only the palace issues it. Hadza added exit-cost analysis: mid-execution states delay the halt.
- Recommended severity: **P0**
- Fix: Tier 3 must have at least one notification path independent of Clavain. Separate BYPASS request from BYPASS execution. Define halt semantics (interrupt/wait/soft).

**F5. No cross-domain authority resolution rule**
- Track A: ATA-05 (P2)
- Track B: ATC-1 (P1)
- Track C: ET-01 (P0)
- Track D: HADZA-01 (P0)
- Convergence: 4/16 agents, 3 tracks (A, B, C+D combined as non-adjacent)
- Synthesis: When a bead spans domains where the agent has different authority tiers, behavior is undefined. ATC-flow discovered the claimed-but-blocked limbo state. Tabot custody elevated to P0: cross-domain defaults to whichever tier is encountered first, functionally granting the more permissive tier by accident. Hadza added domain-boundary leakage via interspect score aggregation.
- Recommended severity: **P0**
- Fix: Minimum-tier composition rule: effective_tier = min(tier for each matched domain). Add `claimed_by_blocked` state for authority violations mid-execution. Assert domain-scoping in agent_reliability contract.

**F6. Weight composition order undefined -- CONSTRAIN can be overridden by intent boost**
- Track A: DGC-03 (P2)
- Track C: VG-01 (P1)
- Track D: SUBAK-02 (P1)
- Convergence: 3/16 agents, 3 tracks
- Synthesis: Venetian glass formulation provided the clearest analysis: intent weight 1.4 * authority penalty 0.7 = 0.98 (near-neutral), meaning a CONSTRAIN freeze is silently violated by arithmetic balance. The subak water temple added: tiers should expand scope of one mechanism, not switch mechanisms entirely. Both recommend treating CONSTRAIN/BYPASS as dispatch eligibility gates, not weight multipliers.
- Recommended severity: **P1**
- Fix: Anomaly gates take priority precedence. CONSTRAIN/BYPASS produce sentinel weights that override intent. Separate anomaly state from weight arithmetic.

**F7. Promotion feedback loop is open -- no calibration of threshold correctness**
- Track A: CCF-02 (P1)
- Track B: GRID-3 (P2)
- Track D: SUBAK-04 (P2)
- Convergence: 3/16 agents, 3 tracks
- Synthesis: After promotion, the system never checks whether the promoted agent performs as predicted. Grid-dispatch identified hysteresis: symmetric thresholds enable oscillation near boundaries. Subak water temple added that thresholds must be calibrated against outcomes, not historical decisions.
- Recommended severity: **P1**
- Fix: Post-promotion audit. Asymmetric thresholds (promote at 0.85, demote at 0.70). Minimum beads before demotion eligibility. Intercept calibration optimizes for outcome improvement, not decision replication.

**F8. Intent YAML has no expiry -- stale policy persists indefinitely**
- Track B: CB-3 (P2)
- Track C: BS-05 (P3)
- Track D: CAROL-04 (P2)
- Convergence: 3/16 agents, 3 tracks
- Synthesis: Central-bank distinguished time-bounded stance from open-ended policy. Carolingian missi analogized to capitulary staleness. All three recommend `valid_until` fields with explicit expiry behavior.
- Recommended severity: **P2**
- Fix: Add `valid_until` and `until_bead_count` to intent.yaml schema. Expired directives revert to neutral weight. `ockham status` warns on stale intent.

### 2-Track Convergence

**F9. 1-hour confirmation window creates blind spot for rapid-onset incidents**
- Track A: SRE-02 (P1)
- Track B: ATC-2 (P1)
- Convergence: 2/16 agents, 2 tracks (A, B)
- Recommended severity: **P1**
- Fix: Add rate-of-change fast path: if events exceed threshold within window (e.g., 3 in 30min), escalate immediately.

**F10. No independent anomaly observation channel**
- Track C: SK-02 (P1)
- Track D: CAROL-01 (P1)
- Convergence: 2/16 agents, 2 tracks (C, D)
- Synthesis: Song-dynasty identified that 3 of 4 anomaly inputs are agent-influenced. Carolingian missi identified that CONSTRAIN fires on Ockham's own signals without interspect corroboration. Both recommend paired confirmation.
- Recommended severity: **P1**
- Fix: Add independent observation source (git revert rate). Require interspect corroboration before CONSTRAIN.

**F11. Weight provenance lost -- scalar storage prevents calibration**
- Track B: OR-4 (P2)
- Track C: VG-03 (P2)
- Convergence: 2/16 agents, 2 tracks (B, C)
- Recommended severity: **P2**
- Fix: Write `ockham_weight_provenance` companion record with decomposed factors.

**F12. Cold-start defaults undefined -- retroactive inference risks granting unearned authority**
- Track A: ATA-04 (P2)
- Track C: ET-03 (P1)
- Track D: CAROL-05 (P3)
- Convergence: 3/16 agents, 3 tracks
- Recommended severity: **P1**
- Fix: Default all-shadow. `ockham init --fast-track` proposes promotions for explicit principal approval. Minimum observation floor before promotion eligibility.

**F13. CONSTRAIN freeze does not propagate to dependent domains**
- Track B: GRID-2 (P1), ATC-4 (P2)
- Convergence: 2/16 agents, 1 track (B-orthogonal, but both identify the same structural gap)
- Recommended severity: **P1**
- Fix: Run dependency-graph lookup on CONSTRAIN. Apply INFORM-tier weight suppression to downstream-dependent domains.

**F14. No dispatch share feedback -- open-loop allocation**
- Track A: DOF-03 (P2)
- Track B: OR-3 (P2)
- Track D: SUBAK-01 (P0)
- Convergence: 3/16 agents, 3 tracks
- Synthesis: Adjacent and orthogonal agents identified the missing feedback from actual dispatch to weight correction. The subak water temple elevated to P0 with the strongest framing: "authority that is enforcement-derived rather than outcome-derived." The temple's authority self-validates through observable outcomes; Ockham's weights are followed regardless of whether they improve results.
- Recommended severity: **P1** (the outcome-validation gap is real but the mechanisms identified as fixes are Wave 1-compatible)
- Fix: Track actual dispatches per theme. Emit INFORM signal when weight-outcome correlation is negative. Add dispatch fairness index metric.

**F15. Signal taxonomy conflates infrastructure and competence failures**
- Track A: SRE-04 (P2)
- Track B: (implied in CB-2 joint feasibility analysis)
- Convergence: 2/16 agents, 2 tracks
- Recommended severity: **P2**
- Fix: Tag signals with cause category. Filter demotion logic to competence signals only.

---

## Findings by Severity

### P0 -- CRITICAL (blocks merge)

| ID | Title | Tracks | Agents | Convergence |
|----|-------|--------|--------|-------------|
| F1 | Safety invariants are behavioral, not structural | A+B+C+D | 8/16 | 4-track |
| F2 | Promotion gaming through bead self-selection | A+B+C+D | 6/16 | 4-track |
| F4 | Algedonic bypass depends on the system it bypasses | A+B+D | 6/16 | 3-track |
| F5 | No cross-domain authority resolution rule | A+B+C+D | 4/16 | 3-track |

### P1 -- IMPORTANT (should fix before merge)

| ID | Title | Tracks | Agents | Convergence |
|----|-------|--------|--------|-------------|
| F3 | Low-budget themes permanently starved | A+B+C+D | 5/16 | 4-track |
| F6 | Weight composition order undefined | A+C+D | 3/16 | 3-track |
| F7 | Promotion feedback loop open | A+B+D | 3/16 | 3-track |
| F9 | 1h window blind spot for rapid-onset | A+B | 2/16 | 2-track |
| F10 | No independent anomaly observation channel | C+D | 2/16 | 2-track |
| F12 | Cold-start defaults undefined | A+C+D | 3/16 | 3-track |
| F13 | CONSTRAIN freeze not propagated downstream | B | 2/16 | 1-track |
| F14 | No dispatch-to-weight feedback loop | A+B+D | 3/16 | 3-track |

### P2 -- NICE TO HAVE (should fix)

| ID | Title | Tracks | Agents | Convergence |
|----|-------|--------|--------|-------------|
| F8 | Intent YAML has no expiry | B+C+D | 3/16 | 3-track |
| F11 | Weight provenance lost | B+C | 2/16 | 2-track |
| F15 | Infra/competence signal conflation | A+B | 2/16 | 2-track |

### Single-Agent Findings (IMP -- improvement suggestions, not deduplicated)

| ID | Agent | Title | Severity |
|----|-------|-------|----------|
| CCF-04 | fd-cybernetic-control-feedback | Requisite variety: 3 tiers for 5+ failure categories | P2 |
| CCF-05 | fd-cybernetic-control-feedback | VSM System 4 (intelligence function) absent | P3 |
| DGC-05 | fd-distributed-governance-consensus | No quorum for authority decisions | P3 |
| DOF-05 | fd-dispatch-optimization-fairness | Perturbation overrides small weight differences | P3 |
| OR-5 | fd-or-scheduling | Freeze/focus semantics unspecified | P3 |
| ATC-3 | fd-atc-flow | No intermediate degraded mode between autonomous and pause | P2 |
| ATC-5 | fd-atc-flow | Audit trail supports compliance but not threshold calibration | P3 |
| GRID-4 | fd-grid-dispatch | No forecast layer for pre-positioning resources | P2 |
| GRID-5 | fd-grid-dispatch | Principal unavailability not modeled | P3 |
| CB-4 | fd-central-bank | Intent expresses stances not reaction functions | P2 |
| VG-04 | fd-venetian-glass-batch-formulation | Anomaly tiers are phase changes not gradients | P3 |
| ET-04 | fd-ethiopian-tabot-custody | Audit receipts lack epistemic state at decision time | P2 |
| ET-05 | fd-ethiopian-tabot-custody | Shadow tier has no must-dispatch urgency pathway | P3 |
| SK-03 | fd-song-dynasty-keju-examination | No temporal decay on authority | P2 |
| SK-04 | fd-song-dynasty-keju-examination | Evidence reused across ratchet stages | P2 |
| SK-05 | fd-song-dynasty-keju-examination | Delegation ceiling not revalidated at exercise time | P3 |
| BS-04 | fd-balinese-subak-irrigation | No cross-theme coordination constraints | P3 |
| SUBAK-03 | fd-balinese-subak-water-temple-governance | Bead-to-theme mapping is label-based, gameable | P1 |
| HADZA-05 | fd-hadza-camp-fission-fusion-egalitarianism | Reputation portability unaddressed | P3 |

---

## Track-Specific Insights

### What the distant/esoteric tracks found that adjacent experts missed

1. **Outcome-derived vs. enforcement-derived authority** (SUBAK-01, P0). The adjacent experts reviewed the mechanism; the subak water temple agent asked the prior question: does Ockham's authority rest on demonstrated outcome advantage, or is it followed because the system enforces it? The temple's authority disappears the moment its schedules produce pest outbreaks. Ockham's weights are followed regardless of outcomes. This is the single most consequential insight from the outer tracks -- it reframes dispatch weight validation from a "nice-to-have monitoring metric" to a structural authority question.

2. **Paired confirmation before CONSTRAIN** (CAROL-01). The Carolingian missi dominici required two independent envoys to agree before suspending jurisdiction. Ockham's CONSTRAIN fires on its own anomaly signal without independent corroboration from interspect. No adjacent agent identified this single-source dependency.

3. **Wall-clock windows measure not-yet-failing, not competence** (ET-02). The tabot custody agent reframed the 24h promotion window: it is a demonstration of absence-of-failure, not a demonstration of competence against the full difficulty distribution. This led to the recommendation to replace time windows with evidence-quantity requirements.

4. **Mechanism switching vs. scope expansion** (SUBAK-02). The subak water temple identified that Ockham's three tiers use three different mechanisms (weight adjustment, metadata freeze, file write), while the 1000-year-old subak system uses the same mechanism (scheduling weights) at three different scopes. Scope expansion of one mechanism is simpler to test, roll back, and reason about.

5. **Label-based theme gaming** (SUBAK-03). The subak system's coordination is infrastructure-determined (physical irrigation channels), not label-determined. An agent can relabel beads to attract high-weight themes. File-path-based theme resolution eliminates this attack surface.

6. **Reputation portability with discount** (HADZA-05). The Hadza system discounts reputation when moving to a new camp. Zero portability wastes evidence; full portability causes domain leakage. Directory-prefix discounting is a concrete answer to Open Question 3.

### Most Surprising Finding

**SUBAK-01 (P0): Ockham's authority is enforcement-derived, not outcome-derived.** The adjacent experts assumed dispatch weights would be validated by their outcomes and focused on the mechanism of weight computation. The subak water temple agent, drawing on Lansing's computational models of Balinese irrigation, asked the question no adjacent agent asked: does Ockham have any mechanism to detect when its own weights are wrong? The answer is no. Interspect monitors agent reliability, not whether Ockham's weighting improves factory throughput. This is a fundamental architectural gap: the governor has no feedback on whether its governance is helping.

---

## Stemma Analysis

Evidence source overlap computed via Jaccard similarity on file:line references. Since this review targets a brainstorm document (not code), evidence sources are section references within the brainstorm.

| Stemma Group | Findings | Shared Evidence | Convergence (corrected) |
|-------------|----------|-----------------|------------------------|
| Dispatch weight composition | F3, F6, F14, DOF-01, VG-02, OR-1, BS-01 | Key Decisions S2 (dispatch integration) | 4 distinct analysis frames |
| Autonomy ratchet gaming | F2, F7, SK-01, SK-04, ET-02, SUBAK-04 | Key Decisions S4 (autonomy ratchet) | 5 distinct analysis frames |
| Algedonic channel integrity | F4, F9, SRE-01, CCF-01, OR-2, CAROL-03 | Key Decisions S3 (algedonic signals) | 4 distinct analysis frames |
| Safety invariant enforcement | F1, F5, ATA-02, CAROL-02, HADZA-02, GRID-1 | Key Decisions S5 (safety invariants) | 4 distinct analysis frames |

Within each stemma group, findings share evidence sections but offer distinct analytical lenses (from different domain expertise). The convergence_corrected values reflect genuinely independent analytical frames rather than simple agreement.

---

## Diverse Perspectives (QDAIF)

### Perspective 1: Industrial Control Systems (SRE + Cybernetics, Track A)
The SRE and cybernetic agents frame Ockham as an alarm management system (ISA-18.2) and a viable system model (Beer's VSM). Their unique contribution is operationalizing the gaps: signal flood budgets, response SLAs, setpoint-based homeostasis. Quality: 0.9 (confirmed findings, high independence, unique operational framing).

### Perspective 2: Resource Allocation Under Constraints (OR + Grid + Central Bank, Track B)
These agents frame Ockham as a scheduling and dispatch optimization problem. Their unique contribution is the joint feasibility analysis: individually valid constraints can combine to produce an empty dispatchable set, which no other track identified. Quality: 0.85 (confirmed findings, independent numeric walkthroughs, unique feasibility analysis).

### Perspective 3: Credentialing and Authority Legitimacy (Tabot + Keju + Hadza, Tracks C+D)
These agents frame promotion as a credentialing problem and ask whether the credential is earned or gamed. Their unique contribution is structural: the difference between rules (which require compliance) and mechanisms (which work regardless of intent). The Hadza leveling mechanism, Song paste-name reform, and tabot ordination all provide concrete structural alternatives. Quality: 0.9 (unique findings, high independence, novel structural framing).

DWSQ (Discourse-Weighted Synthesis Quality): **0.87** = 0.78 (mean finding quality) * (1 + 0.12 diversity bonus from 3 distinct perspective clusters / 16 agents).

---

## Sawyer Flow Envelope

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Participation Gini | 0.03 | <= 0.3 | healthy |
| Novelty rate | 0.24 | >= 0.1 | healthy |
| Response relevance | 0.94 | >= 0.7 | healthy |
| **Flow state** | **healthy** | | |

All 16 agents produced substantive findings with evidence. Participation was nearly uniform (5 findings per agent). 19 of 80 total findings were unique (not deduplicated into any cross-track finding). 75 of 80 findings cited specific section references.

---

## Conflicts

No severity conflicts between agents on the same finding. Two framing tensions:

1. **Dispatch share feedback priority**: SUBAK-01 rates the absence of weight-outcome validation as P0 (authority legitimacy question). DOF-03 and OR-3 rate the same gap as P2 (monitoring improvement). Synthesis: adopted P1 as the merged severity -- the gap is real and actionable in Wave 1 but does not block the architecture.

2. **Tier 3 BYPASS autonomy**: CAROL-03 recommends Tier 3 require principal confirmation before the halt takes effect. HADZA-03 recommends documenting the halt semantics but preserving immediate automated halt. Synthesis: preserved both recommendations -- the vision should specify halt semantics and document the tradeoff.

---

## Files Referenced

- `docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md` (primary review target)
- `os/Clavain/hooks/lib-dispatch.sh` (lines 133-218, dispatch_rescore)
- `core/intercore/config/costs.yaml` (cost baseline reference)
- `~/.clavain/factory-paused.json` (Tier 3 halt mechanism)
- `beads-troubleshooting.md` (Dolt failure modes)
