# Flux Drive Synthesis: Hyperspace AGI Relevance Assessment
**Date:** 2026-03-14
**Reviewed by:** 5 specialized agents (coordination-state-model, autonomous-work-loop, observability-data-model, plugin-evolution, capability-routing)
**Source:** `research/agi-hyperspace/ANALYSIS.md` + Demarch codebase deep dive
**Verdict:** ADAPT SELECTIVELY — High conceptual alignment, but specific techniques require significant translation

---

## Executive Summary

Hyperspace AGI is a **peer-to-peer network of autonomous ML research agents** that continuously run experiments, share discoveries via gossip protocol, and compound results into a public leaderboard. While operating in a fundamentally different environment (decentralized peers, narrow metrics, WASM sandbox) than Demarch (single-machine, multi-dimensional quality, broad autonomy), the core insights about **autonomous learning loops, mutation-based improvement, and compound discovery** are directly applicable.

**Key verdict:** The 3-layer coordination stack (real-time → convergent → durable) is architecturally sound for Demarch. The gap is not in concepts but in implementation details — Demarch can use simpler primitives (SQLite + webhooks vs. CRDTs + GossipSub) while preserving the compound learning pattern.

### Headline Findings

| Finding | Priority | Status |
|---------|----------|--------|
| **Feedback loop does not close** — Skaffen emits evidence but Compound phase writes nothing back | P0 | CRITICAL |
| **Convergent state should use SQLite, not CRDTs** — Interlock is already single-writer centralized; Dolt zombies are process management bugs, not state model bugs | P1 | ARCHITECTURE |
| **Fleet-registry schema invalid** — `orchestrator` category not enumerated; `routing_level` field missing | P0 | BLOCKING |
| **Plugin quality scoring ready** — Composite formula (correctness × utility × trust) reuses 80% existing infrastructure | P1 | IMPLEMENTABLE |
| **Multi-dimensional quality is stronger** — Hyperspace's scalar reduction is wrong for code; Demarch should resist it | P2 | PHILOSOPHY |
| **Snapshot-mode observability** — Replace complex dashboards with 40-line JSON composer script | P0 | QUICK WIN |

---

## Pillar-by-Pillar Recommendations

### 1. Clavain (L2 OS — Orchestration & Sprint Management)

**Verdict:** HIGH RELEVANCE — Focus on coordination stack, skip CRDT implementation

#### P0 Findings (Blocking)

**1.1: Fix negotiation force-release unrecoverable state**
- Issue: If negotiation times out and holder crashes, `force_release_negotiation` doesn't know whether to wait for TTL expiration or release immediately
- Impact: Dead agents block living agents from claiming their own files
- Fix: Query intermute's `Heartbeat` system before timeout validation. If holder is dead (>5min no heartbeat), skip timeout and release immediately
- Location: `interverse/interlock/internal/tools/tools.go` line 716-764 (`force_release_negotiation`)
- Effort: Low (single HTTP call to intermute)

#### P1 Findings (High-Value)

**1.2: Consolidate dual-system claim model**
- Current state: `cmdSprintClaim` uses both `ic lock` (intermute) AND `bd set-state` (Dolt) — two failure domains
- Recommendation: Check intermute reservation only (single HTTP call) + set bd state (single bd call). Drop ic lock requirement.
- Why: The ic agent tracking is metadata but shouldn't gate the claim. Intermute reservation is the source of truth.
- Locations: `os/Clavain/cmd/clavain-cli/claim.go` lines 49-150

**1.3: Make sprint-find-active cancellation idempotent**
- Current state: Multiple concurrent sessions can both find the same stale run and both try to cancel it
- Recommendation: Check run status before canceling. If already cancelled, skip.
- Location: `os/Clavain/cmd/clavain-cli/sprint.go` line 261-263

**1.4: Add timeout wrapper to bd state calls**
- Current state: `runBD("state", beadID, "claimed_by")` can hang indefinitely if Dolt server is zombied
- Recommendation: Add 2-second timeout, fall back to JSONL parsing if unavailable
- Location: `os/Clavain/cmd/clavain-cli/claim.go` line 287 (`cmdBeadHeartbeat`)
- Effort: Low

#### P2 Findings (Infrastructure)

