---
artifact_type: brainstorm
bead: sylveste-sttz.3
date: 2026-04-05
---

# Brainstorm: Forge F3 — Stress Test Artifact Pipeline

## Problem

Forge Mode (F2) enables structured conversations where Auraken stress-tests itself. But the outputs are ephemeral — metadata updates and test logs exist only in conversation context. F3 adds durable artifact extraction: structured log schema, `forge-artifact` block parsing from Claude responses, and a staging workflow for lens metadata diffs.

## Key Decisions

### 1. Artifact extraction: inline vs. post-hoc

**Inline (chosen):** The forge system prompt (already implemented in F2) instructs Claude to output structured updates as fenced JSON blocks tagged `forge-artifact`. A post-response parser extracts these.

Why: The agent already knows the schema (injected in forge prompt). Parsing fenced blocks is simple regex. No second LLM call needed.

### 2. Staging workflow: auto-apply vs. review-first

**Review-first (chosen):** Extracted lens metadata diffs are written to `data/forge-staging/` as JSON patches. Builder reviews with `git diff` before applying to `lens_library_v2.json`.

Why: Flux-review P2 finding — ambiguous staging gate. Auto-applying is dangerous because a single bad stress test could corrupt lens metadata. The staging directory is a natural review buffer.

### 3. Log format: structured JSONL vs. markdown

**JSONL (chosen):** Each stress test produces a `StressTestLog` entry appended to `data/forge-logs/{date}-{capability}.jsonl`. Schema includes replayable fields: `input_scenario`, `candidate_lenses`, `expected_final_lenses`, `contraindications_triggered`, `distinguishing_features_checked`, `resolution_rationale`, `metadata_updates`.

Why: Flux-review P2 finding — logs must be replayable for regression testing. JSONL is machine-readable, appendable, and diff-friendly.

### 4. Profile sim and meta artifacts

Profile sim → `data/forge-staging/profile-rules/` (JSON rule files)
Meta → brainstorm docs in standard `docs/brainstorms/` format

These follow the same staging pattern but with different schemas.

## Architecture

```
Claude response (with forge prompt)
  ↓ post-response parsing
  ↓ regex: ```forge-artifact\n{...}\n```
  ↓
ForgeArtifact → dispatch by type:
  ├── lens_update → data/forge-staging/{lens_id}-{timestamp}.json
  ├── profile_rule → data/forge-staging/profile-rules/{timestamp}.json
  └── stress_test_log → data/forge-logs/{date}-{capability}.jsonl
```

All in `forge.py` — no new module needed. The extraction runs in `telegram.py`'s response path after `handle_message` returns, before sending the reply.

## Constraints

- No new dependencies
- Backward compatible — forge sessions without artifacts still work
- Artifacts are never auto-applied to production lens data
- Log schema must support future F4 coverage index queries
