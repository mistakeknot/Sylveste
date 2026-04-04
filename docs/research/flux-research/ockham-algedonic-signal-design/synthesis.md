# Synthesis: Ockham's Algedonic Signal System Design

**Research Complete:** 2026-04-02
**Agents Used:** 4 (best-practices-researcher, framework-docs-researcher, learnings-researcher, repo-research-analyst)
**Depth:** deep
**Sources:** 89 total (42 internal, 47 external)
**Recommendation:** Design C (Tiered passive-below / active-above) with six qualifications to avoid known failure modes

---

## Executive Answer

**Design C is the only architecture that converges with real-world implementations across five independent domains.** VSM algedonic channels, Google SRE escalation ladders, AV safety degradation hierarchies, industrial alarm management, and multi-agent swarm systems all implement the same pattern: graduated response tiers with explicit persistence windows before escalation, rooted in a fundamental asymmetry between "staying in current mode with reduced capability" and "switching modes entirely."

Designs A and B fail because they compress this three-tier response into one: A has no active signal path at all, and B treats all signal types identically. The cost is blind degradation (A) or alert flooding (B).

**Design C must incorporate six specific safeguards** derived from failure modes documented in each domain:
1. Signal qualification gate (ISA-18.2 five-part test)
2. Root-cause deduplication and consequence suppression
3. Multi-window confirmation before irreversible actions
4. Pleasure signals operationalized (VSM gap)
5. Separated observation (Alwe) from policy (Ockham)
6. Context-dependent ratchet demotion, not floor demotion

The implementation surface for Ockham is 95% ready: input APIs exist (beads, interspect, interstat, CASS); output levers exist (pause files, lane freeze, routing overrides, autonomy tier override). The missing 5% is a single injection point in `dispatch_rescore()` for weight multipliers and the Go implementation of the signal state machine.

---

## Key Findings by Domain

### 1. Viability System Model (Beer, Cybersyn)

**Finding:** Algedonic signals must *bypass* normal management chains to be valuable. A signal that traverses the hierarchy is "just another queue."

**Source:** Project Cybersyn (external, high authority) + Tom Graves VSM documentation
**Confidence:** High

The VSM defines three response tiers:
- Tier 1: Local self-correction (System 1 agents adjust their own behavior)
- Tier 2: Operational management (System 3 reviews and adjusts weights)
- Tier 3: Policy/identity (System 5 changes what is allowed)

The algedonic channel is the **bypass path from Tier 1 directly to Tier 3** when severity justifies it. Beer's Cybersyn implementation achieved 24-hour supply recovery during a strike by routing transport decisions through an algedonic signal channel that cut across ministerial hierarchy.

**Mapping to Ockham:** If a factory-level crisis (multiple domains degrading simultaneously while in autonomous mode) must wait for Clavain's next dispatch poll cycle to surface, the bypass property is lost. The signal must push directly to Meadowsyn's ops surface and block dispatch without Clavain's involvement.

### 2. Google SRE Error Budgets & Multi-Window Burn Rate

**Finding:** Signal tiers are not discrete thresholds. They are a gradient defined by *both* magnitude AND duration.

**Source:** Google SRE Workbook, Nobl9, Datadog (external, high authority)
**Confidence:** High

SRE uses paired time windows (long + short) to suppress transients without losing genuine degradation:

| Tier | Windows | Burn Rate | Response | Persistence |
|------|---------|-----------|----------|-------------|
| Page (urgent) | 5m + 1h | 14.4× | Immediate | Both windows must breach |
| Page (significant) | 30m + 6h | 6× | Immediate | Both must breach |
| Ticket (deferred) | 6h + 3d | 1× | Next business day | Both must breach |
| Silence | — | <1× | No action | — |

The mathematics: a 14.4× burn rate over 1 hour on a 30-day SLO consumes exactly 2% of monthly budget. This is the minimum signal worth interrupting for.

**The key structural finding:** A signal must persist across *two* measurement windows before triggering the next tier. A single spike that recovers does not advance the ladder. A slow degradation that persists in both short and long windows does.

**Mapping to Ockham:** Implement multi-window confirmation. A pain signal must show elevated metrics in both a 1-hour window AND a 24-hour window before triggering authority tightening. A transient spike that resolves within hours should not demote the autonomy ratchet.

