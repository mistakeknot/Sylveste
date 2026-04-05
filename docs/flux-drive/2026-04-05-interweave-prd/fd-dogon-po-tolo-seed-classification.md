# fd-dogon-po-tolo-seed-classification -- PRD Review Findings

**Target:** `docs/prds/2026-04-05-interweave.md`
**Agent:** fd-dogon-po-tolo-seed-classification (Mali Dogon cosmology: generative type systems)
**Decision Lens:** Evaluates whether the PRD's type system is generative (category membership derives relationships) or still taxonomic (labels that group without deriving). Checks dual-classification and relationship algebra implementation.
**Prior review:** `docs/flux-drive/2026-04-04-ontology-graph-concept-brief/fd-dogon-po-tolo-seed-classification.md` (concept brief)

---

## Context: What This Agent Asked For vs. What the PRD Delivers

The concept-brief review raised 5 findings. The PRD explicitly addresses 4 of them. This review evaluates whether the addresses are structural or cosmetic.

---

## Finding 1: The relational calculus is specified but its generative mechanism is ambiguous

**Severity: P1**
**File:** `docs/prds/2026-04-05-interweave.md`, F1, lines 19-30

The PRD names the right concepts: "5 type families," "7 interaction rules," "relational calculus engine" (line 21). It says "New entity types can declare family membership(s) and inherit all family rules" (line 28) and "7 interaction rules implemented -- given (family_a, family_b), returns valid relationship types" (line 27). This is the bummo pattern -- the right architecture.

**However:** The 7 interaction rules (Productivity, Transformation, Stewardship, Structure, Evidence Production, Annotation, Lifecycle) are named but their generative mechanism is not specified. The concept-brief review asked whether rules operate at O(family-pairs) or O(type-pairs). The PRD acceptance criterion says "given (family_a, family_b), returns valid relationship types" -- this IS the O(family-pairs) pattern. But the named rules do not map to family-pair inputs. "Productivity" is a rule name, but which family pair does it compute? "Annotation" applies when... what?

**The Dogon structural isomorphism:** In the bummo system, each interaction rule has clear antecedents: bummo 3 + bummo 7 = productive combination. The rule IS the family-pair mapping. The PRD names 7 rules but does not show which family pairs they apply to. If the 7 rules are 7 flavors of relationship that each require separate per-family-pair declaration, the system is O(families * rules), not O(family-pairs). If the rules are COMPUTED from the family pair (e.g., Artifact + Actor always yields Productivity), the system is genuinely generative.

**Question (not assertion):** Do the 7 interaction rules function as a lookup table indexed by (family_a, family_b) -- where each family pair maps to exactly one rule -- or as 7 independent rule categories that must each be declared for each family pair? The former is generative (O(family-pairs) = 10 entries for 5 families). The latter is still combinatorial (5*5*7 = 175 potential declarations).

**Smallest viable fix:** Add a family-pair interaction matrix to F1's acceptance criteria:

```
| Family A      | Family B      | Interaction Rule     |
|---------------|---------------|---------------------|
| Artifact      | Process       | Transformation      |
| Artifact      | Actor         | Productivity        |
| Actor         | Process       | Stewardship         |
| Actor         | Evidence      | Evidence Production |
| Relationship  | Artifact      | Structure           |
| Evidence      | Artifact      | Annotation          |
| Process       | Actor         | Lifecycle           |
```

If the matrix has 10-15 entries (one per unordered family pair), the system is generative. If it has 50+, the system is still taxonomic wearing a generative name.

---

## Finding 2: Multi-family membership is specified and structurally sound

**Severity: RESOLVED (from prior P1)**
**File:** `docs/prds/2026-04-05-interweave.md`, F1, lines 28-29

The PRD explicitly specifies: "Multi-family membership supported (entity belongs to Process + Evidence simultaneously)" (line 29). This directly addresses the twin-seed finding from the concept-brief review. An entity declaring membership in Process + Evidence inherits interaction rules from both families -- the bummo dual-classification mechanism.

