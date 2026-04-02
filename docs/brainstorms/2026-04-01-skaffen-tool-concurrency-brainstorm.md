---
artifact_type: brainstorm
bead: sylveste-18a.1
stage: discover
---

# Per-Invocation Tool Concurrency Classification

## What We're Building

Extend Skaffen's tool system so each tool call is classified as concurrency-safe or not based on its actual input, then partition a turn's tool calls into parallel (safe) and serial (unsafe) batches. Currently `agentloop.executeToolsWithCallbacks` runs all tool calls sequentially. After this change, consecutive safe calls (read, glob, grep, ls, and bash commands like `cat`, `git log`) execute in parallel, while unsafe calls (write, edit, bash mutations) run serially.

This is a direct port of Claude Code's `isConcurrencySafe(input)` pattern from `Tool.ts:402` and `toolOrchestration.ts:91-116`, adapted to Go's type system and Skaffen's two-registry architecture.

## Why This Approach

**Approach A: Extend the core Tool interface** was chosen over optional interface assertion (B) or registry-level policy (C).

Rationale: every tool should explicitly declare its concurrency behavior. This makes the contract visible in the interface, forces authors of new tools (including MCP bridge tools) to consider concurrency, and keeps classification logic co-located with execution logic. The cost — updating every existing tool — is low (12 built-in tools, most are trivially safe or unsafe).

## Key Decisions

**1. Both registries get the method.** `agentloop.Tool` and `tool.Tool` both add `IsConcurrencySafe(params json.RawMessage) bool`. The agentloop registry is where the orchestrator lives, but the OODARC-level tool.Registry delegates to the same interface.

**2. Orchestrator lives in agentloop.** A new `partitionToolCalls` function in `agentloop/loop.go` groups consecutive safe calls into parallel batches and unsafe calls into serial singletons, matching Claude Code's `toolOrchestration.ts:91-116` algorithm. The `executeToolsWithCallbacks` method calls this partitioner before executing.

**3. Parallel execution uses errgroup.** Safe batches launch goroutines via `golang.org/x/sync/errgroup` (already a transitive dep) with a configurable concurrency limit (default 10, matching Claude Code). Results are collected in order regardless of completion order.

**4. Tool-level classification rules:**
- `read`, `glob`, `grep`, `ls`: always safe (return `true` unconditionally)
- `write`, `edit`: always unsafe (return `false`)
- `bash`: input-dependent — parse the command prefix. Read-only commands (`cat`, `head`, `tail`, `git log`, `git status`, `git diff`, `ls`, `find`, `wc`, `grep`) are safe. Anything else is unsafe. Conservative: unknown commands default to unsafe.
- `web_fetch`, `web_search`: safe (read-only network calls)
- MCP tools: default to unsafe unless the MCP server declares concurrency safety in tool metadata (future extension)

**5. Bash command classification is prefix-based.** Extract the first token of the command string. Match against a known-safe set. This is deliberately conservative — it's a floor, not a ceiling. The set can be expanded with evidence from interlab experiments.

**6. Hook/approval gating runs before concurrency.** The existing hook → approver → execute pipeline in `executeToolsWithCallbacks` stays intact. Concurrency classification only affects execution order, not permission flow. Each tool call still gets its own hook/approval check.

**7. Error cascading: only bash errors cancel siblings.** Matching Claude Code's behavior — a Bash error in a parallel batch aborts sibling Bash calls (implicit dependency chains), but Read/Grep errors don't cascade. Implemented via a shared `context.CancelFunc` scoped to the batch.

## Open Questions

- Should the concurrency limit be configurable via Skaffen config, or hardcoded at 10?
- Should MCP tools be able to declare concurrency safety via their tool metadata schema, or wait for a later iteration?
- Should we add `IsReadOnly(params) bool` alongside `IsConcurrencySafe` (they're the same for now but may diverge for tools that are read-only but have rate limits)?

## Source Reference

- Claude Code `Tool.ts:402` — `isConcurrencySafe(input: z.infer<Input>): boolean`
- Claude Code `toolOrchestration.ts:91-116` — `partitionToolCalls` batching algorithm
- Claude Code `StreamingToolExecutor.ts:354-363` — bash-only error cascading
