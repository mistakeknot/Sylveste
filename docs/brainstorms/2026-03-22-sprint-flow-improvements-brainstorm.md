---
artifact_type: brainstorm
bead: none
stage: discover
---

# Sprint Flow Improvements: Fresh-Eyes Review

## What We're Building

Improvements to the Clavain sprint orchestration flow, informed by a 3-pass review:
1. **My review** (8 structural concerns)
2. **Standard flux-drive** (5 agents: architecture, user-product, correctness, resilience, systems)
3. **Research-generated custom agents** (5 agents: control-theoretic, bio-adaptive, mission-command, cognitive-architecture, compositional-dynamics) — grounded in deep research across control theory, immunology, military C2, game AI, philosophy of mind, ecology, musical form, and manufacturing

Total: 16 independent review perspectives producing ~100 findings, distilled into 7 convergent themes.

## Why This Approach

The sprint flow is Demarch's core loop — PHILOSOPHY.md says "if this journey is slow, brittle, or opaque, the platform fails regardless of how elegant its architecture is." Rather than adding incremental fixes, this brainstorm synthesizes cross-domain analysis to identify structural improvements that compound.

## Key Decisions

### Theme 1: OODARC as Waterfall -> Nested Loops

**Current:** Orient happens once (Strategy/Step 2). Tier 1 skips Observe (brainstorm). Failures halt instead of re-orienting.

**Proposed direction:**
- Orient runs continuously — lightweight re-orient at every phase transition and on every failure
- Tier 1 skips Decide (planning), not Observe — compressed observation + pattern-recognized direct execution (Boyd's IG&C fast path)
- Failures trigger re-orient before deciding to retry/replan/escalate
- Measure orient quality: strategy-drift score (how often does strategy survive execution unchanged?)

### Theme 2: Fixing the Reflect Trap

**Current:** Reflect produced under worst context pressure, value delayed weeks, soft gate enables skipping, calibration corpus has survivorship bias.

**Proposed direction:**
- Pre-commitment: reserve non-redirectable reflect budget at sprint start (Ulysses contract)
- Immediate-payoff reflection: show "3 past reflect learnings influenced this sprint" at sprint start
- Reflect must reference brainstorm themes (sonata recapitulation — did our understanding of the problem transform?)
- Harden gate from soft to firm: minimal reflect artifact required (3 lines minimum)
- Failed sprints still contribute calibration data (survivorship bias fix)

### Theme 3: Classification -> Belief Distribution

**Current:** Single complexity integer, cached at route time, never updated.

**Proposed direction:**
- Carry a belief distribution over complexity through all 10 steps
- Update at each phase transition using actual-vs-estimated token spend as observation signal (Kalman gain equivalent)
- When complexity increases past a tier boundary mid-sprint, autonomy downgrades automatically (JPL asymmetric transitions: fast autonomous downgrade, slow evidence-based upgrade)
- Add pre-sprint metacognitive probe (FOK: agent's confidence rating, calibrated against outcomes over time)

### Theme 4: Review Gauntlet -> Jidoka + Tolerance

**Current:** Steps 6-9 are 4 flat sequential review phases. Quality gates discover problems; earlier steps don't self-check. No suppression of repeatedly-dismissed findings.

**Proposed direction:**
- Every step self-checks during execution (Jidoka) — quality gates becomes confirmation, not discovery
- Immune tolerance: `tolerance.yaml` tracks dismissal patterns, auto-suppresses after N dismissals
- Habituation/sensitization: findings have adaptive severity (habituate on repeated dismissal, sensitize after incidents)
- Consolidate Steps 6-10 into two cognitive blocks: Verify (test + gates) and Close (resolve + reflect + ship)
- Early termination: if first K agents all return CLEAN on a C1-C2 task, skip remaining agents

### Theme 5: Fight Hurt, Don't Halt

**Current:** Error recovery is "retry once, halt." Binary running/halted.

**Proposed direction:**
- Define explicit degraded modes per subsystem (review fleet, test suite, intercore, routing, budget)
- Capability reduction table: "review fleet offline -> sprint continues with self-review, flagged as unreviewed"
- Safe mode: checkpoint all work, commit clean changes, produce diagnostic, await guidance (not just halt)
- Degradation ladder: full scope -> critical-path-only -> skeleton -> checkpoint-only
- Apoptosis: steps detect internal damage (token velocity anomaly, scope drift) and self-terminate cleanly

### Theme 6: Composable Pipeline

**Current:** Fixed 10-step template. Autonomy tiers are skip/pause toggles on same steps.

**Proposed direction:**
- Define entry/exit contracts per step (preconditions + effects)
- Phase 1: use contracts for validation only (fail if precondition unmet)
- Phase 2: constraint solver composes minimal valid pipeline per task
- Invariants ("chord changes") extracted and enumerated separately from sequence ("melody")
- Tier 0 "reflex" mode: for recognized patterns, skip pipeline entirely (no plan, no checkpoints, just act)

### Theme 7: Mycorrhizal Sprint Network

**Current:** Sprints are isolated. Concurrent sprints share no insights.

**Proposed direction:**
- Sibling sprint terrain reports: at bootstrap, load disturbance artifacts and reflect summaries from sibling beads
- Defense signaling: when a sprint discovers an architectural constraint, emit interlock broadcast
- Enriched regression: `--from-step` carries a structured disturbance record (what failed, why, what to do differently)
- Parent epic shares understanding downward to child sprints

## Open Questions

1. **Composability vs. predictability tradeoff:** Dynamic pipeline composition is powerful but the fixed 10-step checklist is a strong legibility artifact. Phase the transition (validation-only first)?
2. **Reflect commitment device:** Pre-committed budget that can't be raided — too rigid? Or necessary because temporal discounting guarantees skipping?
3. **Belief distribution complexity:** Carrying a probability distribution over complexity through 10 steps adds cognitive overhead. Is a simpler mid-sprint "complexity bump" trigger sufficient?
4. **Mycorrhizal scope:** Inter-sprint communication is architecturally ambitious. Start with just disturbance records (enriched regression) and defer runtime terrain reports?
5. **Which themes to tackle first?** Bugs are immediate. Theme 2 (reflect trap) and Theme 5 (fight hurt) have the best effort/impact ratio. Theme 1 (OODARC waterfall) is the deepest structural change.

## Research Sources

Six deep research domains informed the custom review agents:
- **Control theory:** MPC rolling horizons, PID budget control, anytime algorithms, Kalman filtering, MRAC adaptive control (bursting phenomenon)
- **Biological systems:** Immune tolerance, allostasis, apoptosis, habituation/sensitization, clonal selection, circadian rhythms
- **Military C2:** Boyd's OODA (Orient dominance, IG&C), Auftragstaktik, JPL ALFUS framework, naval degraded operations, CCIR information triage
- **Game AI / Manufacturing:** GOAP, Utility AI, behavior trees, Theory of Constraints, Kanban WIP limits, MCTS, Jidoka, roguelike procedural generation
- **Philosophy / Cognitive Science:** Dreyfus skill acquisition, metacognition (FOK), System 1/2, extended mind thesis, satisficing vs maximizing, temporal discounting, enactivism, flow states
- **Arts / Ecology:** Sonata form, Kuleshov effect, ecological succession, jazz improvisation, fermentation/aging, tidal patterns, mycorrhizal networks, theatrical dramaturgy
