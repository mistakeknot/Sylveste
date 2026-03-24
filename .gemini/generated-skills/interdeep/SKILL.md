---
name: interdeep
description: "Deep research plugin — content extraction and research orchestration via MCP tools."
---
# Gemini Skill: interdeep

You have activated the interdeep capability.

## Base Instructions
# interdeep — Agent Guide

Deep research plugin for Claude Code. Content extraction via trafilatura/Playwright and multi-phase research orchestration via MCP tools, skills, and agents.

## Canonical References

1. `PHILOSOPHY.md` — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol

Review `PHILOSOPHY.md` during:
- Intake/scoping
- Brainstorming
- Planning
- Execution kickoff
- Review/gates
- Handoff/retrospective
- Upstream-sync adoption/defer decisions

For brainstorming/planning outputs, add two short lines:
- `Alignment:` one sentence on how the proposal supports the module north star.
- `Conflict/Risk:` one sentence on any tension with philosophy (or `none`).

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.

## Execution Rules

- Keep changes small, testable, and reversible.
- Run validation commands from `CLAUDE.md` before completion.
- Commit only intended files and push before handoff.

---

## Quick Reference

| Item | Value |
|------|-------|
| Language | Python 3.12+ |
| Build | hatchling |
| MCP tools | `extract_content`, `extract_batch`, `compile_report`, `research_status` |
| Skills | `deep-research` (5-phase orchestration) |
| Agents | `research-planner` (haiku), `source-evaluator` (haiku), `report-compiler` (sonnet) |
| Commands | `/research [quick\|balanced\|deep] <query>` |
| Dependencies | trafilatura, aiohttp, mcp, json-repair |
| Optional deps | playwright (browser extraction fallback) |

## Overview

interdeep provides two capabilities:

1. **Content extraction** — fetch and clean web content via trafilatura (fast path) with optional Playwright fallback for JavaScript-heavy pages. Exposed as MCP tools for any agent to call.
2. **Research orchestration** — a 5-phase protocol (Orient, Search, Extract, Synthesize, Persist) defined in `SKILL.md` that composes interdeep's extraction tools with companion plugins for search, synthesis, and knowledge storage.

## Architecture

```
interdeep/
  .claude-plugin/
    plugin.json           # Plugin manifest
  src/interdeep/
    __init__.py
    server.py             # FastMCP server — 4 tools
    extraction/
      __init__.py
      models.py           # ExtractionResult dataclass
      trafilatura_ext.py  # trafilatura wrapper
      playwright_ext.py   # Playwright fallback (optional)
      hybrid.py           # Router + batch extraction
    reports/
      __init__.py
      markdown.py         # Markdown report compiler
  skills/
    deep-research/
      SKILL.md            # 5-phase research protocol
  agents/
    research-planner.md   # Query decomposition (haiku)
    source-evaluator.md   # Source credibility (haiku)
    report-compiler.md    # Report assembly (sonnet)
  commands/
    research.md           # /research slash command
  scripts/
    launch-mcp.sh         # MCP server launcher
    bump-version.sh       # Version bump helper
  tests/
    test_extraction.py    # Extraction unit tests
    test_server.py        # MCP server tool tests
    structural/           # Plugin standard structural tests
```

## How It Works

### Content Extraction

The extraction layer follows a trafilatura-first strategy:

1. `trafilatura_ext.extract_with_trafilatura(url)` — fetches and extracts via trafilatura. Fast, handles most pages.
2. `playwright_ext.extract_with_playwright(url)` — Playwright browser fallback for JS-rendered content. Only used if trafilatura output is too short (< 200 chars).
3. `hybrid.extract_hybrid(url=, html=)` — router that tries trafilatura first, falls back to Playwright if available and needed.
4. `hybrid.extract_batch_async(urls)` — concurrent extraction with configurable parallelism.

All extractors return `ExtractionResult(url, content, title, method, content_length, metadata)`.

### Research Orchestration

The `deep-research` skill defines a 5-phase protocol:

1. **Orient** — research-planner agent decomposes query into sub-queries with source routing.
2. **Search** — dispatches to interject/interflux for web/academic/community search.
3. **Extract** — calls interdeep MCP tools to fetch and clean content from URLs.
4. **Synthesize** — source-evaluator filters findings, report-compiler assembles the report.
5. **Persist** — optionally stores report in interknow for future retrieval.

## Component Conventions

- **MCP tools** are stateless — no session state, no side effects beyond extraction.
- **Agents** return structured JSON. The host agent parses and routes the output.
- **Skills** contain orchestration logic. The host agent (Claude) is the brain.
- **Extraction** always returns `ExtractionResult`, never raises on failure (returns `method="failed"`).

## Integration Points

| Companion | Integration | Required? |
|-----------|------------|-----------|
| interject | Search providers (Exa, arXiv, HN, GitHub) via `interject_search` | recommended |
| interflux/exa | Web search via `web_search_exa` | optional |
| interknow | Knowledge storage via `interknow_qmd__search` | optional |
| intercache | Result caching | optional |
| interlens | Thinking gap detection via `detect_thinking_gaps` | optional |
| intersynth | Advanced synthesis | optional |

## Testing

```bash
# Unit tests (extraction + server)
uv run pytest tests/test_extraction.py tests/test_server.py -q

# Structural tests (plugin standard compliance)
cd tests && uv sync && uv run pytest -q

# All tests
uv run pytest tests/test_extraction.py tests/test_server.py -q && cd tests && uv run pytest -q && cd ..
```

## Known Constraints

- Playwright is optional — if not installed, JS-heavy pages get trafilatura's best effort.
- No built-in search — interdeep extracts content from URLs. Search providers come from companion plugins.
- Report quality depends on extraction quality. Paywalled or bot-blocked sites will yield empty extractions.
- Batch extraction is async but respects `max_concurrent` to avoid overwhelming target servers.


