### Findings Index

- P0 | VCQ-1 | "Capability Mesh" | No interface evidence signals — 10 subsystem health signals but zero cross-subsystem interface health signals, creating 45 unmonitored pairwise interfaces
- P1 | VCQ-2 | "Capability Mesh" | No named structural substrate — the integration layer holding 10 subsystems together is implicit, not explicitly identified or monitored
- P1 | VCQ-3 | "Capability Mesh" | Differential maturity stress unaddressed — subsystems maturing at different rates create interface pressure
- P2 | VCQ-4 | "Flywheel" | No hot-swap protocol — replacing a subsystem (Auraken→Skaffen) cascades interface re-qualification to neighbors

Verdict: risky

---

## Detailed Findings

### VCQ-1: 45 unmonitored interfaces between 10 monitored components [P0]

**Section:** Key Decisions, Decision 2

The capability mesh defines 10 subsystems, each with its own evidence signal:
- Routing: gate pass rate, model cost ratio
- Governance: authority ratchet events, INFORM signals
- Ontology: query hit rate, confidence scores
- Integration: conflict resolution rate, sync latency
- Review: finding precision, false positive rate
- Measurement: attribution chain completeness
- Discovery: promotion rate, source trust scores
- Execution: task completion rate, model utilization
- Persistence: event integrity, query latency
- Coordination: conflict rate, reservation throughput

These are all **component** health signals. Not a single **interface** health signal is defined.

With 10 subsystems, there are C(10,2) = 45 potential pairwise interfaces. The critical ones include:

1. **Ontology → Governance:** Interweave resolves entities → Ockham uses entity identity in policy decisions. If their entity schemas diverge, governance decisions apply to wrong entities.
2. **Routing → Measurement:** Interspect selects models → Factory Substrate measures outcomes. If the attribution chain between routing decisions and measured outcomes breaks, the flywheel produces noise, not signal.
3. **Integration → Ontology:** Interop syncs external data → Interweave indexes it. If sync produces data that Interweave's schema cannot represent, entities are silently dropped.
4. **Review → Routing:** Interflux produces findings → Interspect uses finding quality to adjust agent trust. If finding format changes break Interspect's parsing, the feedback loop silently disconnects.

In the medieval vitrail tradition, this is the difference between testing glass panels (component) and testing lead came joints (interface). Cathedrals lost windows not because panels cracked but because lead came failed at joints — a failure mode invisible to panel-level testing.

**The insight from vitrail composite qualification:** The master verrier tested the assembled window as a whole, under thermal cycling conditions, because interface failures only manifest when components interact under stress. The mesh's component-only evidence signals are equivalent to testing each panel individually and declaring the window sound.

**Recommendation:** Define interface evidence signals for at least the critical pairwise interactions. Candidates:
- Entity identity agreement rate (Ontology ↔ Governance)
- Attribution chain integrity (Routing ↔ Measurement)
- Schema compatibility score (Integration ↔ Ontology)
- Finding parse success rate (Review ↔ Routing)

Even 4-5 interface signals would transform the mesh from a component health dashboard to a composite health dashboard.

### VCQ-2: The structural substrate holding the mesh together is unnamed [P1]

**Section:** Key Decisions, Decision 2 + Flywheel

In a cathedral window, the iron armature is the load-bearing framework that holds all glass panels and lead came in position. It is a distinct engineering element, separately designed and maintained.

The capability mesh has 10 subsystems but never names what holds them together. Candidates:
- **The evidence pipeline** (Interspect + Factory Substrate): the substrate that moves evidence between subsystems
- **The kernel** (Intercore): the durable system of record that all subsystems read from
- **The event bus** (if one exists): the communication layer between subsystems

The brainstorm implicitly assumes the flywheel provides structural coherence (evidence flows between subsystems through the cycle). But the flywheel is a process (how evidence moves), not an architecture (what prevents subsystems from drifting apart). A process can stall; an architecture persists.

Without naming the structural substrate, the mesh is a collection of independently-maturing subsystems with no explicit mechanism for maintaining coherence between them. This is the "invisible armature" problem: everyone assumes something holds it together, nobody specifies what.

**Recommendation:** Explicitly name the structural substrate — likely "the kernel event surface + evidence pipeline" — and add it as an 11th mesh cell (or a cross-cutting element like Interspect in the v4.0 stack diagram). Its evidence signal would be: event delivery integrity, cross-subsystem query latency, schema compatibility across subsystem boundaries.

### VCQ-3: Differential maturity creates interface stress [P1]

**Section:** Capability Mesh + What's Next

The mesh shows subsystems at radically different maturity levels:
- Persistence (Intercore): 8/10 epics shipped — mature
- Execution (Hassease): brainstorm/plan phase — embryonic
- Routing (Interspect): static + complexity-aware — intermediate

When two adjacent subsystems mature at different rates, the interface between them experiences stress. The mature subsystem produces output at a quality level the immature subsystem cannot consume, or the immature subsystem produces input the mature subsystem handles by falling back to degraded modes.

**Concrete example:** Governance (Ockham, F1-F7 shipped) produces sophisticated authority ratchet events. But if Routing (Interspect) is still at "static + complexity-aware" and cannot yet consume authority ratchet signals to adjust routing, the governance output goes nowhere. The interface exists architecturally but is functionally disconnected.

In the vitrail tradition, this is thermal differential stress: installing a fired panel next to a cold panel causes the lead came between them to crack. The solution is either to match maturity rates (fire panels together) or to design interfaces that tolerate maturity differentials (flexible lead came).

**Recommendation:** Acknowledge differential maturity as an interface design constraint. The vision should specify that subsystem interfaces must be designed to degrade gracefully when one side is immature — not just binary connected/disconnected.

### VCQ-4: No subsystem replacement protocol [P2]

**Section:** What's Next, item 4

The brainstorm references Auraken→Skaffen migration as a P0 item. But the capability mesh doesn't address what happens to interfaces when a subsystem is replaced. Does replacing one mesh cell require re-qualification of all interfaces to neighboring cells?

In vitrail restoration, replacing a single panel requires:
1. Removing the old panel without damaging adjacent lead came
2. Fitting the new panel to existing came geometry
3. Re-testing the interface between new panel and existing came
4. Thermal cycling the repaired section to verify composite integrity

The analogous question for Auraken→Skaffen: which interfaces need re-verification? What trust earned by Auraken (if any) transfers to Skaffen? The brainstorm is silent on this, though the Ottoman vakif agent's istibdal finding (trust transferability) addresses the same concern from a different lens.
