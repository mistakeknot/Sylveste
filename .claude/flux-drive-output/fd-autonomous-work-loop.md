# fd-autonomous-work-loop: Hyperspace AGI Work Loop Analysis

> Reviewer: fd-autonomous-work-loop (AI systems architect, autonomous agent loop design)
> Source: `research/agi-hyperspace/ANALYSIS.md` + `research/agi-hyperspace/README.md`
> Grounded against: Skaffen (`os/Skaffen/`), Autarch (`apps/Autarch/`), interlab (`interverse/interlab/`), Clavain (`os/Clavain/`)

---

## 1. Hyperspace 5-Stage Pipeline Mapped onto Skaffen's OODARC

### Current State

Skaffen implements OODARC as a 6-phase FSM defined in `os/Skaffen/internal/agent/phase.go`:

```
Observe → Orient → Decide → Act → Reflect → Compound
```

The actual loop in `os/Skaffen/internal/agentloop/loop.go` (lines 111-244) implements a **Decide-Act loop** — it calls the LLM, executes tool calls, emits evidence, and saves turns. The higher-level OODARC phases are imposed by `os/Skaffen/internal/agent/agent.go` via the `phaseFSM`, which gates tool availability per phase.

Hyperspace's 5-stage pipeline is:

```
Hypothesis → Training → Paper → Critique → Discovery
```

### Mapping

