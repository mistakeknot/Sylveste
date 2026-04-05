### Findings Index
- P1 | BLAZON-1 | "F1: Type Family System" | Type families are composable but interaction rules are not — 7 rules form a catalog, not a grammar
- P1 | BLAZON-2 | "F5: Named Query Templates" | Named queries are fixed templates, not compositions of query primitives — new question patterns require new templates
- P2 | BLAZON-3 | "F1: Type Family System" | Entity type definitions reference source subsystems rather than containing reconstruction-sufficient descriptions
- P2 | BLAZON-4 | "F3: Connector Protocol" | Minimum discovery threshold (4 fields) is too thin for independent reasoning — entities are pointers, not descriptions
- P2 | BLAZON-5 | "F1: Type Family System" | No constraint enforcement on relationship composition — any entity can link to any other via any rule
Verdict: needs-changes

## Summary

The PRD's type family system (F1) represents a genuine attempt at compositionality: 5 families as base types, 7 interaction rules as relationship generators, multi-family membership as a composition operator. This tracks the blazon insight well at the highest level. However, the acceptance criteria reveal that compositionality stops at the family level. The interaction rules themselves are an enumerated catalog (7 named rules), not a compositional grammar built from primitives. The named query templates (F5) are similarly non-compositional — 6 fixed templates rather than composed from query primitives. The herald would say: you have a composable field system (families) but a non-composable charge catalog (rules and queries). Future shields will require new charges, and each new charge is a grammar extension.

## Issues Found

### BLAZON-1 (P1): Interaction rules form a catalog, not a compositional grammar

**File**: `docs/prds/2026-04-05-interweave.md`, lines 22-23, 27 (F1 acceptance criteria)

The PRD specifies "7 interaction rules (Productivity, Transformation, Stewardship, Structure, Evidence Production, Annotation, Lifecycle)" and "given (family_a, family_b), returns valid relationship types." New entity types "declare family membership(s) and inherit all family rules" (line 27).

The compositionality test: can interweave describe a relationship that was not enumerated in the 7 rules using existing grammar? Consider:
- An agent (Actor) *delegates* work on an artifact (Artifact) to another agent (Actor). This involves Productivity (Actor→Artifact), Structure (Actor→Actor), and Transformation (the artifact changes hands). Is "delegation" a composition of Productivity + Structure + Transformation, or does it require rule #8?
- A review finding (Evidence) *supersedes* a previous finding (Evidence) about the same artifact. This is Evidence→Evidence, which is not obviously any of the 7 rules. Is it Lifecycle (state transition of evidence) or does it require a new rule?

The PRD's model is a lookup table: `rules(family_a, family_b) → [relationship_types]`. A compositional model would have relationship *primitives* (creates, reads, updates, deletes, observes, delegates) and *modifiers* (temporal: before/after, causal: because/enables, structural: parent/child) that combine to form named rules. The 7 rules would be named compositions, not opaque atoms.

**Concrete failure scenario**: After 10 connectors are integrated, the system has 15+ interaction rules because each new subsystem introduces relationships that don't fit the original 7. The "relational calculus engine" becomes a relationship catalog. Agents cannot reason about novel relationships because they lack the primitives to decompose them.

**Recommended fix**: Add to F1 acceptance criteria: "Interaction rules are composed from a finite set of relationship primitives (create, consume, transform, observe, govern, annotate) and composition operators (temporal, causal, structural). The 7 named rules are syntactic sugar for common compositions. Unit test: express 'delegation' as a composition of existing primitives without adding a new rule." This transforms the rule system from a catalog to a grammar. The herald's principle: the tincture rule (colour on metal, metal on colour) is a *constraint* on *any* blazon, not a list of permitted blazons.

### BLAZON-2 (P1): Named query templates are not composable

**File**: `docs/prds/2026-04-05-interweave.md`, lines 78-88 (F5 acceptance criteria)

F5 defines 6 named query templates as fixed MCP tools. Each is a specific traversal pattern: `related-work` (1 hop, max 10), `recent-sessions` (1 hop, max 10), `causal-chain` (3 hops, max 20), etc. The Non-goals explicitly exclude "Open-ended graph traversal: No Cypher, SPARQL, or GraphQL. Named templates only."

This is a reasonable constraint for v0.1 — bounded traversal avoids the token-sink problem. But the 6 templates are opaque atoms, not compositions. An agent that needs "recent sessions that produced review findings about this entity" must call `recent-sessions` then `review-findings` and manually intersect. There is no composition operator.

The blazon analogy: you can describe "a lion rampant" and "a cross flory" but you cannot describe "a lion rampant holding a cross flory" because there is no "holding" composition operator. Each combined query requires a new template.

**Concrete failure scenario**: The most common agent question is not any single template but a *composition*: "what happened to function X recently and why?" This requires `recent-sessions(X)` + `causal-chain(X)` + `who-touched(X)` with result intersection. Without composition, agents must execute 3 queries, spend 1500 tokens on results, and synthesize manually. This is the exact problem (manual multi-tool queries costing ~800 tokens) that interweave was built to solve (Problem statement, line 11).

