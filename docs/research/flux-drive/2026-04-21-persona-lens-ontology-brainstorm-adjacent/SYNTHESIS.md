# Flux-Drive Review — Persona/Lens Ontology Brainstorm (Adjacent Domain Track)

**Input:** `/home/mk/projects/Sylveste/docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md`
**Mode:** review, adjacent-domain specialist track
**Date:** 2026-04-21
**Output directory:** `docs/research/flux-drive/2026-04-21-persona-lens-ontology-brainstorm-adjacent/`

## Triage

Five Project Agents (newly generated for this track) dispatched as Stage 1, all scored 8/8:

| Agent | Focus | Verdict |
|---|---|---|
| fd-ontology-schema-discipline | 7-type distinctness, identity vs. versioning | warn |
| fd-age-cypher-query-economics | AGE Cypher feasibility, AGE-vs-Neo4j perf gap | fail |
| fd-semantic-dedup-calibration | Embedding model, thresholds, calibration corpus | warn |
| fd-triage-lift-measurement | Metric commitment, baseline freeze, cost confound | warn |
| fd-multi-store-ingestion-safety | Idempotence, ID strategy, source-of-truth, replay | fail |

No Stage 2; per-user instruction, these five were the designated heavy lifters. No complementary project agents pulled in — the five fully cover the adjacent-domain spectrum.

## Findings Tally

**Total: 30 findings across 5 agents**

| Severity | Count | Agents |
|---|---|---|
| P0 | 2 | fd-age-cypher-query-economics (MVP query plannability), fd-multi-store-ingestion-safety (idempotence key unspecified) |
| P1 | 11 | All five agents |
| P2 | 13 | All five agents |
| P3 | 4 | Four agents |

## Cross-Cutting Themes

### 1. Commitment-before-execution is the dominant gap

Four of five agents (schema, dedup, measurement, ingestion) independently converged on the same structural issue: the brainstorm lists choices without committing. "Idempotent" without a key. "Embedding-based" without a model. "Measurable lift" without a metric. "Bi-temporal via timestamps" without a partial-index strategy. These are not brainstorm-level gaps — they are plan-level commitments that the strategy + write-plan steps must lock in before children beads get filed.

### 2. Two P0s are about the load-bearing MVP promise

- **ACQ-01** (query economics): The MVP Cypher query — "domain × discipline × effectiveness × community neighborhood" — is not concretely plannable from the brainstorm. AGE's known weak spot is multi-hop traversal; community neighborhood requires it. A week-1 benchmark spike is a hard prerequisite.
- **MIS-01** (ingestion safety): "Idempotent" asserted without key specification; default implementation will create duplicates on second run, which the dedup pass will then mask with false `same-as` edges.

Both P0s point at the same root cause: aspirational language in the brainstorm being treated as if it were specified behavior.

### 3. Schema commitments pervade everything

Two P1s (OSD-01 Domain/Discipline overlap, OSD-02 Lens identity-vs-versioning) touch every downstream child. Identity semantics determine whether `wields` edges point to stable IDs or version-specific nodes — that decision reshapes ingestion, dedup, and triage queries. Resolve in strategy step, not during execution.

### 4. Measurement discipline is the credibility floor

TLM-01 through TLM-06 all point at one thing: the MVP promises "measurable triage lift" without the pre-registered machinery that makes the measurement trustworthy. A 1-page pre-registration (primary metric, frozen baseline SHA, 30-diff held-out corpus, paired analysis, cost-per-finding as secondary) is cheap and non-negotiable.

## Recommended Strategy-Step Actions

Before filing children beads under `sylveste-b1ha`, resolve these five gates:

1. **Identity model** (OSD-02): Commit to immutable Lens + `supersedes` + `lens_identity_uuid`, or explicitly document the mutation alternative.
2. **MVP query benchmark spike** (ACQ-01): Week-1 child — load synthetic 10k-edge graph, EXPLAIN ANALYZE the actual proposed triage query, decide AGE-viable vs. redesign-required before Epic shape #4 begins.
3. **Ingestion contract** (MIS-01/02/03/04): Specify idempotence key per importer, stable ID source (frontmatter `name` not filename), per-field source-of-truth precedence, per-entity transactions with manifest log.
4. **Dedup calibration sub-phase** (SDC-01): Split "Semantic dedup pass" into 3a (calibration: model, 50-pair labeled set, threshold) and 3b (run). Embed essence text not raw records (SDC-04).
5. **Measurement pre-registration** (TLM-01/02/03): 1-page doc committing primary metric (recommended: review-coverage-per-diff), baseline SHA, 30-diff paired corpus, ship/abandon thresholds, cost-per-finding as secondary.

## What the Review Does NOT Cover

Per the adjacent-domain track scope, this review covers specialist technical depth. It does NOT cover:

- Strategic fit with Hermes pivot / Auraken roadmap (would be a cognitive-agent track — fd-decisions, fd-systems)
- User-product framing of the three views (fd-user-product)
- Security/trust implications of unified persona registry (fd-safety)
- Cross-model / cross-AI disagreement on the architecture (Oracle)

If the plan-step wants broader coverage, run a core-domain track with those agents.

## Output Files

- `fd-ontology-schema-discipline.md` — 7 findings (P1×3, P2×3, P3×1)
- `fd-age-cypher-query-economics.md` — 6 findings (P0×1, P1×2, P2×2, P3×1)
- `fd-semantic-dedup-calibration.md` — 6 findings (P1×2, P2×3, P3×1)
- `fd-triage-lift-measurement.md` — 6 findings (P1×3, P2×3)
- `fd-multi-store-ingestion-safety.md` — 7 findings (P0×1, P1×3, P2×2, P3×1)
- `SYNTHESIS.md` — this file

## Suggests

- `/interpeer:interpeer` — cross-AI second opinion on the schema commitments (Oracle not invoked this run)
- `/clavain:strategy` — the five gates above are strategy-step inputs
