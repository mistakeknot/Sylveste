# Sylveste v1.0 Roadmap

> Living document. Last audited: 2026-04-27. Runtime evidence may move faster than this roadmap; treat code receipts and bead closures as source of truth for shipped wiring.

## Model

The roadmap uses a **parallel track model**. Three tracks progress independently; a version bump requires **all tracks** to reach the gate threshold.

```
Version gates:
  v0.7 = A:L3 + B:L2 + C:L1    Autonomy loops close. Gates learn. Self-building.
  v0.8 = A:L3 + B:L3 + C:L2    Failures prevented. First external project.
  v0.9 = A:L4 + B:L4 + C:L3    Self-healing. Adversarial tested. Multi-external.
  v1.0 = A:L4 + B:L4 + C:L4    Stability declaration. Onboarding works.
```

**Purpose:** Internal north star during v0.7-v0.8 (guides what to work on). Transitions to external communication at v0.9-v1.0 (credible promises to users).

---

## Track A: Autonomy

*The system's past behavior shapes its future behavior without human intervention.*

Three calibration loops must close: routing, gate thresholds, and phase-cost estimation. Each loop follows the 4-stage pattern from PHILOSOPHY.md: hardcoded defaults → collect actuals → calibrate from history → defaults become fallback.

### A:L1 — Manual Calibration (historical baseline)

Calibration tools exist but require human invocation.

| Loop | Code | Location | Trigger |
|------|------|----------|---------|
| Routing | `_interspect_write_routing_calibration()` | `interverse/interspect/hooks/lib-interspect.sh` | Manual: `/interspect:calibrate` |
| Gate threshold | `calibrate-gate-tiers` | `os/Clavain/cmd/clavain-cli/gate_calibration.go` | Manual: `clavain-cli calibrate-gate-tiers` |
| Phase-cost | `cmdCalibratePhaseCosts()` | `os/Clavain/cmd/clavain-cli/budget.go` | Manual: `clavain-cli calibrate-phase-costs` |

### A:L2 — Semi-Automatic

Calibration fires at natural lifecycle points (sprint end, session end) but may still need human attention on failures.

| Loop | What changes | Current gap |
|------|-------------|-------------|
| Routing | Verdict recording wired into quality-gates runtime and fallback sweep exists | Operational proof across sessions; routing calibration file must be refreshed by lifecycle hook |
| Gate threshold | `ic gate signals` feeds `calibrate-gate-tiers`; SessionEnd hook runs the drain | Operational proof and no-touch streak receipts |
| Phase-cost | Triggered by `/reflect` command at sprint end | SessionEnd trigger shipped 2026-04-27; anomaly flagging still pending |

### A:L3 — Fully Autonomous Loops

All three loops fire without human intervention. The system predicts, observes outcomes, and calibrates from evidence automatically.

| Loop | What changes | Gap from L2 |
|------|-------------|-------------|
| Routing | Session-end lifecycle triggers calibration. Override proposals generated with canary windows. | Prove `routing-calibration.json` updates over multiple natural sessions |
| Gate threshold | Outcomes recorded -> calibration file written -> thresholds auto-adjusted | Prove gate-tier calibration changes over multiple natural sessions |
| Phase-cost | SessionEnd hook triggers calibration. Anomaly flagging for >2x estimates. | Add durable anomaly receipts for >2x estimate drift |

**Exit criterion:** 10 consecutive sprints with no manual calibration intervention across all three loops.

### A:L4 — Self-Healing

Auto-remediation: system retries failed gates, substitutes agents, adjusts parameters without human intervention. The system recovers from model degradation, provider outages, and budget exhaustion autonomously.

---

## Track B: Safety

*The system prevents, detects, and recovers from failures structurally, not probabilistically.*

### B:L1 — Gates Exist (current baseline)

Phase gates run on every transition via `ic gate check`. They block on failure. But:
- Threshold learning now exists but still needs operational proof
- Gate outcome signal quality still needs a no-touch validation window
- The feedback loop from "this gate decision was correct/wrong" must remain observable
- `bd doctor` exists but requires manual invocation

