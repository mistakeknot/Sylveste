### Findings Index
- P1 | CCP-1 | "Solution" | Catalog-of-catalogs claim is credible but needs explicit enforcement beyond F7 safeguards
- P1 | CCP-2 | "F3: Connector Protocol" | Connector registration creates implicit coupling — plugins must know about interweave to be indexed
- P2 | CCP-3 | "F1: Plugin Scaffold + Type Family System" | 5 fixed type families risk premature abstraction before real query patterns are observed
- P1 | CCP-4 | "Non-goals" | Non-goal of "no graph database" is correct but the decision rationale should be in the PRD, not implied
- P2 | CCP-5 | "F8: Philosophy Amendment" | The PHILOSOPHY.md amendment should explain why this isn't "unifying storage" — the distinction is subtle and load-bearing
- P1 | CCP-6 | "Dependencies" | Dependency on tree-sitter creates an implicit language support boundary
Verdict: needs-changes

## Summary

The PRD navigates the central tension well: PHILOSOPHY.md says "unify retrieval, not storage" and "standalone plugins fail-open," yet interweave proposes a cross-system index that all subsystems contribute to. The catalog-of-catalogs framing is the right resolution — interweave owns no entity data, delegates to source subsystems, and passes the finding-aid test (deletable without impact). However, this framing is a semantic commitment, not an architectural guarantee. The PRD needs stronger structural enforcement to prevent the catalog from drifting toward a system of record, and the connector model needs to work without requiring plugins to know about interweave.

## Issues Found

### 1. [P1] Catalog-of-catalogs needs structural enforcement beyond F7 (CCP-1)

**File**: `docs/prds/2026-04-05-interweave.md`, Solution, lines 13-15 + F7, lines 105-111

The PRD makes the right architectural claim: "The ontology is a catalog-of-catalogs: it never owns entity data, delegates to source subsystems, and passes the finding-aid test (deletable without impact)." F7 provides safeguards: no-write-through, staleness TTL, finding-aid audit.

But the gravity-well risk is organizational, not just technical. In every "catalog of catalogs" system I've studied (OCLC WorldCat, Google Dataset Search, data.gov), the drift pattern is identical:
1. Catalog starts as pure metadata projection
2. Users request "enrichment" — add labels, tags, status fields to the catalog
3. Enrichments become the authoritative source for those fields (no other system tracks them)
4. Catalog is now a partial system of record, indistinguishable from the thing it was supposed to index

The F4 "Evidence" field on links is the first enrichment. Who authored those evidence observations? If the answer is "interweave's connectors during harvest," then the evidence exists only in interweave — it is owned data, not projected data.

**Failure scenario**: Over 3 months, agents start relying on interweave's link provenance data (F4) as the authoritative record of cross-system relationships. When interweave is rebuilt from scratch (per F7 finding-aid test), the provenance metadata is lost because connectors don't store it — interweave does. The "deletable without impact" claim fails specifically for the provenance layer.

**Recommendation**: Add to F4 acceptance criteria: "Link provenance metadata is derivable from source subsystem data. The finding-aid test includes rebuilding provenance: after delete + rebuild, link confidence scores must match within 10% of pre-delete values. Any provenance field that cannot be re-derived from source data violates the catalog-of-catalogs contract and must be stored in the source subsystem instead."

### 2. [P1] Connector registration creates implicit coupling (CCP-2)

**File**: `docs/prds/2026-04-05-interweave.md`, F3, lines 49-58

"Connector interface: register, harvest, get_observation_contract"

The connector model requires subsystems to implement this interface. For the 3 first connectors (cass, beads, tldr-code), interweave controls the connectors — they live in the interweave plugin and call out to the subsystems. This is fine.

But the PRD implicitly assumes future connectors follow the same pattern. What about the 57 other interverse plugins? If a plugin wants its entities indexed, does it:
(a) Register with interweave by implementing the connector interface? (coupling: plugin must know about interweave)
(b) Get indexed automatically by interweave scraping its outputs? (decoupling: plugin is unaware)

