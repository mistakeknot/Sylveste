---
artifact_type: prd
bead: sylveste-b1ha
stage: design
brainstorm: docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md
prior_art: docs/research/assess-ontology-stores-2026-04-21.md
review_synthesis: docs/research/flux-review/persona-lens-ontology-brainstorm/2026-04-21-synthesis.md
errata: docs/research/2026-04-27-lattice-reconciliation.md
reconciliation_bead: sylveste-9gn9
---

# PRD: Persona/Lens Ontology Unification (V1)

## ERRATA — 2026-04-27 Lattice Reconciliation

**This PRD was authored without reconciling against `interweave` (epic `sylveste-46s`), an 87%-shipped catalog-of-catalogs ontology layer that already implements the architecture this PRD proposed to build.** Per reconciliation bead `sylveste-9gn9` and diff doc `docs/research/2026-04-27-lattice-reconciliation.md`, the verdict is **SUBSUME**: persona/lens unification becomes type-family extensions to interweave, the unified system is renamed **lattice**, and Apache AGE / Postgres / Cypher are dropped from the architecture in favor of interweave's existing SQLite + named-template engine.

**Superseded sections (read the lattice reconciliation doc for current intent):**
- §Solution paragraph 1 (AGE/Postgres/Cypher framing) — lattice extends interweave's SQLite engine. The seven entity types map onto interweave's five generative type families (Artifact, Process, Actor, Relationship, Evidence). The "ontology-queries module" is replaced by registering new templates in lattice's existing template registry.
- §Success Metrics #1, #3, #4 file paths — `packages/ontology-queries/` paths become `interverse/lattice/` paths.
- §Success Metrics #2 entry count (660 + 291 + 288 = 1239) — actual fd-agent count is 781, not 660. Audit (F2) will produce the corrected total.
- **F1 (Cypher Benchmark Spike)** — already shipped as research per commit `492f1ddf` with verdict AGE-viable. Removed from epic critical path. Artifact retained at `docs/research/f1-cypher-benchmark/`.
- **F2 acceptance criteria** — workstream (a) audit unchanged in spirit; workstream (b) "scaffold ontology-queries package" replaced by "register persona/lens entity-type extensions in lattice's `families.py` + add relationship metadata fields to existing rules."
- **F3 acceptance criteria** — AGE migration 001 replaced by SQLite migration extending lattice's `storage.py`. Most AGE-specific clauses (Cypher, vertex labels, partial indexes on AGE) are dropped or simplified; gate-honored fields (G3 source_independence, G4 bridges metadata, G6 schema_version, G7 strength_grade, G8 lens_identity_uuid + supersedes via Lifecycle rule, G9 transmission chain) survive as relational columns + relationship metadata.
- **F4 acceptance criteria** — three importers become three new `Connector` implementations in lattice (`fd_agents.py`, `auraken_lenses.py`, `interlens.py`), following the existing connector protocol exemplified by beads/cass/tldr_code. Idempotence keys, manifest log, dry-run are connector-framework features lattice already ships.
- **F6b acceptance criteria** — flux-drive backend swap targets lattice's named templates (e.g., a new `select_personae_for_task` template), not a new ontology-queries module.
- **F7 acceptance criteria** — interlens MCP dispatches through lattice's existing template registry. interlens becomes lattice's first external consumer, validating the catalog-of-catalogs pattern.
- **§Dependencies** — drop "Apache AGE extension" and "Auraken Postgres schema stability." Add "lattice rename from interweave (low-risk — no external consumers in tree as of 2026-04-27)."
- **§Open Questions / Plugin home** — answered: lattice plugin replaces interweave at `interverse/lattice/`. No new top-level `packages/` directory is created.

**Effort delta:** ~10.5w (PRD original) → ~6w (lattice reframing). F1 + F3 collapse account for most of the savings; F5/F6a are unchanged because calibration discipline doesn't care about storage engine.

**The eleven gates G1-G11 remain non-negotiable.** They survive the storage change unchanged in intent — only the implementation surface migrates from AGE/Cypher to lattice's SQLite + named templates.

