---
reviewer: fd-noh-kata-canonical-form-drift
bead: sylveste-b1ha
subject: docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md
date: 2026-04-21
severity_counts: {P0: 1, P1: 3, P2: 2, P3: 0}
---

# Review: Persona/Lens Ontology — Canonical-Form Authority and View Drift

## Executive Summary

The three-view projection strategy (D5) lacks iemoto authority mechanisms. Each view will implement "find persona for task" independently, and without a canonical reference implementation, they will drift into incompatible schools within 18–36 months. The bi-temporal versioning (D9) tracks data change but not query-semantics change. One P0 (no canonical query authority across views), three P1s (behavioral contract ambiguity on MCP adapter, effectiveness score drift, micro/meso/macro scale definition drift), two P2s (performance fidelity absent, schema version invisibility).

---

## P0: No Canonical Query Authority Across Three Views

**Location:** D5 (three views), D4 (object types), entire epic structure

**Finding:**
The document specifies three consumers (flux-drive triage, Hermes conversational, Catalog browse) that will each implement "select persona/lens for this context" queries independently. No component is designated as the iemoto reference implementation. The flux-drive view uses "domain match × discipline coverage × effectiveness × community neighborhood" (D5), but Hermes adds "scale (micro/meso/macro) and conversational state" filters, and Catalog will add browse-optimized projections. Neither inherits from the other; no shared query module is specified.

**Concrete failure scenario (18-month horizon):**
- Month 3: flux-drive implements effectiveness-weighted domain matching, threshold 0.6
- Month 8: Hermes team interprets "effectiveness" as binary above/below median
- Month 14: Catalog team adds popularity scoring that re-weights effectiveness by usage frequency
- Month 18: Same query intent ("find bridge lens for climate/economics") returns fd-climate-economics-bridge (flux-drive), fd-systems-thinker (Hermes), fd-polycrisis-navigator (Catalog). All three teams insist their implementation is correct. The ontology's canonical authority has eroded to three incompatible schools.

**Why P0:** This is the foundational drift vector. Without an authoritative reference, each school teaches the kata differently from day one, and drift compounds with every feature iteration. The ontology becomes three ontologies.

**Affected components:** Epic items 4 (flux-drive triage view), 6 (Hermes view, deferred V2), 7 (Catalog, deferred V3), Phase 3 (dedup — who defines "duplicate"?)

**Smallest viable fix:**
1. Designate flux-drive triage view as the iemoto canonical reference implementation (it is the MVP anyway)
2. Extract all persona/lens selection logic into a versioned `ontology-queries` module with semver guarantees
3. Make Hermes and Catalog adapters over the canonical query API, not independent implementers
4. Add to D5: "flux-drive triage view is the canonical reference. Hermes and Catalog MUST delegate persona selection to the ontology-queries API and MAY add presentation-layer filters only."
5. Add acceptance criterion: "All three views return identical persona sets for identical semantic queries (modulo presentation filters)."

---

## P1: D8's "Contract-Stable Adapter" Conflates API Signature with Behavioral Contract

**Location:** D8 (interlens MCP adapter)

**Finding:**
D8 states "Tool contracts (`find_bridge_lenses`, `get_dialectic_triads`) stay stable — only the backing query changes." This conflates API signature stability with behavioral contract stability. The iemoto's concern is not that the function name changed; it is that the *performance* changed — `find_bridge_lenses("climate", "economics")` returns different lenses after migration because the backing query uses a different scoring function.

**Concrete failure scenario:**
- Pre-migration: `find_bridge_lenses` returns 12 lenses ranked by interlens's internal `bridge_score`
- Post-migration: Cypher query uses AGE graph's `effectiveness_score × domain-overlap`, returns 8 lenses in different ranking
- Auraken's dialectic engine (which calls `find_bridge_lenses` as part of a multi-step reasoning chain) now gets different bridge sets
- Team claims "contract is stable" because API signature didn't change
- Three months of "the system got dumber after the migration" bug reports before root cause is identified

**Affected components:** interlens MCP adapter (Epic item 5), any client of `find_bridge_lenses` or `get_dialectic_triads`

**Smallest viable fix:**
1. Amend D8: "Behavioral contracts are versioned via response header `X-Query-Semantics-Version`. Clients MAY assert expected version."
2. Add regression test suite: 50 representative (domain_a, domain_b) pairs with frozen expected lens sets from pre-migration interlens
3. Post-migration query must match ≥90% of pre-migration results or trigger explicit breaking-change protocol
4. Document: "If pre-migration bridge semantics required, pin to `query-semantics-version: 1`. Default post-migration is `version: 2`."

---

## P1: effectiveness_score Has No Derivation Owner Post-Ingestion — Silent Drift Across Views

**Location:** D4 (Auraken `effectiveness_score`), Open Questions ("Who owns effectiveness_score maintenance after ingestion?")

**Finding:**
The document acknowledges this gap but leaves it unresolved. As flux-drive, Hermes, and Catalog each query effectiveness in their selection logic, scoring drift is inevitable. Each view's team will implement its own interpretation of "effective":

