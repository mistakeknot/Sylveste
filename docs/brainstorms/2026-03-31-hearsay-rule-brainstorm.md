---
artifact_type: brainstorm
bead: sylveste-rsj.12
stage: brainstorm
---

# Hearsay Rule — Brainstorm

## Problem

In multi-agent review, Agent B can cite Agent A's finding as evidence for its own claims without independently verifying Agent A's claim. This creates hallucination propagation chains — if Agent A hallucinated a bug, Agent B's "confirmation" amplifies the false signal rather than providing independent verification. The convergence scoring then treats this as two independent sources agreeing, inflating confidence.

Example: fd-architecture says "this module violates SRP." fd-quality's reaction says "as fd-architecture noted, this violates SRP" — that's hearsay, not independent evidence. True convergence would be fd-quality independently finding the same violation through its own analysis.

## Where This Happens

1. **Reaction round** (Step 3.7 in synthesize-review.md): Agents read other agents' findings and react. Reactions that merely agree without adding independent evidence are hearsay.
2. **Synthesis convergence scoring** (Step 6.5): Convergent reactions boost confidence. Hearsay reactions shouldn't count toward convergence.

## Design

### Detection Heuristics

A reaction is hearsay if it:
1. **Cites the original agent by name** without adding new file:line evidence ("as fd-architecture noted...")
2. **Has no independent evidence field** — the reaction has a verdict but no new file paths, line numbers, or code snippets
3. **Paraphrases the original finding** without new analysis — high textual similarity to the original finding's description

### Implementation: Provenance Validator in Synthesis

Add a **Step 3.7b** between reaction ingestion (3.7) and sycophancy scoring (3.8):

For each reaction parsed in Step 3.7:
1. Check if reaction verdict is `confirms-findings`
2. If confirming, check for independent evidence:
   - Has `evidence` field with file:line references NOT present in original finding
   - Has `rationale` that introduces new analysis (not just rephrasing)
3. Tag reactions: `"hearsay": true|false`
4. Hearsay reactions get a **provenance discount**: count as 0.0 (not 0.5 or 1.0) in convergence scoring

### Convergence Impact

Current: reactive additions count as 0.5. Confirmations count as 1.0.
With hearsay rule:
- Independent confirmation (new evidence): 1.0
- Reactive addition (new finding): 0.5
- Hearsay confirmation (no new evidence): 0.0
- Contradiction: always counted (negative evidence is always independent)

### What This Does NOT Do

- Does not prevent agents from reading each other's outputs (that's how reaction rounds work)
- Does not reject hearsay reactions from the report — they're tagged, not removed
- Does not change severity tiers
- No runtime enforcement — this is a synthesis-time validation
