# Open-Source Ontology & Property-Graph Stores Assessment

**Date:** 2026-04-21  
**Scope:** Object-first ontology database for unified Sylveste knowledge integration  
**Context:** Unifying 660 fd-* subagent markdown files, 291 Auraken lenses (Postgres-backed), 288 interlens FLUX lenses  
**Target:** Palantir Foundry-style unified persona+lens database with typed entities, typed relationships-as-first-class-objects, bi-temporal versioning, and three view projections

---

## Summary Table

| Candidate | License | Schema-First | Typed Rels | Bi-Temporal | Postgres Path | Verdict | Rationale |
|-----------|---------|--------------|-----------|-------------|---------------|---------|-----------|
| **Apache AGE** | Apache 2.0 | Yes | Yes | Manual | Native Extension | **Adopt** | Lives in Postgres, minimal ops overhead, Cypher standard, schema-first discipline, typed edges with properties. Missing native bi-temporal; manageable via custom logic. |
| **TerminusDB** | Apache 2.0 | Yes | Yes | Yes (git-like) | None—separate service | **Port-Partially** | Git-for-data versioning elegant; WOQL powerful; schema-first strong. But: separate RDF/JSON service, not Postgres-native. Worth integrating as *auxiliary* versioning layer. |
| **TypeDB** | AGPL 3.0 | Yes | Yes | No | None—separate service | **Inspire-Only** | Excellent typed schema + inference; hypergraph model fits ontology. Dealbreaker: AGPL (restricts commercial), no native bi-temporal, separate JVM service. Use for schema inspiration. |
| **Neo4j Community** | GPLv3 | Schema-on-Read | Yes | Manual | None—separate service | **Skip** | GPLv3 incompatible with commercial licensing intent; Bloom ecosystem requires Enterprise; separate service overhead; manual bi-temporal. |
| **Dgraph** | Apache 2.0 | Flexible | Yes (weak) | No | None—separate service | **Skip** | GraphQL-native but not schema-first by default; strong on distributed scale (not needed); separate service. Better choices exist for monorepo scale. |
| **Memgraph** | BSL 1.1 (→ Apache 2.0) | Schema-on-Read | Yes | No | None—separate service | **Skip** | In-memory + streaming focus (not our use case); BSL licensing uncertainty; separate service overhead. Skip for ontology, revisit for real-time graph analytics. |

---

## Deep-Dive Analysis

### Apache AGE (Apache License 2.0)

**What it is:** PostgreSQL extension (C) providing property-graph engine atop existing Postgres. Queries via openCypher (Neo4j query standard).

**Schema approach:** Schema-first enforced via DDL-style graph schema definitions. Nodes and edges are typed; properties constrained by edge type.

**Typed relationships:** Full support. Edges are first-class with properties, labels, and traversal semantics. Example: `(Person)—[knows {since: 2020}]—>(Person)` is native.

**Bi-temporal:** Not natively supported. Workaround: add `valid_from`, `valid_to`, `tx_time` properties to all edges; query-side logic filters by temporal windows. Doable but manual.

**Postgres integration:** **Zero overhead.** AGE is an extension; no new service, no replication, no operational surface. Uses Postgres's transaction log for MVCC, backup, recovery. You already run Postgres for Auraken (pgvector).

**Language bindings:** Python (psycopg2 + custom Cypher wrapper), JavaScript (pg + custom Cypher), Go (pgx). Not as polished as Neo4j's driver, but functional. Community examples abundant.

**Maturity:** Adopted by Azure Database for PostgreSQL, Postgres Pro Enterprise. Active development 2025–2026. GitHub: 2.8K stars. Not bleeding-edge but stable.

**Dealbreakers:** None major. Bi-temporal is manual but manageable (add timestamp columns, query-time filtering). Schema evolution requires `ALTER` statements (Postgres standard).

**Fit for ontology:** Strong. Schema-first discipline forces clarity. Typed edges with properties enable rich provenance (e.g., relationship edges can carry `confidence`, `source`, `timestamp`). Postgres integration is seamless.

---

### TerminusDB (Apache License 2.0)

**What it is:** Distributed RDF+JSON graph database with git-like branching, diff, merge. Query via WOQL (datalog variant) or GraphQL.