### B:L2 — Gates Learn

Gate thresholds adjust from historical pass/fail data.

| Component | What's needed | Effort |
|-----------|--------------|--------|
| `gate-tier-calibration.json` schema | Shipped; exported from Clavain gatecal state | Done |
| Outcome recording | `ic gate signals` extracts TP/FP/TN/FN from phase events | Done |
| Threshold adjustment | `calibrate-gate-tiers` drains historical signals and adjusts tiers | Done |
| `bd doctor` auto-run | SessionStart hook, block sprint on corruption | Small |

**Bead:** Sylveste-0rgc (gate calibration), Sylveste-py89 (bd doctor auto-run)

### B:L3 — Existential Failures Prevented

Five failure modes mechanically prevented (not mitigated, prevented):

1. **Unbounded cascading failures** — Phase gates act as circuit breakers. Halt propagation mechanically.
2. **Silent quality degradation** — Anomaly detection on core metrics. Detection within N sprints of model degradation.
3. **Unrecoverable state corruption** — `bd doctor --deep` runs automatically, blocks on corruption.
4. **Unprovenanced self-modification** — Every routing/threshold/overlay change produces a durable receipt.
5. **Infinite agent loops** — Kernel-enforced token ceilings and wall-clock timeouts.

**Exit criterion:** 100 consecutive sprints with zero existential failure events.

### B:L4 — Adversarial Testing

Adversarial test suite validates detection rates. Intentionally inject wrong strategies, introduce model degradation, corrupt state — measure detection and recovery.

**Exit criterion:** Semantic cascade detection rate >70%. All 5 existential failure modes survive adversarial probing.

---

## Track C: Adoption

*The system works on codebases the developers don't control, and new users can reach value quickly.*

### C:L1 — Self-Building (current baseline)

Proven on the Sylveste codebase. 800+ sessions, $2.93/landable-change baseline (measured 2026-03-18). Metrics collected via interstat/cost-query.sh.

### C:L2 — Single External Project

One external project (Go or Python) with 50+ completed sprints. Metrics collected and compared to self-building baseline.

**Selection criteria:** Open source, >10K LOC, active development, language Sylveste handles well. Not a fork or derivative of Sylveste.

**Metrics to collect:** Sprint completion rate, cost per landable change, gate false-positive rate, time per sprint.

### C:L3 — Multi-External + ODD Published

3+ external projects across domains (web, infrastructure, data). 20+ sprints each. Directional evidence that the system generalizes.

**Operational Design Domain (ODD):** Published document declaring what Sylveste is designed for and what is explicitly out of scope.

### C:L4 — Accessible Onboarding

Time to first shipped change <60 minutes for new users unfamiliar with internals. 70%+ success rate without help. All onboarding stage events instrumented.

---

## Version Gates

### v0.7.0 — Operational Maturity

**Gate:** A:L3 + B:L2 + C:L1

The three calibration loops operate autonomously. Gates learn from their own outcomes. The system is self-building with operational observability.

**Exit criteria:**
- [ ] 10 consecutive sprints with no manual calibration intervention
- [x] `gate-tier-calibration.json` can be populated from gate outcomes
- [x] `routing-calibration.json` has a session-end lifecycle writer
- [x] `phase-cost-calibration.json` has a SessionEnd trigger
- [ ] `bd doctor --deep` runs on SessionStart, blocks on corruption
- [ ] Anomaly detection flags >2x cost/duration deviations
- [ ] 10-sprint no-touch evidence confirms the hooks actually fire in natural sessions

**Beads:**
- Sylveste-enxv.2: Wire calibration loops (routing, phase-cost)
- Sylveste-0rgc: Gate threshold calibration loop
- Sylveste-py89: bd doctor auto-run
- BEGIN external project runs (C:L2 prep, no formal gate)

### v0.8.0 — Measurement & Resilience

**Gate:** A:L3 + B:L3 + C:L2

Existential failures are mechanically prevented. First external project has 50+ sprints with comparable metrics.

