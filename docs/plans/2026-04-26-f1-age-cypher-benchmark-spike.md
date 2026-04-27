---
artifact_type: plan
bead: sylveste-j5vi
stage: design
prd: docs/prds/2026-04-21-persona-lens-ontology.md
brainstorm: docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md
prior_art: docs/research/assess-ontology-stores-2026-04-21.md
requirements:
  - F1: Cypher Benchmark Spike (gate G1)
---
# F1: Apache AGE Cypher Benchmark Spike — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:subagent-driven-development to implement this plan task-by-task. Spike work is exploratory — each task's output informs the next. Do not parallelize.

**Bead:** sylveste-j5vi
**Goal:** Decide whether Apache AGE on Postgres is viable as the storage backend for the persona/lens ontology by benchmarking the MVP triage query at 10k and 100k synthetic edges; commit EXPLAIN ANALYZE transcripts and a binding go/no-go memo.

**Architecture:** Scratch Docker container running `apache/age` Postgres image. Minimal schema mirroring the PRD's 7-entity ontology (sufficient for the triage query, not the full F3 DDL). Synthetic data generator with deterministic seeding. EXPLAIN ANALYZE harness runs the triage query N=20 times per scale, computes p50/p95, captures one full plan dump.

**Tech Stack:** Apache AGE on Postgres 16, Python 3 for fixture generation and harness (psycopg2 + Cypher string templating — no ORM, this is throwaway), Docker Compose for scratch DB.

**Prior Learnings:**
- `docs/research/assess-ontology-stores-2026-04-21.md` — AGE chosen over Neo4j (GPL), TerminusDB (separate service), Dgraph (schema-on-read), TypeDB (AGPL), Memgraph (BSL). Note: AGE has manual bi-temporal — `valid_from`/`valid_to` columns + query-side filtering, no native `AS OF` syntax.
- AGE Cypher driver maturity: Python via `psycopg2` + custom Cypher wrapper. No polished ORM; raw queries fine for spike.
- **Adjacent reality check**: `/home/mk/projects/auraken/docker-compose.yml` runs `pgvector/pgvector:pg17`, *not* AGE. The "reuses existing infra" framing is aspirational for V1 production; the spike provisions its own scratch container — surface this finding in the decision memo.

---

## Must-Haves

**Truths** (observable outcomes):
- A binding go/no-go decision is recorded with measured p95 numbers, not opinions.
- The triage query at 100k edges either uses indexes for the hot path (Persona×Lens×Domain×Discipline match) or is documented as not — the EXPLAIN ANALYZE plan is the evidence.
- The spike result is reproducible: another engineer can re-run the harness and get the same verdict (within stochastic variance).

**Artifacts** (files with specific contents):
- `docs/research/f1-cypher-benchmark/2026-04-26-transcript.md` — full EXPLAIN ANALYZE plans for 10k + 100k, p50/p95 timings, decision memo.
- `experiments/f1-age-spike/docker-compose.yml` — scratch AGE container.
- `experiments/f1-age-spike/schema.cypher` — minimal 7-entity AGE graph schema.
- `experiments/f1-age-spike/generate_fixture.py` — deterministic synthetic data generator.
- `experiments/f1-age-spike/triage_query.cypher` — the exact MVP triage query under test.
- `experiments/f1-age-spike/bench.py` — N=20 run harness, computes p50/p95.
- `experiments/f1-age-spike/README.md` — re-run instructions.

**Key Links**:
- Decision memo references the exact query file + harness output — no hand-edited numbers.
- Schema mirrors PRD's 7 entity types and the `bridges` / `same-as` / `derives-from` edge taxonomy from G3/G4 (subset sufficient for triage).
- Fixture generator's edge counts and entity counts produce a graph topology realistic for ~1239 entities (the actual ontology size) scaled up — not arbitrary uniform random.

---

## Non-Goals (Spike Discipline)

- **Not the F3 DDL.** Schema here is a sketch sufficient to run the triage query. F3 owns the canonical migration with all G3-G9 fields.
- **No ingestion pipeline.** Synthetic data only. Real importers are F4.
- **No production install of AGE.** F3 owns that decision and its rollback plan.
- **No semantic dedup, no curator workflow, no measurement pre-registration.** Those are F5/F6.
- **No tuning marathon.** If the first reasonable schema + index pass at 100k clears p95 < 2s, ship the verdict. If it fails, document the failure mode and recommend redesign — do *not* spend the week tuning.

---

## Pre-Registered Decision Rule (binding before any benchmark run)

This rule is committed in the plan **before** Task 7 executes. The executor applies it mechanically; no post-hoc reframing.

**Verdict states (pre-registered, exclusive):**

