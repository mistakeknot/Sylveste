# Skaffen CLI Backend Providers: Research Synthesis

> Research date: 2026-03-12
> Scope: Claude Code `-p`, Codex `exec`/`app-server`, Gemini CLI `-p` as subprocess backends for Skaffen's Provider abstraction
> Related: [ai-coding-cli-tui-landscape](2026-03-11-ai-coding-cli-tui-landscape.md), [codex-cli-feature-inventory](2026-03-12-codex-cli-feature-inventory.md)

## Executive Summary

All three major AI coding CLIs (Claude Code, Codex, Gemini) emit JSONL streaming events with convergent schemas. Skaffen's existing `Provider` interface requires **zero changes** to support any of them — each backend is a new `init()` registration + event mapper following the existing Claude Code provider pattern.

The two architecturally significant findings:

1. **Codex app-server** is a persistent JSON-RPC daemon with thread lifecycle management (create/resume/fork/archive), mid-flight steering, approval callbacks, and reconnection. This is substantially richer than `codex exec` and maps naturally to OODARC phase management.

2. **tmux should be used for display/persistence, NOT communication.** Every successful multi-agent project uses tmux for process containment + human visibility, while communicating via structured side-channels (filesystem JSON, SQLite, Unix sockets). Raw `send-keys`/`capture-pane` as IPC is a documented reliability trap.

## Three-Way Protocol Comparison

| Dimension | Claude Code (`-p`) | Codex (`exec` / `app-server`) | Gemini CLI (`-p`) |
|---|---|---|---|
| **Streaming protocol** | JSONL over stdout | JSONL (exec) or JSON-RPC (app-server) | JSONL over stdout |
| **Persistent subprocess** | `--input-format stream-json` | `app-server` daemon | Not supported (single-shot) |
| **MCP cold-start avoidance** | Yes (persistent subprocess) | Yes (app-server threads) | No (respawn per invocation) |
| **Thread management** | `--resume`/`--continue`/`--session-id` | `thread/start`/`resume`/`fork`/`archive` | `--resume`/`--resume <UUID>` |
| **Permission granularity** | Fine: `Bash(pattern)` allow/deny, `--permission-prompt-tool` | Coarse: 3 sandbox × 3 approval | Medium: `tools.allowed` patterns + 6 sandbox profiles |
| **Bidirectional control** | Control protocol (permissions, hooks, MCP mgmt) | JSON-RPC approval flow + `turn/steer` | None documented |
| **Auth for subprocess** | `ANTHROPIC_API_KEY` (OAuth prohibited for 3rd-party) | `CODEX_API_KEY` or pre-provisioned OAuth | `GEMINI_API_KEY` (OAuth problematic in non-TTY) |
| **Go SDK** | `shaharia-lab/claude-agent-sdk-go` | `picatz/openai/codex` (exec only) | None |
| **Subagent system** | Agent tool (no nesting) | `collabToolCall` (spawn/send/resume/wait/close) | Named subagents + A2A (YOLO-mode only) |
| **Free tier** | None | None | 1000 req/day |

## Event Schema Mapping to Skaffen StreamEvent

Skaffen's existing `StreamEvent` types map cleanly to all three CLIs:

```
Skaffen EventType    │ Claude Code              │ Codex exec                    │ Gemini CLI
─────────────────────┼──────────────────────────┼───────────────────────────────┼──────────────
EventTextDelta       │ assistant.content[text]   │ item(agent_message).text      │ message(delta:true)
EventToolUseStart    │ assistant.content[tool]   │ item.started(command/file/mcp) │ tool_use
EventToolUseDelta    │ stream_event(input_json)  │ item/outputDelta              │ (N/A)
EventToolResult      │ user(tool_result)         │ item.completed(command/file)   │ tool_result
EventDone            │ result                    │ turn.completed                │ result
EventError           │ stream_event(error)       │ turn.failed / error           │ error
```

