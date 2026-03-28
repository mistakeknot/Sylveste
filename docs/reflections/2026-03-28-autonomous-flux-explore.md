---
bead: sylveste-d39
title: "Reflect: autonomous flux-explore command"
date: 2026-03-28
type: reflection
---

# Reflection: Autonomous Flux-Explore

## What worked

- **Plan review caught the mode-flag antipattern**: The initial plan added `--mode=explore` to flux-gen, but review correctly identified this as a different loop shape (multi-round with cross-round state) that doesn't share flux-gen's one-shot skeleton. Separating into `flux-explore` keeps both commands clean.
- **Synthesis reads JSON specs, not .md files**: Critical insight — exploration metadata (source_domain, expected_isomorphisms, distance_rationale) only exists in the spec JSON. The rendered .md files don't contain these fields. This avoids needing a version bump or template change in generate-agents.py.
- **Anti-clustering instruction from fd-user-product**: Blocking 13 common AI-analogy domains (biology, military, game theory, etc.) pushes toward genuinely novel territory. The "prefer pre-modern craft, non-human scales, non-Western knowledge" positive steering is more effective than just blocking known attractors.

## What surprised

- **The command is pure prompt orchestration** — zero Python changes needed. The entire loop (parse args → confirm → round 1 → rounds 2..N → synthesize → report) is expressed as markdown instructions to Claude Code. generate-agents.py is called as a tool, unchanged.
- **Per-round spec checkpointing is crash recovery for free**: Each round saves to `{slug}-round-{N}.json`. If the command fails mid-loop, completed rounds are preserved and the user can re-run `/flux-gen --from-specs` on any saved round.

## What to do differently

- For features that wrap existing commands in loops, always evaluate "separate command vs mode flag" — the loop shape is usually different enough to justify separation.
- When adding fields to a JSON spec that's round-tripped through a template renderer, explicitly decide early whether those fields survive the round-trip or only live in the spec. This avoids version-bump-vs-no-version-bump confusion.

## Deferred work

- End-to-end validation (Task 3) — requires running the command with live LLM, deferred to next session
- Lightweight interrupt before final round (show proposed domains, allow redirect)
- Embedding-based distance verification
- Budget integration with interstat
- `## Exploration Context` section in generated .md files
