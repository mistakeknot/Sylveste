# Directory layout

Each subproject has its own `CLAUDE.md` and `AGENTS.md`; read those before editing.

`agents/architecture.md` lists 18 module paths:

| Path | Pillar | Notes |
|------|--------|-------|
| `apps/Autarch/` | Autarch | TUI interfaces (Bigend, Gurgeh, Coldwine, Pollard) |
| `apps/Intercom/` | Autarch | Multi-runtime AI assistant (Claude, Gemini, Codex) |
| `os/Clavain/` | Clavain | Autonomous software agency (L2 OS) |
| `os/Skaffen/` | Skaffen | Sovereign agent runtime (L2 OS) |
| `os/Zaka/` | Zaka | Universal CLI agent driver — tmux steering (L2 OS) |
| `os/Alwe/` | Alwe | Universal agent observation layer — CASS + MCP (L2 OS) |
| `os/Ockham/` | Ockham | Factory governor — intent, authority, anomaly, dispatch (L2 OS) |
| `os/Sonnerie/` | Sonnerie | Token-free GitHub watcher — routes PR and issue events to the owning BB thread |
| `core/intercore/` | Intercore | Orchestration kernel — Go CLI `ic` (L1) |
| `core/intermute/` | Intercore | Multi-agent coordination service (Go) |
| `core/marketplace/` | Intercore | Plugin marketplace registry |
| `core/agent-rig/` | Intercore | Agent rig configuration (TypeScript/Node) |
| `core/interband/` | Intercore | Sideband communication protocol (Go) |
| `core/interbench/` | Intercore | Plugin benchmarking harness (Go) |
| `interverse/` | Interverse | Companion plugins; each has its own docs. The plugin list is on the [plugin map](../plugins/map.md) |
| `sdk/interbase/` | — | Shared integration SDK (Bash/Go/Python) |
| `masaq/` | — | Shared Bubble Tea component library (Go) — themes, keys, viewport, priompt |
| `docs/` | — | Platform-level docs only (brainstorms, research, solutions) |

Several of these directories live in their own repositories and may be absent from a given checkout; the module list above is the canonical map.
