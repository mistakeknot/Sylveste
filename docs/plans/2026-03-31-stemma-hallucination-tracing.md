---
artifact_type: plan
bead: sylveste-rsj.10
stage: planned
---

# Plan: Stemma Hallucination Tracing

## Tasks

### 1. Extend findings schema with stemma fields
- [x] Add `evidence_sources`, `stemma_group`, `shared_context_overlap` to findings.json schema
- **Files:** `interverse/intersynth/agents/synthesize-review.md`

### 2. Add stemma grouping to synthesis Step 6 (dedup)
- [x] After merging findings, collect evidence_sources from each finding's Evidence field
- [x] Compute pairwise Jaccard similarity of evidence_sources
- [x] Group findings with Jaccard > 0.5 into stemma groups (SG-1, SG-2, ...)
- [x] Tag each finding with its stemma group and shared sources
- **Files:** `interverse/intersynth/agents/synthesize-review.md`

### 3. Add convergence correction for stemma groups
- [x] In convergence scoring (Step 3.7 conductor score), apply correction:
  - Count distinct evidence source sets, not raw agent count
  - `corrected_convergence = count(distinct_evidence_sets_in_group)`
- [x] Add `convergence_corrected` field alongside existing `convergence`
- **Files:** `interverse/intersynth/agents/synthesize-review.md`

### 4. Add Stemma Analysis section to report output
- [x] New section in markdown report showing stemma groups
- [x] Format: "N findings share evidence from [sources] — convergence adjusted from M to K"
- [x] Add `stemma_analysis` to findings.json output
- **Files:** `interverse/intersynth/agents/synthesize-review.md`

## Estimated complexity: C3 (1 file, conceptually dense but localized)
