---
artifact_type: prd
bead: iv-zsio
stage: design
---
# PRD: Discovery Pipeline Sprint Presentation

## Problem

Interject-originated beads (`[interject] <title>`) appear as generic work items in Clavain's discovery menu. Users can't distinguish ambient discoveries from regular tasks, and the source/relevance metadata that interject embeds in the bead description isn't surfaced.

## Solution

Enrich the discovery presentation layer so `[interject]` beads display as discovery items with source and relevance score, and route to appropriate review actions.

## Features

### F1: Metadata Extraction in lib-discovery.sh

**What:** Extract source name and relevance score from `[interject]` bead descriptions and include in the discovery JSON output.

**Acceptance criteria:**
- [ ] `discovery_scan_beads()` output includes `discovery_source` and `discovery_score` fields for `[interject]` beads
- [ ] Fields are null/empty for non-interject beads (no overhead)
- [ ] Extraction parses the `Source: <name> | <url>` and `Relevance score: <float>` lines from bead description

### F2: Enriched Presentation in route.md

**What:** Detect `[interject]` prefix in discovery results and present enriched labels in the AskUserQuestion options.

**Acceptance criteria:**
- [ ] `[interject]` beads display as `"Review discovery: <clean title> (<source>, score <score>)"` instead of generic action verbs
- [ ] Clean title strips the `[interject] ` prefix
- [ ] Non-interject beads are unaffected

### F3: Discovery Action Routing

**What:** Route selected `[interject]` beads to appropriate review flow instead of brainstorm/plan/execute.

**Acceptance criteria:**
- [ ] Selecting an `[interject]` bead with `pending_triage` label routes to individual bead review (show details, ask promote/dismiss/skip)
- [ ] Selecting a triaged `[interject]` bead routes normally based on phase (same as any other bead)

## Non-goals

- No new data paths (kernel query, MCP calls) in the discovery flow
- No fallback hint when zero interject beads exist
- No changes to interject's bead creation format (wie5i output is the contract)
- No changes to scoring algorithm (the -15 penalty for untriaged [interject] beads is correct)

## Dependencies

- wie5i (shipped): interject creates `[interject]` prefixed beads with structured descriptions
- interphase lib-discovery.sh: existing scanner infrastructure
- Clavain route.md: existing discovery presentation

## Open Questions

None — scope is fully defined.
