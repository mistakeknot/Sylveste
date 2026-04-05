# fd-burmese-bedin-planetary-relational-calculus -- PRD Review Findings

**Target:** `docs/prds/2026-04-05-interweave.md`
**Agent:** fd-burmese-bedin-planetary-relational-calculus (Myanmar astrology: relational calculus from O(1) category rules)
**Decision Lens:** Evaluates whether relationships are computed from type-level rules or enumerated per pair. Checks context-dependent type transitions (Ketu), runtime overrides (Nat), deterministic type assignment, and materialized graph incrementality.
**Prior review:** `docs/flux-drive/2026-04-04-ontology-graph-concept-brief/fd-burmese-bedin-planetary-relational-calculus.md` (concept brief)

---

## Context: What This Agent Asked For vs. What the PRD Delivers

The concept-brief review raised 5 findings. The PRD addresses 3 directly and 2 partially. This is the agent whose insights underwent the most transformation from concept brief to PRD -- the "relational calculus" framing is now the PRD's core architecture claim.

---

## Finding 1: The O(family-pairs) claim is architecturally present but not verified by acceptance criteria

**Severity: P1**
**File:** `docs/prds/2026-04-05-interweave.md`, F1, lines 21-30

The PRD describes the system as "a relational calculus engine" (line 21) with "7 interaction rules implemented -- given (family_a, family_b), returns valid relationship types" (line 27). This IS the bedin pattern: relationships computed from house (family) membership via interaction rules.

**The bedin structural isomorphism applied to the PRD:** The bedin has 8 houses and 3 interaction types (trine, opposition, square). The complete 8x8 matrix of inter-house relationships is generated from these 3 rules. The PRD has 5 families and 7 interaction rules. The 5-family system yields C(5,2) + 5 = 15 unordered pairs (including self-pairs). If each pair maps to exactly one interaction rule, 7 rules covering 15 pairs is clean -- some rules govern multiple pairs. This is structurally sound.

**However:** The acceptance criteria do not include a test that verifies the O(family-pairs) claim. Specifically, there is no criterion that says: "Adding a new entity type to the Artifact family does NOT require adding new interaction rules or modifying existing ones." Without this test, the implementation could degrade into per-type rule declarations while still technically satisfying the stated criteria.

**Failure scenario:** A developer implements F1 by creating a `rules.yaml` where each rule lists specific entity types rather than families. The rule "Productivity" lists `{File -> Agent, Module -> Agent, Test -> Agent}` instead of `{Artifact -> Actor}`. This passes all current acceptance criteria (rules exist, given two entities it returns valid relationships, new types can "declare family membership") but the generative property is lost -- adding a new Artifact type requires editing every rule that involves Artifacts.

**Smallest viable fix:** Add two acceptance criteria to F1:

```
- [ ] O(family-pairs) verification: interaction rules reference families, not types. No type name
      appears in any rule definition except as an override.
- [ ] Growth test: adding a 6th entity type to the Artifact family requires ZERO changes to
      interaction rules. All Artifact-family rules automatically apply to the new type.
```

---

## Finding 2: The Ketu lifecycle transition is specified at family level but not at entity level

**Severity: P1**
**File:** `docs/prds/2026-04-05-interweave.md`, F1, lines 28-29

The PRD supports multi-family membership (line 29) and says new entity types "can declare family membership(s)" (line 28). But entity type declaration is static -- it happens once, at registration time. The Ketu problem is about TEMPORAL type transitions: an entity that gains new family memberships as it moves through its lifecycle.

**The bedin structural isomorphism:** Wednesday-before-noon is Rahu's house. Wednesday-after-noon is Ketu's house. The same entity (Wednesday) changes house assignment based on temporal context. In the ontology graph, a Session starts as an Actor entity (during execution), gains Process membership when linked to a bead, and gains Evidence membership when its learnings are distilled. These transitions are lifecycle events, not static declarations.

**Question:** Does "Multi-family membership supported" (line 29) mean an entity can gain new family memberships after initial creation? Or only that it can be created with multiple families from the start?

The PRD's 7th interaction rule is named "Lifecycle." This might be where entity-level type transitions live. But the acceptance criteria for F1 do not include any criterion about entities GAINING family membership over time. Every criterion describes static declarations and inheritance.

**Failure scenario:** A Session is created with `families: [Actor]` (it is an executing agent). The session closes, a bead links it, and reflection distills its learnings. The Session should now participate in Actor + Process + Evidence queries. But if family membership is static, the Session remains Actor-only. An agent asking "what evidence was produced during sprint S7?" never finds this Session because it is not in the Evidence family.

The concept-brief review proposed a lifecycle state machine:

```yaml
Session:
  states:
    active:     families: [Actor]
    completed:  families: [Actor, Process]
    distilled:  families: [Actor, Process, Evidence]
  transitions:
    - from: active, to: completed, when: bead_linked
    - from: completed, to: distilled, when: reflection_complete
```

The PRD's "Lifecycle" interaction rule might be intended for this purpose, but the acceptance criteria do not specify entity-level lifecycle transitions. This is the single most important gap between the concept-brief synthesis and the PRD.

**Smallest viable fix:** Add explicit lifecycle transition criteria to F1:

```
- [ ] Lifecycle transitions: entities can gain family memberships via lifecycle events
      (e.g., Session gains Evidence membership after reflection). Transition rules
      declared per entity type. New memberships inherit all family interaction rules.
- [ ] Lifecycle test: a Session created with families=[Actor] transitions to
      families=[Actor, Process, Evidence] and participates in Evidence-family queries.
```

---

## Finding 3: The Nat overlay (runtime relationship overrides) is partially addressed through confidence scoring

**Severity: P2 (reduced from prior P2)**
**File:** `docs/prds/2026-04-05-interweave.md`, F4, lines 61-71

The PRD's confidence scoring feature (F4) tracks link provenance: `method, confidence, evidence[], created_at, last_verified_at`. This provides a mechanism for distinguishing schema-derived relationships from runtime observations. A schema-derived relationship has `method: family-calculus, confidence: confirmed`. A runtime override could have `method: temporal-cooccurrence, confidence: probable`.

**However:** This is not structurally the Nat overlay pattern. The Nat overlay has three properties the confidence system lacks:
1. **Explicit override semantics:** A Nat override explicitly contradicts the planetary baseline. The confidence system has no "contradicts-schema" flag.
2. **Expiration linked to justification:** Nat overrides end when the ritual condition ends. The confidence system has `last_verified_at` and staleness TTL, but no "expires when bead X closes" mechanism.
3. **Separate storage:** Nat overrides are tracked in a separate system from the planetary calculus. The confidence system co-mingles schema-derived and runtime relationships in the same link table.

**Question:** Is the lack of explicit runtime overrides acceptable for v0.1? The PRD is deliberately conservative (catalog-of-catalogs, no write-through, finding-aid test). Runtime overrides add complexity. The concept-brief finding was P2, not P1 -- it degrades quality over weeks but does not block initial value.

**Assessment:** Acceptable for v0.1. The confidence scoring provides enough mechanism to distinguish relationship provenance. Explicit Nat-overlay semantics can be added in a future iteration if runtime overrides prove common.

---

## Finding 4: Deterministic type assignment is not specified

**Severity: P2**
**File:** `docs/prds/2026-04-05-interweave.md`, F3, lines 49-58

The concept-brief review proposed deterministic type assignment from entity identifiers (the bedin name-syllable pattern): `core/**` = Artifact, `.beads/**` = Process, `interverse/**` = infrastructure. The PRD does not include this mechanism. Entity type assignment is implicit -- entities are typed by their source connector. The cass connector harvests sessions (Actor), the beads connector harvests beads (Process), the tldr-code connector harvests files and functions (Artifact).

**The bedin structural isomorphism:** Connector-based assignment is the equivalent of asking a person's planetary house by checking which temple they visit rather than computing it from their name. It works when each entity has exactly one connector source, but fails for boundary entities that appear in multiple connectors. A file path appears in tldr-code (Artifact) but also in cass (files_touched in a session -- Actor context) and in beads (files changed in a bead -- Process context). Without explicit type assignment rules, the file's family depends on which connector harvested it first.

**Smallest viable fix:** Add a type assignment strategy to F1 or F3:

```
- [ ] Type assignment: entity family determined by (1) connector-declared type for single-source
      entities, (2) path-pattern rules for entities appearing in multiple connectors
      (e.g., core/** -> Artifact regardless of which connector surfaces it),
      (3) explicit declaration as override.
```

---

## Finding 5: Materialized graph incrementality is specified and sound

**Severity: RESOLVED (from prior P2)**
**File:** `docs/prds/2026-04-05-interweave.md`, F2, line 43; F7, lines 102-109

The PRD specifies "Incremental updates (don't rebuild entire crosswalk on each change)" (F2, line 43) and "Finding-aid audit script: interweave audit deletes the entire index, verifies all subsystems still function, and rebuilds" (F7, line 108). The incremental update addresses the Mandalay problem (rule changes don't require full rebuild). The finding-aid audit provides a safety valve: if the materialized view drifts, you can destroy and rebuild it without data loss.

The combination of incremental updates for normal operation and destructive rebuild for recovery is structurally sound.

---

## Summary

| # | Severity | Finding | Status vs. Concept Brief |
|---|----------|---------|-------------------------|
| 1 | P1 | O(family-pairs) claim not verified by acceptance criteria -- implementation could degrade | Partially addressed |
| 2 | P1 | Ketu lifecycle transitions: entities gaining family membership over time not specified | NOT addressed |
| 3 | P2 | Nat overlay: confidence scoring approximates but lacks explicit override semantics | Partially addressed (acceptable for v0.1) |
| 4 | P2 | Deterministic type assignment from identifiers not specified | NOT addressed |
| 5 | Resolved | Materialized graph incrementality with finding-aid rebuild | Fully addressed |

**Overall assessment:** The PRD adopted the bedin's relational calculus as its core architecture ("5 type families, 7 interaction rules, relational calculus engine"). The structural design is right. But two critical behaviors are unspecified: (1) the mechanism that ensures rules operate at family level rather than type level (the O(family-pairs) guarantee), and (2) the lifecycle transition mechanism by which entities GAIN family memberships over time (the Ketu pattern). Without these, the PRD describes a system that could be implemented as either a genuine relational calculus or a taxonomy with a generative label. The acceptance criteria need to distinguish between the two by testing for the generative property directly.