**Schema approach:** Schema-first via JSON-LD ontology definitions. Types enforced; schema evolution via commits.

**Typed relationships:** Yes. Relationships are RDF triples with semantic typing. Properties on relationships via reification or RDF-star extensions.

**Bi-temporal:** Native. Git-like versioning (commits, branches, time-travel queries) is the core design. Query `db.queryAsOf('commit-hash')` to see state at any point. Excellent for audit trails.

**Postgres integration:** None. Separate Prolog-based service. Can integrate via webhooks/polling, but no single unified data layer.

**Language bindings:** Python (terminusdb-client), JavaScript/Node (terminusdb-js). Documentation adequate.

**Maturity:** 2.7K GitHub stars. Active development, but smaller community than Neo4j. Used in semantic data management, compliance.

**Dealbreakers:** Requires separate service (ops overhead). RDF/JSON model, while semantic-rich, adds cognitive load vs. property graphs. WOQL steeper learning curve than Cypher.

**Fit for ontology:** Strong for *versioning and provenance* specifically. If audit trails and time-travel are critical, TerminusDB shines. But as single source-of-truth ontology store, operational overhead is higher than Postgres-native options.

**Recommendation:** Port-partially. Use as *auxiliary* versioning layer: sync key ontology snapshots (Auraken lenses, Hermes persona configs) to TerminusDB for immutable audit trail; query Postgres for live access. Adds 2–3 microservices but decouples evolution tracking.

---

### TypeDB (AGPL 3.0)

**What it is:** Knowledge-engineering database (formerly Grakn) with hypergraph model and logical inference engine. Written in Rust 3.0+.

**Schema approach:** Strongly-typed schema (TypeQL DDL) with entities, relations, attributes as first-class citizens. Subtypes and type hierarchies.

**Typed relationships:** Exceptional. Relations are full objects with properties, roles, and inference rules. Example: `(organisation: Company) ← employee : (person: Employee)` with nested attributes and rules.

**Bi-temporal:** Not natively supported. No versioning layer. Timestamp columns possible but inference rules don't reason over time.

**Postgres integration:** None. Separate JVM/Rust service (distributed).

**Language bindings:** Python (typedb-driver), JavaScript, Java, C++. Well-documented.

**Maturity:** 3.0 release Dec 2024 (full Rust rewrite). Growing adoption in knowledge-graph use cases. 3.2K GitHub stars. Active.

**Dealbreakers:** 
- **AGPL 3.0 license.** If Sylveste or downstream users want commercial-use derivatives without source disclosure, AGPL blocks that. Yellow/red flag depending on business model.
- No bi-temporal support.
- Separate service (ops).

**Fit for ontology:** Excellent for *schema design* and *type inference*. If you're modeling persona + lens relationships with rules (e.g., "lenses applicable to persona X if domain matches"), TypeDB's inference is unmatched. Use as **design inspiration** for Auraken lens schema, not as primary store.

---

### Neo4j Community (GPLv3)

**What it is:** Mature, feature-rich property-graph database with ecosystem (Bloom, GDS, APOC plugins).

**Schema approach:** Schema-on-read (flexible) but can enforce schema via constraints and indexes. Community Edition limited to single-node; High Availability Enterprise-only.

**Typed relationships:** Yes. Edges are labeled and can have properties.

**Bi-temporal:** Not natively. Community examples show custom temporal properties + query logic.

**Postgres integration:** None. Separate service (JVM).

**Language bindings:** Python (neo4j-driver), excellent documentation and examples.

**Maturity:** Highly mature (10+ years). 10K+ GitHub stars. Enterprise backing (Neo4j Inc.).

**Dealbreakers:**
- **GPLv3 license.** Like AGPL, GPLv3 requires source disclosure if you distribute Neo4j derivatives. If Sylveste intends commercial use or library licensing, GPLv3 is a hard constraint.
- High Availability, Bloom ecosystem, APOC plugins often Enterprise-only.
- Single-node limit (Community), making scaling path murky.

**Fit for ontology:** Strong for *queries and visualization* (Bloom is excellent). But licensing and single-node limit make it unsuitable for primary canonical store.

---

### Dgraph (Apache 2.0)

**What it is:** Distributed GraphQL database with graph-native backend. Designed for horizontal scale and real-time workloads.