The remainder of this document below is preserved as-authored for historical context. **Read the errata first; treat the original §Solution as superseded.**

---

## Problem

Three persona/lens stores already exist and are drifting: 660 fd-* Claude Code subagent markdown files, 291 Auraken structured lenses, and 288 interlens MCP lenses. The same knowledge is encoded three times, with no cross-references, no canonical schema, and no graph semantics — even though Auraken's `bridge_score` and `community_id` fields plus interlens's `find_bridge_lenses` and `get_dialectic_triads` tools implicitly assume a graph. Within 18 months this drifts into three mutually-incompatible ontologies; new features (Hermes personality selection, flux-drive triage beyond filename-glob heuristics, public catalog) require a unified source of truth that does not exist.

## Solution

A Palantir-style object-first ontology graph backed by **Apache AGE on Postgres** (per `assess-ontology-stores-2026-04-21.md` — reuses Auraken's existing infrastructure, zero new ops surface), with **seven typed object types** (Persona, Lens, Domain, Discipline, Source, Evidence, Concept), **first-class typed relationships** (wields, bridges, supersedes, same-as, derives-from, in-domain, in-discipline, cites, references), and a **single canonical query module** (`ontology-queries`) that all views (flux-drive triage first, Hermes and catalog later) consume as adapters. V1 ships through the flux-drive triage view + interlens MCP adapter swap.

All eleven gates G1-G11 from the brainstorm revision (post flux-review closure of 9 P0s + 2 auxiliary findings) are non-negotiable commitments. Any feature that elides a gate fails plan review.

## Success Metrics (Epic Definition of Done)

Epic `sylveste-b1ha` succeeds when **all** of these hold, not merely when all children close:

1. **Triage lift is measured and positive.** Per G10, the pre-registered primary metric (review-coverage-per-diff on the 30-diff held-out corpus) shows ≥ 15% improvement at constant-or-lower cost-per-finding vs. frozen baseline SHA. Verification: `packages/ontology-queries/tests/ab-triage.test.ts` or equivalent runnable. **If F6b's A/B results in abandon-branch, this DoD criterion is recorded NOT MET and the epic reopens as redesign — all F1-F7 children closing is a necessary but NOT sufficient condition for epic closure.**
2. **All 660 + 291 + 288 = 1239 entries ingested.** Idempotent re-run produces identical node count. Verification: `bd show F4` acceptance artifact + regression test.
3. **Single query authority honored.** interlens MCP server's 16 lens tools (`search_lenses`, `find_bridge_lenses`, `get_dialectic_triads`, etc.) all execute via `ontology-queries` module, not via bundled JSON or reimplemented logic. Verification: `grep -r 'lenses.json' packages/interlens/` returns zero runtime reads post-F7.
4. **Graph health audit passes.** Post-ingestion + post-dedup: zero orphan nodes, every Lens has ≥ 1 `derives-from` chain to a Source, every `same-as` edge has `source_independence` set. Verification: `packages/ontology-queries/scripts/audit-graph.ts` reports clean.
5. **Gate artifacts exist.** Each of G1, G3, G6, G10 produces a committed artifact (EXPLAIN ANALYZE transcript, dedup calibration corpus, migration 001, pre-registration doc). Verification: files exist on disk at documented paths.

## Features

### F1: Cypher Benchmark Spike

**What:** Before any DDL is written, synthetically load 10k then 100k edges into AGE on a scratch database and `EXPLAIN ANALYZE` the MVP triage query (`Persona × Lens × Domain × Discipline match with effectiveness filter and 2-hop community neighborhood`). Decide AGE-viable vs. redesign.

**Acceptance criteria:**
- [ ] Scratch AGE instance provisioned; schema mirror (draft, not canonical) loaded with synthetic entities per G6 column layout
- [ ] At 10k edges: triage query p95 < 500ms, uses indexes (no full-table scan in EXPLAIN ANALYZE)
- [ ] At 100k edges: triage query p95 < 2s, uses indexes for the hot path (bridges traversal can be slower if documented)
- [ ] EXPLAIN ANALYZE transcript for both scales committed to `docs/research/f1-cypher-benchmark/2026-MM-DD-transcript.md`
- [ ] If 100k query p95 > 2s OR query planner shows seq scans on entity tables: feature closes as **redesign-required**, epic blocks at F3 until redesign (denormalize hot path, reduce hops, or reconsider AGE)
- [ ] No production tables touched

**Estimated effort:** 1 week
**Gates honored:** G1
**Priority:** P1

### F2: Domain/Discipline Audit + `ontology-queries` Module Skeleton

**What:** Two parallel workstreams in one bead. (a) Audit existing `domains` values across 660 fd-agents + `discipline` values across 291 Auraken lenses to decide the collapse-vs-keep decision for V1 schema (G11). (b) Scaffold the versioned `ontology-queries` package (empty function stubs, semver 0.1.0, CI, docs) so F3 DDL and F6 triage view have a real module to target (G5).

**Acceptance criteria:**
- [ ] Audit script written (Python or TypeScript) that reads frontmatter from `.claude/agents/fd-*.md` and `auraken-web/data/lenses.json`; outputs overlap matrix + embedding-similarity stats
- [ ] Audit report written to `docs/research/f2-domain-discipline-audit.md` with explicit recommendation: collapse to one type OR keep separate
- [ ] Decision ratified in PRD errata (update this doc's `## Solution` if collapse decided)
- [ ] `packages/ontology-queries/` scaffold: `package.json` (v0.1.0), TypeScript strict mode, empty typed exports for `selectPersonaeForTask`, `expandByBridges`, `rankByEffectiveness`, `graphHealthAudit`, plus test harness
- [ ] README documents the adapter-not-reimplementer contract from G5
- [ ] CI wired: lint + typecheck + empty-suite green on main

**Estimated effort:** 1 week (can run parallel to F1)
**Gates honored:** G5 (scaffold), G11 (audit)
**Priority:** P1

### F3: Schema + DDL

**What:** Write migration 001 that creates the 7-entity ontology in AGE + Postgres with all gated fields locked in. Includes the relationship taxonomy, partial indexes, identity UUIDs, curator-promotion workflow stubs, and per-entity `schema_version` column.

**Acceptance criteria:**
- [ ] F1 verdict is `AGE-viable` (otherwise feature blocked until redesign lands)
- [ ] Migration 001 creates: Persona, Lens, Domain, Discipline, Source, Evidence, Concept (or collapsed Domain+Discipline per F2 verdict) as AGE vertex labels
- [ ] `bridges` edge has `directed: bool`, `activation_delay: enum[immediate, short, medium, long]`, `strength: float` per G4; documented `bridge_score → strength` transform in migration header comment
- [ ] `same-as` edge has `confidence: float`, `method: text`, `source_independence: bool`, `corroborator_count: int` per G3
- [ ] Every entity has `schema_version: semver`, `valid_from: timestamptz`, `valid_to: timestamptz nullable`, `lens_identity_uuid` (Lens) / `persona_identity_uuid` (Persona) per G6 + G8
- [ ] Partial index `WHERE valid_to IS NULL` on all entity tables
- [ ] `Evidence.strength_grade: enum[sahih, hasan, da'if, mawdu]` and `cites.transmitter_tier: int` per G7
- [ ] `Source` replaced with `Transmission` chain per G9: `Source —[transmitted_via]→ Transmission —[prior]→ Transmission`
- [ ] Lens and Persona are immutable on edit (G8): editing creates a new node with `supersedes` edge
- [ ] Curator-promotion workflow has at minimum a `candidate-same-as` edge type + `promote_candidate_same_as(edge_id, approved_by)` stored procedure stub
- [ ] Migration applies cleanly to a fresh Postgres + AGE instance in CI
- [ ] Rollback migration 001-down also written and tested

**Estimated effort:** 1.5 weeks
**Gates honored:** G3, G4, G6, G7, G8, G9
**Priority:** P1 (blocks F4)

### F4: Ingestion Pipeline

**What:** Three idempotent importers — fd-agents markdown parser, Auraken lenses.json loader, interlens JSON loader — that write to the AGE graph with explicit idempotence keys, per-entity transactions with a manifest log for partial-failure replay, dry-run mode, and a second-run regression test that proves stable node count.

**Acceptance criteria:**
- [ ] fd-agents importer uses frontmatter `name` as idempotence key; MERGE-on-key Cypher
- [ ] Auraken importer uses JSON `id` as idempotence key; MERGE-on-key Cypher
- [ ] interlens importer uses JSON `id` as idempotence key; MERGE-on-key Cypher
- [ ] All three importers record a `Transmission` node per G9 with `transmitter_tier`, `transmission_method`, `prior_transmission` (fd-agents → llm-extract upstream where applicable)
- [ ] Per-entity transactions with a `import_manifest` table logging `(importer, source_id, node_id, status, ts)`; resume-from-manifest logic tested
- [ ] Dry-run mode reports the would-change set (inserts/updates) without writing
- [ ] Cross-importer precedence rules documented: Auraken owns `effectiveness_score`, `bridge_score`, `community_id`; fd-agents own review questions + persona pairing
- [ ] Regression test: fresh DB, run each importer twice, assert (a) stable node count, (b) no cosine-1.0 same-as edges between self-and-self, (c) manifest log shows "idempotent-skip" on second run
- [ ] Post-ingestion audit query: every imported node has ≥ 1 `derives-from` Transmission chain ending at an origin Source

**Estimated effort:** 2 weeks
**Gates honored:** G2, G9
**Priority:** P1 (blocks F5 and F6)

### F5: Semantic Dedup with Calibration

**What:** Calibration-first dedup pass. Build a labeled corpus of ≥ 50 lens-pair judgments (same / similar / distinct); commit embedding model choice as artifact; calibrate thresholds for `candidate-same-as` emission; run the full pass; provide a CLI curator tool for promoting `candidate-same-as` → `same-as`.

**Acceptance criteria:**
- [ ] Embedding model committed to `packages/ontology-queries/dedup/model.json` (model id, version, dimension, API/local)
- [ ] Calibration corpus at `packages/ontology-queries/dedup/calibration-set-v1.jsonl` with ≥ 50 hand-labeled pairs across fd-agent×fd-agent, Auraken×Auraken, fd-agent×Auraken, interlens×others
- [ ] Thresholds committed as artifact: `candidate-same-as_min_cosine` (likely 0.75), `auto-similar-to_threshold` (below candidate but above random); justified from corpus precision/recall
- [ ] Dedup pipeline embeds essence-text only (definition + forces + solution); `task_context` stripped per G3
- [ ] Pipeline emits `candidate-same-as` only; never auto-promotes to `same-as`
- [ ] CLI curator tool (`ontology-queries-curator review-candidates`) shows side-by-side diff and allows accept (promote to `same-as` with `source_independence` bool), reject (demote to `similar-to`), or skip
- [ ] Post-dedup audit: `same-as` edges count + precision estimate from the calibration corpus reported in `docs/research/f5-dedup-report.md`
- [ ] Tier inheritance policy (G3): triage queries in F6 verify that `source_independence = true AND corroborator_count ≥ 2` before inheriting Evidence `strength_grade` via `same-as`

**Estimated effort:** 1.5 weeks
**Gates honored:** G3 (full curator workflow + calibration)
**Priority:** P1 *(corrected from P2 per PRD review — F6b A/B depends on F5 graph health)*

### F6a: Measurement Pre-registration + Held-Out Corpus

**What:** Mechanical enforcement of G10's commit-before-code ordering. Before F6b writes any triage backend code, commit the pre-registration doc, the labeled 30-diff held-out corpus, and the A/B harness scaffolding that can execute either backend.

**Acceptance criteria:**
- [ ] `docs/research/f6-measurement-preregistration.md` committed: primary metric (review-coverage-per-diff), secondary metrics (P0/P1 count, cost-per-finding, user-accepted-verdict-rate), baseline SHA frozen at F6a start, ship/abandon thresholds (ship: ≥ 15% primary lift at constant-or-lower cost-per-finding; abandon: < 5% or negative)
- [ ] 30-diff paired held-out corpus at `docs/research/f6-ab-corpus/` with ground-truth agent-selection labels; labels reviewed by at least one reviewer
- [ ] A/B harness scaffolding (without the new backend itself — just the runner that can execute either `legacy` or a yet-to-exist `ontology` backend and record findings/agents/cost per diff)
- [ ] Sign-off on pre-registration doc + corpus before F6b may begin (explicit gate — enforced by bead dependency)

**Estimated effort:** 1 week
**Gates honored:** G10 (mechanical commit-ordering enforcement)
**Priority:** P1

### F6b: flux-drive Triage Backend Swap + A/B Execution + Ship Decision

**What:** The MVP execution step — extract triage logic into `ontology-queries` module (G5), swap flux-drive's backend behind a feature flag, run the A/B against the frozen baseline on F6a's pre-registered corpus, apply pre-registered thresholds, bind the ship/abandon/redesign decision.

**Acceptance criteria:**
- [ ] Triage logic extracted into `ontology-queries` module (`selectPersonaeForTask` etc.) per G5 — no reimplementation in flux-drive
- [ ] flux-drive switches triage backend behind feature flag: `FLUX_DRIVE_BACKEND=ontology` vs. `legacy`
- [ ] A/B harness (from F6a) runs both backends over the corpus, records findings + agents dispatched + total cost per diff
- [ ] Primary metric (review-coverage-per-diff) computed and reported; secondary metrics recorded
- [ ] Ship decision memo at `docs/research/f6-ab-decision.md` applies F6a pre-registered thresholds; outcome binds
- [ ] If **ship**: flag default flips to `ontology`; DoD #1 MET
- [ ] If **abandon**: feature closes with findings documented; **Epic DoD #1 recorded NOT MET; epic reopens as redesign** (does not allow all children to close with epic "done")
- [ ] If **redesign**: feature reopens with explicit scope change; epic pauses until redesign lands

**Estimated effort:** 1.5 weeks
**Gates honored:** G5 (consumption), G10 (execution-after-pre-reg)
**Priority:** P1 (MVP milestone — the epic's primary measurable deliverable)

### F7: interlens MCP Adapter

**What:** Swap interlens MCP server's backend from bundled JSON to AGE queries via the `ontology-queries` module. Validates the adapter-over-module pattern in G5 with a real second consumer and proves the module is not flux-drive-specific. **Depends on F5 (graph health) and F2 (module scaffold) — NOT on F6b. F7 can run in parallel with F6a/F6b since the module's correctness is independent of flux-drive's A/B outcome.**

**Acceptance criteria:**
- [ ] interlens's 16 MCP tools (`search_lenses`, `find_bridge_lenses`, `get_dialectic_triads`, `get_lens_neighborhood`, etc.) all dispatch through `ontology-queries` module functions
- [ ] Zero runtime reads of bundled `lenses.json` in interlens post-F7 (verify: `grep -r 'lenses.json' packages/interlens/src/`)
- [ ] MCP tool contracts (input/output schemas) unchanged — no breaking changes to downstream consumers
- [ ] Per-query caching layer with invalidation tied to `ontology-queries` semver bump addresses ACQ-05 concern
- [ ] Contract tests on each of the 16 MCP tools: input fixture → expected output shape; pass against new backend
- [ ] Any tool that cannot be expressed as an `ontology-queries` function surfaces as a module gap for V2 (not a reimplementation — per G5, adapters don't reimplement)

**Estimated effort:** 1 week
**Gates honored:** G5 (validates adapter-over-module pattern)
**Priority:** P2

## Non-goals

- **Hermes conversational view** — deferred to V2. Must be an adapter over `ontology-queries` per G5 when built; any V2 design that reimplements selection logic fails plan review.
- **Public catalog browse surface** — deferred to V3 (auraken-web or a new surface). Same adapter requirement.
- **Fixative-triad schema** (perfumery Track C P1 distant finding) — V2. Revisit after F5 reveals whether triadic stabilization relationships are common in the real corpus.
- **Full jarh wa-ta'dil matrix on Lens credibility** — V1 applies the grading only to Evidence via G7. Lens-level credibility is V2.
- **TerminusDB auxiliary git-for-data versioning layer** — reassess in V2 if audit requirements grow.
- **Authoring UI** — V1 stays code-authored (markdown ↔ importer ↔ AGE) with CLI curator review per F5.
- **Automatic `same-as` without curator review** — prohibited by G3 across all V1 features.
- **Reimplementing selection logic in any view** — prohibited by G5; V2/V3 views are adapters.
- **Refining or retiring fd-agents** — ontology ingestion is additive; 660 fd-agents stay in `.claude/agents/`. Soft-retire via `tier: retired` is a post-V1 curation task.

## Dependencies

- **Apache AGE extension** installed in the existing Auraken Postgres instance (or a shared Sylveste ontology Postgres). Ops setup is part of F1 scratch env; production install decision in F3.
- **Auraken Postgres schema stability** — Auraken is pivoting to Hermes overlay (`project_auraken_hermes_pivot.md`, sylveste-heh8). Coordinate migration 001 timing with Auraken/Hermes team to avoid schema conflicts; confirm AGE coexists cleanly with pgvector and Auraken's existing tables.
- **interlens plugin** (v2.2.4) — F7 edits its MCP server. Confirm interlens maintainer is aware of backend swap; contract stability protects downstream plugin users.
- **Embedding model** — F5 commits a choice; if OpenAI API, confirm billing and rate limits; if local, confirm inference environment.
- **30-diff held-out corpus** — F6a needs real diffs with ground-truth agent-selection labels. Labeling is a ~2-hour human task; schedule before F6 day 1.
- **Sprint lane capacity** — total ~10-11 weeks on one focused lane. If interleaved, multiply by 2-3x. Strategic decision: allocate to a single lane (a "ontology lane") or interleave?

## Open Questions

These do NOT block epic execution but the write-plan step should surface them for each affected child:

- **Plugin home.** Does `ontology-queries` live in `interlens` (extended), a new `interontology` plugin, as a package under `auraken`, or as a standalone `packages/ontology-queries/` in the monorepo? Recommend standalone `packages/ontology-queries/` — plugin-agnostic, consumable by interlens (F7) and future Hermes/catalog views.
- **Curator promotion workload estimate.** G3's curator step may produce thousands of `candidate-same-as` edges on the first dedup run. F5 acceptance should include a dry-run estimate on a 100-entry sample before committing to the workflow; if > 500 candidates, design batch-review tooling in F5, not V2.
- **Hermes dependency gating.** F6b depends on flux-drive, F7 depends on interlens — both independent of Hermes. Confirm Hermes/Auraken team doesn't need Persona schema commitments this epic doesn't plan to make.
- **Embedding re-run policy.** If the embedding model version changes post-V1, how is the graph re-embedded and re-deduped without corrupting curator decisions? Defer to V2 but note now.

## Gates Index (cross-reference)

| Gate | Brainstorm | PRD feature |
|------|-----------|-------------|
| G1 Cypher benchmark | §Gated Decisions | F1 |
| G2 Ingestion idempotence keys | §Gated Decisions | F4 |
| G3 same-as curator + source_independence | §Gated Decisions | F3 (schema), F5 (calibration + workflow) |
| G4 bridges fully specified | §Gated Decisions | F3 |
| G5 Canonical query authority | §Gated Decisions | F2 (scaffold), F6b (consume), F7 (adapter) |
| G6 schema_version + partial index | §Gated Decisions | F3 |
| G7 Evidence strength_grade | §Gated Decisions | F3 |
| G8 Lens immutable + supersedes | §Gated Decisions | F3 |
| G9 Transmission chain | §Gated Decisions | F3, F4 |
| G10 Measurement pre-registration | §Gated Decisions | F6a (commit-before-code), F6b (execution) |
| G11 Domain/Discipline audit | §Gated Decisions | F2 |
