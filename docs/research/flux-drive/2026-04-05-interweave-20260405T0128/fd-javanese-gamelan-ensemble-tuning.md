### Findings Index
- P1 | GAMELAN-1 | "F1: Type Family System" | Multi-family membership specified but source-specific type semantics not preserved — ombak lost in unification
- P1 | GAMELAN-2 | "F6: Query-Context Salience" | Context modes affect ordering but not schema projection — same entity properties returned regardless of pathet
- P2 | GAMELAN-3 | "F3: Connector Protocol" | New connector integration lacks schema stability guarantee — adding a connector may change existing query behavior
- P2 | GAMELAN-4 | "F1: Type Family System" | 7 interaction rules are enumerated, not composed — each new rule requires grammar extension, not application of existing rules
- P2 | GAMELAN-5 | "F2: Identity Crosswalk" | Crosswalk maps subsystem_id to canonical_id but does not preserve source-specific role information
Verdict: needs-changes

## Summary

The PRD shows awareness of the multi-schema coherence challenge — the type family system (F1) explicitly supports multi-family membership and avoids forced normalization. This tracks the gamelan tuning insight well at the structural level. However, the acceptance criteria reveal two gaps where the brainstorm's patterns are acknowledged conceptually but not operationalized: (1) an entity's source-specific type semantics are flattened to family membership rather than preserved alongside it, and (2) query context modes (F6) change result *ordering* but not result *projection*, meaning agents always see the same entity representation regardless of their operational context. The penyelaras would say: you have tuned the instruments to each other (good — no forced equal temperament) but you play every piece in the same pathet.

## Issues Found

### GAMELAN-1 (P1): Multi-family membership exists but source-specific semantics are lost

**File**: `docs/prds/2026-04-05-interweave.md`, lines 25-29 (F1 acceptance criteria)

The PRD specifies: "5 type families defined as data models with diagnostic properties" (line 25), "New entity types can declare family membership(s) and inherit all family rules" (line 27), and "Multi-family membership supported (entity belongs to Process + Evidence simultaneously)" (line 28).

This is good — it means a git commit can be both Process (in the beads workflow) and Evidence (supporting a review finding). But the acceptance criteria stop at *family* membership. They do not require the entity to carry its *source-specific* type alongside its family type. A commit-as-beads-state-change has different structural properties (bead_id, transition, before_state, after_state) than a commit-as-git-object (tree, parents, author, message) than a commit-as-session-output (session_id, tool_call_id, files_changed).

**Concrete failure scenario**: An agent queries `related-work src/parser.py` and gets back commit C, which is classified as family=Process + family=Evidence. The agent knows the commit is *related* but not *how* — was it a state transition for a bead (suggesting planned work) or a session output (suggesting exploratory work)? The family membership is correct but the ombak — the characteristic difference between how beads and sessions view the same commit — is flattened.

**Recommended fix**: Add to F1 acceptance criteria: "Entities carry source-specific role annotations alongside family membership. When entity E is indexed from subsystem S, the role annotation preserves S's native type (e.g., `{family: [Process, Evidence], source_roles: [{subsystem: beads, type: state_change, props: {bead_id, transition}}, {subsystem: git, type: commit, props: {tree, parents}}]}`)." This is the "ombak preservation" — intentional imprecision that carries semantic information.

### GAMELAN-2 (P1): Query context changes ordering but not projection

**File**: `docs/prds/2026-04-05-interweave.md`, lines 96-99 (F6 acceptance criteria)

F6 specifies: "3 context modes: debugging, planning, reviewing" (line 96), "Each query template has per-context ordering weights" (line 98), and critically: "Context affects result ordering, not result filtering (all results available regardless of context)" (line 99).

The brainstorm's gamelan insight (pathet modal framework) says the *meaning* of the same note changes depending on the active pathet. F6 operationalizes this as ordering changes only. But a debugging context should not just *reorder* results to show sessions first — it should *project* different properties of each entity. In debugging context, a commit should surface its diff stats and associated test results. In planning context, the same commit should surface its bead association and sprint membership.

**Concrete failure scenario**: An agent in debugging context queries `who-touched src/parser.py` and receives commit C with properties {canonical_id, entity_type, created_at, subsystem}. The same agent in planning context receives the same commit C with the same properties, just ordered differently. The pathet (operational context) changed but the modal meaning of each note (entity) did not change — the agent still has to query the source subsystem for context-specific properties.

