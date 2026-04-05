---
artifact_type: plan
bead: sylveste-ape
date: 2026-04-05
---

# Plan: interweave F1 — Plugin Scaffold + Type Family System

## Context

PRD: `docs/prds/2026-04-05-interweave.md` § F1
Brainstorm: `docs/brainstorms/2026-04-04-ontology-graph-brainstorm.md`

interweave is a generative ontology layer for agentic platforms. F1 creates the plugin scaffold and the core type family system: 5 families, 7 interaction rules, multi-family membership, lifecycle transitions.

**Language:** Python (uv project). Consistent with majority of interverse plugins.

## Directory Structure

```
interverse/interweave/
├── .claude-plugin/
│   └── plugin.json
├── CLAUDE.md
├── AGENTS.md
├── pyproject.toml
├── src/
│   └── interweave/
│       ├── __init__.py
│       ├── families.py      # 5 type families + entity type declarations
│       ├── rules.py         # 7 interaction rules (relational calculus)
│       └── engine.py        # query: valid_relationships(type_a, type_b)
└── tests/
    ├── test_families.py
    ├── test_rules.py
    └── test_engine.py
```

## Tasks

### T1: Plugin scaffold

Create `interverse/interweave/` with:
- `.claude-plugin/plugin.json` — name, version 0.1.0, description, author
- `CLAUDE.md` — module instructions, build/test commands
- `AGENTS.md` — architecture overview
- `pyproject.toml` — Python 3.12+, uv, pytest, ruff

### T2: Type families (families.py)

```python
class TypeFamily(Enum):
    ARTIFACT = "artifact"
    PROCESS = "process"
    ACTOR = "actor"
    RELATIONSHIP = "relationship"
    EVIDENCE = "evidence"

@dataclass
class EntityType:
    name: str
    families: list[TypeFamily]
    diagnostic_property: str  # identity-bearing field
    lifecycle_transitions: dict[str, list[TypeFamily]] = field(default_factory=dict)
    # e.g., {"reflection_distilled": [TypeFamily.EVIDENCE]}
```

Registry of built-in entity types:
- `file` → Artifact (path)
- `function` → Artifact (path + signature)
- `session` → Process (session_id), lifecycle: reflection_distilled → +Evidence
- `bead` → Process (bead_id)
- `agent` → Actor (agent_name)
- `finding` → Evidence (finding_id)
- `verdict` → Evidence (verdict_id)
- `discovery` → Evidence (discovery_id)
- `dependency` → Relationship (source + target + type)

`register_entity_type(et: EntityType)` — runtime registration for plugins.
`get_entity_type(name: str)` — lookup.
`get_families(entity_type_name: str)` — returns current family memberships.

### T3: Interaction rules (rules.py)

```python
@dataclass
class InteractionRule:
    name: str
    family_pair: tuple[TypeFamily | None, TypeFamily | None]
    # None means "any family"
    valid_relationships: list[str]
    namespace: str = "core"
```

7 built-in rules:
1. Productivity: (Actor, Process) → executes, dispatches, delegates, monitors
2. Transformation: (Process, Artifact) → produces, modifies, reads, consumes
3. Stewardship: (Actor, Artifact) → owns, maintains, created, reviewed
4. Structure: (same, same) → imports, depends-on, references, blocks, parent-child
5. Evidence Production: (any, Evidence) → produces, evaluates, asserts-about, measures
6. Annotation: (Evidence, Relationship) → validates, disputes, strengthens, weakens
7. Lifecycle: (any, any) → transition mechanism (not a relationship type itself)

`register_rule(rule: InteractionRule)` — extensibility point.
`get_rules_for_pair(family_a, family_b)` — returns matching rules + valid relationship types.

### T4: Relational calculus engine (engine.py)

```python
def valid_relationships(type_a: str, type_b: str) -> list[str]:
    """Given two entity type names, return all valid relationship types.

    Resolves both types to their family memberships, finds matching
    interaction rules for each family pair, returns union of valid
    relationship types. Multi-family entities produce a wider set.
    """

def apply_lifecycle_transition(entity_type: str, event: str) -> list[TypeFamily]:
    """Apply a lifecycle transition to an entity type.

    Returns the new family memberships after the transition.
    The relational calculus immediately applies to the expanded set.
    """
```

### T5: Tests

**test_families.py:**
- Entity type registration and lookup
- Family membership query
- Multi-family entity (session with Process + Evidence)
- Unclassified entity behavior (no families → empty relationships)

**test_rules.py:**
- Each of 7 rules returns correct relationship types
- Rule extensibility (register custom rule)
- Namespaced rule names

**test_engine.py:**
- valid_relationships for single-family entities
- valid_relationships for multi-family entities (union)
- Growth test: add new entity type, zero rule changes, relationships work
- Compositionality test: "delegation" via existing primitives
- Lifecycle transition: session gains Evidence membership
- Unclassified → no valid relationships

### T6: Documentation

- CLAUDE.md: working assumptions, build/test commands
- AGENTS.md: architecture, type family table, interaction rule matrix
- Interaction matrix appendix (15 unordered family pairs → governing rule)

## Verification

- `uv run pytest tests/ -v` — all tests pass
- `uv run ruff check src/` — lint clean
- Growth test passes (T5)
- Compositionality test passes (T5)
