### Findings Index
- P1 | OSD-01 | "D4. Object types for V1 (7 of 8)" | Domain and Discipline are not orthogonal — overlap will be >40%
- P1 | OSD-02 | "D2. Model: two linked entities + D4/D6" | Identity vs. versioning semantics for Lens edits are unspecified
- P1 | OSD-03 | "D4. Object types" | Concept vs. Lens boundary is undefined — Lenses reference Concepts but forces/solution fields contain unlinked concepts
- P2 | OSD-04 | "D4 + D9" | Task-context-as-Persona-property contaminates triage queries
- P2 | OSD-05 | "D6. Relationships" | `bridges` and `contradicts` may both be special cases of a signed `relates-to` with polarity — 10 edge types risks redundancy
- P2 | OSD-06 | "D9. Versioning" | `valid_from`/`valid_to` on entities AND relationships without clarification of which is authoritative on conflict
- P3 | OSD-07 | "Appendix + D6" | `same-as {confidence, method}` lacks a canonical-form rule for transitive closure
Verdict: needs-changes

## Summary

The 7-type / 10-edge taxonomy is a credible first cut, but three of the seven type distinctions (Domain vs. Discipline, Concept vs. Lens, Task-context as Persona property) are under-specified in ways that will force a V2 migration over 100k+ rows. The schema is silent on the single most consequential commitment: when a Lens is edited, is that a mutation of the existing node, or a new node with a `supersedes` edge? That decision pervades ingestion, dedup, triage, and every view. It must be frozen before DDL is written.

## Issues Found

### 1. [P1] Domain vs. Discipline will collapse in practice — OSD-01

**File:** `docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md`, D4 (§"Object types for V1"), lines 56-61.

The brainstorm defines:
- **Domain** as "cross-cutting tag (agent-systems, orchestration, compliance)"
- **Discipline** as "formal field of study (organizational psychology, systems theory)"

These are framed as distinct but the examples already leak: "agent-systems" is both a cross-cutting tag AND a formal field of study (or at least a sub-field of distributed systems + AI). "Compliance" is a tag, but "compliance engineering" and "regulatory science" are disciplines. After ingesting 660 fd-agents (which use `domains:` frontmatter as a free-form list) and 291 Auraken lenses (which have `discipline:` as a single string), the two axes will collide on most entries.

**Failure scenario:** After ingestion, >40% of Domain values have a near-identical Discipline entry. Triage queries that filter "in-domain AND in-discipline" over-constrain (finding nothing) or double-count (finding the same thing twice). Users fix by picking one axis, which means the other was never really needed.

**Smallest fix:** Before DDL, produce a concrete mapping of the existing 660 fd-agent `domains` frontmatter values and 291 Auraken `discipline` values into the proposed schema. If >30% of Domains have a near-equivalent Discipline, collapse to one type with a `kind: {tag, formal-field}` property. Defer the distinction to V2.

### 2. [P1] Identity semantics for edited Lenses are unspecified — OSD-02

**File:** same brainstorm, D2 + D4 + D9, lines 47-48, 56-61, 83-84.

The brainstorm says Lens has fields like `forces`, `solution`, `questions`. It says D9 adds `valid_from`/`valid_to` timestamp columns. It mentions `supersedes` as a relationship in D6. What it does not say is: when a user edits `Lens.forces` to add a new force, is that:

(a) an in-place mutation of the existing Lens node (identity preserved, history is `valid_from` bookkeeping)?
(b) a new Lens node with `supersedes` to the old (identity changes, `valid_to` closes the old node)?
(c) copy-on-write only when the edit crosses a "material change" threshold?

This ambiguity is not merely academic. It determines:
- Whether `wields` edges point to the stable Lens or the historical version
- Whether the dedup pass operates on current lenses or all lens versions
- Whether `bridges {strength}` strength is recomputed per edit
- Whether Hermes conversational view sees "the lens" or "this week's lens"
- How the catalog view renders lens URLs

**Failure scenario:** Two users edit the same Lens concurrently. Under (a), one edit overwrites the other silently. Under (b), two divergent `supersedes` chains form, neither canonically "current." Under unspecified, the graph has no rule and the result is database-implementation-dependent.

**Smallest fix:** Add a D10 decision that commits to one identity model. Recommended: immutable Lens nodes with `supersedes` and a `lens_identity_uuid` that persists across supersedes chains — so `wields` edges point to the `lens_identity_uuid` and the graph always knows "the current Lens for this identity." Ingest is simpler (everything is an insert). Dedup operates on current-identity-only (a view). Edits never race. If this model is rejected, document why and specify the alternative explicitly.

### 3. [P1] Concept vs. Lens boundary is undefined — OSD-03

**File:** same brainstorm, D4 + D6, lines 56-61, 73-74.

