---
artifact_type: review-synthesis
method: flux-review
target: "docs/prds/2026-04-05-interweave.md"
target_description: "interweave PRD — generative ontology graph for agentic platforms"
tracks: 4
track_a_agents: [fd-ontology-schema-evolution, fd-entity-resolution-identity, fd-graph-query-runtime, fd-agent-ontology-runtime, fd-composition-coupling-philosophy]
track_b_agents: [fd-archival-provenance-linkage, fd-clinical-terminology-harmonization, fd-spatial-data-infrastructure, fd-litigation-entity-mapping]
track_c_agents: [fd-persian-qanat-subterranean-topology, fd-javanese-gamelan-ensemble-tuning, fd-heraldic-blazon-compositional-grammar, fd-polynesian-wayfinding-star-path]
track_d_agents: [fd-dogon-po-tolo-seed-classification, fd-petrographic-thin-section-entity-resolution, fd-burmese-bedin-planetary-relational-calculus]
date: 2026-04-05
---

# Flux-Review Synthesis: interweave PRD

**Target:** `docs/prds/2026-04-05-interweave.md`
**Method:** 4-track flux-review (adjacent, orthogonal, distant, esoteric) with 16 agents
**Date:** 2026-04-05
**Verdict:** needs-changes (all 16 agents concur; architecture sound, specification incomplete)

## Critical Findings (P0/P1)

### P0: Body similarity threshold too low for identity linking

**Source:** ERI-3 (Track A, entity-resolution-identity)
**Location:** F2, line 40

The 80% body similarity threshold for function rename detection will produce false positives at scale. In a 60+ plugin codebase, boilerplate functions, generated code, and copy-paste-modify patterns routinely exceed 80% similarity while being intentionally distinct. The LEI (Legal Entity Identifier) system experienced 3% false merge rates from comparable thresholds. At interweave's scale, even 1% produces dozens of phantom identity links. Agents would make decisions based on wrong cross-system context.

**Fix:** Raise auto-link threshold to >95% for `confidence: confirmed`. Links in 80-95% range classified as `confidence: probable`, excluded from default queries per F4. Body similarity alone never earns `confirmed` status.

### P1 findings by cross-track convergence strength

The 37 P1 findings cluster into 7 themes. Findings that emerged independently across multiple tracks carry the highest signal.

**1. Rule matrix unspecified / type system underspecified** (11/16 agents across all 4 tracks)

The PRD declares 5 families and 7 interaction rules but never shows the family-pair matrix that makes the system generative. This is the single most-cited gap. Track A agents (OSE-5, CCP-3) flagged the missing matrix and premature abstraction. Track C agents (BLAZON-1, GAMELAN-4, QANAT implicitly) flagged that rules form a catalog, not a compositional grammar. Track D agents (Dogon Finding 1, Bedin Finding 1) flagged that the generative property is claimed but not verifiable from the acceptance criteria.

**Fix:** Add the 5x5 family-pair interaction matrix as an appendix. Add a "growth test" acceptance criterion: adding a new entity type to any family requires zero changes to interaction rules. Consider defining relationship primitives (create, consume, transform, observe, govern, annotate) from which the 7 named rules are compositions.

**2. No lifecycle transitions for entities gaining family membership** (4 agents, Tracks C+D)

Multi-family membership is specified but only as static declaration at creation time. GAMELAN-1 (source-specific semantics lost), BLAZON-6 (source roles), Bedin Finding 2 (Ketu lifecycle transitions), and Dogon Finding 2 (twin-seed temporal aspect) all converge: entities that start as Actor-only must be able to gain Process and Evidence membership through lifecycle events (bead linking, reflection, deployment). Without this, multi-family membership is a design-time convenience, not a runtime behavior.

**Fix:** Add lifecycle transition specification to F1: entities can gain family memberships via declared lifecycle events. The relational calculus immediately applies to the expanded family set.

