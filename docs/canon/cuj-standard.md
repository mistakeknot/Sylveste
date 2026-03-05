# CUJ (Critical User Journey) Standard

The format and lifecycle for CUJ documents across the Demarch ecosystem. CUJs describe end-to-end user experiences that the product must support well.

## What a CUJ Is

A CUJ is a prose-first artifact with typed success signals. It serves three roles:

| Role | Consumer | What they need |
|------|----------|---------------|
| **Planning artifact** | Humans | Journey narrative, motivation, friction points |
| **Agent guardrail** | Agents | Success signals to check before/after changes |
| **Acceptance criteria** | Tests/smoke tests | Measurable assertions to validate |

## Location

```
docs/cujs/<journey-slug>.md
```

One file per journey. Sub-journeys are separate files linked from the parent.

## Template

```yaml
---
artifact_type: cuj
journey: <journey-slug>
actor: <who>
criticality: <p0-p4>
bead: <bead-id or none>
---
```

Four required sections:

| Section | Purpose | Length |
|---------|---------|-------|
| **Why This Journey Matters** | Stakes — what breaks if this journey is poor | 1-2 paragraphs |
| **The Journey** | Prose narrative of the expected experience | As needed |
| **Success Signals** | Typed assertion table (see below) | 3-15 rows |
| **Known Friction Points** | Current pain points and risks | Bulleted list |

Target: under 150 lines per CUJ.

## Success Signal Types

| Type | Meaning | Example | Who validates |
|------|---------|---------|--------------|
| `measurable` | Quantitative, automatable | HTTP 200 at /health | Agents, CI |
| `observable` | Detectable with instrumentation | Player inventory changes | Agents with hooks |
| `qualitative` | Requires human judgment | Feels intuitive, low friction | Humans |

## Generation

- **Manual authoring** — preferred; CUJs are user-specific and hard to auto-generate well
- **`/interpath:cuj`** — bootstraps a CUJ from PRD, brainstorms, and beads state
- **Hierarchy** — top-level CUJs link to sub-journey files; no inline nesting

## Drift Detection

CUJs are registered in interwatch with two-tier signals:

| Tier | Cost | Signals | When |
|------|------|---------|------|
| **Feature-change** | Cheap | bead_closed, brainstorm_created, file_created, file_deleted, commits_since_update | Every scan |
| **Test-result** | Expensive | Success signal assertions fail in smoke tests | On test runs |

Staleness threshold: 14 days. Discovery pattern: `docs/cujs/*.md` → one watchable per file.

## Relationship to Other Artifacts

- **PRDs** define mechanics; CUJs exemplify the user experience of those mechanics
- **Roadmaps** track what ships; CUJs track whether what shipped works end-to-end
- **Vision docs** articulate outcomes; CUJs describe the concrete paths to those outcomes

CUJs should reference PRD capabilities. PRDs should link to key CUJs.
