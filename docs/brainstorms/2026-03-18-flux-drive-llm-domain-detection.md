# Brainstorm: flux-drive LLM Domain Detection + flux-gen Dispatch

**Bead:** Demarch-b5md
**Date:** 2026-03-18

## Problem

flux-drive's heuristic domain detection (`detect-domains.py`) scores 0 for Demarch — a monorepo with 50+ subprojects. Scores for closest domains:
- `claude-code-plugin`: 0.152 (needs 0.35)
- `tui-app`: 0.208 (needs 0.30)
- `library-sdk`: 0.124 (needs 0.30)

Root cause: heuristic looks for root-level build files, but Demarch has `go.mod`, `.claude-plugin/plugin.json`, `cmd/` scattered across subproject dirs. The detector was designed for single-project repos.

Result: flux-drive Step 1.0.4 always falls through to "core agents only." User compensates by manually running `/flux-gen` before every `/flux-drive`. Cass confirms this is the consistent pattern.

## Design

**Delete the heuristic from flux-drive's runtime path.** The LLM running flux-drive already reads the project in Step 1.0 (README, build files, CLAUDE.md, AGENTS.md, key source files). It has full project understanding — asking it to also classify domains is free.

**Dispatch to flux-gen when agents are missing.** When flux-drive detects no project agents in `.claude/agents/fd-*.md`, it should invoke flux-gen with the document content as the task prompt. This follows "composition through contracts" — flux-gen owns agent authoring, flux-drive owns orchestration.

## Changes

1. **Step 1.0.1**: Replace `detect-domains.py` call with LLM classification. Output `domains:` as part of Step 1.0's project understanding. No script, no cache, no staleness checks.

2. **Step 1.0.4**: Replace `generate-agents.py --mode=regenerate-stale` with: check for existing project agents → if none, invoke `/interflux:flux-gen <document summary>` non-interactively → proceed.

3. **Cache**: `intersense.yaml` remains useful for flux-gen's offline domain mode. flux-drive just doesn't depend on it anymore.

4. **Compact version**: Same changes, fewer lines.
