---
bead: sylveste-rsj.3.1
date: 2026-03-30
type: assessment
verdict: adopt L1-L2, extend L3, defer L4
---

# Assessment: Identification-as-Calibration for Interspect Routing

## Summary

This proposes applying NetHack's graduated item identification system as a design pattern for Interspect's agent/model routing. The core insight: routing decisions should escalate through increasing levels of signal fidelity — from free metadata lookups through historical evidence to expensive calibration probes — stopping at the cheapest level that yields a confident answer. This frames Interspect's existing evidence pipeline as Level 2 of a four-level identification hierarchy, clarifies what's already covered, and identifies two concrete gaps (model metadata as first signal, cross-project evidence aggregation).

## The Graduated Identification Model

NetHack uses graduated identification to reduce uncertainty about items: appearance hints are free, shop pricing narrows the class, watching monsters use items reveals behavior, and scrolls of identify give guaranteed answers at material cost. Each level trades cost for certainty.

Mapped to agent/model routing:

| Level | NetHack Analog | Interspect Equivalent | Signal Source | Cost |
|---|---|---|---|---|
| **1. Metadata** | Item appearance (color, shape) | Model family, context window, documented strengths, cost tier | `config/routing.yaml`, `agent-roles.yaml`, model provider docs | Free (config lookup) |
| **2. Prior traces** | Price identification (shop price narrows item class) | Historical evidence for same task type x agent — counting-rule pattern detection over 90-day rolling window | `.clavain/interspect/interspect.db` (SQLite) | Cheap DB query |
| **3. Peer signal** | Watching monster behavior with items | Cross-session traces — what did other agents/models achieve for similar complexity/domain in other projects | Cross-project interspect.db queries | Medium (cross-DB query) |
| **4. Benchmark probe** | Scroll of identify (guaranteed but costly) | Send calibration task to candidate model, measure response quality directly | LLM API call | Expensive (tokens + latency) |

The key property: each level is strictly more expensive than the previous, and strictly more informative. A well-designed system exhausts cheaper levels before escalating.

### Level 1: Metadata (Free)

Static properties known before any evidence exists. Model family (haiku/sonnet/opus), context window size, cost tier, documented strengths (coding vs. analysis vs. creative), and safety floor constraints. This is the "item appearance" — you can tell a red potion from a blue one without tasting either.

In Clavain's routing stack, this maps to `lib-routing.sh`'s static resolution: `routing_resolve_model` reads `config/routing.yaml` to map phase + category + agent to a model tier. The `_routing_model_tier()` function already encodes a haiku(1) < sonnet(2) < opus(3) ordering. Safety floors in `agent-roles.yaml` set per-agent minimums via `_routing_apply_safety_floor()`. Complexity-aware routing (B2) classifies tasks into C1-C5 tiers using prompt tokens, file count, and reasoning depth.

### Level 2: Prior Traces (Cheap)

Historical evidence from this project. Interspect's three hooks (SessionStart, PostToolUse, Stop) passively collect evidence about flux-drive agent accuracy. The counting-rule threshold system detects patterns — when an agent accumulates enough negative evidence in a domain, it becomes eligible for a routing override. Evidence decays on a 90-day rolling window. Overrides are written to `.claude/routing-overrides.json` (version 1 schema: `{"version":1,"overrides":[{"agent":"...","action":"exclude"|"propose",...}]}`).

This is the core of what Interspect does today. It is well-covered.

### Level 3: Peer Signal (Medium)

Cross-project evidence. If agent X consistently fails at TypeScript type-checking in Project A, that signal is relevant to Project B which also has TypeScript. Currently, each project's `interspect.db` is isolated — canary monitoring, evidence accumulation, and pattern detection are all single-project. There is no mechanism to query or aggregate evidence across projects.

Partially covered: the evidence schema and pattern detection logic are project-agnostic in principle, but the infrastructure for cross-project queries does not exist.

### Level 4: Benchmark Probe (Expensive)

Active calibration: send a known task to a candidate model and measure the response. This would provide ground-truth signal when Levels 1-3 are ambiguous (e.g., new model with no historical evidence, or conflicting cross-project signals). No calibration task mechanism exists in Interspect today.

## Current Interspect Coverage Audit

| Level | Coverage | Evidence |
|---|---|---|
| **1. Metadata** | **Partial — used but not formalized as routing signal** | `lib-routing.sh` resolves models from `routing.yaml` based on phase/category/agent. Safety floors enforce minimums. But metadata is not consulted as a first-pass filter *within Interspect* — Interspect operates on evidence (Level 2), not metadata. The static routing in `lib-routing.sh` and the evidence-based overrides in Interspect are two independent systems that don't compose as a hierarchy. |
| **2. Prior traces** | **Well-covered** | Core Interspect pipeline: 3 hooks collect evidence, counting-rule thresholds detect patterns, overrides written to `routing-overrides.json`, canary monitoring (20-use/14-day window, 20% regression alert). 90-day rolling evidence window. This is the primary value Interspect provides. |
| **3. Peer signal** | **Not covered** | Each project has its own `interspect.db`. No cross-project query mechanism. No evidence aggregation or sharing protocol. Canary monitoring is single-project. |
| **4. Benchmark probe** | **Not implemented** | No calibration task mechanism. No way to actively test a model's capability for a specific task type. |

## Gap Analysis

