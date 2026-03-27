---
artifact_type: reflection
bead: Sylveste-enxv
stage: reflect
---

# Reflect: v1.0 Roadmap Definition

## What went well

- **Fresh brainstorm was the right call.** The existing synthesis (from child .1) was a research exercise that proposed sequential milestones. The brainstorm dialogue surfaced the user's actual priorities: broader v0.7 scope (operational maturity, not just wiring), continuous external validation from v0.7 (not gated to v0.9), and the parallel tracks model. These are significant departures from the synthesis that wouldn't have emerged from "adopt synthesis as brainstorm."

- **Ground truth research exposed the synthesis's optimism.** The synthesis said calibration loops need "mostly wiring, not new capability." The actual codebase analysis revealed: routing verdict recording is broken (quality-gates never calls it), gate thresholds have no calibration mechanism at all (not even a file schema), and only phase-cost calibration is close to working. The gap to v0.7 is larger than the synthesis suggested.

- **Parallel tracks model is more honest than sequential milestones.** Autonomy, safety, and adoption progress at different rates. The parallel model prevents declaring a milestone "done" when one dimension sprinted ahead while another stalled. Version gates enforce balanced progress.

## What could improve

- **Epic scope is very large.** Sylveste-enxv now tracks the full v0.7→v1.0 journey — potentially months of work across many sessions. The bead will stay open a long time. Consider: should milestone-level sub-epics be created (one per version gate) to provide intermediate closure signals?

- **The PRD only scoped v0.7 features.** Future milestones (v0.8, v0.9, v1.0) will need their own PRDs when we approach them. The roadmap artifact provides the guide but doesn't replace per-milestone planning.

- **Gate threshold calibration (F3/Sylveste-0rgc) needs its own brainstorm.** It's the largest gap — requires designing a calibration algorithm, not just wiring existing code. This bead should get its own sprint with a proper design phase.

## Lessons learned

1. **Research syntheses are not brainstorms.** Even thorough research can encode assumptions (sequential milestones, "just wiring") that only surface through dialogue. When the user says "fresh brainstorm," trust the instinct.

2. **The parallel tracks framing unlocks a key insight:** version gates are conjunctions (AND), not disjunctions (OR). This means the slowest track determines the version, which creates natural incentive to work on the hardest track first. Gate threshold calibration (the hardest gap) should be prioritized.

3. **External validation as a continuous thread** (starting at v0.7) is more realistic than a gated milestone. It also provides early signal about whether the infrastructure generalizes — signal that's useful during v0.8 development.