**Recommended fix**: Extend F6 to include per-context property projection: "Each query template defines per-context *property sets* — debugging context surfaces diff_stats, test_association, error_logs; planning context surfaces bead_id, sprint, dependencies; reviewing context surfaces finding_ids, evidence_chain." Add acceptance criterion: "Results include context-specific properties, not just context-specific ordering." This transforms F6 from a "sort key" to a true "pathet" — same data, different modal meaning.

### GAMELAN-3 (P2): No schema stability contract for connector addition

**File**: `docs/prds/2026-04-05-interweave.md`, lines 50-58 (F3 acceptance criteria)

F3 specifies the connector interface (`register, harvest, get_observation_contract`) and 3 initial connectors. But there is no acceptance criterion requiring that adding a new connector does not change the behavior of existing queries.

**Failure scenario**: A future `interspect connector` is added, indexing agent calibration evidence. The connector introduces a new relationship type (`calibrated-by`) between agents and evidence entities. Existing queries like `who-touched src/parser.py` now return calibration events alongside sessions and commits — technically correct (an interspect scan "touched" the file by analyzing it) but semantically surprising to agents expecting only modification events.

The penyelaras's principle: when a damaged instrument is replaced, you tune the replacement to match the ensemble, not the ensemble to match the replacement.

**Recommended fix**: Add to F3 acceptance criteria: "Adding a new connector does not change the result set of existing named queries unless the query template is explicitly updated to include the new connector's entity types. New connectors are opt-in per query template, not auto-included." This is the "tune the replacement to the ensemble" pattern.

### GAMELAN-4 (P2): Interaction rules are enumerated rather than composed

**File**: `docs/prds/2026-04-05-interweave.md`, lines 22-23 (F1 acceptance criteria)

F1 specifies "7 interaction rules (Productivity, Transformation, Stewardship, Structure, Evidence Production, Annotation, Lifecycle)" and "7 interaction rules implemented — given (family_a, family_b), returns valid relationship types." The rules are enumerated as a fixed set of 7.

The compositionality question: can these 7 rules describe a relationship that was not imagined when the rules were written? Or will a new relationship pattern (e.g., "delegation" when Skaffen dispatches a sub-agent to work on an artifact) require adding rule #8?

The current design is a lookup table: given two families, return the valid relationship types. This is not compositional — it is a catalog. A compositional approach would define relationship *primitives* (creates, consumes, transforms, observes, governs) and *composition operators* (sequence, parallel, conditional) from which the 7 named rules can be derived and new rules can be constructed.

**Recommended fix**: Add to F1 acceptance criteria a compositionality test: "New interaction patterns between existing type families can be expressed as compositions of existing primitives without extending the rule set. Unit test: given families (Actor, Artifact), construct a 'delegation' pattern using existing rules without adding a new rule." This is P2 because the 7 enumerated rules may be sufficient for v0.1, but the design should preserve a path to compositionality.

### GAMELAN-5 (P2): Crosswalk flattens source-specific role

**File**: `docs/prds/2026-04-05-interweave.md`, lines 37-38 (F2 acceptance criteria)

The crosswalk schema is `(subsystem, subsystem_id, canonical_id, confidence, method)`. This maps *identity* across subsystems but does not preserve the *role* the entity plays in each subsystem. A file `src/parser.py` has a canonical_id in the crosswalk, but the crosswalk does not capture that this file is a "hot file" in cass (frequently touched in sessions), a "stable module" in tldr-code (rarely modified AST), and an "artifact" in beads (output of a tracked work item).

**Recommended fix**: Add an optional `role_hint` field to the crosswalk schema: `(subsystem, subsystem_id, canonical_id, confidence, method, role_hint)`. The role_hint is a subsystem-specific annotation that captures the entity's significance within that subsystem's model. This is P2 because queries can function without it, but cross-system reasoning is impoverished.

## Improvements

1. **Ombak test in F1 unit tests**: Add a unit test that verifies multi-family entities preserve source-specific properties when traversed from different starting points. "Given commit C indexed from beads and git, traversal from a bead context returns beads-specific properties, traversal from a code context returns git-specific properties."

2. **Context projection documentation in F8**: Add to F8 (documentation) a matrix showing which properties are surfaced per query template per context mode. This is the "pathet reference card" for agent developers.

3. **Ensemble integration test**: Add to F3 a regression test: "After adding a new connector, all existing named query templates produce identical result sets for a fixed test corpus." This is the ensemble stability guarantee.

<!-- flux-drive:complete -->