D4 defines **Concept** as "named idea a lens references (emergence, feedback loop, enabling constraint)" and D6 has `Lens —[references]→ Concept`. But Lens itself has `forces` and `solution` as fields, which in practice contain exactly these kinds of named ideas as free text. A lens like "enabling constraint as design move" IS the concept "enabling constraint" in Lens form. The line between "Lens about enabling constraint" and "Concept: enabling constraint with some attached questions" is not drawn anywhere.

**Failure scenario:** After ingestion, Concepts are either (a) redundant — every Lens spawns a Concept for its name, inflating the graph 2x, or (b) underpopulated — only a handful of "famous" Concepts exist because nobody knows when to create one. Either way, `references` edges are noisy and the type earns nothing.

**Smallest fix:** Define the Concept→Lens promotion rule: a Concept exists only when >= N (N=3?) Lenses reference it. Until then, `forces`/`solution` stays as text. Alternatively, defer Concept to V2 and treat `forces`/`solution` as strings in V1. The brainstorm already defers Task-context for similar reasons; Concept belongs in the same bucket until the use case is concrete.

### 4. [P2] Task-context on Persona contaminates triage — OSD-04

**File:** same brainstorm, D4 last bullet, lines 60-61.

"Task-context... retained as a property on Persona for provenance, not promoted to first-class." This sounds like a conservative choice but the consequence is that the Persona's `domains` property will include task-context-derived domains (e.g., "AGE query economics" for fd-age-cypher-query-economics). Triage Cypher that matches `Persona.domains` will over-fire on task-context noise. Every fd-gen generation adds a new Persona with unique task-context-derived domains — the domain vocabulary inflates monotonically.

**Failure scenario:** fd-drive triage view for a "database performance" diff matches fd-age-cypher-query-economics because its Persona has the domain tag from its task-context. Over time, Persona.domains becomes a bag of generation-artifact terms rather than a clean taxonomy. Triage can't distinguish essential persona identity from generation-provenance metadata.

**Smallest fix:** Split into `Persona.essential_domains` (curated, from a controlled vocabulary) and `Persona.generation_context` (raw, provenance-only, not indexed for triage). Triage queries read `essential_domains` only. This is cheap to add now; impossible to retrofit after 1200 rows exist.

### 5. [P2] Edge-type redundancy: `bridges` + `contradicts` may subsume under signed `relates-to` — OSD-05

**File:** same brainstorm, D6, lines 69-75.

Ten edge types is a lot to justify. `bridges` (positive), `contradicts` (negative), `supersedes` (temporal), `same-as` (equivalence), `derives-from` (source lineage), `in-domain`/`in-discipline` (categorical), `references` (concept), `cites` (evidence), `wields` (persona↔lens). Several feel like properties on a single `relates-to` edge type with `{kind, polarity, strength}` fields rather than distinct labels.

**Failure scenario:** Not a 3 AM failure — a slow tax. Cypher queries that want "any relationship between these two lenses" must union all edge types. Schema evolution (e.g., adding `refines` or `dialogues-with`) requires a new edge type each time. At 10 types you can reason about them; at 20 you need a meta-schema.

**Smallest fix:** Keep the high-traffic types distinct (`wields`, `same-as`, `derives-from`, `bridges`, `supersedes`) — they have different query patterns. Collapse `contradicts`/`refines`/`references` under a typed `relates-to {kind, polarity}` edge. Six edge types beats ten.

## Improvements

### 1. Commit to canonical form for `same-as` transitive closure — OSD-07

`same-as` is declared symmetric with `confidence`. What about transitivity? If A same-as B (0.8) and B same-as C (0.8), is A same-as C at 0.8? 0.64 (product)? Undefined? The dedup pass will need this rule to decide whether to collapse chains. Add a §§ to D7 specifying: "same-as is not transitive. A same-as B and B same-as C does not imply A same-as C; each pair has an independent confidence."

### 2. Name the DDL source-of-truth artifact

The epic-shape sketch says "Design the 7-type ontology in AGE, write DDL, commit to migrations." Commit where? A `migrations/` directory under which module (new `interontology`? Auraken? interlens)? Naming this now unblocks the plan-step and forces the plugin-home open-question to be resolved before children beads are filed.

### 3. For each object type, document 2 negative examples

"What is NOT a Persona?" "What is NOT a Concept?" Two negative examples per type in the spec prevents the `Concept vs. Lens` style confusion at ingestion time. This is a cheap doc exercise with high future-session ROI.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FILES: 0 changed
FINDINGS: 7 (P0: 0, P1: 3, P2: 3, P3: 1)
SUMMARY: Taxonomy is a credible first cut but Domain/Discipline overlap, Concept/Lens boundary, and Lens identity-vs-versioning semantics must be resolved before DDL. Freeze the identity model first — it pervades everything downstream.
---
<!-- flux-drive:complete -->