**No changes needed to the Provider interface.** Tool execution in all CLI backends is internal to the subprocess — the provider always emits `StopReason: "end_turn"` (never `"tool_use"`), so the agent loop never attempts to re-execute tools.

## Codex App-Server: Deep Analysis

The app-server (`codex app-server`) is the most architecturally rich integration surface among all three CLIs. Key capabilities relevant to Skaffen:

### Thread Lifecycle (maps to OODARC phases)

| Method | Purpose | Skaffen Use |
|---|---|---|
| `thread/start` | Create new conversation | Start a new OODARC session |
| `thread/resume` | Continue existing thread | Resume after crash/reconnect |
| `thread/fork` | Branch with copied history | **Phase transitions** — fork at Decide→Act boundary, keep Orient context |
| `thread/archive` | Soft-delete completed | Archive completed OODARC cycles |
| `thread/rollback` | Drop last N turns | Undo failed Act phase attempts |
| `thread/compact/start` | Compress history | Long-running sessions |

`thread/fork` with `ephemeral: true` is particularly interesting — create an in-memory-only branch for exploratory phases (Orient, Decide) that you discard if the plan doesn't pan out.

### Mid-Flight Control

| Method | Purpose | Skaffen Use |
|---|---|---|
| `turn/steer` | Inject input into active turn | Phase-gate corrections without waiting for turn completion |
| `turn/interrupt` | Cancel active turn | Abort runaway Act phase |
| `review/start` | Trigger code review | Built-in Reflect phase |

`turn/steer` is unique — neither Claude nor Gemini can modify a running turn. This enables real-time course correction from the outer OODARC loop.

### Approval Flow (maps to phase-gated tool registry)

The app-server's approval flow is bidirectional JSON-RPC:
1. Server sends `item/commandExecution/requestApproval` or `item/fileChange/requestApproval`
2. Client responds with `accept` / `acceptForSession` / `decline` / `cancel`
3. Server emits `serverRequest/resolved` + `item/completed`

Skaffen can implement a phase-aware approval backend:
- **Observe/Orient**: decline all write/execute approvals
- **Act**: accept workspace-write, decline out-of-workspace
- **Reflect**: accept test commands, decline writes
- **Compound**: accept git operations, decline everything else

### Dynamic Tools (maps to Skaffen tool registry)

The `dynamicTools` parameter on `thread/start` lets Skaffen inject its own tools into the Codex agent:

```json
{
  "method": "thread/start",
  "params": {
    "dynamicTools": [{
      "name": "phase_advance",
      "description": "Advance OODARC phase",
      "inputSchema": {"type":"object","properties":{"phase":{"type":"string"}}}
    }]
  }
}
```

When Codex calls a dynamic tool, the app-server sends `item/tool/call` to the client (Skaffen), which executes it locally and returns the result. This means Skaffen's tool registry can be exposed directly to the Codex agent.

### Protocol Design Patterns Worth Adopting

1. **Notification opt-out** (`optOutNotificationMethods`): Clients declare which events they don't want. Reduces noise for simple consumers.

2. **Backpressure with bounded queues**: Server rejects with `-32001` when saturated. Client retries with exponential backoff + jitter.

3. **Schema generation**: `codex app-server generate-json-schema` dumps the full protocol schema for a specific version. Guarantees client/server compatibility.

4. **`serverRequest/resolved`**: Every approval/elicitation has an explicit resolution notification, including lifecycle cleanup (turn start/complete/interrupt clears pending requests). No dangling callbacks.

5. **Ephemeral threads**: `ephemeral: true` creates in-memory-only threads that are never persisted. Perfect for exploratory phases.

