# AI Factory Work Orchestration Lessons from Demarch

**Date:** 2026-03-19
**Status:** Repository research complete
**Scope:** Beads decomposition, routing, fleet coordination, cost-aware scheduling, evidence-based trust

---

## Executive Summary

Demarch implements a **progressive, evidence-based approach to AI agent work orchestration** across 3 nested timescales: per-turn (agent reasoning), per-sprint (phase gates), and cross-session (routing calibration via Interspect). The system models work as durable artifacts (beads) with explicit dependencies, routes to specific agents based on complexity + context, and closes feedback loops through measurement and calibration.

**Key Finding:** The biggest gap between current state and a fully autonomous software factory is **graduated autonomy with earned trust.** Mycroft (fleet orchestrator, v0.1 planned) is the missing piece — it scales human coordination from 3-5 agents to 20+, but only after demonstrating consistent performance through shadow suggestions → approval tracking → automatic demotion on regression.

---

## 1. Work Decomposition via Beads

### Current State

**Beads model hierarchy via epic parent-child relationships:**
- Parent epic = container (e.g., "Implement auth redesign", type=epic, sprint=true)
- Children = atomic work units (type=task/feature/bug/docs/decision)
- First-class dependency support via `bd create --depends-on` or `bd update --link`
- Labels encode metadata without schema migration: `label:complexity/{simple,medium,complex}`, `label:priority/p0-p4`, custom tags

**Decomposition happens in brainstorm phase:**
1. `/clavain:sprint` brainstorm surfaces the problem
2. Strategy phase proposes decomposition into child beads
3. User (or agent with authority) accepts or refines the structure
4. Phase gates enforce prerequisites: plan review before work, design doc before implementation

**No automatic task breakdown:** Demarch doesn't infer subtasks from specs. The human (or a brainstorm agent in future) reads the spec and proposes children. This is intentional — prevents proliferation of meaningless subtasks and keeps humans in the loop where judgment matters.

### Gaps vs. AI Factory Requirements

1. **Dependency granularity:** Beads track blocking (A must complete before B) but not resource contention (A and B access the same file → assign to same agent). Mycroft's interlock plugin partially fills this via file reservation locks.

2. **Automatic dependency inference:** Complex epics lack suggested dependency graphs. Brainstorm should propose "Task X must come before Y because X modifies the public API," but currently this is manual.

3. **Complexity metadata staleness:** Complexity labels don't auto-update after sprint completion. Historical actual vs. estimated complexity is tracked in reflection but not fed back to calibrate future estimates. Interspect's Phase 2 should automate this.

4. **Epic cascade-close:** When a parent epic is closed, children remain open. No automatic status propagation. This is intentional (children might outlive parent), but requires discipline to keep closed.

---

## 2. Routing Architecture (Route → Sprint vs. Work)

### Current State

**Three-layer classification pipeline** (route.md):

**Layer 1: Fast-path heuristics** (terminal conditions, 1.0 confidence)
- Plan exists + phase=plan-reviewed → `/clavain:work` (execute)
- No description + no brainstorm → `/clavain:sprint` (brainstorm)
- Phase gates determine terminal states; complexity ≥4 or child_count>0 → `/clavain:sprint` (think before build)

**Layer 2: Haiku fallback** (LLM classification if no fast-path)
- Given: description, has_plan, has_brainstorm, complexity, type, phase, child_count
- Routes to `/sprint` (ambiguous, research, epic) or `/work` (clear scope, C1-3, executable)
- ~0.85-0.95 confidence

**Layer 3: Post-dispatch** (after routing)
- Claim bead (race-safe via bd compare-and-swap)
- Token attribution (write session ID to interstat for cost tracking)
- Phase advance (if applicable)

**Key insight:** Route is **not just dispatch — it's discovery + analysis + orchestration** in a single command. Starting /route with no args triggers discovery scan, which ranks beads by staleness, tries to batch-check which are already implemented, and presents top 3 recommendations.

### Gaps vs. AI Factory Requirements

1. **No agent-aware routing:** Classification chooses between `/sprint` and `/work`, but doesn't select which agent within a tier. Dispatch to fd-architecture vs. fd-safety is decided by flux-drive's domain detection, not by Clavain's router.

2. **Staleness sweep incomplete:** Discovery checks top 3 beads for `possibly_done` via Haiku batch-check but doesn't re-score discovery rankings per session. The work queue doesn't refresh in real-time as other agents complete beads.

