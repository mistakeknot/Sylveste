# Promotion Criteria Registry

Per-subsystem maturity promotion and demotion criteria for the Sylveste capability mesh. Referenced by the [Vision](./sylveste-vision.md) (Trust Architecture) and [PHILOSOPHY.md](../PHILOSOPHY.md) (Graduated Authority).

**Rules:**
- Promotion requires at least one Tier-1 or Tier-2 signal meeting threshold. Tier-3 alone is insufficient.
- Critical-tier subsystems require stricter thresholds and longer observation windows than Medium-tier.
- Demotion triggers when regression indicators exceed threshold for the stated observation window.
- Evidence is evaluated by the stated authority, not self-reported by the subsystem.
- All thresholds are revisable by human authority (see Vision § Human Authority Reservation).

---

## Persistence (Intercore)

**Criticality:** High | **Current:** M2 | **Evaluator:** Human attestation + kernel self-test suite

| Transition | Evidence Signal | Threshold | Window | Tier |
|------------|----------------|-----------|--------|------|
| M1 → M2 | Event integrity (zero corruption on WAL replay) | 100% integrity across 1,000+ runs | 30 days | T2 |
| M1 → M2 | Query latency p95 | < 50ms under concurrent access | 30 days | T2 |
| M2 → M3 | Crash recovery success rate | 100% state recovery after simulated kill -9 | 60 days, 10+ simulated crashes | T1 |
| M2 → M3 | Cross-session attribution accuracy | > 95% session-to-bead-to-run joins resolve | 60 days | T2 |
| M3 → M4 | Schema migration safety | Zero data loss across 5+ schema migrations under real conditions | 90 days | T1 |

**Demotion trigger:** Any data corruption event or unrecoverable state. Immediate demotion to M1. Window: 0 (immediate for Critical/High).

---

## Coordination (Interlock)

**Criticality:** Medium | **Current:** M2 | **Evaluator:** Interspect (kernel event observation)

| Transition | Evidence Signal | Threshold | Window | Tier |
|------------|----------------|-----------|--------|------|
| M1 → M2 | Conflict rate | < 5% of reservation attempts result in conflict | 30 days | T2 |
| M1 → M2 | Reservation throughput | Handles 10+ concurrent agents without deadlock | 30 days | T2 |
| M2 → M3 | Conflict resolution success | > 95% of conflicts auto-resolved without human intervention | 45 days | T2 |
| M3 → M4 | Adaptive timeout tuning | Reservation timeouts self-adjust based on agent response patterns | 60 days | T2 |

**Demotion trigger:** Deadlock or sustained conflict rate > 15% over 14 days. Demotion to M1.

---

## Discovery (Interject)

**Criticality:** Medium | **Current:** M2 | **Evaluator:** Interspect + human promotion/dismissal feedback

| Transition | Evidence Signal | Threshold | Window | Tier |
|------------|----------------|-----------|--------|------|
| M1 → M2 | Promotion rate | > 20% of surfaced discoveries promoted by human | 30 days, 50+ discoveries | T2 |
| M1 → M2 | Source trust score correlation | Source scores predict human promotion with > 60% accuracy | 30 days | T2 |
| M2 → M3 | Interest profile convergence | Profile drift < 10% per week (stable learned preferences) | 45 days | T2 |
| M2 → M3 | Auto-create accuracy | > 50% of auto-created work items survive triage (not closed as irrelevant) | 45 days, 20+ auto-creates | T1 |
| M3 → M4 | Source retirement | Interject proposes source retirement, confirmed by human, metrics improve | 60 days, 3+ retirements | T1 |

**Demotion trigger:** Promotion rate drops below 10% for 21 consecutive days. Demotion to M1.

---

## Review (Interflux)

**Criticality:** High | **Current:** M2 | **Evaluator:** Interspect (finding outcome tracking)