| Level | Status | Action |
|---|---|---|
| **1. Metadata** | Exists in lib-routing.sh but disconnected from Interspect's decision path | **Extend** — formalize metadata as the first routing signal Interspect consults before evidence lookup |
| **2. Prior traces** | Core functionality, well-implemented | **Adopt** — no changes needed |
| **3. Peer signal** | Not implemented | **Extend** — design cross-project evidence aggregation, but scope conservatively |
| **4. Benchmark probe** | Not implemented | **Defer** — overkill for current scale; revisit when model roster changes frequently |

## Proposed Additions

### Level 1 Enhancement: Metadata as First Signal

Interspect should consult model metadata before querying evidence. When `interspect-session.sh` runs at SessionStart or when `/interspect:propose` evaluates patterns, the first check should be: "does this agent's model tier match the task requirements based on static config?"

Concrete change: add a `_interspect_metadata_check()` function to `lib-interspect.sh` that reads `routing.yaml` model capabilities and `agent-roles.yaml` safety floors. If metadata alone resolves the routing question (e.g., agent is below safety floor for this task type), skip evidence lookup entirely. This formalizes the hierarchy: metadata first, evidence second.

This is a small change — it wires together two systems that already exist but don't talk to each other.

### Level 3: Cross-Project Evidence Aggregation

Design a lightweight mechanism for sharing evidence across projects. Two options:

**Option A (conservative):** Export/import. Add `interspect-export` and `interspect-import` commands that serialize evidence summaries (not raw events) as JSON. Manual workflow: export from Project A, import into Project B. No live queries, no shared DB.

**Option B (moderate):** Cross-DB read. When Interspect's pattern detection finds insufficient evidence for a decision (< counting-rule threshold), it optionally queries other project DBs under the same workspace. Discovery via glob: `~/projects/*/. clavain/interspect/interspect.db`. Read-only — never write to another project's DB.

Recommendation: **Option A first.** It's simpler, auditable, and doesn't introduce cross-project read dependencies. Option B can be added later if manual export/import proves too friction-heavy.

### Level 4: Calibration Probe (Deferred)

A calibration probe would send a known task to a candidate model and measure quality. This is the "scroll of identify" — guaranteed signal, but expensive. Design sketch for future reference:

- Calibration tasks would be stored in `.clavain/interspect/calibration-tasks/` as JSONL (input + expected output + scoring rubric).
- A `/interspect:calibrate-probe` command would run one task against one model and record the result.
- Probes would only fire when explicitly requested — never automatic, never on timeout.

**Explicitly deferred.** Current scale (< 10 flux-drive agents, < 5 model tiers) doesn't justify the token cost. The combination of metadata + evidence + manual corrections provides sufficient routing signal. Revisit when: (a) model roster grows beyond what manual assessment can track, or (b) a new model family arrives with no transferable evidence.

## Latency Constraints

| Level | Budget | Trigger |
|---|---|---|
| **Level 1 (Metadata)** | < 5ms | Always — first check on every routing decision |
| **Level 2 (Prior traces)** | < 10ms | Always — SQLite query against local `interspect.db` |
| **Level 3 (Peer signal)** | < 100ms | Only when Levels 1-2 return ambiguous or insufficient signals |
| **Level 4 (Benchmark probe)** | Unbounded (user-initiated) | Only with explicit opt-in via command invocation; never automatic |

Levels 1 and 2 run on every routing decision. Level 3 fires only when the first two levels fail to produce a confident answer. Level 4 is never triggered automatically — it requires the user to explicitly run a calibration command.

## Fallback Path

When signal queries fail or return null, degrade gracefully to current behavior:

- **Level 1 failure** (config file missing/malformed): Skip to Level 2. `lib-routing.sh` already handles missing config gracefully.
- **Level 2 failure** (DB corrupt/locked): Use Level 1 metadata only. `_interspect_read_routing_overrides()` already returns `{"version":1,"overrides":[]}` on malformed JSON.
- **Level 3 failure** (cross-DB query timeout/error): Use Levels 1-2 only. Cross-project signal is advisory — its absence never blocks routing.
- **Level 4 failure** (probe timeout/API error): Report failure to user. Never auto-retry. Never escalate cost on timeout.

The identification system is additive: it can only improve routing, not break it. Every level degrades to "skip this level and use whatever lower levels returned." The worst case is equivalent to today's behavior.

## Verdict

| Level | Verdict | Rationale |
|---|---|---|
| **Level 1 (Metadata)** | **Adopt** | Already exists in `lib-routing.sh`. Formalizing it as Interspect's first signal is a small wiring change, not new infrastructure. |
| **Level 2 (Prior traces)** | **Adopt** | Core Interspect functionality. No changes needed. |
| **Level 3 (Peer signal)** | **Extend** | Real gap. Start with export/import (Option A). Cross-DB reads (Option B) as follow-up if friction warrants it. |
| **Level 4 (Benchmark probe)** | **Defer** | Not justified at current scale. Design sketch preserved for future reference. |

**Overall verdict: adopt the graduated identification model as a design pattern.** Levels 1-2 are already implemented (just not composed as a hierarchy). Level 3 is the actionable gap. Level 4 is a known future option.

## Alignment

This directly supports Interspect's north star ("maximize routing accuracy — the right agent fires on the right task at the right cost") by formalizing a cost-ordered signal hierarchy that prevents expensive lookups when cheap ones suffice.

## Conflict/Risk

Minor tension with planning doctrine item 4 ("reserve optimization work until correctness and reliability are proven") — Level 3 cross-project aggregation introduces a new data flow before Level 2 evidence collection is fully battle-tested. Mitigated by making Level 3 advisory-only and never allowing it to override Level 2 signals.
