---
artifact_type: brainstorm
bead: none
stage: discover
---

# AI Factory Orchestration: From Dispatch Bottleneck to Autonomous Software Factory

**Date:** 2026-03-19
**Status:** Brainstorming
**Research:** [10-agent synthesis](../research/flux-research/ai-factory-work-orchestration-lessons/synthesis.md)

## What We're Building

A phased evolution of Demarch's work orchestration from "human dispatches agents to prioritized backlog" to "agents self-serve from a CUJ-driven backlog with earned autonomy and machine-verifiable quality gates."

The core thesis: **AI factory orchestration is a governance problem, not a PM problem.** The question isn't "how do we track work?" (beads solves this) but "how do we delegate authority so agents can act without human dispatch while maintaining quality and cost control?"

### The Problem Today

The principal (user) is the dispatch bottleneck. The backlog is prioritized, the toolchain exists (beads + route.md + flux-drive), but every work assignment requires a human to:
1. Tell an agent "go pick up bead X"
2. Tell an agent "use flux-gen + flux-drive for this brainstorm"
3. Review every output before it lands
4. Monitor agent state across tmux tabs

At 3-5 agents this is manageable. At 10+ it's unsustainable. The system knows what to do but can't act without the human issuing each command.

### The Vision

The human principal operates at the **CUJ level**: "Ship this journey" and "Is this journey healthy?" Everything below that is derived:
- CUJs decompose into beads (planning)
- CUJs gate completion (quality)
- Agents pull work from CUJ-prioritized backlogs
- The principal issues intent directives ("focus on CUJ-3 this week"), not task assignments
- Authority is graduated and earned: agents prove competence per domain before gaining autonomy
- Quality gates are multistage: deterministic (tests) -> stochastic (LLM judge) -> human (irreversible only)

## Why This Approach

### Hybrid pull + intent (not pure push, not pure pull)

Three patterns from non-software domains converged on this:

1. **Military mission-type orders (Auftragstaktik):** Commander states intent + constraints; subordinates self-organize to achieve it. Enables adaptation when conditions differ from plan.
2. **Autonomous fleet dispatch:** Vehicles pull tasks from a ranked queue based on proximity/capability. Central coordinator sets priorities, not assignments.
3. **Hospital OR block scheduling:** 60-75% capacity reserved for planned work, 25-40% for emergent. Agents pull from both pools based on capability and availability.

Pure push (Mycroft assigns everything) creates a single point of failure. Pure pull (agents grab whatever) lacks strategic direction. Hybrid gives the principal leverage without requiring per-task involvement.

### CUJs as both plan AND gate

CUJs already exist as static reference docs. Making them active means:
- **Plan:** "Ship CUJ-3" decomposes into required beads. Strategy phase maps CUJ success signals to concrete work.
- **Gate:** Every bead links to a CUJ. Completion requires the CUJ's success signals to pass (not just "tests pass" but "the user journey works end-to-end").
- **Priority:** CUJ health scores drive backlog ordering. Unhealthy CUJs generate work automatically.

### Phased delivery with validation gates between phases

Each phase is an epic bead blocked by the previous phase being validated and closed. Ship something every 2 weeks, validate it works at current agent count, then layer on the next capability.

## Key Decisions

1. **Governance, not PM.** We're not building another Jira. We're building the authority delegation layer that lets agents self-serve from an existing tracker (beads).

2. **Hybrid pull + intent dispatch.** Agents pull from prioritized backlog; principal shapes priorities via CUJ-level intent directives. Mycroft monitors and escalates, not assigns.

3. **CUJs as first-class planning AND gating objects.** CUJs drive what work exists and what "done" means. The principal thinks in journeys, not tickets.

4. **Cost as primary metric.** Cost-per-task replaces time estimates. Routing, gating, and forecasting all use token cost distributions, not story points or hours.

5. **Graduated authority earned through evidence.** Five tiers (Propose/Execute/Commit/Deploy/Spend) x domain scope. Earned through track record, lost through incidents. Interspect provides the evidence.

6. **Multistage quality gates.** Deterministic (compile+test+lint) -> Stochastic (LLM judge) -> Human (irreversible only). Confidence scoring determines which gate level applies.

