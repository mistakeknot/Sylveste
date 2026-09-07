---
reviewer: fd-isnad-chain-integrity
bead: sylveste-b1ha
subject: docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md
date: 2026-04-21
severity_counts: {P0: 2, P1: 2, P2: 2, P3: 1}
---

# Review: Persona/Lens Ontology — Provenance Chain and Tier Integrity

## Executive Summary

The brainstorm treats provenance as metadata rather than as an authenticatable chain. The design permits **tier laundering** through `same-as` equivalence relationships that conflate content similarity with transmitter reliability. Two P0 findings block any claim to "auditable isnad": Evidence nodes lack graded reliability (jarh wa-ta'dil), and the semantic dedup pass cannot distinguish independent convergence (mutawatir) from single-source near-duplication (ahad-da'if). The isnad audit verdict on the current design is **da'if** (weak chain).

---

## P0: Evidence Nodes Lack Jarh Wa-Ta'dil Grading — da'if Contamination Unblocked

**Location:** D4 (Evidence object type), D6 (`Lens —[cites]→ Evidence` relationship)

**Finding:**
A lens derived from `flux-review-ep11` (LLM-generated, inherently da'if until validated) may cite both a peer-reviewed paper and a blog post. Both `cites` edges have identical semantics. During triage, the Cypher query `MATCH (l:Lens)-[:cites]->(e:Evidence)` returns both lenses equally. The graph has no jarh mechanism — no way to rate the transmitter of the citation or the citation itself.

**Concrete failure scenario:**
flux-drive queries "show me lenses with strong evidence." Lens_A cites a Nature paper (primary source); Lens_B cites a Medium post. Both return identically. A tier-3 generated agent that merely cited the blog post scores the same as a tier-1 manually-authored lens citing peer-reviewed research. The triage selection is corrupted by the indistinguishable evidence weights.

**Affected components:** Evidence object type, `cites` relationship schema, D5 triage view (any query using evidence presence as a signal)

**Smallest viable fix:**
Add `strength_grade: enum[sahih, hasan, da'if, mawdu]` to Evidence nodes. Extend the `cites` relationship with `transmitter_tier: int` (tier of the agent/source that made the citation) and `verified_by: text` (human reviewer who confirmed). Triage queries filter `WHERE e.strength_grade IN ['sahih', 'hasan'] AND cites.transmitter_tier <= 2`.

---

## P0: Semantic Dedup Conflates Embedding Similarity with Source Independence — Tier Laundering via same-as

**Location:** Epic Phase 3 ("Semantic dedup pass"), D6 (`same-as` relationship), D7 (dedup non-goal), Open Questions (similarity threshold)

**Finding:**
Two lenses with 0.85 embedding similarity are linked `same-as {confidence: 0.85}`. If Lens_A comes from `flux-review-ep11` (single-transmitter LLM batch) and Lens_B from manual tier-1 authoring, the current `same-as` schema has `confidence` (embedding proximity) and `method` (how similarity was computed) — but no `source_independence` flag and no `corroborator_count`. A triage query that follows `same-as` edges to inherit tier will grant Lens_A tier-1 status without any ilm al-rijal check.

The critical distinction the schema cannot make:
- **Mutawatir**: five independent reviewers from different disciplines converge on the same framing (high confidence, source_independence=TRUE, corroborator_count=5) → genuine equivalence
- **Ahad-da'if**: one LLM run produces text that embeds near a validated lens → false equivalence

**Concrete failure scenario:**
Phase 4 triage view queries: `MATCH (p:Persona)-[:wields]->(l:Lens) WHERE l.tier <= 2 OR EXISTS((l)-[:same-as {confidence: > 0.7}]->(canonical:Lens {tier: 1})) RETURN l`. Lens_A (tier 3, LLM-generated) inherits tier-1 status via same-as. It is selected over genuinely tier-1 agents for a P0 finding on a critical production system. The tier-laundering is invisible in the graph.

**Affected components:** `same-as` relationship schema, dedup algorithm specification (Phase 3), D7 (the non-goal framing understates the risk), Phase 4 triage query patterns

**Smallest viable fix:**
Extend `same-as` schema with `source_independence: boolean` (TRUE if sources share no common ancestry in derives-from chains) and `corroborator_count: int` (number of independent transmission chains that converged). The dedup pass MUST compute source_independence by traversing derives-from before emitting a same-as edge. Triage queries MUST NOT inherit tier via same-as unless `source_independence = TRUE AND corroborator_count >= 2`.

---

## P1: Source Object Represents Terminal Label, Not Reconstructible Isnad Chain

**Location:** D4 (Source type), D6 (`derives-from` relationship), D7 (dedup policy)

**Finding:**
`flux-review-ep11` is a batch identifier, not a transmitter chain. The required isnad is: `[Original context] → [Extractor: gpt-4-ep11-run] → [Validator: @alice-2025-03-12] → [Importer: batch-ingest.py] → [Graph representation]`. The current schema collapses this to `Source {name: "flux-review-ep11"}`. The question "who transmitted this, what was their tier, was there a validator?" cannot be answered.

A lens derived from a lens derived from ep11 cannot be distinguished from a direct ep11 lens. The transitivity of derives-from is structurally present but informationally empty because Source nodes contain no transmitter data.

**Affected components:** Source object type, derives-from relationship, Phase 2 ingestion, Phase 3 dedup (chain traversal is meaningless without transmitter data)

**Smallest viable fix:**
Replace monolithic Source with a `Transmission` chain: `{transmitter, transmitter_tier, transmission_method: enum[llm_generation, manual_authoring, import], transmitted_at, prior_transmission: FK}`. The `derives-from` relationship becomes `(l:Lens)-[:derives-from {step: int}]->(t:Transmission)`. Isnad reconstruction query follows the recursive chain. Existing Source nodes become single-node Transmission chains during migration.

---

## P1: Bi-Temporal Versioning Tracks What-Changed, Not Who-Transmitted-When

**Location:** D9 (versioning via `valid_from`/`valid_to`)

**Finding:**
Bi-temporal tables answer "what was the lens definition on 2025-04-01?" but not "who vouched for this definition and what was their tier?" When a tier-3 agent modifies a lens originally authored by a tier-1 reviewer, `valid_from` updates but chain of custody is invisible. The lens appears uniformly tier-1 in all temporal queries.

**Concrete failure scenario:**
2025-01-10: expert-reviewer (tier 1) creates "phenomenology-lens". 2025-02-15: fd-conceptual-cartographer (tier 3) adds a `references` edge. 2025-03-01: triage queries phenomenology-lens — sees `valid_from = 2025-02-15`, tier = 1. The tier-3 modification is unrecorded in the provenance. A triage query that trusts tier-1 lenses selects this lens for a P0 architectural review; the modification that changed it was made by a tier-3 generated agent.

**Affected components:** All entity/relationship tables, versioning strategy D9

**Smallest viable fix:**
Add `modified_by: text`, `modifier_tier: int`, `modification_type: enum[creation, property_update, edge_addition]` to all versioned entities. Triage queries check modification provenance: `WHERE created_by_tier <= 2 OR (modifier_tier <= 2 AND modification_type = 'creation')`.

---

## P2: Transitive derives-from Has No Weakest-Link Tier Policy

**Location:** D6 (`derives-from`), Epic Phase 3 (dedup pass)

**Finding:**
In hadith methodology, a chain is only as strong as its weakest transmitter. The graph must enforce this explicitly. The brainstorm does not specify: (a) maximum chain depth for tier inheritance, (b) whether a tier-1 → tier-2 → tier-3 chain results in tier-3 classification (weakest link), or (c) cycle handling.

**Recommendation:**
Document an ISNAD_POLICY: tier of lens = MIN(tier of all transmitters in derives-from chain), max traversal depth = 10, cycles detected → mark as `mawdu` (fabricated provenance). Implement as a stored Cypher procedure called by ingestion and by triage queries.

---

## P2: interlens MCP Migration Will Orphan Isnad-Equivalent Usage Logs

**Location:** D8 (interlens MCP adapter), Epic Phase 5

**Finding:**
The migration moves interlens's 288 lenses to the graph, but existing MCP request logs — which capture who invoked which lens at what time — are isnad data. They show transmission-in-use: which tier-1 reviewers actually deployed this lens in production. If those logs stay in the MCP server database rather than migrating as InvocationEvent nodes, the graph loses tawatur evidence (corroboration through repeated transmission).

**Recommendation:**
Add to Epic Phase 2 (ETL): extract MCP invocation logs, create `InvocationEvent` nodes `{lens_id, invoked_by, invoked_at, context_bead}`, link as `(p:Persona)-[:invoked {timestamp}]->(l:Lens)`. Triage can then weight: "Prefer lenses with >= 5 invocations by tier <= 2 reviewers in last 90 days."

---

## P3: same-as Threshold Question Should Reference Hadith Grading Matrix

**Location:** Open Questions ("What embedding similarity score counts as same-as vs. similar-to?")

**Finding:**
Instead of a single threshold, define an equivalence authentication matrix:

| Confidence | Source Independence | Corroborators | Relationship |
|---|---|---|---|
| >= 0.95 | TRUE | >= 4 | same-as (mutawatir) |
| >= 0.90 | TRUE | >= 1 | same-as (sahih) |
| >= 0.80 | FALSE | any | similar-to (ahad-da'if) |
| < 0.80 | any | any | related-to |

Document as "Equivalence Authentication Policy" in the schema specification.
