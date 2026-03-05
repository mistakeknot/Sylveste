# Critical User Journeys (CUJs)

CUJ documents describe end-to-end user experiences that the product must support well. Each CUJ is a prose-first markdown file with typed success signals.

## Template

See the [brainstorm](../brainstorms/2026-03-05-cujs-as-first-class-artifacts.md) for the full design rationale.

Generate a new CUJ: `/interpath:cuj`

## Format

Each CUJ file uses this structure:

- **Frontmatter:** `artifact_type: cuj`, journey slug, actor, criticality, bead
- **Why This Journey Matters:** 1-2 paragraphs on stakes
- **The Journey:** Prose narrative (linear or exploratory)
- **Success Signals:** Table with Signal | Type | Assertion columns
- **Known Friction Points:** Current pain points

Signal types: `measurable` (automatable), `observable` (instrumented), `qualitative` (human judgment).

## Drift Detection

CUJs are monitored by interwatch for staleness via:
- Feature-change signals (bead closures, new brainstorms, file changes)
- Test-result signals (success signal failures in smoke tests)
