---
artifact_type: brainstorm
bead: sylveste-7505
stage: discover
---

# Interserve: Consolidated Interverse MCP Server

## What We're Building

A new plugin `interserve` (at `interverse/interserve/`) that replaces ~10 individual MCP server processes with two consolidated servers: one Python (`interserve-py`) and one TypeScript (`interserve-ts`). Each original plugin ships an adapter module; interserve discovers and loads these adapters at startup, multiplexing all tools through its two processes.

**Scope:** Python servers (intercache, interdeep, interject, intersearch, interseed, interfer) and TypeScript servers (interfluence, interrank, interlens, tuivision). Go-based servers (interlock, intermux, intermap, interlab, tldr-swinton) remain independent — they're already compiled binaries with minimal startup cost.

**Target:** Session startup drops from ~19 MCP server processes to ~11 (2 consolidated + 9 remaining Go/hybrid/special-purpose).

## Why This Approach

**Two processes, one plugin** was chosen over a single-gateway or proxy architecture because:

- **No cross-language bridging.** Python tools stay in Python, TypeScript tools stay in TypeScript. No IPC serialization overhead, no subprocess management, no foreign function interfaces.
- **Claude Code already supports multiple `mcpServers` per plugin.** Two entries in plugin.json is the simplest path — no framework invention needed.
- **Adapter-in-plugin registration** preserves plugin independence. Each plugin owns its tool definitions and handler logic. interserve only owns the server lifecycle and adapter discovery. Adding or removing a tool doesn't require editing interserve itself.
- **Big-bang cutover** is viable because the adapters are thin wrappers around existing handlers. If interserve breaks, reverting is one commit: restore the old `mcpServers` entries in each plugin's plugin.json.

**Why not consolidate Go servers too?** Go MCP servers compile to single binaries with ~20ms startup. The startup cost problem is Python (`uv run` environment resolution) and Node (`node dist/` module loading), not Go.

## Key Decisions

1. **Name: `interserve`** — reuses an archived plugin name. Lives at `interverse/interserve/`.

2. **Two mcpServers entries:**
   - `interserve-py`: Python process via `uv run interserve-py`. Discovers `adapters/interserve.py` in each Python plugin.
   - `interserve-ts`: Node process via `node dist/index.js`. Discovers `adapters/interserve.ts` in each TypeScript plugin.

3. **Adapter contract (Python):**
   ```python
   # intercache/adapters/interserve.py
   def register(server: McpServer) -> None:
       """Register all MCP tools from this plugin."""
       server.tool("cache_lookup", cache_lookup_handler, schema=...)
       server.tool("cache_store", cache_store_handler, schema=...)
   ```
   Each adapter imports its plugin's existing handlers and registers them. No new business logic.

4. **Adapter contract (TypeScript):**
   ```typescript
   // interrank/adapters/interserve.ts
   export function register(server: McpServer): void {
     server.tool("leaderboard", leaderboardHandler, { schema: ... });
   }
   ```

5. **Discovery mechanism:** interserve walks `../*/adapters/interserve.{py,ts}` at startup. Plugins that don't have an adapter file are silently skipped — they keep their own MCP server.

6. **Migration strategy:** Big-bang swap. One commit removes `mcpServers` from ~10 plugin.json files and adds interserve's plugin.json with both consolidated entries. Rollback is a single revert.

7. **Tool namespacing:** Tool names stay as-is (e.g., `cache_lookup`, `leaderboard`). No prefix needed — MCP tool names are already globally unique across the ecosystem (verified by existing rig-drift checks).

8. **Shared resources:** Each adapter initializes its own state (DB connections, API clients). interserve doesn't manage shared connections — that's a future optimization, not a launch requirement.

## Open Questions

- **Hot reload:** Should interserve support reloading adapters without restarting the process? Useful during development but adds complexity. Likely YAGNI for v1.
- **Health checks:** Should interserve expose a health/status tool that reports which adapters loaded successfully? Useful for debugging but not critical.
- **interknow (qmd) and interflux (exa):** These use custom launch scripts and may not fit the adapter pattern cleanly. Evaluate during planning whether they're in-scope or remain independent.
- **Error isolation:** If one adapter's handler throws, should it take down the whole server or be caught? Per-tool try/catch is cheap and probably worth it.
- **Startup ordering:** Some adapters may depend on shared infrastructure (e.g., intercache). Does registration order matter? Probably not if adapters initialize lazily.
