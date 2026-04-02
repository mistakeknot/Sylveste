---
artifact_type: brainstorm
bead: sylveste-18a.7
stage: discover
---

# Deep Research Pass: Additional Claude Code Patterns for Skaffen

Source: `research/claude-code-source/` (512K LOC TypeScript snapshot, 2026-03-31)

## Patterns Already Covered (sylveste-18a.1 through .6)

- Per-invocation tool concurrency (.1, shipped)
- Streaming tool execution (.2)
- Fork subagent cache optimization (.3)
- Coordinator prompt → OODARC (.4)
- Permission bubble mode (.5)
- Dangerous pattern deny list (.6)

## New Patterns Identified

### P1: Auto-Compact Context Management

Skaffen has no context window management. Claude Code has a layered compaction system:

**Thresholds (model-dependent):**
- `effectiveWindow = contextWindow - maxOutputTokens`
- `autocompactThreshold = effectiveWindow - 13,000` (trigger)
- `blockingLimit = effectiveWindow - 3,000` (hard stop)
- Circuit breaker: stop retrying after 3 consecutive failures

**Three composable strategies (in order):**
1. **Snip** — remove old messages, subtract freed tokens from threshold check
2. **Microcompact** — elide old tool results via cache editing (no API call)
3. **Full compact** — API call to summarize conversation history

**Post-compact restoration:** re-inject tool schemas, file listings, CLAUDE.md, plan context. Without this, the model loses tool awareness after compaction.

**Key insight:** Compaction is checked before every turn, not just at query entry. The circuit breaker prevents infinite recompaction loops (observed: thousands of consecutive failures before the breaker was added).

**Skaffen applicability:** HIGH. Skaffen's session persistence uses JSONL but has no automatic context window management. Long coding sessions will hit the 200K window without warning. The threshold + circuit breaker pattern is straightforward to port to Go.

### P2: Two-Stage Bash Safety Classifier

Claude Code's auto-mode uses an LLM-as-judge to classify bash command safety:

**Stage 1 (fast):** max_tokens=64, XML output `<block>yes/no</block>`, stop sequence `</block>`. If allow → return immediately. If block → escalate.

**Stage 2 (thinking):** max_tokens=4096, `<thinking>...</thinking><block>yes/no</block><reason>...</reason>`. Chain-of-thought reasoning before decision.

**Racing:** classifier runs async while the TUI shows "checking..." badge. If classifier approves before user responds, command auto-executes. Reactive signal system tracks per-toolUseID state.

**System prompt:** customizable allow/deny/environment rules. External users get replaceable defaults; internal users get appended defaults. Transcript is built from conversation history (user text + tool_use blocks, NOT assistant text — prevents injection).

**Skaffen applicability:** MEDIUM-HIGH. Skaffen already has a trust evaluator in `trust/rules.go` with static allow/deny lists. The two-stage LLM classifier is the upgrade path — Stage 1 is cheap enough to run on every bash call, Stage 2 only fires on blocks. The racing pattern with the TUI approval dialog is a natural fit for Bubble Tea's message-based architecture.

### P3: Persistent Agent Memory

Claude Code has a YAML-frontmatter memory system:

**Directory structure:**
- `~/.claude/projects/<git-root>/memory/` — per-project, shared
- `.claude/agent-memory/<type>/` — per-agent, VCS-tracked
- `~/.claude/agent-memory/<type>/` — user-wide scope

**Memory file format:**
```yaml
---
name: memory name
description: one-line description (used for relevance matching)
type: user|feedback|project|reference
---
Content in markdown with **Why:** and **How to apply:** lines
```

**Index:** `MEMORY.md` (max 200 lines, 25KB) with one-line pointers to topic files.

**Semantic recall:** Load frontmatter manifest, send to Sonnet to filter by query + descriptions, return up to 5 relevant files. Injected into turn context before inference.

**Snapshot system:** Timestamp-based sync for sharing agent memory across project clones. `snapshot.json` + `.snapshot-synced.json` for change detection.

**Skaffen applicability:** MEDIUM. Skaffen has no persistent memory today. The YAML-frontmatter format is simple and would let Skaffen agents remember user preferences, code patterns, and project context across sessions. The semantic recall via small model is the expensive part — could start with keyword matching and upgrade to LLM recall later.

### P4: MCP HTTP/SSE Transport

Skaffen only supports MCP stdio. Claude Code supports 7 transport types:

**Most useful for Skaffen:**
- **HTTP** — streamable POST/response with OAuth, for remote MCP servers
- **SSE** — Server-Sent Events for push-based tool updates
- **SDK** — in-process MCP server (no subprocess overhead)

**Connection management:** memoized `connectToServer(name, config)` keyed by name + serialized config. Reconnection via onclose handler that clears cache. Terminal error detection (3 consecutive ECONNRESET/ETIMEDOUT → force close). OAuth discovery via `.well-known`.

**Skaffen applicability:** MEDIUM. HTTP transport would let Skaffen connect to remote MCP servers (useful for team-shared tools). SDK transport would let Go packages expose tools without subprocess overhead. SSE is lower priority unless Skaffen needs push-based updates.

### P5: Skill Execution Context (Fork vs Inline)

Claude Code skills have a `context` frontmatter field:
- `context: inline` (default) — skill content injected into current conversation
- `context: fork` — skill creates a sub-agent with its own context, token budget, and tool pool

**Fork execution:** `runAgent()` creates a separate conversation with merged effort levels, separate MCP connections, and agent-specific hooks. Results are collected and returned as a single tool result.

**Permission checking:** hierarchical rule matching with exact and prefix patterns (`review:*` matches `review-pr`), safe-properties auto-allow, and classifier integration.

**Skaffen applicability:** LOW-MEDIUM. Skaffen already has a skill system via `internal/skill/`. The fork execution pattern would be useful if Skaffen skills need isolated contexts (e.g., a research skill that shouldn't pollute the main conversation). Lower priority than context management and safety classifier.

### P6: Turn Budget with Diminishing Returns Detection

Claude Code tracks token budget per turn and detects diminishing returns:
- Continue if `turnTokens < budget * 90%`
- Stop if 3+ continuations AND last two deltas < 500 tokens each
- Prevents the model from generating filler content when it has nothing useful to add

**Skaffen applicability:** LOW-MEDIUM. Skaffen's router already tracks budget via `BudgetState`. The diminishing returns detection is a cheap addition — compare last N turn token deltas and abort if the model is spinning.

### P7: Post-Compact Context Restoration

After compaction, Claude Code re-injects:
- File listings (most recently read files, up to 5)
- Tool schema deltas (tools added/changed since compact)
- MCP server instructions
- Plan context (if in plan mode)
- Skill listings
- CLAUDE.md / session-start hooks

Without restoration, the model loses awareness of available tools and project context after compaction.

**Skaffen applicability:** HIGH (if auto-compact is implemented). This is a required companion to P1. Skaffen's session system prompt already includes tool definitions and phase context — after compaction, these must be re-injected.

## Priority Ranking for New Beads

| Priority | Pattern | Effort | Impact |
|----------|---------|--------|--------|
| P1 | Auto-compact context management | High | Critical — prevents session crashes |
| P1 | Post-compact restoration | Medium | Required companion to auto-compact |
| P2 | Two-stage bash classifier | Medium | Upgrades trust evaluator from static to dynamic |
| P2 | Persistent agent memory | Medium | Cross-session learning |
| P2 | MCP HTTP transport | Medium | Remote tool servers |
| P3 | Skill fork execution | Low | Isolated skill contexts |
| P3 | Turn budget diminishing returns | Low | Cheap optimization |
