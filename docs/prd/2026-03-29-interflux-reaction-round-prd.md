---
bead: sylveste-rsj.2
date: 2026-03-29
type: prd
---

# Interflux Reaction Round — PRD

## Problem Statement

Interflux multi-agent reviews produce isolated findings that are only merged post-hoc during synthesis. Agents never see what their peers found. This prevents 5 of 7 SOTA multi-agent techniques from operating and leaves review quality on the table.

## Goal

Add a single reaction round (Phase 2.5) between agent dispatch and synthesis where agents see each other's Findings Indexes and respond with agreement, disagreement, or extensions. This unlocks DMAD, Free-MAD, CONSENSAGENT, Lorenzen, and QDAIF techniques while adding <5% cost overhead.

## Features

### F1: Reaction Phase (Phase 2.5)
After all agents complete (Phase 2), collect Findings Indexes, build reaction prompts, dispatch reaction agents in parallel, collect `.reactions.md` files.

### F2: Synthesis Integration
Intersynth reads `.reactions.md` files alongside `.md` files. Reactions become metadata annotations on findings (agreement/disagreement/extension with rationale). Synthesis gains a "Reaction Analysis" section.

### F3: Config Toggle
`enable_reaction_round: true|false` in flux-drive config. Default: true for `review` and `flux-drive` modes, false for `quality-gates` (where speed matters more than depth).

### F4: Findings Index Extraction
`findings-helper.sh read-indexes` subcommand that extracts the Findings Index from each agent's `.md` file. Reusable for future SOTA work.

## Non-Goals

- Live agent-to-agent communication during Phase 2 (Option B from brainstorm — too complex for now)
- Multiple reaction rounds (one is sufficient for the SOTA techniques we're targeting)
- Changing agent verdicts based on reactions (reactions are metadata, not verdict overrides)

## Success Metrics

- Reaction round completes in <30s for a typical 5-agent review
- Cost overhead <5% of total review cost
- At least 1 in 3 reviews surfaces a meaningful reaction (agreement strengthens finding, or disagreement reveals gap)

## Dependencies

- Existing `peer-findings.jsonl` infrastructure (reuse for reaction tracking)
- Existing `findings-helper.sh` (extend with `read-indexes`)
- Intersynth synthesis agent (modify to read `.reactions.md`)