PHILOSOPHY.md states: "Standalone plugins fail-open without intercore." If option (a), plugins that want ontology visibility must take a dependency on interweave's connector interface. This is the Eclipse plugin ecosystem trap: optional integration becomes de facto mandatory once enough tools depend on it.

**Failure scenario**: Plugin `interwatch` wants its drift scores indexed in the ontology. It implements the connector interface, taking a soft dependency on interweave. Now interwatch's test suite needs interweave running to verify connector behavior. Multiply by 20 plugins. The "optional" integration becomes a maintenance burden across the ecosystem.

**Recommendation**: Specify in F3 that connectors are ALWAYS interweave-internal: "Connectors are implemented inside the interweave plugin and harvest data from subsystems without requiring subsystem modification. Subsystems need not know about interweave. If a subsystem exposes no harvestable data, interweave indexes what it can observe externally (file system, git history, CLI output)." This preserves fail-open independence. Subsystems that want richer indexing can publish structured metadata (a file, a JSON endpoint), but this is a convention, not an interface dependency.

### 3. [P2] 5 fixed type families risk premature abstraction (CCP-3)

**File**: `docs/prds/2026-04-05-interweave.md`, F1, lines 19-21

The 5 families (Artifact, Process, Actor, Relationship, Evidence) are declared before any real agent query patterns are observed. PHILOSOPHY.md warns: "premature stability commitments freeze wrong abstractions."

How were these 5 families chosen? The PRD doesn't say. If they were derived from the existing subsystems (beads=Process, cass=Process, code=Artifact, agents=Actor, interspect=Evidence), then they mirror current implementation rather than actual usage patterns.

The Kubernetes API group evolution is instructive: v1 shipped with 5 resource categories, and by v1.25 had 9 — but 3 of the original 5 were renamed or restructured. The categories that survived were the ones derived from user queries ("show me all pods in namespace X"), not from implementation topology ("pods are compute resources").

**Recommendation**: Reframe F1 to ship with a minimal set (3 families: Artifact, Process, Actor) and make family addition a first-class operation. Evidence and Relationship can be added in v0.2 after observing actual agent query patterns. Add to F1: "Family set is provisional. After 100 agent queries, review whether the family decomposition matches actual query patterns. Families with <5% query involvement are candidates for merging or removal."

### 4. [P1] "No graph database" non-goal needs explicit rationale (CCP-4)

**File**: `docs/prds/2026-04-05-interweave.md`, Non-goals, line 123

"interweave uses SQLite with adjacency tables, not Neo4j/kuzu/etc. The catalog-of-catalogs pattern doesn't need a graph engine."

This is the right decision but the rationale is too terse. A future contributor will see 6 named queries with traversal semantics, an adjacency table schema, and recursive CTEs — and reasonably ask "wouldn't a graph database be better here?" Without documented rationale, the decision will be re-litigated.

The actual reasons (which the PRD should state):
- SQLite is a zero-dependency runtime (already used by beads, fits the "no new infrastructure" philosophy)
- The query patterns are fixed and bounded — no need for a general graph query language
- Graph databases add operational complexity (process management, memory tuning, backup strategy) for a read-only index
- The catalog-of-catalogs pattern means the index can be rebuilt from scratch in minutes — durability requirements are low

**Recommendation**: Expand the non-goal to include the rationale: "We evaluated kuzu (embedded graph DB), DuckDB (analytical queries), and Neo4j (full graph engine). SQLite wins on: zero new dependencies, simpler backup (single file, copy), lower memory footprint, and alignment with the finding-aid principle (the entire index is deletable and rebuildable). Graph databases add operational complexity that exceeds the benefit for 6 bounded query templates."

### 5. [P2] PHILOSOPHY.md amendment needs to explain the storage/retrieval distinction (CCP-5)

