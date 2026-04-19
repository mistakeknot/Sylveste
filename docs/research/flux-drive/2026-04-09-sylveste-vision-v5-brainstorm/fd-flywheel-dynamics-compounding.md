### Findings Index

- P0 | FDC-1 | "Flywheel" | Autonomy-to-evidence feedback link has no defined mechanism — the flywheel is open at the critical closing joint
- P1 | FDC-2 | "Flywheel" | Weakest-link constraint contradicts compounding thesis — a single lagging subsystem blocks flywheel acceleration
- P1 | FDC-3 | "Flywheel" | No minimum operating configuration defined — unclear which upstream sources must be producing evidence before the flywheel turns meaningfully
- P2 | FDC-4 | "Pitch" | Flywheel revolution time never estimated — a slow flywheel undermines the "ships most sprints learns fastest" claim
- P2 | FDC-5 | "Flywheel" | Contradictory signal handling undefined — what happens when upstream sources disagree

Verdict: risky

---

## Detailed Findings

### FDC-1: The flywheel is open at the autonomy→evidence joint [P0]

**Section:** The Pitch + The Flywheel (Retained, Expanded)

The flywheel diagram traces:
```
Interweave/Ockham/Interop/FluxBench → Interspect → routing → cost → autonomy → evidence → (back to upstream)
```

The path from upstream sources through routing, cost reduction, and autonomy is mechanistically described (in v4.0 and carried forward). But the critical closing link — from "more autonomy" back to "more/better evidence" — has no defined mechanism in the brainstorm.

How does increased autonomy produce more evidence? Possible mechanisms:
- More sprints run → more sprint evidence produced (volume)
- Higher-autonomy sprints touch more subsystems → more diverse evidence (breadth)
- Less human intervention → agent decisions become the primary evidence source (composition shift)

None of these are stated. The brainstorm says "every sprint produces evidence" and "evidence compounds" but does not explain why more autonomy causes more/better sprint execution. This is the flywheel's load-bearing joint, and it is undefined.

In systems dynamics terms: this is a reinforcing loop (R) with one causal link left as "obvious." In Forrester/Meadows analysis, the undefined link is where flywheels actually stall — not because the mechanism doesn't exist, but because the delay or friction at that link is underestimated.

**Recommendation:** Explicitly define the autonomy→evidence mechanism. Likely: "increased autonomy means more sprints complete without human intervention, each sprint produces evidence artifacts, so autonomy literally increases the evidence production rate." State this directly.

### FDC-2: Weakest-link constraint works against compounding [P1]

**Section:** Key Decisions, Decision 2

The brainstorm introduces a critical balancing constraint: "the system's overall autonomy is the minimum of its subsystem maturities — the weakest link constrains the whole."

This directly conflicts with the compounding thesis. Compounding implies exponential or super-linear growth from accumulated evidence. But the weakest-link rule means that even if 9 of 10 subsystems compound evidence rapidly, the system's effective autonomy is anchored to the slowest-maturing subsystem. This is a balancing loop (B) acting on the reinforcing loop (R) of the flywheel.

The brainstorm acknowledges this partially: "This naturally explains why 'autonomy stalled' (one subsystem isn't there yet) without claiming regression." But it doesn't address the deeper tension: if the weakest link can halt the flywheel, then evidence in other subsystems accumulates without producing system-level autonomy gains. Evidence compounds, but the system doesn't improve — creating the exact "infrastructure that doesn't learn" that the brainstorm rejects in Approach A.

**Recommendation:** Address the tension explicitly. Options: (1) the weakest-link rule is aspirational guidance, not a literal constraint — subsystems can advance the flywheel independently within their scope; (2) the weakest link receives disproportionate evidence investment (triage toward the bottleneck); (3) the compounding thesis applies per-subsystem, not system-wide, with system-level trust being a different (non-compounding) aggregation.

### FDC-3: No minimum viable flywheel configuration [P1]

**Section:** The Flywheel (Retained, Expanded)

The v4.0 flywheel was single-source (Interspect only). The v5.0 flywheel has 4 upstream sources. But the brainstorm does not specify whether the flywheel requires all 4 sources to be producing meaningful evidence, or whether it can operate on a subset.

Current state: Interweave is F1-F3, Ockham is F1-F7, Interop is Phase 1. If the flywheel requires all 4, it cannot begin producing meaningful system-level evidence until all 4 are operational. If it can operate on a subset (as v4.0 demonstrated with Interspect alone), then the expanded flywheel is additive improvement to an already-turning cycle.

This distinction matters for the "What's Next" section: if the flywheel has a minimum operating configuration, the items that bring upstream sources to that minimum are genuinely P0-blocking. If the flywheel turns at any configuration, the upstream work is P1 improvement.

**Recommendation:** State the minimum operating configuration explicitly. Likely: "the flywheel can turn with Interspect alone (as v4.0 demonstrated), but produces higher-quality evidence when upstream sources contribute. Each upstream source enriches the evidence, but none is individually blocking."

### FDC-4: Flywheel revolution time unstated [P2]

**Section:** The Pitch

The pitch claims "the system that ships the most sprints learns the fastest." This implies the flywheel revolution time is short enough that more sprints = meaningfully faster learning. But the brainstorm never estimates how long a single flywheel revolution takes.

If a sprint produces evidence, but that evidence takes 50 sprints of accumulation before it changes routing behavior (because Interspect needs statistical significance), then the flywheel's effective revolution time is 50 sprints, not 1. The "ships most sprints learns fastest" claim requires the evidence-to-learning delay to be short relative to sprint frequency.

### FDC-5: Contradictory upstream signals unaddressed [P2]

**Section:** The Flywheel (Retained, Expanded)

With 4 upstream sources, the flywheel can receive contradictory signals: FluxBench qualifies a model as high-performing, but Interspect's routing evidence shows poor outcomes with that model. The brainstorm does not address signal contradiction resolution. This is a standard multi-source integration problem, but it's unacknowledged in a document whose central mechanism depends on multi-source evidence.
