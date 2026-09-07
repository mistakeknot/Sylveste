### Findings Index
- P0 | MIS-01 | "Epic shape #2: Ingestion pipeline" | "Idempotent" is asserted without specifying the idempotence key — second run will create duplicates under the likely default (filename- or content-derived node ID)
- P1 | MIS-02 | "Epic shape #2 + D4 Source" | ID strategy for fd-agents uses filename implicitly; files get renamed/retired — stable ID must come from frontmatter or content hash, not path
- P1 | MIS-03 | "D4 + D6 derives-from + D8 interlens adapter" | Source-of-truth precedence between Auraken lenses.json (which already extracted from flux-review-ep11) and fd-agents is undefined — both may claim the same lens
- P1 | MIS-04 | "Epic shape #2 2-week estimate" | Partial-failure replay is not addressed — mid-run importer failure at 300/660 leaves graph inconsistent; no transaction boundary specified
- P2 | MIS-05 | "Epic shape #2" | Post-ingestion audit is undefined — record counts are weak; the real check is relationship completeness (every lens has derives-from, every fd-agent has wields)
- P2 | MIS-06 | "Open Questions: Deprecation policy + Epic shape #2" | 660 fd-agents include dead-end experiments; ingestion policy for "retired" entries is undefined (skip? ingest with status? soft-delete post-ingest?)
- P3 | MIS-07 | "Epic shape #2" | Dry-run mode is not listed but is the industry standard safety net for first-run ingestion
Verdict: risky

## Summary

Three importers without explicit idempotence keys, ID strategies, source-of-truth rules, and partial-failure recovery is a recipe for a corrupted graph on second run. The brainstorm asserts "Idempotent" as a property but does not specify the mechanism — which is where every real-world ingestion bug lives. This review demands concreteness on five specific points before Epic shape #2 starts. None of the fixes are expensive; all of them are blocking.

## Issues Found

### 1. [P0] "Idempotent" asserted without specifying the key — MIS-01

**File:** `docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md`, Epic shape #2 line 91.

"Three importers (fd-agents .md parser, Auraken lenses.json loader, interlens JSON loader). Write to graph with `source` relationship recording origin. Idempotent." The word "idempotent" is doing a lot of work here. Idempotent on what key? Three plausible implementations:

(a) Upsert by content hash — first run creates, second run updates matching hash (true idempotence, but small edits create new nodes).
(b) Upsert by filename / JSON key — first run creates, second run overwrites matching key (idempotent on re-ingest, but filename drift breaks identity).
(c) Append-only with no dedup — second run creates duplicates. Not idempotent at all.

The brainstorm does not say. The default when an engineer says "I'll make it idempotent" and doesn't pre-specify is usually (c) plus a post-hoc dedup pass. For this pipeline, (c) is catastrophic: second run creates 1200 duplicates which the next week's semantic dedup pass then tries to cluster — and succeeds at matching duplicates to their originals at cosine 1.0, populating `same-as` edges that look meaningful but are actually re-ingest artifacts.

**Failure scenario:** Sprint 1 completes Epic shape #2 successfully. 1200 nodes in the graph. Sprint 2 ingests three newly-generated fd-agents. The importer runs in "refresh" mode (easiest to test). Result: 1200 duplicated nodes + 3 new nodes. Next dedup pass silently merges duplicates via `same-as`, hiding the bug. Three sprints later someone notices the graph has 2400 nodes when they expected 1200. Recovery requires re-ingesting from scratch — erasing any manual edits or dedup review work.

**Smallest fix:** Epic shape #2 must specify:
- Idempotence key per importer (recommended: stable frontmatter `name` for fd-agents, explicit JSON `id` for Auraken/interlens).
- Upsert semantics: MERGE on key, update properties if content hash differs, do not create a new node.
- A test that proves it: run the importer twice in succession; assert node count unchanged and properties match the second run's input.

This belongs in the plan-step, not discovered during execution.

### 2. [P1] fd-agent filename is not a stable ID — MIS-02

