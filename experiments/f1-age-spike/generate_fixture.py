#!/usr/bin/env python3
"""Generate synthetic ontology graph at parameterized scale.

Usage: python generate_fixture.py --edges 10000 [--seed 42]
Connects to localhost:5532. Truncates label tables and reloads.

Batched UNWIND from the start — preliminary probing showed per-row Cypher
calls cost ~5ms round-trip, which would push the 100k load past the
90-min hard timeout. UNWIND batches of ~500 rows are dramatically faster.
"""
import argparse
import json
import math
import random
import sys
import time

import psycopg2

CONN = "host=localhost port=5532 dbname=spike user=spike password=spike"
BATCH = 500


def setup(cur):
    cur.execute("LOAD 'age';")
    cur.execute('SET search_path = ag_catalog, "$user", public;')


def cypher(cur, q: str):
    cur.execute(f"SELECT * FROM cypher('ontology', $${q}$$) AS (v agtype);")


# Cypher literal serializers — AGE's Cypher accepts bare-identifier map keys,
# not JSON-quoted keys. Strings still take double quotes.
def cy_value(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        # Escape backslash and double quote
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, dict):
        return "{" + ", ".join(f"{k}: {cy_value(val)}" for k, val in v.items()) + "}"
    if isinstance(v, list):
        return "[" + ", ".join(cy_value(x) for x in v) + "]"
    raise TypeError(f"unsupported type: {type(v)}")


def cy_list_of_maps(rows):
    return "[" + ", ".join(cy_value(r) for r in rows) + "]"


def truncate(cur):
    for label in ("Persona", "Lens", "Domain", "Discipline", "Community"):
        cur.execute(f'TRUNCATE TABLE ontology."{label}" CASCADE;')
    for label in ("wields", "in_domain", "in_discipline", "bridges", "member_of"):
        cur.execute(f'TRUNCATE TABLE ontology."{label}" CASCADE;')


def create_vertices_batch(cur, label: str, rows: list):
    """UNWIND a Cypher list of maps and CREATE one vertex per row."""
    if not rows:
        return
    inline = cy_list_of_maps(rows)
    sample = rows[0]
    assignments = ", ".join(f"{k}: row.{k}" for k in sample.keys())
    q = f"UNWIND {inline} AS row CREATE (:{label} {{{assignments}}})"
    cypher(cur, q)


def create_edges_batch(cur, edges: list):
    """edges: list of dicts {from_label, from_id, to_label, to_id, rel, props_dict_or_None}.
    Group by (from_label, to_label, rel, prop_keys) for batching efficiency."""
    if not edges:
        return
    groups = {}
    for e in edges:
        key = (e["from_label"], e["to_label"], e["rel"], tuple(sorted((e.get("props") or {}).keys())))
        groups.setdefault(key, []).append(e)

    for (from_label, to_label, rel, prop_keys), batch in groups.items():
        rows = []
        for e in batch:
            row = {"f": e["from_id"], "t": e["to_id"]}
            for k in prop_keys:
                row[k] = e["props"][k]
            rows.append(row)
        inline = cy_list_of_maps(rows)
        edge_props = ""
        if prop_keys:
            edge_props = " {" + ", ".join(f"{k}: row.{k}" for k in prop_keys) + "}"
        q = (
            f"UNWIND {inline} AS row "
            f"MATCH (a:{from_label} {{id: row.f}}), (b:{to_label} {{id: row.t}}) "
            f"CREATE (a)-[:{rel}{edge_props}]->(b)"
        )
        cypher(cur, q)


