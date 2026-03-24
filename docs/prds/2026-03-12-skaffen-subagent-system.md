---
artifact_type: prd
bead: Demarch-6i0.18
stage: design
---

# PRD: Skaffen Subagent System (Phase 1)

## Problem

Skaffen executes tools serially — one tool per LLM turn, no parallel operations. All 5 competitors ship subagent systems (CC: 5+ types, Codex: 6 threads, Gemini/OpenCode: 4+ each, Amp: 6 types). This limits Skaffen to sequential workflows where competitors can fan out reads, delegate focused tasks, and parallelize independent work.

## Solution

Add a subagent system to Skaffen where each subagent is a fresh `agentloop.Loop` goroutine with scoped context. Ships with two built-in types (Explore, General) and a type registry for custom types. The LLM invokes subagents via an Agent tool registered in the tool system. Write-capable subagents coordinate via Intercore file reservations. Results appear as inline collapsible blocks in the TUI.

## Features

### F1: SubagentRunner — Goroutine lifecycle management

**What:** Core runtime that spawns, monitors, collects results from, and cancels subagent goroutines.

**Acceptance criteria:**
- [ ] `SubagentRunner.Run(ctx, []SubagentTask) ([]SubagentResult, error)` spawns N goroutines concurrently
- [ ] Configurable max concurrent subagents (default: 5, per `.skaffen/config.toml`)
- [ ] Context cancellation propagates to all running subagents
- [ ] Individual subagent timeout (configurable per SubagentType, default: 120s)
- [ ] Results collected via channels; partial results returned if some subagents fail
- [ ] `SubagentResult` includes: response text, token usage, turn count, error, evidence events
- [ ] Runner emits status callbacks: `SubagentStarted`, `SubagentProgress`, `SubagentDone`, `SubagentFailed`

### F2: Type Registry — Subagent type definitions

**What:** Registry that loads subagent type definitions from `.skaffen/agents/` config directory and provides built-in Explore and General types.

