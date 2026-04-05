# Flux-Drive Synthesis: Interweave PRD

**Target:** `docs/prds/2026-04-05-interweave.md`
**Date:** 2026-04-05
**Agents:** 3 esoteric-domain specialists (Dogon cosmology, petrographic mineralogy, Burmese bedin astrology)
**Mode:** PRD review against prior concept-brief findings
**Prior review:** `docs/flux-drive/2026-04-04-ontology-graph-concept-brief/SYNTHESIS.md`

---

## Verdict: The Architecture Absorbed the Insights; the Specification Has Gaps

The PRD transformed the concept brief's taxonomic labeling system into a genuinely generative architecture. The five-layer recommendation from the concept-brief synthesis is recognizable in the PRD's structure:

| Concept-Brief Layer | PRD Implementation | Status |
|--------------------|--------------------|--------|
| L1: Identity Anchors (petrographic extinction angles) | F2: Identity Crosswalk with materialized index | Implemented |
| L2: Family Relational Calculus (bedin/bummo) | F1: 5 families + 7 interaction rules as "relational calculus engine" | Architecture present, specification incomplete |
| L3: Multi-Family Membership (twin-seeds/Ketu) | F1: Multi-family membership supported | Static membership specified, lifecycle transitions missing |
| L4: Schema Assembly (Dogon redundant embedding) | F3: Connector protocol with observation contracts | Partial -- covers entities but not relationship types |
| L5: Runtime Override (bedin Nat overlay) | F4: Confidence scoring with link provenance | Approximation -- lacks explicit override semantics |

The structural transformation from concept brief to PRD is strong. The PRD is not a taxonomy wearing a generative label -- it has the right bones. But the specification does not yet constrain the implementation enough to guarantee the generative property survives coding.

---

## Cross-Agent Convergence on the PRD

### Convergence Point 1: The generative property is claimed but not tested

All three agents independently identified the same gap: the PRD says "relational calculus engine" but the acceptance criteria do not include any test that distinguishes a genuine relational calculus from a taxonomy.

| Agent | Specific Gap |
|-------|-------------|
| **Dogon** | The 7 interaction rules are named but their family-pair mapping is not shown. Are there 10-15 matrix entries (generative) or 50+ (taxonomic)? |
| **Petrographic** | Diagnostic properties are named per-family but not per-entity-type -- no extinction angle table |
| **Bedin** | No acceptance criterion verifies that adding a new type requires ZERO rule changes (the defining property of a generative calculus) |

**Unified recommendation:** Add three acceptance criteria to F1:

1. **Family-pair interaction matrix:** A concrete table showing which interaction rule governs each (family_a, family_b) pair. If this table has 10-15 entries, the system is generative. If it has 50+, the system is still taxonomic.
2. **Growth test:** Adding a 6th entity type to the Artifact family requires zero changes to interaction rules. The new type automatically participates in all Artifact-family relationships.
3. **Diagnostic property table per entity type:** Each entity type's identity anchor (extinction angle) explicitly documented. Files use path; beads use bead_id; sessions use session_id; etc.

### Convergence Point 2: Lifecycle transitions (Ketu pattern) are the biggest remaining gap

Two agents converged on the same missing specification:

| Agent | Diagnosis |
|-------|-----------|
| **Dogon** | Multi-family membership resolves the twin-seed problem for static classification, but does not address entities that GAIN families over time |
| **Bedin** | The Ketu lifecycle transition -- where an entity's family set changes based on lifecycle events -- is not specified anywhere in the PRD |

The PRD supports multi-family membership (a Session can belong to Actor + Process + Evidence). But it does not specify HOW a Session that starts as Actor-only gains Process and Evidence membership as its lifecycle progresses. Without lifecycle transitions, multi-family membership is a static property set at creation time -- which means someone must know at creation time every family the entity will ever participate in. This is impractical for entities whose classification depends on future events (distillation, bead linking, deployment).

**Unified recommendation:** Add lifecycle transition specification to F1:

```
- [ ] Lifecycle transitions: entities can gain (but not lose) family memberships
      via declared lifecycle events. Transition rules per entity type.
- [ ] Lifecycle integration: when an entity gains a family, all interaction rules
      for that family immediately apply. No rule changes needed.
```

### Convergence Point 3: The identity crosswalk is the strongest feature

All three agents recognized F2 (Identity Crosswalk) as the PRD's most complete response to the concept-brief findings:

| Agent | Assessment |
|-------|-----------|
| **Dogon** | (No identity-specific finding -- defers to petrographic) |
| **Petrographic** | Michel-Levy chart is fully realized: materialized index, O(1) lookup, incremental updates, staleness TTL, finding-aid audit |
| **Bedin** | Materialized graph incrementality with destructive rebuild as safety valve |

F2 is implementation-ready. The remaining gaps (per-type diagnostic property table, grain-boundary resolution during ingest rather than post-hoc) are P2 specification refinements, not architectural issues.

---

## Findings Not Addressed by the PRD

Two concept-brief findings received no attention in the PRD:

1. **Deterministic type assignment from identifiers (bedin Finding 4):** The concept-brief review proposed pattern-based family assignment (`core/**` -> Artifact, `.beads/**` -> Process). The PRD relies entirely on connector-based assignment. This works for single-source entities but creates ambiguity for boundary entities that appear in multiple connectors. P2 severity -- worth adding as a future enhancement but not blocking.

