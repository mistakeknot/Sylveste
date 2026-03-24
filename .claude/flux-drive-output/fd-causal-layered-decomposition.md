# Flux Drive: CLA Decomposition Pipeline Review

**Scope:** Correctness and completeness of the CLA decomposition pipeline in Khouri, its integration with SID graph and gap classification.
**Sources reviewed:** `apps/Khouri/PHILOSOPHY.md`, `apps/Khouri/docs/khouri-prd.md`, `shadow-work/docs/plans/2026-03-18-khouri-and-system-tracer-plan.md` (Tasks 1-11 with full code).

---

## Summary

The plan implements a three-stage MVP pipeline (CLA decomposition, ontology matching, gap synthesis) with three deferred stages (SID comparison, sheaf consistency, adversarial probing). The CLA decomposition agent correctly dispatches per-domain specialists that produce four-layer outputs. However, the architecture has a critical structural flaw: **CLA layer membership is discarded after Stage 1 and never propagated into the ontology matching, gap classification, or backlog synthesis stages.** The four CLA layers are generated correctly but then collapsed into flat concept lists, making it impossible for downstream stages to distinguish a myth-layer gap from a systemic-policy gap. This defeats the core value proposition of using CLA as the domain model for inverse scenario planning.

---

## Findings

### F1. CLA layer membership is lost during concept extraction (Severity: CRITICAL)

The `_extract_concepts()` function in `ontology_matching.py` (plan Task 5, lines 714-736) extracts concepts from `litany` and `systemic` fields only, explicitly ignoring `worldview` and `myth`:

```python
for text in [forecast.synthesis_cla.litany, forecast.synthesis_cla.systemic,
             forecast.synthesis_cla.worldview]:
    # ...
for text in [domain.cla.litany, domain.cla.systemic]:
    # ...
```

Even where `worldview` is included (synthesis CLA), it is mixed into the same `concepts` set with no layer tag. The `myth` field is never extracted at all. This means:
- Myth-level concepts (deep narratives, metaphors) are silently dropped from the entire pipeline.
- All extracted concepts lose their CLA layer provenance, becoming an unordered flat set of strings.
- Downstream gap classification cannot distinguish whether "radical hospitality" originated from the worldview layer (requiring discourse change) or the systemic layer (requiring policy change).

**Impact:** Backward traces will produce outputs only at the litany and systemic levels. Worldview and myth gaps — which in Inayatullah's methodology require fundamentally different intervention types (narrative reframing, mythic reimagination) — will either be misclassified as systemic gaps or lost entirely.

### F2. No schema field for CLA layer membership on mapped concepts (Severity: HIGH)

The `OntologyMapping` model (plan Task 2, lines 209-214) has fields `source_concept`, `target_entity`, `confidence`, and `rationale` — but no `cla_layer: CLALayer` field. Once a concept enters the matching pipeline, there is no way to reconstruct which CLA layer it came from. The `Gap` model (lines 227-237) similarly has no `cla_layer` field.

This is a schema-level omission. Even if `_extract_concepts()` were fixed to extract from all four layers, the data model cannot carry the layer information forward.

### F3. Gap classification types are CLA-unaware (Severity: HIGH)

The `GapType` enum (plan Task 2, lines 217-225) defines six gap types: `MISSING_MECHANISM`, `MISSING_AGENT_BEHAVIOR`, `MISSING_CASCADE_PATH`, `MISSING_INSTITUTION_TYPE`, `CALIBRATION_ISSUE`, `CREATIVE_TENSION`. These are all simulation-ontology-centric categories — they classify what is missing in the simulation, not what CLA layer the gap exists in.

In proper CLA methodology, gap types should be cross-indexed with layers:
- **Litany gaps** (observable phenomena missing) map naturally to `MISSING_MECHANISM` or `CALIBRATION_ISSUE`.
- **Systemic gaps** (structural forces missing) map to `MISSING_INSTITUTION_TYPE` or `MISSING_CASCADE_PATH`.
- **Worldview gaps** (ideological frames not representable) require a new gap type — something like `MISSING_DISCOURSE_FRAME` — since no simulation mechanism can directly model discourse.
- **Myth gaps** (deep narrative absence) require yet another type — `MISSING_NARRATIVE_ARCHETYPE` — since these demand generative or interpretive resolution, not engineering.

