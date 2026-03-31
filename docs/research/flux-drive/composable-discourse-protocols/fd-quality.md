---
date: 2026-03-31
reviewer: fd-quality
bead: sylveste-rsj.7
plan: docs/plans/2026-03-31-composable-discourse-protocols.md
---

# Quality Review — Composable Discourse Protocols

### Findings Index

- P1 | QUAL-01 | "Task 3 / Task 4" | discourse-health.sh placement is cross-module: shell script in interflux reads config and writes to intersynth's output contract
- P1 | QUAL-02 | "Task 6" | findings.json schema split across two owners with no merge protocol
- P2 | QUAL-03 | "Task 1" | discourse/ subdirectory breaks the flat config layout convention
- P2 | QUAL-04 | "Tasks 5, 6, 7" | Three sequential tasks that modify the same file should be one task
- P2 | QUAL-05 | "Task 3" | discourse-health.sh naming inconsistent with existing script conventions
- P2 | QUAL-06 | "Task 4 / synthesize.md" | Step 3.9 placement creates unreachable numbering relative to synthesize.md
- P3 | QUAL-07 | "Task 1 / reaction.yaml" | YAML config style: inline flow-block mix in sawyer.yaml differs from reaction.yaml style
- IMP | QUAL-08 | "Task 3" | Gini coefficient implemented as jq arithmetic in bash — fragile for edge cases

---

## QUAL-01 (P1) — discourse-health.sh placement is cross-module

**Section:** Task 3 / Task 4