| Transition | Evidence Signal | Threshold | Window | Tier |
|------------|----------------|-----------|--------|------|
| M1 → M2 | Finding precision | > 60% of findings acted on (not dismissed) | 30 days, 100+ findings | T2 |
| M1 → M2 | False positive rate | < 30% of findings dismissed without action | 30 days | T2 |
| M2 → M3 | Finding precision (higher bar) | > 75% acted on | 60 days, 200+ findings | T2 |
| M2 → M3 | Cross-model disagreement yield | Disagreements between models produce higher-value findings than agreements | 60 days | T1 |
| M3 → M4 | Agent self-improvement | Interspect retires underperforming agents AND metrics improve post-retirement | 90 days, 5+ retirements | T1 |

**Demotion trigger:** Finding precision drops below 40% for 30 days, or false positive rate exceeds 50%. Demotion to M1 (High criticality = stricter window).

---

## Integration (Interop)

**Criticality:** High | **Current:** M1 | **Evaluator:** Interspect + sync journal audit

| Transition | Evidence Signal | Threshold | Window | Tier |
|------------|----------------|-----------|--------|------|
| M1 → M2 | Conflict resolution rate | > 90% of sync conflicts auto-resolved | 30 days, 50+ sync events | T2 |
| M1 → M2 | Sync latency p95 | < 5 seconds for bidirectional sync | 30 days | T2 |
| M1 → M2 | Data loss rate | Zero data loss events | 30 days | T2 |
| M2 → M3 | Multi-adapter stability | 2+ adapters (Notion + GitHub) running concurrently without interference | 60 days | T1 |
| M2 → M3 | Collision window effectiveness | < 2% of opposing-source events produce unresolved collisions | 60 days | T2 |
| M3 → M4 | Adapter self-recovery | Failed adapters auto-restart and re-sync without data loss or human intervention | 90 days, 5+ recovery events | T1 |

**Demotion trigger:** Any data loss event = immediate demotion to M1. Conflict resolution rate below 70% for 14 days = demotion to M1.

---

## Execution (Hassease + Codex)

**Criticality:** Medium | **Current:** M0 | **Evaluator:** Interspect (dispatch outcome tracking)

| Transition | Evidence Signal | Threshold | Window | Tier |
|------------|----------------|-----------|--------|------|
| M0 → M1 | Code shipped | Hassease daemon running, routing decisions executing | — | — |
| M1 → M2 | Task completion rate | > 70% of dispatched tasks complete without human rescue | 30 days, 30+ tasks | T2 |
| M1 → M2 | Model utilization efficiency | Cost-routed model (GLM/Qwen) handles > 60% of tasks successfully | 30 days | T2 |
| M2 → M3 | Escalation accuracy | > 80% of Claude escalations were genuinely necessary (validated by outcome) | 45 days | T1 |
| M3 → M4 | Routing self-optimization | Hassease adjusts model routing thresholds based on outcome data | 60 days | T1 |

**Demotion trigger:** Task completion rate drops below 50% for 21 days. Demotion to M1.

---

## Ontology (Interweave)

**Criticality:** Medium | **Current:** M1 | **Evaluator:** Interspect + query log analysis

| Transition | Evidence Signal | Threshold | Window | Tier |
|------------|----------------|-----------|--------|------|
| M1 → M2 | Query hit rate | > 60% of entity queries return results (not empty) | 30 days, 100+ queries | T2 |
| M1 → M2 | Confidence score accuracy | High-confidence results (> 0.8) are confirmed correct > 80% of the time | 30 days | T2 |
| M2 → M3 | Cross-system entity resolution | > 85% of entities found across 2+ systems have consistent identity | 45 days | T1 |
| M2 → M3 | Finding-aid test compliance | System continues to function with Interweave disabled (degraded but not broken) | Periodic check (monthly) | T1 |
| M3 → M4 | Computed relationship accuracy | Inferred (non-explicit) relationships confirmed useful > 70% of the time | 60 days | T1 |

**Demotion trigger:** Query hit rate below 40% for 21 days, or finding-aid test failure (anything breaks when Interweave is disabled). Demotion to M1.

---

## Measurement (Factory Substrate + FluxBench)

**Criticality:** High | **Current:** M1 | **Evaluator:** Human attestation + FluxBench controlled experiments

