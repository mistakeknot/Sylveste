### Findings Index
- P2 | WH-1 | "The Flywheel / Current State" | Flywheel minimum operating requirements now stated but operational/aspirational boundary could be sharper
- P2 | WH-2 | "Capability Mesh / Interface Evidence" | Interface evidence table addresses interaction failures but lacks maturity-gated testing
- P1 | WH-3 | "Capability Mesh / Current Mesh State" | Dev State column still conflates feature completeness with operational maturity
Verdict: needs-changes

### Summary

The v5.0 vision doc has significantly improved on the first review's P0 (flywheel operating without proven upstream sources). Line 120 now explicitly states "Today the flywheel operates on Interspect evidence alone — the v4.0 configuration" and "The flywheel doesn't wait for all sources — it operates with whatever evidence is available and improves as more sources come online." The balancing loops section (lines 124) adds the weakest-link constraint (B1) and evidence saturation (B2). The Interface Evidence table (lines 182-193) addresses cross-subsystem interaction failures. However, the Dev State column in the capability mesh still describes feature completeness rather than operational testing, and the interface evidence table does not specify at which maturity levels interface testing becomes mandatory.

### Issues Found

WH-1. P2: Flywheel operational/aspirational boundary — Line 120 distinguishes current state (Interspect only) from v5.0 expansion (four upstream sources in early phases). This is a substantial improvement. The flywheel diagram (lines 94-118) still visually presents all five sources feeding Interspect as if this is the current architecture, but the "Current state" paragraph immediately following it clarifies. The visual/textual juxtaposition is a minor legibility issue, not a structural gap. P2 because a reader skimming the diagram could misread the current state, but the text is unambiguous.

WH-2. P2: Interface evidence lacks maturity gating — The Interface Evidence table (lines 186-193) lists 5 cross-subsystem interfaces with monitoring signals. This addresses the first review's concern about emergent interaction failures. However, the table does not specify at which maturity level each interface becomes mandatory to monitor. In the waka hourua tradition, you test hull-lashing interaction at coastal level, not lagoon level. Question: should the Interface Evidence table include a "Required at" column specifying the minimum maturity level at which this interface monitoring activates? This would connect the interface table to the maturity scale and dependency DAG.

WH-3. P1: Dev State conflates feature completeness with operational maturity — The capability mesh (lines 153-166) has a "Dev State" column with entries like "8/10 epics shipped" (Persistence), "F1-F7 shipped" (Governance), and "~80% implemented (3,515 LOC Go)" (Measurement). These describe development completeness, not operational maturity. The adjacent "Maturity" column (M0-M2) does track operational maturity, which is correct. However, the "Dev State" column creates ambiguity: does "F1-F7 shipped" mean the features exist in code (M1) or have been tested under real conditions (M2)? The mesh would be clearer if "Dev State" were renamed to "Implementation Status" or if the column explicitly noted what testing has been done. The tufunga distinguishes between a carved hull (features shipped) and a hull that has been in the water (operationally tested). This is P1 because a reader using this mesh to assess system readiness could mistake development completion for operational readiness.

### Improvements

IMP-1. Add a "Required at" column to the Interface Evidence table (lines 186-193) specifying the minimum maturity level at which each interface monitor activates.

IMP-2. Rename "Dev State" to "Implementation Status" in the capability mesh, or add a brief note clarifying that the Maturity column (not Dev State) indicates operational readiness.

IMP-3. Consider adding a visual annotation to the flywheel diagram (lines 94-118) marking which sources are currently operational vs. planned, so the diagram is self-contained without requiring the reader to find the "Current state" paragraph.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 3 (P0: 0, P1: 1, P2: 2)
SUMMARY: Weakest-link constraint and balancing loops are now sound. Flywheel distinguishes current vs. aspirational state. One P1: Dev State column conflates implementation with operational testing. Interface evidence table exists but lacks maturity-gated activation.
---
<!-- flux-drive:complete -->
