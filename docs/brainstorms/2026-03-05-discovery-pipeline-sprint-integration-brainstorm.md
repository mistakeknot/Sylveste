---
artifact_type: brainstorm
bead: iv-zsio
stage: discover
---
# Integrate Discovery Pipeline into Sprint Workflow

**Date:** 2026-03-05
**Status:** Design captured — ready for planning

## What We're Building

Enrich Clavain's sprint discovery menu (`/route` no-args) so that interject-originated beads appear as "New discovery" items with source and relevance metadata, instead of generic work items. The data path already works — wie5i shipped dual-write (interject scan -> kernel record + bead creation), and lib-discovery.sh already scans these beads. The gap is presentation-only.

## Why This Approach

Three integration approaches were considered:

1. **Beads-only (chosen):** Interject already creates beads for medium+high tier discoveries. lib-discovery.sh already finds them. Fix the presentation layer in route.md to detect `[interject]` prefix and show enriched metadata (source, score). No new data path, no new dependencies.

2. **Kernel query hybrid (rejected):** Would add `ic discovery list` as a second discovery source alongside beads scan. More comprehensive (surfaces low-tier kernel-only records) but adds ic CLI dependency to the critical discovery path. Overkill given that medium+high tier items already become beads.

3. **Session-context injection (rejected):** Would inject relevant discoveries into brainstorm phase via interject MCP server. Orthogonal to the discovery menu problem — could be a follow-up but doesn't solve the "discoveries look like generic work" issue.

## Key Decisions

- **D1: Beads-only approach** — No new data paths. The presentation layer in route.md detects `[interject]` prefix and enriches display. Minimal scope, maximum leverage from wie5i.

- **D2: No fallback for zero discoveries** — If interject hasn't been run, there are simply no `[interject]` beads. The discovery menu shows regular work as usual. Users run `interject-scan` to populate.

- **D3: Scoring calibration** — lib-discovery.sh already penalizes untriaged `[interject]` beads by -15 score (line 337). This is reasonable: untriaged discoveries should rank below in-progress work but above stale backlog. No change needed.

- **D4: Triage loop is already closed** — `/interject:triage` skill (shipped in wie5i) handles batch review of `pending_triage` beads. Once triaged (phase set), the -15 penalty lifts and the bead ranks normally.

## Scope

1. **route.md presentation** — Detect `[interject]` prefix in discovery results, show enriched label: `"New discovery: <clean title> (<source>, <score>)"` instead of generic action verb.
2. **Action verb** — Add `discover` action type for `[interject]` beads that maps to `/interject:triage` or direct review.
3. **lib-discovery.sh** — Extract source/score from bead description (already contains `Source: <name> | <url>` and `Relevance score: <float>`) and include in JSON output.

## Open Questions

- Should `[interject]` beads with `pending_triage` label route to `/interject:triage` (batch) or to individual bead review? Leaning toward individual review since the discovery menu already selected a specific bead.
