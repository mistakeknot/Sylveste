---
artifact_type: brainstorm
bead: sylveste-d39
stage: discover
---

# Brainstorm: Autonomous Flux-Gen Domain Semantic Space Exploration

**Date:** 2026-03-28
**Trigger:** Session f208bc42 (2026-03-27) ran 3 rounds of flux-gen producing 22 agents across progressively more distant semantic domains (customer strategy → salon/frontier → perfumery/oceanography/law/paleography/wayfinding). The user manually directed each round. Can this be automated?

## The Problem

Manual semantic space exploration requires the human to:
1. Review what domains were already covered
2. Identify gaps in the conceptual space
3. Articulate "generate agents for domains maximally distant from X, Y, Z"
4. Decide when to stop exploring

This is cognitively expensive but mechanically formulaic — a good candidate for automation.

## What Happened in the Source Session

Round 1 (7 agents): Customer strategy — business domain analysis
Round 2 (10 agents): Salon reframing (5) + esoteric frontier research (5) — biology, politics, music, ML theory, philosophy, sociology
Round 3 (5 agents): Maximally distant domains — chemistry/olfaction, physical oceanography, common law, medieval paleography, cognitive anthropology

Each round intentionally moved further from previous coverage. The user's prompt was: "run another /flux-gen and /flux-drive for related, orthogonal, and esoteric domains that aren't as far as possible in the semantic space from the domains you have already covered."

## Design Questions

### Q1: How to represent the semantic space of covered domains?

**Option A: Tag list** — Each generated agent has a `domain` tag. Track coverage as a flat set of tags. Simple but no distance metric.

**Option B: Embedding-based** — Embed each agent's `focus` field (or full spec). Use cosine distance in embedding space to find gaps. Real semantic distance but requires an embedding model.

**Option C: LLM-as-judge** — Ask the LLM: "Given these already-covered domains: [list], suggest 5 domains maximally distant in the semantic space." This is what the human did manually. Cheapest to implement, surprisingly effective.

**Recommendation: Option C first, Option B later.** The session proved LLM-as-judge works — the perfumery/oceanography/paleography suggestions were genuinely distant and productive. Embeddings could verify/refine later but aren't needed for v1.

### Q2: How to automatically identify gaps/frontiers?

The LLM prompt in each round should:
1. Receive the full list of previously generated agent names + focus descriptions
2. Be instructed to maximize semantic distance from ALL prior domains
3. Be asked for 3 types of distance: **related** (adjacent but uncovered), **orthogonal** (perpendicular — same abstraction level, different field), **esoteric** (maximally distant — different field, different era, different modality)

This mirrors the user's natural taxonomy from the session.

### Q3: When to stop exploring?

**Option A: Fixed rounds** — 3 rounds, 5 agents each = 15 agents. Simple, predictable cost.

**Option B: Diminishing returns** — Track the "novelty" of structural isomorphisms found. When a round produces mostly restatements of prior insights, stop. Requires LLM evaluation.

**Option C: Budget-based** — Token budget per exploration campaign. Stop when budget is exhausted.

**Recommendation: Option A with Option C as ceiling.** Start with 3 rounds (the session's natural rhythm). Add a budget ceiling. Option B (novelty detection) is a refinement for later.

### Q4: How to synthesize cross-domain findings?

The garden-salon brainstorm's synthesis was the most valuable part — mapping structural isomorphisms across domains (stigmergic coordination ↔ CRDT state, perfumery volatility ↔ agent timescales, etc.). The autonomous version needs:

1. After each round: `/flux-drive` runs the new agents against the target
2. After all rounds: A **synthesis agent** reads all findings and identifies cross-domain structural isomorphisms
3. Output: A brainstorm document with the same structure as the garden-salon brainstorm

## Proposed Architecture

### New command: `/flux-explore`

A wrapper around flux-gen + flux-drive that automates multi-round exploration:

```
/flux-explore <target> [--rounds=3] [--agents-per-round=5] [--budget=500k]
```

**Phase 1: Seed** — Run flux-gen on the target to establish Round 1 agents (domain-appropriate).

**Phase 2: Explore** — For rounds 2..N:
  1. Gather all prior agent names + focus descriptions
  2. Launch a Sonnet subagent with an exploration prompt: "Given these covered domains, design 5 agents from maximally distant domains that could reveal structural isomorphisms relevant to [target]"
  3. Generate agents, run flux-drive
  4. If budget allows, continue to next round

**Phase 3: Synthesize** — Launch a synthesis agent that reads all findings across all rounds and produces:
  - Cross-domain structural isomorphisms
  - Novel mechanism transfers (like perfumery → volatility-stratified ensemble)
  - Open questions and next-round candidates

### Implementation: New flux-gen command extension

Rather than a new command, extend flux-gen with a `--mode=explore` flag:

```
/flux-gen "Review of Sylveste's agent orchestration" --mode=explore --rounds=3
```

This keeps the command surface minimal and reuses flux-gen's existing spec generation, preview, and generation pipeline.

### Exploration Prompt Template

```
You are exploring the semantic space of knowledge domains to find structural
isomorphisms relevant to: {target}

Domains already covered:
{prior_agents_with_focus}

Design 5 new review agents from domains MAXIMALLY DISTANT from all prior coverage.
Select domains that:
1. Come from different fields, eras, and modalities than any prior domain
2. Have rich internal structure that could map to {target}'s architecture
3. Would surprise a practitioner in {target}'s field

For each agent, include the standard fields plus:
- source_domain: the real-world knowledge domain (e.g., "physical oceanography")
- distance_rationale: 1 sentence explaining why this domain is distant from prior coverage
- expected_isomorphisms: 1-2 sentences describing what structural parallels you expect to find
```

## Scope for This Sprint

**Ship:** `--mode=explore` for flux-gen that automates multi-round semantic exploration with synthesis.

**Defer:** Embedding-based distance verification, novelty-based stopping, budget integration with interstat.