| Hyperspace Stage | OODARC Phase | Status in Skaffen | Gap |
|---|---|---|---|
| **Inspiration** (read peers' discoveries) | Observe/Orient | **MISSING** — Skaffen loads context from session resume and system prompt, but does NOT proactively query auto-memory, intersearch, or peer session data before planning | Skaffen starts cold each session |
| **Hypothesis** (generate mutation) | Orient/Decide | **Partially implemented** — The LLM generates a plan, but there is no mutation registry or "best approach so far" to mutate from | Each task starts from scratch |
| **Training** (run experiment) | Act | **Implemented** — Tool execution via `agentloop/loop.go` lines 172-175 | Functional |
| **Paper** (synthesize findings) | Reflect | **Minimal** — Evidence emission (`evidence/emitter.go`) writes JSONL per turn. No cross-session synthesis. | Evidence is raw, not synthesized |
| **Critique** (peer scoring) | (none) | **Handled externally** — Clavain's `interflux` does multi-agent review. Skaffen has no self-critique. | No closed-loop quality signal back to Skaffen |
| **Discovery** (feed back into hypothesis) | Compound | **Stub** — The Compound phase exists in the FSM but the PRD (`docs/prds/2026-03-11-skaffen-go-rewrite.md` line 62) marks phase boundary detection as "deferred to v0.2." The compound phase currently has `{read, glob, ls, bash}` tools but no structured compounding behavior. | This is the critical missing piece |

### Key Finding: The Feedback Loop Does Not Close

Skaffen's OODARC has all the phases, but the **Reflect and Compound phases do not feed back into future sessions**. Evidence is emitted to JSONL files (`~/.skaffen/evidence/<session_id>.jsonl`) and optionally bridged to intercore, but:

1. No future session reads evidence from past sessions
2. No mechanism synthesizes patterns across sessions
3. No "best approach" is maintained per task type
4. The Compound phase has no compounding behavior

By contrast, Hyperspace's Discovery stage explicitly feeds scored results back into the next Hypothesis stage. This is the closed loop that Sylveste is missing.

**Priority: P0** — Without this, Skaffen cannot compound learning. Every session is independent.

---

## 2. Mutation Over Regeneration

### The Hyperspace Pattern

Hyperspace agents maintain a `best.json` per project — the current best configuration. Each new experiment mutates this baseline rather than starting fresh. The overnight report shows 14 mutation types applied across 333 experiments. When one agent discovers that Kaiming initialization helps, 23 others adopt it via gossip.

### Current Sylveste State

Skaffen has **no mutation history**. Each invocation receives a task via prompt and generates a fresh approach. The session system (`os/Skaffen/internal/session/session.go`) persists conversation turns in JSONL, supporting session resume (`Load()`, line 93) and forking (`Fork()`, line 219), but these are conversation-level persistence, not approach-level persistence.

interlab gets closest with its `State` struct (`interverse/interlab/internal/experiment/state.go` lines 44-57) that tracks `BestMetric`, `BaselineMetric`, and `ConsecutiveNoImprove`. But interlab is scoped to benchmark optimization — it tracks numerical metrics, not code approaches.

### Concrete Proposal: Mutation History Data Structure

```json
// ~/.skaffen/mutations/<task-type>.jsonl
// One line per approach, append-only

// First entry: baseline
{"type":"baseline","task_type":"bug-fix","approach":"reproduce → diagnose → fix → test","outcome":"success","quality_signals":{"tests_pass":true,"review_score":null,"time_to_fix_ms":340000},"session_id":"abc123","timestamp":"2026-03-14T10:00:00Z"}

// Mutation: improve on baseline
{"type":"mutation","task_type":"bug-fix","approach":"reproduce → failing test → fix → verify → regression test","parent":"abc123","mutation":"added failing test before fix","outcome":"success","quality_signals":{"tests_pass":true,"review_score":8,"time_to_fix_ms":280000,"regression_prevented":true},"session_id":"def456","timestamp":"2026-03-14T14:00:00Z"}

// Mutation: another variant
{"type":"mutation","task_type":"bug-fix","approach":"reproduce → failing test → root-cause analysis → fix → verify","parent":"def456","mutation":"added explicit root-cause step","outcome":"success","quality_signals":{"tests_pass":true,"review_score":9,"time_to_fix_ms":310000,"root_cause_documented":true},"session_id":"ghi789","timestamp":"2026-03-14T18:00:00Z"}
```

**Task types** to track (derived from beads issue types and Clavain sprint patterns):

| Task Type | Mutation Dimensions | Primary Quality Signal |
|---|---|---|
| `bug-fix` | diagnosis strategy, test-first vs fix-first, root-cause depth | time-to-fix + regression prevention |
| `feature` | decomposition strategy, API-first vs impl-first, test coverage | review score + completeness |
| `refactor` | scope strategy, incremental vs big-bang, test preservation | test stability + diff size |
| `optimization` | profiling strategy, metric selection, iteration depth | metric improvement % (interlab native) |
| `docs` | audience, structure template, example depth | accuracy + completeness |

**Where this lives in the architecture**: New package `os/Skaffen/internal/mutations/` with:
- `store.go` — JSONL append/reconstruct (same pattern as interlab's `state.go`)
- `best.go` — Returns the best approach for a task type, computed from quality signals
- `mutate.go` — Generates mutation suggestions from the current best (injected into Orient phase context)

**Integration point**: The `sessionAdapter.SystemPrompt()` method (`os/Skaffen/internal/agent/agent.go` line 271) should inject the current best approach for the detected task type into the system prompt during Orient/Decide phases.

**Priority: P1** — High value but requires the P0 feedback loop first. Without quality signals flowing back, there is nothing to select "best" from.

---

## 3. Inspiration-Before-Hypothesis

### The Hyperspace Pattern

Before generating their next hypothesis, Hyperspace agents read peers' discoveries via GossipSub. "When one agent discovered Kaiming initialization helped, 23 others adopted it within hours."

### Current Sylveste State

Skaffen does NOT check what other sessions or agents have learned before starting work. The session start flow is:

1. `cmd/skaffen/main.go` parses flags, creates provider/registry/router
2. `agent.New()` constructs the agent with injected deps
3. `agent.Run()` or TUI starts — goes directly to the LLM

Clavain's `session-start.sh` hook injects context via `additionalContext`, but this is Clavain's hook, not Skaffen's. Skaffen's own hooks system (`os/Skaffen/internal/hooks/`) provides pre/post tool-use hooks, not session lifecycle hooks.

The pieces that COULD provide inspiration already exist:
- **auto-memory** (`~/.claude/projects/.../memory/MEMORY.md`) — accumulated lessons
- **intersearch** (`interverse/intersearch/`) — embedding-based search across session data
- **CASS** (`~/.local/bin/cass`) — indexes 10K+ sessions, supports `cass search --robot`
- **beads state** (`bd state`) — what has been tried on related beads

### Recommendation

Add a pre-session "inspiration" step to Skaffen's Orient phase:

1. Detect task type from the user's prompt
2. Query mutations store for best approach to this task type
3. Query CASS for sessions that worked on similar tasks: `cass search "<task description>" --robot --limit 3`
4. Read auto-memory topic files relevant to the project
5. Inject this context into the system prompt via `SessionPrompt()`

This maps to Skaffen's existing architecture: the `Orient` phase already has read-only tools (`{read, glob, grep, ls}`). The inspiration step would be a structured preamble before the LLM sees the task.

**Implementation**: Add to `os/Skaffen/internal/session/priompt_session.go` — the priompt system already supports priority-weighted prompt sections with phase-boost. Inspiration context gets medium priority, boosted during Orient, shed first when context is tight.

**Priority: P1** — Directly enables compound learning. Depends on mutation store (P1) for full value but independently useful with just CASS + auto-memory.

---

## 4. JOURNAL.md vs Auto-Memory

### Hyperspace's JOURNAL.md

Each agent maintains a cognitive journal alongside experiments:
```
projects/<project>/agents/<peerId>/JOURNAL.md
```
A running narrative of what worked, what didn't, and why. Per-agent, per-project. Written by the agent itself.

### Sylveste's Auto-Memory

Auto-memory is per-project, shared across all sessions. Lives at:
```
~/.claude/projects/-home-mk-projects-Sylveste/memory/MEMORY.md
```
Plus topic files (`beads-troubleshooting.md`, `interspect.md`, `plugins.md`, etc.) linked from MEMORY.md's Topic Files section. Governed by `~/.claude/memory-conventions.md` — provenance dating, proactive recording, one-line lessons with context.

### Structural Comparison

| Dimension | JOURNAL.md | Auto-Memory |
|---|---|---|
| Scope | Per agent, per project | Per project, shared across sessions |
| Format | Running narrative | Structured sections (Quick Reference, Gotchas, Topic Files) |
| Authorship | Written by agent | Written by agent, verified by system |
| Persistence | In git branch (per-agent) | On local filesystem |
| Discoverability | Must know agent ID | Always loaded at session start |
| Evolution | Append-only narrative | Editable, reorganized |

### Assessment

**Auto-memory is the right model for Sylveste. JOURNAL.md would be a regression.**

Reasons:

1. **Single-operator context**: Sylveste has one human operator. JOURNAL.md's per-agent isolation makes sense for Hyperspace (different operators, different trust levels) but creates fragmentation in Sylveste. The operator wants a single source of truth, not N journals to cross-reference.

2. **Auto-memory already compounds**: The topic file pattern (`MEMORY.md` links to `beads-troubleshooting.md`, `plugins.md`, etc.) provides structured categorization that JOURNAL.md's flat narrative lacks. Lessons are findable.

3. **JOURNAL.md lacks structure**: A running narrative is hard to query programmatically. Auto-memory's structured format (dated entries, topic sections) is machine-parseable.

4. **However**: Auto-memory lacks one thing JOURNAL.md has — **per-task narrative continuity**. A JOURNAL.md entry for a bug fix tells the whole story: "tried X, it failed because Y, then tried Z which worked." Auto-memory captures the conclusion ("do Z because Y breaks X") but loses the investigation narrative.

### Recommendation: Hybrid — Keep Auto-Memory, Add Session Transcripts

The `/reflect` command in Clavain (`os/Clavain/commands/reflect.md` lines 55-66) already exports session transcripts via CASS:

```bash
cass export "$session_file" --format markdown -o "${transcript_dir}/<sprint_id>-transcript.md"
```

This IS the journal — but scoped to sprints, not to Skaffen sessions. Extend this:

1. **Auto-memory** remains the structured lesson store (unchanged)
2. **Session transcripts** (CASS markdown exports) serve as the narrative journal
3. **Mutations store** (new, from section 2) serves as the approach evolution record
4. **CASS search** makes transcripts discoverable without reading them sequentially

No need for JOURNAL.md. The combination of auto-memory + CASS transcripts + mutations store covers all three purposes (structured lessons, investigation narrative, approach evolution) better than a single flat journal.

**Priority: P3** — Auto-memory already works. The gap (narrative continuity) is covered by CASS transcript export, which already exists in Clavain's reflect command.

---

## 5. Single-Metric vs Multi-Dimensional Quality

### The Philosophical Gap

Hyperspace optimizes a **single scalar**: `val_loss`, `NDCG@10`, `Sharpe ratio`, `test_pass_rate`. This enables clean "is new better than old?" comparisons and automated leaderboards.

Sylveste's quality criteria are **multi-dimensional and partially subjective**:
- Tests pass (binary)
- Code correctness (requires reasoning)
- Code readability (subjective)
- Performance (measurable but not always relevant)
- Security (requires domain knowledge)
- Design consistency (requires project context)
- Diff reviewability (depends on reviewer)

The ANALYSIS.md correctly identifies this as the core divergence (lines 199-203): "Real software development has multi-dimensional quality (correctness, readability, performance, security). Sylveste should resist reducing code quality to a single metric."

### What Autarch Should Use

Autarch's Mycroft (`apps/Autarch/internal/mycroft/`) already has the scaffolding for richer signals:

1. **DispatchOutcome** (`types.go` line 76): `accepted | rejected | success | failure` — but this is binary, not scored
2. **FailureClass** (`types.go` line 47): `healthy | clean | dirty | degraded | corrupted` — failure taxonomy exists but success taxonomy does not

Recommended quality signal structure for Autarch/Skaffen feedback loops:

```go
// QualitySignal captures multi-dimensional outcome of a completed task.
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
    CircuitBreakers int     `json:"circuit_breakers_hit"` // from interlab

    // Human signals (high-value, sparse)
    ReviewScore     *int    `json:"review_score,omitempty"`     // 1-10 from flux-drive or human
    Accepted        *bool   `json:"accepted,omitempty"`         // human accepted the change
    RevisionCount   int     `json:"revision_count"`             // how many times reworked

    // Composite (derived)
    Efficiency      float64 `json:"efficiency"`                 // quality per token spent
}
```

**Key insight**: Do NOT reduce this to a single score. Instead, use **Pareto dominance** for mutation selection: approach A is better than approach B if it is better on at least one dimension and not worse on any. This avoids the reductionism trap while still enabling automated comparison.

interlab's `Result.SecondaryMetrics` (`interverse/interlab/internal/experiment/state.go` line 38) already supports multi-dimensional metrics — extend this to code quality signals.

**Priority: P1** — Without richer quality signals, the mutation store (P1) has nothing meaningful to select "best" from. Tests-pass is necessary but insufficient.

---

## 6. DiLoCo's "Work Locally, Share Deltas" for Multi-Skaffen

### The Pattern

DiLoCo: each agent trains locally for H steps, then shares compressed weight deltas. Automatic fallback to solo if no peers available.

### Current Sylveste State

Multiple Skaffen instances are coordinated today through:
- **interlock** (`interverse/interlock/`) — file-based reservation system for exclusive file access
- **Mycroft** (`apps/Autarch/internal/mycroft/`) — patrol loop that checks agent health every 30s, work queue every 60s (`patrol/patrol.go` lines 18-19)
- **Clavain dispatch** (`os/Clavain/scripts/dispatch.sh`) — spawns agents with codex exec, state tracking via interband sideband

The coordination model is **task-level partitioning**: each agent gets a separate bead (task), works independently, commits independently. There is no mechanism for multiple agents to collaborate on the same task.

### Assessment

DiLoCo's pattern is architecturally interesting but **premature for code generation**:

1. **Code is not differentiable** — You cannot meaningfully "average" two different code changes the way you can average weight deltas. Code merges require semantic understanding.

2. **interlock already handles the easy case** — File-level partitioning (agent A owns files X,Y; agent B owns files Z,W) is sufficient for most parallel work.

3. **The valuable pattern is "share learnings, not work products"** — What DiLoCo gets right is periodic synchronization. Multiple Skaffen instances working on related tasks should share their discoveries (via auto-memory or a shared mutations store) without sharing their code changes.

### Recommendation

Implement **delta-sharing at the learning level**, not the code level:

1. When a Skaffen session completes a task, it writes a mutation record (section 2) and auto-memory entries
2. Other Skaffen sessions check these before starting work (section 3, inspiration-before-hypothesis)
3. The mutations store acts as the "compressed delta" — it encodes what worked, not the full code

This maps to interlock's existing `broadcast_message` tool — sessions can broadcast discoveries to all peers. But the message content needs structure (mutation records) rather than free-form text.

**Priority: P2** — Useful for multi-agent scenarios but works today via auto-memory. The structured mutations store would make this more systematic.

---

## Summary: Priority Matrix

| # | Recommendation | Priority | Depends On | Effort |
|---|---|---|---|---|
| 1 | **Close the feedback loop**: Skaffen's Compound phase must write structured quality signals back to a persistent store that future Orient phases read | P0 | — | Medium (new `mutations/` package, integration with session lifecycle) |
| 2 | **Multi-dimensional quality signals**: Define `QualitySignal` struct with hard/soft/human dimensions, use Pareto dominance not scalar reduction | P1 | — | Low (type definition + collection hooks) |
| 3 | **Mutation history store**: JSONL-based per-task-type approach tracking with best-approach selection | P1 | P0, #2 | Medium (new package, same pattern as interlab's state.go) |
| 4 | **Inspiration-before-hypothesis**: Orient phase queries mutations store + CASS + auto-memory before planning | P1 | #3 | Medium (priompt integration, CASS/intersearch queries) |
| 5 | **Keep auto-memory, skip JOURNAL.md**: Existing auto-memory + CASS transcripts + mutations store covers all use cases | P3 | — | None (maintain status quo) |
| 6 | **Learning-level delta sharing**: Broadcast mutation records via interlock, not code deltas | P2 | #3 | Low (interlock message format + broadcast hook) |

### The Critical Missing Piece

The single most important gap is **#1: the feedback loop does not close**. Skaffen emits evidence (JSONL per turn, intercore bridge) but no future session reads it. The Compound phase exists in the FSM but has no compounding behavior. interlab's campaign system closes its loop within a single campaign (circuit breakers, best metric tracking) but this does not extend to Skaffen's general work loop.

The fix is architectural, not incremental: Skaffen's `Compound` phase must write to a persistent store, and Skaffen's `Orient` phase must read from it. The mutations store (recommendation #3) is the natural data structure for this, but even a simpler approach — writing structured summaries to auto-memory topic files — would be a significant improvement over the current state where the Compound phase does nothing.

### Philosophical Alignment Note

Hyperspace's narrow-metric optimization is the wrong model for Sylveste to copy directly. But the **mechanism** — track what worked, mutate the best, share discoveries — is exactly right. The adaptation is to replace scalar leaderboards with multi-dimensional quality profiles and Pareto-based selection. This preserves the compound learning property while respecting the complexity of software quality.
