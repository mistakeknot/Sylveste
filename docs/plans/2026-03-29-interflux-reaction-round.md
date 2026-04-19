---
bead: sylveste-rsj.2
date: 2026-03-29
type: plan
reviewed: true
review-method: flux-review (3-track, 13 agents)
review-verdict: needs-changes (2 P0, 12 P1 — all addressed below)
---

# Interflux Reaction Round — Implementation Plan (v2, post-review)

## Overview

Add Phase 2.5 (reaction round) to flux-drive's orchestration pipeline. 6 files to create/modify across interflux and intersynth.

**Review findings incorporated:** 2 P0s (anchoring bias in prompt, missing synthesis weighting schema), 12 P1s consolidated into task updates below. See review synthesis at end of document.

## Tasks

### Task 1: Create reaction phase file
**File:** `interverse/interflux/skills/flux-drive/phases/reaction.md`
**Action:** Create new file
**Description:** Phase 2.5 instructions:
1. **Convergence gate:** Count P0/P1 overlap from Phase 2 agents. If >60% already agree (existing dedup logic), skip reaction round — secondary processing adds noise on homogeneous substrate. [RR-01]
2. **Cleanup:** Delete stale `*.reactions.md` files from OUTPUT_DIR before dispatching. [SCHED-02]
3. **Collect Findings Indexes** from each `{agent-name}.md` (first ~30 lines).
4. **Build per-agent reaction prompts** using `config/flux-drive/reaction-prompt.md` template.
5. **Dispatch** as parallel Task calls (sonnet model, `run_in_background: true`).
6. **Timeout contract:** Each agent must write `{agent-name}.reactions.md` or `{agent-name}.reactions.error.md` within the Phase 2 per-agent timeout. Proceed to Phase 3 with whatever files exist after timeout. [SCHED-01]
7. **Report:** N agents reacted, M reactions produced, K empty (no relevant findings).
**Depends on:** Nothing

### Task 2: Add `read-indexes` to findings-helper.sh
**File:** `interverse/interflux/scripts/findings-helper.sh`
**Action:** Add `read-indexes` subcommand
**Description:** Extract Findings Index (between `### Findings Index` and next `###` or end) from each agent `.md` file in a directory. Output as structured text. Also add `--format indexes` flag to existing `read` subcommand as alternative interface.
**Depends on:** Nothing

### Task 3: Create reaction prompt template
**File:** `interverse/interflux/config/flux-drive/reaction-prompt.md`
**Action:** Create new file (note: path corrected to `config/flux-drive/` directory, not `config/`) [PLUG-02]
**Description:** Template with these slots and features:
- `{agent_name}`, `{agent_description}`, `{own_findings_index}`, `{peer_findings}`, `{output_path}`
- **Anti-anchoring framing:** "Your peers reported the following claims" (NOT "discovered") [MCC-01 P0]
- **Own findings injection:** Agent receives its own Findings Index for self-comparison [PROMPT-01]
- **Finding ID requirement:** Each reaction must reference the specific finding ID from the peer's Findings Index [SYNTH-02]
- **Independent coverage field:** `independent_coverage: yes|partial|no` — did the agent independently find this? [MCC-02]
- **Evidence reference field:** Optional but prompted — cite file:line, spec, or own finding [EFC-01]
- **Volume cap:** React to at most 3 peer findings (most divergent from own analysis) [RR-02]
- **Asymmetry gate:** Only react if: (a) finding contradicts own finding, (b) finding falls in own named domain, or (c) finding reveals something in own domain that was missed [RR-04]
- **P2 inclusion (light):** Show P2 findings but only ask for single-sentence severity assessment, not full reaction [APR-02]
- **Structured output format contract:** [PROMPT-02]
  ```
  ### Reactions
  - **Finding**: [Finding ID]
    - **Stance**: agree | partially-agree | disagree | missed-this
    - **Independent Coverage**: yes | partial | no
    - **Rationale**: [1-2 sentences]
    - **Evidence**: [file:line or spec reference, if applicable]

  ## Reactive Additions
  [New findings discovered via peer context, marked with provenance: reactive]

  ### Verdict
  no-concerns | confirms-findings | adds-evidence | contradicts-findings
  ```
**Depends on:** Nothing

### Task 4: Wire reaction phase into SKILL.md
**File:** `interverse/interflux/skills/flux-drive/SKILL.md`
**Action:** Modify
**Description:** After Phase 2 completion, add one-line redirect: `## Phase 2.5: Reaction Round\nRead phases/reaction.md now.` No inline config logic — the phase file handles its own enable/disable gate. [PLUG-01]
**Depends on:** Task 1

