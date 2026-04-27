-- Smoke wrapper. Substitute domain/discipline literally for psql probing.
-- bench.py builds the same query string with parameter substitution.
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
