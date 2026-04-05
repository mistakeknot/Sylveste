## Flux Drive Review — 2026-04-05-interweave

**Reviewed**: 2026-04-05 | **Agents**: 4 launched, 4 completed | **Verdict**: needs-changes

### Verdict Summary
| Agent | Status | Summary |
|-------|--------|---------|
| fd-persian-qanat-subterranean-topology | needs-changes | Connector observation contract specifies existence but not depth; causal-chain traversal crosses unverified observation boundaries |
| fd-javanese-gamelan-ensemble-tuning | needs-changes | Multi-family membership exists but source-specific semantics flattened; query context changes ordering but not projection |
| fd-heraldic-blazon-compositional-grammar | needs-changes | Interaction rules form a catalog not a grammar; named queries are fixed templates not compositions; entity definitions are referential not reconstructive |
| fd-polynesian-wayfinding-star-path | needs-changes | Graceful degradation specified but not acceptance-tested; no contradiction detection; no multi-signal synthesis |

### Critical Findings (P0)
None.

### Important Findings (P1)

**1. Interaction rules are a catalog, not a compositional grammar** (3/4 agents: blazon, gamelan, qanat)
- F1 enumerates 7 interaction rules as opaque atoms. New relationship patterns (delegation, supersession) will require adding rule #8, #9, etc. The type family system is composable; the rule system is not.
- Fix: Define relationship primitives (create, consume, transform, observe, govern, annotate) and composition operators. The 7 named rules become syntactic sugar. Add a compositionality unit test.

**2. Connector observation contract lacks depth declaration** (2/4 agents: qanat, blazon)
- F3's observation contract specifies *what* a connector captures and *how often*, but not *how deeply*. The cass connector indexes sessions and tool calls, but does it capture tool call content (file edits, line changes) or only metadata (name, timestamp)? Without declared depth, agents cannot know what questions the graph can actually answer.
- Fix: Add `observation_depth` per entity type to the observation contract.

**3. Named query templates are not composable** (2/4 agents: blazon, starpath)
- F5 defines 6 fixed templates. The most common agent question ("what happened to X recently and why?") requires calling 3+ templates and manually intersecting. This is the same manual multi-tool query cost the PRD was designed to eliminate.
- Fix: Add a `context-for <entity>` composite template, or add a composition operator with a token budget cap.

**4. Graceful degradation has no testable acceptance criteria** (1/4 agents: starpath, but structurally critical)
- F5 line 88 says "return partial results with source status" but does not specify: timeout behavior, progressive vs blocking results, or the distinction between "no data" and "source unavailable."
- Fix: Expand to 3 testable criteria covering per-source status, timeout thresholds, and the no-data vs unavailable distinction.

**5. No contradiction detection across sources** (1/4 agents: starpath)
- F4 defines confidence levels and staleness but not contradiction. When beads says "closed" and cass shows active sessions on the same entity, the graph returns both without flagging the conflict. Query order silently determines which "truth" the agent receives.
- Fix: Add enumerated contradiction patterns to F4 with explicit cross-source conflict markers.

**6. Source-specific semantics lost in multi-family membership** (2/4 agents: gamelan, blazon)
- F1 supports multi-family membership (entity in Process + Evidence), but acceptance criteria do not require preserving source-specific role annotations. A commit is structurally different as a beads state-change vs a git object vs a session output — the family membership is correct but the semantic differences are flattened.
- Fix: Add source_roles array to entity records alongside family membership.

**7. Query context affects ordering only, not property projection** (1/4 agents: gamelan)
- F6 defines 3 context modes (debugging, planning, reviewing) that change result ordering. The brainstorm's pathet insight says the *meaning* of an entity should change with context. Debugging context should surface diff stats; planning context should surface bead associations. Currently, all contexts return identical entity properties.
- Fix: Add per-context property projection to F6 acceptance criteria.

