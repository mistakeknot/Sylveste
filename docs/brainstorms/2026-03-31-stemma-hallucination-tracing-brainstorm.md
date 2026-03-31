---
artifact_type: brainstorm
bead: sylveste-rsj.10
stage: brainstorm
---

# Stemma Hallucination Tracing — Brainstorm

## Problem

When multiple agents independently produce the same incorrect claim, it's tempting to treat convergence as confirmation. But shared hallucinations arise from shared context — all agents read the same document, and the document's structure or ambiguity creates a systematic misreading.

Example: A document has an ambiguous function name. Three agents independently report a "bug" based on misunderstanding the name. Convergence = 3, but the real source is a single ambiguity in the shared input, not three independent discoveries.

## Concept: Stemma (Textual Phylogenetics)

In manuscript studies, a **stemma** traces how copying errors propagate through a family tree of manuscripts. The **hyparchetype** is the lost ancestor that introduced an error. By comparing which manuscripts share the same errors, scholars reconstruct the family tree.

Applied to agent outputs:
- **Hyparchetype**: The shared context element (file, section, or prompt fragment) that introduced the error
- **Error genealogy**: Which agents were "exposed" to the same context and produced the same misreading
- **Independent vs dependent errors**: If two agents produce the same wrong claim and both read the same file section → dependent (shared ancestor). If they produce the same claim from different evidence → truly independent convergence.

## Design

### What to Track

For each finding in synthesis, extend the provenance metadata:

```json
{
  "provenance": "reactive|independent|null",
  "evidence_sources": ["src/auth.ts:45", "src/auth.ts:48"],
  "shared_context_overlap": 0.85,
  "stemma_group": "SG-1"
}
```

- `evidence_sources`: file:line references the agent cited as evidence
- `shared_context_overlap`: fraction of evidence sources shared with other findings in the same stemma group
- `stemma_group`: findings sharing >50% evidence sources are grouped together

### Stemma Grouping Algorithm (in synthesis Step 6)

1. For each merged finding, collect all `evidence_sources` from the original finding and its convergent reactions
2. Build an overlap matrix: for each pair of findings, compute Jaccard similarity of evidence_sources
3. Findings with Jaccard > 0.5 are in the same stemma group
4. Within a stemma group, the finding with the earliest/most-specific evidence is the "hyparchetype candidate"
5. Tag: `"stemma_analysis": {"group": "SG-1", "shared_sources": [...], "hyparchetype_candidate": "ARCH-01"}`

### Convergence Adjustment

Findings in the same stemma group get a **convergence correction**:
- Instead of counting N independent confirmations, count the number of *distinct evidence source sets*
- If 3 agents all cite `src/auth.ts:45-50`, that's 1 independent source, not 3 confirmations
- The convergence count becomes: `corrected_convergence = count(distinct_evidence_sets)`

### Where This Lives

- **synthesize-review.md Step 6** (deduplication): Add stemma grouping after merge
- **findings.json schema**: Add `stemma_group`, `evidence_sources`, `shared_context_overlap`
- **Report output**: Add Stemma Analysis section showing shared-source clusters

### What This Does NOT Do

- Does not determine if a finding is *correct or incorrect* — it only flags shared-source convergence
- Does not modify severity (same rule as hearsay and reactions)
- Does not require changes to individual agent prompts — agents already provide evidence file:line references
