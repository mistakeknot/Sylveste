---
name: interlore
description: "Philosophy observer — detects latent design patterns and philosophy drift from decision artifacts, proposes PHILOSOPHY.md updates."
---
# Gemini Skill: interlore

You have activated the interlore capability.

## Base Instructions
# AGENTS.md — interlore

Philosophy observer plugin. Scans decision artifacts (brainstorms, PRDs, flux-drive outputs, plans) to detect recurring design patterns and philosophy drift. Proposes PHILOSOPHY.md updates with evidence links.

**Plugin Type:** Claude Code skill plugin
**Plugin Namespace:** `interlore`
**Current Version:** 0.1.0

## Canonical References
1. [`MISSION.md`](../../MISSION.md) — project mission.
2. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — design bets and principles (what interlore observes and proposes updates to).

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](../../PHILOSOPHY.md) during intake, brainstorming, planning, execution, review, and handoff.

For brainstorming/planning outputs, add:
- **Alignment:** one sentence on how the proposal supports Demarch's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

## Architecture

interlore has three layers:
1. **Artifact discovery** — glob patterns from interpath source catalog
2. **Pattern extraction** — content-based tradeoff detection + Alignment/Conflict enrichment
3. **Proposal management** — structured YAML staging with accept/reject/defer lifecycle

State: `.interlore/proposals.yaml` at project root.