- Month 2: Ingestion captures `fd-observer-ethnographer.effectiveness_score = 0.82`
- Month 6: flux-drive adds time-decay: `score × exp(-days_since_use / 90)` → 0.41
- Month 10: Hermes re-normalizes per community_id → 0.67
- Month 12: Catalog replaces with 5-star average → 4.1/5.0 (incomparable scale)

All three views claim to be using "the" effectiveness score from the ontology. Each school has taught the kata differently. The ontology's single-source-of-truth value proposition has failed.

**Affected components:** flux-drive triage view (effectiveness in selection formula, D5), Hermes V2, Catalog V3, ingestion pipeline (Phase 2)

**Smallest viable fix:**
1. Create `EffectivenessScoreCalculator` module owned by the ontology-core team, not view-specific teams
2. All effectiveness reads MUST go through the calculator; views MUST NOT cache or transform the score
3. Calculator API: `calculate(entity_id, context, as_of_date) → float`, with versioned implementations (EffectivenessV1 = static from ingestion, EffectivenessV2 = decay-weighted)
4. Views declare which calculator version they consume
5. Resolve the open question by assigning ownership to ontology-core in the epic's D1 scope note

---

## P1: micro/meso/macro Scale Filter Has No Canonical Definition

**Location:** D5 (Hermes view uses "scale (micro/meso/macro)"), Open Questions

**Finding:**
The micro/meso/macro filter is mentioned only for Hermes (D5), but flux-drive's "domain match" and Catalog's browse categories will implicitly encode scale assumptions. Three schools will teach scale differently:

- Hermes team defines: micro = individual/psychological, meso = organizational/social, macro = systemic/civilizational
- flux-drive team implements scale as "lines-of-code affected" heuristic for routing code vs. architecture reviews
- Catalog team implements as browse tag: #individual, #team, #ecosystem

fd-systems-thinker is then tagged micro (Hermes: thinks in individual cognitive frames), meso (flux-drive: architecture reviews), and macro (Catalog: tagged #ecosystem). User asks Hermes for "macro systems thinker," gets fd-systems-thinker. Same user browses Catalog filtered to macro — fd-systems-thinker is absent. Bug reports, "data inconsistency."

**Affected components:** Hermes conversational view (explicit, D5), flux-drive triage (implicit), Catalog browse (faceted navigation)

**Smallest viable fix:**
1. Add `scale_affinity: {micro: float, meso: float, macro: float}` (sum to 1.0) as a Persona/Lens attribute — stored, not view-computed
2. Define canonical scale taxonomy in schema (Epic item 1): "micro ≡ individual/artifact, meso ≡ team/system, macro ≡ organization/ecosystem"
3. Views query via threshold: `WHERE scale_affinity['macro'] > 0.4`
4. Add to D5: "Scale is a stored attribute, not a view-computed projection. Views filter on scale but MUST use the same stored values."
5. Ingestion pipeline (Phase 2) derives initial scale affinity via LLM prompt, human-reviewed in Phase 3

---

## P2: Persona Type Lacks Performance-Level Fidelity

**Location:** D2 (Persona/Lens distinct types), D4 (Persona object type), `wields` relationship

**Finding:**
The ontology records *that* a Persona wields a Lens but not *how* — the performance kata. Does fd-observer-ethnographer wield participant-observation with detachment (etic) or empathy (emic)? Without this, flux-drive and Hermes will independently develop implicit performance heuristics in their query logic, producing the same lens-persona pair with different behavioral expectations in each view.

**Mitigation:**
Promote `wields` to a reified edge entity with `stance: enum` and `context_suitability: {micro, meso, macro}` properties. Defer population to V2. Add to Phase 3 (dedup pass): "When merging personas, preserve distinct `wields` edges if stance differs even when lens is the same."

---

## P2: Bi-Temporal Timestamps Don't Surface Schema Version Drift Across View Implementations

**Location:** D9 (bi-temporal via `valid_from`/`valid_to`)

**Finding:**
D9 tracks when *data* changed but not when *query semantics* or *schema* changed. If Catalog view is built against schema v3 (before `scale_affinity` added) and Hermes is built against schema v4 (after), the bi-temporal columns don't reveal this. You can see that persona X existed on date Y, but not which schema version defined "existed."

**Concrete failure scenario:**
Month 9: schema v2 adds `scale_affinity`. Month 14: Catalog team (stale docs) queries without `scale_affinity`, includes personas where it is NULL. Month 16: "Catalog shows 400 personas, Hermes shows 320 for same filter." Bi-temporal `valid_from` shows all existed in the time range but says nothing about schema version conformance.

**Smallest viable fix:**
Add `schema_version: semver` attribute to all entity types. Ingestion pipeline tags entities with current schema version. Views query: `WHERE schema_version >= '2.0.0'` for compatibility. Amend D9: "Bi-temporal versioning tracks data validity. Schema versioning tracks model validity. Both required for full provenance."