The plan places `discourse-health.sh` in `interverse/interflux/scripts/` and has it run from `synthesize.md` (which lives in interflux's `skills/` directory). However, the script reads `sawyer.yaml` from `interflux/config/` and writes `discourse-health.json` into `OUTPUT_DIR` — an output owned by the synthesis phase in intersynth.

The concern is ownership: findings.json is intersynth's output contract. Having an interflux script produce a sidecar file (`discourse-health.json`) that gets merged back into findings.json by "the orchestrator" (Task 6 language: "populated by the orchestrator after running discourse-health.sh") creates an implicit merge step with no specified executor. The plan says the synthesis agent populates `discourse_analysis.lorenzen` and the orchestrator merges in `discourse_health`, but synthesize.md's Step 8 is the canonical findings.json writer — not the orchestrator.

**Concrete risk:** If the orchestrator runs discourse-health.sh after the synthesis subagent has already written findings.json, the merge requires the orchestrator to read findings.json, parse it, inject the `discourse_health` block, and re-write it. That is a write-conflict pattern that findings-helper.sh was designed to avoid. There is no merge utility specified in the plan.

**Fix:** Either (a) move the health computation into the synthesis subagent itself (it already has findings.json open and can compute simple metrics from the in-memory data), or (b) have discourse-health.sh write a separate `discourse-health.json` that the human/orchestrator reads separately — not merged into findings.json. Option (a) is cleaner and avoids the cross-module dependency.

---

## QUAL-02 (P1) — findings.json schema split across two owners with no merge protocol

**Section:** Task 6

Task 5 says synthesize-review.md populates `discourse_analysis.lorenzen`. Task 6 says the orchestrator populates `discourse_health`. Both blocks are shown as peers in the same findings.json schema. The merge is described only in prose: "The orchestrator merges them when reading findings.json."

This is an implicit contract with no implementation path. The existing findings.json write path is: intersynth writes the file (synthesize-review.md Step 8), then the orchestrator reads it for reporting. The orchestrator does not currently re-write findings.json — it consumes it read-only.

Without a specified merge step, one of two bad outcomes is likely: the orchestrator never writes the `discourse_health` block (silent omission), or it overwrites the file without preserving `discourse_analysis.lorenzen` (data loss).

**Fix:** Make one agent own the full findings.json write for discourse fields. The simplest path is to have discourse-health.sh output a standalone JSON file and have the synthesis agent read it as an optional input (similar to how it reads FINDINGS_TIMELINE). The synthesis agent can then write all discourse fields in its single Step 8 write.

---

## QUAL-03 (P2) — discourse/ subdirectory breaks the flat config layout convention

**Section:** Task 1

The existing `config/flux-drive/` directory is flat: `reaction.yaml`, `agent-roles.yaml`, `budget.yaml`, `reaction-prompt.md`, plus the `domains/` and `knowledge/` subdirectories. Subdirectories in this layout have a clear semantic: `domains/` groups domain-profile markdown files (one per domain), `knowledge/` groups knowledge entry markdown files (one per pattern). Each subdirectory holds a homogeneous file type.

The proposed `discourse/` subdirectory holds two YAML configuration files that are structurally more similar to `reaction.yaml` and `budget.yaml` than to anything in `domains/` or `knowledge/`. The grouping signals "discourse is a subsystem with its own directory" but the current layout signals "top-level config files live flat, grouped collections get subdirectories."

A stronger fit: place `sawyer.yaml` and `lorenzen.yaml` flat in `config/flux-drive/` alongside `reaction.yaml`. Task 8 already adds a `discourse:` section to `reaction.yaml` that references these files — if they are flat siblings, the reference paths would be `sawyer.yaml` and `lorenzen.yaml`, which is simpler and consistent with how `sycophancy_detection` and `hearsay_detection` are co-located in `reaction.yaml` today.

**Alternative:** If future growth (yes-and, conduction, pressing) will produce many discourse protocol files, a `discourse/` subdirectory is defensible. The plan mentions this expansion explicitly. If Phase 2/3 are planned concretely, the subdirectory is reasonable; if they are speculative, start flat and add the subdirectory when you have three or more files.

---

## QUAL-04 (P2) — Three sequential tasks modifying the same file should be one task

**Section:** Tasks 5, 6, 7

Tasks 5, 6, and 7 all modify `interverse/intersynth/agents/synthesize-review.md`. The plan notes this explicitly ("same file as Task 5 and 6") and the build sequence shows them executing sequentially. Splitting logically-coupled edits to one file across three tasks creates two problems:

1. The dependency chain forces sequential execution of what is conceptually one change set. The build DAG shows Task 6 depending on both Task 3 and Task 5, and Task 7 depending on Task 5. Any implementer must serialize these manually.
2. Three separate edit passes on one file are more likely to produce conflicts or partial states if any pass fails mid-execution. A single task with three described changes is easier to roll back.

The content of Tasks 5, 6, and 7 are: move validation logic (Step 3.7c), schema extension (Step 8), and report section (synthesis.md Discourse Quality section). These are naturally described together as "extend synthesize-review.md to support discourse protocols."

**Fix:** Merge Tasks 5, 6, and 7 into a single task: "Extend synthesize-review.md for discourse protocols." List the three changes as numbered sub-items within that task. The build dependency becomes: Task 1 + Task 2 → Task 5 (merged). This also removes the ambiguity in Task 6's description ("populated by the orchestrator after running discourse-health.sh") which conflicts with the synthesis agent ownership described in QUAL-02 above.

---

## QUAL-05 (P2) — Script naming inconsistent with existing conventions

**Section:** Task 3

Existing scripts in `interverse/interflux/scripts/` follow a verb-noun or noun-noun pattern keyed on their primary domain: `findings-helper.sh` (domain: findings), `validate-roster.sh` (domain: roster validation), `estimate-costs.sh` (domain: cost estimation), `flux-watch.sh` (domain: flux monitoring).

The proposed name `discourse-health.sh` uses a noun-adjective pattern ("discourse" + "health") where "health" describes the output type, not the action. More consistent alternatives:

- `compute-discourse-health.sh` — matches `estimate-costs.sh` verb-noun pattern
- `discourse-metrics.sh` — parallel to the output key `discourse_health` in findings.json; keeps it noun-noun like `findings-helper.sh`

Either is more consistent than the current proposal. `findings-helper.sh` itself is a slight outlier (helper is vague), but the verb-object pattern in `estimate-costs.sh` and `validate-roster.sh` is the clearer precedent for new scripts.

---

## QUAL-06 (P2) — Step 3.9 placement creates unreachable numbering in synthesize.md

**Section:** Task 4 / synthesize.md

The plan adds Step 3.9 (Discourse Health Assessment) to `synthesize.md` (the orchestrator phase file, not the synthesis agent). However, the existing step sequence in `synthesize.md` after Step 3.2 is: 3.3 (synthesis subagent), 3.4 (update document), 3.4a (generate findings.json), 3.4b (cost report), 3.4c (record tokens), 3.5-research, 3.5 (report to user), 3.6 (create beads), 3.7 (clean up temp files).

Step 3.9 runs "after synthesis completes and findings.json exists." The natural insertion point is after Step 3.2 returns (synthesis subagent done) and before Step 3.4a (findings.json generation) — or after Step 3.4a if it reads the already-written file. But the plan describes it as a new "Step 3.9" which numerically follows 3.7 (cleanup). In the current file, 3.7 is the cleanup step and the research-mode 3.7 is the temp-file removal. Adding a Step 3.9 after cleanup suggests health runs after cleanup, which is backwards — cleanup should come last.

The confusion arises because the plan also says synthesize.md (the phase file) has "Step 3.2" as the synthesis subagent delegation, but the plan's Task 4 description says to add Step 3.9 "after Step 3.2 completes." If the intent is "insert after 3.2, before 3.3," the step number should be 3.2a or 3.2b. If the intent is "run after the entire synthesis phase," the numbering 3.9 is more defensible but conflicts with 3.7 being cleanup.

**Fix:** Clarify the insertion point in Task 4. If discourse health runs after synthesis but before user reporting, insert it as Step 3.2a (after subagent returns, before Step 3.3). If it runs after reporting as a parallel/background step, label it explicitly as such (similar to the Post-Synthesis Compounding section, which is unlabeled and post-3.7).

---

## QUAL-07 (P3) — YAML style: inline flow-block mix in sawyer.yaml diverges from reaction.yaml

**Section:** Task 1

`reaction.yaml` uses exclusively block-style YAML throughout — no flow-style mappings. The proposed `sawyer.yaml` mixes block style at the top level with inline flow-style mappings for the `states` values:

```yaml
states:
  healthy: { gini_below: 0.3, novelty_above: 0.1, relevance_above: 0.7 }
  degraded: { gini_below: 0.5, novelty_above: 0.05, relevance_above: 0.5 }
```

This is valid YAML and `yaml.safe_load` will parse it, but it is inconsistent with the surrounding files. A block-style equivalent:

```yaml
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

Similarly, `lorenzen.yaml`'s `legality_scoring` block is consistent block-style — making `sawyer.yaml` match would be a minor consistency improvement.

---

## QUAL-08 (IMP) — Gini coefficient in bash is fragile for edge cases

**Section:** Task 3

The plan specifies computing the Gini coefficient in `discourse-health.sh` via counting findings per agent and computing the index in bash/jq. Gini computation requires sorting, computing cumulative sums, and dividing — this is achievable in jq but produces opaque arithmetic that is hard to validate and maintain.

The specific edge cases to consider: single agent (Gini = 0 by definition, which should be "healthy"), zero findings (division by zero in the formula), and all agents producing exactly one finding each (perfectly equal, Gini = 0).

The plan does not address these. `findings-helper.sh` uses jq for JSON manipulation but delegates to bash arithmetic only for simple operations. For a metric with multiple edge cases, a 10-line Python fallback (jq has no built-in sort-and-sum pipeline for this use) is more maintainable than a bash-arithmetic implementation.

If the script already has a Python dependency (for YAML parsing of `sawyer.yaml`), the Gini computation should be in that Python block rather than in a separate jq pipeline.

---

## Verdict

**Conditional — two P1 issues require resolution before implementation.**

QUAL-01 and QUAL-02 are the same underlying problem: the plan splits ownership of findings.json between the synthesis subagent and the orchestrator without a specified merge mechanism. The merge is described but not designed. This will produce either silent data loss or a write-conflict at runtime.

The structural fix is to route `discourse-health.sh` output as an input to the synthesis subagent (like FINDINGS_TIMELINE) so the subagent owns the complete findings.json write. This also eliminates the ambiguity in Task 6's "populated by the orchestrator" description.

QUAL-03 through QUAL-07 are addressable during implementation without requiring plan revision. QUAL-04 (merge Tasks 5-7) would improve plan clarity but does not affect correctness.
