---
artifact_type: prd
bead: sylveste-8em
stage: design
review: light (3 agents — architecture, safety, product/scope)
---
# PRD: Ockham Vision Document

## Problem

Sylveste's AI factory has no governor. Clavain dispatches agents, Interspect observes them, but nothing translates the principal's strategic intent into dispatch priority, manages authority tiers across domains, or detects factory-level anomalies. Without a governor, the principal must manually adjust weights, approve every promotion, and notice every degradation — a burden that scales linearly with factory size.

## Solution

Write the Ockham vision document: the architectural specification for the L2 factory governor that mediates between principal intent and factory execution. Ockham is a policy engine — it computes dispatch weight offsets, manages authority grants, and emits algedonic signals, but never dispatches agents or claims beads directly. The vision doc defines the architecture, interfaces, safety invariants, and phased rollout (Waves 1-4) so that implementation can proceed with clear contracts.

**Deliverable:** `os/Ockham/docs/vision.md` — a written architectural artifact. All acceptance criteria below are verifiable by reading the document, not by running code.

## Scope Boundary

The vision doc specifies *what* Ockham achieves and *why* each design choice was made. It does NOT specify implementation-level contracts (function signatures, exact thresholds, CLI argument syntax). Where the brainstorm contains implementation detail (e.g., exact promotion thresholds, function call order), the vision doc captures the design principle and defers exact values to design-phase specs.

## Features

### F1: Architecture & Position

**What:** Define Ockham's 4 subsystems, their dependency direction, and relationship to the rest of Sylveste. Establish what Ockham is NOT.

**Acceptance criteria:**
- [ ] Vision doc contains a subsystem table with input/output/wave/allowed-deps for each of Intent, Authority, Anomaly, Scoring
- [ ] Vision doc contains a dependency direction diagram showing no circular imports between subsystems
- [ ] Vision doc contains a "What Ockham Is Not" section distinguishing from scheduler, audit log, UI, Clavain replacement, quality arbiter, Skaffen governor
- [ ] Vision doc states the phased constraint: policy engine through Wave 3, re-evaluate dispatch authority at Wave 4
- [ ] Vision doc contains an architecture position diagram showing L1/L2/L3 layering with Ockham's interfaces to Clavain, Zaka, Alwe, Intercore, Meadowsyn
- [ ] Vision doc specifies degradation contracts for each subsystem: what happens when an upstream dependency is unavailable (Intent: use last-known-good; Authority: interspect unavailable → 5min stale snapshot → fail-closed; Anomaly: Alwe unavailable → skip Alwe-sourced inputs, proceed on remaining channels; Scoring: missing input struct → emit raw score unchanged + log missing-input event)

### F2: Intent Subsystem

**What:** Specify how the principal expresses strategic intent and how Ockham translates intent to dispatch weight offsets.

**Acceptance criteria:**
- [ ] Vision doc contains the intent.yaml schema with version, themes (budget/priority), constraints (freeze/focus), and validation rules
- [ ] Vision doc includes expiry fields: `valid_until` (timestamp) and `until_bead_count` (integer) with behavior on expiry (revert to neutral weight, warn on `ockham status`)
- [ ] Vision doc documents lane-to-theme mapping: `theme = bead.lane`, unlaned beads fall to `open` theme
- [ ] Vision doc specifies fallback behavior: missing/corrupt intent.yaml uses hardcoded default (all themes 1/N, priority normal)
- [ ] Vision doc specifies priority-to-offset magnitude mapping (high/normal/low → positive/zero/negative offset)
- [ ] Vision doc specifies atomic replacement semantics: validation before write, last-known-good preserved on invalid input

### F3: Scoring & Dispatch Integration

**What:** Define how Ockham's weight offsets integrate with existing dispatch scoring, and the gate-before-arithmetic contract for anomaly states.

