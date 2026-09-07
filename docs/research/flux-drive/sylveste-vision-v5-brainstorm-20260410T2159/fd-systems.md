### Findings Index
- P1 | SY-1 | "The Flywheel" | Reinforcing loop R1 contains at least two hidden balancing loops (B1: weakest-link, B2: evidence saturation) that could flip the system into oscillation under stress
- P1 | SY-2 | "Key Decisions §2" | The capability mesh introduces 10 stocks with no identified flow rates — the vision describes stocks (maturity levels) but not the rates at which they fill
- P2 | SY-3 | "Why This Approach" | The flywheel expansion from 1 upstream to 4 creates emergent behavior risk — the document treats it as additive when systems dynamics predicts non-linear interactions
- P2 | SY-4 | "Key Decisions §5" | Sparse topology proposal (Zollman effect) and the evidence compounding thesis may conflict — sparse networks converge more accurately but more slowly
Verdict: needs-changes

### Summary

Applying systems dynamics analysis (Forrester/Meadows stock-and-flow modeling), the brainstorm's flywheel and capability mesh contain structural issues that are not visible from a document consistency perspective but become apparent when modeled as a dynamic system. The flywheel contains hidden balancing loops. The capability mesh describes stocks without flow rates. The expansion from single-source to multi-source flywheel creates emergent interaction risks.

### Issues Found

SY-1. P1: Systems dynamics analysis of the v5.0 flywheel reveals hidden balancing loops that oppose the claimed reinforcing dynamics. The brainstorm presents the flywheel as a reinforcing loop (R1): more evidence → more trust → more autonomy → more evidence. However, two balancing loops are embedded:

**B1 (Weakest-link constraint):** System autonomy = min(subsystem maturities). As the fastest-advancing subsystems accumulate evidence, the slowest subsystem constrains overall autonomy. This creates a "success to the successful" inversion: subsystems that are already mature generate more evidence (because they're active), while the weakest subsystem generates less evidence (because it constrains what the system can do). The rich get richer, the poor stay poor. In Meadows' archetype taxonomy, this is "Limits to Growth" — the reinforcing loop R1 accelerates until B1 activates, then the system stalls until the weakest link is manually addressed.

**B2 (Evidence saturation):** As evidence accumulates for well-characterized scenarios, the marginal value of additional evidence decreases. This creates a balancing loop: more evidence → diminishing marginal trust gain → slower autonomy advancement → stable evidence production rate. The reinforcing loop R1 expects superlinear evidence accumulation; B2 ensures it's sublinear past a threshold.

Neither B1 nor B2 is acknowledged in the brainstorm. A flywheel narrative that omits its own balancing loops will eventually be contradicted by observed system behavior.

SY-2. P1: The capability mesh describes 10 "cells" with current states and evidence signals, but in stock-and-flow terms, it describes stocks (maturity levels) without flow rates (how fast each cell fills). A capability maturity model needs both: the stock tells you where you are, the flow rate tells you how fast you're moving. Without flow rates, the mesh cannot answer three critical questions: (a) Which cell will reach maturity first? (b) How long until the weakest link advances? (c) Where should investment be directed to maximize system-level autonomy advancement? The evidence signals named for each cell (gate pass rate, query hit rate, etc.) could serve as flow rate proxies if they were instrumented. Currently, most are hypothetical (see fd-capability-mesh-maturity findings), so the mesh has neither stocks measured nor flows instrumented.

SY-3. P2: The flywheel expansion from 1 upstream source (Interspect in v4.0) to 4 upstream sources (Interweave, Ockham, Interop, FluxBench in v5.0) is presented as purely additive: "the upstream precondition stack expanded." Systems dynamics research on multi-input feedback systems shows this is not how multi-source reinforcing loops behave. Four upstream sources create 6 pairwise interactions (4 choose 2), and any contradictory pair can introduce oscillation. Example: Interweave (ontology) identifies an entity as "model X is suitable for task type Y." FluxBench (model qualification) measures model X and finds it unsuitable. Interspect now receives contradictory inputs. How it resolves the conflict determines whether the system oscillates (alternating between trusting and distrusting model X) or converges (establishing a reconciled assessment). Without a defined reconciliation mechanism, the four-source flywheel has emergent oscillation risk that the single-source flywheel did not.

SY-4. P2: The proposed PHILOSOPHY.md addition on "sparse topology by default" (referencing the Zollman effect) may conflict with the evidence compounding thesis. The Zollman effect (Zollman 2007, "The Epistemic Benefit of Transient Diversity") shows that fully-connected networks converge faster but are more likely to converge on the wrong answer, while sparse networks converge more slowly but more accurately. The brainstorm applies this to interflux agent review: sparse topologies for more independent findings. However, the compounding thesis claims "the system that ships the most sprints learns the fastest" — a speed argument. If sparse topologies slow convergence (more independent findings but slower synthesis), they may slow the flywheel. The tension is real and could be productive if acknowledged: sparse topology trades flywheel speed for evidence quality. Higher-quality evidence may compound more effectively despite slower production. But the brainstorm treats these as independent claims rather than a tradeoff.

### Improvements

IMP-1. Draw the complete causal loop diagram for the v5.0 flywheel, including both reinforcing (R1) and balancing (B1, B2) loops. Use Meadows notation: R for reinforcing, B for balancing, delay marks for time lags.

IMP-2. Add flow rate proxies to the capability mesh. For each cell, identify a measurable rate of maturity advancement (sprints per level, evidence events per week) alongside the stock-level evidence signal.

IMP-3. Acknowledge the sparse-topology/speed tradeoff explicitly and frame it as a design parameter rather than a universal principle.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 4 (P0: 0, P1: 2, P2: 2)
SUMMARY: Systems dynamics analysis reveals hidden balancing loops (limits to growth, evidence saturation) in the flywheel, missing flow rates in the capability mesh, and emergent oscillation risk from multi-source input expansion. The sparse topology proposal trades flywheel speed for evidence quality without acknowledging the tradeoff.
---
<!-- flux-drive:complete -->
