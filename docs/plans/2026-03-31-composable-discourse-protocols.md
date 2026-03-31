---
bead: sylveste-rsj.7
date: 2026-03-31
type: plan
reviewed: true
review-method: flux-drive (3 agents: fd-architecture, fd-correctness, fd-quality)
review-verdict: needs-changes (1 P0, 3 P1 — all addressed below)
---

# Composable Discourse Protocols — Implementation Plan (v2, post-review)

## Overview

Add Sawyer Flow Envelope (health monitor) and Lorenzen Dialogue (move validation) to interflux's existing reaction round and synthesis pipeline. 4 files to create, 3 to modify. Zero new agent dispatches — all computation happens in orchestrator and synthesis.

**Review findings incorporated:** 1 P0 (findings.json two-writer race), 3 P1s (nil-safe Move Type, subsume_convergence_gate no-op, cross-boundary config read). See review output at `docs/research/flux-drive/composable-discourse-protocols/`.

## Tasks

### Task 1: Create discourse configuration files

**Files:** Create `interverse/interflux/config/flux-drive/discourse-sawyer.yaml` and `interverse/interflux/config/flux-drive/discourse-lorenzen.yaml`
**Action:** Create 2 new files
**Description:** Flat naming (no subdirectory) to match existing config layout convention. [QUAL-03 fix]

`discourse-sawyer.yaml`:
```yaml
flow_envelope:
  enabled: true
  participation_gini_max: 0.3
  novelty_rate_min: 0.1
  response_relevance_min: 0.7
  # Convergence gate subsumption is DEFERRED to Phase 2/3.
  # For now, the existing skip_if_convergence_above in reaction.yaml
  # continues to operate independently. [CDP-03 fix]
  subsume_convergence_gate: false
  states:
    healthy:
      gini_below: 0.3
      novelty_above: 0.1
      relevance_above: 0.7
    degraded:
      gini_below: 0.5
      novelty_above: 0.05
      relevance_above: 0.5
```

`discourse-lorenzen.yaml`:
```yaml
dialogue_game:
  enabled: true
  move_types:
    attack: "Challenge a specific claim with counter-evidence"
    defense: "Provide evidence supporting a challenged claim"
    new-assertion: "Introduce a new claim not yet in the dialogue"
    concession: "Accept an attack and withdraw or modify the original claim"
  validation:
    attack_requires_evidence: true
    defense_requires_new_evidence: true
    new_assertion_max_per_agent: 2
  legality_scoring:
    valid_attack: 1.0
    valid_defense: 1.0
    valid_new_assertion: 0.8
    invalid_move: 0.2
```

Note: move type keys use hyphens (`new-assertion`) to match the reaction prompt output contract. [CDP-07 fix]

**Depends on:** Nothing

### Task 2: Add Lorenzen move types to reaction prompt template

**File:** `interverse/interflux/config/flux-drive/reaction-prompt.md`
**Action:** Modify
**Description:** Add Move Type field to the output format. Each reaction now includes:

```markdown
- **Finding**: [Finding ID]
  - **Stance**: agree | partially-agree | disagree | missed-this
  - **Move Type**: attack | defense | new-assertion | concession
  - **Independent Coverage**: yes | partial | no
  - **Rationale**: [1-2 sentences]
  - **Evidence**: [file:line, spec, or own finding ID]
```

Add instruction section explaining move type assignment:
- `disagree` → `attack` (must cite counter-evidence)
- `agree` with new evidence → `defense`
- `missed-this` → `new-assertion`
- `agree` withdrawing/modifying own prior finding → `concession`
- If unsure, omit Move Type — the synthesis agent will infer or skip validation. [CDP-02 partial]

**Depends on:** Task 1

### Task 3: Create discourse health diagnostic script

**File:** `interverse/interflux/scripts/discourse-health.sh`
**Action:** Create new file
**Description:** Standalone diagnostic tool that computes Sawyer Flow Envelope metrics. **This is NOT the canonical path for populating findings.json** — that is the synthesis agent's job (Task 5). This script exists for:
- CLI diagnostics: `bash discourse-health.sh /path/to/output-dir`
- Post-hoc analysis outside the synthesis pipeline
- Testing health metric computation independently

Input: OUTPUT_DIR containing findings.json. Output: JSON to stdout + writes `{OUTPUT_DIR}/discourse-health.json`.

