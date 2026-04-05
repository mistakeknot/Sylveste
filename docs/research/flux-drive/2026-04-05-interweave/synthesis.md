---
type: synthesis
document: docs/prds/2026-04-05-interweave.md
agents: 4
total_findings: 21
p0: 0
p1: 9
p2: 8
p3: 4
verdict: needs-changes
---

# Flux-Drive Synthesis: interweave PRD Review

## Review Scope

Four domain-specialist agents reviewed the interweave PRD through parallel professional discipline lenses: archival science (federated discovery, finding aids), health informatics (type system formality, crosswalks), geospatial SDI (catalog-of-catalogs, metadata discovery), and e-discovery (entity resolution, confidence scoring). The review focused on operational patterns from these disciplines that the concept brief identified but the PRD did not operationalize into acceptance criteria.

## Verdict: needs-changes

The PRD's architectural foundation is sound — the catalog-of-catalogs pattern, finding-aid test, no-write-through constraint, and named query templates are well-designed. But the acceptance criteria have significant gaps in three areas where the professional disciplines have decades of hard-won practice that the PRD does not yet reflect.

## Top Findings by Convergence

### Convergence 1: The type system is too rigid for an ecosystem that grows by plugin addition

Three agents independently flagged that the type family system (F1) and interaction rules will become a bottleneck as connectors multiply:

- **Clinical terminology**: The 7 interaction rules are a closed set with no extension mechanism. New connectors with domain-specific relationships must force-map to existing rules or request schema changes. (P1)
- **Clinical terminology**: All type families have the same binding strength — no formality gradient distinguishes stable schemas (Artifact, Actor) from inherently fuzzy ones (Evidence, Relationship). (P1)
- **Spatial data infrastructure**: The 5 type families were designed top-down from current analysis. No bottom-up extension convention exists for new families. (P3)
- **Archival provenance**: The relational calculus engine only specifies pair-wise (family_a, family_b) lookup, not compositional path queries across multiple families. (clinical, P1)

**Recommended fix:** Make interaction rules extensible via `{namespace}:{rule-name}` registration. Add binding strength (required/extensible/example) to family diagnostic properties. Add a family registration convention for connectors. These three changes convert the type system from "designed for today's 5 families and 7 rules" to "designed for tomorrow's N families and M rules."

### Convergence 2: Entity resolution omits persons and lacks cost-aware confidence

Two agents flagged that the crosswalk (F2) and confidence scoring (F4) have structural blind spots:

- **Litigation entity mapping**: Person-entity resolution is completely absent. The same developer appears as 3-4 different identifiers across subsystems, and the `who-touched` query returns noise instead of a unified answer. (P1)
- **Litigation entity mapping**: Confidence scoring lacks a cost model — a false-positive in `causal-chain` (high-stakes, agent acts on the result) has different consequences than a false-positive in `related-work` (low-stakes, agent uses for context). (P1)
- **Archival provenance**: Crosswalk entries lack descriptive provenance (who asserted the match, when, based on what evidence). (P2)
- **Clinical terminology**: No temporal validity on relationships — the schema captures creation but not expiration. (P2)

**Recommended fix:** Add an Actor identity table to F2 (separate from artifact identity resolution). Add per-query minimum confidence floors to F5 (high-stakes queries like `causal-chain` require `confirmed`/`probable` edges; low-stakes queries allow `probable` in traversal). Add `valid_from`/`valid_until` to the link schema in F4.

### Convergence 3: The bootstrap and ongoing adoption path has critical friction points

Three agents identified patterns that would prevent interweave from reaching the critical mass needed to be useful:

- **Spatial data infrastructure**: The minimum discovery threshold (4 fields) contradicts the "zero effort from producers" promise — every connector requires custom mapping code. (P1)
- **Spatial data infrastructure**: Query results lack per-connector coverage metadata — agents cannot distinguish "not found" from "not indexed." (P1)
- **Litigation entity mapping**: No iterative enrichment model — the system assumes comprehensive indexing before queries work, creating a bootstrap-period abandonment risk. (P2)
- **Archival provenance**: No lifecycle model for dynamic entities — sessions and plugins get the same TTL, which is wrong for both. (P2)

**Recommended fix:** Reduce the minimum discovery threshold to 2 fields (entity_id, subsystem) with auto-inference for the rest. Add per-connector coverage metadata to query results. Define broad/deep harvest modes so the initial bootstrap takes minutes, not hours. Configure per-type-family TTLs.

## Findings Not Converged (Single-Agent)

| Agent | Finding | Severity |
|-------|---------|----------|
| Archival | Multi-level description hierarchy missing — entities flattened into single graph layer | P1 |
| Archival | Finding-aid test destroys accumulated crosswalk identity chain history | P1 |
| Clinical | No natural-language entity resolution (interface terminology vs reference terminology) | P3 |
| Spatial | Identifier harmonization strategy deferred as open question when it should be a core decision | P2 |
| Spatial | No data currency metadata on connector harvest — stale connectors undetectable | P2 |
| Litigation | No semantic near-duplicate detection across subsystems | P2 |
| Litigation | No access control model on graph traversal | P3 |

## Acceptance Criteria Gaps Summary

The following acceptance criteria should be added to the PRD to operationalize the professional practices these agents surfaced:

| Feature | Gap | Source Agent | Priority |
|---------|-----|-------------|----------|
| F1 | Extensible interaction rules via namespace registration | Clinical | P1 |
| F1 | Binding strength (required/extensible/example) per family | Clinical | P1 |
| F1 | Hierarchical level property on entities; level-aware traversal | Archival | P1 |
| F1 | Path query composition across family sequences | Clinical | P1 |
| F1 | Family registration convention for new type families | Spatial | P3 |
| F2 | Actor identity crosswalk (person-entity resolution) | Litigation | P1 |
| F2 | Assertion provenance on crosswalk entries | Archival | P2 |
| F2 | Schema version tracking on connector entries | Clinical | P2 |
| F2 | Composite canonical ID format `{subsystem}:{native_id}` | Spatial | P2 |
| F3 | Reduced minimum threshold (2 fields) + auto-inference | Spatial | P1 |
| F3 | Broad/deep harvest modes for iterative enrichment | Litigation | P2 |
| F3 | Per-harvest timestamp tracking; overdue detection | Spatial | P2 |
| F3 | Generic filesystem connector template | Spatial | P1 |
| F4 | Temporal validity (`valid_from`/`valid_until`) on links | Clinical | P2 |
| F4 | Topic-overlap method for semantic near-duplicate detection | Litigation | P2 |
| F5 | Per-query minimum confidence floor for traversal edges | Litigation | P1 |
| F5 | Per-connector coverage metadata in query results | Spatial | P1 |
| F7 | Per-type-family TTL configuration | Archival | P2 |
| F7 | Crosswalk identity chain preservation during audit | Archival | P1 |

## Open Questions Resolved

The review resolves or narrows two of the PRD's four open questions:

**OQ3 (Entity input parsing):** The spatial data infrastructure agent recommends composite canonical IDs (`{subsystem}:{native_id}`) which makes disambiguation trivial — the subsystem prefix routes to the right connector, and the native ID is already familiar to agents and humans.

**OQ4 (Index size management):** The archival agent's per-type-family TTL and the litigation agent's broad/deep harvest modes together provide the retention policy: process entities (sessions, runs) get short TTLs with archive-to-cold-storage; artifact entities (files, plugins) get long TTLs or refresh-on-query; broad metadata is always retained; deep metadata expires per TTL.
