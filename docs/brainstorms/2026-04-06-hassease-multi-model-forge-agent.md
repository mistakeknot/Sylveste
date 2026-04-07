---
artifact_type: brainstorm
bead: sylveste-nr6x
stage: discover
---

# Hassease — Multi-Model Code Execution Daemon

Named after the Mind from *Excession* that operated through proxies and intermediaries. Hassease is a headless code execution agent that routes through cheap models (GLM 5.1, Qwen 3.6) for routine work and escalates to Claude (Sonnet/Opus 4.6) for planning, reviews, and complex tasks.

## What We're Building

A new L2 pillar (`os/Hassease/`) — a Go daemon that:
- Receives code instructions over Signal (primary transport)
- Executes changes using a multi-model agent loop
- Routes ~80% of tasks to subsidized Chinese models (cost-optimized)
- Escalates planning, reviews, and complex multi-file work to Claude
- Has built-in tool approval: human approves edits before they land
- Imports Skaffen's agent loop packages as a Go module dependency

## Why This Approach

Auraken's current `claude -p` subprocess model has three problems:
1. **Cost** — every forge invocation uses Claude, even for simple edits
2. **Transport** — tied to Auraken's process, can't run independently
3. **Authority** — all-or-nothing tool whitelist, no per-action approval

Hassease solves all three by being a standalone daemon with model routing and Signal-native approval.

## Architecture

```
Signal (builder)
    │
    ▼
Hassease daemon (Go, headless, runs on server)
    │
    ├─── Router ─────────────────────────────────┐
    │    │                                        │
    │    ├── GLM 5.1 / Qwen 3.6 (routine)       │
    │    │   Read, Grep, Glob, simple Edit       │
    │    │                                        │
    │    ├── Claude Sonnet 4.6 (complex)          │
    │    │   Multi-file edits, refactors          │
    │    │                                        │
    │    └── Claude Opus 4.6 (planning/review)    │
    │        Architecture, strategy, code review  │
    │                                             │
    ├─── Tool Registry (from Skaffen)             │
    │    Read, Edit, Grep, Glob, LS, Bash(gated)  │
    │                                             │
    ├─── Trust Evaluator (from Skaffen)           │
    │    Auto-approve reads, require approval for  │
    │    edits/writes/bash                         │
    │                                             │
    └─── Evidence (JSONL + OODARC)                │
         Every action receipted, costs tracked     │
```

## Key Decisions

1. **Go, not Python.** Aligns with L2 stack (Skaffen, Zaka, Intermute, Intercore). Auraken is also migrating to Go. Chinese model APIs are HTTP — Go handles this fine with `net/http`.

2. **New pillar, not a Skaffen binary.** Skaffen is a sovereign agent (acts autonomously). Hassease is human-directed (acts on instructions with approval). Different identity, different trust model, different transport. They share internal packages but are architecturally distinct.

3. **Signal-native, not Telegram.** Signal is the builder transport. Hassease communicates directly via signal-cli or Signal API, not through Auraken's Telegram bot. Auraken may forward messages to Hassease, but Hassease owns its own Signal connection.

4. **Imports Skaffen's `internal/` as Go module.** Reuse provider abstraction, tool registry, trust evaluator, OODARC engine, session persistence. Add new providers (GLM, Qwen) and a Signal transport adapter.

5. **Cost routing, not capability routing.** The model choice is primarily about cost, not capability boundaries. GLM/Qwen can handle most code tasks — Claude is for when the task needs deeper reasoning, not when it needs "permission." The router optimizes for $/quality, not access control.

## Shared Packages from Skaffen

| Package | What Hassease uses |
|---------|-------------------|
| `internal/agent/` | OODARC workflow engine (phase FSM) |
| `internal/tool/` | Tool registry with phase gating |
| `internal/trust/` | Trust evaluator for tool approval |
| `internal/provider/` | Provider interface + Anthropic adapter |
| `internal/router/` | Per-turn model selection (extend with cost routing) |
| `internal/session/` | JSONL session persistence |
| `internal/mcp/` | MCP stdio client (for interjawn, interlock) |
| `internal/evidence/` | Structured event emission |

## New Packages in Hassease

| Package | What it does |
|---------|-------------|
| `internal/transport/signal/` | Signal messaging (send/receive, approval flow, threads) |
| `internal/provider/glm/` | GLM 5.1 API adapter (HTTP, streaming) |
| `internal/provider/qwen/` | Qwen 3.6 API adapter (HTTP, streaming) |
| `internal/costrouter/` | Cost-optimized model selection (task complexity → cheapest adequate model) |
| `cmd/hassease/` | Daemon entry point (headless, Signal-connected) |

## Model Routing Strategy

| Task type | Primary model | Escalation trigger |
|-----------|--------------|-------------------|
| Read/search/grep | GLM 5.1 | Never — reads are always cheap |
| Simple single-file edit | GLM 5.1 or Qwen 3.6 | Model confidence low, or edit touches >50 lines |
| Multi-file edit | Qwen 3.6 | >3 files, or cross-module dependencies |
| Refactor | Claude Sonnet 4.6 | Always — refactors need deeper understanding |
| Planning / architecture | Claude Opus 4.6 | Always — highest reasoning quality |
| Code review | Claude Sonnet 4.6 | Always — review quality is non-negotiable |
| Test generation | Qwen 3.6 | Test failures after generation → escalate to Sonnet |

The router starts cheap and escalates on evidence (failed edits, low confidence, complexity signals). This is the PHILOSOPHY.md principle: "route to the cheapest model that clears the bar."

## Tool Approval Flow

```
Hassease: "I want to edit src/auth.py lines 45-60 — add token refresh check"
    → Signal message to builder
    
Builder: "y" (or "approve", "go", thumbs up)
    → Hassease executes the edit
    
Builder: "n" (or "deny", "skip")
    → Hassease skips, moves to next step
    
Builder: "show" (or "diff", "preview")
    → Hassease shows the proposed change without executing
```

Auto-approve rules (configurable):
- Read, Grep, Glob, LS → always auto-approved (no Signal message)
- Edit to test files → auto-approved (low risk)
- Edit to src files → requires approval
- Bash → always requires approval
- Write (new files) → requires approval

## Open Questions

- **signal-cli vs Signal API**: signal-cli is the existing integration path. Is there a better Signal transport for a Go daemon?
- **Skaffen module boundary**: Can Hassease import Skaffen's `internal/` directly (same Go workspace), or does Skaffen need to extract shared packages into a `pkg/` layer?
- **Chinese model API stability**: GLM 5.1 and Qwen 3.6 — are their APIs stable enough for production use? Need to assess SDK maturity.
- **Cost tracking**: How do we track per-model costs? Extend interstat, or does Hassease maintain its own cost ledger?
- **Session handoff**: Can a Hassease session escalate to Claude Code (full IDE) mid-task if complexity exceeds what the daemon can handle?
