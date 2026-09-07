---
artifact_type: brainstorm
beads: [sylveste-7ps, sylveste-8au, sylveste-d7w]
scope: interweave F4 (confidence), F6 (salience), F7 (gravity-well safeguards)
---

# Interweave F4/F6/F7: Confidence, Salience, and Gravity-Well Safeguards

## Context

Interweave's identity crosswalk stores confidence levels (`confirmed | probable | speculative`) and provenance (`method`, timestamps) for every link — but query templates never expose them. Results treat all relationships equally regardless of confidence or relevance. As the graph grows, hub entities (common files, prolific actors) will dominate results, drowning out rare but informative connections.

Three features address this:
- **F4** — surface confidence and provenance in query results, add filtering
- **F6** — rank results by relevance to the asking context
- **F7** — detect and dampen graph concentration around dominant entities

## Current State

**What exists:**
- `identity_links.confidence` column: `confirmed | probable | speculative`
- `identity_links.method` column: e.g., `path-match`, `git-config`, `body-similarity`
- `identity_links.created_at` / `last_verified_at` timestamps
- 10 query templates producing `QueryResult(entities, relationships, metadata)`
- 7 interaction rules in the relational engine
- `detect_renames.py` computes body similarity and assigns confidence (CONFIRMED_THRESHOLD=0.95, PROBABLE_THRESHOLD=0.80)

**What's missing:**
- Confidence not included in relationship dicts returned by templates
- No `created_by` field (which agent/tool registered a link)
- No result ranking by relevance or graph position
- No centrality/degree metrics, no diversity enforcement
- Templates follow chains linearly without weighting

## F4: Confidence Scoring + Link Provenance

### Core idea

Every relationship in `QueryResult.relationships` should carry its provenance: how confident are we, who registered it, by what method, and when. Callers can filter by confidence threshold.

### Design

1. **Enrich relationship dicts**: When templates materialize chains into relationships, include `confidence`, `method`, `created_at`, `last_verified_at` from the underlying `identity_links` row.

2. **Add `created_by` to schema**: New column on `identity_links` and `actors` tables. Default `"system"`. Connectors pass their connector name. Migration: add column with default, bump `SCHEMA_VERSION` to 2.

3. **Template filtering parameter**: Add optional `min_confidence` to `QueryTemplate.execute()` context. Templates skip relationships below the threshold. Default: include all (backward compatible).

4. **Metadata enrichment**: Add `confidence_distribution: dict[str, int]` to `QueryResultMetadata` — counts of confirmed/probable/speculative links in the result.

### Key constraints
- Schema migration must be backward compatible (no data loss)
- Existing tests must continue passing with no changes
- Confidence filtering is additive (templates that don't support it ignore the parameter)

## F6: Query-Context Salience

### Core idea

When a template runs, the result should be sorted by relevance to the query context — not just returned in chain-traversal order. "Salience" means: how informative is this entity/relationship for answering the specific question?

### Design

1. **Salience scoring module** (`src/interweave/salience.py`):
   - Input: list of entities/relationships + query context (entity_id, optional keywords)
   - Output: scored list with `salience: float` per item
   - Scoring factors:
     - **Graph distance**: Closer to the query entity = higher salience
     - **Confidence**: Higher confidence links = higher salience
     - **Recency**: More recently verified links = higher salience
     - **Rarity**: Entities with fewer total links = more informative (inverse degree)

2. **QueryContext enrichment**: Add `salience_context: dict` to the context passed to templates. Contains `query_entity_id`, `keywords`, `salience_mode` (off/light/full).

3. **Template integration**: Templates that return relationships call `score_salience(relationships, context)` before returning. Sorted by salience descending.

4. **Metadata**: Add `salience_applied: bool` and `salience_mode: str` to `QueryResultMetadata`.

### Key constraints
- Salience is opt-in: `salience_mode=off` is default (backward compatible)
- Scoring must be O(n) where n = result count (no graph traversal at query time beyond what templates already do)
- No external dependencies (pure Python)

## F7: Gravity-Well Safeguards

### Core idea

Prevent the ontology from collapsing into hub-dominated results. A "gravity well" is when a small number of entities (common files like `__init__.py`, prolific actors, umbrella beads) account for a disproportionate share of relationships, drowning out rare but informative connections.

### Design

1. **Degree tracking**: Maintain in-memory entity degree counts (updated on `link()` and `register()`). No new table — computed on load from existing data.

2. **Concentration detection**: `detect_gravity_wells(threshold=0.05)` returns entities where a single entity holds >5% of all relationships. Exposed via a diagnostic method, not query-time.

3. **Result diversification**: When `diversity_mode=true` in query context:
   - Cap any single entity's appearances in results to `max_entity_frequency` (default: 3)
   - For hub entities exceeding the cap, keep only the highest-salience relationships
   - Add `diversity_applied: bool` and `entities_capped: list[str]` to metadata

4. **Gravity-well metadata**: `QueryResultMetadata` gets `gravity_wells: list[str]` — canonical IDs of entities flagged as hubs in the current result. Callers can display a warning.

### Key constraints
- Diversification is opt-in (`diversity_mode=false` by default)
- Never drop confirmed links — only reorder or cap probable/speculative ones
- Gravity-well detection is a read-only diagnostic, not a write operation

## Dependency Graph

```
F4 (confidence/provenance) → F6 (salience uses confidence as a scoring factor)
F4 (confidence/provenance) → F7 (diversification preserves confirmed links)
F6 (salience scoring) → F7 (diversification applies after salience scoring)
```

All three features modify the same files:
- `storage.py` — schema migration (F4)
- `crosswalk.py` — `created_by` parameter (F4), degree tracking (F7)
- `templates/protocol.py` — metadata fields (all three)
- Individual templates — confidence filter (F4), salience sort (F6), diversification cap (F7)
- New modules: `salience.py` (F6), `gravity.py` (F7)

## Risks

1. **Performance**: Salience scoring adds O(n) cost per query. For small result sets (<100 entities) this is negligible. If result sets grow, may need caching.
2. **Schema migration**: Adding `created_by` column requires version bump. Must handle upgrade from v1 gracefully.
3. **Gravity-well false positives**: Legitimate hub entities (e.g., a core module imported everywhere) shouldn't be penalized for being central. The cap approach (limit appearances, don't exclude) mitigates this.
4. **Test surface**: 179 existing tests must keep passing. New features need ~50 new tests across the three modules.

## Decision: Batch or Sequential?

These three features share significant infrastructure (metadata fields, template parameter passing, storage migration). Implementing them as a single batch avoids:
- Multiple schema migrations
- Multiple passes over the template protocol
- Metadata field additions spread across separate PRs

**Recommendation**: Single plan with 6-8 tasks, executed in F4→F6→F7 order within one sprint.