**8. causal-chain traversal crosses unverified observation boundaries** (1/4 agents: qanat)
- The 3-hop causal-chain query traverses from rich subsystems (beads) through moderate ones (flux-drive) into shallow ones (cass metadata-only). The chain *looks* causal but hop quality degrades silently at observation boundaries.
- Fix: Add `max_confidence_hop` constraint — traversal flags or stops when crossing from confirmed to speculative links.

### Section Heat Map
| Section | P1 Issues | P2 Issues | Agents Reporting |
|---------|-----------|-----------|-----------------|
| F1: Type Family System | 2 | 3 | All 4 |
| F5: Named Query Templates | 2 | 2 | blazon, starpath, qanat |
| F3: Connector Protocol | 1 | 2 | qanat, gamelan, blazon |
| F4: Confidence Scoring | 1 | 1 | starpath, qanat |
| F6: Query-Context Salience | 1 | 0 | gamelan |
| F2: Identity Crosswalk | 0 | 2 | qanat, gamelan |
| F7: Gravity-Well Safeguards | 0 | 1 | qanat |
| F8: Philosophy Amendment | 0 | 1 | starpath |

### Cross-Agent Convergence Analysis

Three structural themes emerged independently across agents:

**Theme 1: Compositionality gap** (blazon + gamelan + qanat). The type family system achieves composability at the family level but not at the rule level or query level. Families compose; rules and queries enumerate. This is the dominant finding — 3/4 agents flagged it from different angles (grammar, ensemble tuning, terrain adaptation).

**Theme 2: Observation depth ambiguity** (qanat + blazon + starpath). The PRD specifies *what* is observed but not *how deeply* or *how reliably*. The connector contract, the entity minimum threshold, and the graceful degradation criteria all share this pattern: they declare existence without declaring quality. The qanat agent calls this "shaft density," the blazon agent calls it "reconstruction sufficiency," and the starpath agent calls it "signal reliability."

**Theme 3: Context-sensitivity gap** (gamelan + starpath). F6 acknowledges that query context matters but operationalizes it only as sort order. The gamelan agent's "pathet" and the starpath agent's "etak" both point to the same missing capability: the same entity should project different properties in different operational contexts, not just appear in a different position in the result list.

### Conflicts
No conflicts detected. All 4 agents agree on verdict: needs-changes. Findings are complementary rather than contradictory — each agent examines a different facet of the same structural gaps.

### Improvements Suggested
1. Observation contract visualization table (qanat) — makes connector depth visible at a glance
2. Grammar specification test (blazon) — two implementations produce same graph from same schema
3. Ombak test for multi-family entities (gamelan) — verify source-specific properties preserved
4. Query reliability table for agent developers (starpath) — which queries to trust, when, fallbacks
5. Ensemble integration regression test (gamelan) — new connector does not change existing queries
6. Cadency-like versioning for entity modifications (blazon) — track versions, not just renames
7. Per-template timeout budgets (starpath) — prevent slowest connector from blocking all queries
8. Source attribution with freshness and confidence per result (starpath)
9. Connector observation depth tests (qanat)
10. Context projection matrix documentation (gamelan)
11. Persistent connector health dashboard (starpath)

### Files
- Summary: `docs/research/flux-drive/2026-04-05-interweave-20260405T0128/summary.md`
- Findings: `docs/research/flux-drive/2026-04-05-interweave-20260405T0128/findings.json`
- Individual reports:
  - [fd-persian-qanat-subterranean-topology](./fd-persian-qanat-subterranean-topology.md) — Connector observation depth, causal-chain boundary crossing, identity chain splits
  - [fd-javanese-gamelan-ensemble-tuning](./fd-javanese-gamelan-ensemble-tuning.md) — Source-specific semantics, context projection, schema stability
  - [fd-heraldic-blazon-compositional-grammar](./fd-heraldic-blazon-compositional-grammar.md) — Rule compositionality, query compositionality, reconstruction sufficiency
  - [fd-polynesian-wayfinding-star-path](./fd-polynesian-wayfinding-star-path.md) — Graceful degradation, contradiction detection, multi-signal synthesis
