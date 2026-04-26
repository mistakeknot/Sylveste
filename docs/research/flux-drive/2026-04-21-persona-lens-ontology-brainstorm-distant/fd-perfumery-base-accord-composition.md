---
reviewer: fd-perfumery-base-accord-composition
bead: sylveste-b1ha
subject: docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md
date: 2026-04-21
severity_counts: {P0: 1, P1: 2, P2: 2, P3: 1}
---

# Review: Persona/Lens Ontology — Compositional Layering and Provenance Integrity

## Executive Summary

The proposed unification exhibits **provenance truncation** (P0), **missing fixative semantics** (P1), and **collapsed temporal layering in bridge relationships** (P1). The three-tier Persona/Lens/Concept hierarchy maps cleanly to base/heart/top note structure, but the relationship model flattens compositional grammar that should be preserved as graph topology.

---

## P0: Provenance Truncation Will Corrupt Lens Lineage

**Location:** D4 (Source object), D6 (`derives-from`), "What We're Building" (flux-review-ep11 reference)

**Finding:**
The Source object and `derives-from` relationship capture only *who created what when*, not *how/why/under-what-constraints*. The example provenance label `flux-review-ep11` is a batch identifier — a perfumer's equivalent of writing "rose" without noting Bulgarian vs. Turkish, harvest year, or extraction method. Two "fd-strategic-incoherence-detector" lenses from different flux-review epochs will appear identical when their olfactive profiles (one trained on 2024 compliance tasks, one on 2026 agentic orchestration) differ substantially.

**Concrete failure scenario:**
flux-drive selects lens_447 (Akan goldweight metrology) for an agent-systems review. The lens was extracted from a 2024 flux-review run predating the "agentic orchestration" vocabulary. The review applies legibility heuristics from chiefdom-era governance, missing emergent coordination patterns. Root cause: the graph knows `flux-review-ep11` but not that ep11 was pre-orchestration-vocabulary.

**Affected components:** D4 (Source schema), D6 (`derives-from` properties), Epic step 2 (ingestion)

**Smallest viable fix:**
Extend Source to include `extraction_method: enum[manual, llm-generated, llm-assisted, corpus-distilled]`, `generation_config: {model, temperature, prompt_version}`, and `vocabulary_epoch: string` (e.g., "pre-orchestration", "post-Hermes-pivot"). Modify the ingestion pipeline to parse `.claude/agents/` frontmatter for generation parameters.

---

## P1: Missing Fixative Semantics in Relationship Model

**Location:** D6 (relationships), interlens `get_dialectic_triads`

**Finding:**
The ontology models `bridges`, `contradicts`, `supersedes` — all dialectical or substitutional relationships — but provides no mechanism for *fixative* lenses: lenses that stabilize combinatorial volatility rather than bridging. The interlens `get_dialectic_triads` function implies some lenses form stable three-element chords; the proposed graph would model this as three pairwise `bridges` edges, losing the information that the triad is stable *because one element acts as a fixative*.

**Concrete failure scenario:**
flux-drive combines `lens_A: emergence-detector` + `lens_B: reductionist-audit` + `lens_C: systems-boundary-mapper`. Graph shows A-[bridges 0.7]→B and B-[bridges 0.6]→C. Consumer assembles A+B without C. In practice A and B are antithetical — their pairing only works when C acts as a fixative holding systemic boundary stable. Incoherent review output results.

**Affected components:** D6 (relationship schema), Epic step 4 (triage view), Epic step 5 (interlens adapter — `get_dialectic_triads` loses expressiveness)

**Smallest viable fix:**
Add `Lens —[fixates {volatility_reduction}]→ {Lens, Lens}` as a ternary relationship. Implement via AGE reified relationship node (`WieldsStabilizer`). Update the ingestion pipeline to extract triads from interlens's existing `get_dialectic_triads` and classify the stabilizing element.

---

