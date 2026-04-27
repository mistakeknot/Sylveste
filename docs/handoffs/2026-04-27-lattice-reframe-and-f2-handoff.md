---
date: 2026-04-27
session: bc6d6268
topic: lattice-reframe-and-f2-handoff
beads: [sylveste-9gn9, sylveste-sk5s, sylveste-w8zv, sylveste-ukd3, sylveste-r3jf, sylveste-b1ha, sylveste-46s]
artifact: docs/research/2026-04-27-lattice-reconciliation.md
---

## Session Handoff — 2026-04-27 lattice reframe + F2 ready

### Directive

> Resume **F2 (sylveste-r3jf)** under the lattice framing. Start with workstream (a) — the domain/discipline audit. Read the bead's notes (recently updated) for full scope, then read the lattice reconciliation diff doc and the PRD errata block. Workstream (b) — type extensions in `interverse/lattice/src/lattice/families.py` — runs after (a)'s collapse-vs-keep verdict lands.

The F2 audit has a **known-good shape** now:
- Script: `interverse/lattice/scripts/audit_domains.py` (Python, reuses lattice's `uv` stack; one small dep `python-frontmatter` is fine)
- Inputs: fd-agent frontmatter (`apps/*/.claude/agents/fd-*.md`, ~781 files), Auraken `apps/Auraken/src/auraken/lens_library_v2.json` (291), interlens `interverse/interlens/apps/api/all_lenses_for_analysis.json` (288)
- Analysis: lexical only (token-set Jaccard + edit distance + set overlap). **No embeddings** — those belong to F5 per G3 calibration commitment.
- Outputs: `docs/research/f2-domain-discipline-audit.json` (canonical, web-consumable schema) + `docs/research/f2-domain-discipline-audit.md` (rendered from JSON)
- JSON schema designed for downstream consumption by lattice-web V0 (sylveste-ukd3, blocked on this F2)

### What landed in this session

1. **Reconciliation verdict (sylveste-9gn9, closed)** — interweave (sylveste-46s, 87% shipped) and persona-lens-ontology (sylveste-b1ha, PRD'd 2026-04-21) reconciled as SUBSUME. The unified system is renamed **lattice**. AGE/Postgres/Cypher dropped; SQLite + named templates retained. Diff doc: `docs/research/2026-04-27-lattice-reconciliation.md`. Effort estimate ~10.5w → ~6w.

2. **Plugin renamed (local scope) — `interverse/interweave/` → `interverse/lattice/`.** Python package, plugin manifest, pyproject, CLAUDE.md, AGENTS.md updated; 215 tests passing under `lattice.*` imports. `core/interweave/` duplicate clone deleted (verified no unique work). Commit `894e401` pushed to `mistakeknot/interweave` upstream — github repo rename is deferred to **sylveste-w8zv (P2)** along with go.mod module path + cmd/internal/ Go imports + cosmetic docstring stragglers.

3. **PRD errata block added** to `docs/prds/2026-04-21-persona-lens-ontology.md` — explicitly supersedes the AGE/Cypher §Solution paragraph and lists every section that's now stale. Original PRD body preserved below the errata for historical context.

4. **Bead notes added on F1 + F2 + F3 + F4 + F5 + F6a + F6b + F7 + epic** — every bead in the persona-lens-ontology family carries the lattice-reframing pointer.

5. **Process-gate bead (sylveste-sk5s, P1)** filed — "Add shipped-state reconciliation gate to /clavain:strategy and PRD authoring flows." This is the systemic fix so the next PRD doesn't repeat the failure mode of authoring without checking shipped epics.

6. **Naming locked across outcomes** — memory `project_lattice_naming.md` records that "lattice" is the chosen name regardless of subsume/supersede/orthogonal verdict on 9gn9.

7. **Web view decided (sylveste-ukd3, P2)** — lattice-web V0 lives at `interverse/lattice/web/` (colocated with lattice plugin), V0 scope is static browse + search (no bridges viz), built **after** F2 audit completes. Meadowsyn was ruled out — its identity is runtime-ops (Cybersyn × Flightradar24), not structural catalog. interlens-web stays interlens's. lattice-web is a peer.

### Dead Ends

- **`bd update --release` flag doesn't exist.** When releasing a claim, just `bd update <id> --status open`. The `--claim` flag is symmetric for *acquiring*; release is a status revert.
- **Mock.patch() string paths bypass the import system.** When renaming a Python package, `git mv` + import-statement rewriting isn't enough — `unittest.mock.patch("package.X")` strings need a separate sed pass on `<oldname>.` → `<newname>.`. Same risk applies to Go imports (string-quoted paths) when sylveste-w8zv runs.
- **`uv`/Python venvs have absolute paths embedded.** Moving the directory after `mv` requires `rm -rf .venv` + `uv sync` to rebuild. Cheap but easy to miss.
- **`clavain-cli set-artifact <type>` warns on "unknown type"** — the registry has a fixed allowlist (`plan`, `prd`, `brainstorm`, etc.). For ad-hoc artifacts like reconciliation diff docs, just use `--notes` on the bead instead, or use `plan` as the closest fit.
- **`bd create` from outside `.beads/` workspace fails** — must `cd /home/mk/projects/Sylveste` first or set `BEADS_DIR`. The route command's discovery worked because it was already in cwd; explicit bead creation in subdirectories does not.

### Context

- **Lattice's design wins because the persona/lens problem is small data.** 1239 entries across all three sources is trivial for SQLite + recursive CTEs. AGE/Cypher overhead was unjustified. The PRD's "graph DB needed" framing came from the brainstorm's Palantir-style ambition, not the actual scale requirement.
- **Lattice has zero external consumers as of 2026-04-27.** Confirmed via grep across the entire Sylveste tree. Persona/lens becomes lattice's *first* real consumer, which is the point — F1-F7 of interweave were built waiting for exactly this.
- **The catalog-of-catalogs principle is load-bearing.** Lattice never owns entity data. Markdown stays in `.claude/agents/`, JSON stays where it is. Lattice indexes; doesn't replicate. PRD's "ingest 1239 entries into the graph" framing violated this principle and would have created a second source of truth.
- **F1 (sylveste-j5vi) Cypher benchmark already shipped** as research per commit `492f1ddf` with verdict AGE-viable. The verdict is durable; the dependency is not. Future graph workloads that need open-ended Cypher can reach for it; this epic doesn't.
- **The 11 gates G1-G11 survive the storage swap.** Only the implementation surface migrates from AGE-specific clauses to relational columns + relationship metadata on lattice's existing rules. Calibration discipline (G3, G10), schema versioning (G6), evidence grading (G7), immutability via supersedes (G8), transmission chain (G9) are all storage-engine-agnostic.
- **Auraken pivot tension reduced.** Original PRD wanted to ride Auraken's Postgres for AGE; that stacked risk against the Hermes overlay pivot. SQLite has zero coupling to Auraken — risk mostly removed.
- **interlens stays interlens.** v2.2.4 is marketplace-published; brand is real. F7 (sylveste-1j30) migrates only the backend (interlens MCP dispatches through lattice's named templates); the frontend at `interverse/interlens/apps/web/` is left alone. lattice-web is a peer surface, not a replacement.
- **Meadowsyn is runtime ops, not catalog.** Read its CLAUDE.md, PRD, synthesis. It's "public audience watching an autonomous factory" — Cybersyn × Flightradar24 — with three-layer display (ambient WebGL + FIDS ribbon + interactive panels). Data sources are factory-status, beads, cass, tmux. Wrong design language and wrong content for lattice's structural catalog. Two distinct surfaces of the broader Sylveste system.
- **F5 curator UI is CLI, not web.** PRD F5 acceptance criterion #6 specifies `ontology-queries-curator review-candidates` as terminal tool. The lifecycle argument that "lattice-web eventually needs writeable backend" is weaker than I initially framed — V2/V3 may still grow that way, but it's not on F5's critical path.

### Open beads in lattice family (priority order)

| Bead | Pri | Title | Status |
|---|---|---|---|
| sylveste-r3jf | P1 | F2: D/D audit + module scaffold (lattice extension) | OPEN, ready |
| sylveste-dsbl | P1 | F3: Schema + DDL (now SQLite migration in lattice) | OPEN, blocked on F1+F2 |
| sylveste-t2cs | P1 | F4: Ingestion (3 lattice connectors) | OPEN, blocked on F3 |
| sylveste-71nz | P1 | F5: Semantic dedup + curator CLI | OPEN, blocked on F4 |
| sylveste-2n8i | P1 | F6a: Pre-registration + held-out corpus | OPEN, blocked on F2 |
| sylveste-g939 | P1 | F6b: flux-drive backend swap + A/B | OPEN, blocked on F2+F5+F6a |
| sylveste-1j30 | P2 | F7: interlens MCP adapter swap | OPEN, blocked on F2+F5 |
| sylveste-sk5s | P1 | Process gate: PRD authoring reconciliation step | OPEN |
| sylveste-w8zv | P2 | github upstream rename + go.mod | OPEN |
| sylveste-ukd3 | P2 | lattice-web V0 (static browse + search) | OPEN, blocked on F2 |

### What this session did NOT do

- Did not run F2 audit. That's the next session's job.
- Did not rename github upstream. Tracked at sylveste-w8zv; do that separately when ready.
- Did not update Go module path or cmd/interweave/ Go imports. Same.
- Did not push the Sylveste root commit (handoff + PRD errata + memory update). Session-close protocol handles this.
- Did not write the lattice-web V0 itself — bead is filed and blocked, work begins after F2 audit lands.