7. **Two-level decomposition.** Strategy produces beads; agents refine beads into sub-tasks at claim time. `bd refine` lets agents propose discovered complexity.

8. **Manufacturing rework model.** Full research: [Rework model synthesis](../research/flux-research/rework-model/synthesis.md). Six dispositions (scrap/rework/repair/RTV/downgrade/deviation) replace "reopen ticket." Quarantine-to-disposition SLAs prevent limbo. Salvage ratio drives scrap-vs-rework: scrap optimal <0.3, rework optimal >0.5. Context pollution gives scrap a unique benefit in token systems (fresh context window).

9. **Interlab/autoresearch patterns.** Campaign-as-intent maps to the directive model. Circuit breakers (max iterations, max crashes, max no-improvement) replace human approval gates during execution. Compound learning via mutation store with provenance prevents rediscovery of dead ends. The factory's discovery loop is structurally identical to interlab's autoresearch loop: hypothesize → edit → benchmark → keep/discard.

## Rollout: 3 Waves

Restructured from 6 sequential phases to 3 waves. Each wave is a coherent capability increment validated as a unit. Epic beads, each blocked by the previous wave's validation.

Rationale: matches interlab campaign pattern (wave = campaign with stopping condition), reduces principal review surface from 6 gates to 3, bundles naturally related work, and follows "measurement precedes control" (Wave 1 generates data Wave 2 needs, Wave 2 generates evidence Wave 3 needs).

### Wave 1: Foundation (3 weeks)
*"Are agents pulling and completing work without me dispatching?"*

Full research: [Phase 1 synthesis](../research/flux-research/phase1-self-dispatch/synthesis.md)

**What ships:**
- **P0 fix:** Atomic claim (merge two-phase into single Dolt transaction, 2-4 hours)
- **Deterministic quality gates:** compile + test + lint + type-check as pre-commit hooks
- **Self-dispatch loop:** Stop hook trigger → 20s idle cooldown → score-based bead selection (priority 40%, phase 25%, recency 15%, deps-ready 12%, WIP-balance 8%) → atomic claim with jitter → dispatch via route.md
- **Failure recovery:** 4-tier escalation (auto-retry max 3 → quarantine → circuit breaker → factory pause), failure classification (retriable/spec_blocked/env_blocked)
- **Basic feedback:** Fleet utilization, queue depth, WIP balance (zero code changes for these 3)

**Validation criteria:**
- ≥3 agents self-dispatch for 48 hours without human per-task commands
- Deterministic gates catch ≥1 real issue that would have shipped
- Stale-claim recovery triggers ≤2 false positives

### Wave 2: Intelligence (3 weeks)
*"Is the factory working on the right things at reasonable cost?"*

Full research: [CUJ gating synthesis](../research/flux-research/cuj-gating-model/synthesis.md)

**What ships:**
- **CUJ health scoring:** health = (signals passing / total), weighted by criticality. Auto-generates beads from signal gaps and friction points
- **CUJ-driven backlog ordering:** beads linked to CUJs, priority derived from CUJ health × theme weight
- **Cost-aware routing:** fleet-registry cost profiles drive model selection (cheap tasks → cheap models). Budget-blocked work deferred, not forced to expensive models
- **Authority shadow mode:** Log all authority decisions (who would be allowed/denied per domain), block nothing. Build evidence baseline for Wave 3
- **Three-state CUJ gates:** pass/marginal/fail with signal tiers. Marginal triggers targeted re-check, not full re-plan

**Validation criteria:**
- CUJ health scores correlate with user-perceived journey quality (spot-check 5 CUJs)
- Cost per landed change drops ≥15% from cost routing
- Authority shadow logs show ≥80% of decisions would be correct if enforced

### Wave 3: Autonomy (4 weeks)
*"Can I step back to CUJ-level oversight?"*

Full research: [Authority tiers synthesis](../research/flux-research/authority-tiers/synthesis.md), [Rework model synthesis](../research/flux-research/rework-model/synthesis.md)

