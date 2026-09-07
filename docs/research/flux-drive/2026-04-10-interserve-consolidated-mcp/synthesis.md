---
artifact_type: review-synthesis
bead: sylveste-7505
review_target: docs/prds/2026-04-10-interserve-consolidated-mcp.md
review_type: flux-drive-strategy
stage: strategy-reviewed
verdict: REVISE_PRD
date: 2026-04-10
agents: 4
---

# Flux-Drive Synthesis — interserve PRD

**Target:** `docs/prds/2026-04-10-interserve-consolidated-mcp.md`
**Reviewers:** 4 general-purpose agents (Architecture, Correctness, Quality/Decomposition, Prior Art)
**Consensus verdict:** REVISE_PRD (3 × REVISE_PRD, 1 × BUILD-with-caveats)
**P0 findings:** 12 unique · **P1 findings:** 14 · **Severity:** HIGH — planning must not start

The review uncovered that the PRD rests on several **factually incorrect assumptions about the existing codebase**. Multiple reviewers converged independently on the same issues, which is a strong signal the problems are real, not speculation.

---

## P0 — Convergent blockers (multiple reviewers agreed)

### P0-1: `interflux` does NOT prove multi-`mcpServers` support
**Reporters:** Architecture, Prior Art (independent verification)
**Evidence:** `interverse/interflux/.claude-plugin/plugin.json` declares exactly one `mcpServers` entry (`exa`). Every `plugin.json` in `interverse/*/` has exactly one entry. The PRD's Dependencies section states "Claude Code must support multiple mcpServers entries per plugin (confirmed — already used by interflux)" — this is factually wrong.
**Impact:** The entire two-process architecture depends on this capability being supported. If Claude Code rejects multi-entry `mcpServers`, F1–F6 collapse.
**Required fix:** Add a pre-F1 spike to scaffold a throwaway plugin with 2 `mcpServers` entries and verify Claude Code loads both. Update PRD Dependencies to say "needs verification" not "confirmed."

### P0-2: Adapter contract is unimplementable against the actual SDK in use
**Reporter:** Architecture (primary) · Correctness (secondary confirmation)
**Evidence:** Five of six in-scope Python plugins use the **low-level** `mcp.server.Server` class with `@server.list_tools()` / `@server.call_tool()` decorators:
- `interverse/intercache/src/intercache/server.py:63-281`
- `interverse/intersearch/src/intersearch/server.py:23,51`
- `interverse/interdeep/src/interdeep/server.py:17-58`
- `interverse/interject/src/interject/server.py:13-31`
- `interverse/interseed/src/interseed/server.py:12-27`

The low-level class supports **exactly one** `list_tools` handler and **exactly one** `call_tool` handler per instance — a second `@list_tools` decoration overwrites the first. The PRD's `server.tool(name, handler, schema=...)` signature is a **FastMCP idiom**, not a low-level SDK API.
**Impact:** F4's "thin wrapper re-exposing existing handlers" is false. Either every plugin migrates to FastMCP first (a large rewrite), or the contract must be redesigned to pass tool-definition objects that interserve-py merges into ONE aggregated `list_tools`/`call_tool` pair.
**Required fix:** Rewrite the F2 adapter contract. Suggest: `register(server) -> list[ToolDefinition]` where `ToolDefinition = {name, schema, async_handler}`, and interserve-py runs ONE merged dispatcher that routes by tool name.

### P0-3: `interfer` is not an MCP-SDK server at all
**Reporter:** Architecture
**Evidence:** `interverse/interfer/server/mcp.py` implements `handle_request(req: dict) -> dict` as a hand-rolled stdio JSON-RPC loop proxying to a Starlette HTTP backend on port 8421. Its `pyproject.toml` has no `mcp` dependency. There is no `Server` object to register tools on.
**Impact:** interfer cannot host an adapter under any version of the contract. Its startup cost isn't even the `uv run` env-resolution problem the PRD targets — its real latency is the MLX inference subprocess.
**Required fix:** Remove interfer from F4 scope. Consider adding a separate bead for "rewrite interfer onto mcp SDK" as a prerequisite, or document that interfer stays independent.

