#!/usr/bin/env python3
"""Run the triage query N times, capture one EXPLAIN ANALYZE plan, print p50/p95/p99."""
import argparse
import json
import math
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


def entity_counts_for_edges(edges: int):
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
    return (time.perf_counter() - t0) * 1000


def explain_once(cur, domain_id, discipline_id):
    q = "EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) " + QUERY.format(
        domain_id=domain_id, discipline_id=discipline_id
    )
    cur.execute(q)
    return "\n".join(row[0] for row in cur.fetchall())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=20)
    ap.add_argument("--edges", type=int, required=True)
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

            for _ in range(5):
                run_once(cur, f"d{random.randrange(n_domains)}",
                         f"disc{random.randrange(n_disciplines)}")

            plan = explain_once(cur,
                                f"d{random.randrange(n_domains)}",
                                f"disc{random.randrange(n_disciplines)}")
            with open(args.out_plan, "w") as f:
                f.write(plan)

            timings = []
            for _ in range(args.runs):
                d = f"d{random.randrange(n_domains)}"
                disc = f"disc{random.randrange(n_disciplines)}"
                timings.append(run_once(cur, d, disc))

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
