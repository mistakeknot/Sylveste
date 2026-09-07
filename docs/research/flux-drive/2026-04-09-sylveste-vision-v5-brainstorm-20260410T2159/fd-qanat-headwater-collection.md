### Findings Index
- P0 | QH-1 | "The Flywheel (Retained, Expanded)" | Flywheel diagram represents aspirational state as operational — untested upstream sources shown as active inputs
- P1 | QH-2 | "The Flywheel" | Source independence unverified — Interweave and Interspect may tap the same underlying event stream, making them correlated rather than independent inputs
- P1 | QH-3 | "What's Next" | Priority sequencing mixes upstream-critical and infrastructure-modernization work at P0 — obscures which work unblocks the flywheel
- P2 | QH-4 | "The Flywheel" | No headwater degradation detection — the vision does not specify how upstream source quality degradation propagates to downstream consumers
- P2 | QH-5 | "The Flywheel" | Combined yield assumption — four upstream sources may not linearly increase evidence quality if some tap correlated data
Verdict: risky

### Summary

The muqanni's central discipline is upstream yield confirmation before downstream commitment. The brainstorm's expanded flywheel moves from a single upstream source (Interspect in v4.0) to four sources (Interweave, Ockham, Interop, FluxBench in v5.0), claiming this expansion explains why "the flywheel didn't stall — its upstream precondition stack expanded" (line 71). This is a strong architectural claim, but the muqanni would ask: have these upstream sources been yield-tested? The brainstorm itself provides evidence that they have not (Interweave: F1-F3 shipped, Ockham: newly created, Interop: Phase 1 only). The qanat plan is drawn based on untested springs. Additionally, the independence of these sources is unverified — if Interweave derives its entity tracking from the same event stream that Interspect already observes, adding Interweave as an "upstream source" does not add independent information to the flywheel.

### Issues Found

QH-1. P0: Flywheel diagram represents aspirational state as operational. The v5.0 flywheel (lines 64-69) shows four upstream sources feeding Interspect as if they are all currently productive:

```
Interweave (what's known) --+
Ockham (what's allowed) ----+
Interop (what's verified) --+--> Interspect --> routing --> cost --> autonomy --> evidence
FluxBench (model quality) --+
```

But the brainstorm's own capability mesh reveals that none of these upstream sources have demonstrated evidence yield at the level the diagram implies:
- Interweave: "F1-F3 shipped, F5 in progress" — a system in early construction
- Ockham: "F1-F7 shipped" — newly created subsystem with no operational track record
- Interop: "Phase 1 shipped" — first phase of a multi-phase system
- FluxBench: represented via "~80% implemented (3,515 LOC Go)" under Factory Substrate

The downstream flywheel cycle (routing, cost, autonomy, evidence) is architecturally dependent on upstream sources that have not been yield-tested. The muqanni has drawn the full qanat schematic — headwaters, main tunnel, distribution channels, agricultural terraces — based on springs that have been located but not tested. A community that builds terraces based on promised water that never materializes faces catastrophe.

**Recommended fix**: The flywheel diagram should visually distinguish operational upstream sources from planned ones. Use a notation like solid lines for yield-tested sources and dashed lines for planned sources. Add text: "v5.0 identifies the full upstream stack. Currently, only Interspect contributes operational evidence. Each additional source comes online as it demonstrates yield."

QH-2. P1: Source independence unverified. The flywheel presents four upstream sources as if they provide genuinely independent evidence streams. But source independence is not guaranteed:

- **Interweave and Interspect**: Interweave tracks entities across systems (ontology). Interspect observes system behavior (measurement). If Interweave's entity resolution depends on events that Interspect already captures, they share an aquifer. Adding Interweave as a "separate upstream source" would count the same underlying data twice.
- **Ockham and Interspect**: Ockham gates on evidence, but its authority ratchet events may feed back into Interspect's evidence pipeline. If Ockham's evidence signals are derived from Interspect's measurements, they are correlated, not independent.
- **FluxBench and Interspect**: FluxBench qualifies models with evidence, but model qualification scores likely feed into Interspect's routing evidence. If both are measuring model quality through overlapping instrumentation, they share a data source.

The muqanni knows that four headwater tunnels tapping the same aquifer yield less than the sum of their individual test yields. The brainstorm should verify that its four upstream sources provide genuinely independent information.

**Recommended fix**: Add a note in the flywheel description acknowledging that source independence is an assumption that must be validated. State which data streams each source produces independently vs. which share underlying observations. Even a brief sentence: "These sources must tap independent evidence streams; correlated inputs do not compound."

QH-3. P1: Priority sequencing mixes upstream and non-upstream work at P0. The "What's Next" section (lines 106-113) assigns P0 to:
1. Integration fabric (Interop) — upstream prerequisite for the flywheel
2. Factory governance (Ockham) — upstream prerequisite for the flywheel
4. Intelligence replatforming (Auraken to Skaffen + Hassease) — infrastructure modernization, NOT an upstream flywheel prerequisite

Replatforming from Python to Go improves execution quality but does not unblock the evidence flywheel. Mixing upstream-critical and infrastructure-modernization work at the same priority level obscures which work unblocks the flywheel and which improves the platform's internal quality. The muqanni schedules headwater tunnel digging and terrace building in the same work phase — but they are fundamentally different kinds of work with different dependencies.

**Recommended fix**: In the vision's "What's Next" section, add a brief rationale for each P0 item explaining its position in the upstream-downstream dependency chain. For flywheel prerequisites, the rationale is "unblocks upstream evidence." For infrastructure work, the rationale is "execution quality" or "platform health." This lets the reader distinguish which P0s are flywheel-critical.

QH-4. P2: No headwater degradation detection mechanism specified. The flywheel assumes upstream sources will maintain their yield over time. But what happens if Interweave's query hit rate drops (its ontology becomes stale), or Ockham's authority ratchet stalls (governance policies aren't updated), or Interop's conflict resolution rate degrades (integration sync breaks)? The brainstorm does not specify how upstream degradation is detected before downstream consumers — routing, cost reduction, autonomy — are affected by poor-quality upstream evidence.

PHILOSOPHY.md's "Closed-loop by default" principle (starting at line 56 of PHILOSOPHY.md) specifies a 4-stage calibration pattern, but the brainstorm does not apply this to upstream source monitoring.

**Recommended fix**: Add language stating that each upstream source has a health signal that Interspect monitors, with degradation triggering either flywheel slowdown or fallback to the previous upstream configuration.

QH-5. P2: Combined yield may not equal sum of individual yields. The brainstorm's expanded flywheel implies that four upstream sources produce more evidence than one (Interspect alone in v4.0). This is true only if the sources are independent and their evidence combines additively. If two sources share underlying data (see QH-2), the combined yield is less than the sum. The brainstorm should not assume linear scaling of evidence quality with number of upstream sources.

### Improvements

IMP-1. The brainstorm's key insight — "the flywheel didn't stall — its upstream precondition stack expanded" (line 71) — is strong but would be stronger with explicit yield criteria. What minimum evidence yield from each upstream source justifies the v4.0-to-v5.0 expansion? This turns an architectural claim into a testable hypothesis.

IMP-2. Consider a "minimum viable flywheel" specification: which upstream sources must be operational for the flywheel to produce trustworthy evidence at each autonomy level? This is the muqanni's "minimum reliable combined yield" assessment before committing to downstream infrastructure.

<!-- flux-drive:complete -->