3. **No cost-aware routing:** Route doesn't check remaining budget before dispatching. Budget enforcement happens downstream in flux-drive, but the router doesn't degrade gracefully to cheaper operations when budget is tight.

4. **Sprint resumption assumes single active sprint:** If 3 sprints are active, user must choose. Tie-breaker is recency, but no mechanism to auto-promote a high-priority sprint over a recent one.

---

## 3. Phase Gates & Sprint Lifecycle

### Current State

**Five mandatory phases** (interphase plugin):
1. **Brainstorm** — explore problem space, propose solutions (output: brainstorm doc)
2. **Strategy** — select approach, propose epic decomposition, architecture (output: prd doc)
3. **Plan** — detailed task breakdown, resource estimation (output: plan doc)
4. **Plan-review** — gates against execution; must pass quality + safety + feasibility checks
5. **Work** — implement and test
6. **Quality gates** (post-work) — merge, deploy, monitor

**Evidence-based gates:**
- Policy: gate is "ready" if 2/3 review agents pass (configurable threshold)
- Measurement: post-merge defect rate feeds back to calibrate gate strictness
- Failure handling: human override always available; override logged to interspect for evidence
- Disabled gates tracked in interspect.db; patterns propagate to routing overrides

**Problem framing emphasis:**
- PHILOSOPHY.md: "Review phases are where the leverage is. Most agent tools skip brainstorm, strategy, and specification."
- Hypothesis: spending tokens on **thinking** (brainstorm 80K, strategy 150K) before building (work 300K) reduces rework and improves output quality
- Not yet measured directly; success metrics are post-merge defect rates and sprint velocity

### Gaps vs. AI Factory Requirements

1. **No dynamic phase skipping:** Gate is binary pass/fail; no conditional advancement (e.g., "skip plan-review if complexity ≤2 AND plan > 500 words"). Gates are all-or-nothing.

2. **Human judgment at every gate:** Phase advancement requires human review. Even "clearly ready" cases need human approval. This doesn't scale to 50+ parallel sprints.

3. **No phase-specific budgets:** Budget is per-work-item (brainstorm=80K, plan=150K) but doesn't adjust for epic size or complexity. A simple task and a research epic get the same budget ceilings.

4. **Gate pass rates not automated:** Gates track whether they pass/fail, but don't automatically adjust thresholds. A gate that always passes should be disabled; one that never passes should be re-tuned. Interspect's Phase 3 would automate this.

---

## 4. Critical User Journeys (CUJs)

### Current State

**CUJ Format** (`docs/cujs/`):
- Metadata: artifact_type=cuj, journey name, actor, criticality tier
- Narrative: journey stages, interaction points, state changes
- Success signals: measurable and qualitative assertions

**Wired CUJs:**
- **mycroft-fleet-dispatch** (P1) — user starts `mycroft run`, monitors fleet, approves/rejects dispatch suggestions. Graduated tiers T0→T3 based on track record.

**Partially wired CUJs:**
- Gurgeh spec generation, Coldwine PRD synthesis, Interspect evidence review

**Not yet wired:** Most CUJs are design documents without runtime wiring. No automated routing to CUJ phase handlers. No outcome tracking against CUJ success signals.

### Gaps vs. AI Factory Requirements

1. **No CUJ-specific routing:** Route doesn't ask "what CUJ is this bead part of?" If a bead is part of an epic that's part of a multi-agent journey, route should prefer agents/phases that advance that journey.

2. **Success signals are qualitative:** "Developer never wonders why Mycroft did that" is unmeasurable. No instrumentation captures user confusion, only explicit rejections.

3. **CUJ dependencies are invisible:** If journey A depends on journey B (e.g., "discovery must complete before dispatch"), there's no way to express or enforce this in the bead system. Epic dependencies exist, but CUJ-to-epic mapping is manual.

4. **No journey prioritization:** When two journeys compete for a single agent, no automatic priority. Mycroft does priority-first bead selection but doesn't know about journey-level priorities.

---

## 5. Fleet Registry & Cost-Aware Scheduling

### Current State

**Fleet registry** (os/Clavain/config/fleet-registry.yaml):
- 35+ agents across 5 categories (review, research, cognitive, generated, orchestration)
- Per-agent capabilities, preferred model, supported models, cost profiles
- Tags for filtering (e.g., `language:go`, `domain:backend`)