**Acceptance criteria:**
- [ ] Built-in `explore` type: tools=[Read, Grep, Glob, Ls], read_only=true, max_turns=10, model=inherit
- [ ] Built-in `general` type: tools=[all], read_only=false, max_turns=25, model=inherit
- [ ] Custom types loaded from `.skaffen/agents/<name>.toml` at startup
- [ ] Type definition schema: name, description, tools (whitelist), system_prompt, max_turns, token_budget, read_only, model (optional override)
- [ ] `TypeRegistry.Get(name) (SubagentType, error)` for lookup
- [ ] `TypeRegistry.List() []SubagentType` for discovery (used by Agent tool schema)
- [ ] Invalid type definitions logged and skipped (don't crash startup)

### F3: ScopedSession — Context isolation with selective injection

**What:** Per-subagent session wrapper that provides scoped context instead of inheriting the full parent conversation.

**Acceptance criteria:**
- [ ] Each subagent gets: system prompt (from type definition) + task prompt (from parent)
- [ ] Optional context injection: parent can pass selected messages, bead descriptions, file contents
- [ ] Implements `agentloop.Session` interface (SystemPrompt, Save, Messages)
- [ ] Subagent messages are isolated — don't pollute parent session
- [ ] System prompt template supports `{{.TaskPrompt}}`, `{{.InjectedContext}}`, `{{.BeadDescription}}` placeholders
- [ ] Context injection is capped at configurable token limit (default: 4096 tokens) to prevent bloat

### F4: Agent Tool — LLM-invocable subagent dispatch

**What:** A tool registered in Skaffen's tool system that the LLM can call to spawn subagents, like CC's Agent tool.

**Acceptance criteria:**
- [ ] Registered as `Agent` in the tool registry, available in all OODARC phases
- [ ] Input schema: `{ "subagent_type": string, "prompt": string, "description": string, "context"?: string[], "file_patterns"?: string[] }`
- [ ] `subagent_type` validated against TypeRegistry; error if unknown type
- [ ] `description` (3-5 words) shown in TUI as subagent label
- [ ] `context` array: optional message IDs or content strings to inject into subagent session
- [ ] `file_patterns` array: glob patterns for Intercore reservation (only for write-capable types)
- [ ] Multiple Agent tool calls in a single LLM turn spawn concurrently (not sequentially)
- [ ] Tool result contains subagent's final response text (collapsed in tool result)
- [ ] Tool result includes token usage metadata for budget tracking

### F5: Intercore Reservation Bridge — Write coordination

**What:** Bridge between subagent system and Intercore's file reservation API for write-capable subagents.

**Acceptance criteria:**
- [ ] Before a write-capable subagent starts, `ic coordination reserve` is called with declared file patterns
- [ ] If reservation conflicts with another agent's lock, subagent spawn fails with descriptive error
- [ ] Reservation TTL matches subagent timeout (auto-released on completion or failure)
- [ ] `ic coordination release` called on subagent completion (success or failure)
- [ ] Read-only subagents (Explore type) skip reservation entirely
- [ ] Reservation failure for one subagent doesn't block other subagents in the same batch
- [ ] Falls back gracefully if `ic` binary is not available (warn, proceed without reservation)

### F6: TUI Inline Collapsible Blocks — Subagent output display

**What:** Masaq component for rendering subagent results as inline collapsible blocks in the chat viewport.

**Acceptance criteria:**
- [ ] Each subagent result renders as a collapsible block: `[+] <description> (done, 1.2k tokens)` collapsed / `[-] <description>` expanded
- [ ] Running subagents show spinner: `[~] <description> (running, turn 3/10)`
- [ ] Failed subagents show error indicator: `[!] <description> (failed: timeout)`
- [ ] Expand/collapse toggled by clicking or keyboard shortcut (Enter on focused block)
- [ ] Multiple concurrent subagents render as stacked blocks with live status updates
- [ ] Collapsed view shows: description, status, token usage, turn count
- [ ] Expanded view shows: full subagent response rendered as markdown

### F7: AggregatingEmitter — Evidence stream merge

**What:** Emitter wrapper that collects evidence events from all subagents and merges them into the parent's evidence stream.

**Acceptance criteria:**
- [ ] Each subagent's evidence events are tagged with `subagent_id` and `subagent_type`
- [ ] Events buffered during subagent execution, flushed to parent emitter on completion
- [ ] Deduplication: identical evidence from multiple subagents (e.g., same file read) emitted once
- [ ] Parent evidence stream maintains chronological ordering across subagent events
- [ ] Evidence includes subagent lifecycle events: spawn, complete, fail (for session replay)
- [ ] Total token usage aggregated across all subagents and reported to Router for budget tracking

## Non-goals

- **Phase 2 features:** Autonomous multi-turn delegates, tab-per-subagent TUI, inter-subagent messaging, spawn depth limits
- **Git worktree isolation:** Write safety handled by Intercore reservations, not worktrees
- **Subprocess isolation:** Subagents run as goroutines in the same process
- **Cross-session subagents:** Subagents are ephemeral within a single parent turn
- **Subagent approval gates:** Phase 1 subagents auto-approve tool calls based on type definition. Interactive approval deferred.

## Dependencies

- **Intercore coordination API** (`ic coordination reserve/release/check`) — already built, used via CLI bridge
- **agentloop.Loop** — existing, reused as-is (no modifications needed)
- **Masaq viewport** — existing, extended for collapsible block rendering
- **Provider connection** — subagents share parent's provider instance or create new ones

## Open Questions

1. **Model routing for subagents:** Should Explore default to Haiku (cheaper, faster) and General inherit parent's model? Or all inherit?
2. **Budget enforcement:** If parent has 100k tokens remaining, how much does each subagent get? Equal split? First-come-first-served from shared pool?
3. **Cancellation UX:** Ctrl+C during subagent execution — cancel all subagents, or cancel one-at-a-time?
