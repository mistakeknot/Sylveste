---
artifact_type: prd
bead: sylveste-g3b
stage: strategy
---

# PRD: Interflux Reaction Round Activation

## Problem Statement

The interflux reaction round (Phase 2.5) is fully designed and partially implemented but has never produced output. The runtime path from Phase 2 → Phase 2.5 → Phase 3 needs validation and any broken links fixed.

## Success Criteria

1. A real flux-drive review produces `.reactions.md` files in the output directory
2. Intersynth correctly processes reactions (conductor scoring, hearsay, sycophancy)
3. The synthesis report contains a "Contested Findings" or "Reaction Analysis" section
4. An Interspect evidence event is emitted for the reaction outcome
5. Cost overhead is <10% of the base review (measured)

## Features

### F1: Runtime Validation
Run a real flux-drive review against a known document (e.g., the decomposition calibration plan). Observe whether Phase 2.5 fires. Trace any failure to its root cause.

### F2: Fix Broken Links
Fix whatever prevents the reaction round from executing. Likely candidates: convergence gate script errors, template filling issues, agent dispatch parameter mismatches.

### F3: Interspect Evidence Emission
After the reaction round completes, emit a `reaction_outcome` event to Interspect with: agent count, reaction count, convergence delta (before vs after reactions), sycophancy flags, discourse health metrics. This closes the loop — reaction quality becomes observable.

### F4: End-to-End Verification
Run a second review to confirm the full pipeline: Phase 2 → Phase 2.5 → Phase 3 synthesis with reactions → evidence emission.

## Non-Goals

- Changing the reaction protocol design (already validated in rsj.2)
- Adding new discourse protocols (pressing, conduction, yes-and)
- Modifying agent topology or fixative algorithms
- Garden Salon integration

## Dependencies

- interflux plugin (existing)
- intersynth plugin (existing)
- interspect plugin (for evidence emission)