**File:** same brainstorm, §"Today's fragmentation" line 21, Epic shape #2 line 91.

"fd-* agents — 660 invokable reviewer personas in `.claude/agents/`." Files named like `fd-ontology-schema-discipline.md`. The obvious idempotence key is filename. But:
- Files get renamed (e.g., `fd-age-cypher-query-economics` got rename-conflicted earlier; I saw `fd-ontology-schema-discipline.md` AND `fd-ontology-schema-evolution.md` coexist in the agents dir — potential rename survivors).
- Files get retired (deleted when superseded).
- Filenames are kebab-case conversions of the persona title; a title edit renames the file.

Using filename as the node ID means: rename causes ingest to create a new node (old one orphaned) OR an update pointed at the wrong node (if rename detection isn't done).

**Failure scenario:** A user renames `fd-ontology-schema-discipline.md` to `fd-ontology-schema.md` (shortening). Next import run sees a "new" file and creates a new node. The old node is still there with no backing file. wields edges point to whichever the importer resolved to — probably the new node, so the old one becomes a ghost. Worse: the old node has the history (`valid_from`, any manual edits, incoming edges from other ingestion rounds); the new node is fresh.

**Smallest fix:** Use the frontmatter `name` field as the primary ID (if it exists; add it if not). Content hash as a secondary: if a file has no stable `name`, hash the role definition text (not the whole file; task_context is volatile). Renames become a metadata-only update. Add a linter check that every fd-agent file has a `name:` in frontmatter.

### 3. [P1] Source-of-truth precedence is undefined — MIS-03

**File:** same brainstorm, §"Today's fragmentation" lines 20-23, D4 line 59, D8 line 80.

Auraken lenses.json already says "Already extracted from flux-review outputs (source field: `flux-review-ep11`)." So some lenses in Auraken were extracted from fd-agent outputs. When ingestion runs:
- The fd-agent importer creates a Lens node from the fd-agent's implicit lens.
- The Auraken importer creates a Lens node that already claimed extraction from the same source.

Both are loading "the same lens" but from different representations. Which wins on property conflicts? Auraken has `effectiveness_score`, `bridge_score`, `community_id` — fields fd-agent doesn't have. fd-agent has the full review question set — Auraken has a distilled `questions` field. A naive "last-write wins" loses information either way.

**Failure scenario:** Ingest order is {fd-agents, Auraken, interlens}. fd-agent creates Lens with its fields. Auraken upserts and blanks out fd-agent-specific fields (or leaves them but Auraken's fields overwrite where they overlap). Users editing via /flux-gen write to fd-agent; users editing effectiveness_score write to Auraken. Next ingest, who wins?

**Smallest fix:** Define source precedence in the plan:
- For lens fields: Auraken is source-of-truth for `effectiveness_score`, `bridge_score`, `community_id`. fd-agent is source-of-truth for review questions + persona pairing. interlens is source-of-truth for dialectic triads.
- Implementation: per-field provenance (each property stores `{value, source, ingested_at}`). Cross-source updates only overwrite within their owned fields.
- Alternative simpler: pick one source as primary per type, treat others as read-only enrichments merged into properties with distinct names (`fd_agent_questions` vs `auraken_questions`).

The precedence rule must be written before any importer code exists.

### 4. [P1] Partial-failure replay is not addressed — MIS-04

**File:** same brainstorm, Epic shape #2 line 91.

"~2 weeks" for three importers. At 660 fd-agents + 291 Auraken + 288 interlens = ~1239 entities, each ingest might run for 10-30 minutes (especially if embeddings are computed inline). What happens if the importer dies at 300/660?

Options:
(a) Single transaction — all-or-nothing. But a 660-node transaction in AGE is risky (locks, WAL pressure, long-running tx).
(b) Per-entity transactions — crashes leave graph in a 300/660 state. Resume logic must detect what's already ingested and skip.
(c) Checkpointed batches — resumable from last checkpoint.

**Failure scenario:** Importer dies at 300/660 due to OOM or a single malformed frontmatter. (a): rollback, retry, hits same bad record, dies again. (b): 300 loaded, 360 not; resume must know the state. (c): clean resume but needs explicit checkpoint code.

Without specification, the default will be (b)-without-resume: importer dies, nobody knows exact state, manual SQL to check, probably truncate-and-retry loses any partial work.

**Smallest fix:** Specify in plan: per-entity transactions with a manifest log. Each importer writes to a `ingestion_log` table: `(run_id, source, entity_id, status={loaded, failed}, attempted_at)`. Resume logic reads the log, skips loaded, retries failed. This is 50 lines of code but eliminates the "half-ingested graph" recovery scenario.

### 5. [P2] Post-ingestion audit is undefined — MIS-05

**File:** same brainstorm, Epic shape #2 line 91.

"Idempotent" covers re-runs. It does not cover "did we get everything on the first run?" Record count comparison is weak — 660 fd-agents in, 660 nodes out, but did each node get its `wields` edge? Its `in-domain` edges? Its `derives-from` Source?

**Failure scenario:** First ingest succeeds by row count. Three weeks later, a triage query returns no personas — because `wields` edges were never populated due to a parser bug that silently swallowed frontmatter errors.

**Smallest fix:** Define post-ingestion audit queries as a deliverable of Epic shape #2:
- Every Lens has >= 1 `derives-from` Source
- Every Persona has >= 1 `wields` Lens
- Every node has >= 1 `in-domain` edge
- Source distribution matches expectation (e.g., 660 fd-agents → 660 Source-linked nodes, give or take retired entries)
- Orphan detection: nodes with no incoming or outgoing edges except to Source

Commit these queries to the repo. Run them as part of Epic #2's acceptance.

### 6. [P2] Retired-experiment policy for 660 fd-agents — MIS-06

**File:** same brainstorm, §"Today's fragmentation" line 20, Open Questions §"Deprecation policy" line 106.

"660 fd-agents include dead-end experiments." Ingestion must decide whether to load all 660 or filter. If all 660: the graph is bloated with experimental personas that nobody wields anymore, and triage finds them. If filtered: by what rule? Filename pattern? Tier=retired? Last-used date?

**Failure scenario:** Ingestion loads all 660. Triage queries now match retired experimental personas for diffs; recommendations include "fd-quantum-zebra-feedback-loop" (a made-up example) because its generated-at-domain tag happens to match. Users dismiss the recommendation, trust in triage erodes.

**Smallest fix:** Before ingestion, do a tier sweep of fd-agents. Add `tier: retired` to any agent with `use_count: 0` and `generated_at > 30 days ago`. Ingestion filters to `tier != retired` for triage-eligible personas; retired personas are still ingested (for provenance and history), but get a `status: retired` property that triage queries filter on. This respects D7's "respects the cultural richness" principle while preventing noise.

## Improvements

### 1. Build a dry-run mode — MIS-07

Every importer should support `--dry-run` that reports what would be created, updated, skipped — without writing. First production run of each importer should always be dry-run-first, diff the report against expectations, then real-run. 100 lines of code, prevents an entire category of incident.

### 2. Version each importer

Importers will evolve. Record `importer_version` as a property on each ingested node. This lets future maintainers identify "these nodes were ingested by v1.0 of fd-agents-importer, which had the bug where task_context was mis-escaped" and run a targeted cleanup.

### 3. Ingestion observability

`ingestion_log` table (from MIS-04) plus Grafana panel showing: rows/sec, error rate, per-source progress. Non-optional for a 2-week sprint that ingests >1200 entities; essential for debugging.

--- VERDICT ---
STATUS: fail
FILES: 0 changed
FINDINGS: 7 (P0: 1, P1: 3, P2: 2, P3: 1)
SUMMARY: "Idempotent" asserted without specifying the key, ID strategy, source-of-truth precedence, or partial-failure replay. All five gaps must be resolved in the plan step — not during execution. The fixes are cheap; skipping them risks a corrupted graph on second run.
---
<!-- flux-drive:complete -->