6. **`externalSandbox` mode**: When the parent orchestrator provides its own sandbox (like Skaffen's phase-gated tool registry), tell Codex to skip its internal sandbox. Avoids double-sandboxing.

## Claude Code: Persistent Subprocess Protocol

### `--input-format stream-json` (Recommended)

Keeps a single `claude` subprocess alive for multi-turn conversation:
- MCP servers start once and persist across turns
- System prompt + tool schemas loaded once (avoids ~50K token cold-start)
- Full conversation history accumulates naturally

### Control Protocol

Bidirectional NDJSON with `request_id`-based multiplexing:

| Direction | Subtype | Purpose |
|---|---|---|
| SDK→CLI | `initialize` | Register hooks, SDK MCP servers |
| SDK→CLI | `can_use_tool` response | Permission callback |
| CLI→SDK | `can_use_tool` request | Permission decision delegation |
| SDK→CLI | `set_model` | Dynamic model switching |
| SDK→CLI | `interrupt` | Cancel current turn |
| SDK→CLI | `mcp_set_servers` | Dynamic MCP management |

### `--permission-prompt-tool` (Phase-Gating)

Delegates permission decisions to an MCP tool — Skaffen could implement a phase-aware permission MCP:

```bash
claude -p --permission-prompt-tool "mcp__skaffen__phase_gate" \
  --allowedTools "Read,Grep,Glob" \
  "Analyze the codebase"
```

The MCP tool receives `{tool_name, input}` and returns `{behavior: "allow"|"deny"}`.

### OAuth Restriction

As of January 2026, Anthropic prohibits consumer OAuth (Free/Pro/Max) in third-party tools. Skaffen **must** use `ANTHROPIC_API_KEY` for the Claude Code provider.

## Gemini CLI: Simple Backend

Gemini CLI is the simplest of the three — same JSONL streaming, similar event types, but:
- **No persistent subprocess mode**: every turn is a cold-start
- **No bidirectional control protocol**: fire-and-forget only
- **Subprocess gotcha**: v0.1.22+ hangs in non-TTY if stdin isn't explicitly closed (`cmd.Stdin = nil`)
- **Richest sandbox options**: 6 Seatbelt profiles + Docker/gVisor/LXC backends
- **Free tier**: 1000 req/day with Google account

Best suited as a budget backend for read-only phases (Observe/Orient).

## tmux: Display Layer, Not Communication Bus

### The Verdict

Every successful multi-agent project uses tmux for display + persistence, NOT for IPC:
- **Claude Code agent teams**: tmux for split-pane visibility; JSON inbox files on disk for messaging
- **Overstory**: tmux for process isolation; SQLite mail system for coordination
- **super-agent-ai/tmux-agents**: tmux for session management; JSON-RPC daemon for control

Raw `send-keys`/`capture-pane` as IPC has documented reliability problems:
- Shell initialization race (Claude Code issue #23513)
- Capture-before-update race (tmux issue #1412)
- Double-approval in polling loops
- Buffer overflow losing output
- Completion detection requiring polling (0.3-0.5s latency)

### The Right Hybrid

Run CLI backends inside tmux panes for persistence and observability, but communicate via their native structured protocols:
- Claude Code: stdin/stdout JSONL with `--input-format stream-json`
- Codex: app-server JSON-RPC over stdio
- Gemini: stdout JSONL (no stdin, single-shot)

## Permission Model Comparison for OODARC Phases

| Phase | Best Backend | Configuration | Why |
|---|---|---|---|
| **Observe** | Any (edge: Codex) | `--sandbox read-only` / `--permission-mode plan` | Read-only, OS-level enforcement |
| **Orient** | Claude `-p` | `--tools "Read,Grep,Glob" --permission-mode plan` | Analysis with subagent delegation |
| **Decide** | Claude `-p` | `--permission-mode plan --allowedTools "Read,Grep,Glob,Agent(Plan)"` | Planning with read-only enforcement |
| **Act** | Claude persistent OR Codex app-server | Workspace-write + phase deny rules | Build needs rich tool access + MCP |
| **Reflect** | Claude `-p` | `--allowedTools "Read,Grep,Glob,Bash(go test *)"` | Read + specific test commands only |
| **Compound** | Claude `-p` | `--allowedTools "Bash(git *)" --disallowedTools "Edit,Write"` | Git operations only |

Claude Code wins 5/6 phases due to `Bash(pattern)` granularity. Codex's coarse sandbox can't express "some commands but not others." But Codex app-server wins for Act phase due to `turn/steer` and `thread/fork`.

## Provider Roadmap

### Priority 1: Evolve Claude Code provider to persistent mode

Change from cold-starting `claude -p` per turn to `--input-format stream-json` persistent subprocess:
- Eliminates MCP cold-start (~50K token overhead/invocation)
- Enables multi-turn conversations
- Unlocks control protocol for permission callbacks
- Reference: `shaharia-lab/claude-agent-sdk-go` for Go implementation patterns

### Priority 2: Add Codex app-server provider

Implement JSON-RPC client for the app-server protocol:
- Thread lifecycle maps to OODARC phases (fork at transitions)
- `turn/steer` enables real-time phase-gate corrections
- Approval callbacks implement phase-aware permission logic
- `dynamicTools` exposes Skaffen's tool registry to the Codex agent
- Reference: `picatz/openai/codex` for Go exec patterns (app-server client would be new)

### Priority 3: Add Gemini CLI provider

Simple exec-mode backend:
- Lowest priority — no persistent subprocess, every turn cold-starts
- Free tier (1000 req/day) makes it useful for budget-sensitive phases
- Watch for stdin hang bug: `cmd.Stdin = nil` required

### Priority 4: tmux process management layer (optional)

Wrap all provider subprocesses in tmux panes:
- Process persistence across SSH disconnections
- Human observability via `tmux attach`
- Orthogonal to provider communication (keep on native protocols)

## Sources

### Official Documentation
- [Codex App Server README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [Codex Non-Interactive Mode](https://developers.openai.com/codex/noninteractive/)
- [Codex Sandboxing](https://developers.openai.com/codex/concepts/sandboxing/)
- [Codex Agent Approvals & Security](https://developers.openai.com/codex/agent-approvals-security/)
- [Codex Authentication](https://developers.openai.com/codex/auth/)
- [Claude Code CLI Reference](https://code.claude.com/docs/en/cli-reference)
- [Claude Code Headless/Programmatic Usage](https://code.claude.com/docs/en/headless)
- [Claude Code Sandboxing](https://code.claude.com/docs/en/sandboxing)
- [Claude Code Permissions](https://code.claude.com/docs/en/permissions)
- [Agent SDK Overview](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Gemini CLI Headless Mode](https://geminicli.com/docs/cli/headless/)
- [Gemini CLI Sandbox](https://geminicli.com/docs/cli/sandbox/)

### Go SDKs & References
- [shaharia-lab/claude-agent-sdk-go](https://pkg.go.dev/github.com/shaharia-lab/claude-agent-sdk-go/claude)
- [picatz/openai/codex](https://pkg.go.dev/github.com/picatz/openai/codex)
- [OpenAI App Server Architecture (InfoQ)](https://www.infoq.com/news/2026/02/opanai-codex-app-server/)

### tmux Agent Orchestration
- [bnomei/tmux-mcp](https://github.com/bnomei/tmux-mcp) — tracked command pattern
- [Dicklesworthstone/ntm](https://github.com/Dicklesworthstone/ntm) — Named Tmux Manager
- [codex-yolo/codex-yolo](https://github.com/codex-yolo/codex-yolo) — parallel auto-approval
- [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams) — tmux for display, JSON for IPC
- [super-agent-ai/tmux-agents](https://github.com/super-agent-ai/tmux-agents) — daemon architecture

### Auth Restrictions
- [Anthropic OAuth restriction (Jan 2026)](https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/)
- [Codex Pricing & Rate Limits](https://developers.openai.com/codex/pricing/)
