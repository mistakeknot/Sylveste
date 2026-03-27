# Autarch Autonomy Gap Analysis

**Date:** 2026-02-25
**Status:** Analysis
**Context:** Evaluating the gap between Autarch's current human-centric UX and Sylveste's vision of increasing agent autonomy through recursive rings of autonomous agencies.

---

## The Diagnosis

Autarch was designed as a human operator's cockpit. Sylveste has since evolved into a platform for autonomous agencies where the human is an executive — a visionary, judge, and strategic decision-maker — not an operator. The four Autarch apps (Bigend, Gurgeh, Coldwine, Pollard) still assume the human is *in* the loop at every step, when the architecture now calls for the human to be *above* the loop.

This isn't a bug in Autarch — it's a phase mismatch. Autarch was correct for L0-L1 autonomy (Record, Enforce). But Sylveste is now at L2 (React) and pushing toward L3 (Auto-remediate). The UX assumptions haven't kept pace.

## The Seven Gaps

### Gap 1: Operator UX vs Executive UX

**Current state:** Every Autarch app assumes the human will interact with each work item individually. Gurgeh's 8-phase workflow requires human review and approval at every phase. Coldwine expects the human to assign tasks, review breakdowns, and manage agents. Pollard surfaces individual research findings for human triage. Bigend shows real-time agent status assuming the human wants to watch.

**Target state:** The human sets objectives ("build X", "investigate Y"), defines constraints ("budget: 50K tokens", "must pass safety review"), and judges outcomes. Everything between objective and outcome is agency-internal. The human sees summaries, exceptions, and decision requests — not individual operations.

**Concrete symptoms:**
- Gurgeh's `/ask`, `/advance`, `/override` commands assume per-phase human presence
- Coldwine's task assignment and agent coordination assume human dispatch decisions
- Pollard's finding-by-finding review assumes human relevance scoring
- Bigend's real-time agent monitoring assumes the human watches processes run

### Gap 2: Tools as Workflow Steps vs Tools as Agency Rings

**Current state:** The four tools map to sequential workflow steps: research (Pollard) → design (Gurgeh) → plan/execute (Coldwine) → monitor (Bigend). The human drives the sequence.

**Target state:** Each tool maps to a **ring** in a recursive agency structure. The outer ring (strategic) makes high-level decisions. Middle rings (tactical) decompose and coordinate. Inner rings (operational) execute. Each ring is an autonomous sub-agency that escalates to the ring above only on exception.

```
Vision (Sylveste autonomy model):

                ┌─────────────────────┐
                │   HUMAN (Judge)     │
                │  Sets objectives    │
                │  Reviews outcomes   │
                │  Decides tradeoffs  │
                └─────────┬───────────┘
                          │ exceptions only
                ┌─────────▼───────────┐
                │  STRATEGIC RING     │
                │  (Portfolio/Bigend) │
                │  Cross-project      │
                │  Resource allocation│
                └─────────┬───────────┘
                          │ delegates down
          ┌───────────────┼───────────────┐
          │               │               │
   ┌──────▼─────┐  ┌─────▼──────┐  ┌─────▼──────┐
   │  DESIGN    │  │  EXECUTE   │  │  RESEARCH  │
   │   RING     │  │   RING     │  │   RING     │
   │  (Gurgeh)  │  │ (Coldwine) │  │ (Pollard)  │
   └──────┬─────┘  └─────┬──────┘  └─────┬──────┘
          │               │               │
     ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
     │ AGENTS  │    │ AGENTS  │    │ AGENTS  │
     │ Opus,   │    │ Codex,  │    │ Hunters │
     │ Sonnet  │    │ Haiku   │    │ Scouts  │
     └─────────┘    └─────────┘    └─────────┘
```

**What this means for Autarch:** The apps shouldn't be tools the human operates. They should be **windows into autonomous rings** that the human observes and occasionally intervenes in. The interaction model flips from "human drives, agents assist" to "agencies drive, human judges."

### Gap 3: Per-Item Interaction vs Exception-Based Attention

**Current state:** The human touches every item: every spec section, every task, every research finding, every phase transition. The TUI is designed for this — it has command palettes, keybindings, inline editors, and chat panels for continuous human-agent dialogue.

**Target state:** The human is presented with exceptions, decisions, and summaries. The normal case is no interaction required. Attention is pulled to:
- **Decisions that require human judgment** (tradeoffs, strategic direction, risk acceptance)
- **Exceptions that exceeded the agency's remediation ability** (3 retries failed, budget exceeded, contradictory requirements)
- **Milestone completions** (a sprint finished, a PRD passed all gates, a finding was confirmed)

**The attention metric:** At L2-L3, the human should interact with <10% of the items the agency processes. Current Autarch assumes ~100% interaction rate.

### Gap 4: Chat-Centric vs Dashboard-Centric

**Current state:** Gurgeh and Coldwine use a 3-pane layout (Sidebar | Document | Chat). The chat panel is the primary interaction surface — the human converses with agents to generate, edit, and review work. This is a Claude-style conversational UX, appropriate for L0-L1 where the human drives every step.

