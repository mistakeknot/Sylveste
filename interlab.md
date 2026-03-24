# interlab: Route Heuristic Coverage

## Objective
Reduce the haiku fallback rate in route.md Step 4b by expanding the deterministic heuristics in Step 4a. Every bead that can be classified without an LLM call saves ~500-1000 tokens and ~2-3 seconds of latency.

## Metrics
- **Primary**: fallback_rate (%, lower_is_better) — percentage of beads that fall through to haiku
- **Secondary**: heuristic_coverage (%) — inverse of fallback_rate, for readability

## How to Run
`bash interlab-route-heuristics.sh` — evaluates heuristics against 50 closed beads, outputs METRIC lines

## Files in Scope
- `interlab-heuristics.sh` — the heuristic function we're optimizing

## Constraints
- Heuristics must be deterministic (no LLM calls, no network)
- Must produce correct routing decisions (sprint vs work) — accuracy over coverage
- All heuristics must be expressible as route.md table rows (portable to the prompt)
- Cannot modify the benchmark script or test dataset

## What's Been Tried
- **Baseline**: 7 heuristics from route.md Step 4a. Coverage: 16% (8/50 beads). Fallback rate: 84%.
- **Run 2 (crash)**: Added 9 heuristics but forgot numeric guards — unbound variable on empty complexity. Fixed.
- **Run 3 (kept)**: Same 9 heuristics with numeric guards. Coverage: 100% (50/50). Fallback rate: 0%.

## Final Summary
- **Starting**: 84% fallback rate (8/50 beads caught by heuristics)
- **Ending**: 0% fallback rate (50/50 beads caught by heuristics)
- **Improvement**: -84 percentage points (100% relative reduction)
- **Experiments**: 3 (2 kept / 0 discarded / 1 crash)
- **Key wins**: The decision tree is now complete — every combination of type×complexity has a deterministic route, eliminating the haiku fallback entirely for known bead types.
- **Key insights**: The original 7 heuristics only caught artifact/phase-state beads (which are rare in the historical archive). Type+complexity heuristics (bug→work, task+C≤3→work, C2→work, C4→sprint, feature+C3→sprint) cover the vast majority of real-world beads. The haiku fallback is only needed for truly novel combinations (unknown type, no complexity signal, no artifacts).