Metrics computed from findings.json:
1. **Participation Gini:** Count findings per agent, compute Gini index
2. **Novelty rate:** Fraction of findings where `convergence_corrected == 1` (uses stemma-corrected convergence, not raw). Falls back to `convergence == 1` if `convergence_corrected` is null. [CDP-05 fix]
3. **Response relevance:** Fraction of findings with non-empty `evidence_sources` arrays
4. **Flow state:** Compare against discourse-sawyer.yaml thresholds → healthy/degraded/unhealthy

**Depends on:** Task 1

### Task 4: Add discourse metrics to synthesis agent (single-writer)

**File:** `interverse/intersynth/agents/synthesize-review.md`
**Action:** Modify
**Description:** This is the consolidated task for ALL discourse metrics in synthesis. [CDP-01 P0 fix: single writer for findings.json] [QUAL-04 fix: consolidate tasks 5/6/7 into one]

The synthesis agent already computes per-agent finding counts (Step 3), convergence (Step 6), and sycophancy (Step 3.8). Discourse metrics piggyback on this existing data — no new file reads needed. [ARCH-04 fix]

**Input contract extension:** Add `LORENZEN_CONFIG` parameter (optional). The orchestrator passes Lorenzen validation rules as a JSON string, not as a file path. This avoids cross-plugin filesystem dependency. [ARCH-02 fix]

```
LORENZEN_CONFIG={"enabled":true,"attack_requires_evidence":true,"defense_requires_new_evidence":true,"new_assertion_max_per_agent":2}
```

**New Step 3.7c: Lorenzen Move Validation**

After Step 3.7b (hearsay classification), if `LORENZEN_CONFIG` is provided and `enabled` is true:

1. For each reaction parsed in Step 3.7, check for `Move Type` field.
   - **If Move Type is present:** validate per the rules below.
   - **If Move Type is absent:** set `move_type: null`, `move_legality: null`. Skip validation for this reaction. Do NOT infer move type from Stance — this produces unreliable results. [CDP-02 fix]

2. Validation rules:
   - **attack (disagree):** Valid if Evidence field contains a file:line or spec reference different from the original finding's evidence. Invalid if no counter-evidence.
   - **defense (agree with evidence):** Valid if Evidence field contains references not already cited by the original finding. Invalid if it only re-cites existing evidence.
   - **new-assertion (missed-this):** Count per agent. If exceeds `new_assertion_max_per_agent`, excess get `move_legality: capped`.
   - **concession:** Always valid.

3. Tag each reaction:
   ```json
   {"move_type": "attack", "move_legality": "valid", "legality_score": 1.0}
   ```

**New Step 6.6: Compute Sawyer Flow Envelope**

After Step 6.5 (QDAIF), compute discourse health from data already in memory:

1. **Participation Gini:** From agent finding counts (already tallied in Step 3). Gini = (2 * sum(i * x_i)) / (n * sum(x_i)) - (n+1)/n, where x_i are sorted finding counts.
2. **Novelty rate:** From dedup results (Step 6). Novelty = count(findings where convergence_corrected == 1 OR (convergence_corrected is null AND convergence == 1)) / total_findings. [CDP-05 fix]
3. **Response relevance:** From findings list. Relevance = count(findings with non-empty evidence_sources) / total_findings.
4. **Flow state:** Compare against thresholds (hardcoded defaults matching discourse-sawyer.yaml: gini_max=0.3, novelty_min=0.1, relevance_min=0.7). Config override via future `SAWYER_CONFIG` param.

**Extended Step 8: Write outputs**

Add to findings.json schema:
```json
{
  "discourse_health": {
    "participation_gini": 0.0,
    "novelty_rate": 0.0,
    "response_relevance": 0.0,
    "flow_state": "healthy",
    "warnings": []
  },
  "discourse_analysis": {
    "lorenzen": {
      "total_moves": 0,
      "valid_moves": 0,
      "invalid_moves": 0,
      "null_moves": 0,
      "move_distribution": {"attack": 0, "defense": 0, "new-assertion": 0, "concession": 0}
    }
  }
}
```

Add `### Discourse Quality` section to synthesis.md:
```markdown
### Discourse Quality

**Flow State:** {flow_state} (Gini={gini}, novelty={novelty_rate}, relevance={response_relevance})
**Move Legality:** {valid_count}/{total_moves} moves structurally valid ({null_count} skipped — no Move Type)
**Move Distribution:** {attack}A {defense}D {new-assertion}N {concession}C

[If any invalid moves: table with agent, finding, reason]
[If flow_state is unhealthy: warnings list]
```

Add to compact return value:
```
Discourse: {flow_state} | Legality: {valid}/{total} valid | Moves: {attack}A {defense}D {new-assertion}N {concession}C
```

