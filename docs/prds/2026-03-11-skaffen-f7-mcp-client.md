---
artifact_type: prd
bead: Demarch-o5u
stage: design
---
# PRD: Skaffen F7 — MCP Stdio Client for Interverse Plugins

## Problem

Skaffen v0.1 shipped with 7 built-in tools (read, write, edit, bash, grep, glob, ls) but no way to use Interverse plugin tools. Claude Code has access to 53 plugins with MCP servers — intermap, interlens, interject, tldr-swinton, etc. Skaffen needs the same capability, with controlled scope and phase-aware gating.

## Solution

Config-driven MCP stdio client that discovers plugins from `plugins.toml`, spawns MCP server subprocesses on demand, and registers their tools into Skaffen's F2 registry with per-plugin phase gating. Uses the official MCP Go SDK (`modelcontextprotocol/go-sdk`) for protocol handling.

## Features

### F1: Plugin Config Parsing

**What:** Parse `plugins.toml` to discover which MCP servers to load, with per-plugin phase gating.

**Acceptance criteria:**
- [ ] Reads `~/.skaffen/plugins.toml` (global) and `./skaffen.toml` `[plugins]` section (project-level), project overrides global
- [ ] Each plugin entry specifies: `path` (to plugin.json), `phases` (allowed OODARC phases), optional `env` overrides
- [ ] Parses `mcpServers` from referenced plugin.json files — extracts `command`, `args`, `env`, `type` (only `stdio` supported)
- [ ] Expands `${CLAUDE_PLUGIN_ROOT}` to the plugin.json parent directory, other `${VAR}` from process environment
- [ ] Relative paths in `path` resolved relative to the config file location
- [ ] Missing or malformed plugin.json logs a warning and skips that plugin (no abort)
- [ ] Unit tests: config parsing, env expansion, path resolution, error cases

### F2: MCP Stdio Client

**What:** Spawn MCP server subprocesses and communicate via JSON-RPC 2.0 over stdio using the official Go SDK.

**Acceptance criteria:**
- [ ] Uses `modelcontextprotocol/go-sdk` `CommandTransport` to spawn stdio subprocesses
- [ ] Performs MCP `initialize` handshake (protocol version, client info, capabilities)
- [ ] Calls `tools/list` to discover available tools and their JSON schemas
- [ ] Calls `tools/call` to execute tools, returning text content results
- [ ] Handles JSON-RPC errors gracefully — returns `ToolResult{IsError: true}` with error message
- [ ] Context-aware: cancellation propagates to subprocess via context.Context
- [ ] Unit tests with a mock MCP server (in-process or test binary)

### F3: Registry Integration

**What:** Adapter that wraps MCP tools as `tool.Tool` implementations and registers them into F2's Registry with phase gating.

**Acceptance criteria:**
- [ ] `MCPTool` struct implements `tool.Tool` interface: `Name()`, `Description()`, `Schema()`, `Execute()`
- [ ] Tool names namespaced as `plugin_server_toolname` (underscores, not colons — valid Go identifiers and shell-safe)
- [ ] `Execute()` delegates to the MCP client's `tools/call` with JSON parameter passthrough
- [ ] `RegisterMCPTools(registry, pluginName, tools, phases)` adds tools to registry with per-plugin phase gating
- [ ] Phase gating: tools registered into specified phases only (extending `Registry.gates` map)
- [ ] Default phase if not specified in config: `["build"]` only
- [ ] Registry.Register() extended to accept phase list (currently hardcodes build-only)
- [ ] Unit tests: MCPTool implements interface correctly, phase gating works, namespace collisions handled

### F4: Lifecycle Management

**What:** Lazy spawn, graceful shutdown, and crash recovery for MCP server subprocesses.

**Acceptance criteria:**
- [ ] `MCPManager` struct manages map of plugin name → active MCP client session
- [ ] Lazy spawn: server subprocess started on first tool call to that plugin, not at Skaffen startup
- [ ] After spawn: `initialize` + `tools/list` + register into F2 registry (one-time per session)
- [ ] Server persists for session lifetime (persistent sidecar pattern)
- [ ] Graceful shutdown: `MCPManager.Shutdown()` sends shutdown to all active servers, kills subprocesses, called on Skaffen exit
- [ ] Crash recovery: if `tools/call` fails with EOF/broken pipe, attempt one respawn + reinitialize. If respawn fails, mark plugin as unavailable for remainder of session and log error
- [ ] Max 3 respawn attempts per plugin per session (prevents infinite restart loops)
- [ ] Skaffen continues without the failed plugin's tools — no session abort
- [ ] Unit tests: lazy spawn behavior, shutdown cleanup, crash recovery with retry limits

## Non-goals

- **Full Claude Code tool parity.** This bead covers MCP tool loading. Deferred tools, resources, prompts, and the full 200+ tool surface are a follow-up bead.
- **Intelligent prefetch.** Evidence-based pre-spawning deferred to v0.2.1. This ships with pure lazy spawn.
- **Plugin auto-discovery.** No scanning of `interverse/` or `~/.claude/plugins/`. Explicit config only.
- **MCP resources or prompts.** Only `tools/list` and `tools/call` — the other MCP primitives are out of scope.
- **SSE or HTTP transport.** Stdio only. Other transports are a future concern.

## Dependencies

- **F2 Tool Registry (Demarch-hop, done):** Runtime `Register()` extension point. Needs minor extension to accept phase list.
- **Official MCP Go SDK:** `github.com/modelcontextprotocol/go-sdk` — new dependency for Skaffen's go.mod.
- **Interverse plugin.json schema:** `mcpServers` field structure (documented in `docs/canon/plugin-standard.md`).
- **BurntSushi/toml or pelletier/go-toml:** For plugins.toml parsing. No TOML dependency in Skaffen yet.

## Open Questions

1. **TOML library choice.** `BurntSushi/toml` (standard, simple) vs `pelletier/go-toml` (v2, richer). Either works — lean toward BurntSushi for simplicity.
2. **Environment variable secrets.** Plugin.json `env` fields reference `${API_KEY}` etc. Skaffen reads these from process env. Should there be a `~/.skaffen/secrets.toml` for plugin-specific secrets? Probably overkill for v0.2 — process env is sufficient.
3. **go-sdk maturity.** The official SDK is relatively new. If we hit blocking issues, fallback is `mark3labs/mcp-go` (already in monorepo via intermap) or a thin custom client.