### P0-4: `interlens` uses low-level TS SDK, incompatible with `McpServer` contract
**Reporter:** Architecture
**Evidence:** `interverse/interlens/packages/mcp/index.js:2` imports the **low-level** `Server` from `@modelcontextprotocol/sdk/server/index.js` pinned to `^0.5.0`. The other three in-scope TS plugins (interfluence, interrank, tuivision) use the **high-level** `McpServer` from `@modelcontextprotocol/sdk/server/mcp.js`. These are different classes with different registration APIs.
**Impact:** F3's single `register(server: McpServer): void` contract cannot host interlens's tools. Interlens must be upgraded to the high-level API as a prerequisite to F5 — this is a non-trivial migration (interlens is the largest TS plugin, ~20 tools).
**Required fix:** Either add "upgrade interlens to high-level TS SDK" as a prerequisite bead, or make the F3 contract accept both low- and high-level Server instances via a normalizing shim.

### P0-5: F6 "single atomic commit" is structurally impossible
**Reporter:** Correctness (primary) · cited MEMORY.md Universal Gotcha
**Evidence:** MEMORY.md [2026-03-12]: "Interverse plugins have independent git repos." A single commit cannot span 10 repositories. The claim "One commit touches 10 plugin.json files" in F6 acceptance is undeliverable as written.
**Impact:** F6 is not atomic. The cutover is inherently a multi-repo sequential operation with a partial-state window.
**Required fix:** Rewrite F6 as a scripted sequential cutover with explicit ordering (interserve first, then N plugin commits), a tracked partial-state window, and a documented "paused cutover" recovery procedure. Remove the word "atomic."

### P0-6: Rollback is O(10), not O(1)
**Reporter:** Correctness
**Evidence:** Success Metric "git revert <cutover-sha> fully restores the pre-cutover state in one command" is false because the 10 plugin.json edits live in 10 separate repos. Reverting only interserve leaves the downstream edits in place, producing double-registration or orphaned tools.
**Required fix:** Replace with `scripts/rollback.sh` that loops over the 10 plugin repos calling `git revert` per-repo, plus an `ic publish` sweep. Rehearse and time it during F6 acceptance.

### P0-7: Discovery via `../*/adapters/...` is broken in the marketplace cache layout
**Reporters:** Architecture, Correctness, Prior Art (all three flagged this)
**Evidence:** Installed plugins live under `~/.claude/plugins/cache/interagency-marketplace/<plugin>/<version>/`. When interserve is loaded from the cache, its siblings are *other versions of interserve itself*, not other plugins. `../intercache/adapters/interserve.py` does not exist at `intercache/0.2.0/adapters/interserve.py`. In local `--plugin-dir` mode the walk works; in production (marketplace install) it silently finds zero adapters.
**Required fix:** Replace filesystem-sibling discovery with one of:
- Python `importlib.metadata` entry_points + TS `package.json` `exports`
- An explicit registry file listing enrolled plugins
- Plugin-registry lookup via `CLAUDE_PLUGIN_ROOT` + marketplace API
Plus: emit a loud warning (not silent skip) if zero adapters load.