**Depends on:** Task 1 (config defines thresholds), Task 2 (agents produce Move Type)

### Task 5: Wire discourse health into synthesis phase

**File:** `interverse/interflux/skills/flux-drive/phases/synthesize.md`
**Action:** Modify
**Description:** Two changes:

1. In the synthesis subagent launch (Step 3.2), pass the Lorenzen config:
   ```
   Task(intersynth:synthesize-review):
     ...existing params...
     LORENZEN_CONFIG=$(cat interverse/interflux/config/flux-drive/discourse-lorenzen.yaml | python3 -c "import sys,yaml,json; print(json.dumps(yaml.safe_load(sys.stdin)['dialogue_game']))")
   ```
   If the config file doesn't exist or parsing fails, omit `LORENZEN_CONFIG` — synthesis proceeds without move validation.

2. After synthesis completes, optionally run the diagnostic script for standalone health output:
   ```bash
   bash interverse/interflux/scripts/discourse-health.sh "{OUTPUT_DIR}" 2>/dev/null || true
   ```
   This produces `discourse-health.json` as a convenience artifact. The canonical health data is in findings.json (written by synthesis in Task 4).

3. Append summary line from synthesis return value (which now includes discourse metrics).

**Depends on:** Task 3, Task 4

### Task 6: Update reaction.yaml with discourse reference

**File:** `interverse/interflux/config/flux-drive/reaction.yaml`
**Action:** Modify
**Description:** Add discourse section:

```yaml
# Discourse protocols (rsj.7)
discourse:
  sawyer: discourse-sawyer.yaml     # health monitoring (computed in synthesis)
  lorenzen: discourse-lorenzen.yaml  # move validation (passed to synthesis as LORENZEN_CONFIG)
  # Future: yes-and, conduction, pressing (Phase 2/3)
```

**Depends on:** Task 1

## Build Sequence

```
Task 1 (config files) ──┬─→ Task 2 (reaction prompt)
                         ├─→ Task 3 (diagnostic script)  ──→ Task 5 (wire into synthesis phase)
                         ├─→ Task 4 (synthesis agent)     ──→ Task 5
                         └─→ Task 6 (reaction.yaml ref)
```

Tasks 2, 3, 4, 6 can execute in parallel after Task 1.
Task 5 depends on both Task 3 and Task 4.

## Verification

1. `bash -n interverse/interflux/scripts/discourse-health.sh` — syntax check
2. `python3 -c "import yaml; yaml.safe_load(open('interverse/interflux/config/flux-drive/discourse-sawyer.yaml'))"` — YAML validity
3. `python3 -c "import yaml; yaml.safe_load(open('interverse/interflux/config/flux-drive/discourse-lorenzen.yaml'))"` — YAML validity
4. Grep for `Move Type` in reaction-prompt.md — output contract updated
5. Grep for `discourse_health` in synthesize-review.md — schema present in single-writer
6. Grep for `move_legality` in synthesize-review.md — validation wired
7. Grep for `LORENZEN_CONFIG` in synthesize-review.md — config passed as param, not file read
8. Grep for `move_type.*null` in synthesize-review.md — nil-safe path exists
9. Grep for `convergence_corrected` in synthesize-review.md — uses stemma-corrected values

## Review Findings Addressed

| Finding | Fix | Task |
|---------|-----|------|
| CDP-01 (P0): findings.json two-writer race | All discourse metrics computed inside synthesis agent; single writer | Task 4 |
| CDP-02 (P1): Missing nil-safe Move Type path | If Move Type absent → null, skip validation | Task 4 Step 3.7c |
| CDP-03 (P1): subsume_convergence_gate no-op | Set to false; deferred to Phase 2/3 | Task 1 |
| ARCH-02 (P1): Cross-boundary config read | Pass LORENZEN_CONFIG as JSON param, not file path | Task 4, Task 5 |
| ARCH-04 (P2): Health script re-derives synthesis data | Diagnostic only; canonical path is synthesis | Task 3, Task 4 |
| QUAL-03 (P2): discourse/ subdirectory breaks flat layout | Flat naming: discourse-sawyer.yaml, discourse-lorenzen.yaml | Task 1 |
| QUAL-04 (P2): Three tasks for one file | Consolidated into single Task 4 | Task 4 |
| CDP-05 (P2): novelty_rate ignores convergence_corrected | Uses convergence_corrected with fallback | Task 4 Step 6.6 |
| CDP-07 (P3): new_assertion vs new-assertion naming | Standardized on hyphens throughout | Task 1 |
