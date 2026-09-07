# F1 AGE Cypher Benchmark Spike

Provides go/no-go evidence for using Apache AGE as the persona/lens ontology backend (epic sylveste-b1ha, child sylveste-j5vi).

## Result

See `docs/research/f1-cypher-benchmark/2026-04-27-transcript.md` for the binding verdict.

**TL;DR:** AGE-viable. p95 = 782ms at 100k edges (threshold: < 2000ms). One pending decision: ops choice between rebuilding the production Postgres image with AGE bundled, or running a separate AGE container alongside Auraken's pgvector — see Ops Feasibility Note in the transcript.

## Re-run

```bash
docker compose up -d && sleep 12
docker compose exec -T age psql -U spike -d spike -v ON_ERROR_STOP=1 < schema.cypher
docker compose exec -T age psql -U spike -d spike -v ON_ERROR_STOP=1 < indexes.sql

python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# 10k benchmark
.venv/bin/python generate_fixture.py --edges 10000 --seed 42
.venv/bin/python bench.py --runs 20 --edges 10000 --out-plan results/10k_explain.txt > results/10k_timings.json

# 100k benchmark (reset DB first)
docker compose down -v && docker compose up -d && sleep 12
docker compose exec -T age psql -U spike -d spike -v ON_ERROR_STOP=1 < schema.cypher
docker compose exec -T age psql -U spike -d spike -v ON_ERROR_STOP=1 < indexes.sql
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
- `schema.cypher` — minimal vertex + edge label seeding (5+5)
- `apply_schema.sh` — applies schema then indexes
- `indexes.sql` — GIN on properties, BTREE on edge endpoints
- `generate_fixture.py` — synthetic graph at parameterized edge count, batched UNWIND
- `triage_query.cypher` — MVP query under test (canonical Cypher)
- `triage_query.sql` — psql wrapper for one-off EXPLAIN ANALYZE inspection
- `bench.py` — N-run harness, p50/p95/p99 via `statistics.quantiles`
- `results/10k_timings.json`, `results/10k_explain.txt` — committed 10k evidence
- `results/100k_timings.json`, `results/100k_explain.txt` — committed 100k evidence

## Discoveries

The transcript at `docs/research/f1-cypher-benchmark/2026-04-27-transcript.md` lists six F3-relevant findings (AGE Cypher map syntax, GIN-not-BTREE indexing, agtype null-key omission, OPTIONAL MATCH+WHERE semantics, batched UNWIND requirement, bridges variance). Read them before starting F3.