**What ships:**
- **Authority enforcement:** `effective_action = min(fleet_tier, domain_grant)`. 4 Dolt tables + `authority.owners` YAML. Evidence thresholds (Promote: 5 obs @80% → 15 @90% → 30 @95%; Demote fires faster). 5 safety invariants enforced
- **Semantic gates + confidence scoring:** LLM-as-judge scores intent alignment. Auto-merge >0.9, hold <0.7. Signal decomposition upgrades qualitative → measurable
- **Rework disposition taxonomy:** 6 dispositions (scrap/rework/repair/RTV/downgrade/deviation). Quarantine-to-disposition SLAs. Salvage ratio drives scrap-vs-rework. Context pollution as scrap benefit
- **Intent directives:** Themes → CUJ health → beads. Factory proposes budgets, principal adjusts. Discovery budget per theme, tiered by trust
- **Claims-time decomposition:** `bd refine` for mid-execution sub-tasks. Auto-merge if complexity increase <20%
- **Re-engagement protocol:** SBAR-format context reconstruction. Decision replay for last N decisions
- **Compound learning:** Mutation store with provenance (from interlab pattern). Prevents rediscovery of dead ends

**Validation criteria:**
- 10+ agents operate for 1 week with principal spending <15 min/day on oversight
- Authority enforcement produces ≤5% false denials
- Rework disposition reduces wasted tokens (scrap-after-rework) by ≥30%
- Factory-proposed intent accepted without modification ≥60% of the time

## CUJ Activation Model (Refined)

Second research round (5 agents, 120 sources) produced a detailed CUJ gating model. Full synthesis: [CUJ gating synthesis](../research/flux-research/cuj-gating-model/synthesis.md)

### CUJ Health Score Drives Planning

CUJ health = (signals passing / total signals), weighted by criticality. Friction points are weighted negatively. The system auto-generates beads from:
- **Signal gaps:** signals with status "planned" or "not measured" become beads to make them active
- **Friction points:** each friction becomes a bead to resolve it
- **Priority:** ranked by health impact per bead

The principal says "ship CUJ-3" = "get health to 1.0." The system decomposes that into a work queue.

### CUJ Gating Model: Three-State Gates with Signal Tiers

**Gate type is determined by signal verifiability ceiling, not implementation convenience.**

| Signal Type | Verifiability | Gate Mode | Failure Response |
|-------------|---------------|-----------|------------------|
| Measurable | ~100% | Hard block | Immediate rejection, retry 1x |
| Observable | ~95% | Three-state (pass/marginal/fail) | Marginal: targeted re-check; Fail: re-plan |
| Qualitative | ~80% (LLM-as-judge ceiling) | Evidence accumulation | Log finding for milestone review, don't block |

**Key insight:** Many "qualitative" signals are actually decomposable into measurable sub-criteria. First step is signal decomposition, not acceptance of the qualitative ceiling. Four verifiability tiers: decomposable (~90%) > proxy-measurable (~85%) > judgment-dependent (~80%) > experiential (~60%, human-only).

**False block cost:** Compound false-block rate across N gates = 1-(1-p)^N. Five gates at 5% FP each = 22.6% compound rate, inflating token costs ~49%. Principle: minimize gate count, maximize gate power. Max 2-3 gates in critical path.

**Bead-CUJ linkage:** Six properties for sound links:
1. **Explicit declaration** — bead declares which CUJ signals it affects
2. **Falsifiability** — reverting bead's changes must cause linked gate to fail
3. **Blast radius scoping** — gate set = declared_signals ∩ blast_radius(changed_files)
4. **Gate sensitivity** — mutation testing validates gates catch regressions
5. **Delta attribution** — compare pre/post bead, not just post state
6. **Dependence validity** — changed code must be in backward slice of gate assertion

**Progressive autonomy:** Follows FDA PCCP model — autonomy pre-authorized through specificity (defining what changes are allowed), not earned through elapsed time. Four tiers:
- **Tier 0** (no-effect changes): Fully automated, post-hoc audit. Docs, formatting, comments.
- **Tier 1** (minor changes): Automated with notification. Bug fixes, config.
- **Tier 2** (significant changes): Automated with veto window. New features, API changes.
- **Tier 3** (critical changes): Human-gated with tool assistance. Security, migrations, releases.

**Ratchet mechanism:** Gates monotonically tighten as system matures, never loosen. New coverage only increases.

## Intent Directive Model (Refined)

The principal steers the factory at the **theme level**, not the task level. The factory proposes intent; the principal approves/adjusts.

### Three-Layer Architecture