The current `CREATIVE_TENSION` type is the closest catch-all but is too vague. The LLM agent performing gap classification (in the `GAP_CLASSIFICATION_SYSTEM` prompt, Task 6 lines 880-902) has no instruction to consider CLA layer provenance when classifying gaps.

### F4. Synthesis agent drops worldview and myth from domain summaries (Severity: MEDIUM)

The `_synthesize()` function (Task 4, lines 511-540) constructs domain summaries for the synthesis agent as:

```python
f"## {d.domain.value.upper()}\n{d.summary}\nLitany: {d.cla.litany}\nSystemic: {d.cla.systemic}"
```

Worldview and myth fields from each domain forecast are not passed to the synthesis agent. The synthesis agent is asked to produce a unified CLA decomposition but only sees litany and systemic inputs. This means:
- The synthesis CLA's worldview and myth fields are fabricated from the summary text rather than synthesized from domain-level worldview and myth content.
- Cross-domain worldview contradictions (e.g., "collective resilience" in climate vs. "radical individualism" in economy) cannot be detected because the synthesis agent never sees them.

### F5. CausalClaim model lacks CLA layer attribution (Severity: MEDIUM)

The `CausalClaim` model (Task 2, lines 174-179) has `cause`, `effect`, `mechanism`, and `confidence` but no field indicating which CLA layer the causal relationship operates at. In CLA, causal mechanisms at different layers have fundamentally different characters:
- Litany-level causation: observable, empirical (e.g., "sea walls reduce flooding").
- Systemic-level causation: structural, policy-driven (e.g., "climate investment creates adaptation industry").
- Worldview-level causation: discursive, ideological (e.g., "collective resilience framing enables sacrifice acceptance").
- Myth-level causation: narrative, archetypal (e.g., "the ark city myth drives settler identity").

Without layer attribution, the SID graph (Task 12, deferred) will build a single-layer causal DAG that conflates empirical and narrative causation. The sheaf consistency checker (Task 13, deferred) will have no layer axis to enforce cross-layer coherence constraints.

### F6. No inter-layer dependency edges in the data model (Severity: HIGH)

The plan describes CLA as having four layers with asymmetric dependency (myth underpins worldview, worldview underpins systemic, systemic produces litany). However, no data structure captures these inter-layer edges. The `CLADecomposition` model is four flat string fields with no relational structure between them.

For backward tracing to work — "what myth must exist for this worldview to hold?" — the pipeline needs explicit edges like:
```
myth:"the ark city" --underpins--> worldview:"collective resilience" --sustains--> systemic:"climate adaptation investment" --produces--> litany:"sea walls, floating districts"
```

These edges are the backbone of inverse scenario planning. Without them, the backward trace degenerates into four parallel flat lists with no traversal path.

### F7. Backlog synthesis does not re-integrate CLA structure (Severity: MEDIUM)

The `GapReport` model (Task 2, lines 239-244) contains `gaps` (a flat list) and `unmapped_concepts` (a flat string list). There is no grouping by CLA layer, no dependency ordering, and no indication of which gaps must be resolved before others (e.g., you cannot fill a systemic gap if the underlying worldview gap is unresolved).

The `generate_backlog()` method on `ProjectAdapter` (Task 3, line 357) takes a `GapReport` and returns `list[dict]` — a flat list with no schema. This prevents downstream consumers from implementing layer-aware prioritization (e.g., "resolve myth gaps first because they constrain all other layers").

### F8. Domain-specialist prompt elicits CLA correctly (Severity: POSITIVE)

The `DOMAIN_AGENT_SYSTEM` prompt (Task 4, lines 440-455) correctly defines all four CLA layers with appropriate Inayatullah-aligned descriptions:
- Litany = "Observable surface phenomena"
- Systemic = "Structural forces and systems producing the litany"
- Worldview = "Ideological frames, values, and discourse that sustain the system"
- Myth = "Deep narratives and metaphors that give the worldview its power"

