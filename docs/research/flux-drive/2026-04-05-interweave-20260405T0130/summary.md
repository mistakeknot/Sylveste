# Flux Drive Review -- interweave PRD

**Reviewed**: 2026-04-05 | **Agents**: 5 launched, 5 completed | **Verdict**: needs-changes

## Verdict Summary

| Agent | Status | Summary |
|-------|--------|---------|
| fd-ontology-schema-evolution | warn | Rule matrix unspecified, multi-family resolution undefined, no schema evolution contract |
| fd-entity-resolution-identity | warn | 80% body similarity threshold too low (P0), transitive closure unaddressed, tree-sitter brittle |
| fd-graph-query-runtime | warn | causal-chain 3-hop has unbounded fan-out, token cost target unrealistic, needs performance contract |
| fd-agent-ontology-runtime | warn | No capability delta proven over existing tools, bootstrap problem, 6 MCP tools too many |
| fd-composition-coupling-philosophy | warn | Connector model risks coupling, F4 provenance may be owned data, premature family abstraction |

## Critical Findings (P0)

**ERI-3: Body similarity heuristic >80% will produce false positives at scale** (fd-entity-resolution-identity)
F2 line 40 specifies ">80% match links identities" for function rename detection. In a 60+ plugin codebase, boilerplate functions, generated code, and copy-paste-modify patterns will match at >80% despite being distinct entities. A 1% false positive rate at thousands-of-functions scale produces dozens of phantom identity links. Agents make decisions based on wrong context.
*Fix*: Raise auto-link threshold to >95% (confirmed). Links in 80-95% range should be `confidence: probable`, excluded from default queries per F4.

## Important Findings (P1)

**OSE-5 + CCP-3: The generative type family system is underspecified** (2/5 agents)
The PRD declares 5 families and 7 rules but never provides the actual 5x5 family-pair rule matrix. Implementers must guess which cells are valid. Additionally, the 5 families were chosen before observing real query patterns, risking premature abstraction.
*Fix*: Add an appendix with the complete rule matrix. Consider shipping with 3 families initially and adding Evidence/Relationship after usage data.

**OSE-1: Multi-family membership lacks resolution strategy** (fd-ontology-schema-evolution)
An entity in {Process, Evidence} queried against an Artifact produces rules from both families. No precedence or merge strategy specified.
*Fix*: Add acceptance criterion specifying union, primary-family, or intersection resolution.

**ERI-1: Transitive identity closure not addressed** (fd-entity-resolution-identity)
If A=B (beads) and B=C (cass), the crosswalk could infer A=C. Transitive closure is the #1 source of false equivalences in entity resolution.
*Fix*: Add "identity links NOT transitively closed by default" to F2 criteria.

**ERI-2 + CCP-6: tree-sitter identity is language-dependent** (2/5 agents)
Function-level resolution depends on tree-sitter grammar quality. Python/JS/Go work well; bash/Haskell do not. Shell scripts (heavily used in this project) get only file-level resolution.
*Fix*: Document supported vs. unsupported languages. Report resolution granularity per language in observation contract.

**GQR-5: causal-chain has unbounded intermediate fan-out** (fd-graph-query-runtime)
"max 20" applies only to final results. Intermediate hops expand all nodes. High-connectivity entities explode: 50 x 50 x 50 = 125K candidates for 20 results.
*Fix*: Add beam-search limit (K=50) per hop. Add to F5: "intermediate fan-out limited to 50 nodes per hop."

**GQR-1: Token cost <500 unrealistic for causal-chain** (fd-graph-query-runtime)
20 results x 25-30 tokens/result = 500-600 tokens for results alone. 3-hop metadata adds more.
*Fix*: Split target: <500 for 1-hop queries, <800 for causal-chain.

**AOR-1: No concrete capability delta proven** (fd-agent-ontology-runtime)
The "~800 tokens for manual multi-tool queries" claim is unsubstantiated. The PRD needs before/after scenarios proving interweave is materially better than cass+beads+grep.
*Fix*: Add a "Scenarios" section with 3 concrete examples including token counts and information gaps.

**AOR-2: Bootstrap problem** (fd-agent-ontology-runtime)
Agents must know entity types, query formats, and when to prefer interweave over existing tools. 6 new MCP tools fragment the agent's decision space.
*Fix*: Consider consolidating to 2-3 tools. Add explicit capability-delta guidance to tool descriptions.

**AOR-4 + CCP-1: Finding-aid test needs expansion** (2/5 agents)
F7's finding-aid test covers data dependency (can subsystems function without the index?) but not behavioral dependency (do agents fall back when interweave is down?) or provenance dependency (is F4 link provenance re-derivable from source data?).
*Fix*: Add behavioral fallback test + provenance regeneration test to F7 criteria.

**CCP-2: Connector model creates implicit coupling** (fd-composition-coupling-philosophy)
If future plugins must implement the connector interface to be indexed, fail-open independence is violated.
*Fix*: Specify that connectors are always interweave-internal. Subsystems need not know about interweave.

## Section Heat Map

| Section | P0 | P1 | P2 | Agents Reporting |
|---------|----|----|-----|-----------------|
| F1: Type Family System | 0 | 3 | 2 | ontology-schema, composition-coupling |
| F2: Identity Crosswalk | 1 | 3 | 1 | entity-resolution, composition-coupling |
| F3: Connector Protocol | 0 | 1 | 2 | composition-coupling, ontology-schema, graph-query |
| F4: Confidence Scoring | 0 | 1 | 1 | entity-resolution, composition-coupling |
| F5: Named Query Templates | 0 | 4 | 2 | graph-query, agent-ontology |
| F6: Query-Context Salience | 0 | 0 | 1 | agent-ontology |
| F7: Gravity-Well Safeguards | 0 | 1 | 0 | agent-ontology, composition-coupling |
| F8: Philosophy Amendment | 0 | 0 | 1 | composition-coupling |
| Non-goals | 0 | 2 | 0 | graph-query, composition-coupling |
| Open Questions | 0 | 1 | 0 | entity-resolution |

