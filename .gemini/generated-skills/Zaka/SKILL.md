---
name: Zaka
description: "Interverse driver capability: Zaka"
---
# Gemini Skill: Zaka

You have activated the Zaka capability.

## Base Instructions
# Zaka — Agent Reference

## Architecture

Zaka is a universal CLI agent driver. It spawns any AI coding agent in a tmux session and steers it via send-keys. The complement to [Alwe](https://github.com/mistakeknot/Alwe), which observes.

```
Orchestrator (Skaffen, CI, scripts)
  │
  ▼
Zaka  ──tmux send-keys──▶  Claude Code / Codex / Gemini / AMP / ...
                            (full interactive runtime in tmux)
```

## Package Map

| Package | Purpose | Key Types |
|---------|---------|-----------|
| `adapter` | Agent abstraction | `AgentAdapter`, `Config`, `Register`, `Get`, `List` |
| `tmux` | Session lifecycle | `Session`, `Spawn`, `Resume`, `ListSessions` |

## Adapters

Each adapter knows how to spawn, resume, and format prompts for a specific CLI agent.

| Adapter | Binary | CASS Connector | Resume |
|---------|--------|----------------|--------|
| `claude-code` | `claude` | `claude_code` | yes |
| `codex` | `codex` | `codex` | no |
| `gemini` | `gemini` | `gemini` | no |
| `amp` | `amp` | `amp` | no |
| `aider` | `aider` | `aider` | no |
| `cline` | `cline` | `cline` | no |
| `cursor` | `cursor` | `cursor` | no |
| `copilot` | `copilot` | `copilot` | no |

### Adding a new agent

```go
// In adapter/register.go init():
Register(NewGeneric("my-agent", "my-agent-binary", "cass_connector_name"))

// Or implement AgentAdapter for custom spawn/resume logic.
```

## Build & Test

```bash
go build ./cmd/zaka
go test ./... -count=1
go vet ./...
```

## CLI

```bash
zaka spawn --agent claude-code --workdir /path/to/project
zaka spawn --agent codex --model o3
zaka steer <session-name> "fix the auth bug"
zaka list
zaka kill <session-name>
zaka agents
```

## Integration with Skaffen

Skaffen imports Zaka's adapter and tmux packages via a thin provider bridge at `internal/provider/tmuxagent/`. The bridge adapts Zaka's types to Skaffen's `provider.Provider` interface.

## Dependencies

- **tmux** — required at runtime for session management
- No Go library dependencies beyond stdlib


