---
name: Skaffen
description: "Interverse driver capability: Skaffen"
---
# Gemini Skill: Skaffen

You have activated the Skaffen capability.

## Base Instructions
# Skaffen — Agent Reference

## Architecture

Skaffen is a two-layer agent architecture:

1. **agentloop** (`internal/agentloop/`): Universal Decide→Act core. Phase-agnostic. Knows about providers, tools, routers, sessions, and emitters — but not about OODARC phases. Can be used standalone for simple agent loops.

2. **agent** (`internal/agent/`): OODARC workflow engine. Wraps `agentloop.Loop` with phase FSM (`brainstorm→plan→build→review→ship`), phase-gated tool access, and adapter bridges. This is what `cmd/skaffen/main.go` instantiates.

The separation means `agentloop` has zero dependencies on `agent` or `tool` (for phase types). The `agent` package converts between `tool.Phase` and plain strings via adapters.

## Package Map

| Package | Purpose | Key Types |
|---------|---------|-----------|
| `agentloop` | Universal loop | `Loop`, `Registry`, `Router`, `Session`, `Emitter`, `SelectionHints` |
| `agent` | OODARC workflow | `Agent`, `phaseFSM`, `GatedRegistry`, adapter types |
| `provider` | LLM abstraction | `Provider`, `StreamResponse`, `Message`, `ToolDef` |
| `provider/anthropic` | Anthropic API | SSE streaming, tool_use, usage reporting |
| `provider/claudecode` | Claude Code proxy | Subprocess management, stream-json parsing |
| `router` | Model selection | `Router`, `Config`, `ICClient`, complexity classifier |
| `session` | Persistence | `Session`, JSONL format, truncation, priompt rendering |
| `tool` | Tool system | `Tool`, `Registry`, `Phase`, 7 built-in tools |
| `mcp` | MCP client | `Manager`, `Client`, `MCPTool`, `PluginConfig` |
| `evidence` | Event emission | JSONL writer + `ic events record` bridge |
| `git` | Git operations | Auto-commit, revert, squash |
| `trust` | Tool approval | `Evaluator`, safety classification |
| `tui` | Terminal UI | Bubble Tea app, chat viewport, composer, status bar |

## Build & Test

```bash
# Build
go build ./cmd/skaffen

# Test (all 355+ tests)
go test ./... -count=1

# Test single package
go test ./internal/agent/ -v

# Vet
go vet ./...

# Run TUI mode
go run ./cmd/skaffen

# Run print mode
echo "Hello" | go run ./cmd/skaffen --mode print -p "Say hello"

# Run with MCP plugins
go run ./cmd/skaffen --plugins ~/.skaffen/plugins.toml
```

## Testing Patterns

- **Mock-based isolation:** Agent loop tests use mock providers that return scripted responses. Router, session, and emitter are injected as interfaces.
- **Golden files:** Anthropic provider tests use recorded HTTP responses in `testdata/`.
- **Phase gate matrix tests:** Verify tool availability per OODARC phase.
- **No integration tests requiring external services.** All provider tests are hermetic.

## Coding Conventions

- **Go standard layout:** `cmd/` for binaries, `internal/` for private packages
- **Interface-first design:** Core types (`Provider`, `Router`, `Session`, `Emitter`, `Tool`) are interfaces. Implementations are injected.
- **Error handling:** Return errors up the stack. Use `fmt.Errorf("context: %w", err)` for wrapping. Graceful degradation for optional dependencies (ic, MCP plugins).
- **No `log` package.** All diagnostics go to `os.Stderr` via `fmt.Fprintf`.
- **Sorted iteration:** When iterating maps where output order matters (tool registry), sort keys first. See `agentloop/registry.go`.

## Configuration

```
~/.skaffen/
  routing.json      Model routing config (phase defaults, budget, complexity)
  plugins.toml      MCP plugin declarations
  sessions/         Session JSONL files
  evidence/         Evidence JSONL files
```

### CLI Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--mode` | `tui` | Execution mode: `tui` or `print` |
| `--provider` | auto-detect | `anthropic` or `claude-code` |
| `--model` | phase default | Model override for all phases |
| `--phase` | `build` | Starting OODARC phase |
| `--max-turns` | `100` | Safety limit for loop iterations |
| `--budget` | `0` (unlimited) | Per-session token budget |
| `--plugins` | `~/.skaffen/plugins.toml` | MCP plugin config path |
| `-p` | stdin | Prompt text |
| `-c` | — | Resume last session |
| `-r` | — | Resume specific session by ID |

## Module Relationships

```
cmd/skaffen ─→ agent ─→ agentloop ─→ provider
                │              │
                ├→ tool        ├→ (no tool import)
                ├→ router      │
                ├→ session     │
                ├→ evidence    │
                ├→ mcp ────→ tool
                └→ tui ────→ agent, trust, masaq
```

Key constraint: `agentloop` never imports `agent` or `tool`. This enables reuse as a standalone agent loop library.

## External Dependencies

| Dependency | Purpose | Version |
|-----------|---------|---------|
| `modelcontextprotocol/go-sdk` | MCP stdio client | v1.4.0 |
| `charmbracelet/bubbletea` | TUI framework | v1.3.4 |
| `charmbracelet/bubbles` | TUI components | v0.20.0 |
| `charmbracelet/lipgloss` | TUI styling | v1.1.0 |
| `BurntSushi/toml` | Config parsing | v1.6.0 |
| `mistakeknot/masaq` | Shared TUI components | local (../../masaq) |


