---
artifact_type: brainstorm
bead: Demarch-o5u
stage: discover
---

# F7: MCP Stdio Client for Interverse Plugins

**Date:** 2026-03-11
**Status:** Brainstorming
**Parent:** Skaffen v0.2 (Demarch-4xp)

## What We're Building

An MCP stdio client for Skaffen that discovers, spawns, and communicates with Interverse plugin MCP servers. This gives Skaffen native access to the same plugin tools that Claude Code uses (intermap, interlens, interject, etc.) — but with controlled scope and phase-aware gating.

**Scope:** Config-driven discovery + MCP stdio protocol + F2 registry integration.
**Out of scope (follow-up bead):** Full Claude Code tool parity (200+ tools), deferred tool loading, dynamic tool discovery.

## Why This Approach

### Config-driven discovery (not auto-scan)

Skaffen loads only plugins explicitly listed in config (`~/.skaffen/plugins.toml` or project-level `skaffen.toml`). Rationale:

- **Predictability.** The agent's tool surface is deterministic and auditable. No surprises from a new plugin appearing in `interverse/`.
- **Security.** MCP servers are subprocesses with filesystem/network access. Explicit opt-in is the right default for a sovereign agent.
- **Performance.** 53 Interverse plugins exist. Most sessions need 2-3. Loading all would waste subprocess resources and bloat the tool list sent to the LLM.

Config format:

```toml
# ~/.skaffen/plugins.toml
[plugins.intermap]
path = "interverse/intermap/.claude-plugin/plugin.json"  # or absolute
phases = ["brainstorm", "build", "review"]  # which phases can use these tools

[plugins.interlens]
path = "interverse/interlens/.claude-plugin/plugin.json"
phases = ["build"]  # write-capable tools, build-only

[plugins.tldr-swinton]
path = "~/.claude/plugins/cache/tldr-swinton/*/plugin.json"  # glob for versioned cache
phases = ["brainstorm", "build", "review", "ship"]  # read-only tools, all phases
```

### Official MCP Go SDK (modelcontextprotocol/go-sdk)

The official Go SDK for MCP, maintained by the MCP org in collaboration with Google. Provides:
- `CommandTransport` for stdio subprocess communication
- Client with `tools/list` and `tools/call` support
- Session management for concurrent connections
- Spec-tracking — updates in lockstep with MCP protocol changes

Preferred over `mark3labs/mcp-go` (which intermap uses as a server) because it's the canonical implementation and tracks the spec directly. The integration surface is small (spawn + list + call), so swapping later would be straightforward if needed.

### Lazy spawn with intelligent prefetch

MCP server subprocesses start on first tool call to that plugin, not at Skaffen startup. Benefits:
- Most sessions use 2-3 plugins. No wasted subprocesses for the other 50.
- First-call latency (~200ms for spawn + initialize) is acceptable.
- Servers stay alive for the session once spawned (persistent sidecar pattern, same as intermap's Python bridge).

**Intelligent prefetch:** Skaffen's evidence pipeline (F6) records every tool call with `{tool_name, session_id}`. A prefetch heuristic reads recent evidence: if a plugin was used in >50% of the last N sessions, it's pre-spawned at startup. This turns evidence into a feedback loop that improves latency over time.

Prefetch is a v0.2.1 enhancement — v0.2.0 ships with pure lazy spawn.

### Per-plugin phase gating

Each plugin entry in config specifies which OODARC phases can access its tools. This extends F2's existing phase gate matrix:

| Phase | Built-in tools | MCP tools |
|-------|---------------|-----------|
| brainstorm | read, glob, grep, ls | Per-config (read-only plugins like intermap, tldr) |
| build | all 7 | Per-config (all configured plugins) |
| review | read, glob, grep, ls, bash | Per-config (read-only plugins) |
| ship | read, glob, ls, bash | Per-config (typically none or read-only) |

If no `phases` key in config, default is `["build"]` (safest default — MCP tools only in build phase).

## Key Decisions

1. **Config-driven, not auto-discover.** Explicit plugin list in TOML. Auto-scan of interverse/ rejected for predictability and security.
2. **Official MCP Go SDK (modelcontextprotocol/go-sdk) for protocol.** Canonical implementation, maintained by MCP org + Google. Handles JSON-RPC, initialize, tools/list, tools/call.
3. **Lazy spawn, not eager.** Subprocess created on first tool call. Persistent for session lifetime. Intelligent prefetch via evidence heuristic deferred to v0.2.1.
4. **Per-plugin phase gating in config.** Each plugin declares allowed phases. Default is build-only.
5. **Namespaced tool names.** MCP tools registered as `plugin:server:tool_name` to avoid collisions with built-in tools and between plugins. Matches Claude Code's convention.
6. **Graceful degradation.** If an MCP server fails to spawn or crashes mid-session, Skaffen logs the error and continues without that plugin's tools. No session abort.
7. **Full parity is a follow-up bead.** This bead covers the client infrastructure. Loading all Claude Code tools (deferred tools, resources, prompts) is separate work.

## Architecture Sketch

```
┌─────────────────────────────────┐
│         Skaffen Agent Loop      │
│  (F3: OODARC)                   │
│                                 │
│  Registry.Execute(phase, name)  │
│         │                       │
│    ┌────┴────┐                  │
│    │ Router  │                  │
│    └────┬────┘                  │
│    ┌────┴──────────┐            │
│    │  Built-in?    │──yes──→ Execute directly │
│    └────┬──────────┘            │
│         │ no                    │
│    ┌────┴──────────┐            │
│    │  MCP tool?    │──yes──→ MCPManager.Call() │
│    └────┬──────────┘            │
│         │ no                    │
│         └──→ "unknown tool" err │
└─────────────────────────────────┘

MCPManager:
  - Holds map[pluginName]*MCPServer
  - LazySpawn: if server not running, spawn → initialize → cache tools
  - Call: JSON-RPC tools/call via mcp-go client
  - Shutdown: kill all subprocesses on session end
```

## Integration Points

- **F2 Registry:** `Register(tool)` at runtime after `tools/list` response. MCP tools implement the `tool.Tool` interface, delegating `Execute()` to JSON-RPC.
- **F6 Evidence:** Tool calls to MCP tools emit the same evidence events as built-in tools. No special handling needed — the agent loop already emits per-tool-call evidence.
- **Config:** New `~/.skaffen/plugins.toml` file. Could also be a `[plugins]` section in a future unified `skaffen.toml`.

## Open Questions

1. **Plugin path resolution.** How to resolve relative paths in plugins.toml — relative to the config file? CWD? Monorepo root? Needs a convention.
2. **Environment variable expansion.** Plugin.json mcpServers use `${CLAUDE_PLUGIN_ROOT}` and `${API_KEY}`. How does Skaffen set these? Does it read from its own env, or from a separate secrets config?
3. **Tool name collisions.** If two plugins expose a tool with the same name (e.g., both have "search"), the namespace prefix handles it. But should Skaffen warn? Error? Silently namespace?
4. **Server health monitoring.** If an MCP server process dies mid-session, should Skaffen auto-restart it on next tool call? How many retries before giving up?
5. **Prefetch heuristic details.** What's the right threshold? 50% of last 10 sessions? Should it be per-project or global? Deferred to v0.2.1 but worth designing the evidence schema now.
