---
date: 2026-04-06
session: cd2fc786
topic: Auraken discrimination curriculum
beads: [sylveste-2l1.3, sylveste-uais, sylveste-9owj, sylveste-5ca9, sylveste-ddmg, sylveste-1zei, sylveste-csa7]
---

## Session Handoff — 2026-04-06 Auraken discrimination curriculum

### Directive
> Your job is to write the implementation plan for sylveste-uais (progressive discrimination curriculum). Start by `/route sylveste-uais` — sprint resumes at Step 3 (Write Plan). The PRD is at `docs/prds/2026-04-06-progressive-discrimination-curriculum.md` with 5 features (F1-F5). F1 (difficulty ladder) and F2 (judicial holdings) are mechanical transforms on existing data — start there. F3 (conversation integration spec) is the design bottleneck and P1.

- Beads: `sylveste-uais` — open (epic, sprint at Step 3)
- Children: `sylveste-9owj` (F1), `sylveste-5ca9` (F2), `sylveste-ddmg` (F3 P1), `sylveste-1zei` (F4), `sylveste-csa7` (F5)
- Closed this session: `sylveste-2l1.3` (near-miss density analysis)

### Dead Ends
- Beads Dolt server on port 40095 died mid-session (stash/pull/pop killed it). Had to restore from backup JSONL (`bd backup restore`) and fix port/pid files. Running Dolt is PID 1176082 on port 36047 but that's the one with only 60 issues (Auraken's DB). Sylveste beads required restore.
- flux-review track agents (A and B) couldn't write spec files due to Write permission denials. Tracks C and D succeeded. The agent designs from A and B were captured in conversation context and synthesized manually — the synthesis doc has all 16 agents' insights regardless.

### Context
- **Design thesis** (from 4-track flux-review, 16 agents): "Calibration data is a curriculum, not a routing table." 4/4 tracks converged. DQs should be presented TO users as Socratic dialogue, not used silently for routing.
- **Three-depth model** named "Wax-and-Gold" from Ethiopian Qene poetry: deep gold (embody lens without naming), shallow gold (name after user applies it), wax (teach vocabulary directly). This is the key design innovation for F3.
- **Lens stacks are reference-frame inversions** (from Polynesian Etak navigation): each lens redefines the problem, not adds analysis. The D3524 lens-stack archetype (Approach/Avoid → Microboundaries → SBI) was validated across 3 pair tests.
- **Forge stress test results**: 16 tests total (12 RESOLVED, 4 PARTIAL). One contraindication refined ("Trust Is a Long Game" contra changed from "broken down" to "irreversibly closed"). All data at `apps/Auraken/data/calibration/`.
- **Key files**:
  - `/home/mk/projects/Sylveste/apps/Auraken/data/calibration/near_miss_analysis.json` — 30 enriched pairs
  - `/home/mk/projects/Sylveste/apps/Auraken/data/calibration/near_miss_forge_ready.json` — DistinguishingFeature records
  - `/home/mk/projects/Sylveste/apps/Auraken/data/calibration/forge_stress_test_log.jsonl` — 16 stress tests
  - `/home/mk/projects/Sylveste/docs/research/flux-review/auraken-systems-consultant-approaches/2026-04-06-synthesis.md` — full 16-agent synthesis
  - `/home/mk/projects/Sylveste/docs/brainstorms/2026-04-06-progressive-discrimination-curriculum-brainstorm.md`
  - `/home/mk/projects/Sylveste/docs/prds/2026-04-06-progressive-discrimination-curriculum.md`
- **Discord summary** was shared with Flux Collective — describes the 12-model cookoff methodology and top contested pairs.
