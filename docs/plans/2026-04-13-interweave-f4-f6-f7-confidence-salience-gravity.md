---
artifact_type: plan
bead: sylveste-7ps
stage: design
requirements:
  - F4: Confidence scoring + link provenance
  - F6: Query-context salience
  - F7: Gravity-well safeguards
---

# Interweave F4/F6/F7 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-7ps (primary), sylveste-8au, sylveste-d7w
**Goal:** Surface confidence/provenance in query results, rank by salience, prevent graph concentration.

**Tech Stack:** Python 3.12, sqlite3 (stdlib), existing interweave template framework.

---

## Must-Haves

**Truths:**
- Relationships in QueryResult carry confidence, method, created_at, created_by
- Templates accept min_confidence filter (backward compatible default: include all)
- Results can be sorted by salience (graph distance, confidence, recency, rarity)
- Hub entities are detected and their appearances capped in results
- 179 existing tests continue passing

**Artifacts:**
- Modified: `src/interweave/storage.py` — schema v2
- Modified: `src/interweave/templates/protocol.py` — metadata fields, QueryContext params
- Modified: all 10 templates — confidence enrichment
- Created: `src/interweave/salience.py` — scoring module
- Created: `src/interweave/gravity.py` — hub detection and diversification

---

### Task 1: Schema migration — add created_by column

**Files:**
- Modify: `src/interweave/storage.py`
- Test: `tests/test_storage.py`

**Step 1: Write failing test**
```python
# Add to tests/test_storage.py
class TestCreatedBy:
    def test_link_stores_created_by(self, db):
        db.upsert_entity("git:src/main.py", "file", "artifact", {})
        db.add_identity_link(
            subsystem="beads", subsystem_id="file:src/main.py",
            canonical_id="git:src/main.py",
            confidence="confirmed", method="path-match",
            created_by="connector:beads",
        )
        links = db.get_links_for("git:src/main.py")
        assert links[0]["created_by"] == "connector:beads"

    def test_link_defaults_created_by(self, db):
        db.upsert_entity("git:src/main.py", "file", "artifact", {})
        db.add_identity_link(
            subsystem="beads", subsystem_id="file:src/main.py",
            canonical_id="git:src/main.py",
            confidence="confirmed", method="path-match",
        )
        links = db.get_links_for("git:src/main.py")
        assert links[0]["created_by"] == "system"

    def test_schema_version_2(self, db):
        conn = sqlite3.connect(db.path)
        version = conn.execute("PRAGMA user_version").fetchone()[0]
        assert version == 2
        conn.close()
```

**Step 2: Implement**

In `storage.py`:
1. Add `created_by TEXT NOT NULL DEFAULT 'system'` to `identity_links` and `actors` CREATE TABLE statements
2. Bump `SCHEMA_VERSION` to 2
3. Add migration logic: if `user_version == 1`, run `ALTER TABLE identity_links ADD COLUMN created_by TEXT NOT NULL DEFAULT 'system'` and same for `actors`, then set `user_version = 2`
4. Update `add_identity_link()` signature: add optional `created_by: str = "system"` parameter
5. Update `upsert_actor()` similarly

**Step 3: Run tests**
```bash
cd interverse/interweave && uv run pytest tests/test_storage.py -v
```

---

### Task 2: Enrich relationship dicts with confidence/provenance

**Files:**
- Modify: `src/interweave/storage.py` — new method `get_chain_with_provenance()`
- Modify: `src/interweave/crosswalk.py` — expose provenance in `follow_chain()`
- Test: `tests/test_crosswalk.py`

