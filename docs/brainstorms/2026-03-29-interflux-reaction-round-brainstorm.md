---
bead: sylveste-rsj.2
date: 2026-03-29
type: brainstorm
---

# Interflux Reaction Round

## Problem

Interflux agents currently produce findings in isolation. Each agent writes `{OUTPUT_DIR}/{agent-name}.md` during Phase 2, then synthesis (Phase 3) merges them post-hoc via deduplication. No agent ever sees what its peers found.

Every frontier multi-agent technique assumes agents react to each other: DMAD (diverse reasoning methods), Free-MAD (trajectory scoring for capitulated agents), CONSENSAGENT (sycophancy detection via disagreement monitoring), Lorenzen dialogue (turn-based challenge/defense), QDAIF (diversity archive over convergence). Adding one reaction round unlocks 5 of 7 SOTA techniques simultaneously.

## Current Architecture

```
Phase 1: Triage → score agents → user confirms roster
Phase 2: Parallel dispatch (agents isolated)
         Stage 1 (top 2-3) → Stage 2 (expansion)
         Each writes: {OUTPUT_DIR}/{agent-name}.md
Phase 3: Synthesis via intersynth
         Read all .md → deduplicate (5 rules) → findings.json + synthesis.md
```

Key files:
- `interverse/interflux/skills/flux-drive/SKILL.md` — main orchestration
- `interverse/interflux/skills/flux-drive/phases/launch.md` — dispatch logic
- `interverse/interflux/skills/flux-drive/phases/synthesize.md` — synthesis delegation
- `interverse/intersynth/agents/synthesize-review.md` — synthesis agent
- `interverse/interflux/scripts/findings-helper.sh` — JSONL peer-findings write/read

Existing infrastructure: `peer-findings.jsonl` already supports `blocking`/`notable` severity levels and `findings-helper.sh` for write/read. Currently only used post-hoc during synthesis for convergence tracking — not for live agent communication.

## Design: Phase 2.5 Reaction Round

Insert between Phase 2 completion and Phase 3 synthesis:

```
Phase 2: All agents complete → {agent-name}.md files exist
    ↓
Phase 2.5: REACTION ROUND
    2.5.0: Collect Findings Indexes (first ~30 lines of each .md)
    2.5.1: Build reaction prompts (inject all peer Findings Indexes)
    2.5.2: Dispatch reaction agents in parallel (model: sonnet)
    2.5.3: Monitor for {agent-name}.reactions.md completion
    ↓
Phase 3: Synthesis reads .md + .reactions.md
```

### Key decisions

1. **Agents see Findings Indexes only** — not full prose. This is ~30 lines per agent, keeping reaction prompts small (~2-3K tokens total context).
2. **Reactions are separate files** (`.reactions.md`) — original findings stay immutable. This preserves the "what did the agent find independently?" signal.
3. **Sonnet model for reactions** — reactions are synthesis/evaluation work, not discovery. Cheaper than opus.
4. **Reactions don't change verdicts** — they annotate findings with agreement/disagreement/extension. Synthesis tracks reaction convergence as metadata.
5. **Toggle via config** — `enable_reaction_round: true|false` in flux-drive config. Default: true for reviews, false for quick checks.
6. **Only react to P0/P1 findings** — skip P2/improvements to keep reaction round focused and cheap.

### Reaction prompt template

```
You are {agent-name} ({agent-description}).

Your peers discovered these findings during this review:

{All Findings Indexes, grouped by agent, filtered to P0/P1}

For each finding relevant to your domain:
1. Agreement: agree / partially agree / disagree
2. Impact on your analysis: none / extends / contradicts
3. Brief rationale (1-2 sentences)

If peer findings reveal something you missed, add it.
If peer findings contradict your analysis, explain why.

Write to: {OUTPUT_DIR}/{agent-name}.reactions.md
```

### Synthesis modifications

Intersynth reads `.reactions.md` files alongside `.md` files:
- Reactions become metadata on findings: `finding.reactions: [{agent, stance, rationale}]`
- New convergence signal: finding confirmed by N agents via reactions (stronger than dedup overlap)
- New contradiction signal: finding disputed by M agents with rationale
- Synthesis output gains a "Reaction Analysis" section

### Cost estimate

- N agents × ~500-1K output tokens each (sonnet) = ~$0.02-0.05 per review
- Compared to typical flux-drive review cost of $0.50-2.00, this is 2-5% overhead
- Can be further reduced by only reacting agents whose domain overlaps with P0/P1 findings

## What this unlocks

| Technique | What reaction round enables |
|---|---|
| **DMAD** (ICLR 2025) | Agents with diverse reasoning methods can now see how others approached the same problem |
| **Free-MAD** | Trajectory scoring: did an agent find something early but not report it? Reactions surface "I saw this too but deprioritized it" |
| **CONSENSAGENT** (ACL 2025) | Disagreement rate monitoring: track how often agents disagree in reactions vs. capitulate |
| **Lorenzen dialogue** | Challenge/defense structure: reactions are the "challenge" turn; original findings are the "claim" |
| **QDAIF** (ICLR 2024) | Reactions maintain perspective diversity — disagreements preserved, not merged away |

## Implementation plan (sketch)

1. Create `interverse/interflux/skills/flux-drive/phases/reaction.md` — the reaction round phase
2. Modify `SKILL.md` — insert Phase 2.5 reference after Phase 2 completion
3. Create reaction prompt template in `interverse/interflux/config/reaction-prompt.md`
4. Modify `interverse/intersynth/agents/synthesize-review.md` — read .reactions.md, annotate findings
5. Add config toggle: `interverse/interflux/config/flux-drive.yaml` — `enable_reaction_round: true`
6. Update `findings-helper.sh` — add `read-indexes` subcommand (extract Findings Indexes from .md files)
