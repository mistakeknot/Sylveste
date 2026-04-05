### Findings Index
- P1 | OSE-1 | "F1: Plugin Scaffold + Type Family System" | Multi-family membership creates combinatorial rule explosion without a resolution strategy
- P1 | OSE-2 | "F1: Plugin Scaffold + Type Family System" | No schema versioning or migration strategy for type family changes
- P2 | OSE-3 | "F1: Plugin Scaffold + Type Family System" | "Unclassified" status creates a shadow category that erodes type discipline over time
- P2 | OSE-4 | "F3: Connector Protocol + First Connectors" | Observation contract lacks schema evolution guarantees for connector metadata
- P1 | OSE-5 | "Features (general)" | 5 families x 7 rules = 35 cells but PRD specifies no rule matrix — which cells are valid?
Verdict: needs-changes

## Summary

The PRD proposes a generative ontology with 5 type families and 7 interaction rules that produce relationship types via relational calculus. The generative approach is architecturally sound — it avoids the Freebase failure mode of enumerating thousands of explicit relationship types. However, the PRD underspecifies the schema lifecycle: what happens when families change, when rules conflict under multi-family membership, and how the system absorbs new entity types from future plugins without breaking existing queries. The type family system is the load-bearing architectural decision and needs more rigor before implementation.

## Issues Found

### 1. [P1] Multi-family membership creates combinatorial rule explosion (OSE-1)

**File**: `docs/prds/2026-04-05-interweave.md`, F1 acceptance criteria, line 28

The PRD states "Multi-family membership supported (entity belongs to Process + Evidence simultaneously)" but does not specify how interaction rules resolve when an entity participates in multiple families. If entity X belongs to {Process, Evidence} and entity Y belongs to {Artifact, Actor}, the relational calculus must evaluate X's rules from both Process and Evidence families against Y's rules from both Artifact and Actor families. This is a 2x2 matrix per entity pair, and with 5 families, an entity could theoretically belong to all 5.