**File**: `docs/prds/2026-04-05-interweave.md`, F8, lines 117-118

"PHILOSOPHY.md: new paragraph under 'Composition Over Capability' explaining catalog-of-catalogs as composition (finding-aid test, no data ownership, no write-through)"

The amendment must address the obvious objection: "Isn't a materialized crosswalk (F2) storage? Isn't link provenance (F4) owned data?"

The distinction is subtle: interweave stores derived metadata that can be regenerated from source systems. It does not store primary data that would be lost if interweave were deleted. This is the finding-aid test. But PHILOSOPHY.md says "unify retrieval, not storage" — and a materialized SQLite index IS storage, even if it's regenerable.

**Recommendation**: The F8 amendment should explicitly state: "interweave stores regenerable projections, not primary data. The distinction between 'storage' (primary, authoritative, loss-is-catastrophic) and 'materialization' (derived, regenerable, loss-is-inconvenient) is the boundary the catalog-of-catalogs principle enforces. The finding-aid test is the operational verification."

### 6. [P1] tree-sitter dependency creates implicit language support boundary (CCP-6)

**File**: `docs/prds/2026-04-05-interweave.md`, Dependencies, line 136

"tree-sitter: AST parsing for function-level identity resolution"

tree-sitter has grammars for ~60 languages, but grammar quality varies significantly. Python, JavaScript, Go, and Rust have mature grammars. Haskell, Elixir, and many domain-specific languages have incomplete grammars. Shell scripts (heavily used in this project — lib-routing.sh, lib-sprint.sh) have a grammar that struggles with complex parameter expansion.

This creates an implicit language support boundary: entities in well-supported languages get function-level resolution; entities in poorly-supported languages get only file-level resolution. The PRD doesn't acknowledge this boundary.

**Failure scenario**: Agent queries `who-touched lib-sprint.sh::bead_claim`. tree-sitter can't reliably parse the function boundary in bash. The crosswalk has no function-level entity for `bead_claim`. The query returns file-level results (everyone who touched lib-sprint.sh), which is too noisy to be useful.

**Recommendation**: Add to F2: "Function-level resolution is language-dependent. Supported languages (with reliable AST extraction): Python, JavaScript/TypeScript, Go, Rust, Java. Unsupported languages fall back to file-level resolution. The connector reports its resolution granularity per language in the observation contract." This sets expectations and makes the limitation explicit rather than a silent degradation.

## Improvements

1. **Add a "dependency weight" metric to track coupling creep.** For each subsystem that interweave indexes, count: (a) how many interweave queries touch that subsystem's data, (b) how many of that subsystem's operations reference interweave. If (b) is ever non-zero, coupling is flowing the wrong direction — the subsystem is depending on interweave, not just being indexed by it.

2. **Consider a "discovery-first" rollout.** Ship F5 with 2 queries (related-work, recent-sessions) before building the full 6-tool surface. Observe agent usage for 2 weeks. The usage patterns will reveal whether the remaining 4 queries are needed, and whether the type family decomposition matches real query needs. This aligns with the "pre-1.0 means no stability guarantees" philosophy.

3. **Make the connector protocol a convention, not an interface.** Instead of a formal `register/harvest/get_observation_contract` interface, define a file convention: any plugin that writes `{plugin_dir}/.interweave/entities.jsonl` gets indexed. interweave scans for these files during harvest. No registration, no interface dependency, no coupling. Plugins that want to be indexed write a file; plugins that don't, don't. This is the Unix way.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 6 (P0: 0, P1: 4, P2: 2)
SUMMARY: The catalog-of-catalogs framing correctly navigates the PHILOSOPHY.md tension, but the connector model risks coupling plugins to interweave, and link provenance (F4) may violate the "no owned data" claim if it can't be re-derived from source subsystems.
---
<!-- flux-drive:complete -->
