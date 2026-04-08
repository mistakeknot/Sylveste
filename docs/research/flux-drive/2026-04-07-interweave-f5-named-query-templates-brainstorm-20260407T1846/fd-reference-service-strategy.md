### Findings Index
- P1 | REF-1 | "What We're Building" | Template scope boundaries undocumented — who_touched_file implies all-time all-actors but cass coverage has temporal gaps
- P1 | REF-2 | "What We're Building" | entity_relationships has no entity-family scope validation — silently empty results for out-of-scope entity types
- P2 | REF-3 | "Open Questions" | No mechanism to detect connector schema/coverage changes that affect template recall — templates become silently stale
- P2 | REF-4 | "What We're Building" | Template descriptions insufficient for agent self-directed selection — adjacent templates (entity_relationships vs entity_timeline vs related_artifacts) undifferentiated
- P3 | REF-5 | "Key Decisions" | Recall/precision posture undeclared per template — agents cannot reason about false-negative risk when choosing between templates
Verdict: needs-changes

### Summary
The 8-template design encodes significant expert knowledge about cross-system joins, but the brainstorm omits the documentation layer that gives templates their value over ad-hoc queries. Template descriptions, as implied by the brainstorm, do not document temporal coverage, entity family constraints, or what classes of actor/event a template cannot retrieve. The entity_relationships template will silently return empty results for entity types outside its supported family without explanation. Template obsolescence detection — how to know when a connector's schema change has invalidated a template's recall — is entirely absent.

### Issues Found

REF-1. P1: Template scope boundaries undocumented — who_touched_file implies all-time all-actors but cass coverage has temporal gaps

The brainstorm describes `who_touched_file` as returning "all actors (agents, humans) that modified it, with session context and timestamps. Joins: crosswalk (file entity) + cass (sessions) + beads (work items)." The word "all" is false advertising when cass was installed at a specific date. Agents that invoke `who_touched_file` on an old file will receive actor history only from cass's installation date onward, with no indication that earlier modification history exists. The Severity Calibration scenario in this agent's spec (actor_activity with an actor who predates cass installation) is exactly this problem.

Each QueryTemplate's description must document: (1) the time range of its coverage, (2) which subsystems contribute actor history and from what date, and (3) a canonical question form that makes the scope boundary explicit ("who has touched this file since cass indexing began" not "who touched this file").

Smallest fix: Add a "Scope limitations" subsection to the What We're Building description for each template, explicitly noting temporal coverage bounds and any entity-family or installation-date dependencies.

REF-2. P1: entity_relationships has no entity-family scope validation — silently empty results for out-of-scope entity types

The brainstorm defines `entity_relationships` as "uses the relational calculus engine. Pure engine query over crosswalk data." The engine's interaction rules are defined per entity type family (the brainstorm references "5 type families"). If an agent passes a session entity ID to `entity_relationships` and sessions are modeled as Actor-family, but the structure interaction rule only applies to Artifact-family entities, the template returns an empty relationships list with no scope error. The agent cannot distinguish "this entity has no relationships" from "this entity's type is outside this template's scope."

This is analogous to a library search strategy that accepts a query on a topic outside its database's coverage and returns zero results without informing the patron that the topic requires a different database.

Smallest fix: Add to the QueryTemplate ABC specification: "execute() must validate that the input entity's type family is within the template's declared entity_families list and raise EntityFamilyScopeError with a descriptive message when the entity is out-of-scope, rather than returning an empty QueryResult."

REF-3. P2: No mechanism to detect connector schema/coverage changes that affect template recall — templates become silently stale

The brainstorm notes that "templates compose existing primitives without adding new storage." This means template correctness depends entirely on the stability of the connector schemas and crosswalk indexing. If cass adds a new session attribute that would improve `actor_activity` coverage, or if beads changes its work item structure, templates that were correct at the time of writing may silently miss new data. Library search strategies that were built against database vocabulary from 2020 miss new terms indexed after 2020.

The TemplateRegistry design has no mechanism to signal when a template may be stale relative to a connector's schema version, and no `last_validated_against` timestamp that tells consumers how recently the template was verified against live connectors.

Smallest fix: Add `schema_version: dict[str, str]` to the QueryTemplate ABC — each template declares the connector schema versions it was validated against. The registry can warn when a connector's current version differs from the template's declared version.

REF-4. P2: Template descriptions insufficient for agent self-directed selection — adjacent templates undifferentiated

The brainstorm lists `entity_relationships`, `related_artifacts`, and `entity_timeline` as separate templates. From the description alone, an agent asking "what is connected to this entity?" cannot determine whether to use `entity_relationships` (relational calculus, pure engine), `related_artifacts` (structure interaction rule, imports/dependencies), or `entity_timeline` (chronological events). These three templates answer subtly different questions but share overlapping surface descriptions.

BI report catalogs that lack canonical question forms create exactly this navigation problem — users browse to the wrong report because the descriptions don't disambiguate.

Smallest fix: Each template's description must include a "Canonical question form" — one sentence that makes the template's unique scope explicit. For example: `entity_relationships`: "What entities does X have semantic relationships with according to the interaction rules?" vs `related_artifacts`: "What code artifacts structurally depend on or reference X?" vs `entity_timeline`: "What events happened to X in chronological order?"

REF-5. P3: Recall/precision posture undeclared per template — agents cannot reason about false-negative risk

`entity_relationships` is described as a "pure engine query" — high precision (only relationships the engine can certify), potentially lower recall (may miss relationships not modeled in the interaction rules). `evidence_for_entity` is described as using "the evidence-production interaction rule" — also precision-focused. There is no equivalent of a "sensitive search" template that sacrifices precision for recall.

Agents that need exhaustive coverage (e.g., "find every possible connection before deleting this entity") have no way to know which templates maximize recall vs. precision. Documenting the posture per template would let agents make principled template selection decisions.

Suggestion: Add a `search_posture: Literal['precision', 'recall', 'balanced']` attribute to the QueryTemplate ABC, documented in the brainstorm's Key Decisions.

### Improvements

REF-IMP-1. Add a structured scope section to each template description in the brainstorm: input entity family constraints, subsystem coverage, temporal coverage, and canonical question form — this is the single change that most improves agent self-directed template selection.

REF-IMP-2. Consider a meta-template or discovery tool that agents can query with a free-text question to get back the best-matching template name — analogous to a library reference desk that routes patrons to the right search strategy.
<!-- flux-drive:complete -->
