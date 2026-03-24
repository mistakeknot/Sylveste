---
name: tldr-swinton
description: "Token-efficient code reconnaissance for LLMs. Autonomous skills save 48-85% tokens via diff-context, semantic search, structural patterns, and symbol analysis. Includes MCP server for direct tool integration."
---
# Gemini Skill: tldr-swinton

You have activated the tldr-swinton capability.

## Base Instructions
# AGENTS.md - AI Agent Instructions for tldr-swinton

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](../../PHILOSOPHY.md) during:
- Intake/scoping
- Brainstorming
- Planning
- Execution kickoff
- Review/gates
- Handoff/retrospective

For brainstorming/planning outputs, add two short lines:
- **Alignment:** one sentence on how the proposal supports the module's purpose within Demarch's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.


Token-efficient code analysis tool for LLMs. Fork of llm-tldr with fixes for TypeScript, Rust, and multi-language support.

**Version**: 0.7.14
**Quick start**: Run `tldrs quickstart` for a concise reference guide.

## Quick Reference

```bash
# Install (development)
uv pip install -e .
uv pip install -e ".[semantic-ollama]"  # FAISS backend: Ollama embeddings
uv pip install -e ".[semantic-colbert]" # ColBERT backend: best quality, ~1.7GB PyTorch
uv pip install -e ".[full]"            # Full stack (Ollama + tiktoken)

# Smoke check
tldrs extract src/tldr_swinton/modules/core/api.py
tldrs structure src/

# After code changes
find . -name "*.pyc" -delete && find . -name "__pycache__" -type d -exec rm -rf {} +
uv pip install -e .
```

Full workflow guide: `docs/agent-workflow.md`

## CLI Decision Tree

See `docs/agent-workflow.md` for the full workflow. Summary:

1. **Recent changes?** `tldrs diff-context --project . --preset compact`
2. **Symbol context?** `tldrs context <entry> --project . --preset compact`
3. **File/folder overview?** `tldrs structure src/` or `tldrs extract <file>`
4. **Semantic search?** `tldrs index .` then `tldrs find "query"`
5. **Structural patterns?** `tldrs structural 'def $FUNC($$$ARGS): return None' --lang python`
6. **Deep analysis?** `tldrs slice`, `tldrs cfg`, `tldrs dfg`
7. **Capability manifest?** `tldrs manifest --pretty`

## Topic Guides

| Topic | File | Covers |
|-------|------|--------|
| Architecture | [agents/architecture.md](agents/architecture.md) | Source layout, extraction pipeline, semantic search pipeline |
| MCP Server | [agents/mcp-server.md](agents/mcp-server.md) | 24 tools, cost ladder, full tool catalog |
| Plugin | [agents/plugin.md](agents/plugin.md) | Commands, skills, hooks, file layout, Codex skill |
| Critical Rules | [agents/critical-rules.md](agents/critical-rules.md) | Import convention, language field, function names, FAISS normalization, incremental index |
| Data Structures | [agents/data-structures.md](agents/data-structures.md) | FunctionInfo, ModuleInfo, CodeUnit, delta mode, compression, output caps |
| Semantic Search | [agents/semantic-search.md](agents/semantic-search.md) | FAISS/ColBERT backends, embedding model, operational notes, gotchas |
| Related Projects | [agents/related-projects.md](agents/related-projects.md) | interbench sync, tldr-bench datasets, dev reference |


