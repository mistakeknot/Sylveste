---
reviewer: fd-sibu-classification-fit-check
bead: sylveste-b1ha
subject: docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md
date: 2026-04-21
severity_counts: {P0: 1, P1: 2, P2: 2, P3: 1}
---

# Review: Persona/Lens Ontology — Classification Partition Coherence

## Executive Summary

This schema exhibits the classic symptoms of a residual-category problem. **Concept** functions as the catch-all 雜家 (miscellaneous masters) bin with no admission criterion. The Domain/Discipline boundary replicates the jing/zi instability that plagued late-Qing catalogers. The Task-context deferral is a classification escape rather than a principled deferral. Most critically, the bi-temporal versioning conflates instance-level and schema-level change — which will create irrecoverable ambiguity when the type system evolves.

---

## P0: Bi-Temporal Versioning Cannot Distinguish Schema Evolution from Instance Mutation

**Location:** D9 (bi-temporal via timestamps)

**Finding:**
The proposed `valid_from/valid_to` timestamps will collapse two ontologically distinct kinds of change:
1. **Instance-level:** "This lens's effectiveness score changed from 0.8 to 0.9"
2. **Schema-level:** "We split Concept into Concept+Pattern on 2026-07-01; all prior 'Concept' labels now ambiguous"

The Siku editors faced this when the 四庫 classification itself changed between the 1774 and 1782 editions — entries "moved" between divisions, but the catalogs provided no metadata distinguishing genuine reclassification from catalog-level restructuring.

**Concrete failure scenario:**
V1 launches with 7 types. Six months later, Task-context is promoted to first-class (the document flags this as deferred, not rejected). 200 Persona nodes gain `valid_to = 2026-07-01` when their task-context properties are migrated. A flux-drive query in 2027 retrieves these Personas (no `valid_to` filter) and references their now-deleted task-context properties → runtime null-pointer errors. An analytics query for "active Personas in June 2026" cannot distinguish "deprecated instance" from "schema migration artifact."

**Affected components:** All temporal queries (flux-drive triage, Catalog browse, analytics), migration scripts

**Smallest viable fix:**
Add `schema_version: str` to all nodes. Timestamp tuples become `(valid_from, valid_to, schema_version)`. When schema changes, increment version. Queries filter `WHERE schema_version = 'v1'` for pre-migration state, or `WHERE schema_version = current AND valid_to IS NULL` for current active set.

---

## P1: "Concept" Is the Designated Residual Category with No Admission Criterion

**Location:** D4 object types ("Concept — named idea a lens references")

**Finding:**
The definition "named idea" admits any noun phrase. The given examples span three ontological levels:
- *emergence* — a philosophical primitive (ontology-level)
- *feedback loop* — a structural pattern instantiated in systems (meso-level mechanism)  
- *enabling constraint* — a specific theoretical construct from complexity science that is *also used as a lens* in Cynefin

