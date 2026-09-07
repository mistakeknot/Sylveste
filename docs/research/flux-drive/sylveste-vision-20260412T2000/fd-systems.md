### Findings Index
- P1 | SY-1 | "The Flywheel" | Balancing loop B1 (weakest-link) creates a "limits to growth" archetype but the document does not specify the leverage point for breaking through the constraint
- P2 | SY-2 | "The Flywheel" | Evidence saturation (B2) is acknowledged but no mechanism detects when saturation has been reached for a specific subsystem
- P2 | SY-3 | "The Capability Mesh" | Dependency DAG creates a "success to the successful" archetype — subsystems that mature first attract more evidence investment, starving later subsystems
- P2 | SY-4 | "Trust Architecture" | Trust lifecycle operates as a stock-and-flow model but the "stock" (accumulated evidence) has no explicit decay function
- P3 | SY-5 | "Cross-Document" | PHILOSOPHY.md and vision doc both describe the flywheel but at different abstraction levels — no explicit mapping between the two
Verdict: needs-changes

### Summary

The v5.0 document demonstrates strong systems thinking. The flywheel diagram (lines 94-118), balancing loops B1-B2 (line 124), and upstream dependency ordering (lines 127-133) are all causal-loop-aware. The document correctly identifies the reinforcing loop (more sprints -> more evidence -> better decisions -> more autonomy -> more sprints) and two balancing loops (weakest-link constraint, evidence saturation).

From a systems dynamics perspective (Meadows/Forrester), the document's primary structural gap is in specifying the leverage points within its own causal architecture. The balancing loops constrain the reinforcing loop, which is correct — but the document does not specify how to escape the limits-to-growth archetype when the weakest-link constraint becomes binding.

### Issues Found

SY-1. P1: No leverage point specified for the limits-to-growth archetype (The Flywheel, lines 123-124)
B1 (weakest-link constraint) creates a classic "limits to growth" archetype (Senge): the reinforcing flywheel drives growth until the balancing loop becomes dominant. The document correctly identifies B1 as a feature ("prevents runaway advancement"). But it does not specify the leverage point — the intervention that lifts the constraint when it becomes the binding limit.
In systems dynamics, the leverage point for limits-to-growth is always investment in the constraining factor BEFORE it becomes binding. The capability mesh tells you which subsystem is weakest, but the document does not specify how resource allocation shifts to address it. "What's Next" (lines 377-384) lists priorities, but these are not dynamically linked to the mesh state.
Failure scenario: The system reaches M2 everywhere except Execution (M0) and Measurement (M1). Resources continue flowing to the already-strong subsystems because "What's Next" priorities were set at document-write time, not dynamically computed from the mesh.
Fix: Add an explicit rule: "Investment priority follows the weakest-link — the subsystem(s) at the lowest maturity level receive disproportionate attention until they catch up." Or reference a specific mechanism (Interspect? Ockham?) that performs this dynamic reallocation.

SY-2. P2: Evidence saturation has no detection mechanism (The Flywheel, line 124)
B2 (evidence saturation) is correctly described: "once a model or agent is well-characterized, additional evidence produces diminishing returns." But how does the system KNOW when saturation has been reached? What triggers the shift from "collect more evidence" to "evidence is sufficient, move to the next subsystem"?
In systems dynamics, stock saturation requires a sensor — a measurement that detects the inflection point. Without it, the system over-invests in evidence collection for already-well-characterized domains.
Fix: Define a saturation indicator per evidence signal — e.g., "when the confidence interval for a metric narrows below X% of the mean, further observations produce diminishing returns." This is the statistical equivalent of sample size adequacy.

SY-3. P2: "Success to the successful" archetype in dependency DAG (Capability Mesh, lines 174-180)
The dependency DAG creates an implicit resource allocation dynamic: independent root cells (Persistence, Coordination, Discovery, Review, Execution) can mature immediately, while dependent cells (Ontology, Measurement, Governance, Routing) must wait. This creates a "success to the successful" archetype — early-maturing cells accumulate evidence, attract attention, and reach M3-M4, while late-maturing cells remain at M0-M1 because their prerequisites are not met.
The document is aware of this ("upstream dependency ordering" section) but does not address the second-order effect: when late-maturing cells finally become investable, the team's attention and tooling are optimized for the early cells.
Fix: Acknowledge the archetype and specify a countermeasure — e.g., "investment in dependent cells' DESIGN and PLANNING (M0 activities) begins in Phase 1, even though their OPERATIONAL maturity (M2+) depends on upstream cells reaching M1+."

SY-4. P2: Evidence stock has no explicit decay function (Trust Architecture, lines 199-225)
The trust lifecycle describes four phases: earn, compound, epoch, demote. Evidence accumulates (earn), persists (compound), gets partially reset (epoch), or triggers demotion. But between epoch triggers, there is no continuous decay function. Evidence from 6 months ago is weighted the same as evidence from yesterday, unless an epoch event occurs.
In systems dynamics, stocks without outflows grow without bound. The epoch mechanism provides discrete resets, but continuous decay would provide more responsive trust adjustment. PHILOSOPHY.md mentions "Intermem's decay model is the standard: grace period + linear decay + hysteresis" (line 181) — but this is for memory, not for trust evidence. The trust evidence stock should either adopt the same decay model or explicitly justify why it does not decay continuously.
Fix: Either (a) adopt a continuous decay function (exponential or linear with grace period) for evidence freshness within the trust lifecycle, or (b) explicitly state that evidence does not decay between epochs and justify why (e.g., "evidence about subsystem capability is structural, not temporal").

SY-5. P3: Cross-document flywheel mapping (Cross-Document Consistency)
PHILOSOPHY.md states the flywheel at the philosophical level: "authority enables actions -> actions produce evidence -> evidence earns authority" (line 11). The vision doc expands this into a 5-input flywheel with balancing loops. But there is no explicit mapping between the two — which part of the philosophical cycle corresponds to which stage of the v5.0 flywheel? This makes it harder for readers to verify consistency.
Fix: Add a one-sentence bridge in the vision doc's flywheel section: "This is the operational implementation of the philosophical cycle in PHILOSOPHY.md: evidence-earns-authority."

### Improvements

IMP-SY-1. The document would benefit from a stock-and-flow diagram in addition to the causal loop diagram. The current flywheel ASCII diagram shows causal relationships but not accumulation/depletion dynamics. A stock-and-flow would make evidence accumulation, decay, and epoch resets visually explicit.

IMP-SY-2. Consider adding delay analysis to the flywheel. What is the latency from "sprint produces evidence" to "routing decision changes"? If the delay is 50+ sprints, the reinforcing loop is effectively open-loop for the first year of operation, and the document should acknowledge this.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 1, P2: 3, P3: 1)
SUMMARY: Causal architecture is well-identified but leverage points, saturation detection, and evidence decay functions are unspecified — the feedback loops are drawn but the control parameters are missing.
---
<!-- flux-drive:complete -->