**Schema approach:** Flexible schema-on-read (mutations create types dynamically), or explicit schema via GraphQL SDL. Not strictly schema-first.

**Typed relationships:** Yes, but edges are less first-class than in TypeDB or AGE. Properties on edges supported via nested queries.

**Bi-temporal:** No native support. Would require custom timestamp logic.

**Postgres integration:** None. Distributed service (Go-based, replicated sharding).

**Language bindings:** Python (pydgraph), JavaScript, Go, Java.

**Maturity:** 4.8K GitHub stars. Acquired by Istari Digital (Oct 2025). Under stewardship but smaller community. Apache 2.0 license.

**Dealbreakers:** Horizontal scale and streaming optimizations are premature for Sylveste's modest scale (1200 entities). Schema-on-read model conflicts with "schema-first ontology" design goal. Separate service overhead.

**Fit for ontology:** Skip. Better suited for large-scale recommendation engines or identity graphs. Overhead unjustified for current scope.

---

### Memgraph (BSL 1.1 → Apache 2.0 conversion pending)

**What it is:** In-memory graph database (C++) with Cypher compatibility, streaming ingestion (Kafka, Pulsar), and GraphRAG integrations.

**Schema approach:** Schema-on-read. Flexible but not schema-first.

**Typed relationships:** Yes, Cypher-style labels and properties.

**Bi-temporal:** No.

**Postgres integration:** None. In-memory, separate service.

**Language bindings:** Python, JavaScript, CLI.

**Maturity:** ~2.5K GitHub stars. Growing (2025 GraphRAG announcements, MCP integration). BSL licensing (Business Source License) converts to Apache 2.0 after 3–4 years; current uncertainty for commercial use.

**Dealbreaker:** In-memory focus (not suitable for persistent ontology store without filesystem sync). BSL licensing complexity. Streaming/real-time optimizations irrelevant for this use case.

**Fit for ontology:** Skip. Revisit for real-time graph analytics (e.g., live persona + lens recommendation engine), not canonical storage.

---

## Recommendation

### Primary Path: **Apache AGE + Postgres**

**Adoption decision:** AGE is the clear winner for Sylveste's unified ontology store.

**Rationale:**
1. **Zero operational overhead.** Runs in your existing Postgres (Auraken infrastructure). No new service, no replication cluster, no JVM overhead.
2. **Schema-first discipline.** Forces clear type definitions for personas, lenses, relationships. Enables validation and inference.
3. **Typed relationships with properties.** Edges can carry provenance (confidence, source, timestamp, audit_user). Handles rich semantics needed for persona-lens cross-referencing.
4. **Postgres native bi-temporal.** Manual but straightforward: add `valid_from`, `valid_to`, `tx_timestamp` to node/edge properties. Query-time filtering is simple and testable.
5. **Language integration.** Python (preferred for Auraken scripts) + Node (interlens MCP) both supported.
6. **Apache 2.0 license.** Commercial-friendly. No source-code disclosure requirements.

**Implementation sketch:**
- Define ontology schema (TypeDB-inspired): Persona entity, Lens entity, Domain (enum), Discipline (enum), Source entity, Evidence entity, Bridge relationship.
- Encode 291 Auraken lenses as Lens nodes + Bridge edges (b/t lenses). Properties: `effectiveness_score`, `community_id`, `tier`, `source_url`, `ingested_at`, `last_updated_by`.
- Encode 660 fd-* markdown files as Persona nodes + HasContext edges (b/t Persona and Lens). Properties: `task`, `review_questions`, `confidence`, `fd_file_path`, `ingested_at`.
- Encode interlens FLUX lenses as second Lens flavor (FLUX-tier attribute), disambiguate via community_id.
- Bi-temporal: add system-time (audit), valid-time (when lens was published/relevant). Query `SELECT * FROM lens WHERE valid_from ≤ ? AND valid_to >= ?` for temporal slicing.

**Three projections:**
1. **flux-drive triage:** Cypher query `MATCH (p:Persona)—[r:HasContext]—>(l:Lens) WHERE l.tier = 'FLUX' RETURN p, l ORDER BY r.confidence DESC`. AGE supports this natively.
2. **Hermes conversational:** MCP server wrapping AGE Cypher queries. Return persona+lenses for context injection into Claude prompts.
3. **Public catalog:** Read-only SQL-like view (AGE supports SELECT-like syntax) exporting lenses + bridges for web UI (Meadowsyn).

