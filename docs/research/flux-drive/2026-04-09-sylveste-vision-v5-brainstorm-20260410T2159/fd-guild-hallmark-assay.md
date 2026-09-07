### Findings Index
- P0 | GHA-1 | "The Pitch / Capability Mesh" | Evidence verification is architecturally unspecified — subsystems self-report quality metrics without independent assay
- P1 | GHA-2 | "Capability Mesh" | No maturity thresholds defined — evidence signals listed without the gating levels that would trigger authority escalation
- P1 | GHA-3 | "PHILOSOPHY.md Additions / Authority ratchet" | Ratchet mechanism is forward-only — no revocation protocol for degraded subsystem evidence
- P2 | GHA-4 | "The Pitch" | Trust portability unaddressed — earned trust is context-bound with no cross-project transfer mechanism
- P2 | GHA-5 | "Capability Mesh" | Interspect appears both as a subsystem in the mesh (Measurement row) and as the downstream aggregation point in the flywheel — dual role conflates evidence producer with evidence assessor
Verdict: risky

### Summary

The brainstorm articulates "compounding evidence, earned trust" as the central thesis but does not specify the institutional machinery that makes evidence trustworthy. In the hallmarking tradition, evidence has value only because the assay office (1) tests independently of the maker, (2) records results in a tamper-resistant ledger, (3) gates specific privileges at defined thresholds, and (4) revokes privileges when evidence of failure emerges. The brainstorm describes the goldsmith's work (subsystem evidence signals) but not the assay office (who independently verifies those signals, where they accumulate, and what thresholds gate authority changes). The "authority ratchet" is named as a mechanism but described only in the forward direction.

### Issues Found

GHA-1. P0: Evidence verification architecture is unspecified. The brainstorm's thesis — "trust in autonomous systems is earned through observable evidence that compounds over time" — depends on evidence being independently verifiable. However, the capability mesh (lines 84-98) lists evidence signals per subsystem (gate pass rate, conflict resolution rate, query hit rate) without specifying who or what independently verifies these signals. In the current description, each subsystem self-reports its own quality metrics: Routing reports its own gate pass rate, Interop reports its own conflict resolution rate, Interweave reports its own query hit rate. This is the goldsmith stamping their own hallmark. PHILOSOPHY.md (line 1) states "Every action produces evidence" and (line 2) "Evidence earns authority," but the brainstorm does not position any component as the independent verification layer. Interspect is described as a flywheel participant, not an independent assessor. The concrete failure scenario: a subsystem with degraded quality continues to self-report acceptable metrics, earning authority it has not actually demonstrated. This structurally undermines the entire evidence thesis because self-reported evidence is not evidence in the trust-building sense.

**Recommended fix**: Add a subsection under "Key Decisions" specifying that Interspect (or a dedicated measurement subsystem) serves as the architecturally independent verification layer — it observes subsystem behavior through its own instrumentation, not through subsystem-reported metrics. The vision should state this separation as a structural requirement, not an implementation detail.

GHA-2. P1: Capability mesh lacks maturity thresholds. The mesh (lines 84-98) lists 10 subsystems with "Current State" and "Evidence Signal" columns but defines no thresholds for maturity progression. There is no equivalent of "50 hallmarked pieces over three years permits export." For example, Routing's evidence signal is "gate pass rate, model cost ratio" — but what gate pass rate moves Routing from "static" to "complexity-aware" to "adaptive"? Without defined thresholds, authority escalation is either manual judgment or undefined, contradicting the claim that trust is "earned through observable evidence" rather than granted by fiat.

**Recommended fix**: Add a third column "Maturity Gates" or a separate table mapping evidence signal values to maturity transitions. Even approximate ranges ("gate pass rate >85% for 30 days triggers complexity-aware routing") would make the evidence thesis concrete.

GHA-3. P1: Authority ratchet lacks revocation mechanism. The brainstorm names "authority ratchet as mechanism" as a proposed PHILOSOPHY.md addition (lines 119-121) and describes Ockham's "graduated authority model (evidence-gated promotions/demotions)." However, the brainstorm's own framing emphasizes forward movement: "Evidence compounds. Trust ratchets." (line 29). The hallmarking system's power comes equally from its ability to revoke privileges as to grant them. If Interop's conflict resolution rate drops from 95% to 40%, does previously earned authority persist or is it revoked? PHILOSOPHY.md already states "trust is a dial" (line 2) which implies bidirectionality, but the brainstorm does not specify the regression mechanism.

**Recommended fix**: Add explicit language in the "authority ratchet as mechanism" proposal stating that the ratchet is bidirectional — evidence of sustained degradation triggers authority demotion through a defined protocol, not just evidence of improvement triggering promotion.

GHA-4. P2: Trust portability unaddressed. The brainstorm does not address whether earned trust transfers across contexts. In the hallmarking system, the hallmark is portable — a buyer in Bruges trusts London gold because the hallmark compresses institutional verification into a portable symbol. Does a subsystem's evidence record in one project transfer to another Sylveste deployment? The "Horizons" section (line 100-102) mentions "cross-project federation" but does not connect it to trust portability. This is not blocking for v5.0 but represents a gap in the evidence thesis's completeness.

GHA-5. P2: Interspect's dual role conflates evidence production with evidence assessment. In the capability mesh, Interspect appears as a subsystem (Measurement row, line 92) with its own evidence signals (attribution chain completeness). In the flywheel diagram (lines 64-69), Interspect is the downstream aggregation point that all upstream sources feed into. This dual role means Interspect is both a subsystem being measured AND the system that measures other subsystems. In hallmarking terms, this is the assay office also being one of the goldsmiths whose work is assayed. The brainstorm should clarify whether Interspect's own measurement quality is assessed by an independent party.

### Improvements

IMP-1. Consider adding a "Trust Architecture" subsection to Key Decisions that explicitly maps: (a) evidence producers (subsystems), (b) evidence verifiers (independent measurement), (c) evidence store (where cumulative records live), (d) privilege gates (thresholds that trigger authority changes). This would make the hallmarking structure visible.

IMP-2. The resolved question on "measurement hardening" (lines 133) mentions Factory Substrate and FluxBench as complementary evidence streams — the vision should clarify which of these serves the independent verification role vs. which are subsystem-level self-measurement.

<!-- flux-drive:complete -->