**Acceptance criteria:**
- [ ] Vision doc specifies the additive offset formula and explains why additive (not multiplicative) preserves priority ordering
- [ ] Vision doc specifies bounds on offsets and includes reasoning showing they cannot invert adjacent priority tiers
- [ ] Vision doc defines the integration boundary: Ockham writes offsets to intercore state, lib-dispatch.sh reads them (Ockham does NOT own or modify dispatch functions)
- [ ] Vision doc specifies gate-before-arithmetic: CONSTRAIN and BYPASS produce dispatch eligibility decisions (block/allow), evaluated BEFORE weight arithmetic — not expressed as extreme negative weights that could be partially cancelled by intent boosts
- [ ] Vision doc specifies dual logging principle: both pre-offset and post-offset scores must be recorded for counterfactual calibration
- [ ] Vision doc specifies a weight floor to prevent theme starvation, with starvation detection and idle capacity release to the open pool
- [ ] Vision doc specifies bulk pre-fetch requirement (one state read per dispatch cycle, not per-bead)

### F4: Anomaly & Algedonic Signals

**What:** Specify the tiered algedonic signal system with confirmation windows, de-escalation, and weight-outcome feedback.

**Acceptance criteria:**
- [ ] Vision doc defines three tiers: Tier 1 INFORM (continuous adjustment), Tier 2 CONSTRAIN (freeze + notify), Tier 3 BYPASS (halt, reaches principal)
- [ ] Vision doc specifies multi-window confirmation for Tier 2 (short AND long windows must breach simultaneously)
- [ ] Vision doc specifies a rate-of-change fast path for rapid-onset incidents that bypasses the confirmation window
- [ ] Vision doc specifies de-escalation: both windows must clear, plus a stability period with no re-fire
- [ ] Vision doc specifies Tier 3 trigger criteria based on distinct root causes (not raw signal count)
- [ ] Vision doc specifies in-flight bead handling when a theme freezes (agents complete current work at supervised autonomy, no new claims)
- [ ] Vision doc enumerates six signal qualifications: qualification gate, root-cause dedup, multi-window, pleasure signals, observation separation (Alwe observes / Ockham acts), zero cost on healthy path
- [ ] Vision doc specifies the weight-outcome feedback loop: Ockham detects when its own weights degrade factory throughput and emits a self-corrective signal
- [ ] Vision doc specifies at least one independent observation channel that is agent-unwritable (e.g., git revert rate)
- [ ] Vision doc specifies paired confirmation before CONSTRAIN: requires interspect corroboration (no single-source CONSTRAIN)
- [ ] Vision doc specifies the Anomaly subsystem's degradation contract when Alwe is unavailable: skip Alwe-sourced inputs, proceed on remaining observation channels, log degraded-mode event

### F5: Authority & Autonomy Ratchet

**What:** Specify the per-domain autonomy state machine with promotion/demotion logic, cold start, and cross-domain resolution.

**Acceptance criteria:**
- [ ] Vision doc contains the state machine diagram: shadow → supervised → autonomous, with a transition table showing triggers and guards for each transition
- [ ] Vision doc specifies that promotion guards are evidence-quantity based (minimum beads at minimum complexity), not wall-clock windows
- [ ] Vision doc specifies asymmetric thresholds: promotion threshold > demotion threshold to prevent oscillation near boundaries
- [ ] Vision doc specifies per-domain (not per-agent) scope, with domain defined by CODEOWNERS-style globs
- [ ] Vision doc specifies cold start: infer from existing interspect evidence, conservative (max supervised even if evidence qualifies for autonomous)
- [ ] Vision doc specifies cross-domain min-tier rule: `effective_tier = min(tier for each matched domain)`
- [ ] Vision doc specifies ratchet runaway prevention: periodic re-confirmation of autonomous domains
- [ ] Vision doc specifies post-promotion audit: verify promoted agent performs as predicted within a confirmation period
- [ ] Vision doc specifies pleasure signals and their role in promotion decisions, noting they ship with Wave 1
- [ ] Vision doc specifies the interspect interface contract: what data Ockham reads from interspect for authority decisions
- [ ] Vision doc specifies behavior during interspect degradation: in-progress promotions are paused (not committed) until interspect recovers; in-progress demotions proceed immediately (fail-safe)
- [ ] Vision doc documents the known gaming surface (S-02: agents influence pass rates through bead granularity) and the interim mitigation: pleasure signals are treated as advisory for promotion decisions until Wave 3 resolves the canonical evidence source

