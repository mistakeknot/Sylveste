# Quality Review: Khouri Domain Model Plan

**Scope:** `apps/Khouri/src/khouri/models.py` + `tests/test_models.py` (planned)
**Languages in scope:** Python 3.12+

## Summary

The plan is structurally sound and covers the domain well. Most issues are correctness-adjacent (mypy strict failures, runtime validation gaps) rather than cosmetic. Three items warrant fixing before implementation; the rest are improvements.

## Must-Fix (3)

### 1. CLAGraph will fail mypy strict without explicit annotations
networkx has no py.typed marker — mypy strict will error on Any-propagation. Fix: declare a minimal Protocol or annotate internal field as Any explicitly.

### 2. Bounded-float fields need `Annotated` constraints
confidence, severity, score, weight described as 0-1 ranges but bare `float` won't validate at runtime. Use `Annotated[float, Field(ge=0.0, le=1.0)]` type aliases.

### 3. GapReport.resolution_order duplicates gaps_by_layer
Stored list alongside dict duplicates every gap — will drift on mutation. Prefer `@computed_field` or derive from dict on demand.

## Improvements (6)

4. CLADecomposition.layers should validate completeness (all 4 layers present) or expose `is_complete`
5. Consider split into cla.py/causal.py/gaps.py with models.py as re-export facade (matches CONVENTIONS.md)
6. CLA_DEPTH_ORDER should be `Final` with explicit index-0-is-deepest comment
7. StructuredForecast.generated_at should default to `datetime.now(timezone.utc)`
8. OntologyMapping.target_entities should use a type alias for future upgrade
9. CLAEdge.relationship should be Literal or small enum, not free str

## Test Notes
- Test validator failure paths (confidence=1.5, severity=-0.1)
- Test GapReport resolution_order ordering contract against CLA_DEPTH_ORDER
- Use model_dump()/model_validate() (v2 API), not .dict()/.parse_obj()

## Ruff/Mypy Notes
- Add `extend-ignore-names = ["CLA*"]` to ruff pep8-naming to avoid N801 on CLA prefix
- SIM sort pattern: `sorted(..., key=lambda g: CLA_DEPTH_ORDER.index(g.cla_layer))`