---

### Secondary Path: **TerminusDB for Audit Layer (Optional)**

**If** audit trail and time-travel queries are critical:
- Sync snapshots of Auraken lenses + Hermes persona configs to TerminusDB on update.
- Keeps immutable provenance history (git-like diffs). Query historical schemas via commit hash.
- Query Postgres AGE for live access; query TerminusDB for "what was the state on 2026-03-15?"
- Adds 1 microservice + ETL sync; doable if compliance/audit is a business requirement.

---

### **Not Recommended**

- **TypeDB:** AGPL incompatible; no bi-temporal; separate service. Use for schema *design inspiration* only.
- **Neo4j Community:** GPLv3 incompatible; single-node limit; ecosystem lock-in. Skip.
- **Dgraph:** Overkill for scale; schema-on-read conflicts with "schema-first ontology" goal. Skip.
- **Memgraph:** In-memory design mismatch; BSL uncertainty. Skip for now.

---

## Risks & Fallbacks

### Risk 1: Bi-Temporal Complexity
**If** manual timestamp-filtering becomes error-prone at scale:
- **Fallback 1a:** Integrate TerminusDB as auxiliary audit layer (see Secondary Path).
- **Fallback 1b:** Implement bi-temporal views as Postgres materialized views, refreshed on lens/persona update.

### Risk 2: Postgres Connection Limits
**If** AGE queries under high concurrency saturate Postgres:
- **Fallback:** Spin up read-only Postgres replica, run AGE Cypher on replica for analytical queries (flux-drive triage). Write (Hermes persona updates) still goes to primary.

### Risk 3: Schema Evolution Friction
**If** frequent ontology redesigns make DDL-heavy approach tedious:
- **Fallback:** Loosen schema constraints (nullable properties, generic JSON columns) to simulate schema-on-read. Trade type safety for velocity.

### Risk 4: Cypher Learning Curve
**If** team prefers SQL over Cypher:
- **Fallback:** AGE supports both. Use SQL for simple entity queries, Cypher for traversals. No commitment to 100% Cypher.

---

## Scale Reality Check: Is "Palantir-style" Overengineered?

**Honest assessment:** Yes, *partially.*

- **Palantir Foundry** targets Fortune 500 orgs with petabyte-scale heterogeneous data, 50+ concurrent analyst desks, regulatory audit trails, and data-lineage provenance across systems.
- **Sylveste** has 1200 entities (lenses + personas) and three view projections (triage, conversational, catalog).

**Verdict:** AGE + Postgres is *exactly* the right tool. Not over-engineered (no TerminusDB aux layer needed unless audit becomes business-critical). Not under-engineered (schema-first + typed relationships give you Palantir-*like* rigor without Palantir-*scale* cost).

**The framing is apt:** You're building a personal-scale Palantir Foundry for AI-native tooling. AGE scales from this to 10M entities without architectural change, so you're not boxed in.

---

## Conclusion

**Adopt Apache AGE + Postgres** as the canonical Sylveste unified ontology store. Achieves Palantir-style typed entities + relationships, schema-first discipline, and bi-temporal capability with zero operational overhead (lives in existing Postgres). Ship Hermes + flux-drive projections on top. Defer TerminusDB audit layer until compliance becomes a requirement.

**Timeline:** Schema design (1–2 weeks), AGE DDL (1 week), data migration from md/JSON sources (2–3 weeks), three projections (2–3 weeks). 6–8 weeks to first unified query.

---

## References

- [Apache AGE Documentation](https://age.apache.org/overview/)
- [TerminusDB Git-for-Data Overview](https://terminusdb.org/)
- [TypeDB Knowledge Engineering Database](https://typedb.com/)
- [Neo4j Community Edition](https://neo4j.com/docs/operations-manual/current/installation/)
- [Dgraph GraphQL Database](https://dgraph.io/)
- [Memgraph Real-Time Graph Database](https://memgraph.com/)
- [Bitemporal Modeling Research](https://en.wikipedia.org/wiki/Bitemporal_modeling)
- [Typed Property Graphs](https://medium.com/geekculture/labeled-vs-typed-property-graphs-all-graph-databases-are-not-the-same-efdbc782f099)
