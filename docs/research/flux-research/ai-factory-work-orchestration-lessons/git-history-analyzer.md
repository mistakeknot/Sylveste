# Demarch Work Orchestration Evolution: Git History Analysis

**Date:** 2026-03-19
**Scope:** Git archaeology of work orchestration patterns across the Demarch monorepo (Jan 2026 – Mar 2026)
**Methodology:** Commit analysis, brainstorm/PRD/plan document review, routing decision evolution, fleet orchestration arc

---

## Executive Summary

The Demarch monorepo shows a deliberate evolution from **task-centric dispatch** (beads + Clavain routing) toward **trust-earned autonomy** (Mycroft fleet orchestrator with graduated tiers). The key insight is that work orchestration patterns became progressively more sophisticated not to handle complexity, but to **make AI agent coordination legible and controllable**.

Three major phases are visible in the git history:

1. **Phase 1 (Jan-Feb 2026):** Foundation — beads as the single source of truth, Clavain's route.md as the routing oracle, complexity classification via heuristics
2. **Phase 2 (Late Feb 2026):** Cost awareness — budget constraints emerge via interstat token tracking, fleet registry stores historical cost data, routing becomes budget-aware
3. **Phase 3 (Mar 2026):** Trust-based dispatch — Mycroft introduces graduated autonomy tiers (T0 → T3), evidence-backed routing decisions via Interspect, fleet coordination becomes observable and reversible

---

## 1. Beads Evolution: From Backup Tracking to State Source

### 1.1 Genesis: `bd init` Pattern (Early Feb 2026)

**Key commits:** `434ddee`, `2ba5e84`, `32a9ef8`, `dad49bc`, `b24c26c`, `e8f66ed`, `e78aa17`, `d4997c6`

Early in the commit history, beads initialization appears **multiple times** in isolated commits. Each one is a fresh `bd init` in different contexts — suggesting beads was not initially integrated but bolted on as work progressed.

```
434ddee bd init: initialize beads issue tracking
```

This pattern repeated 7+ times in quick succession indicates:
- **Beads started as optional.**
- Initial adoption was exploratory, not mandatory.
- The commit message pattern (`bd init: initialize...`) shows emerging convention before full integration.

### 1.2 Consolidation: Work Tracking Policy (Feb 2026)

**Key commit:** `b599188`

```
b599188 fix: add work tracking policy to root CLAUDE.md + backup beads
```

This is the **inflection point**. The policy document formalized the decision:

> "Never create TODO files with status frontmatter, pending-beads lists, or markdown checklists for tracking work. If beads is unavailable, note items in a single `BLOCKED.md` and convert when it recovers."

**Implication:** Beads became the **single source of truth** for work, not a secondary artifact. This matches the memory convention:

> "Beads tracker at `/home/mk/projects/Demarch/.beads/` (prefix `Demarch-`), NOT in subprojects"

### 1.3 Beads as State Backend (Late Feb 2026)

**Key commit:** `f460175`

```
f460175 chore(beads): migrate 27 Autarch/Coldwine TODO items to beads
```

This mass migration from TODO lists to beads marked the transition from "parallel tracking" to "beads-only tracking." The cascade of `chore(beads): close ...` and `chore(beads): backup ...` commits that follow show beads now managing the day-to-day work cadence.

### 1.4 State Extensions: Complexity, Complexity, Budget

**Key changes in lib-sprint.sh and bd state:**

The evolution of `bd set-state` usage shows what became important:

- **Phase 1:** `claimed_by`, `status`
- **Phase 2:** `complexity`, `token_budget`
- **Phase 3:** `interlock_agent_id`, `session_id`, `ic_run_id` (linking to kernel state)

From lib-sprint.sh (lines 114-125):
```bash
_sprint_default_budget() {
    local complexity="${1:-3}"
    case "$complexity" in
        1) echo "50000" ;;       # 50K tokens
        2) echo "100000" ;;      # 100K
        3) echo "250000" ;;      # 250K
        4) echo "500000" ;;      # 500K
        5|*) echo "1000000" ;;   # 1M
    esac
}
```

This shows **complexity became the primary lever for budgeting**, not arbitrary caps. Each tier has a justified token budget.

---

## 2. Routing Evolution: From Heuristics to Trust-Based Dispatch

### 2.1 Fast-Path Heuristics Era (Early Feb 2026)