The prompt also correctly requests causal claims, making the LLM output structurally sound. The problem is not generation quality but downstream loss of layer information.

---

## Recommendations

### R1. Add `cla_layer` field to `OntologyMapping`, `Gap`, and `CausalClaim` (addresses F2, F5)

```python
class OntologyMapping(BaseModel):
    source_concept: str
    cla_layer: CLALayer  # NEW
    target_entity: str | None = None
    confidence: MappingConfidence = MappingConfidence.NONE
    rationale: str = ""

class CausalClaim(BaseModel):
    cause: str
    effect: str
    mechanism: str = ""
    confidence: float = Field(default=0.5, ge=0.0, le=1.0)
    source_layer: CLALayer = CLALayer.LITANY  # NEW
    target_layer: CLALayer = CLALayer.LITANY  # NEW — enables cross-layer edges
```

### R2. Refactor `_extract_concepts()` to return layer-tagged tuples (addresses F1)

Replace `set[str]` with `list[tuple[str, CLALayer]]`. Extract from all four CLA layers, tagging each concept with its origin layer. Pass the layer tag through to `OntologyMapping`.

### R3. Add CLA-aware gap types (addresses F3)

Extend `GapType` or add a parallel `GapLayer` dimension:
```python
class GapType(str, Enum):
    # Existing simulation-centric types...
    MISSING_DISCOURSE_FRAME = "missing_discourse_frame"     # worldview layer
    MISSING_NARRATIVE_ARCHETYPE = "missing_narrative_archetype"  # myth layer
    WORLDVIEW_CONFLICT = "worldview_conflict"  # cross-domain worldview tension
```

Update the `GAP_CLASSIFICATION_SYSTEM` prompt to instruct the LLM to consider CLA layer provenance when classifying gaps and to use the new types for worldview/myth gaps.

### R4. Pass all four CLA layers to synthesis agent (addresses F4)

Change the domain summary format in `_synthesize()` to include worldview and myth:
```python
f"Litany: {d.cla.litany}\nSystemic: {d.cla.systemic}\nWorldview: {d.cla.worldview}\nMyth: {d.cla.myth}"
```

### R5. Add a `CLAGraph` model for inter-layer edges (addresses F6)

```python
class CLAEdge(BaseModel):
    """Directed dependency edge between CLA layer concepts."""
    source_concept: str
    source_layer: CLALayer
    target_concept: str
    target_layer: CLALayer
    relationship: str  # "underpins", "sustains", "produces", "challenges"

class CLAGraph(BaseModel):
    """Full CLA decomposition with inter-layer dependency edges."""
    decomposition: CLADecomposition
    edges: list[CLAEdge] = Field(default_factory=list)
```

Request the domain agents to produce inter-layer edges alongside causal claims. This gives the SID graph (Task 12) the directed cross-layer edges it needs.

### R6. Structure `GapReport` with layer grouping (addresses F7)

```python
class GapReport(BaseModel):
    gaps_by_layer: dict[CLALayer, list[Gap]] = Field(default_factory=dict)
    resolution_order: list[CLALayer] = Field(
        default_factory=lambda: [CLALayer.MYTH, CLALayer.WORLDVIEW, CLALayer.SYSTEMIC, CLALayer.LITANY]
    )
    # ... existing fields ...
```

This enables the backlog synthesis agent to generate work items in dependency order: myth gaps first, then worldview, then systemic, then litany.

### R7. Add a validation test for layer coverage (addresses all findings)

Add a test that asserts the pipeline produces at least one gap or mapped concept at each of the four CLA layers. This acts as a regression gate ensuring layer information is not silently dropped in future refactors.

```python
def test_pipeline_produces_all_four_layers(report):
    layers_present = {g.cla_layer for g in report.gaps}
    assert CLALayer.MYTH in layers_present or CLALayer.WORLDVIEW in layers_present, \
        "Pipeline must not collapse to litany+systemic only"
```