## P1: Collapsed Temporal Layering in Bridge Relationships

**Location:** D6 (`bridges {strength}` relationship)

**Finding:**
The `bridges {strength}` scalar measures degree of connection but not *timing of revelation*. In haute parfumerie, a bridge note has a temporal arc: when it emerges, how long it holds, when it fades. A lens bridge has the same grammar: does Lens A activate Lens B immediately (top-to-heart), or only after prolonged application (heart-to-base)? The flat scalar corrupts combinatorial sequencing in Hermes conversational view (V2) where the system needs to know whether to deploy Lens B after 2 conversational turns or after 20.

**Concrete failure scenario:**
Hermes deploys `lens_A: emergence-detector` at turn 3. Graph shows A-[bridges 0.9]→B: path-dependency-auditor. Hermes immediately offers Lens B at turn 4. In reality, path-dependency only becomes legible after emergence has been observed over multiple cycles — Lens B should deploy at turn 10+. The user receives a premature reframing; the conversation feels mechanical.

**Affected components:** D6 (`bridges` properties), D5 (Hermes V2 view — though deferred), Epic step 4 (multi-pass reviews)

**Smallest viable fix:**
Extend `bridges` with `activation_delay: enum[immediate, short, medium, long]` and optional `revelation_condition: string`. Default existing entries to `immediate` during ingestion. In Phase 3 dedup pass, infer delays from embedding comparison of lens *questions* vs. *forces*: if B's questions reference concepts that only appear in A's *solution*, classify as `medium` or `long`.

---

## P2: Three-View Projections Risk Concentration Drift

**Location:** D5 (three view projections)

**Finding:**
The three views are defined by consumer need, not deployment strength. flux-drive will add `tier` and `use_count` as indexed query parameters; Hermes will add `conversational_affordance`; Catalog will add `display_name` and `is_public`. If these properties live on core Persona/Lens objects rather than view-specific metadata layers, the graph becomes a dumping ground.

**Mitigation:**
Introduce a metadata layer pattern: each view gets a separate linked metadata object (PersonaTriageMetadata, PersonaConversationalMetadata, LensCatalogMetadata) rather than extending core objects. Not blocking for MVP; decide before Hermes V2 work begins.

---

## P2: Same-As 0.8 Threshold Violates the Two-Roses Principle

**Location:** D7 (dedup strategy), Epic step 3 (semantic dedup pass)

**Finding:**
lens_291 (Auraken, Persian-medicine-assayer — humoral diagnostics) and lens_418 (fd-agents, Akan-goldweight-metrology — calibration rituals and trust mechanisms) would embed at ~0.82 similarity (both pre-modern non-Western metrology epistemics). A dedup pass marks them `same-as {confidence: 0.82}`. A query for "distributed trust audit lenses" returns the Persian medicine lens because it ranked higher on another dimension. The Akan lens's specific focus on goldweight standards as political technology is buried under a false equivalence.

**Mitigation:**
Change `same-as` semantics: the semantic dedup pass populates `candidate-same-as {similarity, method}` for human review. A curator promotes to `same-as` only for true duplicates (same lens, different phrasing). The 0.8 threshold becomes a recall parameter for the candidate queue, not a precision threshold for equivalence.

---

## P3: Compositional Semantics Not Documented — Design Vulnerable to Refactoring

**Location:** D4 (object types), "Why This Approach"

**Finding:**
The Persona/Lens/Concept hierarchy maps excellently to base/heart/top note positions (Persona = base: stable archetype with temporal persistence; Lens = heart: contextual framing; Concept = top: volatile named idea), but the document doesn't articulate this. Without an explicit compositional semantics section in D4, future maintainers lack a conceptual anchor for deciding where new types belong (e.g., Task-context: is it a heart note or a top note?).

**Recommendation:**
Add a "Compositional Semantics" subsection to D4 stating the base/heart/top mapping and its implications for temporal persistence and update frequency.
