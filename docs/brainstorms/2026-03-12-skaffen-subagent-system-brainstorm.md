---
artifact_type: brainstorm
bead: Sylveste-6i0.18
stage: discover
---

# Subagent System for Skaffen

**Bead:** Sylveste-6i0.18

## What We're Building

A subagent system that lets Skaffen spawn parallel child agents for concurrent task delegation. Phase 1 delivers parallel tool execution (Explore + General subagent types) with an LLM-invocable Agent tool. Phase 2 (future) adds autonomous multi-turn delegates.

### Competitive Context

All 5 competitors ship subagents:
- **Claude Code:** 5+ built-in types (general-purpose, Explore, Plan, etc.), background execution, worktree isolation
- **Codex CLI:** 6 concurrent threads, `/agent` command to switch between them
- **Gemini CLI:** 4 built-in + custom subagent types
- **OpenCode:** 4 built-in + custom types
- **Amp:** 6 subagent types

Skaffen has zero subagent capability today. This is a P1 competitive gap.

## Why This Approach

### Architecture: agentloop-native subagents

Each subagent is a fresh `agentloop.Loop` instance running in a goroutine. This reuses Skaffen's proven Decide-Act loop without duplication.

**Rationale:**
- `agentloop` is already phase-agnostic and interface-first (Router, Session, Emitter are all swappable)
- TUI-agent goroutine communication via channels is battle-tested
- No new process model needed — goroutines are cheap, context-cancellable
- Provider connections can be shared (connection pooling) or per-subagent

**Rejected alternatives:**
- Subprocess isolation (too heavy, duplicate provider connections, harder context injection)
- Provider-level parallelism only (no multi-turn, no independent tool execution)

### Context Model: Scoped + selective injection

Subagents get a scoped context by default:
- System prompt (from subagent type definition)
- Task-specific prompt from parent
- Optionally injected context: selected parent messages, bead descriptions, relevant prior tool results
- No full conversation history (prevents context bloat, reduces token cost)

The parent (or an intermediary subagent) curates what context to inject. Bead associations provide domain awareness.

### Write Safety: Intercore file reservations (no worktrees)

- **Explore subagents** (read-only): no coordination needed, run freely in parallel
- **General subagents** (write-capable): use `ic coordination reserve` with glob patterns before writing
- Leverages Intercore's existing `BEGIN IMMEDIATE` serializable transactions + glob overlap detection
- Bridges to Intermute for cross-agent visibility
- No git worktrees — explicit design decision to keep the system simpler and aligned with Sylveste's existing coordination patterns

### Extensibility: Type registry from day one

Subagent types defined in `.skaffen/agents/` config directory. Each type specifies:
- Tool whitelist (which tools the subagent can use)
- System prompt template
- Max turns / token budget
- Read-only flag (skips Intercore reservation)

Ships with Explore + General built-in. MCP servers and skills can register custom types via the registry API.

### TUI Integration: Inline collapsible blocks

Phase 1: Subagent output appears inline in chat as collapsible blocks (header: status, expand: full output). Reuses viewport rendering.

Phase 2 (future): Tab-per-subagent in masaq tabbar for richer inspection.

### Agent Tool: LLM-invocable

An `Agent` tool registered in the tool system allows the LLM to decide when to spawn subagents. Input schema includes: subagent type, task prompt, optional context injection, optional file reservation patterns.

## Key Decisions

1. **Phased delivery:** Phase 1 = parallel tools + Agent tool. Phase 2 = autonomous multi-turn delegates.
2. **No worktrees:** Write safety via Intercore's glob-based file reservations, not git worktree isolation.
3. **Scoped context with selective injection:** Subagents don't inherit full conversation. Parent curates injected context + bead associations.
4. **Type registry from day one:** `.skaffen/agents/` config enables custom subagent types. Ships with Explore + General.
5. **Inline collapsible TUI:** Subagent results shown as expandable blocks in chat. Tabs deferred to Phase 2.
6. **agentloop-native:** Each subagent is a goroutine running `agentloop.Loop`. No subprocess isolation.

## Open Questions

1. **Concurrency limits:** What's the default max concurrent subagents? Configurable per-type or global?
2. **Budget allocation:** How does the parent's token budget split across subagents? Fixed per-subagent or shared pool?
3. **Cancellation UX:** How does the user cancel a running subagent? Ctrl+C kills all, or per-subagent cancel?
4. **Evidence aggregation:** How do subagent evidence events (JSONL) merge with parent's evidence stream?
5. **Model routing:** Do subagents use the parent's model, or can types specify their own (e.g., Explore uses Haiku, General uses Sonnet)?
6. **Approval gates:** Do subagent tool calls go through the TUI's approval system, or are they auto-approved based on type trust level?

## Package Structure (Proposed)

```
os/Skaffen/internal/
  subagent/
    runner.go      — SubagentRunner: spawn, collect, cancel goroutines
    registry.go    — TypeRegistry: load from .skaffen/agents/, built-in types
    types.go       — SubagentTask, SubagentResult, SubagentType
    session.go     — ScopedSession: isolated per-subagent session with context injection
    emitter.go     — AggregatingEmitter: buffers evidence, merges to parent
    tool.go        — AgentTool: registered in tool system, LLM-invocable
    reservation.go — Intercore bridge: reserve/release files for write-capable subagents
```

## Phase 2 Sketch (Future)

- Autonomous multi-turn delegates with their own conversation loops
- Per-subagent tabs in masaq tabbar
- Inter-subagent messaging via Intermute
- Subagent-to-subagent delegation (spawn depth limits via Intercore's dispatch tracking)