**3. causal-chain query has unbounded fan-out and unrealistic token cost** (5 agents, Tracks A+C)

The 3-hop causal-chain query's "max 20" limit applies only to final results. Intermediate hops expand all matching nodes. GQR-5 (graph explosion), GQR-1 (token cost >500 for 20 results at 3 hops), GQR-3 (no performance contract), QANAT-2 (traversal crosses observation boundaries of unknown depth), and BLAZON-2 (templates not composable, forcing manual multi-query) all target this feature.

**Fix:** Add beam-search limit of K=50 per intermediate hop. Split token cost target: <500 for 1-hop queries, <800 for causal-chain. Add `max_confidence_hop` constraint so traversal flags or stops when crossing from confirmed to speculative links. Add latency contract: all queries <200ms at 100K entities / 500K links.

**4. Connector model risks coupling and lacks observation depth** (6 agents, Tracks A+B+C)

CCP-2 (connector registration creates implicit dependency), QANAT-1 (observation contract declares existence but not depth), SDI Finding 1 (minimum 4-field threshold contradicts "zero effort"), Clinical Finding 3 (closed relationship set), and Archival Finding 1 (flat graph with no hierarchy) all target F3.

**Fix:** Specify that connectors are always interweave-internal (subsystems need not know about interweave). Add `observation_depth` per entity type to observation contracts. Reduce minimum discovery threshold to 2 fields (entity_id, subsystem) with auto-inference for the rest. Add `relationship_types` to the observation contract.

**5. No concrete capability delta over existing tools / bootstrap problem** (3 agents, Track A)

AOR-1 (no before/after scenarios proving interweave beats cass+beads+grep), AOR-2 (agents must learn 6 new MCP tools to use the system), and AOR-3 (6 tools impose 300-600 tokens of permanent context overhead) challenge the core value proposition.

**Fix:** Add a "Scenarios" section to the PRD with 3 concrete before/after examples including token counts and information gaps. Consolidate from 6 MCP tools to 2-3 (a composite `context-for` tool, `causal-chain`, and `evidence-for`). Include explicit capability-delta guidance in tool descriptions.

**6. Finding-aid test necessary but insufficient** (5 agents, Tracks A+B+D)

AOR-4 (no behavioral fallback test), CCP-1 (F4 provenance may be owned data that cannot be re-derived), Archival P1-2 (crosswalk identity chain history destroyed by rebuild), QANAT-5 (visibility gap during audit), and Petrographic Finding 2 (grain-boundary entities use post-hoc dedup) all expand what "finding-aid test" must mean.

**Fix:** Split F7 into three test levels: (a) structural audit (delete index, verify subsystems), (b) provenance regeneration (rebuild link confidence within 10% of pre-delete), (c) behavioral fallback (agents complete queries via direct subsystem access when interweave is down). Preserve identity chain history across audits.

**7. Person-entity resolution absent** (1 agent, Track B, but structurally critical)

Litigation Finding 1: the PRD resolves artifact identity (files, functions) but has no mechanism to unify developer identity across subsystems. The same person appears as a GitHub username, a session ID, a beads `claimed_by` value, and a PR reviewer name. The `who-touched` query returns 4 entities for one human.

**Fix:** Add an Actor identity table to F2 with `(subsystem, actor_id, canonical_person_id, confidence, method)`. The canonical person ID can be git email (most universal developer identifier).

## Cross-Track Convergence

The deepest signal emerges when agents from different semantic distances independently flag the same structural gap. Five convergence points span 3+ tracks:

### Convergence 1: Rules are catalog, not grammar (Tracks A, C, D)

Track A calls it "unspecified rule matrix" (OSE-5). Track C calls it "catalog, not compositional grammar" (BLAZON-1, GAMELAN-4). Track D calls it "generative property claimed but not verified" (Dogon, Bedin). Three different framings of the same gap: the 7 interaction rules are named as opaque atoms, not defined as either (a) a family-pair lookup table or (b) compositions from relationship primitives. The PRD's central architectural claim -- "relational calculus engine" -- is an aspiration unless constrained by specification.

