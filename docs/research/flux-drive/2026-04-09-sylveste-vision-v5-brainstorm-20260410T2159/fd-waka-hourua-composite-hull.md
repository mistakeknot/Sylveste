### Findings Index
- P0 | WH-1 | "The Flywheel (Retained, Expanded)" | Flywheel operates before upstream subsystems reach minimum maturity — the canoe launches with unproven lashings
- P1 | WH-2 | "Capability Mesh" | Current State conflates feature completeness with operational maturity — "F1-F7 shipped" is not "tested under load"
- P1 | WH-3 | "Capability Mesh" | No cross-subsystem interaction testing — mature Routing with immature Governance produces emergent failures invisible to individual subsystem assessment
- P1 | WH-4 | "Capability Mesh / Key Decision 2" | Minimum-of-maturities claim is inconsistently applied — the flywheel diagram implies continuous operation regardless of subsystem state
- P2 | WH-5 | "What's Next" | No progressive deployment sequence — the jump from current state to "more autonomy" is undifferentiated
Verdict: risky

### Summary

The brainstorm correctly identifies that "the system's overall autonomy is the minimum of its subsystem maturities — the weakest link constrains the whole" (line 98). This is the tufunga's central discipline: a canoe with master-level hulls and apprentice-level lashings is an apprentice-level canoe. However, the brainstorm then contradicts this claim in its flywheel diagram (lines 64-69), which shows evidence flowing through a continuous cycle including all upstream sources — implying the flywheel operates even when some sources are immature. Additionally, the capability mesh's "Current State" column describes development status (features shipped) rather than operational maturity (tested under conditions), and the mesh treats subsystems as independent cells without addressing emergent failure modes from cross-subsystem interaction.

### Issues Found

WH-1. P0: Flywheel operates before upstream subsystems reach minimum maturity. The v5.0 flywheel diagram (lines 64-69) shows four upstream sources (Interweave, Ockham, Interop, FluxBench) feeding into Interspect, which drives routing, cost reduction, autonomy, and evidence production. The brainstorm itself notes that these upstream sources are at varying levels of maturity: Interweave is "F1-F3 shipped, F5 in progress" (newly created), Ockham is "F1-F7 shipped" (newly created), Interop is "Phase 1 shipped" (newly created). Yet the flywheel diagram presents all four as active inputs without distinguishing between operational and aspirational sources. 

The concrete failure scenario: the flywheel begins producing evidence and granting authority based on a partial upstream input set. If Interweave's ontology is immature, the evidence flowing through the flywheel is based on incomplete entity tracking. Routing decisions made on this evidence inherit the immaturity of the weakest upstream source. The system earns trust through evidence derived from an incomplete infrastructure — which is exactly the scenario the minimum-of-maturities principle is supposed to prevent.

**Recommended fix**: The flywheel diagram should clearly distinguish between currently yield-tested upstream sources (Interspect only, as v4.0 assumed) and planned upstream sources (Interweave, Ockham, Interop, FluxBench). Add a note specifying the minimum upstream configuration required for the flywheel to produce meaningful evidence: "The flywheel can operate with Interspect alone (v4.0 behavior). Each additional upstream source increases evidence quality but is not required for basic operation."

WH-2. P1: Current State conflates feature completeness with operational maturity. The capability mesh (lines 84-98) describes subsystem state in terms of development milestones: "F1-F7 shipped" for Governance, "F1-F3 shipped, F5 in progress" for Ontology, "Phase 1 shipped" for Integration. These describe code completeness, not operational readiness. A hull carved to specification has never been in water. "F1-F7 shipped" for Ockham does not indicate whether those governance features have been tested under real conditions — under actual dispatch loads, with real policy decisions, producing real evidence.

The tufunga distinguishes between a carved hull and a sea-tested hull. The vision should distinguish between "code shipped" and "evidence-producing under operational conditions." The current framing creates the impression that these subsystems are contributing to the evidence flywheel when they may only have passed unit tests.

**Recommended fix**: Split "Current State" into two columns: "Development State" (features shipped) and "Operational State" (evidence yield under real conditions). If operational state is unknown or untested, mark it explicitly as "untested" rather than leaving the reader to assume development completeness equals operational maturity.

WH-3. P1: Cross-subsystem interaction testing absent. The capability mesh treats subsystems as independent cells with independent maturity assessments. But subsystem interactions create emergent failure modes not visible when testing subsystems in isolation. For example: if Routing (mature, static + complexity-aware) selects a model based on Governance policy from Ockham (immature, F1-F7 shipped but untested), the combination produces model selections that neither subsystem would produce alone. Good hulls with bad lashings produce hull separation that neither the hull carver nor the lasher would predict from independent inspection.

The brainstorm does not address interaction testing. The minimum-of-maturities claim (line 98) implies that knowing each subsystem's individual maturity is sufficient to determine system-level readiness. It is not — you must also test subsystem pairs and combinations at each maturity level.

**Recommended fix**: Add a note in the capability mesh section acknowledging that subsystem interaction testing is a separate concern from individual subsystem maturity. The vision need not specify the full interaction matrix, but it should state the principle: "individual subsystem maturity is necessary but not sufficient; cross-subsystem interaction must be validated at each autonomy level."

WH-4. P1: Minimum-of-maturities applied inconsistently. Line 98 states "the system's overall autonomy is the minimum of its subsystem maturities." But the flywheel diagram (lines 64-69) and the pitch (lines 22-32) imply continuous operation: "Every sprint produces evidence. Evidence compounds. Trust ratchets." If autonomy is truly constrained by the weakest subsystem, then the flywheel should NOT compound trust when any upstream source is below minimum maturity — it should stall or operate in a degraded mode. The brainstorm needs to reconcile the minimum-of-maturities constraint with the flywheel's implied continuous operation.

**Recommended fix**: Add language specifying that the flywheel operates in degraded modes when upstream sources are below maturity thresholds. For example: "The flywheel turns at the speed of its weakest upstream source. With only Interspect operational, the flywheel produces evidence about routing alone. As Interweave, Ockham, and Interop reach operational maturity, the flywheel's evidence scope expands."

WH-5. P2: No progressive deployment sequence. The brainstorm describes current states and an implied future of "more autonomy" but does not define a progressive deployment strategy. The tufunga tests in the lagoon before the reef passage, in the reef before the coast. What is Sylveste's lagoon? What is its reef passage? Is there a defined sequence of autonomy scopes that expand incrementally as subsystem maturities are proven? The "What's Next" section (lines 105-113) lists 6 work items but does not sequence them in terms of progressive autonomy expansion.

**Recommended fix**: Add a brief note in "What's Next" or a new subsection mapping the progressive deployment sequence: "Once X and Y reach operational maturity, the system can expand autonomy scope to Z."

### Improvements

IMP-1. The capability mesh would benefit from a "minimum viable upstream" specification: which subsystems must reach what maturity level before the flywheel can begin producing evidence that the system is willing to act on. This makes the weakest-link constraint operational rather than abstract.

IMP-2. Consider adding a "sea trials" concept to the vision — defined environments of increasing complexity where subsystem maturity is validated before the system is given more authority.

<!-- flux-drive:complete -->