**Failure scenario**: A "review session" entity belongs to both Process (it's a workflow step) and Evidence (it produces findings). When querying relationships to an Artifact, the system returns both Transformation rules (Process->Artifact) and Evidence Production rules (Evidence->Artifact). Without a precedence or merge strategy, consumers see duplicate or contradictory relationship types for the same entity pair.

**Recommendation**: Add an acceptance criterion specifying the multi-family resolution strategy. Options: (a) union — return all valid relationship types from all family memberships (simple, but noisy); (b) primary family — each entity declares one primary family for rule resolution, secondary families for search only; (c) intersection — only return relationship types valid across ALL family memberships (conservative, may be too restrictive). The PRD should pick one and document why.

### 2. [P1] No schema versioning or migration strategy (OSE-2)

**File**: `docs/prds/2026-04-05-interweave.md`, F1, lines 19-29

The PRD describes the type family system as a static design: 5 families, 7 rules. But ontologies evolve. The schema.org versioning debacle (breaking changes between 3.x and 4.x that invalidated cached structured data across millions of sites) demonstrates what happens when a schema ships without an evolution contract.

Concrete scenarios that need answers:
- What happens when a 6th family is added? Do existing queries break?
- What happens when a rule is split (e.g., "Stewardship" becomes "Ownership" + "Guardianship")? Do existing links retype automatically?
- What happens when a family is retired? Do entities lose their membership and fall to "unclassified"?

The PRD's "new entity types can declare family membership(s) and inherit all family rules" handles entity-level evolution but not family-level or rule-level evolution.

**Recommendation**: Add to F1 acceptance criteria: "Family and rule additions are backward-compatible (existing queries return the same results after schema expansion). Family removal triggers a deprecation period where the family still resolves but emits a staleness warning." This can be a P2 acceptance criterion — the mechanism doesn't need to be built in v0.1, but the contract should be established now.

### 3. [P2] "Unclassified" status erodes type discipline (OSE-3)

**File**: `docs/prds/2026-04-05-interweave.md`, F1, line 29

"Unclassified status: entities without family membership appear in search but don't participate in relational calculus." This is pragmatic for bootstrapping but creates a permanent escape hatch. In the Wikidata ontology, the equivalent ("Q35120 — entity" as a catch-all type) became the dumping ground for 40%+ of items, making the type hierarchy unreliable for inference.

**Failure scenario**: Over 6 months, 60% of entities from new plugins remain "unclassified" because nobody classifies them. The relational calculus covers only 40% of the entity space. Agents learn to use direct subsystem queries instead. The ontology becomes a liability — maintained but unused.

**Recommendation**: Add a health metric to F7: "`interweave health` reports the percentage of entities that are unclassified. Alert when unclassified > 30%." This creates pressure to classify without forcing it at ingestion time.

### 4. [P2] Observation contract lacks schema evolution guarantees (OSE-4)

**File**: `docs/prds/2026-04-05-interweave.md`, F3, lines 51-52

The observation contract defines `entities_indexed, granularity, properties (captured/inferred), refresh cadence, freshness_signal` — but does not specify what happens when a connector adds new properties, removes old ones, or changes granularity. If the cass connector starts indexing tool-call arguments (a new property), does the crosswalk need to rebuild? If tldr-code changes from function-level to statement-level granularity, do existing canonical entity IDs break?

**Recommendation**: Add to F3 acceptance criteria: "Observation contracts are versioned. Property additions are backward-compatible. Property removals trigger a deprecation signal to interweave before removal. Granularity changes require a new entity_type (not mutation of existing)."

### 5. [P1] 5 families x 7 rules = 35 cells but no rule matrix specified (OSE-5)

**File**: `docs/prds/2026-04-05-interweave.md`, F1, lines 19-21

The PRD says "7 interaction rules (Productivity, Transformation, Stewardship, Structure, Evidence Production, Annotation, Lifecycle) as a relational calculus engine" and "given (family_a, family_b), returns valid relationship types." But the actual rule matrix — which family pairs produce which relationship types — is not specified. This is the core design artifact of the ontology and it is absent.

For example:
- Productivity: Actor -> Artifact? Actor -> Process? Both?
- Transformation: Process -> Artifact only? Or also Artifact -> Artifact?
- Evidence Production: who produces evidence about whom?

Without this matrix, implementers must guess, and different implementers will guess differently. The 7 rule names are evocative but not precise.

**Failure scenario**: Implementation interprets "Stewardship" as Actor->Artifact (ownership), but the PRD author intended Actor->Process (process governance). Every query involving Stewardship returns wrong results. Discovered only after agents have been using the wrong relationships for weeks.

**Recommendation**: Add an appendix or linked document containing the complete 5x5 family-pair matrix with the valid interaction rules for each cell. This is the specification that makes "generative" concrete rather than aspirational.

## Improvements

1. **Add a "Type Family Decision Record"** documenting why these 5 families and 7 rules were chosen, what alternatives were considered, and what real entity examples map to each family. This makes future schema evolution decisions traceable.

2. **Consider making families extensible by plugins.** The PRD's generative architecture already supports this ("new entity types can declare family membership"), but does not allow plugins to declare new families. If a future plugin introduces a "Policy" family (governance rules, constraints, thresholds), the current design requires modifying the core type family system. A plugin-extensible family registry would be more aligned with the "composition over capability" philosophy.

3. **Specify the closed-world vs. open-world assumption explicitly.** When `(family_a, family_b)` returns no valid relationship types, does that mean the relationship is impossible (closed-world) or merely not yet defined (open-world)? The answer affects every consumer of the relational calculus. The closed-world interpretation is safer for agent queries (no false positives); the open-world interpretation is better for ontology evolution (new rules can be added without invalidating the "no relationship" assumption).

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 3, P2: 2)
SUMMARY: The generative type family architecture is sound in principle but underspecified in practice — the rule matrix, multi-family resolution strategy, and schema evolution contract are all missing from the PRD.
---
<!-- flux-drive:complete -->
