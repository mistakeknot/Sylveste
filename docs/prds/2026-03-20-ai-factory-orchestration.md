---
artifact_type: prd
bead: Sylveste-ysxe
stage: design
version: 1
---
# PRD: AI Factory Orchestration — From Dispatch Bottleneck to Autonomous Software Factory

## Problem

The principal (user) is the dispatch bottleneck. The backlog is prioritized, the toolchain exists (beads + route.md + flux-drive), but every work assignment requires a human to: tell an agent "go pick up bead X", specify which tools to use, review every output before it lands, and monitor agent state across tmux tabs. At 3-5 agents this is manageable. At 10+ it's unsustainable.

The system knows what to do but can't act without the human issuing each command.

## Solution

A phased evolution from human-dispatched agents to an autonomous software factory where agents self-serve from a CUJ-driven backlog with earned autonomy and machine-verifiable quality gates. Three waves, each a coherent capability increment validated before the next begins.

**Core thesis:** AI factory orchestration is a governance problem, not a PM problem. The question isn't "how do we track work?" (beads solves this) but "how do we delegate authority so agents can act without human dispatch while maintaining quality and cost control?"

**Approach:** Hybrid pull + intent dispatch. Agents pull from prioritized backlog; principal shapes priorities via CUJ-level intent directives. Mycroft monitors and escalates, not assigns.

## Scope

This PRD covers all three waves. Implementation plans will be per-wave. Wave 1 is the immediate priority.

### Wave 1: Foundation (3 weeks) — Self-dispatch + deterministic gates
### Wave 2: Intelligence (3 weeks) — CUJ health scoring + cost-aware routing + authority shadow
### Wave 3: Autonomy (4 weeks) — Authority enforcement + semantic gates + rework disposition

## Features

### F1: Atomic Claim (Wave 1, P0)

**What:** Merge the current two-phase bead claim (bd update --claim + bd set-state) into a single Dolt transaction. Eliminates the race window where two agents can claim the same bead.

**Acceptance criteria:**
- [ ] Single `bd claim <id>` command writes assignee, status, claimed_by, and claimed_at in one Dolt transaction
- [ ] Concurrent claim attempts from different sessions result in exactly one winner
- [ ] `bead_claim()` in lib-sprint.sh and `clavain-cli bead-claim` updated to use new atomic path
- [ ] Backward-compatible: old two-phase callers still work but log deprecation warning
- [ ] Test: 10 parallel claim attempts on same bead, exactly 1 succeeds

### F2: Deterministic Quality Gates (Wave 1, P0)

**What:** Compile + test + lint + type-check as automated pre-commit quality gates. These are the floor — every landed change must pass deterministic checks before any stochastic or human review.

**Acceptance criteria:**
- [ ] Gate runner invoked automatically after execution phase completes
- [ ] Language-detected: Go (go build + go test + golangci-lint), Rust (cargo check + cargo test + cargo clippy), Python (ruff check + pytest), Shell (shellcheck)
- [ ] Gate results recorded as structured verdict (pass/fail per check, duration, output snippet on failure)
- [ ] Failed gate blocks sprint progression — agent must fix before proceeding
- [ ] Zero new infrastructure: uses existing project test commands, orchestrated by clavain-cli

### F3: Self-Dispatch Loop (Wave 1, P1)

**What:** After completing a bead (or on session start with no active work), agents autonomously select and claim the next bead from the backlog using a scoring function.

**Acceptance criteria:**
- [ ] Stop hook trigger with 20-second idle cooldown before dispatch (prevents thrashing)
- [ ] Score-based bead selection: priority (40%), phase alignment (25%), recency (15%), deps-ready (12%), WIP-balance (8%)
- [ ] Atomic claim with jitter (0-5s random delay to reduce collision under concurrent dispatch)
- [ ] Dispatch via existing route.md — self-dispatch reuses the same sprint protocol
- [ ] Agent skips beads outside its capability scope (determined by module/language match)
- [ ] WIP limit: agent holds at most 1 in-progress bead at a time
- [ ] Opt-in per session via `CLAVAIN_SELF_DISPATCH=true` environment variable
- [ ] Telemetry: dispatch events recorded for fleet utilization analysis

### F4: Failure Recovery (Wave 1, P1)

**What:** 4-tier escalation when a bead fails during execution: auto-retry, quarantine, circuit breaker, factory pause.

**Acceptance criteria:**
- [ ] Failure classification: retriable (transient errors, flaky tests), spec_blocked (unclear requirements), env_blocked (missing deps, infra issues)
- [ ] Tier 1 — Auto-retry: up to 3 attempts for retriable failures, with exponential backoff
- [ ] Tier 2 — Quarantine: after max retries, bead moves to `blocked` with failure reason. Agent picks next bead.
- [ ] Tier 3 — Circuit breaker: if 3+ beads quarantine within 30 minutes from same agent, agent pauses self-dispatch and alerts
- [ ] Tier 4 — Factory pause: if circuit breakers trip on 2+ agents within 15 minutes, all self-dispatch pauses and principal is notified
- [ ] All failure events logged with classification, attempt count, and error summary
- [ ] Stale-claim recovery: heartbeat timeout at 45 minutes; unclaimed beads return to backlog