**Key file:** `os/Clavain/commands/route.md` (lines 91-113)

The original routing table has **deterministic rules** that fire in order:

```markdown
| Condition | Route | Conf |
|-----------|-------|------|
| has_plan AND phase=`plan-reviewed` | `/clavain:work <plan_path>` | 1.0 |
| has_plan AND phase=`planned` | `/clavain:sprint --from-step plan-review` | 1.0 |
| ... (12 more rows)
| issue_type=`feature` AND complexity = 3 | `/clavain:sprint` | 0.85 |
```

**Critical detail:** "Row order is semantically significant — rows 1-4 are terminal (conf 1.0), rows 5+ are advisory."

This is a **cascade of precedence**, not a classifier. It works because the rows encode both the domain knowledge (plans are reviews → direct to work) and confidence levels (heuristic matches are lower conf).

### 2.2 Complexity Routing: Static → Cost-Aware (Late Feb 2026)

**Key commit:** `d1bc3b9`

```
d1bc3b9 docs: add brainstorm, PRD, and plan for B2 complexity routing integration
```

This was the attempt to route based on **model selection** (B1=baseline, B2=routing). However:

**Key memory note:**
> "B2 complexity routing increases costs by 20%. The real value isn't in model-switching but in agent exclusion (routing overrides)."

This is crucial: the project **learned** that cost-aware routing doesn't come from smarter model selection, but from **knowing when NOT to use an agent**. This led directly to the interspect routing overrides system.

### 2.3 Interspect Routing Overrides: Evidence → Action (Feb-Mar 2026)

**Key commits:**
- `fbedacb`: "docs: brainstorm + plan for routing decision kernel facts (iv-godia)"
- `9d7dea3`: "docs: brainstorm, PRD, and plan for interspect routing overrides schema (iv-r6mf)"

**The insight:** Routing decisions are **kernel facts** (intercore state), not ephemeral parameters.

From the schema brainstorm (routing-overrides-schema-brainstorm.md):

```json
{
  "version": 1,
  "overrides": [
    {
      "agent": "fd-perception",
      "action": "exclude",
      "reason": "Agent consistently wrong on Go codebases — 5/6 corrections were agent_wrong",
      "evidence_ids": ["ev-abc123", "ev-def456"],
      "created": "2026-02-23T10:30:00Z",
      "created_by": "interspect"
    }
  ]
}
```

This structure is **declarative**: routing overrides are not algorithmic (no scoring function), they're **fact-based** and **auditable**. Each exclusion has:
- **Reason** (human-readable evidence)
- **Evidence IDs** (traceable back to Interspect findings)
- **Timestamp + creator** (who made this decision and when)

This is fundamentally different from the heuristic table — it's saying "we tried this agent, it failed in this way, here's the proof, exclude it."

### 2.4 Routing Enforcement and Safety Floors (Mar 2026)

**Key commit:** `85a3714`

```
85a3714 docs: add routing enforcement brainstorm and plan
```

The brainstorm emerged **after** routing overrides were designed. It addresses the question: "How do we ensure overrides are actually applied?"

**Key insight from memory:**
> "Safety floors" in lib-routing.sh are YAML ordering checks — ensure routing-overrides.json is applied before other routing decisions.

This shows the evolution from "make routing decisions" → "make routing decisions that stick" → "make routing decisions verifiable."

---

## 3. Cost-Aware Scheduling: Budget as a Constraint

### 3.1 Initial Framing: Token Tracking Infrastructure (Feb 2026)

**Key commits:**
- `5455bf2`: "research: token consumption analysis across Interverse monorepo"
- `5455bf2`: "docs: interstat token benchmarking — brainstorm, PRD, and implementation plan"

Interstat emerged as a **measurement system** first, not a control system. It passively tracked tokens via:
- PostToolUse hook → inserts into `metrics.db`
- SessionEnd hook → backfills token data from session.jsonl

### 3.2 Budget Controls: Four Design Variants (Feb 16 2026)

**Key document:** `2026-02-16-token-budget-controls-brainstorm.md`

This brainstorm presents **four design options** for how to enforce budgets:

