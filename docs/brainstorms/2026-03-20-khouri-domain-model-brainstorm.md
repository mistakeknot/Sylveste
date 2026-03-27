---
artifact_type: brainstorm
bead: Sylveste-xk68
stage: discover
---

# Core Domain Model with CLA Layer Provenance

## What We're Building

Pydantic models for Khouri's CLA inverse scenario planning pipeline. Every model carries its CLA layer (Litany, Social Causes, Discourse/Worldview, Myth/Metaphor) so gap analysis and forecasting can operate per-layer.

**Models:** CLALayer enum, CLADecomposition, CLAEdge, CLAGraph (networkx-backed), CausalClaim (with source_layer/target_layer), ForecastDomain, DomainForecast, StructuredForecast, OntologyMapping (with cla_layer + target_entities for coalitions), MappingConfidence, GapType (including MISSING_DISCOURSE_FRAME, MISSING_NARRATIVE_ARCHETYPE, WORLDVIEW_CONFLICT), Gap (with cla_layer), GapReport (with gaps_by_layer + resolution_order).

## Why This Approach

The parent epic (Sylveste-31g4) defines a 10-stage hybrid pipeline. The domain model is P0 because every stage depends on these types. Threading CLA layer through the entire model graph enables:
- Layer-specific gap classification (Stage 6)
- Layer-ordered backlog synthesis (Stage 7)
- Cross-layer causal edges in the graph (Stage 1)
- Per-layer ontology matching (Stage 2b)

## Key Decisions

- **Pydantic v2 models** — validation, serialization, schema generation out of the box
- **CLALayer as str enum** — used as dict keys in GapReport.gaps_by_layer, must be serializable
- **NetworkX for CLAGraph** — matches epic dependency list, handles directed multigraph for cross-layer edges
- **Flat module** — single `models.py` until complexity warrants splitting

## Open Questions

- Should CLAGraph expose networkx directly or wrap it? (Decide during implementation — start with direct exposure, abstract if needed.)
- MappingConfidence scoring model — simple float confidence vs structured breakdown? (Start simple.)
