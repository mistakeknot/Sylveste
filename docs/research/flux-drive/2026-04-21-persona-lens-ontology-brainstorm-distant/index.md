---
artifact_type: flux-drive-index
bead: sylveste-b1ha
subject: docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md
date: 2026-04-21
track: distant-domain structural isomorphisms
agents_run: 5
severity_totals: {P0: 6, P1: 9, P2: 9, P3: 4}
---

# Flux-Drive Review Index — Persona/Lens Ontology (Distant-Domain Track)

## Agents

| Agent | File | P0 | P1 | P2 | P3 |
|---|---|---|---|---|---|
| fd-perfumery-base-accord-composition | fd-perfumery-base-accord-composition.md | 1 | 2 | 2 | 1 |
| fd-sibu-classification-fit-check | fd-sibu-classification-fit-check.md | 1 | 2 | 2 | 1 |
| fd-isnad-chain-integrity | fd-isnad-chain-integrity.md | 2 | 2 | 2 | 1 |
| fd-quipu-cord-typing-discipline | fd-quipu-cord-typing-discipline.md | 2 | 2 | 1 | 1 |
| fd-noh-kata-canonical-form-drift | fd-noh-kata-canonical-form-drift.md | 1 | 3 | 2 | 0 |

**Totals: P0 × 7, P1 × 11, P2 × 9, P3 × 4**

(Note: some findings address the same root issue from different angles; cross-cutting findings are noted below.)

## Cross-Cutting Convergences

### same-as as tier-laundering vector (P0 — isnad, P1 — perfumery, P3 — sibu)
Three agents independently flagged D7's same-as relationship as an unguarded contamination path. Isnad identifies it as tier-laundering (LLM-generated lens inheriting tier-1 via same-as without source-independence check). Perfumery identifies it as the two-roses collapse (0.8 embedding similarity is insufficient to merge culturally distinct lenses). Sibu identifies it as the 互見 escape hatch that papers over classification indecision. The fix is the same across all three: same-as must require `source_independence = TRUE AND corroborator_count >= 2` before any tier-inheritance is permitted; automated dedup should emit `candidate-same-as` for human review, not `same-as`.

### bi-temporal versioning conflates instance and schema change (P0 — sibu, P2 — noh)
Sibu flags D9 as P0: when the type system evolves (Task-context promoted, Concept split), `valid_to` timestamps become ambiguous between "deprecated instance" and "schema migration artifact." Noh flags the same gap at P2: schema_version is absent, so views built against different schema iterations cannot be distinguished in provenance queries. Fix is shared: add `schema_version: semver` to all entities.

### no canonical query authority (P0 — noh) / effectiveness_score drift (P1 — noh) / view projection drift (P2 — perfumery)
Noh's P0 is the highest-signal finding of the run: D5 describes three views but designates no iemoto reference implementation. Each view will implement "find persona for task" independently. This is structurally the same failure mode perfumery flags at P2 (projection-level drift as views accumulate view-specific properties) and isnad flags for effectiveness_score (no owner post-ingestion → each view computes its own interpretation). The shared fix: extract selection logic into a versioned `ontology-queries` module; make Hermes and Catalog adapters, not reimplementers.

### bridges edge underspecified (P0 — quipu, P1 — perfumery, P1 — quipu)
Quipu flags P0: bridges directionality (symmetric vs. directed) is undefined, making the "community neighborhood" triage term unimplementable consistently. Perfumery flags the same edge at P1: bridges lacks temporal activation structure (immediate vs. sequential revelation), corrupting Hermes V2 combinatorial sequencing. Both fixes are additive: add `symmetric: bool` declaration and `activation_delay: enum` to the bridges edge schema in D6.

## Highest-Signal Single Finding

**fd-isnad-chain-integrity P0-2: Semantic dedup conflates embedding similarity with source independence.**

The Phase 3 dedup pass populates `same-as {confidence, method}` but has no mechanism to distinguish mutawatir convergence (five independent sources arriving at the same framing) from ahad-da'if near-duplication (one LLM batch producing text that embeds near a validated lens). A triage query that follows same-as edges to inherit tier will grant tier-1 status to LLM-generated lenses without any chain-of-custody check. This is silent and automatic — it happens during a routine Phase 3 run, not during an explicit merge operation. It directly undermines the MVP value proposition (triage lift) by corrupting the tier signal that selection ranking depends on.

## Recommended Sequencing for Epic D1 Scoping

Before the Schema + DDL step (Epic item 1) closes, these decisions need to be locked:
1. **bridges directionality** (P0 — quipu) — cannot write DDL without it
2. **same-as source_independence + corroborator_count fields** (P0 — isnad) — must be in schema, cannot be retrofitted
3. **schema_version column on all entities** (P0 — sibu / P2 — noh) — migration 001 must include it
4. **Evidence strength_grade** (P0 — isnad) — one new column, must be in initial DDL

Before Phase 4 (flux-drive triage view), these must be resolved:
5. **ontology-queries canonical module** (P0 — noh) — triage view is the iemoto reference; must be built as a module, not a one-off query
6. **Auraken bridge_score → bridges.strength transform** (P1 — quipu) — Phase 2 decision that determines whether Phase 4 triage formula works at all
7. **same-as → candidate-same-as demotion** (P0 — isnad, P1 — perfumery) — Phase 3 algorithm change
