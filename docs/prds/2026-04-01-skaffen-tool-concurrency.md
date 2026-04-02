---
artifact_type: prd
bead: sylveste-18a.1
stage: design
---

# PRD: Per-Invocation Tool Concurrency Classification

## Problem

Skaffen's agentloop executes all tool calls sequentially, even when multiple calls in the same turn are read-only and independent. A turn with 5 `grep` calls takes 5x as long as necessary. Claude Code's production implementation shows that per-invocation concurrency classification with batch partitioning is both safe and significant for throughput.

## Solution

Add an optional `ConcurrencyClassifier` interface to the tool system. Each tool classifies whether a specific invocation (based on its input) is safe for concurrent execution. The agentloop orchestrator partitions a turn's tool calls into parallel (safe) and serial (unsafe) batches, executing safe batches concurrently with pre-allocated result slots to preserve ordering.

## Features

### F1: ConcurrencyClassifier Optional Interface

**What:** Define `ConcurrencyClassifier` interface in `tool/tool.go` and implement on all built-in tools.

**Acceptance criteria:**
- [ ] `ConcurrencyClassifier` interface defined: `ConcurrencySafe(params json.RawMessage) bool`
- [ ] `read`, `glob`, `grep`, `ls`, `web_fetch`, `web_search` return `true` unconditionally
- [ ] `write`, `edit` return `false` unconditionally
- [ ] `bash` parses command prefix against known-safe set (`cat`, `head`, `tail`, `git log`, `git status`, `git diff`, `ls`, `find`, `wc`, `grep`, `rg`)
- [ ] `bash` returns `false` if shell metacharacters detected (`&&`, `||`, `;`, `|`, `$()`, backticks) regardless of first token
- [ ] `BashCommandSafe(command string) bool` is a package-level function in `tool/bash.go`, not embedded in the method
- [ ] Tools not implementing `ConcurrencyClassifier` default to `false` (conservative)
- [ ] All existing tests pass

### F2: Three-Phase Tool Execution Orchestrator

**What:** Replace sequential `executeToolsWithCallbacks` with a three-phase model: serial gate → parallel execute → serial collect.

**Acceptance criteria:**
- [ ] `partitionToolCalls` function groups consecutive safe calls into parallel batches and unsafe calls into serial singletons
- [ ] Phase 1 (gate): hooks + approval run serially for all calls before execution begins
- [ ] Phase 2 (execute): safe batches launch goroutines with pre-allocated `[]ToolResult` slots (index-based, no append)
- [ ] Phase 3 (collect): results drained in original call order, `streamCB` events emitted sequentially
- [ ] Concurrency limit: named constant `maxParallelToolCalls = 10`
- [ ] `ToolApprover` never called from a goroutine (remains serial)
- [ ] Tool result ordering matches tool call ordering (Anthropic API contract preserved)
- [ ] `StreamToolStart` events emitted before goroutine launch (serial), `StreamToolComplete` emitted in collect phase (serial)
- [ ] No new direct dependencies (use `sync.WaitGroup` + semaphore channel, not errgroup)

### F3: Error Cascading via PropagatesErrorToSiblings

**What:** Optional interface for tools whose errors should cancel sibling goroutines in the same batch.

**Acceptance criteria:**
- [ ] `PropagatesErrorToSiblings() bool` optional interface defined in `agentloop/types.go`
- [ ] `BashTool` implements it returning `true`; no other built-in tools implement it
- [ ] Within a parallel batch, tools with `PropagatesErrorToSiblings` share a cancellable context
- [ ] Non-propagating tools (read, grep, etc.) receive the parent context — a bash error does not cancel them
- [ ] No tool name strings (`"bash"`) appear in `agentloop/` — identity is via interface, not name
- [ ] Cancelled siblings receive synthetic error results, not missing results

### F4: toolBridge Forwarding

**What:** Update `agent/agent.go` toolBridge to forward both optional interfaces from inner `tool.Tool` to `agentloop.Tool`.

**Acceptance criteria:**
- [ ] `toolBridge.ConcurrencySafe` delegates via type assertion on `b.inner`
- [ ] `toolBridge.PropagatesErrorToSiblings` delegates via type assertion on `b.inner`
- [ ] Unimplemented inner tools return conservative defaults (`false` for safe, `false` for propagates)
- [ ] MCP tools (which don't implement either interface) get correct defaults through this path

## Non-goals

- Streaming tool execution (executing tools as API response streams — that's sylveste-18a.2)
- MCP tool self-declaration of concurrency safety (future: when MCP spec adds metadata)
- Configurable concurrency limit (hardcode 10 until evidence shows otherwise)
- `IsReadOnly` as separate method (`GateConstraint.RateLimit` handles rate-limited read-only tools)

## Dependencies

- Masaq viewport fix (done — masaq `ScrollTo` landed)
- No external dependencies needed — `sync.WaitGroup` + semaphore channel, no errgroup promotion

## Open Questions

- Should `GatedRegistry` in `agent/gated_registry.go` be removed first? (Audit needed — may be dead code)
- Should `PostToolUse` hook goroutines be bounded under parallel execution? (Currently unbounded — acceptable for ≤10 concurrent tools)