def chunked(seq, n):
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--edges", type=int, required=True, help="target total edge count")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--expired-fraction", type=float, default=0.20,
                    help="fraction of personas/lenses with valid_to set (G6 partial-index test)")
    args = ap.parse_args()

    random.seed(args.seed)

    scale = args.edges / 10000.0
    n_persona = max(50, int(660 * scale))
    n_lens = max(50, int(579 * scale))
    n_domain = max(10, int(30 * math.sqrt(scale)))
    n_discipline = max(15, int(50 * math.sqrt(scale)))
    n_community = max(10, int(25 * math.sqrt(scale)))

    print(f"Target edges: {args.edges}", file=sys.stderr)
    print(f"Personas: {n_persona}, Lenses: {n_lens}, Domains: {n_domain}, "
          f"Disciplines: {n_discipline}, Communities: {n_community}", file=sys.stderr)
    print(f"Expired fraction: {args.expired_fraction}", file=sys.stderr)

    t0 = time.time()
    with psycopg2.connect(CONN) as conn:
        with conn.cursor() as cur:
            setup(cur)
            truncate(cur)
            conn.commit()

            # ---- Vertices ----
            # Always include valid_to (null when current) so all rows in a UNWIND
            # batch share the same key-set — the batcher derives column list from row 0.
            personas = []
            for i in range(n_persona):
                expired = random.random() < args.expired_fraction
                row = {
                    "id": f"p{i}",
                    "valid_from": "2025-06-01" if expired else "2026-01-01",
                    "valid_to": "2025-12-31" if expired else None,
                }
                personas.append(row)

            lenses = []
            for i in range(n_lens):
                expired = random.random() < args.expired_fraction
                row = {
                    "id": f"l{i}",
                    "effectiveness_score": round(random.uniform(0.3, 0.95), 2),
                    "valid_from": "2025-06-01" if expired else "2026-01-01",
                    "valid_to": "2025-12-31" if expired else None,
                }
                lenses.append(row)

            domains = [{"id": f"d{i}"} for i in range(n_domain)]
            disciplines = [{"id": f"disc{i}"} for i in range(n_discipline)]
            communities = [{"id": f"c{i}"} for i in range(n_community)]

            for batch in chunked(personas, BATCH):
                create_vertices_batch(cur, "Persona", batch)
            for batch in chunked(lenses, BATCH):
                create_vertices_batch(cur, "Lens", batch)
            for batch in chunked(domains, BATCH):
                create_vertices_batch(cur, "Domain", batch)
            for batch in chunked(disciplines, BATCH):
                create_vertices_batch(cur, "Discipline", batch)
            for batch in chunked(communities, BATCH):
                create_vertices_batch(cur, "Community", batch)
            conn.commit()
            print(f"Vertices loaded in {time.time()-t0:.1f}s", file=sys.stderr)

            # ---- Edges ----
            wields = int(args.edges * 0.50)
            in_domain = int(args.edges * 0.10)
            in_discipline = int(args.edges * 0.10)
            bridges = int(args.edges * 0.25)
            member_of = args.edges - wields - in_domain - in_discipline - bridges

            edges = []
            for _ in range(wields):
                edges.append({
                    "from_label": "Persona", "from_id": f"p{random.randrange(n_persona)}",
                    "to_label": "Lens", "to_id": f"l{random.randrange(n_lens)}",
                    "rel": "wields", "props": None,
                })
            for _ in range(in_domain):
                edges.append({
                    "from_label": "Lens", "from_id": f"l{random.randrange(n_lens)}",
                    "to_label": "Domain", "to_id": f"d{random.randrange(n_domain)}",
                    "rel": "in_domain", "props": None,
                })
            for _ in range(in_discipline):
                edges.append({
                    "from_label": "Lens", "from_id": f"l{random.randrange(n_lens)}",
                    "to_label": "Discipline", "to_id": f"disc{random.randrange(n_discipline)}",
                    "rel": "in_discipline", "props": None,
                })
            for _ in range(bridges):
                a = random.randrange(n_lens)
                b = random.randrange(n_lens)
                if a == b:
                    continue
                edges.append({
                    "from_label": "Lens", "from_id": f"l{a}",
                    "to_label": "Lens", "to_id": f"l{b}",
                    "rel": "bridges",
                    "props": {"strength": round(random.uniform(0.2, 0.9), 2)},
                })
            for _ in range(member_of):
                edges.append({
                    "from_label": "Lens", "from_id": f"l{random.randrange(n_lens)}",
                    "to_label": "Community", "to_id": f"c{random.randrange(n_community)}",
                    "rel": "member_of", "props": None,
                })

            for batch in chunked(edges, BATCH):
                create_edges_batch(cur, batch)
            conn.commit()
            print(f"Edges loaded ({len(edges)} created): {time.time()-t0:.1f}s total", file=sys.stderr)

            # ANALYZE so the planner has stats
            for label in ("Persona", "Lens", "Domain", "Discipline", "Community",
                          "wields", "in_domain", "in_discipline", "bridges", "member_of"):
                cur.execute(f'ANALYZE ontology."{label}";')
            conn.commit()
            print(f"ANALYZE done: {time.time()-t0:.1f}s", file=sys.stderr)

    print(f"DONE total {time.time()-t0:.1f}s")


if __name__ == "__main__":
    main()
