---
artifact_type: prd
beads: [sylveste-7ps, sylveste-8au, sylveste-d7w]
---

# Interweave F4/F6/F7: Confidence, Salience, Gravity-Well Safeguards

## Problem

Interweave's query templates return relationships without confidence, provenance, or relevance ranking. All links are treated equally. As the graph grows, hub entities dominate results. Three gaps:

1. **F4**: Confidence and provenance stored but never exposed in results
2. **F6**: Results unranked — no relevance to the asking context
3. **F7**: No protection against graph concentration around dominant entities

## Features

### F4: Confidence Scoring + Link Provenance
- Relationship dicts include `confidence`, `method`, `created_at`, `created_by`
- Optional `min_confidence` filter in query context
- `confidence_distribution` in result metadata
- Schema v2: add `created_by` column to `identity_links` and `actors`

### F6: Query-Context Salience
- New `salience.py` module: scores entities by graph distance, confidence, recency, rarity
- Opt-in via `salience_mode` in query context (off/light/full)
- Templates sort results by salience when enabled
- `salience_applied` flag in metadata

### F7: Gravity-Well Safeguards
- Degree-based hub detection: `detect_gravity_wells(threshold)`
- Opt-in `diversity_mode`: caps per-entity appearance in results
- Never drops confirmed links — only reorders or caps probable/speculative
- `gravity_wells` list in metadata for caller warnings

## Non-Goals
- Graph visualization
- Real-time streaming updates
- External search integration
- Breaking existing test contracts

## Success Criteria
- 179 existing tests continue passing
- Each feature adds ~15-20 new tests
- Schema migration is backward compatible
- All features are opt-in (default behavior unchanged)
