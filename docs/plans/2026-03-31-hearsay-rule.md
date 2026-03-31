---
artifact_type: plan
bead: sylveste-rsj.12
stage: planned
---

# Plan: Hearsay Rule

## Tasks

### 1. Add hearsay detection config to reaction.yaml
- [x] Add `hearsay_detection` section with enable flag and thresholds
- **Files:** `interverse/interflux/config/flux-drive/reaction.yaml`

### 2. Add Step 3.7b (hearsay classification) to synthesize-review.md
- [x] After reaction ingestion (3.7), before sycophancy scoring (3.8)
- [x] For each confirming reaction, check for independent evidence
- [x] Tag reactions with `"hearsay": true|false`
- [x] Detection: no new file:line evidence, cites original agent by name, or high textual overlap with original finding
- **Files:** `interverse/intersynth/agents/synthesize-review.md`

### 3. Update convergence scoring to apply hearsay discount
- [x] In Step 6.5 (QDAIF/convergence), hearsay reactions count as 0.0 instead of 1.0
- [x] Update convergence ratio calculation to exclude hearsay
- **Files:** `interverse/intersynth/agents/synthesize-review.md`

### 4. Add hearsay summary to synthesis output
- [x] In the findings.json schema, add `hearsay_count` field
- [x] In the markdown report, add hearsay stats to Reaction Analysis section
- **Files:** `interverse/intersynth/agents/synthesize-review.md`

### 5. Update reaction prompt to encourage independent evidence
- [x] In the reaction round prompt (interflux), add instruction for agents to provide independent file:line evidence when confirming
- [x] Clarify that "as [agent] noted" style confirmations will be discounted
- **Files:** `interverse/interflux/config/flux-drive/reaction-prompt.md` (or equivalent)

## Estimated complexity: C3 (2-3 files, clear scope)
