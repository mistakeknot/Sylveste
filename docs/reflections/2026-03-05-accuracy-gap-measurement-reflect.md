# Reflection: Accuracy Gap Measurement (iv-u74sq)

**Date:** 2026-03-05
**Complexity:** 3/5 (moderate)

## What Happened

Measured the accuracy gap between tool selection with 49 plugins (with/without shallow composition layer) using a synthetic 15-task benchmark. Also discovered and fixed a deployment bug: interstat's PostToolUse hooks were written but never published.

## Key Learnings

1. **"Shipped" != "deployed."** The instrumentation bead (iv-rttr5) was closed with "Implemented" but the hooks never made it into the plugin cache. This is a verification gap — the bead close reason described writing code, not verifying it was live. Future beads involving hook deployment should include a verification step: "SELECT COUNT(*) FROM <table> after a test session."

2. **Sequencing hints dominate composition value.** The +70% delta was unexpected — we thought discovery metadata would be the primary value. Instead, the model is excellent at inferring plugin purposes from names but terrible at knowing which plugins form pipelines. This changes where we invest: more `first→then` hints, not more domain groups.

3. **The "18-point gap" was misattributed.** The original framing (74% vs 92%) implied scale degradation. The benchmark shows scale is a non-issue (0% delta). The gap was mostly sequencing failures masquerading as scale problems. This reframes iv-mtf12: there's no consolidation pressure from scale, only from sequencing complexity.

4. **Synthetic benchmarks with n=5 are directional, not definitive.** The discovery delta (+20%) could be noise from a single task (interwatch vs intercheck). Real instrumentation data is needed to confirm. The sequencing delta (+70%) is too large to be noise even at n=5.

## What Would I Do Differently

- Verify hook deployment as part of the instrumentation bead's acceptance criteria
- Include a "negative control" category in the benchmark: tasks where NO plugin is the right answer, to check for false-positive tool selection
- Run multiple trials (3x) to estimate variance, even for a directional benchmark

## Follow-Up Work

- Audit real sessions for unhinted sequencing pipelines (requires 2+ weeks of instrumentation data)
- Repeat benchmark with Sonnet/Haiku to test model-capability sensitivity
- Add more sequencing hints to tool-composition.yaml based on real failure data
