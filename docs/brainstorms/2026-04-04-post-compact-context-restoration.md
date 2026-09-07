---
bead: sylveste-18a.9
type: brainstorm
date: 2026-04-04
---

# Post-Compact Context Restoration for Skaffen

## Problem

After auto-compact fires (sylveste-18a.8, shipped), the model loses context from elided/snipped messages. In Claude Code, `postCompactCleanup.ts` and `buildPostCompactMessages` handle this by: clearing stale caches, re-injecting plan context, re-announcing available tools, and adding a context-loss summary. Skaffen needs the equivalent.

## What Skaffen Already Handles

Skaffen's architecture is simpler than CC's — several post-compact concerns are non-issues:

1. **System prompt**: Rebuilt from scratch every turn via `session.SystemPrompt(PromptHints{})`. No cache to invalidate.
2. **Tool definitions**: Re-sent every turn via `convertToolDefsCached()`. Tool schema is always present.
3. **Phase context**: Encoded in system prompt, not in conversation history.
4. **Token cache**: Already reset by `loop.resetTokenCache()` in the auto-compact path.

## What's Missing (Gaps)

### Gap 1: Post-compact orientation message (P1)

After compaction, the model's first turn has no context about what was being worked on. The snip marker says "earlier context was removed" but doesn't say what it was about. The model needs a brief orientation:

```
[Context restored after compaction]
You were working on: <goal from CompactionSummary>
Files modified: <list from CompactionSummary>
Current phase: <OODARC phase>
Last test result: <pass/fail from CompactionSummary>
```

This maps to CC's `getCompactUserSummaryMessage()`. In Skaffen, the `CompactionSummary` struct already has all these fields — it just needs to be injected after snip.

### Gap 2: Plan re-injection (P2)

If the agent was following a plan (`PlanMode=true` in LoopConfig), the plan text needs to be re-injected after compaction. Currently plan mode adds context via the system prompt, so this may already work — but needs verification.

### Gap 3: MCP tool instruction re-announcement (P2)

MCP tools loaded via `mcp.Manager.LoadAll()` include per-tool instructions in their descriptions. These survive compaction (tool defs are re-sent every turn). However, if MCP tools were *discovered during the session* (via ToolSearch equivalent), the discovery context is lost. This is a minor issue for Skaffen since MCP tools are loaded at startup.

### Gap 4: CompactionSummary construction from evidence (P1)

The `CompactionSummary` struct exists but is only used by the explicit `CompactStructured()` method. Auto-compact doesn't build a summary — it just calls `microCompact` and `snip` without creating a `CompactionSummary` to inject. The auto-compact path needs to build one from accumulated evidence.

## Approach: PostCompactHook callback

Add an optional `PostCompactHook` to `AutoCompactConfig` — a callback that receives the pre-compaction messages and returns additional messages to inject after compaction. This keeps the auto-compact logic generic while letting the agent layer provide session-specific context.

```go
type PostCompactHook func(preCompact []provider.Message, phase string) []provider.Message
```

The agent layer (`agent.go`) wires this up to build a `CompactionSummary` from its evidence store and inject the orientation message.

## Approach rejected: Evidence-based summary in agentloop

Building the summary inside `agentloop/` would require importing `session/CompactionSummary`, creating a dependency cycle. The hook approach keeps the dependency flowing downward.

## Scope

- New: `PostCompactHook` field on `AutoCompactConfig`, called in loop.go after compaction
- New: Hook implementation in `agent.go` that builds `CompactionSummary` from evidence
- Modify: `autocompact.go` to call the hook and inject returned messages
- Tests: integration test verifying orientation message appears after compaction
- NOT in scope: MCP tool re-announcement (already works), plan re-injection (verify only)
