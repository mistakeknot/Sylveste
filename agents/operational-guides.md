# Operational Guides

Consolidated reference guides — read the relevant guide before working in that area.

| Guide | When to Read | Path |
|-------|-------------|------|
| Repo Operations | Before editing root-tracked files, pushing, or adding links to subprojects | `docs/guides/repo-ops.md` |
| Plugin Troubleshooting | Before debugging plugin errors, creating hooks, publishing | `docs/guides/plugin-troubleshooting.md` |
| Shell & Tooling Patterns | Before writing bash hooks, jq pipelines, or bd commands | `docs/guides/shell-and-tooling-patterns.md` |
| Multi-Agent Coordination | Before multi-agent workflows, subagent dispatch, or token analysis | `docs/guides/multi-agent-coordination.md` |
| Data Integrity Patterns | Before WAL, sync, or validation code in TypeScript | `docs/guides/data-integrity-patterns.md` |
| Secret Scanning Baseline | Before rolling out or auditing secret scanning policy across repos | `docs/guides/secret-scanning-baseline.md` |
| Interband Sideband Protocol | Before working on sideband communication between agents | `docs/guides/interband-sideband-protocol.md` |
| Beads 0.51 Upgrade | For completed migration status and post-migration operations | `docs/guides/beads-0.51-upgrade-plan.md` |
| Institutional Learnings | Before implementing bug fixes, patterns, or working in gotcha-prone areas | `docs/solutions/` via `interflux:learnings-researcher` |
| MCP Server Criteria | Before deciding whether a new plugin needs an MCP server | [`docs/canon/mcp-server-criteria.md`](../docs/canon/mcp-server-criteria.md) |

**Searching prior solutions:** Before implementing a fix or pattern, search `docs/solutions/` for prior art. Use `Grep` with `pattern="tags:.*(keyword)" path=docs/solutions/` on frontmatter tags. For structural search, spawn the `interflux:learnings-researcher` agent. Always read `docs/solutions/patterns/critical-patterns.md` for must-know patterns.

**Prior art check (before building new systems):** Before building new infrastructure, tooling, or search/indexing systems from scratch, run the prior art pipeline:

1. **Local assessment docs** — check if the domain was already evaluated:
   ```bash
   grep -ril "<2-3 keywords>" docs/research/assess-*.md 2>/dev/null
   ```
   If a tool has "adopt" or "port-partially" verdict, integrate it instead of rebuilding.
2. **Existing plugins/beads** — check for overlap with current work:
   ```bash
   ls interverse/*/CLAUDE.md 2>/dev/null | xargs grep -li "<keywords>" 2>/dev/null
   bd search "<keywords>" 2>/dev/null
   ```
3. **Web search (conditional)** — only when creating a new system from scratch (not feature additions, bug fixes, refactors):
   ```
   WebSearch: "open source <what we're building> CLI tool 2025 2026"
   ```
4. **Deep evaluation** — if a candidate is found, clone to `research/` for code-level analysis:
   ```bash
   git clone --depth=1 https://github.com/<owner>/<repo> research/<repo>
   ```
   Write assessment to `docs/research/assess-<repo>.md` with verdict (adopt/port-partially/inspire-only/skip).

This pipeline is enforced in `/clavain:brainstorm` (Phase 1.1), `/clavain:strategy` (Phase 0), and `/clavain:write-plan` (Step 0). Skip for feature additions, bug fixes, refactors, config changes, and UI tweaks.

## Operational Notes & Research

Operational lessons (Oracle CLI, git credentials, tmux, SQLite gotchas, plugin publishing) and research references (search improvements, code compression, key papers) are in [docs/guides/agents-operational-notes.md](../docs/guides/agents-operational-notes.md).