**1.5: Enable WebSocket push notifications for reservations**
- Current: Agents poll for negotiation responses via `time.Sleep(negotiationPollInterval)`
- Hyperspace equivalent: GossipSub broadcasts results in ~1 second
- Demarch can do: Expose intermute's `Broadcaster` interface (already exists in sweeper) to interlock clients
- Value: Eliminates polling latency for file release negotiations
- Location: `core/intermute/internal/ws/gateway.go` (Broadcaster pattern exists, not exposed to clients)

**1.6: Create periodic "coordination snapshot"**
- Hyperspace analogy: `snapshots/latest.json` published hourly
- Demarch equivalent: JSON file with active agents, reservations, active sprints
- Use case: Agents read at session start for context (Observe phase pre-loading)
- Effort: ~30 lines bash, cron job

#### P3 Findings (Learning)

**1.7: Add progress heartbeat with token delta**
- Current: `bead-heartbeat` only proves liveness (agent can execute `bd set-state`)
- Enhancement: Also report token spend delta since last heartbeat
- Value: Distinguish "alive but stuck" (same tokens) from "making progress" (tokens increasing)
- Mapping: Hyperspace's pulse verification proves *computation happened*; token delta is the local equivalent

---

### 2. Skaffen (L2 Sovereign Agent — Autonomous Work Loop)

**Verdict:** MEDIUM-HIGH RELEVANCE — The feedback loop is the critical missing piece

#### P0 Findings (Blocking — Cannot Proceed Without)

**2.1: Close the feedback loop — Compound phase must write to persistent store**

The single most critical gap: **Skaffen's OODARC has all phases but Reflect + Compound don't feed back into future sessions.**

Current state:
```
Observe → Orient → Decide → Act → Reflect → Compound
(loads context) (generates plan) (executes) (emits evidence) (does nothing, returns)
```

The Compound phase (`os/Skaffen/internal/agent/phase.go`) exists in the FSM but PRD line 62 marks its actual behavior as "deferred to v0.2." It currently has `{read, glob, ls, bash}` tools but no structured compounding.

**What Hyperspace does:** Discovery stage (peer scoring) feeds back into Hypothesis stage (next experiment). The loop is closed.

**What Demarch must do:**
1. Compound phase writes **quality signals** to a persistent store (mutations JSONL, auto-memory topic files, or both)
2. Orient phase reads from that store before planning
3. The signals must be **multi-dimensional** (tests pass, review score, tokens spent, diff size, regression prevented) — not a single scalar