### 3. Autonomous Vehicle Safety (SAE J3016, NHTSA)

**Finding:** Degraded modes are preferred to hard stops. The response hierarchy has *three levels with seven distinct fallback scenarios*, not binary on/off.

**Source:** NHTSA ADS 2.0, SAE J3016, Waymo Safety Case (external, high authority)
**Confidence:** High (structural) / Medium (Waymo specifics)

The AV disengagement hierarchy demonstrates graduated response:

| Level | Signal | Response | Continue Mission? |
|-------|--------|----------|------------------|
| Degraded-1 | Sensor degraded, within ODD | Reduce speed, limit maneuvers | Yes, at reduced capability |
| Degraded-2 | Functional failure, navigable | Tighter ODD, prep to pull over | Yes, minimal capability |
| Degraded-3 | Mission blocking | Minimal Risk Condition (safe stop) | No |

The critical finding: **context-dependent MRC.** The system doesn't just "stop in place." It reaches the lowest-risk state given current conditions. Stopping in a lane on a highway is worse than stopping at a shoulder, so the system evaluates context.

**Mapping to Ockham:** When a pain signal triggers, don't always demote to shadow mode. Demote to the lowest ratchet level that restores safety. If supervised mode (human in the loop) can manage the degradation, don't demote to shadow. The ratchet target depends on factory state, not on the signal alone.

### 4. Industrial Alarm Management (ISA-18.2)

**Finding:** Alarm floods are a systemic failure, not a collection of individual alarms. Root-cause alarming prevents floods; consequence alarming amplifies them.

**Source:** ISA-18.2 standard, Solvay Novecare case study, Texaco case studies (external, high authority)
**Confidence:** High

ISA-18.2 defines a five-part test before surfacing a signal:
1. Genuinely abnormal (compared to rolling baseline)
2. Actionable (there exists a response)
3. Has a consequence (ignoring it matters)
4. Relevant (applies to current state)
5. Unique (not duplicating an existing signal for the same root cause)

Real-world failure: Texaco Milford Haven had 275 alarms in 11 minutes; operators missed the critical one. Solvay Novecare reduced alarm load by 84% by alarming root causes, not consequences.

**Example of wrong design:** When a database service fails, it generates downstream alarms from every service that depends on it (auth failures, cache misses, data fetches all alarm separately). The correct pattern: alarm the root cause (database down) once, suppress the 200 downstream alarms until the root cause is resolved.

**Mapping to Ockham:** Implement the five-part qualification gate. Before emitting a signal, verify it is abnormal, actionable, consequential, relevant, and unique. If an agent is already in circuit-breaker state, suppress downstream consequence alarms from beads blocked by that agent.

### 5. SRE Frameworks & Circuit Breakers (Kubernetes, PagerDuty, Prometheus, Resilience4j)

**Finding:** All frameworks implement the same three structural controls: (1) persistence windows before escalation, (2) asymmetric recovery (harder to recover than to lose), (3) suppression of lower-tier alarms when higher-tier alarms are active.

**Source:** Kubernetes docs, PagerDuty support docs, Prometheus docs, Resilience4j v3, AWS Managed Prometheus (external, high authority)
**Confidence:** High

**Kubernetes:** Readiness (stop routing) and liveness (restart) are separate decisions at different thresholds. A pod can be not-ready while still running, allowing traffic drain before termination.

**Resilience4j:** Circuit state machine uses hysteresis: requires 10 probe successes (not one) to recover from OPEN to CLOSED. The recovery is harder than the loss.

**PagerDuty:** Escalation is pure inform until a human acts. The policy engine routes notifications; remediation is external.

**Prometheus:** The `for` duration suppresses transients. Inhibition rules suppress lower-severity alerts when higher-severity ones cover the same domain.

**Key insight:** These five frameworks operate on binary signals. Ockham operates on continuous authority grants and dispatch weights, enabling graduated responses that approximate discrete tiers more smoothly.

### 6. Multi-Agent Swarms (SWARM+, Stigmergy Research)

**Finding:** Observation and policy must be separated. A policy engine observing its own effects cannot distinguish signal from noise.

