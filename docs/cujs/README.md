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

## Journeys

### Platform (P0-P1)

| Journey | Actor | Criticality | Covers |
|---------|-------|-------------|--------|
| [First Install](first-install.md) | New user | P1 | Install → first sprint |
| [Running a Sprint](running-a-sprint.md) | Regular user | P0 | Core Clavain `/route` → ship loop |
| [Reviewing with Flux-Drive](reviewing-with-flux-drive.md) | Regular user | P1 | Multi-agent code review |
| [Multi-Agent Coordination](multi-agent-coordination.md) | Regular user | P1 | Interlock + Intermux + Beads |
| [Skaffen Sovereign Session](skaffen-sovereign-session.md) | Regular user | P1 | OODARC agent runtime |

### Apps (P1-P2)

| Journey | Actor | Criticality | Covers |
|---------|-------|-------------|--------|
| [Mycroft Fleet Dispatch](mycroft-fleet-dispatch.md) | Regular user | P1 | T0→T3 autonomy, patrol loop |
| [Mycroft Failure Recovery](mycroft-failure-recovery.md) | Regular user | P2 | Demotion, intervention, override |
| [Bigend Mission Control](bigend-mission-control.md) | Regular user | P2 | Multi-project dashboard |
| [Gurgeh PRD Generation](gurgeh-prd-generation.md) | Regular user | P2 | Spec creation and validation |
| [Coldwine Sprint Execution](coldwine-sprint-execution.md) | Regular user | P2 | Task orchestration TUI |
| [Pollard Research Scan](pollard-research-scan.md) | Regular user | P3 | Intelligence hunting |
| [Intercom Telegram Assistant](intercom-telegram-assistant.md) | Regular user | P2 | Multi-runtime Telegram bot |

### Ecosystem (P2-P3)

| Journey | Actor | Criticality | Covers |
|---------|-------|-------------|--------|
| [Plugin Discovery & Install](plugin-discovery-install.md) | New user | P2 | Marketplace → install → use |
| [Knowledge Compounding](knowledge-compound.md) | Regular user | P2 | Compound + recall + CASS |

## Drift Detection

CUJs are monitored by interwatch for staleness via:
- Feature-change signals (bead closures, new brainstorms, file changes)
- Test-result signals (success signal failures in smoke tests)