**Implementation:** Add package `os/Skaffen/internal/compounding/` with:
- `store.go` — JSONL reader/writer (same pattern as interlab's state.go)
- `quality_signal.go` — Data structure capturing hard/soft/human signals
- `write_compound.go` — Inject quality signals into auto-memory or mutations store

**Location:** `os/Skaffen/internal/agent/phase.go` (phase FSM) + new `compounding/` package

**Effort:** Medium (requires session lifecycle integration, not just a new tool)

**Priority:** P0 — Without this, every session is independent. No compound learning happens.

---

#### P1 Findings (High-Value)

**2.2: Define multi-dimensional quality signals**

Replace Hyperspace's scalar (`test_pass_rate`) with structured data:

```go
type QualitySignal struct {
    // Hard signals (automated, reliable)
    TestsPass       bool    `json:"tests_pass"`
    TestsAdded      int     `json:"tests_added"`
    LintClean       bool    `json:"lint_clean"`
    BuildSucceeds   bool    `json:"build_succeeds"`

    // Soft signals (heuristic, noisy but useful)
    DiffSizeLines   int     `json:"diff_size_lines"`
    FilesChanged    int     `json:"files_changed"`
    TurnsUsed       int     `json:"turns_used"`
    TokensSpent     int     `json:"tokens_spent"`

    // Human signals (high-value, sparse)
    ReviewScore     *int    `json:"review_score,omitempty"`  // 1-10 from flux-drive
    Accepted        *bool   `json:"accepted,omitempty"`      // human accepted change
    RevisionCount   int     `json:"revision_count"`

    // Composite (derived)
    Efficiency      float64 `json:"efficiency"`  // quality per token
}
```

**Selection method:** Use **Pareto dominance** (approach A beats B if A is better on ≥1 dimension and not worse on any) instead of scalar reduction. This preserves multi-dimensionality while enabling automated comparison.

**Location:** New struct in `os/Skaffen/internal/compounding/` + extend interlab's `Result.SecondaryMetrics`

**Effort:** Low (type definition + collection hooks)

**Blocker:** P0 (close feedback loop) must come first

---

**2.3: Maintain mutation history per task type**

**Data structure:**
```json
// ~/.skaffen/mutations/<task-type>.jsonl
// One line per approach, append-only

{"type":"baseline","task_type":"bug-fix","approach":"reproduce → diagnose → fix → test","outcome":"success","quality_signals":{...},"session_id":"abc123","timestamp":"2026-03-14T10:00:00Z"}

{"type":"mutation","task_type":"bug-fix","approach":"reproduce → failing test → fix → verify → regression test","parent":"abc123","mutation":"added failing test before fix","outcome":"success","quality_signals":{...},"session_id":"def456","timestamp":"2026-03-14T14:00:00Z"}
```

**Task types to track:**
- `bug-fix` — diagnosis strategy, test-first vs fix-first, root-cause depth
- `feature` — decomposition strategy, API-first vs impl-first, test coverage
- `refactor` — scope strategy, incremental vs big-bang, test preservation
- `optimization` — profiling strategy, metric selection, iteration depth
- `docs` — audience, structure template, example depth

**Selection:** Best approach = highest Pareto score. Inject into Orient phase context.

**Location:** `os/Skaffen/internal/mutations/` (new package) — same pattern as interlab's state.go

**Effort:** Medium

**Blocker:** Depends on P0 (feedback loop) + P1 (quality signals)

---

**2.4: Inspiration-before-hypothesis in Orient phase**

Before generating a plan, Orient phase should:
1. Detect task type from user prompt
2. Query mutations store for best approach to this task type
3. Query CASS for sessions that worked on similar tasks: `cass search "<task description>" --robot --limit 3`
4. Read auto-memory topic files relevant to the project
5. Inject this context into system prompt via `SessionPrompt()`

**Location:** `os/Skaffen/internal/session/prompt_session.go` (priompt system)

**Effort:** Medium (priompt integration, CASS/intersearch queries)

**Blocker:** Depends on P1 (mutation store)

---

#### P2 Findings (Useful but not blocking)

**2.5: Skip JOURNAL.md, keep auto-memory**

Hyperspace agents maintain per-agent journals. Demarch should NOT adopt this because:
- Auto-memory is already per-project, shared across sessions (right model for single-operator context)
- Topic file pattern provides structure that JOURNAL.md's narrative lacks
- CASS transcript exports already serve as the investigation narrative

**What is missing:** Per-task narrative continuity (JOURNAL provides this, auto-memory doesn't). Solution: use CASS session transcript export (already in Clavain's `/reflect` command) + mutations store (provides approach evolution record).

**Recommendation:** Maintain status quo — auto-memory + CASS transcripts + mutations store covers all three use cases better than adding JOURNAL.md.

---

**2.6: Learning-level delta sharing for multi-Skaffen**

When multiple Skaffen instances work on related tasks, they should share discoveries (mutations, best approaches) without sharing code changes.

**Mechanism:** Extend interlock's `broadcast_message` with structured mutation records. Other sessions check for new mutations before starting work.

**Effort:** Low (message format definition + broadcast hook)

**Blocker:** Depends on P1 (mutation store has structure to broadcast)

---

### 3. Observability & Data Model

**Verdict:** QUICK WINS — Most infrastructure exists; gap is consolidation, not collection

#### P0 Findings (Blocking)

**3.1: `bd snapshot --json` consolidated summary format**

**Current state:** Beads backup produces 1.1MB JSONL (too large for LLM consumption). Interstat produces focused JSON but 10 different modes (not consolidated). No single file to "point any LLM at."

**Solution:** Compose `snapshot.json` (~10KB) from existing tool outputs:
```json
{
  "version": 1,
  "timestamp": "2026-03-14T12:00:00Z",
  "counts": {
    "total": 952, "open": 208, "in_progress": 12, "closed": 732, "blocked": 4
  },
  "velocity": {
    "closed_last_7d": 47, "closed_last_24h": 8, "avg_close_time_hours": 3.2, "cost_per_change_usd": 1.17
  },
  "active_agents": [
    {"session_id": "...", "bead_id": "Demarch-05kd", "claimed_at": "...", "title": "..."}
  ],
  "blockers": [...],
  "top_cost_beads_7d": [...],
  "experiment_campaigns": {...}
}
```

**Implementation:** ~40 lines bash joining outputs from:
1. `bd list --json` (counts, active agents)
2. `cost-query.sh baseline` (velocity/cost)
3. `interlab status_campaigns` (experiment data)

**Composition script:** `.beads/scripts/snapshot.sh` or SessionStart hook

**Effort:** Low (composing existing outputs)

**Blocker:** None — can ship immediately

---

#### P1 Findings

**3.2: Per-bead work-record JSON schema**

Hyperspace's `run-NNN.json` per experiment. Demarch needs equivalent:

```json
{
  "version": 1,
  "bead_id": "Demarch-05kd",
  "session_id": "2f47757d-c465-4865-af26-0a9911d43f5e",
  "agent": "claude-opus-4-6",
  "timestamp": "2026-03-14T04:18:27Z",
  "duration_s": 342,
  "outcome": "closed",

  "cost": {
    "total_tokens": 48000,
    "input_tokens": 35000,
    "output_tokens": 13000,
    "usd": 1.42
  },

  "artifacts": {
    "commits": ["abc1234", "def5678"],
    "files_changed": 4,
    "lines_added": 120,
    "lines_removed": 15,
    "tests_added": 3
  },

  "experiment": {
    "metric_name": "reconstruct_100_ns",
    "direction": "lower_is_better",
    "baseline": 1540000,
    "result": 68000,
    "improvement_pct": 95.6
  },

  "context": {
    "sprint_id": "sprint-2026w11",
    "parent_bead": "Demarch-85k",
    "complexity": 2,
    "priority": 2,
    "issue_type": "task"
  }
}
```

**Implementation:** 50-line bash script joins:
- Interstat's `cost-snapshot` (cost section)
- Interlab's `CampaignSummary` (experiment section)
- Beads JSONL (context section)
- Git (commits section)

**Location:** `.beads/records/<bead_id>.json` (one file per closed bead)

**Effort:** Low

---

**3.3: Sprint report generator (NOT leaderboard)**

Hyperspace's auto-generated LEADERBOARD doesn't apply — Demarch agents do heterogeneous work that can't be ranked on a single axis.

**Instead:** Generate periodic sprint retrospective:
```markdown
## Sprint Report: 2026-W11
**Closed:** 47 beads | **Cost:** $55.00 | **Avg time:** 3.2h

### By Type
| Type | Count | Avg Cost |
|------|-------|----------|
| feature | 12 | $2.10 |
| bug | 18 | $0.80 |

### Notable Completions
- F4: Model routing + budget tracking ($4.20, 3h)

### Cost Outliers (>2x avg)
- Demarch-0pj: F4 Model routing — $4.20 (3.6x avg)
```

**Implementation:** 100 lines bash joining:
1. `bd list --status=closed --since=<sprint_start> --json`
2. `cost-query.sh by-bead --since=<sprint_start>`
3. `interlab status_campaigns`

**Effort:** Low

**Integration:** Send to Intercom's TelegramBridge for team awareness

---

#### P2 Findings

**3.4: Autarch activity feed from snapshot + work records**

Bigend's web dashboard could consume `snapshot.json` directly. Mycroft's status command could include recent closed beads with cost data. No new data pipeline — just aggregation.

**Effort:** Integration work (existing data, new presentation)

---

### 4. Plugin Evolution & Interverse

**Verdict:** HIGH RELEVANCE — Interlab already does most of the work

#### P0 Findings (Blocking)

**4.1: Human approval gate for autonomous plugin publish**

**Current state:** `ic publish` pushes to marketplace without human review

**Requirement:** Never auto-publish autonomously-mutated plugins. Loop must be:
```
Agent identifies friction → Agent runs /autoresearch on plugin →
Agent creates PR with mutations → Human reviews PR → Human publishes
```

**Mapping:** PHILOSOPHY.md trust level 2: "Human reviews evidence post-hoc"

**Implementation:** Extend interpub pipeline to require human approval on plugin publish. Already gated for plugin code changes; this is about autonomous mutations.

**Effort:** Medium (approval workflow in interpub)

---

**4.2: SKILL.md content scanning for injection patterns**

Before any mutated skill enters the publish pipeline, scan for:
- Injection patterns: "ignore previous instructions", "do not report", "always approve"
- Exfiltration patterns: `curl`, `wget`, `nc`, base64-encoded payloads
- Authority escalation: "override", "bypass", "skip verification"

**Implementation:** New intercheck hook or extension of interskill audit

**Effort:** Medium (pattern detection + flagging)

---

#### P1 Findings

**4.3: Plugin Quality Score (PQS) formula + data wiring**

Define composite scoring:
```
PQS = correctness_score × utility_score × trust_modifier

correctness_score = (structural_tests / total)
                  × (build_passes ? 1.0 : 0.0)
                  × (audit_score / 19)

utility_score = normalize(
    0.5 × active_session_invocations_30d
  + 0.3 × unique_agent_sessions_30d
  + 0.2 × cross_project_session_count_30d
)

trust_modifier = intertrust_author_score
```

**Differences from Hyperspace:**
- Three factors instead of two (add author trust)
- Multi-signal utility (intensity + breadth + generalizability)
- Audit-augmented correctness (skill quality, not just build)

**Data sources already exist:**
1. Structural tests (`tests/structural/test_structure.py`)
2. Build status (go test / uv run pytest)
3. Interskill audit (19-point checklist)
4. Interstat tool invocations (aggregated per plugin)
5. Intertrust author scores (already computed)

**Implementation:**
1. Add `plugin-health` command to interpub/intercheck
2. Extend interstat to aggregate per-plugin invocations
3. Write `plugin-score` script combining all signals
4. Publish to `plugin-health.json` in marketplace

**Effort:** Medium (mostly wiring existing tools)

---

**4.4: `plugin-benchmark.sh` for interlab plugin campaigns**

The gap is not the loop machinery (interlab's `/autoresearch` is ready) — it's the benchmark command.

**What's needed:** A script that:
1. Runs structural tests
2. Runs interskill audit
3. Emits METRIC lines (PQS score and components)

**Example campaign spec:**
```json
{
  "name": "interlock-quality",
  "metric_name": "plugin_quality_score",
  "metric_unit": "score",
  "direction": "higher_is_better",
  "benchmark_command": "bash plugin-benchmark.sh",
  "files_in_scope": [
    "skills/conflict-recovery/SKILL.md",
    "skills/coordination-protocol/SKILL.md",
    ".claude-plugin/plugin.json"
  ]
}
```

**Output:**
```
METRIC plugin_quality_score=0.78
METRIC structural_tests_pass=6
METRIC structural_tests_total=6
METRIC audit_score=14
METRIC audit_max=19
```

**What unlocks:** Agents can run `/autoresearch` on any plugin, iteratively improving skill quality, fixing audit failures, optimizing structure — using the same loop that optimized ReconstructState 22x.

**Effort:** Low (single new script, reuses all interlab infrastructure)

**Blocker:** None — can ship immediately

---

**4.5: Diff-bounded mutations (exclude hooks, bins, manifests)**

Constrain what interlab can modify in plugin improvement campaigns:
- **Allowed:** Skill content files (SKILL.md, SKILL-compact.md), test files
- **Excluded:** hooks/, bin/, .claude-plugin/plugin.json, commands/

Hook modifications require separate, more restrictive approval.

**Implementation:** `files_in_scope` configuration in campaign spec

**Effort:** Low

---

**4.6: Metric rotation for Goodhart resistance**

Per PHILOSOPHY.md: "Agents will optimize for any stable target. Rotate metrics, cap optimization rate, randomize audits."

For plugin improvement campaigns:
1. Rotate primary metric between correctness sub-dimensions (structural tests → audit score → integration coverage)
2. Cap improvement campaigns to 1 per plugin per week
3. Randomly include "red team" sub-campaigns that try to *break* the plugin

**Effort:** Low (campaign configuration)

---

#### P2 Findings

**4.7: Multi-plugin improvement via `/autoresearch-multi`**

Once individual plugin campaigns work, multi-campaign orchestration is nearly free:

```json
{
  "goal": "Improve plugin quality scores across 5 lowest-scoring plugins",
  "campaigns": [
    {"name": "interlock-quality", "benchmark_command": "...", "files_in_scope": [...]},
    {"name": "intercheck-quality", "benchmark_command": "...", "files_in_scope": [...]}
  ]
}
```

Reuses `plan_campaigns` (file conflict detection), `dispatch_campaigns` (subagent dispatch), `synthesize_campaigns` (cross-plugin aggregation).

**Effort:** Low (orchestration already shipped in interlab v0.3)

---

**4.8: interject scanning for low-PQS plugins**

Extend interject (discovery inflow pipeline) to periodically scan plugin quality scores and create beads for plugins below a PQS threshold.

This is the "agent identifies friction" step that starts the evolution loop.

**Effort:** Medium (interject integration)

---

### 5. Capability Routing (from fd-capability-routing)

**Verdict:** DO NOT ADOPT Hyperspace's flat weight model — Demarch's B1-B4 routing is more sophisticated

#### P0 Findings (Blocking)

**5.1: Fix fleet-registry schema validation errors**

**Issue 1:** `orchestrator` category not in enum
- Current valid categories: `kernel`, `os`, `agent`
- Missing: `orchestrator` (Clavain declares itself as this)
- Fix: Add `orchestrator` to enum in fleet-registry schema

**Issue 2:** Missing `routing_level` field
- Current: Routes can stack recursively (orchestrator → os → agent)
- Problem: No way to express "this is kernel-level routing, don't route further"
- Fix: Add `routing_level` field: `kernel | os | orchestrator | agent`
- Prevents recursive routing in flat models

**Location:** `core/fleet-registry/schema.json` or YAML schema definition

**Blocker:** fleet-registry is invalid against its own schema — this breaks downstream validation

---

#### P1 Findings

**5.2: DO NOT adopt capability declarations in lib-routing.sh**

Hyperspace uses flat capability weights (e.g., +10% for inference, +12% for research).

**Why it doesn't work for Demarch:**
1. **Demarch has a 4-track routing system (B1-B4)** — already more sophisticated than flat weights
2. **Capability declarations belong in a pre-filter, not a scoring signal**
3. **Evidence scoring should drive agent selection**, not declared capabilities
4. **Capabilities should enter late in the process** — after evidence phase has narrowed candidates

**Recommendation:** If capability declarations are added later, wire them as pre-filters:
```
Candidate agents = route_by_availability()
Filtered agents = pre_filter_by_capability(candidates, required_capabilities)
Scored agents = score_by_evidence(filtered_agents)
Selected agent = highest_score(scored_agents)
```

Not:
```
Scored agents = evidence_score + capability_bonus
Selected agent = highest_score(agents)
```

**Location:** `os/Clavain/scripts/lib-routing.sh` — do NOT add capability scoring there yet

---

#### P2 Findings

**5.3: Add `capability_weights` section to fleet-registry**

For future C3 Composer (relative importance of capabilities per task type).

**Schema example:**
```yaml
capability_weights:
  bug-fix:
    diagnostics: 0.4
    testing: 0.3
    code-correctness: 0.2
    documentation: 0.1

  feature:
    api-design: 0.3
    code-correctness: 0.3
    testing: 0.2
    documentation: 0.1
```

**Current state:** Placeholder, not used

**Effort:** Schema addition only (no logic changes)

---

**5.4: Wire `fleet_by_capability` into flux-drive triage**

Once capabilities are well-defined, use them to pre-filter reviewers for flux-drive sessions.

**Current:** Reviewers are selected by availability + trust score

**Enhancement:** Prefer reviewers who have demonstrated expertise in the code area (based on capability declarations + past review history)

**Effort:** Medium (flux-drive triage logic)

---

#### P3 Findings (Not Applicable)

**5.5: Uptime formula not applicable**

Hyperspace tracks agent uptime for capability scoring (persistent daemons that crash less are preferred).

Demarch agents are session-scoped (created, run task, exit). Uptime is not a meaningful signal. **Skip this.**

**5.6: Hardware adaptation irrelevant**

Hyperspace agents adapt their compute budget to available hardware (browser → laptop → H100).

Demarch abstracts hardware via model tier (Haiku, Sonnet, Opus). The model tier routing already covers this. **Skip this.**

---

## Cross-Cutting Themes

### Theme 1: The Feedback Loop Is the Missing Piece

Every review agent identified that **Skaffen/Autarch cannot compound learning** because Compound/Reflect phases emit evidence but no future session reads it. This is the #1 architectural gap.

**Why it matters:** Without compound learning, every session is independent. The agent learns nothing from past work. This is the core difference between Hyperspace (which closes the loop) and current Demarch (which doesn't).

**Solution:** Requires P0 work in Skaffen to wire Compound → persistent store → future Orient/Decide phases.

---

### Theme 2: Demarch Can Use Simpler Primitives

Hyperspace uses CRDTs, GossipSub, and cryptographic proofs because it's **decentralized, multi-party, untrusted**. Demarch is **centralized-but-local, single-operator, trusted**.

**Implication:** Don't copy Hyperspace's infrastructure wholesale. Adapt the *concepts* while using simpler primitives:

| Hyperspace | Demarch Can Use Instead | Why |
|-----------|------------------------|-----|
| GossipSub broadcast | Webhook + polling | Single-machine, agents can poll |
| CRDT leaderboard | SQLite with circuit breaker | Single-writer (intermute) on one machine |
| Cryptographic proof-of-work | Token spend delta tracking | Single-operator context |
| Per-agent branches | Agent-namespaced directories + CASS | Avoids merge complexity, preserves history |
| Gossip skill discovery | Marketplace + interstat + beads | Centralized registry already exists |

---

### Theme 3: Multi-Dimensional Quality Is Critical

**Hyperspace's assumption:** Single metric (`val_loss`, NDCG@10, test_pass_rate) enables clean comparison.

**Demarch's reality:** Code quality is multi-dimensional (correctness, readability, performance, security, design consistency). Reducing it to a single score leads to Goodhart's Law violations.

**Recommendation:** Use **Pareto dominance** — approach A is better than B if A is better on ≥1 dimension and not worse on any. This preserves nuance while enabling automated comparison.

---

### Theme 4: Observability Is 80% Done

Demarch already produces structured JSON from interstat, cass, interlab, and beads. The gap is not data collection but **consolidation**. A single snapshot composer script (40-50 lines) joining existing outputs delivers 80% of Hyperspace's observability UX.

---

## Priority-Ordered Implementation Roadmap

### Week 1 (Quick Wins)

- [ ] P0: Create `bd snapshot --json` composer (40 lines bash) — **enables LLM analysis**
- [ ] P0: Fix fleet-registry schema (add `orchestrator` enum value, `routing_level` field) — **unblocks validation**
- [ ] P0: Add `plugin-benchmark.sh` (single script) — **enables plugin improvement campaigns**
- [ ] P1: Add 2-second timeout wrapper to `bd state` calls in Clavain
- [ ] P1: Make `sprint-find-active` cancellation idempotent (check status before canceling)

### Week 2-3 (Core Gaps)

- [ ] P0: Close the feedback loop — Skaffen's Compound phase writes quality signals to persistent store
- [ ] P0: Define multi-dimensional quality signals struct
- [ ] P0: Query intermute Heartbeat before timeout in `force_release_negotiation`
- [ ] P1: Consolidate dual-system claim model (drop ic lock requirement)
- [ ] P1: Mutation history store per task type (JSONL, pattern from interlab)
- [ ] P1: Plugin Quality Score formula + data wiring
- [ ] P1: Diff-bounded mutations config (exclude hooks/bins/manifests)
- [ ] P1: Metric rotation for Goodhart resistance

### Week 4+ (Compounding)

- [ ] P2: Enable WebSocket push notifications for reservation events
- [ ] P2: Inspiration-before-hypothesis in Orient phase (query mutations + CASS + auto-memory)
- [ ] P2: Sprint report generator
- [ ] P2: Multi-plugin improvement campaigns (`/autoresearch-multi`)
- [ ] P2: interject scanning for low-PQS plugins
- [ ] P3: Add progress heartbeat with token delta
- [ ] P3: Per-bead work-record JSON schema (nice-to-have, enables analysis)

---

## Key Codebase Locations

### Coordination & Orchestration
- Interlock MCP tools: `/home/mk/projects/Demarch/interverse/interlock/internal/tools/tools.go`
- Intermute storage: `/home/mk/projects/Demarch/core/intermute/internal/storage/sqlite/`
- Clavain sprint/claim logic: `/home/mk/projects/Demarch/os/Clavain/cmd/clavain-cli/{claim,sprint}.go`
- Clavain routing: `/home/mk/projects/Demarch/os/Clavain/scripts/lib-routing.sh`

### Work Loop & Compounding
- Skaffen OODARC FSM: `/home/mk/projects/Demarch/os/Skaffen/internal/agent/phase.go`
- Skaffen evidence: `/home/mk/projects/Demarch/os/Skaffen/internal/evidence/emitter.go`
- Interlab state model: `/home/mk/projects/Demarch/interverse/interlab/internal/experiment/state.go`
- Session prompt: `/home/mk/projects/Demarch/os/Skaffen/internal/session/prompt_session.go`

### Observability
- Fleet registry: `core/fleet-registry/` (schema location)
- Beads backup: `/home/mk/projects/Demarch/.beads/backup/`
- Interstat: `/home/mk/projects/Demarch/interverse/interstat/scripts/cost-query.sh`
- Cass: `~/.local/bin/cass` (v0.2.0+)

### Plugin Evolution
- Interlab `/autoresearch`: `/home/mk/projects/Demarch/interverse/interlab/skills/autoresearch/SKILL.md`
- Interskill audit: `/home/mk/projects/Demarch/interverse/interskill/skills/audit/SKILL.md`
- Intertrust: `/home/mk/projects/Demarch/interverse/intertrust/`
- Interpub pipeline: `/home/mk/projects/Demarch/interverse/interpub/`
- Structural tests: `tests/structural/test_structure.py` per plugin

---

## What NOT to Do

### Anti-Pattern 1: Copy CRDTs wholesale
**Why:** Demarch is single-machine, single-operator. Loro CRDTs solve a multi-writer convergence problem that doesn't exist. Use SQLite with circuit breaker + retry (already in intermute). The real problem is Dolt's process management bugs, not the state model.

### Anti-Pattern 2: Reduce code quality to a single metric
**Why:** Hyperspace optimizes `val_loss` because ML metrics are naturally scalar. Code quality is multi-dimensional. Trying to optimize a single score (e.g., "code quality index") leads to Goodhart's Law violations. Use Pareto dominance instead.

### Anti-Pattern 3: Adopt per-agent branches for code
**Why:** Hyperspace's per-agent branches work because agents write independent config files. Demarch agents modify the same shared codebase. Per-agent branches would bypass interlock's conflict detection. Keep trunk-based development. Use agent-namespaced *directories* for artifacts (already in use).

### Anti-Pattern 4: Auto-publish plugin mutations
**Why:** This turns a quality improvement tool into an attack surface. The publish step *must* require human approval. Never ship autonomous plugin evolution without a human-in-the-loop gate.

### Anti-Pattern 5: Build elaborate dashboards
**Why:** Hyperspace publishes raw JSON snapshots and tells users "point any LLM at it." Demarch should do the same. Generate `snapshot.json` and let LLMs interpret it. Resist building Bigend dashboard widgets for every metric.

---

## Philosophical Alignment Summary

**Where Hyperspace and Demarch Agree:**
1. Agents as first-class citizens (autonomous, not just tools)
2. Compound learning (intelligence accumulates across sessions)
3. Hardware heterogeneity (support diverse tiers/devices)
4. Git as source of truth (durable archive)
5. Open research (transparency over secrecy)

**Where They Differ:**
1. **Centralization** — Hyperspace: fully P2P. Demarch: centralized-but-local.
2. **Incentives** — Hyperspace: points/tokens. Demarch: task completion + testing.
3. **Autonomy scope** — Hyperspace: narrow (single metric). Demarch: broad (code understanding + design).
4. **Mutation target** — Hyperspace: hyperparameters. Demarch: code (much harder search space).
5. **Verification** — Hyperspace: cryptographic proof. Demarch: tests + human review.

**The key adaptation:** Steal the *mechanism* (feedback loop, mutation strategy, convergent state) while respecting Demarch's constraints (single machine, broad autonomy, multi-dimensional quality, human oversight).

---

## Conclusion

Hyperspace AGI is a **valuable reference architecture** for Demarch's next evolution. The core insight — **close the feedback loop so agents compound learning** — is exactly what Demarch needs. The specific techniques (CRDTs, GossipSub, cryptographic proofs) are overkill for a single-machine context, but simpler primitives (SQLite, webhooks, tests + review) deliver the same compound learning property.

The critical path is clear:
1. **P0: Close the feedback loop** (Skaffen Compound → persistent store)
2. **P0: Fix infrastructure blockers** (fleet-registry schema, interlock force-release)
3. **P1: Wire the data** (quality signals, mutation store, plugin quality scores)
4. **P2+: Compound** (inspiration-before-hypothesis, multi-agent learning sharing)

The estimated total effort: **6-8 weeks for core P0/P1 work**, with clear value milestones at each stage.