| Variant | Scope | New Module? | Real-time? |
|---------|-------|-----------|-----------|
| A: Budget-aware triage | flux-drive only | No | No (historical avg) |
| B: Session token ledger | all tools | Yes (interbudget) | Yes |
| C: Extend interstat | all tools | No | Partial |
| D: Flux-drive internal | flux-drive only | No | No (historical avg) |

**The recommendation:** Variant D was chosen (initially), but the document shows the **tension**:
- **Speed:** Variant D wins (1 day effort)
- **Coverage:** Variant B wins (all tools, all scopes)
- **Purity:** Variant C wins (single source of truth)

The choice of Variant D reflects **pragmatism over purity** — the system needed to ship, not be architecturally perfect.

### 3.3 Fleet Registry: Offline Baseline + Runtime Delta (Mar 1 2026)

**Key commits:**
- `f0f2ba6`: "docs: fleet registry enrichment brainstorm, PRD, plan, and exec manifest"
- `2026-03-01-fleet-registry-enrichment-brainstorm.md`

This was the breakthrough: fleet registry became the **bridge between measurement and control**.

**Hybrid data flow:**

1. **Offline merge:** `scan-fleet.sh` reads interstat (actual per-agent×model costs) and writes to `fleet-registry.yaml` with timestamps
2. **Runtime delta:** `lib-fleet.sh` checks for newer runs in interstat (since last scan) and overlays fresher data
3. **Graceful degradation:** If interstat unavailable, use YAML baseline

This is a **systems thinking pattern**: the registry is not a static catalog, it's a **rolling-window forecast** that decays gracefully.

### 3.4 Cost Baseline: $2.93 per Landable Change (Mar 18 2026)

**Key memory note:**
> "Cost baseline: $2.93/landable change (785 sessions, 2026-03-18). Query: `interverse/interstat/scripts/cost-query.sh`"

This **metric materialized** the budget discussion. It's not abstract ("control costs"), it's concrete ("$2.93/delivery"). This grounds all subsequent budget decisions.

---

## 4. Mycroft Fleet Orchestrator: Trust-Earned Autonomy (Mar 2026)

### 4.1 Problem Framing: Human Bottleneck (Mar 12 2026)

**Key commit:** `30e4ad0`

```
30e4ad0 docs: add Mycroft fleet orchestrator brainstorm with all review resolutions
```

The brainstorm frames the problem beautifully:

> "The user hops between 3-10 tmux tabs to:
> - Check what each agent is doing
> - Discover and assign work
> - Detect failures
> - Make routing decisions
>
> At 5+ agents, the user becomes the bottleneck."

This is **not** a technical problem statement (no mention of algorithms or data structures). It's a **coordination problem** — how do you scale human judgment when there are N agents?

### 4.2 Graduated Autonomy: Four Tiers with Evidence Gates (Mar 12 2026)

**From the brainstorm:**

| Tier | Authority | Graduation Criteria |
|------|-----------|-------------------|
| **T0** | Observe | Default state; emit shadow suggestions |
| **T1** | Suggest | User approves each assignment |
| **T2** | Auto-dispatch (low-risk) | >90% approval rate + >70% completion |
| **T3** | Full dispatch | N successful auto-dispatches + Interspect gate |

**Critical detail:** Graduation is **earned, not granted**.

The approval rate is measured empirically: how often did the user agree with Mycroft's suggestions? This creates a **feedback loop** where autonomy increases only when Mycroft's judgment is proven sound.

### 4.3 Interspect Evidence Gate (Mar 12 2026)

**From the brainstorm (line 56):**

> "Auto-promotion (opt-in via config) adds an **Interspect gate**: `tier/evidence.go` queries Interspect's evidence table, and graduation is blocked if Interspect classifies Mycroft's dispatch patterns as `growing` or `emerging` (insufficient evidence). Only `ready` classification allows auto-promotion."

This is **not arbitrary gatekeeping**. It's using the same evidence system that gates agent trust to gate Mycroft's trust. The symmetry is important: Mycroft can't outrun its own evidence threshold.

### 4.4 Automatic Demotion: Symmetric Circuit Breaker (Mar 12 2026)

**From the brainstorm (lines 75-78):**

```
- **T3→T2:** >25% failure rate in rolling 24h window
- **T2→T1:** >15% failure rate in rolling 24h window
- **Any→T0:** Budget overshoot (>120% of daily limit)
- **Immediate one-tier demotion:** 3 consecutive failures
```