**Step 1: Write failing test**
```python
# Add to tests/test_crosswalk.py
class TestChainProvenance:
    def test_chain_includes_confidence(self, crosswalk):
        crosswalk.register(subsystem="git", native_id="old.py:f", entity_type="function", family="artifact")
        crosswalk.register(subsystem="git", native_id="new.py:f", entity_type="function", family="artifact")
        crosswalk.record_rename(from_id="git:old.py:f", to_id="git:new.py:f", confidence="confirmed")
        chain = crosswalk.follow_chain("git:old.py:f")
        assert chain[0]["confidence"] == "confirmed"

    def test_links_include_provenance(self, crosswalk):
        crosswalk.register(subsystem="git", native_id="src/main.py", entity_type="file", family="artifact")
        crosswalk.link(
            subsystem="beads", subsystem_id="file:src/main.py",
            canonical_id="git:src/main.py",
            confidence="probable", method="path-match",
        )
        links = crosswalk.get_links("git:src/main.py")
        assert links[0]["confidence"] == "probable"
        assert links[0]["method"] == "path-match"
        assert "created_at" in links[0]
```

**Step 2: Implement**

In `crosswalk.py`:
- Add `get_links(canonical_id) -> list[dict]` method that wraps `_db.get_links_for()` and returns full dicts including confidence, method, created_at, created_by
- Existing `follow_chain()` already returns dicts from `get_chain()` which include confidence — verify this

---

### Task 3: QueryContext and metadata extensions

**Files:**
- Modify: `src/interweave/templates/protocol.py`
- Test: `tests/test_templates_core.py`

**Step 1: Extend QueryContext**
```python
@dataclass
class QueryContext:
    crosswalk: Any
    connector_registry: Any
    min_confidence: str | None = None  # F4: filter threshold
    salience_mode: str = "off"  # F6: off | light | full
    salience_entity_id: str | None = None  # F6: center entity for distance scoring
    diversity_mode: bool = False  # F7: cap hub entity appearances
    max_entity_frequency: int = 3  # F7: max times a single entity appears
```

**Step 2: Extend QueryResultMetadata**
```python
@dataclass
class QueryResultMetadata:
    # ... existing fields ...
    confidence_distribution: dict[str, int] = field(default_factory=dict)  # F4
    salience_applied: bool = False  # F6
    diversity_applied: bool = False  # F7
    entities_capped: list[str] = field(default_factory=list)  # F7
    gravity_wells: list[str] = field(default_factory=list)  # F7
```

**Step 3: Update `to_dict()`** to include new metadata fields.

**Step 4: Write test**
```python
class TestMetadataExtensions:
    def test_confidence_distribution_serialized(self):
        meta = QueryResultMetadata(
            template_name="test", template_version="1.0.0",
            execution_timestamp="2026-04-13T00:00:00Z",
            confidence_distribution={"confirmed": 3, "probable": 1},
        )
        result = QueryResult(entities=[], relationships=[], metadata=meta)
        d = result.to_dict()
        assert d["metadata"]["confidence_distribution"] == {"confirmed": 3, "probable": 1}
```

---

### Task 4: Template confidence enrichment — entity_relationships

**Files:**
- Modify: `src/interweave/templates/entity_relationships.py`
- Test: `tests/test_templates_core.py`

**Step 1: Enrich chain_relationships with provenance**

In `execute()`, when building `chain_relationships`, include the chain's confidence and provenance:
```python
chain_relationships.append({
    "source": canonical_id,
    "target": chain["to_id"],
    "type": chain.get("relation", "related"),
    "confidence": chain.get("confidence", "speculative"),
    "method": chain.get("method"),
    "created_at": chain.get("created_at"),
})
```

**Step 2: Apply min_confidence filter**
```python
if context.min_confidence:
    CONFIDENCE_ORDER = {"confirmed": 0, "probable": 1, "speculative": 2}
    min_level = CONFIDENCE_ORDER.get(context.min_confidence, 2)
    chain_relationships = [
        r for r in chain_relationships
        if CONFIDENCE_ORDER.get(r.get("confidence", "speculative"), 2) <= min_level
    ]
```

**Step 3: Populate confidence_distribution in metadata**

**Step 4: Apply same pattern to all other templates** that produce relationships. This is a mechanical change across 9 remaining templates — confidence enrichment is identical for each.

---

### Task 5: Salience scoring module

**Files:**
- Create: `src/interweave/salience.py`
- Test: `tests/test_salience.py`

**Design:** Pure function, no state.

