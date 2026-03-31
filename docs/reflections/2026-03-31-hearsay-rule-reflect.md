---
artifact_type: reflection
bead: sylveste-rsj.12
stage: reflect
---

# Reflect: Hearsay Rule (rsj.12)

## What worked
- The existing reaction prompt already had `Independent Coverage` and `Evidence` fields — the hearsay classification maps directly onto these without requiring agents to change their output format
- Adding a step between reaction ingestion and sycophancy scoring was clean — the pipeline stages compose naturally
- The weight system (1.0/0.5/0.0) for independent/reactive/hearsay is simple and auditable

## Key design choice
- Hearsay reactions are tagged and discounted, NOT removed from the report. This preserves the information while preventing it from inflating convergence scores. The user can still see that Agent B agreed with Agent A — they just know it was agreement-by-citation rather than independent verification.

## What to watch
- The heuristic for detecting hearsay ("cites original agent by name") depends on agents actually naming each other in their rationale. If agents learn to avoid naming peers while still parroting their findings, the detection fails. The `Independent Coverage: no` field is the stronger signal.
- This is a synthesis-agent-level instruction, so it works without runtime enforcement. If a different synthesis agent is used, the hearsay rule won't apply. Consider extracting it into a reusable synthesis primitive if more synthesis agents emerge.
