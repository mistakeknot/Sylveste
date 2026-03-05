---
artifact_type: brainstorm
bead: none
stage: discover
---

# CUJs as First-Class Artifacts in Demarch

## What We're Building

Critical User Journeys (CUJs) as a new first-class artifact type in Demarch, sitting alongside PRDs, roadmaps, vision docs, and changelogs. CUJs serve three roles simultaneously:

1. **Planning artifact** -- documents user journeys to inform what gets built and prioritized (humans consume)
2. **Agent guardrails** -- defines expected end-to-end flows that agents should preserve during development
3. **Testing / acceptance criteria** -- success signals map to validation that agents and smoke tests can check

CUJs use a **hierarchical** model: top-level journeys contain steps, and steps can link to sub-journeys (separate CUJ files) for drill-down. However, the format is **prose-first** -- the hierarchy emerges from links between documents, not from rigid schema nesting.

## Why This Approach

### Prose-first with structured success signals

The core design bet: CUJ bodies are freeform prose (like PRDs and vision docs), but **success signals** are semi-structured tables with typed assertions. This is the minimum machine-readable contract agents need for validation.

**Why not structured step tables or node graphs?**

- Linear step tables work for CLI flows but break down for games/complex UIs where journeys are non-linear, state-dependent, and emergent
- Node graphs are powerful but expensive to author and maintain -- and agents don't need a formal graph to validate "did the player find crafting within 15 minutes?"
- Prose naturally describes both linear flows ("configure, then deploy") and exploratory flows ("player discovers crafting organically") without format friction
- Extensions (step tables, mermaid diagrams, emotional arcs) can be added inline as standard markdown when useful -- the schema doesn't need to anticipate them

**Why typed success signals?**

Agents need to know which assertions they can auto-check vs. which need human judgment:

- **measurable** -- quantitative, automatable (HTTP 200, < 5min, no errors)
- **observable** -- detectable but requires instrumentation (player inventory changes, user clicks X)
- **qualitative** -- requires human judgment (feels intuitive, creates tension)

### Follows existing artifact conventions

CUJs integrate into the existing Demarch artifact lifecycle:

- **Frontmatter**: `artifact_type: cuj` with journey name, actor, criticality, bead link
- **Location**: `docs/cujs/` (dedicated directory, like `docs/prds/`, `docs/brainstorms/`)
- **Generation**: new interpath phase (`interpath:cuj`) or manual authoring
- **Drift detection**: interwatch monitors via two-tier signals:
  - *Feature-change driven* (cheap, proactive): beads closed that touch CUJ-referenced components, UI/API changes, new brainstorms redefining user flows
  - *Test-result driven* (expensive, reactive): success signals start failing in smoke tests or acceptance criteria
- **Refresh**: standard interwatch confidence tiers (Certain/High/Medium/Low) trigger regeneration or user prompt

## Key Decisions

1. **Prose-first format** -- CUJ bodies are freeform markdown, not structured step schemas. This scales from simple CLI flows to complex game UIs without format friction.

2. **Typed success signals as the machine-readable contract** -- a table with Signal/Type/Assertion columns. Types: measurable, observable, qualitative. This is what agents validate against.

3. **Hierarchical via linking, not nesting** -- top-level CUJs link to sub-journey CUJ files rather than embedding nested schemas. Keeps individual files simple.

4. **Lean four-section template**:
   - Why This Journey Matters (motivation)
   - The Journey (prose narrative)
   - Success Signals (typed assertion table)
   - Known Friction Points (current pain points)

5. **Two-tier drift detection** -- feature-change signals (cheap, proactive) plus test-result signals (expensive, reactive). Reuses existing interwatch infrastructure.

6. **`docs/cujs/` directory** -- dedicated location, not embedded in PRDs. CUJs are standalone artifacts with their own lifecycle.

## CUJ Template

```markdown
---
artifact_type: cuj
journey: <journey-slug>
actor: <who>
criticality: <p0-p4>
bead: <bead-id or none>
---

# <Journey Name>

## Why This Journey Matters
[1-2 paragraphs: why this journey is critical, what breaks if it's bad]

## The Journey
[Prose describing the expected experience. For linear flows, this reads
as a narrative. For exploratory/game flows, this describes the intended
discovery path, emotional beats, and key moments. Authors may optionally
add step tables, mermaid diagrams, or other structured elements inline.]

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| ... | measurable/observable/qualitative | ... |

## Known Friction Points
- [Current pain points, gaps, or risks in this journey]
```

## Open Questions

- **Generation strategy**: Should `interpath:cuj` auto-generate CUJs from existing PRDs and brainstorms, or are CUJs always manually authored? Auto-generation could bootstrap initial CUJs but risks producing generic journeys.
- **Cross-CUJ relationships**: Beyond sub-journey linking, should there be explicit "prerequisite journey" or "alternative journey" relationships? Or is prose cross-referencing sufficient?
- **Agent validation protocol**: When an agent checks a CUJ's success signals, what's the actual mechanism? Does it run smoke tests, check code assertions, or just flag "this CUJ may be affected by your change"?
- **Monorepo CUJs**: Should there be project-level CUJs (per plugin) and ecosystem-level CUJs (cross-plugin journeys)? The monorepo roadmap pattern suggests yes.
- **Versioning**: Should CUJs track which version of the product they describe? A CUJ written for v0.5 may not apply to v0.8.
