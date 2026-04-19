---
artifact_type: brainstorm
bead: none
stage: discover
---

# Vision Brainstorm: interweave

## What We're Building

Interweave is the ontology layer for agentic software development. It answers the question every agent eventually asks: "what do I know about this entity across every system that has touched it?"

The concept is analogous to Palantir Foundry's ontology — a structured representation of all objects, relationships, and actions in a domain — but purpose-built for codgents and the projects they work on. Where Foundry models supply chains or intelligence targets, interweave models the full codgent universe: code artifacts (files, functions, modules), agent operations (sessions, sprints, beads, tool calls), and the relationships between them (who modified what, what evidence exists, what blocks what).

The design rests on two permanent constraints:

1. **Finding-aid test.** If you delete interweave, everything still works. Subsystems own their data. Interweave is a catalog-of-catalogs — it indexes, relates, and presents, but never stores primary data. This is not a phase-appropriate guardrail; it's a permanent architectural invariant. The ontology can never become a system-of-record.

2. **Generative over enumerated.** Seven interaction rules generate the complete relationship matrix from five type families. Adding a new entity type means declaring its family membership — it inherits all rules automatically. The ontology is not a hand-maintained graph; it's a calculus that produces the graph.

## Why This Approach

### Horizons Model

The vision unfolds in three horizons, each building on the previous one:

**Horizon 1: Foundation (current epic, sylveste-46s)**
Type families, identity crosswalk, connectors, named query templates, confidence scoring, salience, gravity-well safeguards. The minimum viable ontology — agents can ask cross-system questions and get structured answers.

*You know it's working when:* An agent encountering a file for the first time can call `session_actors_for_file` and immediately know who changed it, which beads are related, and what evidence exists — without querying cass, beads, and tldr-code separately.

**Horizon 2: Inference + Routing Integration**
Computed relationships beyond explicit links. Temporal cooccurrence ("these entities were modified in the same session"), embedding similarity ("these functions have similar AST structure"), causal inference ("this finding was discovered during this sprint"). The ontology stops being a passive index and starts surfacing patterns.

The routing integration makes this concrete: agent dispatch queries the ontology. "Which agent should handle this file?" becomes a traversal: who touched it → what was their success rate → what complexity signals exist → route accordingly. Routing IS ontology traversal.

*You know it's working when:* Interweave suggests a relationship that no explicit link established — e.g., "this file and that bead are probably related because the same actor touched both in overlapping sessions" — and the suggestion is correct often enough that agents rely on it.

**Horizon 3: Cross-Project Federation**
The ontology spans multiple projects. A developer's identity, patterns, and learnings are portable. An actor who established expertise in Project A carries that provenance into Project B. Cross-project patterns emerge: "this architecture decision was tried in three projects; it succeeded in two."

Federation doesn't mean centralization. Each project has its own interweave instance. Federation is a protocol for exchanging identity links and relationship claims between instances — with confidence metadata, so receiving instances can assess trust.

*You know it's working when:* An agent in a new project can query "has anyone in the org solved a problem like this before?" and get an answer drawn from another project's ontology, without that project's data being copied.

### The Permanent Invariants

Across all three horizons, these never change:

- **Finding-aid test holds.** Delete interweave at any horizon, everything still works. H2's inferred relationships are valuable but not required. H3's federation links are additive context, not dependencies.
- **Generative, not enumerated.** The 7 interaction rules scale to any number of entity types. H2 adds inference methods, not rules. H3 adds federation protocols, not entity types.
- **Catalog-of-catalogs.** Interweave never writes to subsystems. It never caches data that subsystems own. It never becomes the canonical source for any entity. The subsystem is always authoritative.
- **Evidence-earns-authority.** Inferred relationships carry confidence levels. Federated links carry provenance. No relationship is trusted without metadata about how it was established. This is Sylveste's core principle (Principle 2) applied to the ontology.

## Key Decisions

- **Identity:** Interweave is the ontology for codgents — spanning both code artifacts and agent operations, with cross-system identity as the foundation
- **Scope:** The full codgent universe — code AND agents AND relationships between them
- **Finding-aid:** Permanent constraint, not a phase guardrail
- **Structure:** Three-horizon model (foundation → inference + routing → federation)
- **Horizon ordering:** Inference first (most value per token), routing integration (most operational leverage), federation last (most ambitious)
- **Framing:** Horizons model over Palantir-parallel or principles-first

## Open Questions

1. **Inference methods for H2:** Which inference approaches first? Temporal cooccurrence is cheapest. Embedding similarity is most powerful. Causal inference is most ambitious. Likely start with temporal — it requires no model calls.
2. **Federation protocol for H3:** What does cross-project identity exchange look like? Probably a subset of attp (the cross-machine protocol), reused for cross-project ontology federation.
3. **Routing integration depth:** Does interweave provide routing data (passive) or participate in routing decisions (active)? Probably passive first — provide the data, let the router (Ockham/Clavain) decide.
4. **Standalone vs kernel-native classification:** Is interweave standalone (current) or kernel-native? It feeds kernel systems (routing, dispatch) but doesn't require them. Probably stays standalone with optional kernel integration via connectors.
