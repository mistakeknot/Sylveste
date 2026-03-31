---
artifact_type: prd
bead: sylveste-rsj.9
date: 2026-03-31
---

# PRD: Discourse Fixative

## Problem

Sawyer Flow Envelope (rsj.7) monitors discourse health but has no consumer. When health degrades (high conformity, low novelty, drifting relevance), the reaction round proceeds unchanged — producing the same quality of discourse regardless of the health signal. The monitoring is passive.

## Solution

Add a discourse fixative — a zero-cost coherence mechanism that injects corrective context into reaction prompts when Sawyer health metrics indicate degradation. The fixative is invisible when discourse is healthy (no-op) and activates only when needed, adding ~50-100 tokens of contextual nudges to reaction prompts.

## Scope

### In Scope

- Pre-reaction health assessment (approximate Sawyer metrics from Phase 2 output)
- Fixative configuration (`discourse-fixative.yaml` with trigger thresholds and injection texts)
- Template slot `{fixative_context}` in reaction-prompt.md
- Integration into reaction phase (Step 2.5.3)
- Fixative activity logging in synthesis report

### Out of Scope

- Separate fixative agent dispatch (Option B — future)
- Post-synthesis corrective round (Option C — future)
- Adaptive threshold learning via Interspect
- Per-agent tailored injections

## Success Criteria

1. When Sawyer metrics are healthy: reaction prompts are unchanged (zero overhead)
2. When Sawyer metrics degrade: 1-3 contextual notes appended to reaction prompts
3. Synthesis report logs fixative activity
4. No new agent dispatches, no new wait cycles
5. Configuration-driven: all thresholds and injection texts in YAML