**Resolution:** The family-pair matrix is the minimum viable specification. Track C's composition-from-primitives proposal is stronger but can wait for v0.2.

### Convergence 2: Observation quality undeclared (Tracks A, B, C)

Track A calls it "tree-sitter language boundary" (CCP-6, ERI-2). Track B calls it "connector coverage metadata missing" (SDI Finding 2) and "harvest freshness undetectable" (SDI Finding 4). Track C calls it "observation depth ambiguity" (QANAT-1) and "reconstruction insufficiency" (BLAZON-3, BLAZON-4). The PRD specifies what connectors observe but never how deeply, how reliably, or how completely. An agent receiving query results cannot assess whether the absence of data means "nothing there" or "not yet indexed."

**Resolution:** Add observation_depth, coverage_estimate, and per-connector freshness metadata to query results. Distinguish "no data" from "source unavailable" from "not yet indexed."

### Convergence 3: Context-sensitivity is sort-only (Tracks A, C)

Track A calls it "agents must self-classify their task" (AOR-5). Track C calls it "ordering not projection" (GAMELAN-2), "etak not operationalized" (STARPATH-4), and the general "context-sensitivity gap" theme across all 4 Track C agents. F6 acknowledges that query context matters but operationalizes it only as result ordering. A debugging context should surface different entity properties (diff stats, test results) than a planning context (bead associations, sprint membership). Same data, different modal meaning.

**Resolution:** Extend F6 to include per-context property projection alongside ordering. Add a context projection matrix to documentation.

### Convergence 4: Type system rigidity vs. ecosystem growth (Tracks A, B, D)

Track A calls it "premature abstraction" (CCP-3) and "5 families risk freezing wrong abstractions." Track B calls it "closed relationship set" (Clinical Finding 3), "no formality gradient" (Clinical Finding 2), "no bottom-up extension" (SDI Finding 5). Track D calls it "connector observation contracts cover entities but not relationship types" (Dogon Finding 4). The type system was designed top-down from today's 3 subsystems. When connector count reaches 10+, the 5 fixed families and 7 fixed rules become a bottleneck.

**Resolution:** Make interaction rules extensible via `{namespace}:{rule-name}` registration. Add binding strength (required/extensible/example) to family diagnostic properties. Ship with 3-5 families and expand based on observed query patterns.

### Convergence 5: Transitive closure and contradiction unhandled (Tracks A, C)

Track A calls it "transitive identity closure not addressed" (ERI-1). Track C calls it "no contradiction detection" (STARPATH-2). Both point to the same category: the PRD does not specify what happens when evidence from different sources conflicts or compounds. Transitive closure creates false equivalences. Contradiction creates silent resolution by query order. Both degrade agent decision quality over time.

**Resolution:** Add "identity links NOT transitively closed by default" to F2. Add enumerated contradiction patterns (closed-but-active, deleted-but-referenced) to F4 with explicit cross-source conflict markers.

## Domain-Expert Insights (Track A)

Track A's 5 agents reviewed the PRD from adjacent technical disciplines. Aggregate: 1 P0, 16 P1, 10 P2 across 27 findings. Heat map:

| Feature | P0 | P1 | P2 |
|---------|----|----|-----|
| F1: Type Family System | 0 | 3 | 2 |
| F2: Identity Crosswalk | 1 | 3 | 1 |
| F3: Connector Protocol | 0 | 1 | 2 |
| F4: Confidence Scoring | 0 | 1 | 1 |
| F5: Named Query Templates | 0 | 4 | 2 |
| F6: Query-Context Salience | 0 | 0 | 1 |
| F7: Gravity-Well Safeguards | 0 | 1 | 0 |
| Non-goals / Open Questions | 0 | 3 | 0 |