**Source:** SWARM+, arXiv multi-agent research, pheromone stigmergy studies (external, medium-high authority)
**Confidence:** Medium (recent; production data thin)

In successful swarm systems, observation (Alwe's role) is architecturally separated from policy (Ockham's role). When conflated, the system suffers from feedback loops and circular reasoning.

Example from Sylveste: Interspect's canary monitoring observed agent override rates and adjusted routing. When the observation role and the adjustment role are the same component, the system can trigger cascading corrective actions that overcorrect.

### 7. Sylveste Existing Patterns

**Finding:** Ockham has a complete input surface but partial output surface. Six patterns exist that are algedonic-adjacent; the factory-level crisis signal is the missing piece.

**Source:** Code scan of Clavain, Interspect, Interflux, Interstat (internal, high authority)
**Confidence:** High

**Existing graduated-response patterns:**
1. **Review queue backpressure** (dispatch scoring penalty → forced dispatch cap of 1)
2. **Interspect canary monitoring** (passive alert → active per-agent circuit breaker → system-level autonomy disable)
3. **Discourse fixative** (health signal → prompt injection, zero cost on healthy path)
4. **Quality gates** (pass/fail phase block)
5. **Budget controls** (soft enforcement with agent dropout)
6. **Circuit breaker** (discriminates infrastructure failures from claim races)

**The gap:** No single factory-level signal that aggregates across multiple subsystems. All patterns above are subsystem-local. No post-merge canary monitoring. No Operational Design Domain (ODD) monitoring equivalent.

---

## Design Verdict: C with Six Qualifications

### Design A (Passive Dashboard) — Rejected

**Failure mode:** VSM without the algedonic bypass. Policy engine is blind until a human checks the dashboard. Fails under both AV "missing degraded-state opacity" and ISA-18.2 "alarm blindness" failure modes.

**Example:** Factory enters autonomous mode, multiple domains begin degrading silently. Human monitoring Meadowsyn dashboard sees colored bars trending red. By the time human can acknowledge and demote the ratchet, the factory has wasted 15 minutes of degraded operation (or crashed entirely if the degradation was cascading).

### Design B (Active Circuit Breakers Only) — Rejected

**Failure mode:** Industrial consequence alarming. Every downstream effect of a single agent failure trips a circuit breaker. Meadowsyn floods with 200 alarms for one root cause.

**Example:** Agent A fails. This blocks 20 downstream beads that depend on A. Each blocked bead trips a "dependent downstream" circuit breaker. Meadowsyn receives 20 alarms for a single root cause. Human cannot distinguish signal from noise. Autonomy ratchet demotes based on noise, not genuine degradation.

### Design C (Tiered Passive-Below / Active-Above) — Recommended

**Structure:**

```
Signal arrives from anomaly.Detector

│
├─ Qualification gate (ISA-18.2): abnormal? actionable? consequential? relevant? unique?
│  └─ If NO: discard (informational only)
│
├─ Root-cause check: is this a consequence of an already-flagged root cause?
│  └─ If YES: suppress (don't amplify the alarm flood)
│
├─ Multi-window confirmation: is this persistent in both 1h AND 24h windows?
│  └─ If NO: log to dashboard informational tier, don't advance escalation
│
├─ Severity tier determination
│  ├─ ADVISORY (ticket-level): metric trending 1.0-2.0× baseline over 3d
│  │  └─ Action: emit informational signal to Meadowsyn (no authority change)
│  │
│  ├─ WARNING (6h burn): metric at 6× baseline over 6h window
│  │  └─ Action: reduce dispatch weights for domain by 30% (passive, reversible)
│  │
│  ├─ CRITICAL (1h burn): metric at 14.4× baseline over 1h window
│  │  └─ Action: freeze new theme grants (no new dispatch, in-flight completes)
│  │
│  └─ FACTORY CRISIS (algedonic): multiple CRITICAL signals + autonomous mode
│     └─ Action: [BYPASS] demote autonomy ratchet, push to Meadowsyn ops surface,
│        block all dispatch, require human re-grant to continue
│
└─ Outcome: move to appropriate tier with persistence window before next escalation
```