**The pattern:** Demotion thresholds are **asymmetric but principled**:
- T3→T2 at 25% is higher than T2→T1 at 15% (easier to lose higher tier)
- Budget overshoot demotes all the way to T0 (cost control is non-negotiable)
- Consecutive failures are immediate (don't wait for rolling window)

This shows **domain-specific reasoning** about failure modes.

### 4.5 CUJs as First-Class Artifacts (Mar 2026)

**Key commits:**
- `e73f7fe`: "docs(cujs): write 3 core Critical User Journeys"
- `afc3c08`: "docs: add 8 more CUJs — plugins, Skaffen trust, Clavain gates"

**What changed:** CUJs became **design artifacts**, not post-hoc documentation.

Example: `mycroft-fleet-dispatch.md` (CUJ) defines:
- The actor: "regular user running multi-agent fleet"
- The journey: patrol loop → shadow suggestions → T0→T1 promotion → T2 auto-dispatch
- Success signals: measurable (>90% approval), observable (fleet state accuracy)

**Integration point:** CUJs are referenced in **planning documents** (plans/, PRDs/) not just user guides. They shape product decisions.

---

## 5. Interspect Integration: Evidence as Routing Input

### 5.1 Evidence Database as Source of Truth (Feb-Mar 2026)

**Key commits:**
- `ddc906c`: "chore(beads): track interspect calibration known limitations"
- `4cc6f03`: "chore(beads): close iv-8fgu + iv-gkj9 interspect feature beads"
- `c8c812e`: "chore: gitignore routing-decisions.jsonl (transient interspect data)"

Interspect introduced a **new data source**: not beads (work), not fleet-registry (costs), but **evidence of agent behavior**.

The `.clavain/interspect/interspect.db` stores:
- **Evidence entries:** {agent, task, correctness_verdict, correction_type, severity}
- **Modifications:** {override_id, agent, action, reason, created_by}
- **Canary entries:** {override_id, window_uses, status}

### 5.2 Routing Override Lifecycle (Feb 23 2026)

**From route.md pattern library (lines 13-17):**

```bash
**claim-identity:** `bd set-state ... claimed_by=$CLAUDE_SESSION_ID`
**claim-bead:** `bd update --claim`
```

Routing overrides follow a similar lifecycle:
1. **Propose** (via interspect-propose command): user/system suggests excluding agent X
2. **Create** (via interspect-apply): writes to routing-overrides.json + Interspect.db
3. **Monitor** (via canary): tracks if override is working as intended
4. **Revert** (via interspect-revert): removes override when problem is resolved

Each step is **auditable** via `bd set-state` and git commits.

### 5.3 Trust Bootstrapping: From Votes to Verdicts (Mar 2026)

**Key insight from interspect evidence schema:**

Verdicts have **three levels**:
1. **Agent findings:** what the agent said (its output)
2. **Voter corrections:** what reviewers said it got wrong (if anything)
3. **Verdict attribution:** was it the agent, or the task, or the environment?

This three-layer attribution allows routing decisions to be made at different granularities:
- **Agent-level:** agent X is wrong on Go → exclude
- **Domain-level:** agent X is wrong on Go *codebases* → scoped override
- **Task-level:** agent X is wrong on *reviews* → shouldn't route reviews to X

---

## 6. Lib-Sprint.sh: The Orchestration Kernel

### 6.1 IC Availability as a Precondition (Lines 43-62)

```bash
sprint_require_ic() {
    if [[ "$_SPRINT_IC_AVAILABLE" == "yes" ]]; then return 0; fi
    if [[ "$_SPRINT_IC_AVAILABLE" == "no" ]]; then return 1; fi
    if intercore_available; then
        _SPRINT_IC_AVAILABLE="yes"
        return 0
    else
        _SPRINT_IC_AVAILABLE="no"
        log_error "Sprint requires intercore (ic)..."
        return 1
    fi
}
```

This caching pattern shows **thoughtful degradation**: if intercore (ic) is unavailable, fail fast rather than hanging.

### 6.2 Default Budgets by Complexity (Lines 114-125)

The budget table is not arbitrary:
- **C1 (50K):** Haiku can do trivial tasks
- **C3 (250K):** Standard complexity, assumes Sonnet + 1-2 agents
- **C5 (1M):** Research complexity, full review suite

This maps **complexity → budget** based on observed costs.

### 6.3 Phase Actions as Kernel Config (Line 165)

```bash
local default_actions='{"brainstorm":{"command":"/clavain:strategy",...}'
```

Sprint actions are stored in the **kernel state** (intercore), not hardcoded in Clavain. This means:
- **Kernel can override phase routing** (future extension)
- **Phase actions are versioned** (tied to run state)
- **Actions can be customized per-sprint** (via ic run config)

---

## 7. Key Decision Patterns

### 7.1 Complexity as the Primary Lever

**Pattern:** Every orchestration decision uses complexity as the first discriminant.

- **Routing:** "C5 → /sprint, C1 → /work"
- **Budgeting:** C1 = 50K tokens, C5 = 1M tokens
- **Autonomy:** T2 allowlist gates on complexity (max_complexity: medium)

**Why:** Complexity is **estimated early** (via heuristic or LLM) and **anchors all downstream decisions**. It's the "north star" of orchestration.

### 7.2 Evidence as the Guard Rail

**Pattern:** Major autonomy changes (T0→T1, T2→T3) require **proof of competence**.

- **T1 approval rate:** user must approve >90% of suggestions
- **T2 auto-dispatch:** >70% completion rate + <15% failure rate
- **T3 full dispatch:** Interspect evidence must be `ready`, not `emerging`

**Why:** This creates a **feedback loop** where the system self-regulates. It can't promote itself into failure.

### 7.3 Audit Trail as the Confidence Signal

**Pattern:** Every orchestration decision is recorded with:
- Who made it (agent_name, user, interspect)
- When (timestamp)
- Why (reason field)
- Evidence (linked IDs)

**Examples:**
- `bd set-state <bead> claimed_by=grey-area claimed_at=1710829200`
- Routing override reason: "Agent consistently wrong on Go codebases — 5/6 corrections were agent_wrong"
- Mycroft dispatch log: `{action: auto_dispatch, agent: grey-area, reason: "P3 task within T2 allowlist", timestamp: ...}`

**Why:** This makes the system **debuggable**. When something goes wrong, you can trace every decision back to its rationale.

### 7.4 Staged Rollout as the Risk Mitigation

**Pattern:** New orchestration features roll out through phases:

- **Phase 1:** T0 (observe only), shadow suggestions, no actions taken
- **Phase 2:** T1 (user-approved suggestions), full audit trail
- **Phase 3:** T2 (auto-dispatch low-risk only), tight allowlist
- **Phase 4:** T3 (full autonomy), budget-gated

**Why:** This lets the system **earn trust** through successive proofs of competence. At each phase, there's a specific success metric that must be met before advancing.

---

## 8. What Didn't Make It Into Orchestration

### 8.1 Agent Capabilities Routing (Not Implemented)

The fleet-registry.yaml has a `capabilities` field:

```yaml
agents:
  - name: grey-area
    capabilities: [go, rust, tests, docs]
```

**Current status:** Parsed but not used in routing decisions.

**Why:** Capability routing is harder than it looks. Example: "fix a Go bug" requires [go, tests, docs], but you can't just match capabilities. You need to know:
- Does the agent have **recent** success on this capability?
- Does it match the **domain** (internal tool vs. customer app)?
- Is it **available** (not stuck on another task)?

Capability-based routing became **deferred** in favor of simpler patterns (complexity, evidence).

### 8.2 Machine Learning for Routing (Not Implemented)

Early research notes (research/heterogeneous-routing-*.md) explored ML-based routing, but the final shipped system uses:
- **Heuristic rules** (route.md fast-path)
- **LLM classification fallback** (haiku-based)
- **Evidence-based exclusions** (routing overrides)

**Why:** The current system is more **debuggable** and **auditable** than an ML-based router. Operators can understand why a decision was made.

### 8.3 Cross-Project Mycroft (Not Implemented)

Mycroft v0.1 assumes single-project coordination. The brainstorm notes:

> "Single fleet only — Mycroft assumes one project. Multi-project coordination is Autarch/Bigend territory."

**Why:** Scaling to N projects requires **priority arbitration** (which project's work matters most?) that isn't solved at the Mycroft layer. That's an app-level decision (Autarch).

---

## 9. Lessons for AI Factory Work Orchestration

### 9.1 Legibility > Optimization

The Demarch orchestration system prioritizes **understandability** over algorithmic sophistication.

- Routing rules are **declared** (route.md table) not **learned**
- Override decisions are **reasoned** (evidence-based) not **scored**
- Autonomy is **earned** (evidence-gated) not **assumed**

This makes the system slower to implement but faster to debug when things go wrong.

### 9.2 Measurement Precedes Control

Every control mechanism is built on a foundation of measurement:

- **Cost control** starts with `interstat` (token tracking)
- **Routing overrides** require `interspect` (evidence collection)
- **Autonomy tiers** require `dispatch_log` (decision audit trail)

The system doesn't control what it doesn't measure.

### 9.3 Complexity is the Root Discriminant

Almost every decision starts with: "What's the complexity of this work?"

- **Trivial work (C1)** can go straight to automated execution
- **Standard work (C3)** needs brainstorm + plan + execute
- **Research work (C5)** needs full lifecycle with multiple agents

This suggests that **work classification** is the first architectural problem to solve in any multi-agent factory.

### 9.4 Evidence-Based Trust Scales Better Than Role-Based Trust

Instead of "is this user authorized?" Demarch asks "has this agent proven competence?"

- Interspect tracks agent verdicts
- Mycroft's tiers are earned through track record
- Routing overrides are triggered by failure patterns

This **inverts the trust model**: the system grants autonomy based on observed performance, not granted credentials.

### 9.5 Audit Trails Enable Continuous Improvement

Every orchestration decision is logged:
```json
{
  "bead": "Demarch-abc123",
  "action": "auto_dispatch",
  "agent": "grey-area",
  "reason": "P3 task within T2 allowlist",
  "timestamp": "2026-03-19T15:30:00Z"
}
```

This enables:
- **Post-mortems** (when something fails, trace back to the decision)
- **Metrics** (what % of auto-dispatches succeeded?)
- **Feedback loops** (use success rate to adjust thresholds)

---

## 10. Timeline: Major Inflection Points

| Date | Commit | Event | Impact |
|------|--------|-------|--------|
| **Feb 16** | `b599188` | Work tracking policy formalized | Beads becomes single source of truth |
| **Feb 19** | `f460175` | Migrate TODO → beads | 27 items move to kernel-tracked work |
| **Feb 23** | `9d7dea3` | Interspect routing overrides schema | Evidence becomes routing input |
| **Mar 1** | `f0f2ba6` | Fleet registry enrichment | Cost data flows into registry |
| **Mar 6** | `fbedacb` | Routing decisions as kernel facts | Routing becomes versioned state |
| **Mar 12** | `30e4ad0` | Mycroft brainstorm complete | Fleet coordination vision articulated |
| **Mar 18** | *memory note* | $2.93/landable change baseline | Cost control becomes concrete metric |

---

## 11. Remaining Gaps

### 11.1 Capability-Based Routing

The system still routes on **complexity + evidence**, not on **agent capabilities**. A task marked "Fix Go bug" doesn't automatically route to agents with `capabilities: [go]`.

### 11.2 Cross-Project Work Prioritization

Mycroft handles single-project fleet coordination. Multi-project scenarios (5 projects × 3 agents each) need a higher-level arbiter.

### 11.3 Long-Lived Context Optimization

Budget constraints are per-sprint. There's no mechanism to optimize token consumption **across sprints** (e.g., "reuse findings from previous sprints when relevant").

### 11.4 Failure Mode Classification

Interspect tracks agent verdicts but doesn't yet classify **failure modes** (agent competence vs. task ambiguity vs. environment problem). This would enable more targeted routing fixes.

---

## Conclusion

Demarch's work orchestration evolution shows a **systems thinking approach** to multi-agent coordination:

1. **Start with measurement** (interstat, interspect)
2. **Formalize decisions** (beads state, routing overrides)
3. **Earn trust through evidence** (Mycroft tiers, approval rates)
4. **Make everything auditable** (git commits, dispatch logs)
5. **Enable continuous improvement** (feedback loops, demotion triggers)

The key insight is that orchestration is not about **algorithmic sophistication**; it's about **legibility + control**. When a user asks "why did the system make this decision?" there should be a traceable answer.

This approach scales to larger fleets not by building smarter algorithms, but by building **trust-earning mechanisms** where each component proves its competence before gaining autonomy.

---

<!-- flux-research:complete -->
