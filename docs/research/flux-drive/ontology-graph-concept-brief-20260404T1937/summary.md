## Flux Drive Review — ontology-graph-concept-brief

**Reviewed**: 2026-04-04 | **Agents**: 8 launched, 8 completed (2 rounds) | **Verdict**: risky

### Review Rounds

- **Round 1** (auto-triaged): fd-archival-provenance-linkage, fd-clinical-terminology-harmonization, fd-spatial-data-infrastructure, fd-litigation-entity-mapping
- **Round 2** (user-directed far-field): fd-persian-qanat-subterranean-topology, fd-javanese-gamelan-ensemble-tuning, fd-heraldic-blazon-compositional-grammar, fd-polynesian-wayfinding-star-path

### Verdict Summary

| Agent | Status | Round | Summary |
|-------|--------|-------|---------|
| fd-archival-provenance-linkage | needs-changes | 1 | 3 P1 + 3 P2: Flat topology loses hierarchical context; authority control conflated with entity resolution |
| fd-clinical-terminology-harmonization | needs-changes | 1 | 3 P1 + 3 P2: Pre-coordination explosion; no formality gradient; no freshness metadata |
| fd-spatial-data-infrastructure | needs-changes | 1 | 3 P1 + 3 P2: Catalog-vs-warehouse undecided; no minimum metadata threshold; entity ID problem |
| fd-litigation-entity-mapping | risky | 1 | 1 P0 + 3 P1 + 2 P2: No provenance on entity links (P0); no proportionality analysis |
| fd-persian-qanat-subterranean-topology | needs-changes | 2 | 3 P1 + 2 P2: Observation depth unspecified; false negatives indistinguishable from absence |
| fd-javanese-gamelan-ensemble-tuning | needs-changes | 2 | 2 P1 + 3 P2: Normalization destroys source-specific semantics; no query-context mechanism |
| fd-heraldic-blazon-compositional-grammar | needs-changes | 2 | 3 P1 + 2 P2: Schema is catalog not grammar; untyped relationships; referential not reconstructive |
| fd-polynesian-wayfinding-star-path | needs-changes | 2 | 3 P1 + 2 P2: No graceful degradation; no contradiction resolution; no path reliability metadata |

### Critical Findings (P0)

1. **LEM-1: Cross-system entity links lack provenance metadata** (Round 1, fd-litigation-entity-mapping). The ontology graph proposes connecting entities across subsystems without any mechanism for recording why a link was created, what evidence supports it, or what confidence level was assigned. A false link (e.g., temporal co-occurrence mistaken for causal relationship) propagates through the dispatch system, causing incorrect routing decisions with no audit trail. **Cross-round convergence**: Round 2's qanat agent (QAN-3) independently identified the same structural gap from the causation-vs-correlation angle -- "the brief does not distinguish between causal edges and correlative edges."

### Important Findings (P1) -- Cross-Round Synthesis

22 P1 findings across 8 agents cluster into 7 convergence themes. Themes with cross-round convergence (same structural insight surfaced by agents from different knowledge domains across different rounds) are the highest-confidence findings.

**Theme 1: Observation/indexing depth unspecified (5/8 agents -- CROSS-ROUND)**

Round 1: SDI-2 (minimum metadata threshold), CTH-3 (no freshness metadata), APL-5 (implicit storage migration). Round 2: QAN-1 (observation depth unspecified), BLZ-3 (referential not reconstructive entity definitions). Five agents from five unrelated disciplines independently identified the same gap: the brief says "connect to sessions" but never says "index session metadata, tool call sequences, and file-level diffs, refreshed within N minutes of session completion." The ontology's value depends entirely on the depth and freshness of its observation into each source system.

**Theme 2: Entity normalization flattens meaningful differences (4/8 agents -- CROSS-ROUND)**

Round 1: CTH-1 (pre-coordination explosion), APL-1 (type system composition). Round 2: GAM-1 (ombak destroyed by normalization), BLZ-1 (catalog not grammar). A commit as git-object, beads-state-change, and session-output carries structurally different information in each system. Clinical informatics solved this with post-coordination (compose types at query time from atomic components). Heraldic blazon solved it with compositional grammar (5 primitives, not 30+ bespoke types). Gamelan tuning solved it by preserving intentional differences between instruments.