| State | Required conditions (ALL must hold) |
|-------|-------------------------------------|
| `AGE-viable` | (a) 10k p95 < 500ms, (b) 100k p95 < 2.0s, (c) EXPLAIN ANALYZE plan shows **no `Seq Scan` on `_ag_label_lens` or `_ag_label_persona`** at the hot path, (d) ops feasibility note attached: AGE installable on Postgres image used by F3 (Auraken's `pgvector/pgvector:pg17` or successor), or named alternative |
| `redesign-required` | Any of: (a) 100k p95 ≥ 2.0s, (b) 10k p95 ≥ 500ms, (c) Seq Scan on Lens or Persona at hot path, (d) ops infeasibility (cannot install AGE on the chosen production Postgres image) |
| `inconclusive — escalate` | 100k p95 in **[1.5s, 2.5s]** band → MUST rerun benchmark with N=100 (not N=20) before any verdict; only then re-apply the rule above |

**No `viable-with-caveats` outcome exists.** If results are borderline, the answer is "rerun N=100, then decide binary." Author judgment is bounded to plan inspection (which the rule already covers via the Seq Scan condition); it does not extend to redefining thresholds.

**Hard execution timeouts (also pre-registered):**

- 100k fixture load: kill at **90 minutes** wall clock; switch to UNWIND-batched generator and restart. Do not wait longer.
- Total spike wall clock: 1 week. If not done by Day 7, write whatever transcript exists with `verdict: incomplete` and file a follow-up bead — do not extend.

**Scope of the verdict (pre-registered):** "AGE-viable" means **only** that the MVP triage *read* query meets timing and uses indexes at 100k synthetic edges. It does NOT certify AGE for: ingestion write throughput (F4 risk), schema migration ergonomics (F3 risk), AGE ecosystem stability over Postgres major upgrades, or driver maturity. The decision memo MUST include this scope sentence verbatim.

---

## Task 1: Provision Scratch AGE Container ✓ DONE

**Files:**
- Create: `experiments/f1-age-spike/docker-compose.yml`
- Create: `experiments/f1-age-spike/init.sql`
- Create: `experiments/f1-age-spike/.gitignore`
- Create: `experiments/f1-age-spike/README.md`

**Step 1: Write docker-compose.yml**
```yaml
services:
  age:
    image: apache/age:release_PG16_1.6.0
    container_name: f1-age-spike
    environment:
      POSTGRES_PASSWORD: spike
      POSTGRES_USER: spike
      POSTGRES_DB: spike
    ports:
      - "5532:5432"
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
      - agedata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U spike"]
      interval: 3s
      timeout: 2s
      retries: 10
volumes:
  agedata:
```

**Step 2: Write init.sql**
```sql
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;
SELECT create_graph('ontology');
```

**Step 3: Write .gitignore**
```
# scratch — never commit volume contents
agedata/
*.local.sql
```

**Step 4: Bring up and smoke-test**
```bash
cd experiments/f1-age-spike
docker compose up -d
sleep 10
docker compose exec age psql -U spike -d spike -c "LOAD 'age'; SET search_path = ag_catalog, \"\$user\", public; SELECT * FROM ag_graph;"
```
Expected: one row showing graph `ontology`.

**Step 5: Commit**
```bash
git add experiments/f1-age-spike/docker-compose.yml experiments/f1-age-spike/init.sql experiments/f1-age-spike/.gitignore
git commit -m "spike(f1): scratch AGE container for benchmark"
```

<verify>
- run: `docker compose -f experiments/f1-age-spike/docker-compose.yml ps`
  expect: contains "Up"
- run: `docker compose -f experiments/f1-age-spike/docker-compose.yml exec -T age psql -U spike -d spike -c "SELECT name FROM ag_catalog.ag_graph;"`
  expect: contains "ontology"
</verify>

---

## Task 2: Define Minimal AGE Schema ✓ DONE

**Discovery:** AGE 1.6.0 names label tables as plain labels (e.g., `ontology."Persona"`), NOT `_ag_label_persona`. All Task 3 + harness code references must use the plain-label form.

**Files:**
- Create: `experiments/f1-age-spike/schema.cypher`
- Create: `experiments/f1-age-spike/apply_schema.sh`

The MVP triage query needs: Persona, Lens, Domain, Discipline, Community vertex labels + `wields` (Persona→Lens), `in_domain` (Lens→Domain), `in_discipline` (Lens→Discipline), `bridges` (Lens→Lens), `member_of` (Lens→Community) edge labels. Source/Evidence/Concept and `same-as`/`supersedes`/`derives-from` are deferred to F3 — not needed for triage timing.

**Step 1: Write schema.cypher**
```cypher
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

SELECT * FROM cypher('ontology', $$
  CREATE (:_label_marker {label: 'Persona'})
$$) AS (v agtype);

-- AGE auto-creates labels on first vertex insert; the marker call ensures
-- the table exists with predictable name (ontology._ag_label_persona, etc.)

SELECT * FROM cypher('ontology', $$
  CREATE
    (:Persona {id: 'seed-p'}),
    (:Lens {id: 'seed-l'}),
    (:Domain {id: 'seed-d'}),
    (:Discipline {id: 'seed-disc'}),
    (:Community {id: 'seed-c'})
$$) AS (v agtype);

-- Seed one of each edge label so AGE creates the edge label tables
-- before indexes.sql tries to reference them. Delete immediately after.
SELECT * FROM cypher('ontology', $$
  MATCH (p:Persona {id:'seed-p'}), (l:Lens {id:'seed-l'}),
        (d:Domain {id:'seed-d'}), (disc:Discipline {id:'seed-disc'}),
        (c:Community {id:'seed-c'})
  CREATE (p)-[:wields]->(l),
         (l)-[:in_domain]->(d),
         (l)-[:in_discipline]->(disc),
         (l)-[:bridges {strength: 0.5}]->(l),
         (l)-[:member_of]->(c)
$$) AS (v agtype);

-- delete seeds (CASCADE-style: AGE auto-deletes edges when both endpoints removed)
SELECT * FROM cypher('ontology', $$
  MATCH (n) WHERE n.id STARTS WITH 'seed-' DETACH DELETE n
$$) AS (v agtype);
```

**Step 2: Write apply_schema.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker compose exec -T age psql -U spike -d spike < schema.cypher
```

**Step 3: Apply and verify**
```bash
chmod +x experiments/f1-age-spike/apply_schema.sh
experiments/f1-age-spike/apply_schema.sh
docker compose -f experiments/f1-age-spike/docker-compose.yml exec -T age psql -U spike -d spike -c "\dt ontology.*"
```
Expected: 5 vertex label tables (`_ag_label_persona`, `_ag_label_lens`, `_ag_label_domain`, `_ag_label_discipline`, `_ag_label_community`) + 5 edge label tables (`_ag_label_wields`, `_ag_label_in_domain`, `_ag_label_in_discipline`, `_ag_label_bridges`, `_ag_label_member_of`) + 2 AGE meta-tables (`_ag_label_vertex`, `_ag_label_edge`) = 12 total.

**Step 4: Commit**
```bash
git add experiments/f1-age-spike/schema.cypher experiments/f1-age-spike/apply_schema.sh
git commit -m "spike(f1): minimal AGE schema for triage query"
```

<verify>
- run: `docker compose -f experiments/f1-age-spike/docker-compose.yml exec -T age psql -U spike -d spike -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'ontology' AND table_name LIKE '\_ag\_label\_%' ESCAPE '\';"`
  expect: contains "12"
</verify>

---

## Task 3: Add Indexes (G6) ✓ DONE

**Major discovery:** AGE 1.6.0's Cypher→SQL translator emits agtype **containment** filters (`properties @> '{"id":"X"}'::agtype`) for property predicates, NOT JSONB text-extraction. The plan-review's P1#1 was correct: BTREE on `((properties)->>'id')` would never be used. Switched to **GIN on `properties`** + **BTREE on (start_id, end_id)** for edge tables. Partial-index strategy for G6 deferred to F3 (agtype null-vs-absent semantics need investigation; not blocking the spike verdict).

**Files:**
- Create: `experiments/f1-age-spike/indexes.sql`
- Modify: `experiments/f1-age-spike/apply_schema.sh:1-10` (chain indexes after schema)

AGE stores vertex properties in a single `properties` agtype JSONB-like column. Indexes go on `(properties->'fieldname')` GIN/BTREE. The triage hot path needs lookups on `Persona.id`, `Lens.id`, `Domain.id`, `Discipline.id`, plus a partial index on `valid_to IS NULL` (G6).

**Step 1: Write indexes.sql**
```sql
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- BTREE on identity property for hash-style lookups
CREATE INDEX ON ontology."_ag_label_persona"
  USING BTREE (((properties)->>'id'));
CREATE INDEX ON ontology."_ag_label_lens"
  USING BTREE (((properties)->>'id'));
CREATE INDEX ON ontology."_ag_label_domain"
  USING BTREE (((properties)->>'id'));
CREATE INDEX ON ontology."_ag_label_discipline"
  USING BTREE (((properties)->>'id'));
CREATE INDEX ON ontology."_ag_label_community"
  USING BTREE (((properties)->>'id'));

-- Partial index for current rows only (G6 bi-temporal hot path)
CREATE INDEX ON ontology."_ag_label_lens"
  USING BTREE (((properties)->>'id'))
  WHERE (properties)->>'valid_to' IS NULL;

CREATE INDEX ON ontology."_ag_label_persona"
  USING BTREE (((properties)->>'id'))
  WHERE (properties)->>'valid_to' IS NULL;

-- Effectiveness filter (Lens.effectiveness_score numeric)
CREATE INDEX ON ontology."_ag_label_lens"
  USING BTREE ((((properties)->>'effectiveness_score')::float))
  WHERE (properties)->>'valid_to' IS NULL;
```

**Step 2: Add to apply_schema.sh after the schema apply**
```bash
docker compose exec -T age psql -U spike -d spike < indexes.sql
```

**Step 3: Apply**
```bash
docker compose -f experiments/f1-age-spike/docker-compose.yml exec -T age psql -U spike -d spike < experiments/f1-age-spike/indexes.sql
```

**Step 4: Verify indexes created**
```bash
docker compose -f experiments/f1-age-spike/docker-compose.yml exec -T age psql -U spike -d spike -c "\di ontology.*"
```
Expected: at least 8 indexes listed.

**Step 5: Commit**
```bash
git add experiments/f1-age-spike/indexes.sql experiments/f1-age-spike/apply_schema.sh
git commit -m "spike(f1): G6 partial indexes on identity + effectiveness"
```

<verify>
- run: `docker compose -f experiments/f1-age-spike/docker-compose.yml exec -T age psql -U spike -d spike -tAc "SELECT count(*) FROM pg_indexes WHERE schemaname = 'ontology';"`
  expect: contains "8"
</verify>

---

## Task 4: Synthetic Data Generator ✓ DONE

**Discoveries during execution:**
1. AGE Cypher uses bare-identifier map keys (`{id: "p0"}`), not JSON. Built `cy_value` / `cy_list_of_maps` serializers to emit Cypher map literals from Python dicts.
2. Per-row INSERT was projected to be too slow → batched UNWIND from start (BATCH=500), confirmed sub-second on 100 edges.
3. UNWIND batch infers column list from row[0]'s keys — must ensure every row has the same key set, including `null` placeholders.
4. **agtype omits null-valued keys from storage** — `{"valid_to": null}` becomes `{}`. The `IS NULL` filter still works (returns true for absent keys), but the G6 partial-index strategy (`WHERE valid_to IS NULL`) cannot distinguish absent from explicit-null at the index level. F3 will need a different partial-index strategy (e.g., `WHERE NOT (properties ? 'valid_to')` if AGE supports the existence operator, or a materialized "current" view).

**Files:**
- Create: `experiments/f1-age-spike/generate_fixture.py`
- Create: `experiments/f1-age-spike/requirements.txt`

The generator must produce a topology realistic for ~1239 real entities scaled up. Real ratios from the three stores: ~660 personas, ~579 lenses (291+288), ~30 domains, ~50 disciplines, ~25 communities. Edge ratios: each Persona wields ~5-10 Lenses; each Lens belongs to 1 Domain + 1 Discipline; each Lens bridges to ~3-5 other Lenses; communities have ~20 members each.

**Step 1: Write requirements.txt**
```
psycopg2-binary==2.9.9
```

**Step 2: Write generate_fixture.py**
```python
#!/usr/bin/env python3
"""Generate synthetic ontology graph at parameterized scale.

Usage: python generate_fixture.py --edges 10000 [--seed 42]
Connects to localhost:5532 (the docker-compose'd AGE). Truncates and reloads.
"""
import argparse
import math
import random
import sys
import time

import psycopg2

CONN = "host=localhost port=5532 dbname=spike user=spike password=spike"


def cypher(cur, q: str):
    cur.execute("LOAD 'age';")
    cur.execute('SET search_path = ag_catalog, "$user", public;')
    cur.execute(f"SELECT * FROM cypher('ontology', $${q}$$) AS (v agtype);")


def truncate(cur):
    for label in ("persona", "lens", "domain", "discipline", "community"):
        cur.execute(f'TRUNCATE TABLE ontology."_ag_label_{label}" CASCADE;')
    cur.execute('TRUNCATE TABLE ontology."_ag_label_edge" CASCADE;')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--edges", type=int, required=True, help="target total edge count")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    random.seed(args.seed)

    # Scale entity counts proportional to edge count.
    # Ratio anchor: 10k edges ≈ 660 P + 579 L + 30 D + 50 Disc + 25 Comm (real distribution).
    scale = args.edges / 10000.0
    n_persona = max(50, int(660 * scale))
    n_lens = max(50, int(579 * scale))
    n_domain = max(10, int(30 * math.sqrt(scale)))
    n_discipline = max(15, int(50 * math.sqrt(scale)))
    n_community = max(10, int(25 * math.sqrt(scale)))

    print(f"Target edges: {args.edges}")
    print(f"Personas: {n_persona}, Lenses: {n_lens}, Domains: {n_domain}, "
          f"Disciplines: {n_discipline}, Communities: {n_community}")

    t0 = time.time()
    with psycopg2.connect(CONN) as conn:
        with conn.cursor() as cur:
            truncate(cur)
            conn.commit()

            # Vertices — 20% of personas and lenses are "expired" (valid_to set),
            # giving the partial index `WHERE valid_to IS NULL` real selectivity (G6 test).
            EXPIRED_FRACTION = 0.20
            for i in range(n_persona):
                if random.random() < EXPIRED_FRACTION:
                    cypher(cur, f"CREATE (:Persona {{id: 'p{i}', valid_from: '2025-06-01', valid_to: '2025-12-31'}})")
                else:
                    cypher(cur, f"CREATE (:Persona {{id: 'p{i}', valid_from: '2026-01-01'}})")
            for i in range(n_lens):
                eff = round(random.uniform(0.3, 0.95), 2)
                if random.random() < EXPIRED_FRACTION:
                    cypher(cur, f"CREATE (:Lens {{id: 'l{i}', effectiveness_score: {eff}, valid_from: '2025-06-01', valid_to: '2025-12-31'}})")
                else:
                    cypher(cur, f"CREATE (:Lens {{id: 'l{i}', effectiveness_score: {eff}, valid_from: '2026-01-01'}})")
            for i in range(n_domain):
                cypher(cur, f"CREATE (:Domain {{id: 'd{i}'}})")
            for i in range(n_discipline):
                cypher(cur, f"CREATE (:Discipline {{id: 'disc{i}'}})")
            for i in range(n_community):
                cypher(cur, f"CREATE (:Community {{id: 'c{i}'}})")
            conn.commit()
            print(f"Vertices loaded: {time.time()-t0:.1f}s")

            # Edges — distribute the budget
            #  ~50% wields, ~10% in_domain, ~10% in_discipline, ~25% bridges, ~5% member_of
            edges_remaining = args.edges
            wields = int(args.edges * 0.50)
            in_domain = int(args.edges * 0.10)
            in_discipline = int(args.edges * 0.10)
            bridges = int(args.edges * 0.25)
            member_of = args.edges - wields - in_domain - in_discipline - bridges

            for _ in range(wields):
                p = random.randrange(n_persona)
                l = random.randrange(n_lens)
                cypher(cur, f"MATCH (p:Persona {{id:'p{p}'}}), (l:Lens {{id:'l{l}'}}) CREATE (p)-[:wields]->(l)")

            for _ in range(in_domain):
                l = random.randrange(n_lens)
                d = random.randrange(n_domain)
                cypher(cur, f"MATCH (l:Lens {{id:'l{l}'}}), (d:Domain {{id:'d{d}'}}) CREATE (l)-[:in_domain]->(d)")

            for _ in range(in_discipline):
                l = random.randrange(n_lens)
                d = random.randrange(n_discipline)
                cypher(cur, f"MATCH (l:Lens {{id:'l{l}'}}), (d:Discipline {{id:'disc{d}'}}) CREATE (l)-[:in_discipline]->(d)")

            for _ in range(bridges):
                a = random.randrange(n_lens)
                b = random.randrange(n_lens)
                if a == b:
                    continue
                strength = round(random.uniform(0.2, 0.9), 2)
                cypher(cur, f"MATCH (a:Lens {{id:'l{a}'}}), (b:Lens {{id:'l{b}'}}) CREATE (a)-[:bridges {{strength: {strength}}}]->(b)")

            for _ in range(member_of):
                l = random.randrange(n_lens)
                c = random.randrange(n_community)
                cypher(cur, f"MATCH (l:Lens {{id:'l{l}'}}), (c:Community {{id:'c{c}'}}) CREATE (l)-[:member_of]->(c)")

            conn.commit()
    print(f"Done. Total: {time.time()-t0:.1f}s")


if __name__ == "__main__":
    main()
```

**Note**: One Cypher call per row is slow (network round-trips). If the 10k load takes > 5min, batch with `UNWIND` in Task 5 — for the spike, don't optimize generation prematurely.

**Step 3: Install + smoke-test**
```bash
cd experiments/f1-age-spike
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python generate_fixture.py --edges 100  # tiny smoke test
```
Expected: prints counts; no exceptions; ends with "Done."

**Step 4: Verify rows landed**
```bash
docker compose exec -T age psql -U spike -d spike -tAc "SELECT count(*) FROM ontology.\"_ag_label_edge\";"
```
Expected: ~100 (off by a few due to bridges self-loop skip).

**Step 5: Commit**
```bash
git add experiments/f1-age-spike/generate_fixture.py experiments/f1-age-spike/requirements.txt
git commit -m "spike(f1): synthetic graph fixture generator"
```

<verify>
- run: `cd experiments/f1-age-spike && .venv/bin/python generate_fixture.py --edges 100 2>&1 | tail -3`
  expect: contains "Done"
- run: `docker compose -f experiments/f1-age-spike/docker-compose.yml exec -T age psql -U spike -d spike -tAc "SELECT count(*) FROM ontology.\"_ag_label_edge\";"`
  expect: contains a non-zero number
</verify>

---

## Task 5: Write the MVP Triage Query ✓ DONE

**Files:**
- Create: `experiments/f1-age-spike/triage_query.cypher`
- Create: `experiments/f1-age-spike/triage_query.sql` (the EXPLAIN ANALYZE wrapper)

The PRD's MVP triage query: "Persona × Lens × Domain × Discipline match with effectiveness filter and 2-hop community neighborhood." Concretely: given a target Domain + Discipline pair (the "task"), find Personae whose wielded Lenses (a) belong to that Domain and Discipline, (b) have effectiveness ≥ threshold, (c) bridge within 2 hops to other Lenses in shared Communities. Rank by aggregate effectiveness.

**Step 1: Write triage_query.cypher**
```cypher
// Inputs (parameterized at call time):
//   $domain_id, $discipline_id, $eff_threshold (e.g., 0.6)
//
// Output: top-N Personae with their wielded Lenses + 2-hop bridge neighborhood.
//
// NOTE on OPTIONAL MATCH semantics: a WHERE clause directly following an
// OPTIONAL MATCH filters the OPTIONAL pattern *during* matching (so a
// non-matching neighbor causes the whole optional path to be discarded,
// not preserved as NULL). To get post-join filter semantics (keep NULL row
// when no neighbor matches), filter with `neighbor IS NULL OR <predicate>`.

MATCH (p:Persona)-[:wields]->(l:Lens)-[:in_domain]->(d:Domain {id: $domain_id}),
      (l)-[:in_discipline]->(disc:Discipline {id: $discipline_id})
WHERE l.effectiveness_score >= $eff_threshold
  AND l.valid_to IS NULL
  AND p.valid_to IS NULL
WITH p, l
OPTIONAL MATCH (l)-[:member_of]->(c:Community)<-[:member_of]-(neighbor:Lens)
WHERE neighbor IS NULL OR neighbor.valid_to IS NULL
WITH p, l, collect(DISTINCT neighbor.id) AS community_neighbors
OPTIONAL MATCH (l)-[b1:bridges]->(hop1:Lens)-[b2:bridges]->(hop2:Lens)
WHERE (hop2 IS NULL OR hop2.valid_to IS NULL)
  AND (b1 IS NULL OR b1.strength >= 0.4)
  AND (b2 IS NULL OR b2.strength >= 0.4)
WITH p, l, community_neighbors, collect(DISTINCT hop2.id) AS bridge_neighbors_2hop
RETURN p.id AS persona,
       l.id AS lens,
       l.effectiveness_score AS effectiveness,
       size(community_neighbors) AS comm_size,
       size(bridge_neighbors_2hop) AS bridge_2hop_size
ORDER BY effectiveness DESC
LIMIT 50
```

**Step 2: Write triage_query.sql (EXPLAIN ANALYZE wrapper)**
```sql
-- Run with: psql ... -v domain_id="'d3'" -v discipline_id="'disc7'" -v eff="0.6"
-- AGE requires the cypher() call to be wrapped in SELECT.
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM cypher('ontology', $$
  MATCH (p:Persona)-[:wields]->(l:Lens)-[:in_domain]->(d:Domain {id: 'd3'}),
        (l)-[:in_discipline]->(disc:Discipline {id: 'disc7'})
  WHERE l.effectiveness_score >= 0.6
    AND l.valid_to IS NULL
    AND p.valid_to IS NULL
  WITH p, l
  OPTIONAL MATCH (l)-[:member_of]->(c:Community)<-[:member_of]-(neighbor:Lens)
  WHERE neighbor IS NULL OR neighbor.valid_to IS NULL
  WITH p, l, collect(DISTINCT neighbor.id) AS community_neighbors
  OPTIONAL MATCH (l)-[b1:bridges]->(hop1:Lens)-[b2:bridges]->(hop2:Lens)
  WHERE (hop2 IS NULL OR hop2.valid_to IS NULL)
    AND (b1 IS NULL OR b1.strength >= 0.4)
    AND (b2 IS NULL OR b2.strength >= 0.4)
  WITH p, l, community_neighbors, collect(DISTINCT hop2.id) AS bridge_2hop
  RETURN p.id, l.id, l.effectiveness_score, size(community_neighbors), size(bridge_2hop)
  ORDER BY l.effectiveness_score DESC
  LIMIT 50
$$) AS (persona agtype, lens agtype, eff agtype, comm_size agtype, bridge_size agtype);
```

**Step 3: Smoke-test against the 100-edge fixture**
```bash
docker compose -f experiments/f1-age-spike/docker-compose.yml exec -T age psql -U spike -d spike < experiments/f1-age-spike/triage_query.sql 2>&1 | head -40
```
Expected: an EXPLAIN ANALYZE plan dump (may be empty result set at 100 edges — that's fine; we just need the plan).

**Step 4: Commit**
```bash
git add experiments/f1-age-spike/triage_query.cypher experiments/f1-age-spike/triage_query.sql
git commit -m "spike(f1): MVP triage query + EXPLAIN ANALYZE wrapper"
```

<verify>
- run: `docker compose -f experiments/f1-age-spike/docker-compose.yml exec -T age psql -U spike -d spike < experiments/f1-age-spike/triage_query.sql 2>&1 | grep -c "QUERY PLAN\|Planning Time\|Execution Time"`
  expect: contains a non-zero number
</verify>

---

## Task 6: Benchmark Harness ✓ DONE

**Files:**
- Create: `experiments/f1-age-spike/bench.py`

**Step 1: Write bench.py**
```python
#!/usr/bin/env python3
"""Run the triage query N times, capture one EXPLAIN ANALYZE plan, print p50/p95/p99."""
import argparse
import json
import random
import statistics
import sys
import time

import psycopg2

CONN = "host=localhost port=5532 dbname=spike user=spike password=spike"

QUERY = """
SELECT * FROM cypher('ontology', $$
  MATCH (p:Persona)-[:wields]->(l:Lens)-[:in_domain]->(d:Domain {{id: '{domain_id}'}}),
        (l)-[:in_discipline]->(disc:Discipline {{id: '{discipline_id}'}})
  WHERE l.effectiveness_score >= 0.6
    AND l.valid_to IS NULL
    AND p.valid_to IS NULL
  WITH p, l
  OPTIONAL MATCH (l)-[:member_of]->(c:Community)<-[:member_of]-(neighbor:Lens)
  WHERE neighbor IS NULL OR neighbor.valid_to IS NULL
  WITH p, l, collect(DISTINCT neighbor.id) AS community_neighbors
  OPTIONAL MATCH (l)-[b1:bridges]->(hop1:Lens)-[b2:bridges]->(hop2:Lens)
  WHERE (hop2 IS NULL OR hop2.valid_to IS NULL)
    AND (b1 IS NULL OR b1.strength >= 0.4)
    AND (b2 IS NULL OR b2.strength >= 0.4)
  WITH p, l, community_neighbors, collect(DISTINCT hop2.id) AS bridge_2hop
  RETURN p.id, l.id, l.effectiveness_score, size(community_neighbors), size(bridge_2hop)
  ORDER BY l.effectiveness_score DESC
  LIMIT 50
$$) AS (persona agtype, lens agtype, eff agtype, comm_size agtype, bridge_size agtype);
"""


# Mirror generate_fixture.py's scaling formula so bench samples real ID ranges,
# never asks for IDs that don't exist (which would produce instant empty results
# and deflate p95).
def entity_counts_for_edges(edges: int):
    import math
    scale = edges / 10000.0
    return {
        "personas": max(50, int(660 * scale)),
        "lenses": max(50, int(579 * scale)),
        "domains": max(10, int(30 * math.sqrt(scale))),
        "disciplines": max(15, int(50 * math.sqrt(scale))),
        "communities": max(10, int(25 * math.sqrt(scale))),
    }


def run_once(cur, domain_id, discipline_id):
    q = QUERY.format(domain_id=domain_id, discipline_id=discipline_id)
    t0 = time.perf_counter()
    cur.execute(q)
    cur.fetchall()
    return (time.perf_counter() - t0) * 1000  # ms


def explain_once(cur, domain_id, discipline_id):
    q = "EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) " + QUERY.format(
        domain_id=domain_id, discipline_id=discipline_id
    )
    cur.execute(q)
    return "\n".join(row[0] for row in cur.fetchall())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=20)
    ap.add_argument("--edges", type=int, required=True,
                    help="edge count used for fixture — bench derives entity counts from this")
    ap.add_argument("--seed", type=int, default=43)
    ap.add_argument("--out-plan", default="last_explain.txt")
    args = ap.parse_args()

    if args.runs < 20:
        sys.exit(f"runs must be >= 20 for stable p95 (got {args.runs})")

    counts = entity_counts_for_edges(args.edges)
    n_domains = counts["domains"]
    n_disciplines = counts["disciplines"]
    print(f"Bench against fixture with {n_domains} domains, {n_disciplines} disciplines",
          file=sys.stderr)

    random.seed(args.seed)

    with psycopg2.connect(CONN) as conn:
        with conn.cursor() as cur:
            cur.execute("LOAD 'age';")
            cur.execute('SET search_path = ag_catalog, "$user", public;')

            # Warmup (5 runs — query plans + JIT cache + buffer pool)
            for _ in range(5):
                run_once(cur, f"d{random.randrange(n_domains)}",
                         f"disc{random.randrange(n_disciplines)}")

            # Capture plan once
            plan = explain_once(cur,
                                f"d{random.randrange(n_domains)}",
                                f"disc{random.randrange(n_disciplines)}")
            with open(args.out_plan, "w") as f:
                f.write(plan)

            # Timed runs with varied parameters drawn from the actual ID range
            timings = []
            for _ in range(args.runs):
                d = f"d{random.randrange(n_domains)}"
                disc = f"disc{random.randrange(n_disciplines)}"
                timings.append(run_once(cur, d, disc))

    # Use statistics.quantiles for defensible p95. n=100 buckets the data into
    # percentiles; index 94 is the p95 boundary. Requires Python 3.8+.
    quantiles = statistics.quantiles(timings, n=100, method="inclusive")
    p50 = statistics.median(timings)
    p95 = quantiles[94]
    p99 = quantiles[98]
    mean = statistics.mean(timings)

    out = {
        "runs": args.runs,
        "edges": args.edges,
        "n_domains": n_domains,
        "n_disciplines": n_disciplines,
        "p50_ms": round(p50, 2),
        "p95_ms": round(p95, 2),
        "p99_ms": round(p99, 2),
        "mean_ms": round(mean, 2),
        "min_ms": round(min(timings), 2),
        "max_ms": round(max(timings), 2),
        "all_ms": [round(t, 2) for t in timings],
        "explain_plan_path": args.out_plan,
    }
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
```

**Step 2: Smoke-test with --runs 20 against the 100-edge fixture**
```bash
cd experiments/f1-age-spike
.venv/bin/python bench.py --runs 20 --edges 100 --out-plan smoke_plan.txt
```
Expected: JSON output with `p50_ms`, `p95_ms`, etc. Numbers don't matter at this scale — just verifying the harness runs end-to-end.

**Step 3: Commit**
```bash
git add experiments/f1-age-spike/bench.py
git commit -m "spike(f1): EXPLAIN ANALYZE harness with p50/p95"
```

<verify>
- run: `cd experiments/f1-age-spike && .venv/bin/python bench.py --runs 20 --edges 100 --out-plan /tmp/smoke_plan.txt 2>/dev/null | python3 -c "import sys,json; print(list(json.load(sys.stdin).keys()))"`
  expect: contains "p95_ms"
</verify>

---

## Task 7: Benchmark at 10k Edges ✓ DONE — p95=205.77ms (well under 500ms threshold)

**Files:**
- Create: `experiments/f1-age-spike/results/10k_explain.txt`
- Create: `experiments/f1-age-spike/results/10k_timings.json`

**Step 1: Reset and load 10k (with hard timeout)**
```bash
cd experiments/f1-age-spike
docker compose down -v && docker compose up -d
sleep 10
./apply_schema.sh
docker compose exec -T age psql -U spike -d spike < indexes.sql
# Pre-registered hard timeout: 30 minutes for 10k load (proportionally tighter than 100k's 90 min).
timeout 1800 .venv/bin/python generate_fixture.py --edges 10000 --seed 42 2>&1 | tail -5
gen_exit=$?
if [ "$gen_exit" -eq 124 ]; then
    echo "FIXTURE LOAD TIMED OUT at 30 min — switch to UNWIND batch generator before continuing"
    exit 1
fi
```
Expected: "Done." with vertex counts printed.

**Step 2: Run benchmark and save**
```bash
mkdir -p results
.venv/bin/python bench.py --runs 20 --edges 10000 --out-plan results/10k_explain.txt > results/10k_timings.json
cat results/10k_timings.json
```

**Step 3: Sanity-check the plan for index use**
```bash
echo "--- Hot-path Seq Scan check (BLOCKING) ---"
grep -E "Seq Scan on .*_ag_label_(lens|persona)" results/10k_explain.txt && \
  echo "FAIL: Seq Scan on Lens or Persona — index not used at hot path" || \
  echo "OK: no Seq Scan on Lens/Persona"

echo "--- Index Scan summary ---"
grep -E "Index Scan|Bitmap Index" results/10k_explain.txt | head -10
```
Note: `Seq Scan` on tiny tables (Domain, Discipline, Community at 10k) is fine. The pre-registered fail condition is **Seq Scan on `_ag_label_lens` or `_ag_label_persona`** — these are the high-cardinality vertex tables the triage hot path depends on.

**Step 4: Acceptance check (mechanical, per pre-registered rule)**
- p95 < 500ms AND no Seq Scan on Lens/Persona → proceed to 100k.
- Either condition fails → `redesign-required` candidate; record and proceed to 100k anyway (the 100k result still informs the redesign), but flag in transcript.

**Step 5: Commit results**
```bash
git add experiments/f1-age-spike/results/10k_explain.txt experiments/f1-age-spike/results/10k_timings.json
git commit -m "spike(f1): benchmark results at 10k edges"
```

<verify>
- run: `python3 -c "import json; d=json.load(open('experiments/f1-age-spike/results/10k_timings.json')); print(d['p95_ms'])"`
  expect: contains a number (no validation on value here — that's the human review step)
</verify>

---

## Task 8: Benchmark at 100k Edges ✓ DONE — p95=782.25ms (well under 2000ms threshold)

**Files:**
- Create: `experiments/f1-age-spike/results/100k_explain.txt`
- Create: `experiments/f1-age-spike/results/100k_timings.json`

**Step 1: Reset and load 100k (with hard timeout)**
```bash
cd experiments/f1-age-spike
docker compose down -v && docker compose up -d
sleep 10
./apply_schema.sh
docker compose exec -T age psql -U spike -d spike < indexes.sql
# Pre-registered hard timeout: kill at 90 minutes wall clock.
timeout 5400 .venv/bin/python generate_fixture.py --edges 100000 --seed 42 2>&1 | tail -5
gen_exit=$?
if [ "$gen_exit" -eq 124 ]; then
    echo "FIXTURE LOAD TIMED OUT at 90 min — switching to UNWIND batch generator (per pre-registered rule)"
    # Stop and rewrite generate_fixture.py to batch with UNWIND $rows clauses (~1000 rows/call), then resume.
    exit 1
fi
```

**Step 2: Run benchmark and save**
```bash
.venv/bin/python bench.py --runs 20 --edges 100000 --out-plan results/100k_explain.txt > results/100k_timings.json
cat results/100k_timings.json
```

**Step 3: Plan inspection (BLOCKING per pre-registered rule)**
```bash
echo "--- Hot-path Seq Scan check (BLOCKING) ---"
grep -E "Seq Scan on .*_ag_label_(lens|persona)" results/100k_explain.txt && \
  echo "FAIL: Seq Scan on Lens or Persona — verdict cannot be AGE-viable" || \
  echo "OK: no Seq Scan on Lens/Persona"

echo "--- Full plan summary ---"
grep -E "Index Scan|Seq Scan|Bitmap|Hash Join|Nested Loop" results/100k_explain.txt
```
Apply the pre-registered decision rule (see top of plan):
- If 100k p95 in `[1.5s, 2.5s]` band → **rerun with N=100** before deciding (do not skip this).
- Bridges 2-hop traversal showing `Nested Loop` over `Seq Scan` is acceptable IF documented and IF p95 still meets the threshold; the rule does not block on bridges-side scans (only on Lens/Persona).

**Step 4: Commit results**
```bash
git add experiments/f1-age-spike/results/100k_explain.txt experiments/f1-age-spike/results/100k_timings.json
git commit -m "spike(f1): benchmark results at 100k edges"
```

<verify>
- run: `python3 -c "import json; d=json.load(open('experiments/f1-age-spike/results/100k_timings.json')); print(d['p95_ms'])"`
  expect: contains a number
</verify>

---

## Task 9: Decision Memo + Transcript ✓ DONE — verdict AGE-viable, transcript at docs/research/f1-cypher-benchmark/2026-04-27-transcript.md

**Files:**
- Create: `docs/research/f1-cypher-benchmark/2026-04-26-transcript.md`

This is the **acceptance artifact** per PRD F1. It must contain: both timing results, both plan dumps inline, the explicit verdict (`AGE-viable` | `redesign-required` | `viable-with-caveats`), the threshold rule from PRD F1, and any caveats discovered (e.g., AGE-not-installed-on-Auraken-Postgres).

**Step 1: Write the transcript**
```markdown
---
artifact_type: spike-result
bead: sylveste-j5vi
gate: G1
date: 2026-04-26
verdict: <FILL: AGE-viable | redesign-required | inconclusive>
---

# F1 Cypher Benchmark — AGE Multi-Hop Triage Query

**Verdict scope (pre-registered):** This verdict covers ONLY the MVP triage *read* query latency at 100k synthetic edges and ONLY whether AGE's planner uses indexes at the hot path. It does NOT certify AGE for ingestion write throughput (F4 risk), schema migration ergonomics (F3 risk), AGE ecosystem stability over Postgres major upgrades, or driver maturity. If post-V1 testing reveals problems in unmeasured dimensions, redesign decisions reopen.

**Decision:** <FILL>

**Pre-registered decision rule applied:**
- `AGE-viable` requires ALL of: 10k p95 < 500ms, 100k p95 < 2.0s, no Seq Scan on `_ag_label_lens` or `_ag_label_persona` at hot path, AND ops feasibility note attached (AGE installable on the Postgres image F3 will use)
- `redesign-required` if ANY: 100k p95 ≥ 2.0s, 10k p95 ≥ 500ms, Seq Scan on Lens or Persona at hot path, or ops infeasibility
- `inconclusive — escalate` if 100k p95 ∈ [1.5s, 2.5s] → MUST rerun N=100 before deciding (then re-apply rule)
- No `viable-with-caveats` outcome exists.

## Setup

- Apache AGE on Postgres 16 (Docker `apache/age:release_PG16_1.6.0`)
- 7-entity ontology (Persona, Lens, Domain, Discipline, Community subset; Source/Evidence/Concept deferred to F3 — not on triage hot path)
- BTREE indexes on identity properties + partial indexes on `valid_to IS NULL` + effectiveness index
- Synthetic fixture: ratios anchored to real entity counts (660P, 579L, 30D, 50Disc, 25C at 10k edge scale)
- Harness: 3-run warmup + 20 timed runs with varied (domain, discipline) parameters

## Results — 10k Edges

<paste contents of results/10k_timings.json here>

### Plan
<paste results/10k_explain.txt here, fenced as ```sql>

## Results — 100k Edges

<paste contents of results/100k_timings.json here>

### Plan
<paste results/100k_explain.txt here, fenced as ```sql>

## Plan Analysis

- Identity lookups: <Index Scan | Seq Scan> — <observation>
- Domain/Discipline filter: <observation>
- Effectiveness filter: <observation>
- Community 2-hop neighborhood: <observation>
- Bridges 2-hop traversal: <observation>

## Ops Feasibility Note (gate condition for AGE-viable)

**Auraken Postgres uses `pgvector/pgvector:pg17`, NOT AGE.** This means the "AGE-viable" verdict requires a parallel ops decision:

- **Option A** — rebuild the production Postgres image to bundle AGE alongside pgvector. AGE supports Postgres 16; pgvector image is at pg17. Either downgrade pgvector to pg16 OR wait for AGE Postgres 17 support OR build a custom image. ETA on each? <FILL>
- **Option B** — stand up a separate Sylveste-managed Postgres+AGE container. Adds an ops surface (one more service); decouples ontology from Auraken. ETA <FILL>.

Pre-registered rule: **the verdict cannot be `AGE-viable` until one of these options is chosen and rough ETA recorded.** A successful benchmark + unsolved ops question = `inconclusive`.

PRD §F3 must be updated with the chosen option before F3 begins.

## Other Caveats Surfaced

- <add as discovered>

## Verdict

<EXPLICIT recommendation: ship F3 as planned | redesign storage choice | proceed with named caveats>

<If redesign-required: name the next steps. Candidates: denormalize hot path into materialized view, reduce 2-hop bridges to 1-hop with precomputed transitive closure, reconsider TerminusDB or a hybrid Postgres+graph approach.>

## Reproduction

```bash
cd experiments/f1-age-spike
docker compose up -d && sleep 10
./apply_schema.sh
docker compose exec -T age psql -U spike -d spike < indexes.sql
.venv/bin/python generate_fixture.py --edges 10000 --seed 42
.venv/bin/python bench.py --runs 20 --out-plan results/10k_explain.txt > results/10k_timings.json
```
```

**Step 2: Fill in the FILL markers from the actual results (mechanical)**
- Read `results/10k_timings.json` and `results/100k_timings.json`
- Read `results/10k_explain.txt` and `results/100k_explain.txt`
- Apply the **pre-registered** rule from the top of the plan — no new outcome states, no judgment-call thresholds.
  - If 100k p95 ∈ [1.5s, 2.5s]: STOP, rerun N=100, re-evaluate. Do NOT write a verdict from N=20 in this band.
  - If Seq Scan on Lens or Persona at hot path: verdict = `redesign-required` even if p95 passes.
  - If ops feasibility unresolved: verdict = `inconclusive` even if benchmark passes.
- Inspect plan output and write the Plan Analysis bullets factually (no spin)

**Step 3: Commit transcript**
```bash
git add docs/research/f1-cypher-benchmark/2026-04-26-transcript.md
git commit -m "spike(f1): G1 acceptance — AGE benchmark transcript + verdict"
```

<verify>
- run: `head -10 docs/research/f1-cypher-benchmark/2026-04-26-transcript.md | grep -c "verdict:"`
  expect: contains "1"
- run: `grep -c "<FILL>" docs/research/f1-cypher-benchmark/2026-04-26-transcript.md || echo 0`
  expect: contains "0"
</verify>

---

## Task 10: README + Spike Wrap ✓ DONE — bead state f1_verdict=AGE-viable, follow-up bead sylveste-4uhk filed for ops decision

**Files:**
- Modify: `experiments/f1-age-spike/README.md`

**Step 1: Write the README**
```markdown
# F1 AGE Cypher Benchmark Spike

Provides go/no-go evidence for using Apache AGE as the persona/lens ontology backend.

## Result

See `docs/research/f1-cypher-benchmark/2026-04-26-transcript.md` for the binding verdict.

## Re-run

```bash
docker compose up -d && sleep 10
./apply_schema.sh
docker compose exec -T age psql -U spike -d spike < indexes.sql

python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# 10k benchmark
.venv/bin/python generate_fixture.py --edges 10000 --seed 42
.venv/bin/python bench.py --runs 20 --edges 10000 --out-plan results/10k_explain.txt > results/10k_timings.json

# 100k benchmark (reset DB first)
docker compose down -v && docker compose up -d && sleep 10
./apply_schema.sh
docker compose exec -T age psql -U spike -d spike < indexes.sql
.venv/bin/python generate_fixture.py --edges 100000 --seed 42
.venv/bin/python bench.py --runs 20 --edges 100000 --out-plan results/100k_explain.txt > results/100k_timings.json
```

## Tear-down

```bash
docker compose down -v
```

## Files

- `docker-compose.yml` — scratch AGE container, port 5532
- `init.sql` — creates AGE extension + `ontology` graph on first run
- `schema.cypher` + `apply_schema.sh` — minimal vertex labels
- `indexes.sql` — G6 partial indexes
- `generate_fixture.py` — synthetic graph at parameterized edge count
- `triage_query.cypher` + `triage_query.sql` — MVP query under test
- `bench.py` — N-run harness, p50/p95/p99
- `results/` — committed timings + plans (the F1 acceptance evidence)
```

**Step 2: Update bead state with verdict**
```bash
verdict=$(grep '^verdict:' docs/research/f1-cypher-benchmark/2026-04-26-transcript.md | cut -d: -f2- | tr -d ' ')
bd set-state sylveste-j5vi "f1_verdict=$verdict" --reason "G1 spike result"
clavain-cli set-artifact sylveste-j5vi "spike-result" "docs/research/f1-cypher-benchmark/2026-04-26-transcript.md"
```

**Step 3: If verdict is `redesign-required`, file follow-up bead**
```bash
# Only if redesign-required:
bd create --title "F1 abandon-branch: redesign storage choice for persona/lens ontology" \
  --priority 1 --issue-type task \
  --description "AGE benchmark failed gate G1 (p95 > 2s at 100k edges). See docs/research/f1-cypher-benchmark/2026-04-26-transcript.md. F3 (sylveste-dsbl) blocks until redesign lands. Candidate next steps documented in transcript." \
  --depends-on sylveste-j5vi
# Then update F3 to depend on the new redesign bead
```

**Step 4: Commit**
```bash
git add experiments/f1-age-spike/README.md
git commit -m "spike(f1): README + tear-down instructions"
```

<verify>
- run: `bd state sylveste-j5vi f1_verdict`
  expect: contains "AGE-viable" or "redesign-required" or "inconclusive"
- run: `clavain-cli get-artifact sylveste-j5vi spike-result`
  expect: contains "transcript.md"
</verify>

---

## Wrap

Sprint Step 6 (test) for this spike = the verify rules in Tasks 7+8+9. Step 7 (quality-gates) reviews the transcript memo, plan analysis, and follow-up bead (if any). Step 10 (ship) closes sylveste-j5vi.

If `f1_verdict == redesign-required`:
- F3 (sylveste-dsbl) stays open and blocked on the new redesign bead
- Epic sylveste-b1ha stays in_progress; do NOT close it
- The follow-up bead is the next sprint's entry point

If `f1_verdict == AGE-viable`:
- F3 unblocks naturally (DAG already wires F3←F1+F2)
- Epic continues per plan

## Execution Manifest

This plan is **all-sequential** (each task's output informs the next; spike work doesn't parallelize cleanly). No `.exec.yaml` companion — under 3 independent waves.