**Target state:** At L2-L3, the primary surface is a **decision dashboard** with:
- Agency health (are rings operating normally? any stuck?)
- Decision queue (what needs human judgment? sorted by urgency/impact)
- Outcome summary (what shipped? what failed? what's the quality signal?)
- Budget tracking (tokens spent vs value delivered)
- Interspect signals (what did we learn? what changed?)

Chat becomes a drill-down tool — "tell me more about this exception" — not the primary interface.

### Gap 5: Single-Project Focus vs Portfolio View

**Current state:** Gurgeh, Coldwine, and Pollard are project-scoped. The human works on one project at a time. Bigend aggregates projects but as a flat list of cards.

**Target state:** The human manages a **portfolio** of concurrent agencies. Each project has its own autonomous sprint running. The human sees cross-project status at a glance, allocates attention to the projects that need it, and lets the rest run autonomously. Intercore already has portfolio orchestration primitives (run budgets, cross-project verification).

### Gap 6: Manual Phase Advancement vs Autonomous Sprint Progression

**Current state:** Clavain's sprint workflow advances phases based on kernel gates, but Gurgeh's spec sprint and Coldwine's task orchestration have their own advancement logic embedded in app code (the "arbiter extraction debt" acknowledged in the Autarch vision doc).

**Target state:** All phase advancement is kernel-driven. Apps observe phase transitions; they don't control them. The autonomous agency (Clavain + Intercore) runs the full lifecycle. Apps render progress and surface exceptions.

**The arbiter problem is worse than acknowledged.** The vision doc treats arbiter extraction as architectural debt — agency logic that belongs in the OS. But the real issue is deeper: *the arbiter's existence assumes the human is present to drive it.* Extracting the arbiter to Clavain is necessary but not sufficient. The extracted logic must also become autonomous — it must run without continuous human input, escalating only when it can't proceed.

### Gap 7: No Delegation/Escalation Protocol

**Current state:** There is no formal protocol for an agency ring to escalate a decision to the human. The human is assumed to be present and engaged. Gurgeh's "ask the user" and Coldwine's "review this" are ad-hoc, not structured.

**Target state:** A typed escalation protocol:
- **Decision requests** with context, options, tradeoffs, and a recommended default
- **Exception reports** with what happened, what was tried, and what options remain
- **Approval gates** with evidence summaries and confidence scores
- **Priority/urgency classification** so the human can triage their attention queue

This maps directly to Interspect's signal taxonomy: human signals are expensive, so the system must use them efficiently. Structured escalation is how you minimize human attention while maximizing its value.

## The Reframe

Autarch's apps shouldn't be redesigned. They should be **re-layered**. The current tool-level interaction model (operate each step) becomes one mode in a hierarchy:

| Mode | Human Role | Interaction Rate | When |
|------|-----------|-----------------|------|
| **Executive** | Sets objectives, reviews outcomes, decides tradeoffs | <5% of items | L3-L4: Default mode |
| **Supervisor** | Monitors progress, intervenes on exceptions | ~10% of items | L2-L3: Fallback on flagged runs |
| **Operator** | Drives each step directly | ~100% of items | L0-L1: New/untrusted domains |

The current Autarch apps are the Operator mode. What's missing is Executive mode (the primary mode at L2+) and Supervisor mode (the middle ground).

### What Executive Mode Looks Like

**Instead of four tool tabs, one agency dashboard with drill-down:**

```
┌─ Agency Dashboard ──────────────────────────────────────────┐
│                                                              │
│ ▸ Portfolio Health                      Budget: 42K/100K     │
│   3 sprints active, 1 blocked, 2 completed today            │
│                                                              │
│ ▸ Attention Required (2)                                     │
│   ⚠ [interlock] Gate failed: safety review found P0 issue    │
│     → 3 remediation attempts exhausted. Options: [override]  │
│       [investigate] [reassign] [abort]                       │
│   ? [clavain] Tradeoff: add 2 new deps vs reimplement       │
│     → Agency recommends: reimplement (lower maintenance)     │
│     → [accept recommendation] [override: use deps] [discuss] │
│                                                              │
│ ▸ Completed Since Last Visit (5)                             │
│   ✓ [interflux] v0.3.0 shipped — 4 findings, 0 false pos    │
│   ✓ [interject] Research cycle — 12 discoveries, 3 promoted  │
│   ✓ [autarch] Bug fix sprint — 2 issues closed               │
│   ✓ [interspect] Overlay applied: fd-safety excluded on Go   │
│   ✓ [intercore] Gate rule relaxed: plan-review pass rate 98% │
│                                                              │
│ ▸ Interspect Insights                                        │
│   📊 Token efficiency up 12% this week (model downgrades)    │
│   📊 fd-architecture false positive rate: 8% (was 23%)       │
│   📈 Sprint completion rate: 94% (7-day rolling)             │
│                                                              │
│ ▸ Active Rings [expand for detail]                           │
│   🔄 interflux sprint: executing (phase 7/10, 3 agents)     │
│   🔄 interlock sprint: plan-review (2 agents, gate pending)  │
│   🔄 pollard research: continuous (next scan in 4h)          │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Key differences from current Autarch:**
1. **Attention is demand-pulled, not supply-pushed.** Items appear when they need the human, not because they exist.
2. **The dashboard is a decision queue**, not a monitoring wall. Each item has actions.
3. **Normal operation is invisible.** The 90% of work that proceeds without issues shows as summary lines, not individual items.
4. **Drill-down reveals the operator mode.** Clicking an active ring opens the current Gurgeh/Coldwine/Pollard view for that ring — but this is the exception, not the default.

## Implications for Each App

### Bigend → Agency Observatory
- **Keep:** Multi-project aggregation, real-time status
- **Add:** Attention queue (exception-driven), portfolio budget view, Interspect insights panel
- **Change:** Default view from "all agent activity" to "things that need you"
- **Remove:** Nothing — Bigend is closest to the target. It's already read-only and observation-focused.

### Gurgeh → Design Agency (autonomous PRD generation)
- **Keep:** The spec generation engine, confidence scoring, research integration
- **Add:** Autonomous sprint mode (run all 8 phases without human intervention, escalate only on low confidence)
- **Change:** Default interaction from "review each section" to "review the finished PRD with highlighted uncertainty"
- **Extract:** Arbiter to Clavain (already planned) — but make the extracted version autonomous-first, not human-driven

### Coldwine → Execution Agency (autonomous task coordination)
- **Keep:** Task hierarchy, agent coordination, file reservation
- **Add:** Autonomous execution mode (decompose, assign, execute, verify — escalate only on failure)
- **Change:** Default from "human assigns and monitors each task" to "human reviews sprint outcomes"
- **Extract:** Task orchestration to Clavain dispatch (already planned)

### Pollard → Discovery Agency (autonomous research)
- **Keep:** Multi-domain hunters, continuous watch, insight scoring
- **Add:** Autonomous triage (auto-promote high-confidence discoveries, auto-dismiss low-confidence)
- **Change:** Default from "human reviews each finding" to "human reviews promoted findings and adjusts interest profile"
- **Connect:** Feed directly into Intercore discovery pipeline (planned in vision doc)

## Architectural Requirements

For Executive mode to work, these infrastructure pieces are needed:

1. **Structured escalation protocol** — typed messages from agency to human (decision, exception, approval, milestone)
2. **Attention queue** — kernel-level priority queue of items requiring human judgment
3. **Autonomous sprint mode in Clavain** — full lifecycle without human gates (except configurable mandatory gates like "don't push without approval")
4. **Budget-based autonomy** — "run this sprint with a 50K token budget; stop and escalate if you'd exceed it"
5. **Interspect confidence gates** — automatic phase advancement when confidence exceeds threshold, human review when below

Most of these already exist as primitives in Intercore (gates, budgets, events, dispatches). The gap is in the **composition** — wiring them into an autonomous sprint mode and building the Executive UX on top.

## The Recursive Ring Model

The deepest reframe: Autarch apps should map to **agency rings**, not workflow steps.

Each ring is:
- **Autonomous** — it runs without human intervention in normal operation
- **Budget-constrained** — Intercore token budgets prevent runaway
- **Escalation-capable** — typed protocol to request human (or outer ring) judgment
- **Observable** — kernel events make all ring activity visible to outer rings
- **Self-improving** — Interspect profiles each ring and proposes optimizations

The rings compose recursively:
- A **research ring** (Pollard) discovers and scores findings
- A **design ring** (Gurgeh) consumes high-confidence findings and produces specs
- An **execution ring** (Coldwine) consumes specs and produces implementations
- A **portfolio ring** (Bigend) manages multiple concurrent research/design/execution cycles
- A **meta ring** (Interspect) observes all rings and proposes improvements

The human sits above all rings as the executive who:
- Sets the portfolio (which projects, which objectives)
- Resolves escalations (tradeoffs, risk acceptance, strategic direction)
- Reviews outcomes (what shipped, what quality, what cost)
- Adjusts policy (autonomy levels, budget constraints, gate thresholds)

This is already what the Sylveste vision describes. Autarch just hasn't caught up to the architecture it's supposed to surface.

## Recommended Next Steps

1. **Write the Executive Mode PRD** — Define the dashboard, attention queue, escalation protocol, and drill-down model
2. **Define the Escalation Protocol** — Typed messages with context/options/recommendation/urgency
3. **Prototype the Agency Dashboard** — A single TUI surface that replaces the four-tab model as the default entry point
4. **Extract + autonomize Gurgeh's arbiter** — Not just move it to Clavain, but make it autonomous-first
5. **Connect Pollard to Intercore discovery** — The research ring should feed the kernel, not a standalone database
6. **Add autonomous sprint mode to Clavain** — Full lifecycle with configurable human checkpoints

---

*This analysis evaluates the structural gap between Autarch's current human-operator UX and Sylveste's vision of autonomous agencies. It does not propose specific implementation — that belongs in a plan doc after review.*