Key insight unique to Track A: **the PRD needs before/after scenarios** (AOR-1). Without concrete proof that interweave queries save material tokens over cass+beads+grep, the system risks being architecturally elegant and operationally ignored. The "~800 tokens for manual multi-tool queries" claim in the problem statement is unsubstantiated.

Track A also provided the strongest single-agent contribution from fd-entity-resolution-identity, whose 6 findings (including the only P0) demonstrate deep expertise in the crosswalk's failure modes: transitive closure, tree-sitter language brittleness, granularity mismatch, and entity input parsing.

## Parallel-Discipline Insights (Track B)

Track B's 4 agents reviewed through professional-practice lenses where catalog-of-catalogs patterns have decades of operational history. Aggregate: 0 P0, 9 P1, 8 P2, 4 P3 across 21 findings.

Three themes dominated:

**Type system rigidity.** Clinical terminology (3 P1s) provided the strongest structural critique: the type system lacks post-coordination for compound queries, a formality gradient across families, and extensible relationship types. These are patterns clinical informatics solved decades ago. The fix (binding strengths, namespace-extensible rules, path query composition) converts the type system from "designed for today" to "designed for growth."

**Person-entity resolution absent.** Litigation mapping (P1) flagged the complete omission of developer identity unification -- the most universal entity type in any development platform. The PRD resolves files and functions but not the humans who touch them.

**Bootstrap friction.** Three agents (SDI, Litigation, Archival) independently identified adoption-blocking friction: the minimum discovery threshold requires custom connector code (contradicting "zero effort"), the harvest model assumes comprehensive indexing before useful queries, and TTL treats all entity types identically (wrong for both ephemeral sessions and stable plugins). The iterative enrichment model -- broad (fast, metadata-only) then deep (slow, on-demand) -- is the professional consensus on avoiding bootstrap-period abandonment.

## Structural Insights (Track C)

Track C's 4 far-field agents reviewed through compositional and navigational lenses. Aggregate: 0 P0, 8 P1 across 3 themes plus 11 P2.

**Theme 1: Compositionality gap.** The type family system achieves composability at the family level but not at the rule level or query level. Families compose; rules and queries enumerate. The heraldic blazon agent provided the sharpest formulation: you have a composable field system (families) but a non-composable charge catalog (rules and queries). Future relationship patterns require new charges, and each new charge is a grammar extension. The recommended fix -- relationship primitives with composition operators -- transforms the rule system from catalog to grammar.

**Theme 2: Observation depth ambiguity.** The qanat, blazon, and starpath agents all flagged the same gap from different angles. The connector observation contract specifies what is observed but not how deeply or how reliably. The qanat agent calls this "shaft density" (a shaft shows water level but not flow direction). The blazon agent calls it "reconstruction sufficiency" (an entity record is a reference, not a description). The starpath agent calls it "signal reliability" (no way to know which queries to trust under which conditions). All three converge on: query results need per-source depth, coverage, and freshness metadata.

**Theme 3: Context-sensitivity gap.** The gamelan and starpath agents both point to the same missing capability: F6 acknowledges context matters but implements it as sort order. The gamelan agent's "pathet" (modal framework where the same note has different meaning in different modes) and the starpath agent's "etak" (moving reference frame where the canoe is fixed and islands move past) both demand per-context property projection, not just per-context ordering.

Track C also contributed the most actionable single finding: BLAZON-2's observation that the 6 named query templates are not composable, and the most common agent question ("what happened to X recently and why?") requires calling 3+ templates with manual intersection -- exactly the manual multi-tool cost the PRD was designed to eliminate. A composite `context-for <entity>` template would address this.

## Frontier Patterns (Track D)

Track D's 3 agents reviewed the PRD against findings from their prior concept-brief review, checking whether the brainstorm's architectural decisions survived translation to specification. Aggregate: 2 P1, 7 P2, and 5 resolved findings (of 12 original concept-brief findings).

**Concept-brief insight resolution scorecard:**