### Task 5: Modify synthesis agent to read reactions
**File:** `interverse/intersynth/agents/synthesize-review.md`
**Action:** Modify
**Description:**
1. **Exclusion:** Add `*.reactions.md` to the Step 1 discovery glob exclusion list (alongside `summary.md`, `synthesis.md`, `findings.json`). This prevents `.reactions.md` files from being parsed as agent output files. [SYNTH-01 P1 — without this, synthesis is corrupted]
2. **Reaction ingestion:** After reading `.md` files, separately read `.reactions.md` files. Parse structured format (Finding ID → stance → rationale → evidence).
3. **Finding annotation:** For each reaction, annotate the corresponding finding (matched by Finding ID) with `reactions: [{agent, stance, independent_coverage, rationale}]`.
4. **Weighting schema (conductor score):** [RR-03 P0]
   - Convergent reactions (>50% agree): confidence boost only, **severity unchanged**
   - Divergent reactions (any disagree): flag as `verdict: contested`, require synthesis note on why final severity was chosen
   - Extension reactions (agent adds missed item): treat as new finding with `provenance: reactive`, route through normal dedup. Reactive additions get a provenance discount in convergence scoring. [EFC-02]
   - **Reactions cannot promote severity tier** (P2 cannot become P1 because 3 agents agreed)
   - Domain-peer disputes (same domain) → `verdict: needs-human-review`. Domain-outsider disputes → lower confidence, don't suppress. [ADR-01]
5. **Output sections:** Add `## Contested Findings` (P0/P1 with net disagreement) before main findings, and `## Reaction Analysis` (convergence summary, 5-line max). [ADR-02]
**Depends on:** Task 1

### Task 6: Add config toggle
**File:** `interverse/interflux/config/flux-drive/reaction.yaml` (new file in existing directory) [PLUG-02 — path corrected]
**Action:** Create
**Description:**
```yaml
reaction_round:
  enabled: true
  model: sonnet
  severity_filter: ["P0", "P1"]
  severity_filter_p2_light: true  # show P2 for single-sentence severity check
  max_reactions_per_agent: 3
  skip_if_convergence_above: 0.6
  timeout_seconds: 60
  # Disabled by default for quality-gates mode (speed > depth)
  mode_overrides:
    quality-gates: false
    review: true
    flux-drive: true
```
**Depends on:** Nothing

## Execution Order

Tasks 1, 2, 3, 6 are independent — execute in parallel.
Task 4 depends on Task 1.
Task 5 depends on Task 1.

```
Parallel: [Task 1] [Task 2] [Task 3] [Task 6]
    ↓
Sequential: [Task 4] [Task 5]
```

## Testing

- Run a flux-drive review on a recent diff with reaction round enabled
- Verify: `.reactions.md` files produced for each agent with structured format
- Verify: synthesis output includes "Reaction Analysis" and "Contested Findings" sections
- Verify: synthesis excludes `.reactions.md` from agent discovery glob
- Verify: config toggle `enabled: false` skips reaction round
- Verify: convergence gate skips reaction when >60% P0/P1 overlap
- Verify: reactions reference finding IDs (not free-form)
- Verify: cost overhead <5% for large reviews, <15% for small plan reviews

## Review Findings Incorporated

### P0 (addressed)
- **MCC-01** (Track B, medical case conference): Anchoring bias in prompt framing → fixed in Task 3 ("reported claims" not "discovered") + `independent_coverage` field
- **RR-03** (Track C, orchestral rehearsal): Missing synthesis weighting schema → fixed in Task 5 (conductor score with 4 explicit rules)

### P1 (addressed, by task)
- Task 1: SCHED-01 (timeout), SCHED-02 (stale cleanup), RR-01 (convergence gate)
- Task 3: SYNTH-02 (finding-ID), APR-02 (P2 light inclusion), MCC-02 (independent_coverage), EFC-01 (evidence ref), RR-02 (volume cap), RR-04 (asymmetry gate), PROMPT-02 (output format)
- Task 5: SYNTH-01 (glob exclusion), ADR-01 (conflict resolution)

### P2 (captured for execution)
- PLUG-02: config path fixed
- PROMPT-01: own findings injection added
- TOKEN-01: cost claim scoped
- All others noted as improvements to implement during execution
