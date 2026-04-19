### Findings Index
- P1 | CT-1 | "Capability Mesh" | Maturity promotion thresholds are descriptive, not operational — no sample sizes, time windows, or statistical power specified
- P1 | CT-2 | "Trust Architecture" | Evidence quality tiers lack weighting mechanism — Tier 1/2/3 distinction exists but aggregation formula is absent
- P2 | CT-3 | "Trust Architecture" | Epoch trigger list is illustrative, not exhaustive — "defined events" need an actual registry
- P2 | CT-4 | "The Flywheel" | No distinction between leading and lagging indicators in evidence signals
- P2 | CT-5 | "Trust Architecture" | Demotion observation window undefined — "sustained degradation" needs a concrete duration
Verdict: needs-changes

### Summary

The v5.0 document has materially improved from v4.0. The M0-M4 maturity scale, trust lifecycle (earn/compound/epoch/demote), and evidence quality tiers (Tier 1-3) are all present and structurally sound. The clinical-trial-phasing lens confirms that the four-phase trust lifecycle maps cleanly to Phase I-IV trial logic. However, the evidence thresholds remain aspirational rather than operational — the document says "pre-specified thresholds" exist but never specifies them.

### Issues Found

CT-1. P1: Maturity promotion thresholds are descriptive, not operational (Capability Mesh, lines 141-149)
The maturity scale table defines M0-M4 with criteria like "evidence signals yielding data for 30+ days" (M2) and "evidence thresholds defined and tested" (M3). But the promotion criteria themselves — what specific values of gate pass rate, sync latency, or finding precision constitute "sufficient evidence" — are not specified anywhere in the document. In clinical trials, Phase II/III boundaries require pre-specified primary endpoints with statistical significance thresholds. Without these, promotion decisions become post-hoc judgment calls.
Failure scenario: A subsystem claims M3 ("calibrated") because someone decided the evidence "looks good enough" — no reproducible standard, no independent auditor can verify the decision.
Fix: Add a "Promotion Criteria Registry" section (or reference one) that specifies per-subsystem, per-maturity-level: evidence type, minimum observation window, threshold value, and evaluating authority.

CT-2. P1: Evidence quality tiers lack aggregation mechanism (Trust Architecture, lines 203-207)
The document defines three evidence quality tiers (Tier 1: controlled, Tier 2: observational, Tier 3: anecdotal) with "highest weight," "standard weight," and "lowest weight." But the actual weighting function is absent. How many Tier 3 observations equal one Tier 1 experiment? Is it additive, multiplicative, or threshold-based? In clinical research, evidence hierarchies (Cochrane, GRADE) specify how lower-tier evidence is weighted against higher-tier — typically a discount factor, not mere ordering.
Failure scenario: 100 Tier 3 (anecdotal) observations overwhelm 2 Tier 1 (controlled) experiments in a poorly specified aggregation, leading to premature promotion.
Fix: Specify a concrete aggregation rule — e.g., "Tier 3 evidence contributes at 0.1x weight; promotion requires at least N Tier 1 or Tier 2 observations meeting the threshold."

CT-3. P2: Epoch trigger list is illustrative, not exhaustive (Trust Architecture, lines 211-212)
"Epochs are triggered by defined events, not by time alone" — but which events? The document gives three examples (model API change, architecture migration, subsystem replacement) but does not commit to a complete list or a classification rule for what constitutes an epoch-triggering event. This matters because missing an epoch trigger means stale trust persists unchallenged.
Fix: Define a classification rule (e.g., "any change that invalidates >50% of the evidence base for a subsystem triggers a partial epoch") rather than enumerating specific events.

CT-4. P2: No distinction between leading and lagging indicators (The Flywheel, lines 94-118; Capability Mesh, lines 155-167)
The evidence signals in the capability mesh (e.g., "gate pass rate," "finding precision," "conflict resolution rate") are a mix of leading indicators (predictive) and lagging indicators (outcome-based), but the document does not classify them. Clinical trials distinguish these sharply because leading indicators enable early stopping or acceleration, while lagging indicators only confirm after the fact.
Fix: Tag each evidence signal in the mesh table as "leading" or "lagging" and specify how leading indicators feed early warning systems.

CT-5. P2: Demotion observation window undefined (Trust Architecture, line 213)
"When evidence shows sustained degradation (regression indicators exceeding threshold for a defined observation window)" — the observation window is never defined. How many days/sprints constitute "sustained"? Without this, demotion is either too trigger-happy (single bad sprint) or too slow (regression persists for months).
Fix: Specify a default observation window (e.g., "3 consecutive evaluation periods or 14 calendar days, whichever is longer") with per-subsystem override capability.

### Improvements

IMP-CT-1. Add a "Data Safety Monitoring Board" equivalent — a periodic review cadence where all subsystem evidence is assessed holistically, not just per-subsystem. The capability mesh's weakest-link constraint needs a mechanism to surface WHICH subsystem is the bottleneck, analogous to DSMB interim analyses.

IMP-CT-2. The trust transfer section (lines 224-225) for subsystem replacement is well-conceived but should specify the verification period duration and the comparison methodology (non-inferiority testing vs. equivalence testing).

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 3)
SUMMARY: Evidence architecture is structurally sound but operationally underspecified — promotion thresholds, aggregation weights, and demotion windows need concrete values to move from aspirational to actionable.
---
<!-- flux-drive:complete -->