2. **Runtime relationship overrides with expiration (bedin Finding 3):** The Nat overlay pattern (overrides tracked separately, linked to justification, auto-cleared when condition ends) is only approximated by confidence scoring. The PRD has no explicit mechanism for "this relationship contradicts the schema for the duration of sprint S8." P2 severity -- acceptable for v0.1 given the PRD's conservative design philosophy.

---

## Consolidated Finding Table

| # | Severity | Finding | Agents | Status |
|---|----------|---------|--------|--------|
| 1 | **P1** | Generative property claimed but not verified by acceptance criteria | Dogon, Bedin | Spec gap |
| 2 | **P1** | Ketu lifecycle transitions: entities gaining family membership over time not specified | Dogon, Bedin | Missing |
| 3 | **P2** | Family-pair interaction matrix not shown -- 7 rules exist but mapping to family pairs unclear | Dogon | Spec gap |
| 4 | **P2** | Per-entity-type diagnostic property table (extinction angles) not specified | Petrographic | Spec gap |
| 5 | **P2** | Grain-boundary entities use post-hoc dedup, not ingest-time resolution | Petrographic | Partial |
| 6 | **P2** | Function-level identity resolution needs confidence tiers | Petrographic | New |
| 7 | **P2** | Connector observation contracts cover entities but not relationship types | Dogon | Spec gap |
| 8 | **P2** | Deterministic type assignment from identifiers not specified | Bedin | Not addressed |
| 9 | **P2** | Runtime relationship overrides lack explicit Nat-overlay semantics | Bedin | Acceptable v0.1 |
| 10 | Resolved | Multi-family membership (twin-seed pattern) | Dogon | Fully addressed |
| 11 | Resolved | Materialized identity resolution index (Michel-Levy chart) | Petrographic, Bedin | Fully addressed |
| 12 | Resolved | Finding-aid audit and staleness TTL safeguards | Petrographic | Fully addressed |
| 13 | Resolved | Unclassified entity handling (fonio question) | Dogon | Fully addressed |
| 14 | Resolved | Pleochroism via multi-family membership | Petrographic | Fully addressed |

---

## Answers to the Four Review Questions

### Q1: Does the type family system implement a GENERATIVE calculus or is it still taxonomic?

**Answer: Architecturally generative, specification-wise ambiguous.**

The PRD describes the right architecture: 5 families, 7 interaction rules, "given (family_a, family_b) returns valid relationship types." This is the bummo/bedin pattern. But the acceptance criteria do not include any test that distinguishes a generative implementation from a taxonomic one. Specifically: (a) the family-pair interaction matrix is not shown, and (b) there is no "growth test" verifying that adding a new type requires zero rule changes. An implementer could satisfy all stated criteria while building a taxonomy.

**Fix:** Add the family-pair matrix and growth test to F1 acceptance criteria.

### Q2: Does the identity crosswalk distinguish diagnostic vs. contingent properties?

**Answer: Yes, structurally. The crosswalk schema separates identity (canonical_id) from subsystem-specific properties. The word "diagnostic" even appears in F1. But the per-entity-type diagnostic property table (the extinction angle per type) is not specified.**

File-level resolution is detailed (path normalization, git SHA, tree-sitter AST fingerprinting). Other entity types rely on implicit convention (bead_id for beads, session_id for sessions). Making the extinction angle explicit per type prevents developers from accidentally using contingent properties as identity anchors.

**Fix:** Add a diagnostic property (identity anchor) table to F2.

### Q3: Are the 7 interaction rules truly O(family-pairs) or do they require O(type-pairs) declarations?

**Answer: The acceptance criterion says "given (family_a, family_b) returns valid relationship types" -- this IS O(family-pairs). But the 7 rules are not mapped to family pairs in the PRD.** With 5 families yielding 15 unordered pairs, 7 rules is a plausible count (each rule governs ~2 family pairs). The specification does not show the mapping, which means an implementer could create rules that reference types instead of families without violating any stated criterion.

**Fix:** Show the family-pair matrix. This is one table, ~15 rows. It would also reveal whether 7 rules is the right number or whether some rules are actually type-level overrides misclassified as family-level rules.

### Q4: Is the Ketu lifecycle transition pattern concretely specified?

**Answer: No. This is the biggest gap.**

The PRD supports multi-family membership (static), but does not specify how entities gain new family memberships through lifecycle events. The "Lifecycle" interaction rule (one of the 7) might be intended for this purpose, but its name suggests it governs relationships between entities in a lifecycle context, not that entities undergo lifecycle transitions themselves. No acceptance criterion tests for an entity transitioning from one family set to a larger family set.

**Fix:** Add lifecycle transition rules to F1. At minimum: entities can gain family memberships via declared lifecycle events, and the relational calculus applies to the entity's current family set.

---

## Overall Assessment

The PRD is a strong transformation of the concept-brief. It absorbed the three key insights (generative calculus, multi-family membership, materialized identity index) and built them into the architecture. Of the 12 original concept-brief findings, 5 are fully resolved and 5 are partially addressed.

The two P1 gaps (generative property verification, Ketu lifecycle transitions) are specification-level, not architectural. The architecture supports both -- the PRD just needs to constrain the implementation with specific acceptance criteria that test for the generative property and for lifecycle transitions. These are additive changes (new acceptance criteria) not architectural changes.

The identity crosswalk (F2) and gravity-well safeguards (F7) are implementation-ready and among the strongest features in the PRD.
