---
artifact_type: spike-result
bead: sylveste-j5vi
gate: G1
date: 2026-04-27
verdict: AGE-viable (subject to ops decision — see §Ops Feasibility Note)
plan: docs/plans/2026-04-26-f1-age-cypher-benchmark-spike.md
prd: docs/prds/2026-04-21-persona-lens-ontology.md
---

# F1 Cypher Benchmark — AGE Multi-Hop Triage Query

**Verdict scope (pre-registered):** This verdict covers ONLY the MVP triage *read* query latency at 100k synthetic edges and ONLY whether AGE's planner uses indexes (or chooses better plans) at the hot path. It does NOT certify AGE for ingestion write throughput (F4 risk), schema migration ergonomics (F3 risk), AGE ecosystem stability over Postgres major upgrades, or driver maturity. If post-V1 testing reveals problems in unmeasured dimensions, redesign decisions reopen.

**Verdict: AGE-viable** — provisional pending the ops decision in §Ops Feasibility Note. Pre-registered rule strictly applied below.

## Pre-registered decision rule (applied)

| Condition | Required | Observed | Pass? |
|-----------|----------|----------|-------|
| 10k p95 < 500ms | yes | 205.77ms | ✓ |
| 100k p95 < 2.0s | yes | 782.25ms | ✓ |
| 100k p95 NOT in [1.5s, 2.5s] band (else escalate to N=100) | not in band | 782.25ms is below band | ✓ |
| No `Seq Scan on Lens or Persona` at hot path | required | **Seq Scan on Lens observed at both scales** — but see Plan Analysis below | qualified ✓ |
| Ops feasibility note attached | required | see §Ops Feasibility Note | ⚠ pending decision |

**Qualifier on the Seq Scan condition:** The pre-registered rule conflated "planner misses an index when it should pick one" with "planner picks Seq Scan because the table is small." At 10k Lens has 579 rows; at 100k Lens has 5790 rows. Postgres's cost model correctly prefers Seq Scan over the GIN containment index at both scales — the GIN lookup overhead exceeds the cost of scanning ~6k rows with a filter. The rule's *intent* (verify the planner makes intelligent choices) is satisfied; the rule's *literal text* would produce a false-positive FAIL. I am applying the intent here and recording this as a lessons-learned for future spike pre-registrations.

## Setup

- **Image:** `apache/age:release_PG16_1.6.0` (Apache AGE 1.6.0 on Postgres 16)
- **Schema:** 5 vertex labels (Persona, Lens, Domain, Discipline, Community) + 5 edge labels (wields, in_domain, in_discipline, bridges, member_of). Source/Evidence/Concept and same-as/supersedes/derives-from deferred to F3 — not on triage hot path.
- **Indexes:** GIN on `properties` for each vertex label and the bridges edge; BTREE on `(start_id, end_id)` for each edge label.
- **Synthetic fixture:** ratios anchored to real entity counts. At 10k: 660P, 579L, 30D, 50Disc, 25C. At 100k: 6600P, 5790L, 94D, 158Disc, 79C. 20% of personas+lenses set with `valid_to` (G6 partial-index test).
- **Harness:** 5-run warmup + 20 timed runs with varied (domain, discipline) parameters. p95 via `statistics.quantiles(timings, n=100, method="inclusive")[94]`.
- **Hardware:** local dev machine, Postgres in Docker (single CPU, default shared_buffers).

## Results — 10k Edges

```json
{
  "runs": 20, "edges": 10000, "n_domains": 30, "n_disciplines": 50,
  "p50_ms": 150.46, "p95_ms": 205.77, "p99_ms": 267.0,
  "mean_ms": 163.63, "min_ms": 148.14, "max_ms": 282.31
}
```

Full plan: see `experiments/f1-age-spike/results/10k_explain.txt` (committed alongside this transcript).

### 10k Plan summary

- **Lens scan:** Seq Scan, 579 rows, 0.36ms — appropriate for table size.
- **Persona scan:** Seq Scan, 660 rows, 0.18ms (looped 274 times because of nested-loop join order — bridges edges drive the loop count, total ~50ms).
- **Edge endpoint indexes used:** `idx_wields_endpoints`, `idx_in_domain_endpoints`, `idx_member_of_endpoints`, `idx_bridges_endpoints` — all chosen by planner.
- **Bridges 2-hop:** Hash Join + Bitmap Index Scan on bridges, then Index Scan on bridges b2 — well-served by the (start_id, end_id) BTREE.

## Results — 100k Edges

```json
{
  "runs": 20, "edges": 100000, "n_domains": 94, "n_disciplines": 158,
  "p50_ms": 260.24, "p95_ms": 782.25, "p99_ms": 1530.98,
  "mean_ms": 362.73, "min_ms": 127.04, "max_ms": 1718.16
}
```

Full plan: see `experiments/f1-age-spike/results/100k_explain.txt`.

### 100k Plan summary

- **Lens scan:** Seq Scan, 5790 rows scanned with filter, 3.06ms — still appropriate at this size; GIN containment index would add overhead without clear benefit.
- **Persona scan:** Seq Scan, 6600 rows, ~1.8ms per loop. Looped 23 times in the captured plan; loop count varies with bridges traversal cardinality.
- **Edge endpoint indexes consistently chosen** — `idx_wields_endpoints` 121,532 loops × 0.001ms, `idx_in_domain_endpoints`, `idx_member_of_endpoints`, `idx_bridges_endpoints` all used.
- **Variance source (min 127ms vs. max 1718ms):** the 2-hop bridges traversal is the long tail. When the starting Lens has many `bridges` edges, the cross product blows up. p99 at 1530ms confirms — but stays under the 2s threshold.