### P0-8: Tool identifier rename is a global breaking change
**Reporter:** Architecture
**Evidence:** MCP tools are namespaced as `mcp__plugin_<plugin>_<server>__<tool>` (visible in this session's deferred tool list: `mcp__plugin_intercache_intercache__cache_lookup`, etc.). Moving handlers from `intercache-mcp` to `interserve-py` changes the `<plugin>_<server>` segment to `interserve_interserve-py`, so every tool gets a new fully-qualified name at cutover. Every command, skill, and agent prompt that hardcodes an MCP tool identifier breaks at F6.
**Impact:** F6 is not "zero tool-surface change" — it's a global rename.
**Required fix:** Audit all commands/agents/skills that reference MCP tool names (`grep -r 'mcp__plugin_' os/ interverse/ .claude/`). Either plan a coordinated rename, or add a compatibility shim that exposes tools under their legacy identifiers via aliasing. Treat F6 as a breaking change in the PRD.

### P0-9: Import-time side effects are not caught by "per-adapter try/except"
**Reporter:** Correctness
**Evidence:** intercache's `server.py` holds module-level globals (`_manifests`, `_sessions`, `_blob_store` at lines 29-31) and imports `signal` at line 13 to install SIGINT handlers. When interserve-py imports six adapters, **every transitive import runs at import time**. Per-adapter try/except around `register()` does not catch failures during `import adapter_module`.
**Required fix:** Specify that discovery wraps `importlib.import_module` in its own try/except, separate from `register()`. Document in `py/README.md` that adapters must NOT execute side effects at module top level (no signal handlers, no `asyncio.run`, no env-var reads that raise, no DB connection opens).

### P0-10: `interfluence` TS entrypoint runs `main()` at module top
**Reporter:** Correctness
**Evidence:** `interverse/interfluence/server/src/index.ts` calls `main().catch(console.error)` at the bottom and instantiates `new McpServer(...)` at module top. If interserve-ts imports this file to reach the tool-registration helpers, it will spin up a second McpServer and race the parent's stdio transport.
**Required fix:** Require each TS plugin to refactor `index.ts` to export handlers/registration without side effects. Top-level `main()` moves to `bin.ts` or is guarded by `if (import.meta.url === ...)`. Add this as an explicit F5 precondition.

### P0-11: F4/F5 bundle parallelizable work and mask partial failures
**Reporter:** Quality
**Impact:** 6 Python adapters and 4 TS adapters are independent thin wrappers touching disjoint files. Bundling forces serial execution and produces confusing failure modes ("F4 failed" when 5/6 landed).
**Required fix:** Split F4 → F4a–F4f (one per plugin), F5 → F5a–F5d (one per plugin). Keep one umbrella bead or track as epic children with intra-epic dependencies.

### P0-12: Observability and performance-regression gates are missing
**Reporter:** Quality
**Impact:** The PRD commits to process count (19→11) but NOT to cold-start wall time or memory RSS. interserve-py could cold-start *slower* than the legacy sum (adapter discovery + 6 chained imports). The stated goal is startup latency — we need a hard gate.
**Required fix:** Add to F6 Success Metrics: "interserve-py `initialize`-to-ready ≤ median of the 6 legacy servers' sequential cold-start sum." Add to F2/F3 AC: "JSON-per-line logs on stderr with `{ts, level, plugin, tool, event, err}` and an example in `py/README.md`."

---

## P1 — Should address

- **P1-1** (Correctness): Per-tool try/except is insufficient for async streaming handlers (interdeep's `extract_batch`, intersearch's `embedding_index`). A mid-stream raise has already sent partial frames; the MCP contract for mid-stream errors is unspecified. **Fix:** Scope error-isolation claim to non-streaming handlers in v1, or define mid-stream failure semantics explicitly.
- **P1-2** (Architecture, Correctness): Shared asyncio loop and signal-handler conflicts. First adapter to install a signal handler wins. Any adapter calling `asyncio.run` / `nest_asyncio.apply` corrupts the shared loop. **Fix:** F2 AC forbids these patterns; add a grep-based lint in F4/F5.
- **P1-3** (Architecture): `tldr-swinton` is Python (confirmed by reviewer — `pyproject.toml:92-99` declares `tldr-mcp` with `mcp>=1.0.0`). Must be added to F4 scope, not left as Open Question 1. **Fix:** Decide now, add to F4.
- **P1-4** (Quality): F1's "plugin loads without error" AC references `claude --plugin-dir` which is not a real flag. **Fix:** Name the actual validator (e.g., `ic publish --dry-run`, `rig-drift --plugin interserve`, or a concrete test command).
- **P1-5** (Quality): F2 unit-test fixture location is unspecified. **Fix:** Commit to `py/tests/fixtures/adapter_ok/` and `py/tests/fixtures/adapter_broken/` in F2 AC.
- **P1-6** (Quality): No AC for updating migrated plugins' AGENTS.md/CLAUDE.md to reflect the interserve handover. **Fix:** Add F6 AC or explicit deferral.
- **P1-7** (Prior Art): Brainstorm's "none found" prior-art claim is incomplete. Mature aggregators exist (**metatool-ai/metamcp**, **adamwattis/mcp-proxy-server**, **MCPEz**, **Envoy AI Gateway MCP**) — none solve the process-count problem (they all spawn child processes), but the PRD should cite them with a one-paragraph "prior art & why not" section.
- **P1-8** (Prior Art): MCP spec roadmap lists gateway/proxy patterns as upcoming. **Fix:** Open an issue in `anthropics/claude-code` asking about native shared MCP runtime / plugin-pool support; if upstream is planning this, time-box interserve as a bridge.
- **P1-9** (Prior Art): Error-isolation conventions from metamcp (stderr piping, per-child isolation) are worth mirroring rather than reinventing.
- **P1-10** (Prior Art): Discovery via `importlib.metadata` entry_points + `package.json` `exports` is strictly better than filesystem globbing.
- **P1-11** (Quality): Health-check tool (PRD Open Q3) should be **required**, not optional. With 10 adapters in 2 processes, "which adapter failed?" is the primary debugging question.
- **P1-12** (Quality): Publish-pipeline smoke test should be in F1, not discovered in F6. **Fix:** F1 AC includes `ic publish --dry-run` of an empty interserve.
- **P1-13** (Quality): Open Question 4 (metrics capture format) is deferred homework, not exploratory. Move to F1 as "define `scripts/snapshot.sh` and the snapshot JSON schema."
- **P1-14** (Architecture): The "tool names are globally unique, verified by rig-drift" claim has no cited source. Actually run rig-drift before F2 and capture the output.

---

## P2 — Nice to have

- interdeep CLAUDE.md says "FastMCP" but the code uses low-level SDK (existing doc drift)
- Non-goal "Shared DB pooling" ignores that module-level singletons in intercache make pooling *automatic* when imported twice — document as observed behavior
- Rollback rehearsal AC doesn't specify the test environment
- Calibration vs. interop PRD: interserve has less-specific ACs; bringing it to interop's granularity is achievable in the revision pass

---

## Alternative worth considering (Architecture reviewer, P2)

**Pre-forked supervisor / worker-pool pattern.** A tiny Python parent forks N workers (one per plugin, each running the unchanged `intercache-mcp` / `intersearch-mcp`), sharing the `uv` venv resolution and import cache. Preserves per-plugin isolation (a crash in one worker doesn't kill others), eliminates the adapter contract entirely (no plugin code changes), and still hits the startup-latency win because `uv run` env resolution happens ONCE in the parent. Tradeoff: still N Python heaps (memory overhead), and Claude Code still sees N stdio transports unless the supervisor multiplexes them. **Worth one afternoon of prototyping before committing to the adapter-rewrite path.**

---

## Verdict summary

| Reviewer | Verdict | Top concern |
|---|---|---|
| Architecture | REVISE_PRD | Adapter contract unimplementable against actual SDK |
| Correctness | REVISE_PRD | F6 non-atomic, rollback O(10), import-time side effects |
| Quality/Decomposition | REVISE_PRD | F4/F5 bundled, observability + perf gates missing |
| Prior Art | BUILD (w/ caveats) | multi-mcpServers unverified; replace fs-walk discovery with entry_points |

**Consensus:** The infrastructure goal is valid and the diamond dependency graph is the right shape, but the PRD rests on factual errors about the SDK landscape, the plugin.json precedent, the marketplace cache layout, and git-repo topology. A revision pass is required before planning can begin.

---

## Recommended next steps (ordered)

1. **Pre-F1 spike:** Build a two-`mcpServers`-entry throwaway plugin and verify Claude Code loads both. Blocker for everything else.
2. **Revise the adapter contract** in the PRD against the low-level `mcp.server.Server` API (and decide the fate of low-level TS SDK in interlens).
3. **Remove `interfer` from F4 scope** (or add a prerequisite bead to rewrite it).
4. **Add `tldr-swinton`** to F4 scope (resolve Open Q1).
5. **Replace filesystem discovery** with entry_points / package exports.
6. **Rewrite F6** as sequential multi-repo cutover. Rewrite rollback as O(10) script.
7. **Split F4/F5** into per-plugin sub-features.
8. **Add observability + performance gates** to F2/F3/F6 acceptance.
9. **Audit tool-identifier usage** across commands/agents/skills; plan rename or shim.
10. **Optional:** prototype the pre-forked supervisor alternative (one afternoon).
