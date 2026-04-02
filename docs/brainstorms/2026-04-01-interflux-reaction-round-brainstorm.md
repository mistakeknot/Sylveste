---
artifact_type: brainstorm
bead: sylveste-g3b
stage: brainstorm
---

# Interflux Reaction Round — Brainstorm

## Problem

The reaction round is **designed but never fires**. All the pieces exist:
- `phases/reaction.md` — full phase instructions
- `config/flux-drive/reaction.yaml` — config with sensible defaults
- `config/flux-drive/reaction-prompt.md` — agent prompt template
- `scripts/findings-helper.sh read-indexes` — index extraction
- `intersynth:synthesize-review` Steps 3.7–3.8 — conductor scoring, hearsay, Lorenzen, sycophancy
- `discourse-topology.yaml`, `discourse-fixative.yaml`, `discourse-lorenzen.yaml`, `discourse-sawyer.yaml` — supporting protocols

SKILL.md says "Read `phases/reaction.md` now" at Phase 2.5. But no `.reactions.md` files have ever been produced. The question is: **why not, and what's actually blocking?**

## Hypothesis: The Instructions Work But Nobody's Tested Them

The SKILL.md is a set of instructions that Claude follows. Phase 2.5 says "Read `phases/reaction.md` now." When Claude reads that file, it should follow the steps: run convergence gate, collect findings indexes, build reaction prompts, dispatch agents, collect outputs.

Possible failure modes:
1. **Phase 2.5 is being skipped** — `reaction_round.enabled` might be overridden by mode
2. **Convergence gate trips** — if overlap > 0.6, reaction is skipped
3. **findings-helper.sh read-indexes fails** — index extraction might not parse actual agent outputs
4. **Agent dispatch fails silently** — reaction agents timeout or produce empty output
5. **The instructions are ambiguous** — Claude doesn't know how to execute the steps

## Assessment: What's Actually Missing

After reading all the files, the **design and implementation are complete**. The most likely failure mode is #5: the `phases/reaction.md` instructions are clear to a human but might be ambiguous for Claude to execute, especially:

- The convergence gate requires running a bash script and interpreting numeric output
- Building per-agent reaction prompts requires template filling with topology filtering
- Dispatching reactions requires constructing Agent tool calls with the right parameters

The fix isn't more code — it's **testing the runtime path** and fixing whatever breaks.

## Approach: Validate-Then-Fix

1. Run a real flux-drive review on a known document
2. Observe whether Phase 2.5 fires
3. If it doesn't, trace why and fix the specific failure
4. If it does but reactions are empty/malformed, fix the prompt or dispatch
5. Verify intersynth processes the reactions correctly
6. Add an Interspect evidence event for reaction outcomes (closed-loop)

## Key Design Decisions Already Made

- **Convergence gate**: skip if >60% of P0/P1 findings overlap (saves tokens when agents already agree)
- **Sparse communication**: agents don't see all peer findings, controlled by topology
- **Max 3 reactions per agent**: prevents runaway token spend
- **Sonnet model for reactions**: cheaper than Opus, sufficient for structured reactions
- **Hearsay rule**: confirmations without new evidence are discounted (weight 0.0)
- **Move types**: attack, defense, new-assertion, concession (Lorenzen dialogue game)
- **Sycophancy detection**: flag agents with >80% agreement + <30% independence

## What Would Make This SOTA

The reaction round alone is table stakes — OpenAI's DMAD and Google's CONSENSAGENT do similar things. What makes Sylveste's version distinctive:

1. **Sparse communication topology** — agents don't all see everything. This preserves cognitive diversity (rsj.11). Most multi-agent systems use fully-connected graphs which leads to consensus collapse.

2. **Discourse fixative** — corrective prompt injection when discourse health degrades (Gini imbalance, low novelty, drift). No other system monitors the health of multi-agent discourse in real-time.

3. **Hearsay rule** — confirmations that just cite peer outputs without new evidence get zero weight. This combats the echo chamber effect where agents rubber-stamp each other.

4. **Sycophancy scoring** — flag agents that agree too much with too little independence. Combined with Interspect evidence, this can drive routing overrides: consistently sycophantic agents get deprioritized.

5. **Lorenzen dialogue formalization** — reactions are classified as formal dialogue moves. This enables structural analysis of the discourse quality, not just content analysis.

6. **Evidence emission** — reaction outcomes feed into Interspect, which feeds into routing. The reaction round isn't just a review improvement — it's a signal source for the flywheel.

## Scope for This Sprint

- **In scope**: Validate the runtime path end-to-end. Fix whatever breaks. Add Interspect evidence emission for reaction outcomes. Verify with a real review.
- **Out of scope**: New discourse protocols (pressing, conduction, yes-and). Changes to the topology or fixative algorithms. Garden Salon integration.

## Risk

Low. The design is validated. The code exists. The main risk is discovering that the instructions don't execute cleanly in Claude's runtime — but that's exactly what we're here to find out and fix.