**Theme 3: Source failure and contradiction unaddressed (4/8 agents -- CROSS-ROUND)**

Round 1: CTH-3 (no freshness metadata), SDI-4 ("not indexed yet" vs "does not exist"). Round 2: QAN-2 (false negatives indistinguishable from absence), NAV-1 (queries block on slowest source), NAV-2 (contradictions silently resolved by query order). When the Dolt server crashes, does the query return partial results with availability markers, or does it block? When beads says "closed" but sessions show active work, is the contradiction surfaced or silently resolved by whichever source responds first?

**Theme 4: Entity identity resolution is a first-class problem (3/8 agents -- CROSS-ROUND)**

Round 1: APL-2 (authority control conflated with entity resolution), LEM-3 (person-entity dedup absent), SDI-3 (identifier harmonization). Round 2: GAM-5 (multi-typed entity representation absent). The same developer appears as a GitHub username, a session UUID, and a beads claimed_by string. The same file appears as a git path, an AST node, a beads artifact, and a session touched-file. Entity identity resolution must precede relationship traversal.

**Theme 5: Query context and salience absent (2/8 agents -- ROUND 2)**

Round 2: GAM-2 (no pathet/modal framework), NAV-5 (query reference frame unspecified). "Show me everything related to X" should return different salience orderings for debugging vs planning vs reviewing. This finding is unique to Round 2 -- Round 1 agents focused on structural concerns, while Round 2's distant-domain analogies revealed the runtime query experience gap.

**Theme 6: No traversal path reliability metadata (2/8 agents -- CROSS-ROUND)**

Round 1: LEM-1 (provenance on links). Round 2: NAV-3 (no path reliability metadata), QAN-3 (correlation mistaken for causation). Not all traversal paths are equally trustworthy. git commit -> file is high confidence. session -> file (inferred from tool calls) is medium confidence. The schema and API must surface this meta-information.

**Theme 7: Progressive adoption vs all-or-nothing (3/8 agents -- CROSS-ROUND)**

Round 1: LEM-4 (no iterative enrichment), SDI-6 (progressive value delivery). Round 2: QAN improvement #2 (progressive observation deepening: v1 existence, v2 operations, v3 causality). Both rounds independently recommend starting with coarse stubs and deepening on demand, rather than attempting comprehensive indexing as a prerequisite.

### Improvements Suggested (Merged, Prioritized)

1. **Connector observation contracts** (qanat + SDI + clinical). For each source system: entity types indexed, granularity, captured vs inferred properties, refresh cadence, known gaps. This is the single highest-leverage addition to the concept brief. *5/8 agents touched this.*

2. **Composable type primitives** (blazon + clinical + archival). Replace 30+ bespoke entity types with ~5 base types (Artifact, Process, Actor, Relationship, Evidence). Apply the grammar compositionality test before finalizing schema. *4/8 agents.*

3. **Catalog-of-catalogs, not data warehouse** (SDI + archival + litigation). The ontology indexes metadata about entities in subsystem stores and returns pointers to authoritative data. It never owns entity data. If deleting the ontology leaves every subsystem fully functional, the design is correct. *3/8 agents.*

4. **Context-dependent query salience** (gamelan + wayfinding). Add a query-context parameter (debug/plan/review/audit/explore) that adjusts relationship salience without changing relationship existence. *2/8 agents, unique to Round 2.*

5. **Progressive partial query results** (wayfinding + clinical + SDI). Design query execution as parallel fan-out with immediate partial results and explicit source-availability markers. *3/8 agents across rounds.*

6. **Source reliability hierarchy** (wayfinding + litigation). Per-source trust rankings, calibrated from observed contradiction resolutions. Annotate traversal paths with inherited reliability. *2/8 agents across rounds.*

7. **Entity identity resolution as a distinct layer** (archival + litigation + SDI + gamelan). Separate authority control (canonical records), entity resolution (matching references), and person-entity dedup into three distinct operations with different architectures. *4/8 agents.*

8. **Provenance on every cross-system link** (litigation). Record why each link was created, what evidence supports it, and what confidence level was assigned. The P0 finding. *1/8 agents but P0 severity.*

### Section Heat Map