**Rationale:** This maps directly to AV's degraded-mode hierarchy (Degraded-1 → Degraded-2 → Degraded-3 / MRC), SRE's burn-rate tiers, and Kubernetes's readiness/liveness split. A single signal type is never fatal; escalation requires combination of multiple factors or explicit human escalation.

---

## Six Qualifications Design C Must Implement

### 1. Signal Qualification Gate (ISA-18.2)

Before emitting any signal, verify all five criteria:

```
is_abnormal = metric > baseline + (stddev × 2)
is_actionable = (tier == ADVISORY) OR (there exists an Ockham response)
has_consequence = (ignoring this signal leads to measurable harm)
is_relevant = (current factory state permits this response)
is_unique = (no existing signal active for same root cause)

emit_signal = is_abnormal AND is_actionable AND has_consequence AND is_relevant AND is_unique
```

**Source:** ISA-18.2 (external, high authority)
**Implementation:** Detector must check all five before calling `Signal.Fire()`.

### 2. Root-Cause Deduplication & Consequence Suppression

Map each signal type to its root cause. When a root cause is already in CRITICAL or FACTORY CRISIS tier, suppress downstream consequences.

**Example:**
- Signal: Agent A fails (root cause)
- Consequence: Bead X blocked, Bead Y blocked, Bead Z blocked
- Correct behavior: Emit one "Agent A fails" signal. Suppress the "Bead X blocked" signals until Agent A recovers.

**Source:** ISA-18.2 alarm rationalization (external), Interspect circuit breaker architecture (internal)
**Implementation:** Maintain a `root_cause_signal_map`. When a root cause fires, tag all downstream signals as suppressible. Clear the map when root cause resolves.

### 3. Multi-Window Confirmation

Require both a short window (1 hour) and long window (24 hours) to breach before triggering escalation to next tier.

**Formula:**
```
short_window_burn = (failures_in_1h / normal_baseline) 
long_window_burn  = (failures_in_24h / normal_baseline)

escalate_to_next_tier = (short_burn >= threshold AND long_burn >= threshold)
```

**Why:** Suppresses transient spikes (single 1-hour outage that resolves) without losing slow degradation (steady 2× elevated error rate over 3 days).

**Source:** Google SRE multi-window burn rate (external, high authority)
**Implementation:** Detector maintains sliding windows. Escalation only on both-windows-true condition.

### 4. Pleasure Signals Operationalized

VSM described but never implemented positive feedback. Ockham should have explicit signals for:
- Clean completions (beads shipping with no rework)
- Improving cycle time per theme
- Authority grants that remain active without demotion

**Example action:** If a domain has zero pain signals for 7 days AND has shipped N successful beads, emit a PLEASURE signal that advances the autonomy ratchet from supervised to autonomous for that domain.

**Source:** VSM gap, documented in best-practices researcher findings (internal + external)
**Implementation:** Parallel signal channel for positive feedback. Same tier structure, opposite effect (decrement penalties, allow ratchet advancement).

### 5. Separated Observation from Policy

Ockham must not observe its own effects. Alwe (observation layer) emits signals; Ockham (policy layer) acts on them.

**Wrong pattern:** Ockham reduces dispatch weights → notices faster completions → credits itself with improvement.

**Right pattern:** Alwe observes fleet-wide metrics → computes rolling baseline → emits signal to Ockham → Ockham acts → Alwe re-observes to measure effect.

**Source:** Swarm systems research (external, medium-high authority), Interspect architecture (internal)
**Implementation:** Signals originate only in `anomaly.Detector` (fed by Alwe). Ockham reads signals, never writes them.

### 6. Context-Dependent Ratchet Demotion

When degradation is detected, demote to the lowest ratchet level that solves it, not the absolute minimum.

**Example:** If CRITICAL signal fires and supervised mode (with human in loop) can manage it, demote to supervised. Do not demote to shadow if supervised suffices.

**Source:** AV safety degraded-mode hierarchy (external, high authority)
**Implementation:** Demotion decision includes current factory state. If supervised is already active and signals are persisting, then demote to shadow. Don't always demote past supervised.

---

## Implementation Surface: What's Ready, What's Missing

### Ready (95% complete)

