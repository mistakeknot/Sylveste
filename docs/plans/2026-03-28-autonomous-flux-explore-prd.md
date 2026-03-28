---
bead: sylveste-d39
title: "PRD: Autonomous flux-gen semantic space exploration"
date: 2026-03-28
type: prd
---

# PRD: Autonomous Flux-Gen Semantic Space Exploration

## Problem Statement

Multi-round semantic space exploration (as in the garden-salon session) requires the human to manually direct each round, review prior coverage, articulate distance constraints, and decide when to stop. This is mechanically formulaic but cognitively expensive. The process produced 22 agents and some of the project's most valuable architectural insights (perfumery → volatility-stratified ensemble, paleography → stemma-based hallucination tracing).

## Success Criteria

1. `/flux-gen --mode=explore` automates multi-round exploration with zero human intervention between rounds
2. Each round produces agents from domains maximally distant from all prior rounds
3. A synthesis step identifies cross-domain structural isomorphisms
4. Output is a brainstorm document with the same quality/structure as the manual session

## Features

### F1: Explore Mode for flux-gen
- `--mode=explore` flag triggers multi-round exploration
- `--rounds=N` controls depth (default: 3)
- `--agents-per-round=N` (default: 5)
- Round 1: standard flux-gen on the target
- Rounds 2+: exploration prompt with prior coverage context

### F2: Exploration Prompt
- Receives full list of prior agent names + focus descriptions
- Requests domains maximally distant from all prior coverage
- Asks for structured metadata: source_domain, distance_rationale, expected_isomorphisms
- Instructs LLM to draw from different fields, eras, and modalities

### F3: Cross-Domain Synthesis
- After all exploration rounds complete, a synthesis agent reads all generated agents' focus/review_areas/severity_examples
- Identifies structural isomorphisms across domains
- Produces a brainstorm document with: findings per domain, cross-domain patterns, novel mechanism transfers, open questions

## Non-Goals

- Embedding-based distance verification (v2)
- Novelty-based stopping criteria (v2)
- Budget integration with interstat (v2)
- Running flux-drive on the target with generated agents (user does that separately)

## Risks

- LLM-generated "distant" domains may cluster around familiar analogies (biology, military, etc.) — mitigate by including anti-clustering instruction
- Synthesis quality may degrade with >15 agents — mitigate by limiting to 3 rounds default