### F6: Safety Invariants & Halt Protocol

**What:** Define the safety invariants with structural enforcement mechanisms, the halt protocol, and the restart sequence.

**Acceptance criteria — each invariant individually specified:**
- [ ] Vision doc specifies invariant 1 (no self-promotion): structural enforcement at the write path (consumers reject self-referential authority writes), not just behavioral compliance
- [ ] Vision doc specifies invariant 2 (delegation ceiling): an agent cannot grant authority exceeding its own level
- [ ] Vision doc specifies invariant 3 (action-time validation): authority checked at execution time, with degradation contract (stale snapshot window → fail-closed)
- [ ] Vision doc specifies invariant 4 (audit completeness): every authority decision produces a durable receipt in interspect
- [ ] Vision doc specifies invariant 5 (human halt supremacy): write-before-notify ordering, with crash-recovery scenario documented (process killed between write and notify → factory-paused.json still present and honored on restart)
- [ ] Vision doc specifies invariant 6 (weight neutrality floor): no bead silently blackholed by organic weights — explicit freeze required
- [ ] Vision doc specifies invariant 7 (signal independence): at least one Tier 3 trigger path is agent-unwritable and Clavain-independent (filesystem sentinel)
- [ ] Vision doc specifies invariant 8 (policy immutability during halt): all subsystems read-only when factory-paused.json exists
- [ ] Vision doc specifies the authority write token contract: who issues tokens, what signing mechanism is used, and how revocation works (design-phase detail, but the vision doc must name the approach)
- [ ] Vision doc specifies the Tier 3 restart sequence: principal action → check Tier 2 signals → constrained or normal mode → all domains reset to supervised for one confirmation period
- [ ] Vision doc specifies that at least one Tier 3 notification path is independent of Clavain (in case Clavain is hung)

## Non-goals

- **Implementation code.** This bead produces a vision document, not Go code. Implementation beads are children of the factory orchestration epic (Demarch-6fdq).
- **CLI interface spec.** Command signatures (`ockham intent`, `ockham resume`) are mentioned for context but their exact flags, arguments, and output format are deferred to design-phase beads.
- **Inter-package API schemas.** Wire formats, protobuf/JSON contracts, and function signatures are design-phase concerns. The vision doc names the interfaces, not their schemas.
- **Meadowsyn integration spec.** Meadowsyn's rendering of Ockham state is a separate concern.
- **Multi-factory support.** Single-factory assumption for Wave 1. Multi-factory deferred to post-Wave 1.
- **Skaffen governance.** Skaffen-dispatched work is outside Ockham's scope until Wave 4.
- **Test or validation plans.** How to test the implementation is a planning concern, not a vision concern.

## Dependencies

- **Brainstorm (done):** `docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md` (rev 3, 16-agent reviewed)
- **Research (done):** Algedonic signal design, authority tiers, Phase 1 self-dispatch (flux-research syntheses)
- **Flux-review (done):** `docs/research/flux-drive/ockham-vision/synthesis.md` (4-track, 16 agents, 15 cross-track findings)
- **Existing scaffolding:** `os/Ockham/` (Go module, AGENTS.md, CLAUDE.md with package map)

## Open Questions

1. **Evidence gaming vectors (S-02):** Agents influence their own first_attempt_pass_rate through bead granularity choices. Interim mitigation (advisory-only pleasure signals) documented in F5; canonical evidence source resolved during Authority package design (Wave 3).
2. **Multi-factory:** If multiple Sylveste instances share a beads tracker, does each get its own Ockham? (Defer to post-Wave 1.)
