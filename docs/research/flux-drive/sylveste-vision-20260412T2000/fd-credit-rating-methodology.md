### Findings Index
- P1 | CR-1 | "Capability Mesh" | Min-of-maturities aggregation discards information — no mechanism to weight by criticality or compensate strength in one subsystem against weakness in another
- P1 | CR-2 | "Capability Mesh" | Evidence signals are incommensurable — "gate pass rate" and "query hit rate" cannot be compared on a common scale without a normalization function
- P2 | CR-3 | "The Flywheel" | Evidence compounding does not distinguish point-in-time vs through-the-cycle assessment
- P2 | CR-4 | "North Star Metric" | Goodhart caveat acknowledged but no operational anti-gaming mechanism specified
- P2 | CR-5 | "Trust Architecture" | No audit trail specification — cannot reconstruct why a maturity level changed from evidence alone
Verdict: needs-changes

### Summary

The v5.0 document addresses the prior review's finding about lack of subsystem-level tracking (the mesh replaces the linear L0-L4 ladder). The criticality tiers (inspired by aviation DALs) are a significant improvement — they acknowledge that not all subsystems deserve equal rigor. However, the aggregation methodology remains underspecified. The document says "system-level trust = min(maturity across mesh cells)" but this is the simplest possible aggregation, and credit rating methodology demonstrates why minimums produce misleading composite scores.

### Issues Found

CR-1. P1: Min-of-maturities aggregation discards information (Capability Mesh, line 151)
"System-level trust = min(maturity across mesh cells)." This is a pure-minimum aggregation — the system is as mature as its weakest cell. While this is conservative (desirable for safety), it has two problems from a rating methodology perspective:
(a) It makes Coordination (Medium criticality) equally constraining as Governance (Critical criticality). The document introduces criticality tiers but the aggregation function ignores them.
(b) It provides zero information about system trajectory. A system at min=M1 with 8 cells at M3 and 1 cell at M1 is very different from a system at min=M1 with 5 cells at M1. Both display "M1" to stakeholders.
In credit ratings, a sovereign with strong fiscal metrics but weak institutional governance gets a composite rating that reflects BOTH — not just the worst dimension.
Failure scenario: The system displays "M1" for months because one low-criticality subsystem (e.g., Execution, which is at M0) blocks the narrative, while high-criticality subsystems (Governance, Measurement) have already reached M2+. This creates false pessimism that undermines stakeholder trust in the maturity model itself.
Fix: Either (a) adopt a weighted-minimum that only gates on subsystems above a criticality threshold (e.g., "system-level trust = min(maturity of Critical and High subsystems)") or (b) report both the floor and the weighted average — "System maturity: M1 (floor) / M2.3 (weighted)" — so the composite conveys trajectory.

CR-2. P1: Evidence signals are incommensurable (Capability Mesh, lines 155-167)
The mesh lists evidence signals per subsystem: "Event integrity, query latency" (Persistence), "Conflict rate, reservation throughput" (Coordination), "Finding precision, false positive rate" (Review), etc. These are measured in different units (rates, latencies, counts) on different scales. Taking the minimum of maturity levels derived from these signals requires each signal to be mapped to the same M0-M4 ordinal scale — but the mapping function is not specified.
What is M2 for "query latency"? Is it <100ms? <500ms? The mapping from continuous signals to ordinal maturity is the most critical piece of the methodology and it is entirely absent.
Failure scenario: Two engineers evaluating the same subsystem assign different maturity levels because they interpret "operational" differently when looking at the same metrics.
Fix: Define a "maturity mapping table" per evidence signal — concrete thresholds that convert continuous metrics to M0-M4 ordinal values. Example: "Gate pass rate: M0=N/A, M1=any, M2=>70% over 30d, M3=>85% over 90d with promotion criteria tested, M4=>95% with self-correction."

CR-3. P2: No point-in-time vs through-the-cycle distinction (The Flywheel, lines 120-124)
The flywheel claims "evidence compounds" but does not distinguish between point-in-time assessment (current evidence snapshot) and through-the-cycle assessment (evidence trend over multiple cycles). Credit ratings learned this lesson in 2008: point-in-time ratings are volatile and procyclical; through-the-cycle ratings are stable but can miss sudden deterioration. The v5.0 document does not specify which assessment mode the maturity levels represent.
Does M2 mean "evidence signals yielding data NOW" or "evidence signals have consistently yielded data for 30+ days"? The 30-day window in M2 criteria suggests through-the-cycle, but this is not stated explicitly, and no mechanism prevents a subsystem from being assessed at M2 based on a single good 30-day period followed by degradation.
Fix: Explicitly state the assessment mode. Recommend through-the-cycle as the primary mode (consistent with the document's emphasis on sustainability) with a point-in-time "watchlist" overlay for early warning.

CR-4. P2: Goodhart caveat is rhetorical, not operational (North Star Metric, lines 331-332)
The document includes a Goodhart caveat: "Rotate emphasis, diversify evaluation dimensions, and watch for agents optimizing the metric at the expense of actual quality." This is good acknowledgment but provides no operational mechanism. When does rotation occur? Who decides? What triggers a rotation?
PHILOSOPHY.md provides more detail ("Anti-gaming by design: Rotate metrics, cap optimization rate, randomize audits"), but the vision document should reference or summarize the operational mechanism, not just the principle.
Fix: Cross-reference PHILOSOPHY.md's anti-gaming mechanisms explicitly, or specify the rotation cadence in the North Star Metric section.

CR-5. P2: No audit trail specification (Trust Architecture, lines 199-225)
The trust lifecycle (earn/compound/epoch/demote) is well-structured, but there is no specification for how trust transitions are recorded. Can a human reconstruct why Governance moved from M1 to M2? What evidence was cited? When? Who (or what system) made the assessment? In credit rating methodology, the "rating action" includes: new rating, previous rating, rationale, evidence cited, outlook, and reviewing analyst.
Fix: Specify that every maturity transition produces a durable receipt containing: subsystem, old level, new level, trigger (promotion evidence or demotion indicator), evidence citations, and evaluating authority (Interspect or human).

### Improvements

IMP-CR-1. Consider publishing a "methodology document" analogous to rating agency methodologies — a standalone artifact that specifies exactly how evidence maps to maturity levels. The vision doc should reference it; the methodology doc should be the operational specification.

IMP-CR-2. Add an "outlook" concept to maturity assessments — not just current level but trajectory (positive/stable/negative). This provides stakeholders with forward-looking information that the current min-of-maturities snapshot cannot convey.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 3)
SUMMARY: Evidence aggregation methodology is underspecified — the min-of-maturities rule discards criticality weighting, evidence signals lack commensurability mappings, and trust transitions have no audit trail.
---
<!-- flux-drive:complete -->
