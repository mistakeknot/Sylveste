---
date: 2026-04-27
bead: sylveste-9gn9
relates: [sylveste-46s, sylveste-b1ha, sylveste-r3jf]
verdict: subsume
naming: lattice
---

# Lattice Reconciliation — interweave (sylveste-46s) ⊃ persona-lens-ontology (sylveste-b1ha)

## Verdict

**Subsume.** The persona-lens-ontology epic (`sylveste-b1ha`) is reframed as **persona/lens type-family extensions to interweave**, the existing 87%-shipped catalog-of-catalogs ontology layer. The unified system is renamed **lattice**. Apache AGE / Postgres / Cypher are dropped from the architecture; SQLite + named templates (interweave's existing engine) are used instead. F1 (Cypher benchmark, already shipped with verdict AGE-viable) becomes orphan research evidence — kept on disk, decoupled from the epic's critical path.

## Evidence

### What interweave actually shipped

Read 2026-04-27 from `core/interweave/` and `interverse/interweave/` (sibling clones, independent .git, no external consumers in the Sylveste tree):

- **Storage:** SQLite via stdlib `sqlite3` (`storage.py`, 209 LOC). Zero deps, zero ops surface.
- **Engine:** 5 type families (Artifact, Process, Actor, Relationship, Evidence) × 7 interaction rules (`engine.py`, 65 LOC; `families.py`; `rules.py`).
- **Identity crosswalk:** File + function level via tree-sitter (`crosswalk.py`, `resolve_file.py`, `resolve_function.py`, `detect_renames.py`).
- **Connectors:** beads, cass, tldr_code (`connectors/`, with `connector.py` defining `Connector`, `HarvestMode`, `HarvestResult`, `ObservationContract`).
- **Named templates:** 8 shipped (entity_relationships, entity_timeline, evidence_for_entity, related_artifacts, session_actors_for_file, session_entities, bead_context, actor_activity), with `protocol.py` defining `QueryTemplate` ABC + `QueryResult` typed contract + registry.
- **Auxiliary modules:** `gravity.py` (gravity-well safeguards), `salience.py` (query-context salience), `harvest.py`, `diagnostics.py`, `worker.py`.
- **Tests:** 8+ test files, all canonical features covered.

Total: ~6,542 Python LOC + 1,664 Go LOC. `pyproject.toml` uses `uv`, `pytest`, `ruff`. Plugin manifest at `interverse/interweave/.claude-plugin/plugin.json`.

### What persona-lens-ontology PRD asks for

From `docs/prds/2026-04-21-persona-lens-ontology.md`:

| PRD requirement | interweave coverage |
|---|---|
| 7 typed entity types (Persona, Lens, Domain, Discipline, Source, Evidence, Concept) | ✅ 5 generative families absorb all 7: Persona→Actor, Lens/Source/Domain/Discipline/Concept→Artifact subtypes, Evidence→Evidence |
| Typed relationships (wields, bridges, supersedes, same-as, derives-from, in-domain, in-discipline, cites, references) | ✅ map onto Stewardship (wields), Lifecycle (supersedes), Structure (in-domain, in-discipline, references), Evidence Production (cites, derives-from), Annotation (bridges, same-as) |
| "Single canonical query authority" (G5) — adapters consume; never reimplement | ✅ named templates + registry are exactly this pattern |
| Identity UUIDs + supersedes for Lens/Persona (G8) | ✅ Lifecycle rule + crosswalk |
| Evidence `strength_grade` + transmitter chain (G7, G9) | ⚠️ partial — Evidence family exists; grade/transmission_method are added metadata |
| `bridges` directed/activation_delay/strength (G4) | ⚠️ added metadata on Annotation rule |
| `same-as` curator promotion + source_independence (G3) | ⚠️ existing `candidate-*` patterns; curator CLI is new |
| Three importers (fd-agents markdown, Auraken JSON, interlens JSON) | ❌ new connectors required (but pattern is shipped — beads/cass/tldr_code show the recipe) |
| Apache AGE / Postgres / Cypher / 2-hop traversal at p95 < 2s on 100k edges | ❌ **rejected** — interweave deliberately chose SQLite + bounded named templates over open-ended Cypher (AGENTS.md: "named templates with bounded traversal, not open-ended graph language") |
| 1239 entries (660 + 291 + 288) ingested | ✅ trivially within SQLite scale |

### Why AGE was the wrong tool

The PRD's case for AGE rested on three claims, all of which dissolve under inspection:

1. **"Graph-shaped queries need a graph DB."** False at this scale. 1239 nodes with 2-hop traversal is a 1.5M-edge worst case — SQLite recursive CTEs handle this in milliseconds. AGE's overhead (Postgres + extension + Cypher learning curve) is unjustified.

2. **"interlens already implies a graph."** True, but the implication is satisfied by *any* relational store with named queries — which is what interweave ships. The graph shape is in the data model, not the storage engine.

3. **"Reuses Auraken's Postgres."** This is actually an *anti*-argument: Auraken is mid-pivot to Hermes overlay (`project_auraken_hermes_pivot.md`). Adding AGE migration during that pivot stacks risk. SQLite has zero ops surface and zero pivot-coupling.

The recent commit `492f1ddf` ("F1 AGE Cypher benchmark spike — verdict AGE-viable") shipped F1 as research. **Keep the artifact, drop the dependency.** The F1 verdict tells us AGE *could* work; it doesn't tell us AGE is *required*. interweave's design demonstrates it isn't.

### Why interweave's design wins

The catalog-of-catalogs principle ("if you delete interweave, everything still works") is not just a slogan — it's a load-bearing architectural commitment. Persona/lens ingestion under AGE would have written 1239 nodes into a graph that *owns* the data, violating the catalog principle and creating a second source of truth. Under interweave, fd-agents stay in `.claude/agents/*.md`, Auraken lenses stay in `apps/Auraken/src/auraken/lens_library_v2.json`, interlens lenses stay in `interverse/interlens/apps/api/all_lenses_for_analysis.json`. interweave indexes; the markdown/JSON remain canonical.

This is the right answer to the PRD's "three persona/lens stores already exist and are drifting" problem — the drift is a *catalog* problem, not a *data unification* problem. Pulling everything into AGE solves the wrong thing.

## What lattice means concretely

- **Plugin name:** `lattice` (renames `interweave`). Architecture name can stay "interweave" internally if rename cost is high, but the plugin/CLI/MCP surface is lattice.
- **Plugin home:** `interverse/lattice/` (renamed from `interverse/interweave/`). Resolve `core/interweave/` duplicate as part of the rename.
- **F2 (sylveste-r3jf) becomes:** "Add persona/lens entity-type extensions to lattice + run domain/discipline overlap audit." Concretely:
  - Audit (workstream a) unchanged in spirit: read fd-agent frontmatter `domains` (across `apps/*/.claude/agents/fd-*.md`, ~781 files) + Auraken `discipline` (291 lenses), produce overlap matrix, recommend collapse-or-keep, write to `docs/research/f2-domain-discipline-audit.md`.
  - Scaffold (workstream b) replaced by: register persona/lens/domain/discipline/source entity types in lattice's `families.py`; add metadata fields to relationship rules (`bridges.directed/activation_delay/strength`, `same_as.source_independence/corroborator_count`, `evidence.strength_grade`); document persona/lens type catalog as an extension to AGENTS.md. **No new package created.**
- **F3 (sylveste-dsbl) collapses dramatically:** SQLite migration in lattice's existing `storage.py` adds the new entity-type rows + relationship metadata columns. From "1.5 weeks AGE+DDL" to "2-3 days schema extension."
- **F4 (sylveste-t2cs) stays scope-equivalent:** three new lattice connectors (fd_agents.py, auraken_lenses.py, interlens.py), each implementing `Connector` protocol. Existing connector tests show the pattern. Idempotence keys, manifest log, dry-run — all already in connector framework.
- **F5 (sylveste-71nz) unchanged:** calibration corpus, embedding choice, candidate-same-as → curator promotion. Lives in `lattice/dedup/` rather than `ontology-queries/dedup/`. G3 discipline survives.
- **F6a (sylveste-2n8i) unchanged:** pre-registration + 30-diff held-out corpus + A/B harness. G10 commit-before-code discipline survives.
- **F6b (sylveste-g939) simplified:** flux-drive backend swap targets lattice's named templates (e.g., `selectPersonaeForTask` becomes a new template), not a new ontology-queries module. A/B unchanged.
- **F7 (sylveste-1j30) clarified:** interlens MCP server dispatches through lattice's existing template registry. This is the *first* external consumer of lattice — proves the catalog-of-catalogs design with a real user.

### Effort delta

| Feature | PRD estimate | Lattice estimate |
|---|---|---|
| F1 (Cypher benchmark) | 1w | 0 (already done as research, drop from critical path) |
| F2 (audit + scaffold) | 1w | 0.5w (audit) + 0.5w (type extension) |
| F3 (Schema/DDL) | 1.5w | 0.3w (SQLite extension) |
| F4 (Ingestion) | 2w | 1.5w (3 connectors via existing protocol) |
| F5 (Dedup) | 1.5w | 1.5w (unchanged) |
| F6a (Pre-reg) | 1w | 1w (unchanged) |
| F6b (Backend swap) | 1.5w | 1w (lattice template registration) |
| F7 (interlens adapter) | 1w | 0.5w (lattice template dispatch) |
| **Total** | **10.5w** | **~6w** |

~40% reduction, primarily from F1 + F3 collapse. F5 and F6a are the same regardless of storage — calibration discipline doesn't care about SQLite vs AGE.

## PRD revisions required

1. **Drop §Solution paragraph 1** ("Apache AGE on Postgres ... seven typed object types"). Replace with "extends `lattice` (the renamed interweave catalog) with persona/lens type extensions."
2. **Drop F1 from feature list.** Move to `docs/research/f1-cypher-benchmark/` as standalone research.
3. **Rewrite F2 acceptance criteria** to target lattice extension + audit, not new-package scaffold.
4. **Rewrite F3 acceptance criteria** to target SQLite migration + relationship metadata, not AGE migration 001.
5. **Update F4** to reference lattice's `Connector` protocol.
6. **Update F6b/F7** to reference lattice's template registry.
7. **Drop §Dependencies entries** for "Apache AGE extension" and "Auraken Postgres schema stability."
8. **Add §Dependencies entry** for "lattice rename from interweave (low-risk — no external consumers)."
9. **Update §Open Questions** "Plugin home" — answered: lattice plugin replaces interweave.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| SQLite scale ceiling if 1239 grows to 100k+ entries | Bounded named templates already enforce this discipline; if scale demands change, migrate to Postgres without changing query API |
| Interweave's 87% bead status overstates maturity | No external consumers means no breakage risk from extension; persona/lens becomes the first real consumer (which is the point) |
| `core/interweave/` vs `interverse/interweave/` duplication | Resolve as part of rename: keep `interverse/lattice/`, delete `core/interweave/` |
| Auraken pivot still imposes coordination cost | Lower than AGE alternative — no shared Postgres, no schema coupling |
| F1 Cypher work feels "wasted" | It isn't — verdict (AGE-viable) is durable research. Future graph workloads can reach for it; this epic doesn't need it. |

## Recommended next moves

1. Update PRD per the §PRD revisions list above (errata block + section rewrites).
2. Update bead descriptions for F2-F7 to reflect lattice framing.
3. Rename `interverse/interweave/` → `interverse/lattice/`. Delete `core/interweave/`. Update `.claude-plugin/plugin.json`, `pyproject.toml` package name, all import paths.
4. Resume F2 (sylveste-r3jf) under the lattice framing — audit workstream first, type-extension workstream second.
5. Close sylveste-9gn9 with this doc as the artifact.