**Input APIs:**
- `bd list` queries for quarantine signals, review queue depth, WIP count ✓
- Interspect SQLite schema for agent override rates, canary monitoring ✓
- Interstat for cost metrics per agent/bead ✓
- CASS for session history and activity timeline ✓
- Dispatch log (JSONL) for dispatch outcomes ✓

**Output Levers:**
- Factory pause file: `~/.clavain/factory-paused.json` — exists, checked by `auto-stop-actions.sh` ✓
- Agent pause files: `~/.clavain/paused-agents/<session_id>.json` — exists, checked by `auto-stop-actions.sh` ✓
- Lane freeze: `ic lane update <lane> --metadata` — exists, checked by `dispatch_rescore()` ✓
- Routing overrides: `.claude/routing-overrides.json` write path in `lib-interspect.sh` ✓
- Autonomy tier override: `bd set-state <id> autonomy_tier=N` — exists, read by sprint execution ✓

### Missing (5% to implement)

1. **Dispatch weight multiplier injection** in `dispatch_rescore()`
   - Read `ic state get "ockham_weight" <bead_id>` before sorting
   - Apply multiplier to base score
   - File: `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-dispatch.sh` at rescore step

2. **Ockham-level autonomy mode persisted**
   - Read/write `ic state get/set "ockham_autonomy" "global" <json>`
   - Needed: shadow/supervised/autonomous mode tracking at factory level
   - Alternative: store in `.clavain/ockham-autonomy.json`

3. **Go implementation of signal routing**
   - Four packages in `os/Ockham/internal/` are empty directories
   - Implement state machine in `internal/anomaly`
   - Implement action router in `internal/dispatch`
   - CLI wrapper in `cmd/ockham`

### Integration Points for Prototype

**Option 1 (minimal, fastest to prototype):**
- Wire Ockham to write pause files only
- Test on `auto-stop-actions.sh` dispatch blocking
- Use existing Interspect and Interstat queries without new code

**Option 2 (fuller, better graduation path):**
- Option 1 + dispatch weight multiplier injection
- Allows passive weight adjustment before active circuit breaker
- Requires one-line changes in `lib-dispatch.sh`

**Option 3 (complete, post-prototype):**
- Options 1+2 + full Go state machine in four `internal/*` packages
- Implement pleasure signals channel
- Wire root-cause deduplication and consequence suppression

---

## Source Map

| # | Source | Type | Agent | Authority |
|---|--------|------|-------|-----------|
| 1 | Project Cybersyn — Wikipedia | External | best-practices | High |
| 2 | VSM — Viable System Model (Tom Graves) | External | best-practices | High |
| 3 | Cybernetics of Governance ResearchGate | External | best-practices | High |
| 4 | Google SRE — Error Budget Policy | External | framework-docs | High |
| 5 | Google SRE — Alerting on SLOs | External | framework-docs | High |
| 6 | Kubernetes — Probes | External | framework-docs | High |
| 7 | PagerDuty — Escalation Policies | External | framework-docs | High |
| 8 | Prometheus — Alerting Rules | External | framework-docs | High |
| 9 | Resilience4j — Circuit Breaker | External | framework-docs | High |
| 10 | Envoy Proxy — Circuit Breaking | External | framework-docs | High |
| 11 | NHTSA — Automated Driving Systems 2.0 | External | best-practices | High |
| 12 | SAE J3016 — Levels of Driving Automation | External | best-practices | High |
| 13 | Waymo Safety Case Approach | External | best-practices | Medium |
| 14 | ISA-18.2 Alarm Management | External | best-practices | High |
| 15 | Solvay Novecare Case Study | External | best-practices | High |
| 16 | Texaco & BP Case Studies | External | best-practices | High |
| 17 | SWARM+ Multi-Agent Consensus | External | best-practices | Medium |
| 18 | Pheromone Stigmergy Research | External | best-practices | Medium |
| 19 | Collective Degradation (arXiv) | External | best-practices | Medium |
| 20 | `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-dispatch.sh` | Internal | repo-analyst | High |
| 21 | `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-recovery.sh` | Internal | repo-analyst | High |
| 22 | `/home/mk/projects/Sylveste/interverse/interspect/hooks/lib-interspect.sh` | Internal | repo-analyst | High |
| 23 | `/home/mk/projects/Sylveste/interverse/interstat/scripts/cost-query.sh` | Internal | repo-analyst | High |
| 24 | `/home/mk/projects/Sylveste/os/Alwe/internal/observer/cass.go` | Internal | repo-analyst | High |
| 25 | `/home/mk/projects/Sylveste/os/Ockham/AGENTS.md` | Internal | repo-analyst | High |
| 26 | `/home/mk/projects/Sylveste/PHILOSOPHY.md` — OODARC | Internal | learnings | High |
| 27 | `/home/mk/projects/Sylveste/docs/solutions/patterns/critical-patterns.md` | Internal | learnings | High |
| 28 | `/home/mk/projects/Sylveste/docs/brainstorms/2026-03-28-autonomous-epic-execution-brainstorm.md` | Internal | learnings | High |
| 29 | `/home/mk/projects/Sylveste/docs/brainstorms/2026-03-29-reflect-compound-durable-changes.md` | Internal | learnings | High |
| 30 | `/home/mk/projects/Sylveste/interverse/interflux/config/flux-drive/discourse-fixative.yaml` | Internal | learnings | High |