## Cross-Agent Convergence

4 findings had independent convergence from 2+ agents:
1. **Rule matrix / premature abstraction** (OSE-5 + CCP-3): Schema evolution and philosophy agents both flagged the unspecified/premature family system
2. **tree-sitter language brittleness** (ERI-2 + CCP-6): Identity and philosophy agents both flagged the language support boundary
3. **causal-chain fan-out / query cost** (GQR-5 + AOR-2): Query runtime and agent-runtime agents both flagged the 3-hop cost problem
4. **Finding-aid test scope** (AOR-4 + CCP-1): Agent-runtime and philosophy agents both flagged provenance/behavioral dependency gaps

## Evaluation of the 6 Review Dimensions

### 1. Are the 8 features correctly scoped and decomposed?

**Mostly yes, with one structural gap.** F1-F3 form a clean foundation layer (type system, identity, connectors). F4-F6 build query capabilities on that foundation. F7 provides safeguards. F8 handles documentation.

The gap: there is no feature for **index lifecycle management** (initial population, rebuild, migration). F7's `interweave audit` deletes and rebuilds, but the normal first-time setup, incremental population, and version upgrade paths are not scoped as a feature. Open Question 4 (index size management) acknowledges this but leaves it entirely open.

### 2. Are acceptance criteria concrete and testable?

**Mixed.** F2, F5, and F7 have concrete, testable criteria. F1 and F3 have criteria that read more like feature descriptions than test cases. For example, F1's "7 interaction rules implemented -- given (family_a, family_b), returns valid relationship types" is testable only if the expected outputs (the rule matrix) are specified -- and they are not. F4's "default query filter excludes speculative links" is testable. F6's "3 context modes" is testable.

### 3. Is the dependency chain correct?

**Yes, the stated chain F1->F2->F4 and F1->F3->F5->F6 is sound.** F1 (type families) must exist before F2 (identity crosswalk) can classify entities. F3 (connectors) must exist before F5 (queries) can return cross-system results. F4 (confidence) logically depends on F2 (identity). F6 (salience) depends on F5 (queries).

One missing dependency: **F5 depends on F2** (not just F3). The named queries accept entity identifiers as input -- the identity crosswalk must be able to resolve those identifiers to canonical entities before the query can execute. The stated chain F1->F3->F5 skips F2.

### 4. Are the non-goals appropriate?

**Yes, all 5 non-goals are correct** and well-calibrated for v0.1. The "no graph database" and "no open-ended traversal" non-goals are the most important architectural decisions in the PRD -- they prevent scope creep toward a general knowledge graph. The "no real-time streaming" non-goal is appropriate given the harvest model. Two agents flagged that the "no graph database" rationale should be expanded (CCP-4), not that the decision is wrong.

### 5. Are the open questions the right ones?

**3 of 4 are correct. OQ3 (entity input parsing) should be promoted to an acceptance criterion** -- it's not a design decision to defer, it's a requirement that F5 cannot function without. OQ1 (single vs. separate DBs) and OQ2 (refresh scheduling) are genuine design decisions that can be resolved during implementation. OQ4 (index size) is appropriate to leave open for v0.1.

**Missing open question**: What is the cold-start experience? When interweave is first installed, the index is empty and all queries return nothing. How long until the first harvest populates enough data for queries to be useful? This determines whether early adopters abandon the tool before it provides value.

### 6. Is the generative type family architecture sound?

**The architecture is sound in principle but underspecified in practice.** The generative approach (families + rules produce the relationship space) is superior to the enumerative approach (list every valid relationship). It handles new entity types gracefully and avoids the Freebase explosion of relationship types.

However, the specification is incomplete:
- The 5x5 rule matrix is absent (which family pairs produce which rules?)
- Multi-family resolution is undefined (what happens when an entity belongs to 2+ families?)
- The closed-world/open-world assumption is unstated (does "no valid rule" mean "impossible" or "not yet defined"?)
- Schema evolution is unaddressed (what happens when families or rules change?)

The architecture can work. The specification does not yet contain enough detail to implement it consistently.

## Conflicts

No direct conflicts between agents. All 5 agents agree the PRD is architecturally sound but insufficiently specified for implementation.

## Files

- Summary: `docs/research/flux-drive/2026-04-05-interweave-20260405T0130/summary.md`
- Findings: `docs/research/flux-drive/2026-04-05-interweave-20260405T0130/findings.json`
- Individual reports:
  - [fd-ontology-schema-evolution](./fd-ontology-schema-evolution.md) -- Rule matrix, multi-family resolution, schema evolution
  - [fd-entity-resolution-identity](./fd-entity-resolution-identity.md) -- Body similarity P0, transitive closure, tree-sitter brittleness
  - [fd-graph-query-runtime](./fd-graph-query-runtime.md) -- causal-chain fan-out, token cost, SQLite performance
  - [fd-agent-ontology-runtime](./fd-agent-ontology-runtime.md) -- Capability delta, bootstrap problem, tool consolidation
  - [fd-composition-coupling-philosophy](./fd-composition-coupling-philosophy.md) -- Catalog enforcement, connector coupling, premature families