**Budget enforcement** (interverse/interflux/config/flux-drive/budget.yaml):
- Hardcoded defaults by work type (brainstorm=80K, plan=150K, diff-small=60K)
- Per-agent cold-start estimates (review=40K, research=15K, oracle=80K)
- AgentDropout: dynamic redundancy elimination based on domain coverage + finding density
- Slicing multiplier: 0.5x when document slicing is active

**Cost calibration pipeline** (interstat + estimate-costs.sh):
1. **Collect actuals:** interstat records token spend per agent+model+phase
2. **Enrich registry:** scan-fleet.sh reads interstat and writes calibrated estimates back to fleet-registry.yaml
3. **Estimate future:** estimate-costs.sh reads registry baseline + delta from recent runs, weights them, outputs per-agent budget
4. **Enforce:** flux-drive checks estimate vs. remaining budget, drops low-priority agents if over

**Soft enforcement:** If budget exceeded, warn user + offer override (not auto-fail).

### Gaps vs. AI Factory Requirements

1. **No per-project budget policies:** Budget is global. A project with 10K token budget uses same gate thresholds and agent defaults as one with 500K. No cost-sensitivity signaling to agents.

2. **AgentDropout is heuristic, not outcome-driven:** Redundancy score combines domain convergence (0.4) + finding density (0.2), but these weights aren't calibrated against post-drop outcomes. No measurement of false negatives from dropped agents.

3. **Calibration is sparse:** Enrichment requires ≥3 runs per agent+model. Cold-start projects estimate poorly. No progressive refinement (e.g., use lower confidence in first run, upgrade to calibrated after 3 runs).

4. **No token-budget feedback loop:** If an agent overspends by 50%, flux-drive doesn't adjust future estimates. Runaway spending is only caught retroactively.

---

## 6. Evidence-Based Routing via Interspect

### Current State

**Phase 1 (shipped): Evidence collection**
- SQLite database (.clavain/interspect/interspect.db, WAL mode)
- Captures: review dismissals, gate overrides, manual corrections, finding density, token consumption
- Session lifecycle hooks auto-index events
- Reporting commands summarize patterns

**Phase 2 (partially shipped): Routing overrides**
- F1: Pattern detection (count-rule thresholds: ≥3 sessions, ≥2 projects, ≥N events)
- F2: Propose overlay (display summary of evidence + proposed change)
- F3: Apply with canary (commit overlay to git, monitor metrics across 20-use window)
- F4: Status display (show which overlays are active, degrading, stale)
- F5: Manual revert (user can disable overlay, no questions)
- Canary metrics: override rate, false positive rate, finding density (three cross-checks)