**Recommended fix**: Add a 7th query template `context-for <entity>` that composes the other templates: returns recent-sessions + related-work + who-touched in a single call, bounded to the same token budget. This is not open-ended traversal — it is a *named composition* of existing templates. Acceptance criterion: "context-for returns the union of recent-sessions, related-work, and who-touched results, deduplicated, within a 500-token budget. Agents can use a single call for the common 'tell me everything recent about X' pattern."

Alternatively, add a composition operator to the query interface: `interweave query --compose "recent-sessions(X) + who-touched(X)" --max-tokens 500`. This is still bounded (max-tokens constraint) but composable.

### BLAZON-3 (P2): Entity type definitions are referential, not reconstructive

**File**: `docs/prds/2026-04-05-interweave.md`, lines 25, 52-53 (F1 and F3)

F1 defines "5 type families defined as data models with diagnostic properties." F3's minimum discovery threshold is `entity_type, entity_id, subsystem, created_at`. The progressive enhancement allows connectors to provide "minimal (4-field) or rich metadata."

The blazon reconstruction test: given an entity record from interweave, can an agent that has never queried the source subsystem understand what the entity *is* and what it *does*? With the minimum threshold, the answer is no. An entity record `{type: "function", id: "parseConfig", subsystem: "tldr-code", created_at: "2026-03-15"}` tells the agent that something called parseConfig exists in the code. But it does not tell the agent what parseConfig does, what its signature is, what calls it, or what it returns. The agent must query tldr-code directly for any substantive reasoning.

The herald would say: this blazon reads "see the arms of the Duke of Norfolk" instead of describing the arms. It is a *reference*, not a *description*.

**Recommended fix**: Strengthen the minimum discovery threshold to include a `description` field (free-text, 1-2 sentences) and a `lifecycle_state` field (active/deprecated/archived). These two fields transform the entity from a pointer to a basic description. Acceptance criterion: "Given only the interweave entity record, an agent can determine (a) what the entity represents in one sentence and (b) whether it is currently active." This is the reconstruction sufficiency test.

### BLAZON-4 (P2): Minimum discovery threshold insufficient for independent reasoning

**File**: `docs/prds/2026-04-05-interweave.md`, line 53 (F3)

Related to BLAZON-3 but distinct: the minimum discovery threshold (`entity_type, entity_id, subsystem, created_at`) is the contract for *all* connectors. Even rich connectors may default to the minimum for entity types they consider secondary.

**Failure scenario**: The beads connector indexes issues (rich: title, status, assignee, priority, description) and dependencies (minimal: entity_type=dependency, entity_id=dep-123, subsystem=beads, created_at=...). An agent queries `related-work src/parser.py` and gets back bead B (rich) and dependency D (minimal). The agent can reason about bead B but dependency D is opaque — it knows a dependency exists but not what it represents.

**Recommended fix**: Define a "reasoning-sufficient" threshold above the minimum: `entity_type, entity_id, subsystem, created_at, description, lifecycle_state, primary_relationships[]`. Connectors should aim for reasoning-sufficient; minimum is the absolute floor. Add to F3 acceptance criteria: "Each first-party connector (cass, beads, tldr-code) provides reasoning-sufficient metadata for all indexed entity types, not just the minimum discovery threshold."

### BLAZON-5 (P2): No typed constraints on relationship composition

**File**: `docs/prds/2026-04-05-interweave.md`, lines 22-23 (F1)

F1 specifies "given (family_a, family_b), returns valid relationship types." But the acceptance criteria do not specify *constraints* — rules about which relationship compositions are invalid.

The blazon tincture rule is a constraint: colour shall not be placed on colour. It prevents meaningless blazons. Interweave has no equivalent. Can an Evidence entity have a Productivity relationship with another Evidence entity? Can a Relationship entity have a Structure relationship with an Actor? The rule engine says "given these two families, here are the valid relationship types" but does not specify "these relationship compositions are invalid."

Without constraints, traversal paths can compose individually valid edges into meaningless chains. An agent follows: Function → (Productivity) → Session → (Evidence Production) → Finding → (Annotation) → Bead → (Lifecycle) → Sprint. Each hop is valid, but the 4-hop path from Function to Sprint via Finding and Annotation is semantically meaningless.

**Recommended fix**: Add to F1 acceptance criteria: "Invalid relationship compositions defined: at minimum, (a) relationship types that are not valid between specific family pairs, and (b) maximum traversal depth per relationship type (not just per query template). Unit test: attempt to create an invalid relationship (e.g., Evidence→Productivity→Evidence) and verify rejection."

## Improvements

1. **Grammar specification test**: Add to F1 a formal compositionality test: "Given the type family system and interaction rules, two independent implementations produce the same relationship matrix for a test corpus of 20 entity types across 5 families." This is the blazon reconstruction test — two heralds paint the same shield from the same blazon.

2. **Query composition documentation**: Add to F8 documentation showing how to compose multi-template queries. Even without a composition operator, showing the recommended pattern (call A then B, intersect results, estimate token cost) prevents agents from inventing ad-hoc patterns.

3. **Cadency-like versioning for entities**: Consider adding a "cadency mark" mechanism to F2: when a function is modified across commits, the crosswalk tracks the base identity (same function) with a cadency mark (version N). This enables traversal across versions without treating each version as a new entity. The identity chain (line 41) partially does this but only for renames, not for modifications.

<!-- flux-drive:complete -->
