---
artifact_type: prd
bead: sylveste-7505
stage: design
---
# PRD: Interserve — Consolidated Interverse MCP Server

## Problem

Claude Code sessions currently spawn ~19 MCP server subprocesses at startup. Ten of those are per-plugin Python or Node processes whose cold-start is dominated by environment resolution (`uv run`, `pnpm mcp`, `node dist/...`), not actual work. The resulting startup latency, memory footprint, and log noise are all roughly 10× what they need to be for the Python/TS tools in interverse.

## Solution

Ship a new plugin `interverse/interserve/` containing exactly **two** long-lived MCP server processes — one Python (`interserve-py`), one TypeScript (`interserve-ts`) — each of which discovers `adapters/interserve.{py,ts}` modules in sibling plugins at startup and multiplexes all their tools through a single server instance. Go-based MCP servers (already fast to cold-start) and external wrappers (qmd, exa) stay independent. Cutover is a single atomic commit; rollback is a single revert.

## Features

### F1: interserve plugin scaffold
**What:** Create `interverse/interserve/` with `.claude-plugin/plugin.json` declaring two `mcpServers` entries (`interserve-py` and `interserve-ts`), plus AGENTS.md, CLAUDE.md, README.md, and the directory layout (`py/`, `ts/`, `scripts/`). No tool registration yet — this delivers a plugin that loads cleanly and starts two empty MCP servers.
**Acceptance criteria:**
- [ ] `claude --plugin-dir interverse/interserve` loads without error
- [ ] Both `interserve-py` and `interserve-ts` MCP servers start, respond to `initialize`, and return an empty `tools/list`
- [ ] `python3 -c "import json; json.load(open('interverse/interserve/.claude-plugin/plugin.json'))"` passes
- [ ] `rig-drift` (or equivalent) reports both servers as healthy

### F2: Python adapter framework (`interserve-py`)
**What:** Python MCP server implementation that discovers `adapters/interserve.py` files in sibling plugin directories, imports each, and calls `register(server)`. Each adapter wires its plugin's existing tool handlers onto the shared `McpServer` instance. Per-adapter and per-tool try/except so one broken adapter or one throwing handler cannot take down the whole process.
**Acceptance criteria:**
- [ ] `uv run interserve-py` starts a single MCP server process
- [ ] Discovery walks `../*/adapters/interserve.py` relative to the interserve plugin root
- [ ] Documented `register(server: McpServer) -> None` contract in `py/README.md`
- [ ] Per-adapter import failure logs `adapter_load_failed:<plugin>` and continues
- [ ] Per-tool handler failure logs `tool_error:<plugin>:<tool>` and returns an MCP error to the caller (does NOT crash server)
- [ ] Unit test: loads two synthetic adapters, verifies both sets of tools appear in `tools/list`
- [ ] Unit test: adapter that raises in `register` does not prevent a second adapter from loading

### F3: TypeScript adapter framework (`interserve-ts`)
**What:** Node/TypeScript MCP server symmetric to F2. Discovers `adapters/interserve.ts` (or compiled `.js`) in sibling plugin directories, dynamically imports, calls the default-exported or named `register` function. Same error isolation guarantees as F2. Bundled via esbuild/tsc to `ts/dist/index.js`.
**Acceptance criteria:**
- [ ] `node ts/dist/index.js` starts a single MCP server process
- [ ] Discovery walks `../*/adapters/interserve.{ts,js}` relative to interserve plugin root
- [ ] Documented `register(server: McpServer): void` contract in `ts/README.md`
- [ ] Per-adapter import failure logs `adapter_load_failed:<plugin>` and continues
- [ ] Per-tool handler failure logs `tool_error:<plugin>:<tool>` and returns an MCP error to the caller
- [ ] Unit test equivalents to F2's tests

### F4: Python plugin adapters
**What:** Add `adapters/interserve.py` to each of the six in-scope Python plugins: **intercache, interdeep, interfer, interject, intersearch, interseed**. Each adapter imports its plugin's existing handlers and registers them via the F2 contract. Original per-plugin `mcpServers` entries in `plugin.json` stay in place — interserve and the legacy servers both run until cutover (F6).
**Acceptance criteria:**
- [ ] Six adapter files exist, each no more than a thin wrapper that re-exposes existing handlers
- [ ] No new business logic added — adapters only re-export
- [ ] With F2 running, `tools/list` on interserve-py returns the union of all six plugins' tools
- [ ] Tool names are identical to the legacy servers (verified by comparing `tools/list` against legacy server output for each plugin)
- [ ] Each plugin still works via its legacy MCP entry (dual-stack until F6)