| Insight | Status | Evidence |
|---------|--------|----------|
| Generative type families (bummo/bedin relational calculus) | Architecture present, specification incomplete | F1 has the right structure but acceptance criteria do not test the generative property |
| Multi-family membership (twin-seed pattern) | Fully addressed | F1 line 29 explicitly supports it |
| Identity crosswalk (extinction angle / Michel-Levy chart) | Fully addressed | F2 has materialized index, O(1) lookup, incremental updates |
| Unclassified entity handling (fonio question) | Fully addressed | F1 line 30, conservative approach (visible but inert) |
| Pleochroism (entity changes type across views) | Fully addressed | Multi-family membership resolves this |
| Finding-aid audit as safety valve | Fully addressed | F7 staleness TTL + destructive rebuild |
| Lifecycle transitions (Ketu pattern) | NOT addressed | Multi-family is static; no mechanism for entities to gain families over time |
| Deterministic type assignment from identifiers | NOT addressed | PRD relies on connector-based assignment only |
| Runtime relationship overrides (Nat overlay) | Partially addressed | Confidence scoring approximates but lacks explicit override/expiration semantics |
| Schema drift detection (redundant embedding) | Partially addressed | Connector contracts cover entity properties but not relationship types |
| Per-entity diagnostic property table | Partially addressed | "Diagnostic properties" named per-family but not per-entity-type |
| Grain-boundary entity resolution | Partially addressed | Post-hoc dedup rather than ingest-time resolution |

The 2 P1 findings are:

1. **Generative property claimed but not verified** (Dogon + Bedin convergence). The acceptance criteria do not distinguish a genuine relational calculus from a taxonomy wearing a generative label. A developer could satisfy all stated criteria while building O(type-pairs) rules instead of O(family-pairs). Fix: add the family-pair matrix and a growth test.

2. **Ketu lifecycle transitions unspecified** (Bedin Finding 2). Entities gaining family membership through lifecycle events (session becomes evidence after reflection) is the single most important gap between concept-brief synthesis and PRD. The architecture supports it; the specification does not require it.

Track D's overall assessment: the PRD absorbed the three core insights (generative calculus, multi-family membership, materialized identity index) and built them into a sound architecture. The transformation from concept brief to PRD is strong. The remaining gaps are specification-level -- additive acceptance criteria, not architectural changes.

## Synthesis Assessment

### Architecture vs. Specification

The PRD's architecture is sound across all 16 agents' evaluations. No agent recommends a fundamentally different approach. The catalog-of-catalogs pattern, the finding-aid test, the no-write-through constraint, the named query templates with bounded traversal, and the generative type family system are all correct architectural decisions.

The gaps are specification-level: acceptance criteria that are too loose to guarantee the architecture survives implementation. The rule matrix, lifecycle transitions, observation depth, and capability delta are all cases where the PRD states the right intention but does not constrain the implementation enough to prevent drift.

### What the PRD got right

1. **F2 (Identity Crosswalk) is implementation-ready.** All tracks recognize F2 as the strongest feature. Materialized index, O(1) lookup, incremental updates, and identity chains are well-specified.

2. **F7 (Gravity-Well Safeguards) addresses the right risks.** No-write-through, staleness TTL, and the finding-aid audit are structural protections that no agent disputes. The gaps are in scope (behavioral fallback, provenance regeneration) not in concept.

3. **The catalog-of-catalogs framing correctly navigates PHILOSOPHY.md.** The tension between "unify retrieval, not storage" and a materialized cross-system index is resolved through the "regenerable projections, not primary data" distinction. Track A's composition-coupling agent validated this.

4. **Non-goals are well-calibrated.** All 5 non-goals (no graph database, no open-ended traversal, no real-time streaming, no cross-platform packaging, no replacing existing tools) are correct for v0.1 and prevent scope creep.

5. **Multi-family membership resolves multiple concept-brief findings.** The twin-seed, pleochroism, and partial-observation findings from the concept-brief review are all addressed by a single design decision.