**Exit criteria:**
- [ ] All 5 existential failure modes mechanically prevented
- [ ] Pass@k evaluation harness operational (≥3 complexity tiers)
- [ ] 1 external project with 50+ sprints, metrics within 1 SD of self-building
- [ ] 100 consecutive sprints without existential failure events
- [ ] Model upgrade impact detected within 1 sprint (canary windows operational)

### v0.9.0 — Proven Trust

**Gate:** A:L4 + B:L4 + C:L3

Self-healing operational. Adversarial testing passes. Multiple external projects validated. ODD published.

**Exit criteria:**
- [ ] Auto-remediation: system retries failed gates, substitutes agents without human intervention
- [ ] Adversarial test suite: semantic cascade detection >70%
- [ ] 3+ external projects, 20+ sprints each, directional evidence
- [ ] ODD published: in-scope, out-of-scope, autonomy tier promises
- [ ] Deletion-recovery test passes: amnesiac >15% worse, recovery <50 sprints, no manual intervention

**Bead:** Sylveste-enxv.3 (deletion-recovery test)

### v1.0.0 — Stability Declaration

**Gate:** A:L4 + B:L4 + C:L4

No new features compared to v0.9.x. This is a stability commitment, not a feature release.

**Exit criteria:**
- [ ] All v0.7-v0.9 criteria still hold
- [ ] API stability contract published (what is frozen, what evolves, deprecation policy)
- [ ] Onboarding: time to first shipped change <60 minutes, 70%+ success without help
- [ ] Backward compatibility tested: v1.0 plugins load in v1.x
- [ ] Migration guide from v0.6.x → v1.0
- [ ] "State of production readiness" document published

---

## Current State (2026-04-27 Audit)

```
Track A (Autonomy):  ████████░░░░░░░░ L2.5  Runtime loops wired; proof window and anomaly receipts pending.
Track B (Safety):    ███████░░░░░░░░░ L2    Gate learning code exists; operational streak still unproven.
Track C (Adoption):  ████░░░░░░░░░░░░ L1    Self-building only. 800+ sessions.

Next gate: v0.7 (A:L3 + B:L2 + C:L1)
  Track A gap: 10-sprint no-touch proof + phase-cost anomaly receipts
  Track B gap: bd doctor auto-run + gate-learning receipts from natural sessions
  Track C gap: None (already at L1)
```

2026-04-27 evidence:
- Quality-gates records verdict outcomes via `_interspect_record_verdict()` in `os/Clavain/commands/quality-gates.md`.
- Routing calibration writes during Interspect session-end auto-calibration; Clavain accepts schema v1 and v2 calibration files.
- Clavain SessionEnd calibration hook runs both `calibrate-gate-tiers --auto` and `calibrate-phase-costs` in bounded fail-open mode.
- Gate calibration has a schema, drain algorithm, `ic gate signals` source, and SessionEnd hook. What remains is operational proof, not greenfield design.

## Bead Mapping

| Bead | Track | Level Target | Status |
|------|-------|-------------|--------|
| Sylveste-enxv.1 | Meta | Stability contract | ✓ Closed |
| Sylveste-enxv.2 | A | L1.5 → L3 | Open (P2) |
| Sylveste-enxv.3 | Cross | Deletion-recovery test | Open (P2) |
| Sylveste-0rgc | A+B | A:L3 + B:L2 (gate calibration) | Code shipped; proof window pending |
| Sylveste-py89 | B | B:L2 (bd doctor auto-run) | Open (P2) |
| Sylveste-c44z | Meta | This roadmap artifact | Open (P1) |
| sylveste-fd7x.6 | A+B | Audit remediation for closed-loop autonomy | Open |

## Progress Tracking

**Bead labels:** Every roadmap-relevant bead carries one or more track labels: `autonomy`, `safety`, `adoption`. Query with `bd list --label=autonomy` etc.

This document is updated when:
1. A track level is reached (evidence link added to the level section)
2. A version gate's exit criteria changes
3. A bead is closed that maps to a level target

The parallel structure means work on any track at any time. Version bumps happen when ALL tracks reach the gate. If one track races ahead, that's fine — the version gate ensures balanced progress for releases.
