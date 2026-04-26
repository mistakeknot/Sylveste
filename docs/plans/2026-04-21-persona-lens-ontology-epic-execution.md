---
artifact_type: plan
bead: sylveste-b1ha
stage: plan
plan_type: epic-execution
prd: docs/prds/2026-04-21-persona-lens-ontology.md
brainstorm: docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md
---

# Epic Execution Plan — Persona/Lens Ontology (sylveste-b1ha)

This sprint scopes the epic — detailed per-child implementation plans are written in each child's own sprint via `/route`. This doc covers **sequencing, parallelization, lane strategy, and abandon-branch handling** across the 8 feature beads.

## Dependency DAG

```
            ┌────────────────────────┐
            │ sylveste-b1ha (epic)    │
            └────┬─────────┬─────────┘
                 │         │
         ┌───────▼──┐  ┌───▼──────┐
         │ F1 j5vi  │  │ F2 r3jf  │       (P1 · parallel, 1 week each)
         │ Benchmark│  │ D/D +    │
         │ spike    │  │ module   │
         └─────┬────┘  └──┬──┬────┘
               │          │  │
               └─────┬────┘  │
                     │       │
                ┌────▼───────┐│
                │ F3 dsbl    ││             (P1 · 1.5 weeks · GATES G3,G4,G6,G7,G8,G9)
                │ Schema+DDL ││
                └─────┬──────┘│
                      │       │
                ┌─────▼───────┴─┐
                │ F4 t2cs        │           (P1 · 2 weeks · GATES G2,G9)
                │ Ingestion      │
                └────┬──────┬────┘
                     │      │
                ┌────▼──┐   │
                │ F5    │   │                (P1 · 1.5 weeks · GATE G3 full)
                │ 71nz  │   │
                │ Dedup │   │
                └───┬──┬┘   │
                    │  │    │
      ┌─────────────┘  │    │
      │                │    │
      │   ┌────────────▼────▼────┐
      │   │ F6a 2n8i              │          (P1 · 1 week · GATE G10 commit)
      │   │ Pre-reg + corpus       │
      │   └───────────┬───────────┘
      │               │
      │   ┌───────────▼───────────┐
      │   │ F6b g939               │          (P1 · 1.5 weeks · GATES G5,G10 execute)
      │   │ Backend + A/B + decide │
      │   └────────────────────────┘
      │
   ┌──▼──────────┐
   │ F7 1j30      │                           (P2 · 1 week · GATE G5 adapter)
   │ interlens MCP │
   └───────────────┘
```

**Dependency edges** (beyond every child → epic):
- F3 ← F1, F2
- F4 ← F3
- F5 ← F4
- F6a ← F2
- F6b ← F2, F5, F6a
- F7 ← F2, F5

## Critical Path

**Critical path:** F1 → F3 → F4 → F5 → F6b = 1 + 1.5 + 2 + 1.5 + 1.5 = **7.5 weeks** of serial work.

**Total individual effort:** ~10.5 weeks (sum of all beads). Parallelization collapses to 7.5 weeks on a single dedicated lane. With moderate interleave (50% lane), expect **15-18 elapsed weeks** to epic close.

## Parallelization Opportunities

| Window | Ready work | Notes |
|--------|-----------|-------|
| Weeks 1-1.5 | F1 ‖ F2 | Both depend only on epic. F2 is actually 1 week but has two workstreams (audit + scaffold); assign one dev per workstream for ~0.5w each, or serialize. |
| Weeks 4-5 (during F4) | F6a can start as soon as F2 closes | F6a only depends on F2 — it's a pre-registration + corpus task, no backend code. Start it when lane has slack during F4's 2 weeks. |
| Weeks 7-9 (after F5) | F7 ‖ F6b | F7 depends on F2+F5; F6b depends on F2+F5+F6a. They're independent consumers of `ontology-queries`. Run in parallel; F7 is shorter. |

**No opportunities for parallelizing F3 or F4** — both are single large pieces of schema/ingestion work that must complete before downstream consumers.

## Lane Strategy

Recommend a **single dedicated "ontology lane"** for at least F1→F5 (schema + ingestion + dedup, weeks 1-6). This is the work where context continuity pays: DDL decisions in F3 affect F4 importers; F5 dedup calibration touches the same schema. Switching dev context in-lane costs re-learning the graph structure each time.

After F5 ships, lane can split:
- Ontology lane continues with F6a → F6b (measurement + A/B)
- Adapter lane (1 dev) takes F7 in parallel (~1 week)

If interleaved with other work (not dedicated), expect the critical path to stretch 2-3x but gain capacity for other Sylveste epics.

