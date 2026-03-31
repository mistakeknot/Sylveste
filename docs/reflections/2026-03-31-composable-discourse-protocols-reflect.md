---
artifact_type: reflection
bead: sylveste-rsj.7
date: 2026-03-31
---

# Reflect: Composable Discourse Protocols (rsj.7)

## What shipped

Phase 1 of composable discourse protocols: Sawyer Flow Envelope (health monitoring) and Lorenzen Dialogue Game (move validation) integrated into interflux's reaction round and intersynth's synthesis pipeline.

**New files (4):**
- `discourse-sawyer.yaml` — health thresholds (gini, novelty, relevance)
- `discourse-lorenzen.yaml` — move types and validation rules
- `discourse-health.sh` — standalone diagnostic script
- Plan, PRD, brainstorm documents

**Modified files (3):**
- `reaction-prompt.md` — Move Type field in output contract
- `synthesize-review.md` — Steps 3.7c (Lorenzen validation) + 6.6 (Sawyer health) + schema/report extensions
- `synthesize.md` — LORENZEN_CONFIG injection + diagnostic script wiring
- `reaction.yaml` — discourse config references

## Key design decisions

1. **Single-writer for findings.json.** The plan review (3 agents) unanimously identified a P0: the original plan split findings.json writes between the synthesis agent and the orchestrator. Fixed by moving ALL discourse metrics into the synthesis agent — consistent with how sycophancy, hearsay, stemma, and QDAIF are handled.

2. **Config passed as parameter, not file path.** The synthesis agent (intersynth) must not read interflux config files directly — this would create a cross-plugin filesystem dependency. LORENZEN_CONFIG is passed as a flattened JSON string, matching the FINDINGS_TIMELINE pattern.

3. **Nil-safe Move Type.** Pre-rsj.7 reaction outputs won't have Move Type. Rather than inferring (unreliable with haiku), null values skip validation entirely. This makes rollout safe.

4. **Convergence gate subsumption deferred.** Sawyer's `subsume_convergence_gate` is set to `false`. The existing overlap-based gate continues independently. Full subsumption requires multi-round reaction support (Phase 2/3).

5. **Diagnostic script is convenience, not canonical.** discourse-health.sh exists for CLI analysis. The authoritative health data lives in findings.json, written by the synthesis agent.

## What went well

- Plan review caught a real architectural bug (two-writer race) before any code was written. The 3-agent convergence on the same root cause gave high confidence.
- The integration review (fd-integration) caught a JSON shape mismatch that would have silently disabled evidence validation. Fixed in quality gates.
- The protocol stack model (5 layers, bottom-up) provides a clean mental model for future phases.

## What to improve

- The integration review's "P0" about Sawyer config hardcoding is valid as a future concern. When Phase 2 adds the `SAWYER_CONFIG` parameter, the synthesis agent must read thresholds from config rather than hardcoded defaults. Track this.
- `legality_scoring` in discourse-lorenzen.yaml is dead config — the synthesis agent hardcodes 1.0 for valid moves. Either remove it or wire it up in a future bead.
- The plan originally had 8 tasks; post-review consolidated to 6. Starting with fewer, more coherent tasks would have saved the review cycle.

## Lessons learned

1. **Cross-plugin data flow needs explicit contracts.** When module A produces config that module B consumes, the shape must be specified at the boundary (JSON param), not assumed from file structure.
2. **Single-writer principle applies to structured artifacts.** findings.json, discourse-health.json, verdicts — any structured artifact should have exactly one writer. Multiple writers require an explicit merge protocol.
3. **Hardcoded defaults are acceptable for Phase 1 if documented.** Step 6.6 explicitly names the values and notes the future config path. This is better than over-engineering config injection for a first pass.

## Follow-up beads

- Phase 2: Yes-And with Degeneration Guards (premise tracking, challenge rate, scope drift)
- Phase 3: Conduction Protocol + Pressing Cycle (multi-round orchestration, referent-drift)
- Wire `legality_scoring` weights from config into synthesis
- Add `SAWYER_CONFIG` parameter for configurable health thresholds