### F5: TypeScript plugin adapters
**What:** Add `adapters/interserve.ts` to each of the four in-scope TypeScript plugins: **interfluence, interlens, interrank, tuivision**. Each adapter imports existing handlers and registers them via the F3 contract. Dual-stack with legacy servers until F6.
**Acceptance criteria:**
- [ ] Four adapter files exist, each a thin wrapper re-exposing existing handlers
- [ ] With F3 running, `tools/list` on interserve-ts returns the union of all four plugins' tools
- [ ] Tool names match the legacy servers exactly (verified)
- [ ] Each plugin still works via its legacy MCP entry until F6

### F6: Big-bang cutover
**What:** Single atomic commit removes `mcpServers` entries from all ten consolidated plugins' `plugin.json` files. interserve becomes the sole MCP entry point for those tools. Verify total tool count across the ecosystem is unchanged. Document rollback (single `git revert`).
**Acceptance criteria:**
- [ ] One commit touches 10 `plugin.json` files + any publish/marketplace caches
- [ ] Pre-cutover tool-count snapshot captured to `docs/reflect/2026-04-10-interserve-pre-cutover-tool-snapshot.json`
- [ ] Post-cutover tool-count snapshot captured; diff against pre-snapshot shows zero missing tools
- [ ] Session startup measured before and after: process count drops from ~19 to ~11 (recorded in reflect doc)
- [ ] Rollback rehearsed: `git revert <sha>` restores all 10 plugins in one operation and tools still work
- [ ] `ic publish` sweeps all affected plugins so marketplace cache matches git

## Non-goals

- **Go MCP server consolidation.** interlock, interlab, intermap, intermux, intermix keep their own MCP entries. Go cold-start is already ~20ms — no benefit.
- **External-wrapper consolidation.** interknow/qmd and interflux/exa wrap external npm tools (`qmd`, `exa-mcp-server`). They stay independent.
- **interkasten consolidation.** interkasten has webhook infrastructure (Caddy, systemd, DNS) that is not tool-shaped and does not fit the adapter pattern.
- **Shared DB/API connection pooling.** Each adapter still initializes its own state. Pool sharing is a future optimization, not a launch requirement.
- **Hot reload of adapters.** v1 ships with restart-required reloads. Hot reload is YAGNI.
- **Tool namespacing / prefixing.** Tool names stay globally unique — no `interserve:cache_lookup` style prefixes.
- **Cross-language bridging.** No Python↔TS IPC. Two processes, hard language boundary.

## Dependencies

- Claude Code must support multiple `mcpServers` entries per plugin (confirmed — already used by interflux).
- `uv` available on PATH for Python startup (already required ecosystem-wide).
- `pnpm` or `node` + compiled bundle for TS startup (already required).
- rig-drift or equivalent tool count validator for F1/F4/F5/F6 acceptance.
- No dependency on interphase, interspect, or any clavain component — interserve is infrastructure-level.

## Open Questions

1. **tldr-swinton inclusion.** The brainstorm classified tldr-swinton as "Go-based, remains independent," but ground-truth inspection shows it launches via `uv run tldr-mcp` — it's Python. Should it be added to F4's migration list? **Recommendation:** defer to planning step; worth ~15 additional minutes of adapter work and one more migrated plugin.
2. **Startup ordering.** Some adapters may touch shared infrastructure (e.g., intercache). Does load order matter? Probably not if adapters initialize lazily on first tool call — but worth a single pass of confirmation during F2/F3.
3. **Health-check tool.** Should `interserve-py` and `interserve-ts` each expose a built-in `interserve_status` tool that reports loaded-adapter health? Useful for debugging, minimal cost, not in acceptance criteria but easy to add during F2/F3.
4. **Metrics capture for F6 reflection.** What exact measurements should the pre/post snapshots contain beyond process count and tool count? Memory RSS? Cold-start wall time? Decide before F1 starts so F2/F3 emit the right instrumentation.

## Success Metrics (Epic DoD)

- **Process count:** Session startup drops from 19 MCP subprocesses to 11 (±1), verified by `ps -ef | grep mcp` or Claude Code session telemetry.
- **Tool count preservation:** Pre-cutover and post-cutover `tools/list` across all interserve-managed servers enumerate the exact same set (zero missing, zero duplicated).
- **Rollback cost:** `git revert <cutover-sha>` fully restores the pre-cutover state in one command, verified during F6 acceptance.
- **Error isolation:** A deliberately injected broken adapter (F2/F3 unit test) does not prevent the rest of the server from starting or serving tools.
