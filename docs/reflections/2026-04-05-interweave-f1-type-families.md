---
artifact_type: reflection
bead: sylveste-ape
date: 2026-04-05
---

# Reflection: interweave F1 — Plugin Scaffold + Type Family System

## What worked

The brainstorm's convergence finding — "a small set of composable type primitives generates the complete relationship matrix" — translated directly into code. 5 families + 7 rules + the engine function `valid_relationships(type_a, type_b)` is the entire API surface. The growth test and compositionality test both pass without any special-casing.

The interaction matrix (15 unordered family pairs, all covered) was verified by a dedicated test that iterates all pairs and asserts at least one rule matches.

## What to watch

1. **Module-level mutation:** The `apply_lifecycle_transition` function mutates `EntityType.families` in-place. This is intentional for runtime use (an entity type permanently gains new family membership), but caused test isolation issues. Fixed by deep-copying builtins in the registry reset fixture. Any future consumers of lifecycle transitions must be aware that it's a mutating operation.

2. **Structure rule scope:** Only fires for Artifact×Artifact, not all same-family pairs. This is correct (imports/depends-on are artifact relationships), but means Process×Process pairs only get `transitions-to` from the lifecycle rule. If we later need "Process blocks Process" or "Process triggers Process", we'll need to extend the structure rule or add a new one.

3. **Wildcard rules flood the relationship set:** Evidence Production (any→Evidence) and Lifecycle (any→any) match many pairs, making the relationship type list noisy. F5 (named query templates) will need to filter by relevance, not just validity. A relationship being valid doesn't mean it's likely.

## Reusable pattern

The family-pair relational calculus pattern (small set of families, interaction rules as the product space, entity types inherit via membership) is reusable for any domain where relationship types between entities should be derivable rather than declared per-pair.