| Transition | Evidence Signal | Threshold | Window | Tier |
|------------|----------------|-----------|--------|------|
| M1 → M2 | Attribution chain completeness | > 80% of sprints have complete session → bead → run → outcome chain | 30 days, 50+ sprints | T2 |
| M1 → M2 | FluxBench qualification rate | > 90% of model qualification runs produce consistent scores (< 10% variance on rerun) | 30 days, 10+ qualification runs | T1 |
| M2 → M3 | Attribution accuracy | > 90% of attributed outcomes verified correct by human spot-check (sample of 20) | 60 days | T1 |
| M2 → M3 | Drift detection sensitivity | FluxBench detects model regression within 48 hours of API change (validated on 3+ events) | 90 days | T1 |
| M3 → M4 | Automated requalification | Model requalification triggers autonomously on drift detection, results verified | 90 days, 3+ auto-triggers | T1 |

**Demotion trigger:** Attribution completeness below 60% for 14 days (High criticality). Demotion to M1.

---

## Governance (Ockham)

**Criticality:** Critical | **Current:** M1 | **Evaluator:** Human attestation (Interspect cannot assess its own governance layer independently)

| Transition | Evidence Signal | Threshold | Window | Tier |
|------------|----------------|-----------|--------|------|
| M1 → M2 | Authority event accuracy | > 90% of weight offset decisions align with principal intent (human-validated sample of 30) | 45 days | T1 |
| M1 → M2 | INFORM signal false positive rate | < 20% of INFORM signals are false alarms | 45 days, 20+ signals | T2 |
| M1 → M2 | Zero unauthorized actions | No agent takes action exceeding its authority scope | 45 days | T2 |
| M2 → M3 | Authority ratchet accuracy | Promotions/demotions match human judgment > 85% of the time (sample of 20) | 90 days | T1 |
| M2 → M3 | Algedonic signal utility | Weight-drift and pleasure signals correlate with actual sprint quality (> 0.6 correlation) | 90 days | T1 |
| M3 → M4 | Policy self-tuning | Ockham proposes governance policy changes, human approves, metrics improve | 120 days, 5+ proposals | T1 |

**Demotion trigger:** Any unauthorized agent action = immediate demotion to M0 (Critical = most severe). Authority event accuracy below 70% for 14 days = demotion to M1. Observation window is shorter for Critical tier.

---

## Routing (Interspect)

**Criticality:** High | **Current:** M2 | **Evaluator:** Human attestation + FluxBench controlled experiments

| Transition | Evidence Signal | Threshold | Window | Tier |
|------------|----------------|-----------|--------|------|
| M1 → M2 | Gate pass rate | > 70% of phase transitions pass on first attempt | 30 days, 100+ transitions | T2 |
| M1 → M2 | Model cost ratio | Routed model costs < 80% of always-Opus baseline for equivalent quality | 30 days | T2 |
| M2 → M3 | Routing override accuracy | > 80% of Interspect-proposed overrides improve outcomes when applied | 60 days, 20+ overrides | T1 |
| M2 → M3 | Canary monitoring precision | Canary detects regression within 48 hours, < 10% false positive rate | 60 days | T1 |
| M3 → M4 | Counterfactual shadow validation | Shadow routing recommendations match or beat actual routing > 70% of the time | 90 days | T1 |
| M3 → M4 | Self-improvement measurable | North star metric (cost per landable change) improves > 10% quarter-over-quarter | 90 days | T1 |

**Demotion trigger:** Gate pass rate below 50% for 14 days, or routing override accuracy below 60% for 30 days. Demotion to M1.

---

## Registry Governance

This registry is a living document. Thresholds are initial estimates based on current system understanding and will be calibrated as evidence accumulates.

**Revision policy:**
- Thresholds can be tightened at any time based on evidence.
- Thresholds can be loosened only with human approval and documented rationale.
- New transitions can be added as subsystems mature.
- The registry itself is subject to evidence epochs: major architectural changes trigger a registry review.

**Maturity assessment cadence:**
- M0-M1 transitions: evaluated on-demand (when implementation ships).
- M1-M2 transitions: evaluated monthly once evidence collection begins.
- M2+ transitions: evaluated quarterly.
- Demotion: evaluated continuously by Interspect (or human for Governance/Routing).