**Remaining question:** The PRD does not describe how conflicting rules from dual membership are resolved. If an entity belongs to both Artifact and Process, and a query involves an Actor, which interaction rule applies -- Productivity (Artifact + Actor) or Stewardship (Process + Actor)? The Dogon twin-seed mechanism applies BOTH: the entity participates in both relationship portfolios simultaneously. Does the PRD intend the same? The acceptance criterion "inherit all family rules" (line 28) suggests yes, but it should be explicit.

---

## Finding 3: The "Unclassified" status addresses the fonio question

**Severity: RESOLVED (from prior P3)**
**File:** `docs/prds/2026-04-05-interweave.md`, F1, line 30

The PRD says "Unclassified status: entities without family membership appear in search but don't participate in relational calculus" (line 30). This is a deliberate design choice -- NOT the Dogon fonio pattern (which gives unclassified entities a default bummo with a full relationship portfolio) but a different valid approach: unclassified entities are visible but inert.

This is actually safer for the interweave use case. The fonio-default gives every entity some relationships, which can create noise. The PRD's approach says "we see you but won't guess your relationships" -- appropriate for a catalog-of-catalogs that should be conservative about inferred relationships.

---

## Finding 4: Schema drift detection is partially addressed through connectors

**Severity: P2 (reduced from prior P2)**
**File:** `docs/prds/2026-04-05-interweave.md`, F3, lines 49-58

The PRD's connector protocol (F3) with "observation contracts" (line 51) partially addresses the schema-drift concern. Each connector declares what it provides: `entities_indexed, granularity, properties, refresh_cadence, freshness_signal`. This means the ontology assembles from subsystem declarations -- the Dogon redundant-embedding pattern in structural form. If a subsystem adds a new entity type, the connector contract changes, and interweave detects the delta.

**However:** The observation contract describes what data the connector provides, not what relationship types exist between entities in that subsystem. Beads has 6 relationship types internally (blocks, depends, parent, caused_by, etc.). If beads adds a 7th, the connector might not surface it because the contract only covers `entities_indexed` and `properties`, not relationship types.

**Smallest viable fix:** Add `relationship_types` to the observation contract format in F3's acceptance criteria:

```
Observation contract format: entities_indexed, granularity, properties (captured/inferred),
  relationship_types (internal relationships the connector can surface), refresh_cadence, freshness_signal
```

---

## Finding 5: Relationship algebra exists but needs explicit acceptance testing

**Severity: P2**
**File:** `docs/prds/2026-04-05-interweave.md`, F1, line 30

The PRD's unit tests criterion says "family declaration, rule inheritance, multi-family, unclassified behavior" (line 30). This is good but does not include the critical generative test: when a NEW type is added to a family, do its relationships appear automatically without additional declarations?

**The Dogon structural isomorphism:** The proof that the bummo system is generative is that when Griaule's informant Ogotemmeli described a previously uncategorized plant and assigned it to bummo 3, its relationships to every other bummo were immediately known without further enumeration. The test for interweave's generative claim is the same: add a new type to the Artifact family and verify that all 4 Artifact-family interaction rules activate for that type automatically.

**Smallest viable fix:** Add a test case to F1 acceptance criteria:

```
- [ ] Generative test: adding a new type with family=[Artifact] automatically enables all Artifact-family
      interaction rules without additional rule declarations. Removing the type removes its participation.
```

---

## Summary

| # | Severity | Finding | Status vs. Concept Brief |
|---|----------|---------|-------------------------|
| 1 | P1 | 7 interaction rules named but generative mechanism ambiguous -- family-pair matrix missing | Partially addressed |
| 2 | Resolved | Multi-family membership explicitly specified (twin-seed pattern) | Fully addressed |
| 3 | Resolved | Unclassified status handles the fonio question | Fully addressed |
| 4 | P2 | Schema drift: connector contracts cover entity properties but not relationship types | Partially addressed |
| 5 | P2 | Generative behavior not tested -- no acceptance criterion for auto-inheritance | New finding |

**Overall assessment:** The PRD absorbed the core Dogon insight (generative type families with multi-family membership). The remaining gap is that the 7 interaction rules are named but their generative mechanism -- the family-pair matrix that makes them O(family-pairs) rather than O(type-pairs) -- is not concretely specified. The architecture is right; the specification needs one table.
