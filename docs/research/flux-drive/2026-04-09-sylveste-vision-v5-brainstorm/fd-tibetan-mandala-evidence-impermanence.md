### Findings Index

- P0 | TME-1 | "Pitch" | No evidence staleness mechanism — accumulated evidence from past conditions permanently inflates trust even when the environment has shifted beneath it
- P1 | TME-2 | "Capability Mesh" | No temporal weighting in mesh minimum — stale evidence from 6 months ago receives equal weight to fresh evidence
- P1 | TME-3 | "PHILOSOPHY.md Additions" | Authority ratchet is strictly monotonic — no evidence epoch or controlled dissolution mechanism to prevent rigidity from accumulated form
- P2 | TME-4 | "Flywheel" | Compounding thesis assumes monotonic benefit — does not account for evidence compounding into constraint

Verdict: risky

---

## Detailed Findings

### TME-1: Evidence staleness is the hidden assumption that breaks the thesis [P0]

**Section:** The Pitch

The brainstorm's central thesis: "trust in autonomous systems is earned through observable evidence that compounds over time."

The sand mandala tradition reveals the hidden assumption: the thesis treats time as uniformly positive for evidence. More time = more evidence = more trust. But the mandala's deepest insight is that accumulated form eventually becomes an obstacle to seeing present reality.

Consider the concrete scenario: Interspect accumulates 6 months of positive gate pass rate evidence for the Routing subsystem. The authority ratchet promotes Routing to high autonomy. Then a major model API change occurs — the model that was being routed to changes its behavior profile. The accumulated evidence no longer reflects current reality.

The brainstorm specifies no mechanism for this scenario. The evidence continues to compound. The trust persists. The system routes based on a model of the world that no longer exists.

PHILOSOPHY.md already partially addresses this through "Anti-gaming by design... Rotate metrics" and the closed-loop calibration pattern (defaults → collect → calibrate → fallback). But the brainstorm's vision-level evidence thesis does not reference these safeguards. More critically, the calibration pattern addresses metric gaming, not environmental shift. When the environment changes, the old evidence isn't gamed — it's simply stale.

**The mandala's structural insight:** The tradition prescribes periodic destruction of the accumulated structure not because it was wrong when built, but because attachment to it prevents construction of a new structure that reflects current understanding. The analogous mechanism in the evidence thesis would be an **evidence epoch**: a periodic moment where accumulated trust is partially or fully reset and must be re-earned from current conditions.

**Recommendation:** The vision should acknowledge evidence temporality as a first-class concern. At minimum: (1) evidence has a temporal dimension (freshness matters), (2) the authority ratchet must support controlled regression when environmental conditions shift, (3) the concept of evidence epoch or temporal decay should be named even if the specific mechanism is deferred to Ockham's design docs.

### TME-2: Mesh minimum ignores evidence freshness [P1]

**Section:** Key Decisions, Decision 2

The capability mesh states: "the system's overall autonomy is the minimum of its subsystem maturities." But maturity is assessed via evidence signals (gate pass rate, query hit rate, conflict resolution rate), and the brainstorm does not specify whether these signals are point-in-time or trailing averages.

If Routing's gate pass rate is 95% from evidence collected 6 months ago, and Governance's authority ratchet events are from 3 days ago, the mesh treats both as equally valid inputs to the minimum calculation. But stale evidence may describe a system that no longer exists.

The mandala is rebuilt from center outward — inner rings must be stable before outer rings are built. The implicit assumption is that inner rings are inspected for degradation each time the mandala is rebuilt. The mesh has no such inspection cycle.

**Recommendation:** Evidence signals in the mesh should include a freshness dimension: when was this evidence last collected, and is there a maximum age beyond which it is considered stale? Even a simple flag — "evidence current" vs. "evidence stale (>N weeks)" — would prevent the mesh from presenting outdated assessments as current state.

### TME-3: Ratchet has no demotion granularity matching promotion [P1]

**Section:** Key Decisions, Decision 5

The authority ratchet is described as a mechanism for graduated promotion: evidence accumulates, trust increases, authority expands. But the mandala tradition is defined by its dissolution protocol: the entire structure is swept away at completion.

The analogue is not necessarily total dissolution (that would be counterproductive for an engineering system). But the ratchet needs demotion granularity that matches its promotion granularity:

- If promotion takes 50 sprints of positive evidence, does demotion take 50 sprints of negative evidence? (Too slow — a subsystem failing catastrophically should lose authority faster than it earned it)
- If promotion happens at defined thresholds, are there defined demotion thresholds? (The brainstorm doesn't name any)
- If promotion is subsystem-specific, does demotion cascade to dependent subsystems? (If Measurement loses trust, does Routing — which depends on it — also demote?)

The asymmetry between promotion (well-described) and demotion (mentioned once, never specified) is the structural weakness the mandala lens reveals.

### TME-4: Evidence can compound into constraint [P2]

**Section:** The Flywheel (Retained, Expanded)

The flywheel treats evidence accumulation as always beneficial: more sprints → more evidence → better routing → more autonomy. But evidence can compound into constraint:

- **Overconfidence from low-complexity evidence:** If the flywheel accumulates evidence primarily from simple sprints during a period of low environmental complexity, it develops high confidence in routing decisions that may fail under novel conditions. The mandala built in still air will not survive wind.
- **Path dependency from early evidence:** The first 50 sprints' evidence disproportionately shapes routing behavior. If those sprints had non-representative characteristics (a particular project, a particular model mix, a particular task type), the compounded evidence creates path-dependent routing that resists correction from later, more representative evidence.

The brainstorm acknowledges the flywheel's virtuous cycle but not its vicious counterpart: the overconfidence cycle where accumulated evidence from past success prevents adaptation to changed conditions.