```python
def score_salience(
    entities: list[dict],
    relationships: list[dict],
    center_entity_id: str | None = None,
    mode: str = "light",
) -> tuple[list[dict], list[dict]]:
    """Score and sort entities/relationships by salience.
    
    Returns (sorted_entities, sorted_relationships) with salience: float added.
    
    Scoring factors (light mode):
    - confidence: confirmed=1.0, probable=0.7, speculative=0.4
    - recency: newer created_at = higher score (linear decay over 30 days)
    
    Scoring factors (full mode, adds):
    - graph_distance: hop count from center_entity_id (1/distance)
    - rarity: 1 / (entity appearance count in relationships)
    """
```

Test cases:
- confirmed relationships scored higher than speculative
- entities closer to center entity scored higher
- hub entities (many appearances) scored lower than rare entities
- mode=off returns input unchanged

---

### Task 6: Gravity-well detection and diversification

**Files:**
- Create: `src/interweave/gravity.py`
- Test: `tests/test_gravity.py`

```python
def detect_gravity_wells(
    relationships: list[dict],
    threshold: float = 0.05,
) -> list[str]:
    """Return canonical_ids that account for >threshold fraction of all relationships."""

def diversify_results(
    entities: list[dict],
    relationships: list[dict],
    max_entity_frequency: int = 3,
    preserve_confidence: str = "confirmed",
) -> tuple[list[dict], list[dict], list[str]]:
    """Cap per-entity appearances. Never drops links at preserve_confidence level.
    
    Returns (filtered_entities, filtered_relationships, capped_entity_ids).
    """
```

Test cases:
- Hub entity (>5% of relationships) detected
- Diversification caps appearances at max_entity_frequency
- Confirmed links never dropped even when entity exceeds cap
- Empty input returns empty output

---

### Task 7: Wire salience + gravity into template execution

**Files:**
- Modify: `src/interweave/templates/entity_relationships.py` (exemplar)
- Create: `src/interweave/templates/_postprocess.py` — shared post-processing

Create a shared post-processing function that all templates can call after building their results:

```python
# src/interweave/templates/_postprocess.py
def postprocess_results(
    result: QueryResult,
    context: QueryContext,
) -> QueryResult:
    """Apply salience scoring and gravity-well diversification.
    
    Called at the end of template execute(), modifies result in-place.
    """
    if context.salience_mode != "off":
        result.entities, result.relationships = score_salience(
            result.entities, result.relationships,
            center_entity_id=context.salience_entity_id,
            mode=context.salience_mode,
        )
        result.metadata.salience_applied = True
    
    if context.diversity_mode:
        wells = detect_gravity_wells(result.relationships)
        result.metadata.gravity_wells = wells
        result.entities, result.relationships, capped = diversify_results(
            result.entities, result.relationships,
            max_entity_frequency=context.max_entity_frequency,
        )
        result.metadata.diversity_applied = True
        result.metadata.entities_capped = capped
    
    return result
```

Wire into entity_relationships.py at the end of `execute()`:
```python
return postprocess_results(result, context)
```

Apply to remaining templates.

---

### Task 8: Integration test

**Files:**
- Modify: `tests/test_templates_composite.py` or create `tests/test_f4_f6_f7_integration.py`

End-to-end test:
1. Create crosswalk with entities at different confidence levels
2. Run entity_relationships with `min_confidence="confirmed"` — verify speculative filtered
3. Run with `salience_mode="light"` — verify sorted by score
4. Run with `diversity_mode=True` — verify hub capped
5. Check all metadata fields populated correctly

---

## Execution Order

```
Task 1 (schema migration) → Task 2 (provenance exposure)
                                    │
Task 3 (protocol extensions) ◄─────┘
                                    │
Task 4 (template enrichment) ◄─────┘
                                    │
Task 5 (salience module) ──── (parallel with Task 4)
Task 6 (gravity module) ──── (parallel with Task 4-5)
                                    │
Task 7 (wire postprocessing) ◄─────┘
                                    │
Task 8 (integration test) ◄────────┘
```

**Parallelizable:** Tasks 4+5+6 (no shared files). Tasks 1→2→3 sequential. Task 7 after 4+5+6. Task 8 after all.
