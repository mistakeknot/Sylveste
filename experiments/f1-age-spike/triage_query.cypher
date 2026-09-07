// MVP triage query under benchmark.
// Inputs: $domain_id, $discipline_id (effectiveness threshold hardcoded 0.6)
// Output: top-50 personae+lenses ranked by effectiveness, with neighborhood sizes.
//
// OPTIONAL MATCH semantics: a WHERE directly after OPTIONAL MATCH filters the
// optional pattern *during* matching (failed match → discard, not NULL row).
// To preserve NULL rows, use `x IS NULL OR <predicate>`.

MATCH (p:Persona)-[:wields]->(l:Lens)-[:in_domain]->(d:Domain {id: $domain_id}),
      (l)-[:in_discipline]->(disc:Discipline {id: $discipline_id})
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
WITH p, l, community_neighbors, collect(DISTINCT hop2.id) AS bridge_neighbors_2hop
RETURN p.id AS persona,
       l.id AS lens,
       l.effectiveness_score AS effectiveness,
       size(community_neighbors) AS comm_size,
       size(bridge_neighbors_2hop) AS bridge_2hop_size
ORDER BY effectiveness DESC
LIMIT 50