The Qing test: when a curator encounters "requisite variety" (Ashby's law), they reach for Concept because it's neither clearly a Lens (not framing-complete with forces/solution/questions) nor a Discipline (not a field of study). **Concept is the 雜家** — when you don't know where else to put it.

**Concrete failure scenario:**
Curator ingests "double-loop learning" from Auraken corpus. Materials present it as a lens (forces: "single-loop learning exhausted"; solution: "question governing variables"). But source lacks the structured forces/solution/questions fields, so curator punts to Concept. Six months later, a Hermes user asks "show me lenses about organizational learning" — double-loop learning is missing from results. Curator manually creates a Lens wrapper; now "double-loop learning" exists in both types and a `same-as` edge is created to paper over the misclassification.

**Affected components:** Authoring UX (no decision rubric for Concept vs. Lens boundary), Hermes conversational view (Concept nodes invisible in lens-filtered queries), curation burden

**Smallest viable fix:**
Promote Concept to a union type with two subtypes: **Concept/Primitive** (irreducible theoretical terms: emergence, autopoiesis) and **Concept/Pattern** (structured mechanisms that could become Lenses when elaborated: feedback loop, double-loop learning). Add admission criterion: "Pattern goes here if source lacks forces/solution/questions; Primitive goes here if referenced by 3+ Lenses but never wielded as a standalone framing."

---

## P1: Domain/Discipline Boundary Will Not Hold Under Ingestion Pressure

**Location:** D4 object types, D6 relationships (`in-domain`, `in-discipline`)

**Finding:**
The distinction between Domain ("cross-cutting tag: agent-systems, orchestration, compliance") and Discipline ("formal field of study: organizational psychology, systems theory") replicates the 經部/子部 boundary problem. Concrete example: where does "agent-based modeling" belong?
- **As Domain:** cross-cutting technique applied in economics, epidemiology, social simulation → tag-like, method-level
- **As Discipline:** formal research program with journals (JASSS), conferences (ESSA), canonical texts → field-like, community-level

Auraken's `community_id` field suggests some entries already bridge this. The current schema forces a mutually exclusive choice via `in-domain` vs. `in-discipline` relationships.

**Concrete failure scenario:**
Flux-drive ingests fd-agent "agent-based-modeler-computational-social-scientist" with `domains = ["agent-systems", "simulation"]`. Auraken corpus has lens "Agent-Based Modeling for Policy" with `discipline = "computational social science"`. Curator must choose: Domain or Discipline? Either way, one query path misses it. Curator creates both nodes and adds manual bridging; duplication creeps back in.

**Affected components:** flux-drive triage view (domain match × discipline coverage relies on clean separation), Hermes conversational view, unification pipeline (no decision rubric for ~50 boundary cases)

**Smallest viable fix:**
Replace mutual exclusion with a continuum. Both Domain and Discipline nodes get `formalization_level: float` (0.0 = pure method tag, 1.0 = institutionalized field). Allow dual-typing: entities can have both `in-domain` and `in-discipline` edges if `0.3 < formalization_level < 0.7`. Queries filter by level.

---

## P2: Task-Context Deferral Is an Architectural Escape Hatch

**Location:** D4 ("Deferred: Task-context retained as a property on Persona, not promoted to first-class")

**Finding:**
The deferral presents no principle distinguishing Task-context from Domain or Discipline — both of which are also "tags" that could have been properties. The only implicit distinction is cardinality anxiety: Task-context could have 200+ instances. But cardinality is a database optimization concern dressed as ontology architecture.

**Anticipated failure:**
Hermes V2 needs to filter personas by "conversational state" — which maps to task-contexts like "open-ended exploration" vs. "decision convergence." These are currently Persona properties (strings). To query "show me all personas good at exploration across domains," the implementation must load all Personas and filter by property substring match. The Hermes team then promotes Task-context to first-class, and D9's bi-temporal versioning (P0) creates migration chaos.

**Smallest viable fix:**
Promote Task-context to first-class now with a cardinality cap: "Only task-contexts referenced by 5+ Personas become nodes; others stay as properties." Prevents runaway entity proliferation while admitting the structural nature of high-frequency task types.

---

## P2: Lens/Concept Dual-Nature Entities Will Force Silent Misclassification

**Location:** D4 object types (Lens, Concept), implicit mutual exclusion in D6 relationship patterns

**Finding:**
The `derives-from`, `references`, and `cites` relationship patterns assume mutual exclusivity: `Lens —[references]→ Concept` implies Concept is not itself a Lens. But "enabling constraint" (Juarrero's formulation) appears as an example Concept AND is used as a Cynefin facilitator *lens*. A Qing librarian resolves this via canonical primacy — if a text is cited as a classic, it goes in 經部. The brainstorm provides no equivalent rule.

**Smallest viable fix:**
Add explicit admission rule: "If an entity is used as a framing tool in 2+ Personas, it's a Lens; if referenced by 3+ Lenses but never wielded, it's a Concept. Dual-nature entities get both types (multi-label node)." Enable multi-label nodes in the AGE schema.

---

## P3: `same-as` Will Accumulate as a Classification Escape Hatch

**Location:** D6 (relationships), D7 (deduplication non-goal)

**Finding:**
`same-as` will function as the 互見 (mutual-reference) annotations that proliferated when Siku's 子部/集部 boundary was unstable. Curators uncertain of classification will hedge with multiple nodes linked by `same-as`, creating a shadow meta-layer of equivalence edges that makes the 7-type schema unusable.

**Mitigation:**
Add curation metric: "`same-as` edge count / total node count must stay < 0.15." Monthly review of high-`same-as` nodes triggers reclassification or schema revision.