### What must change before implementation

Ranked by cross-track convergence strength:

| Priority | Change | Tracks | Agents |
|----------|--------|--------|--------|
| 1 | Add family-pair interaction matrix to F1 | A, C, D | 11 |
| 2 | Add lifecycle transition specification to F1 | C, D | 4 |
| 3 | Add beam-search limits and latency contract to F5 causal-chain | A, C | 5 |
| 4 | Raise body similarity threshold to >95% for confirmed links | A | 1 (P0) |
| 5 | Specify connectors as interweave-internal; add observation depth | A, B, C | 6 |
| 6 | Add before/after scenarios proving capability delta | A | 3 |
| 7 | Expand finding-aid test to 3 levels (structural, provenance, behavioral) | A, B, D | 5 |
| 8 | Add person-entity resolution to F2 | B | 1 |
| 9 | Add per-context property projection to F6 | A, C | 3 |
| 10 | Make interaction rules extensible via namespace registration | B | 3 |

### Concrete acceptance criteria to add

**F1 additions:**
- Family-pair interaction matrix (appendix or linked document) showing which rule governs each (family_a, family_b) pair
- Growth test: adding a new entity type to any family requires zero rule changes
- Lifecycle transitions: entities can gain family memberships via lifecycle events; transition rules declared per entity type
- Multi-family resolution strategy: union (return all valid relationship types from all memberships)
- Compositionality test: express "delegation" using existing primitives without adding rule #8

**F2 additions:**
- Identity links NOT transitively closed by default
- Body similarity >80% classified as `probable` (not `confirmed`); >95% for automatic confirmed linking
- Actor identity table for person-entity resolution
- Per-entity-type diagnostic property table (identity anchors)
- Supported languages for function-level resolution declared; unsupported fall back to file-level

**F3 additions:**
- Connectors are interweave-internal; subsystems need not know about interweave
- Observation depth per entity type in observation contract
- Relationship types in observation contract
- Adding a new connector does not change existing query results unless template explicitly updated
- Coverage metadata per connector (indexed_since, coverage_estimate)

**F4 additions:**
- Cross-source contradiction detection with enumerated patterns (closed-but-active, deleted-but-referenced)
- Temporal validity (valid_from/valid_until) on links
- Per-query minimum confidence floor for traversal edges (high-stakes queries require confirmed/probable)

**F5 additions:**
- Before/after scenarios section (3 examples with token counts)
- Beam-search limit K=50 per intermediate hop for causal-chain
- Split token cost: <500 for 1-hop, <800 for 3-hop
- Latency contract: <200ms at 100K entities / 500K links
- Per-connector coverage and freshness metadata in results
- Graceful degradation expanded to 3 testable criteria (per-source status, 2s timeout, no-data vs unavailable)
- Composite `context-for <entity>` template combining related-work + recent-sessions + who-touched

**F6 additions:**
- Per-context property projection (debugging surfaces diff stats; planning surfaces bead associations)

**F7 additions:**
- Three-level finding-aid test: structural, provenance regeneration, behavioral fallback
- Identity chain history preserved across audits
- Per-type-family TTL configuration
- Unclassified entity percentage health metric (alert at >30%)

### Open questions resolved by the review

**OQ3 (Entity input parsing):** Composite canonical IDs using `{subsystem}:{native_id}` format. The subsystem prefix routes to the right connector; the native ID is already familiar. Promoted from open question to F2 acceptance criterion.

**OQ4 (Index size management):** Per-type-family TTLs (Process entities get short TTL with archive-to-cold-storage; Artifact entities get long TTL or refresh-on-query) combined with broad/deep harvest modes (broad metadata always retained; deep metadata expires per TTL).

### Missing open question

**Cold-start experience:** When interweave is first installed, how long until queries return useful results? The iterative enrichment model (broad harvest in minutes, deep harvest on-demand) addresses this but should be an explicit open question and acceptance criterion for F3.