**Phase 3 (designed, not shipped): Autonomy + evaluation**
- Counterfactual shadow evaluation (run candidate changes on real traffic before auto-apply)
- Privilege separation (proposer can't write to repo; only allowlisted applier can)
- Eval corpus requirement (don't tune prompts without real evidence)

### Gaps vs. AI Factory Requirements

1. **Evidence gaps:** Interspect sees dismissals, overrides, and token spend, but doesn't see upstream signals (agent state, git history, code quality). No way to correlate "agent A was confused by legacy code style" with "override this agent on legacy-style files."

2. **Limited signal types:** Only 8 signal types captured. Missing: agent confusion (did it loop? did it backtrack?), context loss (did it forget prior constraints?), hallucinations (did it invent APIs?).

3. **No learning from success:** Interspect tracks failures and dismissals but not positive evidence. When an agent nails a task, that's as important as when it fails, but there's no mechanism to amplify it.

4. **Proposal stasis:** Evidence collection (Phase 1) ships, routing overrides (Phase 2 F1-F5) ship, but Phase 2 context overlays (feature flags for agent prompts) don't ship. This means tuning is delayed pending evaluation infra.

---

## 7. Multi-Agent Coordination via Mycroft (Planned)

### Current State

**Mycroft v0.1 planned (not shipped):**
- Fleet monitor (patrol loop reading intermux, beads, interlock every 30-60s)
- T0 observe: shadow suggestions logged but no action
- T1 suggest: numbered suggestions, user approves/rejects each
- Failure detection: classify agent state (clean, dirty, degraded, corrupted, healthy)
- Dispatch execution: claim bead → write metadata → spawn tmux session
- Automatic demotion: >25% failure rate or 3 consecutive failures → demote

**Tier architecture (earned, not granted):**
- **T0**: Observe only, emit shadow suggestions
- **T1**: Suggest, require user approval for each dispatch
- **T2**: Auto-dispatch P3-P4 tasks (type/priority/complexity allowlist)
- **T3**: Full autonomy, budget-gated

**Key design choice:** Graduated autonomy via track record, not capability. Mycroft doesn't earn T1 through code review; it earns it by demonstrating >90% approval rate on ≥20 dispatches at T0.

**Circuits and guards:**
- 20-sample minimum before evaluating graduation criteria (prevents small-sample artifacts)
- Symmetric rolling-window circuit breaker (T3→T2 at >25% failure, T2→T1 at >15%, both demote equally aggressively)
- Dual-source verification: Mycroft's dispatch_log must agree with git history + bead state
- Interspect gate prevents auto-promotion in feedback loop

### Gaps vs. AI Factory Requirements

1. **No recursive decomposition:** Mycroft assigns work to agents, but doesn't handle agent-to-subagent dispatch. If an agent needs to spawn sub-agents for parallelization, Mycroft doesn't help.

2. **No conflict resolution:** Interlock reserves files, but when conflicts occur, Mycroft escalates to user. No automatic rescheduling or conflict negotiation between agents.

3. **No resource discovery:** Mycroft routes by bead priority and agent capability, but doesn't discover new agents or capability improvements. Fleet is static in v0.1.

4. **No cross-project coordination:** Mycroft monitors one project. Multi-project work (where a change to commons breaks downstream projects) has no orchestration.

---

## 8. Architectural Principles

### Receipts Close Loops (Evidence → Authority → Action → Evidence)

**Flywheel (OODARC: Observe → Orient → Decide → Act → Reflect → Compound):**

- **Per-turn:** Agent observes tool output, decides next action, reflects on outcome, updates working memory
- **Per-sprint:** Phase gates observe artifacts (brainstorm, plan, review results), decide advancement, reflect at phase end
- **Cross-session:** Interspect observes evidence, proposes overrides, Mycroft decides dispatch authority, evidence feeds back

**Key lesson:** Reflect without Compound is journaling (write-only). Compound without Reflect is cargo-cult (copying without understanding). **Both required.**

Implementation: 4-stage pattern (hardcoded defaults → collect actuals → calibrate from history → fallback to defaults) applied everywhere predictions exist (cost estimation, routing, complexity scoring, gate thresholds).

### Composition Over Capability

**Small, scoped plugins (53 in Interverse) beat monolithic generalists.**

- Each plugin does one thing well
- Plugin ecosystem declares capabilities; platform composes them
- Plugins fail open, degrade gracefully without dependencies (except kernel-native ones)
- External tool adoption preferred over rebuilding (beads is external, not reimplemented)

**Current framing:**
- **Standalone plugins** (default): no hard kernel dependency. Examples: interlens, interlock, interkasten, tldr-swinton
- **Kernel-native plugins** (rare): extend kernel subsystems (discovery, events, dispatch). Examples: interject, interspect, interphase

**Implications for work orchestration:** Demarch is composable — Mycroft + Interspect + Clavain routing are independent pieces that cooperate via beads state and events, not monolithic.

---

## 9. Critical Gaps: Current vs. Fully Autonomous Factory

### Gap 1: Dynamic, Adaptive Routing

**Current state:** Route chooses between `/sprint` and `/work` (2 buckets). Agent selection happens downstream in flux-drive (domain + capability match).

**Missing:** Cost-aware routing that degrades gracefully when budget is tight. If we have 50K tokens left and need to review a large diff (normal estimate 200K), route should offer:
- Tier down to cheaper model (Haiku instead of Opus)
- Slice the diff to review in parts
- Skip non-critical agents (drop fd-game-design if budget-critical)
- Escalate to user if all options exhausted

**Current workaround:** Flux-drive's AgentDropout handles some of this, but it's static per-run, not adaptive per-decision.

### Gap 2: Graduated Autonomy Without Earned Trust

**Current state:** Humans approve at every phase gate (L1 autonomy). L2-L5 require Interspect + Mycroft, both unshipped or partial.

**Missing:** Mechanism to earn higher autonomy in **specific domains**. An agent might be 100% trusted on documentation but 60% on security. Route should route doc changes to that agent autonomously but escalate security changes to human review.

**Current workaround:** Manual routing overrides in fleet registry, but no automatic learning from outcomes.

### Gap 3: Work Discovery at Scale

**Current state:** Discovery scan checks top 3-5 beads via Haiku, re-runs if stale >1hr. Works for 20-50 beads, breaks at 200+.

**Missing:** Learned ranking that improves with session data. What makes a good next bead? Not just priority (could be P4 but unblocked), but:
- Agent capability match (agent A is 90% accurate on this type)
- Dependency readiness (all blockers resolved)
- Context continuity (bead is adjacent to previous work)
- Cost efficiency (quick wins to build momentum before hard tasks)

**Current workaround:** Priority + age tiebreaker works OK empirically, but isn't evidence-based.

### Gap 4: Failure Recovery Automation

**Current state:** Mycroft detects failures (stuck agents, corrupted git state, stale claims) and escalates to user. User fixes the root cause and re-assigns.

**Missing:** Automatic recovery playbooks. "Agent A git state is corrupted; attempt git reset --hard, retry dispatch if successful." "Agent B claim is stale >45min; reassign to Agent C."

**Current workaround:** User detects via Mycroft status and runs recovery commands manually.

### Gap 5: Cross-Epic Work Coordination

**Current state:** Epics are independent. No mechanism for "Epic A must complete before Epic B" or "Epic A and Epic B must run in parallel and synchronize at checkpoints."

**Missing:** Epic-level dependencies and synchronization primitives. A refactor epic that touches 5 files should coordinate with dependent feature epics to avoid conflicts.

**Current workaround:** Manual coordination via Mycroft (human tracks conflicts) + interlock (file reservations prevent silent conflicts).

### Gap 6: Cost Transparency & Budget Negotiation

**Current state:** Budget is fixed per work type (brainstorm=80K). If estimated cost is 80K and actual is 120K, flux-drive warns but allows override.

**Missing:** Negotiated budget decisions. "This brainstorm needs 150K because the problem is unfamiliar. Offer user the choice: extend budget, or skip brainstorm and go straight to plan?"

**Current workaround:** Hard limit + override friction is acceptable today; will break at higher autonomy.

---

## 10. Synthesis: The Missing Infrastructure Layer

**Current stack (3 layers):**
- **L1 (kernel):** Intercore — state, runs, gates, evidence
- **L2 (OS):** Clavain, Skaffen — agents, orchestration, skills
- **L3 (apps):** Autarch, Intercom — user interfaces, workflow

**Missing horizontal layer (call it Oryx for now):**
- **Work Dispatch Engine:** Adaptive routing (cost-aware, domain-aware, agent-aware)
- **Autonomy Ledger:** Per-agent, per-domain trust scores with outcome-based updates
- **Failure Recovery:** Automatic playbooks with privilege separation (detect → plan → escalate/execute)
- **Cost Negotiation:** Budget vs. outcome tradeoff UI
- **Progress Visualization:** Real-time fleet state, bead dependency graph, critical path

This layer would sit between L1 and L2: above the kernel (needs its state + events) but below agents (agents don't call it, they obey its decisions via env vars + context).

---

## 11. Lessons for Flux-Drive Design

### From route.md
- **Heuristics + LLM fallback is robust.** Fast-path heuristics handle 80% of cases (plan exists → execute) with 1.0 confidence. LLM fallback is cheap (Haiku) and has lower bar (0.85 confidence). Combined: faster and more accurate than LLM-only.
- **Terminal conditions matter.** Rows 1-4 of the routing table are semantically significant (1.0 confidence). Row order can't be reordered without affecting semantics. Make this explicit in code comments.
- **Staleness sweep is cheap, valuable.** Discovery's background Haiku check (top 3 beads, 5s max wait) catches "already implemented" cases that would otherwise appear as work.

### From Mycroft brainstorm
- **Tier graduation needs dual-source verification.** Mycroft's track record (dispatch_log) plus independent signal (git commits, closed beads) ensures no self-grading.
- **Minimum sample size prevents artifacts.** 20 successful dispatches before evaluating >90% approval criteria catches early flukes.
- **Symmetric circuit breaker is safety.** T3→T2 and T2→T1 use same aggressive thresholds (25% and 15%), so demotion is as fast as promotion. This prevents slow degradation.
- **Shadow suggestions are low-friction feedback.** T0 suggests without acting. User can compare suggestions to their own decisions without committing to Mycroft. Evidence of good judgment accumulates naturally.

### From Interspect vision
- **Observe before acting.** Phase 1 (evidence collection) ships value (observability, debugging) before Phase 2 (overlays). Don't skip to modifications without proof the observations are useful.
- **Overlays, not rewrites.** Context overlays layer onto agent prompts via feature flags. Instant rollback. Better than editing canonical prompts.
- **Canary thresholds are conservative.** Three metrics (override rate, false positive rate, finding density) cross-check each other. Degradation must be clear before alert fires.

### From lib-sprint.sh
- **Fail-safe is the pattern.** Sprint operations return 0 on error (never block workflow). Except sprint_claim(), which returns 1 on conflict (caller handles). Everything else degrades gracefully.
- **Cache run IDs locally.** Resolving bead_id → ic_run_id happens once per sprint, result cached in `_SPRINT_RUN_ID_CACHE`. Saves subprocess overhead.
- **Guard nil maps before writing.** YAML unmarshal leaves maps nil when key absent. Always check before assignment.

---

## 12. Recommended Next Steps for AI Factory

### Short-term (4-8 weeks)

1. **Wire Mycroft v0.1 fully.**
   - Complete Steps 1-10 of the implementation plan
   - T0 + T1 operational (observe + approve model)
   - Integration test end-to-end patrol → detect → select → dispatch

2. **Add complexity auto-calibration to Interspect Phase 2.**
   - Capture actual complexity (sprint duration, tokens used) at sprint end
   - Propose complexity label updates to child beads
   - Feed back to improve `/route` heuristics

3. **Implement work discovery ranking improvement.**
   - Track what the user actually chose vs. what discovery recommended
   - Build a simple ranking model (priority, age, capability match)
   - Compare against current priority-first heuristic

### Medium-term (3-4 months)

4. **Build the Oryx layer** (work dispatch + autonomy ledger).
   - Cost-aware routing: when budget tight, offer tier-down / slice / agent-drop
   - Per-agent, per-domain trust scores with outcome feeds
   - Budget negotiation UI: show estimated cost, ask for confirmation or tradeoff
   - Progress visualization: fleet state + dependency graph

5. **Expand Interspect Phase 2** (context overlays + full canary monitoring).
   - Feature-flag overlays for agent context
   - Multi-metric canary with degradation alerting (not auto-revert)
   - Approval flow for proposed overlays

6. **Implement failure recovery playbooks.**
   - Detect patterns: git corruption, stale claims, infinite loops
   - Propose recovery (git reset, reassign, timeout)
   - Escalate if recovery fails
   - Measure: success rate of auto-recovery vs. manual user intervention

### Long-term (6-12 months)

7. **Interspect Phase 3:** Autonomy with shadow evaluation.
   - Counterfactual testing (run candidate changes on real traffic)
   - Privilege separation (proposer can't write)
   - Eval corpus for prompt tuning
   - Auto-promotion gated by shadow eval passes

8. **Multi-project coordination** (beyond single-project Mycroft v0.1).
   - Cross-project dependency tracking (change to commons breaks downstream)
   - Dispatch coordination between agents in different projects
   - Unified progress tracking across fleet

---

## Appendix: Key Files & Locations

| Category | Path | Key Insight |
|----------|------|-------------|
| **Routing** | `os/Clavain/commands/route.md` | 4-stage pipeline: fast-path heuristics → Haiku fallback → dispatch → phase advance |
| **Beads & Discovery** | `os/Clavain/hooks/lib-discovery.sh`, `lib-sprint.sh` | Epic parent-child hierarchy; discovery ranks by staleness + possibly_done sweep |
| **Fleet & Budget** | `os/Clavain/config/fleet-registry.yaml`, `interverse/interflux/config/flux-drive/budget.yaml` | 35+ agents with capabilities; hardcoded defaults + calibration from interstat |
| **Interspect** | `docs/interspect-vision.md`, `core/intercore/docs/product/interspect-vision.md` | Evidence collection shipped; routing overrides partial; autonomy phase planned |
| **Mycroft (v0.1)** | `docs/plans/2026-03-12-mycroft-fleet-orchestrator-v01.md`, `docs/cujs/mycroft-fleet-dispatch.md` | Fleet monitor, T0/T1 tiers, graduated autonomy via track record |
| **CUJs** | `docs/cujs/mycroft-fleet-dispatch.md`, `docs/cujs/gurgeh-prd-generation.md` | Customer journeys define success; not yet auto-routed into phase handlers |
| **Compose** | `os/Clavain/cmd/clavain-cli/compose.go`, `os/Clavain/scripts/lib-compose.sh` | Dispatch plan generation: matches agency spec roles to fleet capabilities + safety floors |
| **Philosophy** | `PHILOSOPHY.md` | 3 principles: evidence closes loops, authority is earned, composition over capability |

---

<!-- flux-research:complete -->
