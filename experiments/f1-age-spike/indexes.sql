-- AGE 1.6.0 stores label tables as ontology."Persona" etc. (plain label name).
-- Properties are agtype (NOT jsonb). The Cypher→SQL translator emits
-- containment filters of the form `properties @> '{"id": "X"}'::agtype`.
-- BTREE on ->> text extraction will NOT be chosen; we need GIN on agtype.
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- GIN on the full properties column supports @> containment, which is what
-- AGE's translator generates for `MATCH (n:Label {key: value})`.
CREATE INDEX IF NOT EXISTS idx_persona_props_gin     ON ontology."Persona"     USING GIN (properties);
CREATE INDEX IF NOT EXISTS idx_lens_props_gin        ON ontology."Lens"        USING GIN (properties);
CREATE INDEX IF NOT EXISTS idx_domain_props_gin      ON ontology."Domain"      USING GIN (properties);
CREATE INDEX IF NOT EXISTS idx_discipline_props_gin  ON ontology."Discipline"  USING GIN (properties);
CREATE INDEX IF NOT EXISTS idx_community_props_gin   ON ontology."Community"   USING GIN (properties);

-- Edge tables also benefit from GIN on properties (used by bridges {strength: ...} filters).
CREATE INDEX IF NOT EXISTS idx_bridges_props_gin     ON ontology."bridges"     USING GIN (properties);

-- BTREE on the start_id / end_id columns AGE keeps — these power edge
-- traversal joins (Persona)-[:wields]->(Lens). AGE auto-indexes start_id
-- but a covering index on (start_id, end_id) helps two-hop joins.
CREATE INDEX IF NOT EXISTS idx_wields_endpoints     ON ontology."wields"        (start_id, end_id);
CREATE INDEX IF NOT EXISTS idx_in_domain_endpoints  ON ontology."in_domain"     (start_id, end_id);
CREATE INDEX IF NOT EXISTS idx_in_discipline_endpoints ON ontology."in_discipline" (start_id, end_id);
CREATE INDEX IF NOT EXISTS idx_member_of_endpoints  ON ontology."member_of"     (start_id, end_id);
CREATE INDEX IF NOT EXISTS idx_bridges_endpoints    ON ontology."bridges"       (start_id, end_id);

-- Note on G6 partial-index goal (current rows only):
-- Agtype containment queries `@> '{"valid_to": null}'::agtype` are tricky —
-- agtype distinguishes "key absent" from "key present with null value".
-- At spike time we measure the GIN-only baseline; if the verdict is
-- borderline we revisit partial-index strategies (e.g., a separate "current_lens"
-- materialized view) in F3.
