---
bead: sylveste-rsj.3
date: 2026-03-30
type: plan
source: docs/prds/2026-03-30-roguelike-agent-architecture.md
---

# Plan: Roguelike-Inspired Agent Architecture

## Scope

Execute the three P2 features from the PRD. P3 items (F4-F6) are tracked as open beads for future sprints.

## Tasks

### Task 1: Update Vision Doc with Stigmergic Coordination Evidence (rsj.3.3)

**File:** `docs/sylveste-vision.md`

1. Add empirical citation for stigmergic coordination advantage (arxiv 2601.08129v2: 36-41% at 500+ agents)
2. Add citation for Arcgentica's 340x orchestration efficiency (validates infrastructure-over-intelligence thesis)
3. Add "Roguelike Isomorphisms" subsection under an appropriate heading — brief structural parallels that ground design choices in external research
4. Keep additions concise (~200 words total) — vision doc should point to evidence, not reproduce it

**Acceptance:** Vision doc references empirical research, cross-linked from relevant Interspect docs so developers doing routing work encounter it. No design changes to Garden Salon (that's F4).

### Task 2: Write Identification-as-Calibration Design Assessment (rsj.3.1)

**File:** `docs/research/assess-identification-as-calibration.md`

1. **Audit current schema:** Read Interspect's evidence tables and routing-overrides to identify which signal levels already have data collected vs. net-new collection required
2. Document the graduated identification model (4 signal levels)
3. Map current Interspect routing to this model — what levels does it already cover?
4. Identify gaps: which signal levels are missing or underused?
5. Propose concrete additions to Interspect's routing pipeline
6. Include cost/latency constraints (levels 1-2 < 10ms, levels 3-4 only when ambiguous)
7. **Define fallback path:** If signal queries fail or return null, degrade to current behavior — never escalate to expensive probe on timeout

**Acceptance:** Assessment doc with clear adopt/extend/defer verdicts per signal level. Each level mapped to existing Interspect tables or marked as net-new.

### Task 3: Write BALROG Evaluation Assessment (rsj.3.2)

**File:** `docs/research/assess-balrog-evaluation.md`

1. Document BALROG setup requirements (6 environments, dependencies, hardware)
2. Assess which environments are most relevant to Sylveste's claims (TextWorld, MiniHack, NetHack)
3. Design adapter sketch: BALROG observations → Skaffen OODARC loop
4. Define baseline protocol: raw model vs. Skaffen-orchestrated
5. Estimate effort and priority relative to other evaluation work

**Acceptance:** Assessment doc with effort estimate and recommended starting environment. Closing rsj.3.2 creates a follow-on bead for the actual BALROG baseline run with starting environment and effort estimate pre-attached.

## Sequence

Tasks 1-3 are independent. Execute in parallel if possible. Task 1 is smallest (vision doc edit). Tasks 2-3 are assessment docs of similar size.

## Post-Sprint: Elevated P3 Items

Per plan review feedback, rsj.3.5 (Agentica SDK evaluation) should be elevated to P2 and sequenced immediately after rsj.3.1 closes. Both address adjacent questions about Skaffen's agent runtime calibration. Elevation happens after this sprint ships.

## Definition of Done

- Vision doc updated with empirical citations and cross-linked from Interspect docs
- Two assessment docs created (identification-as-calibration, BALROG evaluation)
- All three beads (rsj.3.1, rsj.3.2, rsj.3.3) closeable after review
- rsj.3.2 close triggers follow-on bead for actual BALROG run
- Brainstorm, PRD, and plan committed to repo
