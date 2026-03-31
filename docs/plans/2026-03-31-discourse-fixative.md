---
bead: sylveste-rsj.9
date: 2026-03-31
type: plan
reviewed: true
review-method: flux-drive (2 agents: fd-architecture, fd-correctness)
review-verdict: needs-changes (3 P1 — all addressed in implementation)
---

# Discourse Fixative — Implementation Plan

## Overview

Add a discourse fixative step to the reaction phase that reads approximate Sawyer health metrics from Phase 2 output and, when health is degraded, injects corrective context into reaction prompts. 1 file to create, 2 to modify. Zero new agent dispatches.

## Tasks

### Task 1: Create fixative configuration

**File:** `interverse/interflux/config/flux-drive/discourse-fixative.yaml`
**Action:** Create new file
**Description:**

```yaml
fixative:
  enabled: true
  triggers:
    participation_gini_above: 0.3
    novelty_estimate_below: 0.1
    # Relevance uses evidence-bearing findings ratio (same as Sawyer)
    relevance_estimate_below: 0.5
  max_injection_tokens: 150
  injections:
    imbalance: >-
      Note: Agent participation is imbalanced. If you have a perspective
      that differs from the dominant viewpoint, prioritize expressing it
      over confirming existing findings.
    convergence: >-
      Note: Most agents found similar issues. Focus your reaction on what
      is MISSING from peer findings rather than confirming what they found.
      What didn't anyone check?
    drift: >-
      Note: Some findings lack specific evidence. Anchor your reactions
      to concrete file:line references from the codebase.
    collapse: >-
      Note: Discourse quality indicators suggest echo-chamber risk. Before
      reacting, re-read the original review prompt. Challenge at least one
      peer finding you initially agreed with.
```

**Depends on:** Nothing

### Task 2: Add fixative context slot to reaction prompt template

**File:** `interverse/interflux/config/flux-drive/reaction-prompt.md`
**Action:** Modify
**Description:** Add `{fixative_context}` template slot after the Move Type Assignment section and before the Rules section. When the fixative is inactive, this slot is empty (adds nothing to the prompt). When active, it contains 1-3 contextual notes.

```markdown
{fixative_context}
```

**Depends on:** Task 1

### Task 3: Add fixative health check to reaction phase

**File:** `interverse/interflux/skills/flux-drive/phases/reaction.md`
**Action:** Modify
**Description:** Add a new Step 2.5.2b between Step 2.5.2 (Collect Findings Indexes) and Step 2.5.3 (Build Per-Agent Reaction Prompts).

**Step 2.5.2b: Discourse Fixative Health Check**

If `discourse-fixative.yaml` `fixative.enabled` is true:

1. **Compute approximate health metrics** from the Findings Indexes already collected in Step 2.5.2:

   - **Participation Gini:** Count findings per agent from the collected indexes. Compute Gini coefficient.
   - **Novelty estimate:** From the convergence gate data (Step 2.5.0): `novelty_estimate = 1 - overlap_ratio`. This is approximate — the authoritative metric comes from synthesis later.
   - **Relevance estimate:** Count how many P0/P1 findings have file:line references in their titles or IDs vs. generic observations.

2. **Check triggers** against thresholds from `discourse-fixative.yaml`:
   - `gini > participation_gini_above` → fire `imbalance` injection
   - `novelty_estimate < novelty_estimate_below` → fire `convergence` injection
   - `relevance_estimate < relevance_estimate_below` → fire `drift` injection
   - If ALL three fire simultaneously → also fire `collapse` injection (compound degradation)

3. **Build fixative context string.** Concatenate all fired injections, separated by newlines. If no triggers fire, fixative_context is empty.

4. **Log fixative activity:**
   ```
   Fixative: {active|inactive} ({N} injections: {injection_names})
   ```

5. **Pass `fixative_context` to Step 2.5.3** for template slot filling.

**Modification to Step 2.5.3:** Add `{fixative_context}` to the template slot filling list:
```
- `{fixative_context}` — discourse fixative injections (empty if healthy)
```

**Modification to Step 2.5.5 (Report):** Append fixative status:
```
Fixative: {active|inactive} ({N} injections)
```

**Depends on:** Task 1, Task 2

## Build Sequence

```
Task 1 (config) ──┬─→ Task 2 (prompt template)
                   └─→ Task 3 (reaction phase) ── depends on Task 2
```

Task 2 and the config portion of Task 3 can start in parallel.

## Verification

1. `python3 -c "import yaml; yaml.safe_load(open('interverse/interflux/config/flux-drive/discourse-fixative.yaml'))"` — YAML validity
2. Grep for `fixative_context` in reaction-prompt.md — template slot present
3. Grep for `fixative` in reaction.md — health check step added
4. Grep for `discourse-fixative.yaml` in reaction.md — config reference present
5. Verify fixative_context appears in Step 2.5.3 template slot list