```
Layer 1: THEMES (principal-steered, factory-proposed)
  Thematic lanes with weights, discovery budgets, time horizons.
  Factory proposes from CUJ health + cost trends + external signals.
  Principal adjusts. Factory learns from adjustments over time.

Layer 2: CUJ HEALTH → PRIORITY (auto-derived)
  CUJ health scores drive bead ordering within each theme.
  Unhealthy CUJs in high-weight themes get priority.

Layer 3: BEADS + DISCOVERY (agent-pulled)
  Agents self-serve: execute beads, run discovery within lane budgets.
  Discovery authority scales with trust tier.
```

### Intent = Research Agenda + Execution Budget + Constraints

The principal's highest-leverage action is pointing the discovery engine at the right questions. Intent isn't just about steering execution — it's about scoping what the factory learns.

- **Themes** bundle CUJs + beads + discovery into coherent streams (maps to `/clavain:lane`)
- **Discovery budget** per theme: how much autonomous research agents can initiate, tiered by trust
- **Time horizons**: "reliability this sprint" vs. "reliability this quarter" drive different discovery depths
- **Reactive signals**: external events (customer reports, production incidents, interject discoveries) can trigger intent proposals from the factory
- **Drop-down overrides**: principal can always issue direct commands ("ship bead X today", "don't touch module Y")

### Factory-Proposed Intent (Key Innovation)

The factory proposes budgets and priorities based on:
- CUJ health trends (declining health = higher weight proposal)
- Cost efficiency data (themes where cost/change is improving = maintain; degrading = investigate)
- External signals (interject discoveries, production metrics)
- Historical principal adjustments (if principal always bumps reliability, learn that preference)

Principal reviews and adjusts. Adjustments become training signal. Over time, the factory's proposals converge with the principal's preferences, and the principal intervenes less.

This is graduated autonomy applied to strategy itself — the "player-coach evolving to principal" arc.

## Open Questions

2. **Trust across model updates:** When Anthropic ships a new model version, do earned authority tiers reset? Partially decay? This is the "regime change" problem from financial forecasting.

3. **Cross-CUJ conflicts:** Two CUJs require contradictory changes to the same module. How does the system detect and escalate this before agents start conflicting?

4. **Signal decomposition process:** Who decomposes qualitative signals into measurable sub-criteria? The principal? An agent? Automated analysis? This is a one-time cost per CUJ but critical for the gating model to work.

5. **Concurrent bead attribution:** When multiple beads' blast radii overlap, signal changes can't be cleanly attributed. Serialize verification (precise but expensive) or flag ambiguity (fast but loose)?

## Research Corpus

**Round 1:** 10 research agents, 5 domains (work decomposition, scheduling, velocity, dashboards, governance + 5 discovery):
- `docs/research/flux-research/ai-factory-work-orchestration-lessons/synthesis.md`
- Specs: `.claude/flux-gen-specs/ai-factory-work-orchestration-research.json`

**Round 2:** 5 research agents on CUJ gating (gate typology, signal verifiability, false block costs, progressive autonomy, bead-CUJ linkage):
- `docs/research/flux-research/cuj-gating-model/synthesis.md`
- Specs: `.claude/flux-gen-specs/cuj-gating-model-research.json`

**Round 3:** 5 research agents on Phase 1 self-dispatch (claiming atomicity, trigger/idle detection, backlog matching, failure recovery, feedback loops):
- `docs/research/flux-research/phase1-self-dispatch/synthesis.md`
- Specs: `.claude/flux-gen-specs/phase1-self-dispatch-research.json`

**Round 4:** 5 research agents on authority tiers (schema design, evidence thresholds, credentialing analogues, multiagent trust, dispatch integration):
- `docs/research/flux-research/authority-tiers/synthesis.md`
- Specs: `.claude/flux-gen-specs/authority-tier-research.json`

**Round 5:** 6 research agents on rework model (manufacturing disposition, CI/CD failures, VFX revision, CUJ integration, cost accounting, authority routing) + 1 on interlab/autoresearch patterns:
- `docs/research/flux-research/rework-model/synthesis.md`
- `docs/research/flux-research/ai-factory-work-orchestration-lessons/interlab-autoresearch-patterns.md`
- Specs: `.claude/flux-gen-specs/rework-model-research.json`
