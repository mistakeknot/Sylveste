---
artifact_type: brainstorm
bead: Demarch-4wm
stage: discover
---

# Brainstorm: Token-Efficient Conversation Resumption Across Container Sessions

## What We're Building

A conversation resumption mechanism for intercom container sessions that preserves enough context for an agent to continue meaningfully after a session reset — without replaying full conversation history into the context window.

The mechanism handles three scenarios with graceful degradation:

| Scenario | Trigger | Context Source | Expected Quality |
|----------|---------|---------------|-----------------|
| Size overflow | Session JSONL > 512 KiB | Agent-authored handoff note (PreCompact hook) | Best (~200-400 tokens, structured) |
| Planned restart | User-initiated or code change | Agent-authored handoff note (PreCompact or stop) | Best |
| Crash/timeout | SIGKILL, network drop, timeout | Ambient state reconstruction | Decent (~100-200 tokens, machine-generated) |

## Why This Approach

### System prompt prepend (not SDK resume or MCP tool)

The resumption context is injected as a structured block in the system prompt before the container starts. This is:
- **Token-efficient**: one-time cost, no back-and-forth
- **SDK-agnostic**: works with any model, no SDK changes needed
- **Universal**: the agent-runner already constructs the prompt from CLAUDE.md + group config — adding a context section is a natural extension

Alternatives considered:
- **First user message**: wasteful (model responds to the synthetic message)
- **SDK resume with summary**: requires JSONL to still exist (fails on crash)
- **MCP tool**: adds latency (agent must decide to call it) and token cost

### Structured handoff note (not prose summary or state-only)

The handoff note follows a fixed schema:
- **Task**: bead ID + 1-line summary of current work
- **Decisions**: key choices made during the session (bulleted)
- **Pending**: concrete next steps
- **Gotchas**: things to avoid or watch out for

This matches Clavain's existing handoff format (`session-handoff.sh`). ~200-400 tokens. Can be authored by the agent (planned/overflow) or reconstructed from ambient state (crash).

Alternatives considered:
- **LLM-generated prose summary**: richer but expensive to generate, variable length, harder to reconstruct on crash
- **State snapshot only**: always available but lacks narrative — the agent gets facts without context

### PreCompact hook timing (not periodic or stop-only)

The agent writes its handoff note when the SDK fires PreCompact (context window filling up). This is the natural moment — the agent knows it's about to lose context. The existing `sessions-index.json` hook already fires here.

- Covers size-overflow automatically (the most common case)
- For planned restarts, the agent can also write one on explicit stop
- Crash recovery uses ambient state reconstruction (no handoff note available)

Alternatives considered:
- **Every N messages**: always fresh but adds token overhead on every Nth turn
- **On container stop signal**: doesn't cover crash (SIGKILL) or size overflow

### Ambient state reconstruction (crash fallback)

When no agent-authored handoff exists, build a minimal context from external state:
- Active bead: `bd list --status=in_progress` (what the agent was working on)
- Git diff --stat: what files changed (what work was done)
- Last conversation archive title (from `conversations/` folder)

No LLM call needed, always available, ~100-200 tokens. The agent gets enough to re-orient.

## Key Decisions

- **Injection point**: System prompt prepend in agent-runner, not SDK resume or MCP tool
- **Primary content**: Agent-authored structured handoff note at PreCompact time
- **Fallback**: Ambient state reconstruction from beads + git + archives
- **Format**: Fixed-schema structured block (~200-400 tokens), not prose
- **Graceful degradation**: best (agent note) → decent (ambient state) → minimal (just CLAUDE.md)
- **No LLM calls** for reconstruction — all fallback paths are deterministic

## Architecture Sketch

```
┌─────────────────────────────────────────────────────┐
│                  Container Session N                 │
│                                                     │
│  PreCompact hook fires ──► Write handoff note        │
│                            to /workspace/group/      │
│                            handoff.json              │
│                                                     │
│  (or crash/timeout ──► no handoff written)           │
└─────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│              Container Session N+1                   │
│                                                     │
│  agent-runner starts ──► Check for handoff.json      │
│                          │                           │
│                          ├─ Found ──► Parse & inject │
│                          │            into system    │
│                          │            prompt         │
│                          │                           │
│                          └─ Missing ──► Reconstruct  │
│                               from ambient state     │
│                               (beads, git, archives) │
│                               & inject into system   │
│                               prompt                 │
└─────────────────────────────────────────────────────┘
```

### Handoff note schema (handoff.json)

```json
{
  "version": 1,
  "created_at": "2026-03-10T14:30:00Z",
  "source": "agent",
  "session_id": "abc123",
  "task": {
    "bead_id": "Demarch-4wm",
    "summary": "Designing conversation resumption mechanism"
  },
  "decisions": [
    "Using system prompt prepend for context injection",
    "Structured handoff note format, not prose"
  ],
  "pending": [
    "Implement PreCompact hook handler in agent-runner",
    "Add handoff.json reading to session startup"
  ],
  "gotchas": [
    "Don't read conversation archives directly — too many tokens",
    "handoff.json must be written atomically (rename, not write-in-place)"
  ]
}
```

### System prompt injection format

```
## Previous Session Context

You are resuming a conversation. Here is context from your previous session:

**Task:** [Demarch-4wm] Designing conversation resumption mechanism
**Decisions made:**
- Using system prompt prepend for context injection
- Structured handoff note format, not prose
**Pending work:**
- Implement PreCompact hook handler in agent-runner
- Add handoff.json reading to session startup
**Watch out for:**
- Don't read conversation archives directly — too many tokens
```

### Integration points

1. **agent-runner/src/index.ts** — PreCompact hook: write `handoff.json` to `/workspace/group/`
2. **agent-runner/src/index.ts** — Session startup: read `handoff.json`, format as system prompt section
3. **agent-runner/src/index.ts** — Ambient reconstruction: if no `handoff.json`, build context from beads/git/archives
4. **process_group.rs** — Ensure `/workspace/group/` persists across container restarts (it already does — it's a bind mount)
5. **protocol.ts** — Add `previousContext?: string` to `ContainerInput` (optional, for host-side reconstruction)

## Open Questions

- **Token budget cap**: Should there be a hard limit on resumption context size? (e.g., max 500 tokens, truncate oldest decisions first)
- **Handoff note rotation**: Keep last N handoff notes for multi-restart chains? Or just the latest?
- **Host vs container reconstruction**: Should ambient state reconstruction happen in the Rust host (process_group.rs) or the TypeScript container (agent-runner)? Host has access to Postgres session history; container has access to workspace files.
- **Conversation archive integration**: Should the system also include the last few lines of the previous conversation archive, or is the structured note sufficient?
