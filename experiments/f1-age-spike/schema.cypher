LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- Seed one of each vertex label so AGE auto-creates the label tables.
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

-- delete seeds (DETACH removes attached edges)
SELECT * FROM cypher('ontology', $$
  MATCH (n) WHERE n.id STARTS WITH 'seed-' DETACH DELETE n
$$) AS (v agtype);