## Gate Checkpoints (non-negotiable — epic fails review if any is elided)

| Gate | Feature | Checkpoint artifact |
|------|---------|---------------------|
| **G1** Cypher benchmark viable | F1 | `docs/research/f1-cypher-benchmark/…-transcript.md` — if p95 > 2s at 100k edges, F1 closes `redesign-required`, epic **blocks** at F3 until redesign |
| **G2** Ingestion idempotence | F4 | Regression test (second-run stable count) in CI |
| **G3** same-as curator + source_independence | F3 (schema), F5 (workflow) | DDL includes candidate-same-as edge; F5 CLI curator tool |
| **G4** bridges fully specified | F3 | DDL header comments document transform |
| **G5** Canonical query authority | F2 (scaffold), F6b (consume), F7 (adapter) | `packages/ontology-queries/` semver 0.1.0; no re-implementation in flux-drive/interlens |
| **G6** schema_version + partial index | F3 | Migration 001 |
| **G7** Evidence strength_grade | F3 | Migration 001 enum |
| **G8** Lens immutable + supersedes | F3 | DDL + supersedes edge type |
| **G9** Transmission chain | F3 (schema), F4 (populate) | DDL Transmission nodes; F4 importers write chains |
| **G10** Measurement pre-registration | F6a (commit-before), F6b (execute) | Pre-reg doc committed BEFORE F6b code |
| **G11** D/D audit | F2 | Audit report with collapse-or-keep recommendation |

## Abandon-Branch Handling

**F1 abandon (AGE non-viable):** Epic blocks at F3. Redesign child bead filed. Strategy options: (a) denormalize hot path + reduced hops; (b) reconsider AGE vs. Neo4j despite ops cost; (c) reshape the query itself (fewer hops, precomputed materialized view). F2 (scaffold + audit) continues regardless — it's AGE-independent work.

**F6b abandon (triage lift insufficient):** Per Epic DoD #1, all F1-F7 children closing is **necessary but not sufficient** — F6b abandon-branch records DoD #1 NOT MET and epic **reopens as redesign**. Don't close the epic; file a follow-up scoping sprint evaluating: redesign the selection logic, expand the corpus, change the primary metric, or reconsider whether the ontology approach provides triage value at all.

**F5 dedup catastrophic (e.g., > 5000 candidate-same-as edges):** Not an abandon — a scope expansion. F5 bead expands to include batch-review tooling; estimate extends from 1.5w to 2.5-3w; F6b start delayed. Document in F5's dry-run report and update `sylveste-b1ha` epic state.

**F2 D/D audit "keep separate" outcome:** Not an abandon, but a DDL shape shift. If G11 audit finds < 30% Domain/Discipline overlap and recommends keeping both types distinct (current PRD assumption), F3 proceeds unchanged. If audit recommends collapse (> 30% overlap), F3 DDL gains `kind: enum[informal-tag, formal-field]` on a single merged type and importers in F4 gain a derivation rule. Either outcome is a green light — the gate is "explicit decision in PRD errata," not "must collapse."

**F4 ingestion idempotence unachievable on real data shape:** If the second-run regression test reveals that one of the three importers cannot achieve stable node count (e.g., fd-agent filename renames are more frequent than expected, breaking `name`-based keys), F4 expands to include content-hash ID migration. This is importer-specific redesign, not an epic abandon. Estimate adds 0.5-1w; F5 start delayed accordingly.

**F7 MCP adapter gap (tool not expressible via `ontology-queries`):** If an interlens MCP tool cannot be implemented as a composition of `ontology-queries` functions, the tool is surfaced as a **module gap** per G5 — NOT reimplemented in interlens. Module gap gets a follow-up bead under the epic (or V2, depending on triage); F7 closes with the implementable subset. If > 3 tools surface as gaps, F7 re-scopes as "module expansion + adapter" and extends by 1 week.

## Session Boundary Strategy

Per the user's ADHD + many-parallel-projects context (`user_adhd_many_projects.md`): every child bead gets its own sprint via `/route` or `/sprint --from-step=3`. Durable anchors — not session continuity — carry the work forward.

- **Start next session with:** `bd ready` — F1 and F2 will be the top two unblocked P1s.
- **Use `/route`** per child to dispatch the appropriate workflow (likely `/sprint` for F1 C3/C4, possibly `/work` for F2 audit which is C2).
- **Pick up per-child plans** at their sprint's Step 3 — detailed implementation belongs there, not here.

## Handoff

When this sprint ships (Step 10), epic `sylveste-b1ha` remains **in_progress** with 8 open children. Subsequent work picks up via `/route` on each child bead. This plan is the map; per-child plans are the turn-by-turn directions.