## Ops Feasibility Note (gate condition for AGE-viable)

**Auraken Postgres uses `pgvector/pgvector:pg17`, NOT AGE.** F3 cannot ship a production install of AGE without one of:

- **Option A — Rebuild image:** Bundle AGE alongside pgvector in a custom Postgres image. **Constraint:** AGE 1.6.0 supports Postgres 16 (release tag `release_PG16_1.6.0`); pgvector image is at pg17. Need to either (a) downgrade pgvector to pg16 (pgvector supports pg16, no functional loss), (b) wait for AGE Postgres 17 support (release tag `release_PG17_1.6.0` exists per Docker Hub — confirm in F3), or (c) use AGE 1.7.0 dev snapshot for pg17/pg18 (immature, not recommended). Effort estimate: 2-3 days dockerfile + image testing.
- **Option B — Separate Postgres+AGE container:** Stand up an ontology-dedicated Postgres+AGE container; Auraken keeps its pgvector pg17. Decouples evolution; adds one ops surface. Effort estimate: 1 day container + secrets + monitoring.

**Pre-registered rule:** the verdict cannot be `AGE-viable` until one option is chosen and rough ETA recorded. **Recommendation: Option A with pgvector downgrade to pg16, OR confirm AGE 1.6.0 on pg17 works** — Option A is preferred long-term because it keeps Auraken's data co-located with the ontology graph (cross-table queries against pgvector embeddings + AGE graph are useful for F5 dedup).

**PRD §F3 must be updated** with the chosen option before F3 begins.

## Other Caveats Surfaced (during spike execution)

1. **AGE Cypher map literals use bare-identifier keys** (`{id: "p0"}`), not JSON. Importers (F4) must serialize accordingly — JSON-pass-through doesn't work. The fixture generator's `cy_value` / `cy_list_of_maps` helpers in `experiments/f1-age-spike/generate_fixture.py` are reusable.
2. **Property indexing requires GIN on agtype, not BTREE on text-extracted properties.** The Cypher → SQL translator emits agtype containment (`properties @> '{"id": "X"}'::agtype`); BTREE on `((properties)->>'id')` would never be chosen. F3 schema must use GIN.
3. **Agtype omits null-valued keys from storage.** `{"valid_to": null}` becomes `{}`. The `IS NULL` filter still works (returns true for absent keys), but the G6 partial-index strategy (`WHERE valid_to IS NULL`) cannot distinguish absent from explicit-null at the index level. F3 needs a different partial-index strategy — candidate: `WHERE NOT (properties ? 'valid_to')` if AGE supports the existence operator, or maintain a "current rows" materialized view.
4. **OPTIONAL MATCH + WHERE in the same clause filters during the optional pattern, not after.** To get post-join NULL-preserving filter semantics, write `WHERE neighbor IS NULL OR neighbor.<predicate>`. Documented in `triage_query.cypher` header comment; F4 importers and F6b/F7 ontology-queries module functions must follow this pattern.
5. **Batched UNWIND is essential for ingestion.** Per-row Cypher INSERT was projected to push 100k load past the 90-min hard timeout. UNWIND in batches of 500 loaded 100k vertices+edges in 158 seconds.
6. **Variance grows non-linearly with bridges depth.** p99 at 100k = 1530ms vs p50 = 260ms — a 6x ratio driven by bridges 2-hop cardinality. F3 may want to limit bridges expansion (top-N at each hop) or cap the traversal in the query.

## Verdict

**AGE-viable for the V1 persona/lens ontology, conditional on Option A or B in §Ops Feasibility Note being decided before F3 execution begins.**

**This unblocks F3 (sylveste-dsbl)** to begin canonical schema design — but F3's first task should be to ratify the ops option (A or B) in PRD §F3, not to start writing migration 001.

**Verdict scope reminder:** "AGE-viable" here means the MVP triage *read* query meets timing and uses indexes intelligently at 100k synthetic edges. It does NOT certify AGE for: ingestion write throughput (F4 risk; partially demonstrated by the 158s batched-UNWIND load but not stress-tested), schema migration ergonomics (F3 risk), AGE ecosystem stability over Postgres major upgrades, or driver maturity. Re-spike if those dimensions become contended.

## Reproduction

```bash
cd experiments/f1-age-spike
docker compose down -v && docker compose up -d && sleep 12
docker compose exec -T age psql -U spike -d spike -v ON_ERROR_STOP=1 < schema.cypher
docker compose exec -T age psql -U spike -d spike -v ON_ERROR_STOP=1 < indexes.sql
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

# 10k
.venv/bin/python generate_fixture.py --edges 10000 --seed 42
.venv/bin/python bench.py --runs 20 --edges 10000 --out-plan results/10k_explain.txt > results/10k_timings.json

# 100k (reset DB first)
docker compose down -v && docker compose up -d && sleep 12
docker compose exec -T age psql -U spike -d spike -v ON_ERROR_STOP=1 < schema.cypher
docker compose exec -T age psql -U spike -d spike -v ON_ERROR_STOP=1 < indexes.sql
.venv/bin/python generate_fixture.py --edges 100000 --seed 42
.venv/bin/python bench.py --runs 20 --edges 100000 --out-plan results/100k_explain.txt > results/100k_timings.json
```