### F5: Fleet Feedback Dashboard (Wave 1, P2)

**What:** Basic observability for the self-dispatching factory. Zero new code — derived from existing beads state and cass analytics.

**Acceptance criteria:**
- [ ] Fleet utilization: agents active / agents total (from tmux sessions + claim state)
- [ ] Queue depth: open beads by priority tier
- [ ] WIP balance: beads in-progress per agent
- [ ] Surfaced via `clavain-cli factory-status` command
- [ ] Data source: beads DB queries + cass timeline, no new telemetry infrastructure

### F6: CUJ Health Scoring (Wave 2)

**What:** CUJ health = (signals passing / total signals), weighted by criticality. Auto-generates beads from signal gaps and friction points. Drives backlog ordering.

**Acceptance criteria:**
- [ ] CUJ docs extended with structured signal definitions (measurable, observable, qualitative)
- [ ] Health score computed per CUJ, updated on bead close
- [ ] Beads auto-generated from: signal gaps (status=planned), friction points, priority by health impact
- [ ] Backlog ordering: CUJ health x theme weight drives bead priority
- [ ] `clavain-cli cuj-health` shows per-CUJ scores

### F7: Cost-Aware Routing (Wave 2)

**What:** Fleet-registry cost profiles drive model selection. Cheap tasks route to cheap models. Budget-blocked work deferred, not forced to expensive models.

**Acceptance criteria:**
- [ ] Route.md model selection consults fleet-registry cost profiles
- [ ] Complexity-based routing: complexity 1-2 beads → Haiku/Sonnet, 3 → Sonnet, 4-5 → Opus
- [ ] Budget gate: if remaining budget < estimated cost, bead deferred with reason
- [ ] Cost per landed change tracked per agent x model combination

### F8: Authority Shadow Mode (Wave 2)

**What:** Log all authority decisions (who would be allowed/denied per domain), block nothing. Builds evidence baseline for Wave 3 enforcement.

**Acceptance criteria:**
- [ ] Authority decision logged on every dispatch: agent, domain, action, would_allow (bool), evidence_count
- [ ] No enforcement — all decisions permissive, shadow log only
- [ ] Dashboard shows would-be denial rate per agent x domain
- [ ] >=80% correct decisions in shadow mode before Wave 3 proceeds

### F9: Authority Enforcement (Wave 3)

**What:** `effective_action = min(fleet_tier, domain_grant)`. Five authority tiers (Propose/Execute/Commit/Deploy/Spend) earned through evidence, lost through incidents.

**Acceptance criteria:**
- [ ] 4 Dolt tables: authority_grants, authority_evidence, authority_tiers, authority_incidents
- [ ] `authority.owners` YAML per module defining domain grants
- [ ] Evidence thresholds: Promote requires 5 obs @80% -> 15 @90% -> 30 @95%; demote fires faster
- [ ] 5 safety invariants enforced (no self-promotion, no cross-domain escalation, etc.)
- [ ] Enforcement active: denied actions blocked with explanation and escalation path

### F10: Rework Disposition (Wave 3)

**What:** Six dispositions (scrap/rework/repair/RTV/downgrade/deviation) replace "reopen ticket." Manufacturing-inspired taxonomy for failed work.

**Acceptance criteria:**
- [ ] Disposition assigned when bead fails quality gates or review
- [ ] Salvage ratio drives scrap-vs-rework: scrap optimal <0.3, rework optimal >0.5
- [ ] Context pollution benefit: scrap gets fresh context window (unique advantage in token systems)
- [ ] Quarantine-to-disposition SLAs prevent limbo (max 4 hours)
- [ ] Wasted tokens (scrap-after-rework) reduced >=30% vs baseline

## Validation Criteria (per wave)

### Wave 1
- >=3 agents self-dispatch for 48 hours without human per-task commands
- Deterministic gates catch >=1 real issue that would have shipped
- Stale-claim recovery triggers <=2 false positives

### Wave 2
- CUJ health scores correlate with user-perceived journey quality (spot-check 5 CUJs)
- Cost per landed change drops >=15% from cost routing
- Authority shadow logs show >=80% of decisions would be correct if enforced

### Wave 3
- 10+ agents operate for 1 week with principal spending <15 min/day on oversight
- Authority enforcement produces <=5% false denials
- Rework disposition reduces wasted tokens by >=30%

## Open Questions

1. **Trust across model updates:** When Anthropic ships a new model version, do earned authority tiers reset? Partially decay?
2. **Cross-CUJ conflicts:** Two CUJs require contradictory changes to the same module — detection and escalation mechanism TBD
3. **Signal decomposition:** Who decomposes qualitative signals into measurable sub-criteria — principal, agent, or automated analysis?
4. **Concurrent bead attribution:** When multiple beads' blast radii overlap, serialize verification or flag ambiguity?

## Research Corpus

5 research rounds, 31 agents total. See brainstorm for full links:
- Round 1: AI factory work orchestration (10 agents, 5 domains)
- Round 2: CUJ gating model (5 agents)
- Round 3: Phase 1 self-dispatch (5 agents)
- Round 4: Authority tiers (5 agents)
- Round 5: Rework model + interlab patterns (6 agents)