| Section | Issues (R1+R2) | Improvements | Agents Reporting |
|---------|---------------|-------------|-----------------|
| Three Concrete Capabilities | P0: 1, P1: 10, P2: 2 | 5 | all 8 agents |
| Design Tensions | P1: 2, P2: 5 | 2 | qanat, gamelan, clinical, SDI, litigation |
| What Already Exists | P1: 1, P2: 4 | 2 | qanat, gamelan, archival, SDI |
| Open Questions | P1: 2, P2: 2 | 3 | wayfinding, litigation, archival |
| Agentic Development Context | P1: 2 | 2 | blazon, litigation |
| Palantir Model | P1: 2 | 1 | blazon, clinical |

### Conflicts

No conflicts detected across either round. All 8 agents from 8 unrelated knowledge domains converge on the same fundamental recommendation: the ontology must be a metadata catalog (not a data warehouse), with provenance on every link, compositional types (not exhaustive schemas), progressive adoption (not all-or-nothing), and explicit handling of source failure and contradiction.

### Cross-Domain Structural Isomorphisms

The deepest insight from this review is that 8 professional disciplines -- each with centuries of independent evolution -- converge on structurally identical solutions for the same class of problem:

| Ontology Design Problem | Round 1 Analogs | Round 2 Analogs | Converged Pattern |
|------------------------|----------------|----------------|-------------------|
| What does each connector index? | SDI minimum metadata threshold; Clinical freshness metadata | Qanat observation shaft depth; Blazon reconstruction sufficiency | Observation contracts: declare depth, granularity, freshness per source |
| How to unify without normalizing? | Clinical post-coordination; Archival multi-level description | Gamelan ombak (intentional detuning); Blazon composable primitives | Compositional types: atomic building blocks assembled at query time |
| What happens when a source fails? | Clinical binding strength; SDI data currency | Wayfinding graceful degradation; Qanat dry shaft diagnosis | Progressive partial results with source-availability markers |
| How to handle contradictions? | Litigation confidence scoring | Wayfinding signal contradiction resolution | Surface contradictions with source attribution; configurable trust hierarchy |
| Will the schema scale? | Clinical pre-coordination explosion | Blazon grammar vs catalog test | Grammar compositionality: future types from existing primitives |
| Same entity, multiple systems? | Archival authority files; Litigation person-entity dedup | Gamelan slendro/pelog coexistence; Blazon marshalling | Multi-faceted entities with source-specific type information |
| Which traversal paths to trust? | Litigation provenance on links | Wayfinding star paths; Qanat causal vs correlative edges | Path reliability metadata + pre-computed reliable routes |

### Individual Agent Reports

**Round 1 (auto-triaged):**
- [fd-archival-provenance-linkage](./fd-archival-provenance-linkage.md) -- needs-changes: 3 P1, 3 P2
- [fd-clinical-terminology-harmonization](./fd-clinical-terminology-harmonization.md) -- needs-changes: 3 P1, 3 P2
- [fd-spatial-data-infrastructure](./fd-spatial-data-infrastructure.md) -- needs-changes: 3 P1, 3 P2
- [fd-litigation-entity-mapping](./fd-litigation-entity-mapping.md) -- risky: 1 P0, 3 P1, 2 P2

**Round 2 (user-directed far-field):**
- [fd-persian-qanat-subterranean-topology](./fd-persian-qanat-subterranean-topology.md) -- needs-changes: 3 P1, 2 P2
- [fd-javanese-gamelan-ensemble-tuning](./fd-javanese-gamelan-ensemble-tuning.md) -- needs-changes: 2 P1, 3 P2
- [fd-heraldic-blazon-compositional-grammar](./fd-heraldic-blazon-compositional-grammar.md) -- needs-changes: 3 P1, 2 P2
- [fd-polynesian-wayfinding-star-path](./fd-polynesian-wayfinding-star-path.md) -- needs-changes: 3 P1, 2 P2

### Files

- Summary: `docs/research/flux-drive/ontology-graph-concept-brief-20260404T1937/summary.md`
- Findings: `docs/research/flux-drive/ontology-graph-concept-brief-20260404T1937/findings.json`
- Individual reports: `docs/research/flux-drive/ontology-graph-concept-brief-20260404T1937/fd-*.md`