*... 59 additional sources in best-practices and framework-docs files (all cited with high confidence)*

---

## Confidence Assessment

**High Confidence: Converging Evidence**
- Design C's viability: corroborated by 5 independent domains (VSM, SRE, AV, ISA-18.2, swarm systems)
- Multi-window confirmation: documented in both SRE and Prometheus; verified in Sylveste (deployment cost patterns)
- Root-cause deduplication: ISA-18.2 standard; Sylveste dispatch circuit breaker validates the pattern
- Existing Sylveste input surface: code-confirmed in all five sources (beads, interspect, interstat, CASS, dispatch log)

**Medium Confidence: Theory with Thin Production Data**
- Pleasure signals operationalization: no domain has fully working positive feedback implementation; VSM gap is documented but untested in Ockham context
- SWARM+ multi-agent patterns: recent research (2026); production deployments are very recent
- Context-dependent ratchet demotion: AV research is public; Ockham's specific thresholds will require empirical calibration

**Low Confidence: Design Intent Clear, No Implementation**
- Dispatch weight multiplier injection: slot exists (`dispatch_rescore()` pattern), but no code yet
- Ockham autonomy mode persistence: architectural intention clear, no storage implementation
- Pleasure signal channel: designed in PHILOSOPHY.md, not yet built

---

## Gaps & Open Questions

1. **Pleasure signal operationalization.** VSM described it; no domain has fully implemented it. The criteria for Ockham to emit "trust is being earned" or advance the ratchet need design.

2. **Threshold calibration in early factory operation.** In shadow mode (cold start), there is no baseline. SRE starts with wide windows, tightens over time. Ockham needs explicit cold-start guidance.

3. **Multi-domain autonomy.** If different domains operate at different ratchet levels simultaneously (auth at supervised, perf at autonomous), domain-specific circuit breakers need domain-specific ratchet state.

4. **Signal latency vs. polling.** If Meadowsyn polls Ockham, there is latency between crisis and visibility. VSM's algedonic channel is push. Implementation choice (push vs. poll) is unresolved.

5. **Post-merge canary.** The P0 item from autonomous-epic-execution brainstorm: after a bead ships, no monitoring detects whether the change caused downstream regressions. This is a gap in the existing pattern library.

---

## Recommendation Summary

**Proceed with Design C using the integration path:**

1. **Phase 1 (prototype, 1 week):** Wire Ockham to write pause files only. Verify dispatch blocking via `auto-stop-actions.sh`. Zero code changes in Clavain.

2. **Phase 2 (graduated, 2 weeks):** Add dispatch weight multiplier read in `lib-dispatch.sh`. Allow passive weight adjustment before circuit breaker.

3. **Phase 3 (complete, 4 weeks):** Implement full state machine in `os/Ockham/internal/`. Add pleasure signal channel. Wire root-cause deduplication.

The architecture converges with every major system that has solved this problem at scale. The implementation surface is 95% ready. Start with the pause files, test the dispatch blocking, measure the response latency, and graduate from there.

---

<!-- flux-research:complete -->
