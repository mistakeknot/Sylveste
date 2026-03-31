---
date: 2026-03-31
reviewer: fd-architecture
bead: sylveste-rsj.7
input: docs/plans/2026-03-31-composable-discourse-protocols.md
---

# Architecture Review — Composable Discourse Protocols

### Findings Index

- P1 | ARCH-01 | "Task 3 / Task 6" | discourse_health split-ownership violates single-writer contract
- P1 | ARCH-02 | "Task 5 / Task 6" | Lorenzen config read crosses plugin boundary (interflux config read by intersynth agent)
- P2 | ARCH-03 | "Task 6" | findings.json populated across two execution phases with no merge step
- P2 | ARCH-04 | "Task 3" | discourse-health.sh re-derives metrics from findings.json that synthesis already computed
- P3 | ARCH-05 | "Task 1" | sawyer.yaml subsumes convergence gate without a canonical gate owner
- P3 | ARCH-06 | "Task 2" | Move Type field extends the reaction-prompt output contract asymmetrically

Verdict: needs-changes

---

## ARCH-01 — discourse_health split-ownership violates single-writer contract

**Severity:** P1
**Section:** Task 3 / Task 6

The plan places `discourse_analysis.lorenzen` in findings.json (written by the intersynth synthesis agent in Step 3.7c) and `discourse_health` in findings.json (written by the interflux orchestrator after running discourse-health.sh in Step 3.9). Task 6 acknowledges this directly: "The `discourse_health` block is populated by the orchestrator…not by the synthesis agent itself. The synthesis agent populates `discourse_analysis.lorenzen`…The orchestrator merges them when reading findings.json."

This creates a double-write to a single structured artifact with no defined merge contract:

1. intersynth:synthesize-review writes findings.json including `discourse_analysis.lorenzen`
2. The interflux orchestrator then runs discourse-health.sh and must re-open findings.json to inject `discourse_health`

The synthesize-review agent is haiku-class, writes findings.json atomically, and returns. The orchestrator then needs to patch a key into a file it did not write. There is no merge utility specified. The plan says "the orchestrator merges them" but the synthesize phase (synthesize.md Step 3.2) documents that "the host agent never touched any individual agent output file" — this is the existing architectural invariant. Patching findings.json from the orchestrator after synthesis breaks this invariant.

The existing codebase establishes findings.json as written exclusively by the synthesis subagent (synthesize-review.md Step 8, synthesize.md Step 3.4a — "the orchestrator generates this from the collected Findings Indexes"). The cost_report is injected into findings.json in Step 3.4b, but that happens within the orchestrator's own flow before synthesis writes the file. Here, the sequence is reversed: synthesis writes first, orchestrator patches second.

**Smallest fix:** Move discourse-health.sh execution inside the synthesis subagent, before Step 8 writes findings.json. The synthesis agent already has OUTPUT_DIR and already reads all agent files. Pass `SAWYER_CONFIG` as an optional parameter. The orchestrator reads discourse_health from findings.json exactly as it reads every other field. This restores single-writer semantics.

If there is a reason discourse-health must run post-synthesis (e.g., it needs the deduplicated findings.json as input rather than raw agent files), then the plan needs an explicit merge protocol: specify whether the orchestrator uses `jq` to patch the file, writes a sidecar, or some other mechanism. The current plan leaves this as implementation-defined, which will cause inconsistency across executor implementations.

---

## ARCH-02 — Lorenzen config read crosses plugin boundary

**Severity:** P1
**Section:** Task 5 / Task 6

Task 5 adds Step 3.7c to `interverse/intersynth/agents/synthesize-review.md`. That step reads `lorenzen.yaml` (Task 1 places it at `interverse/interflux/config/flux-drive/discourse/lorenzen.yaml`) and applies validation rules from it. This means the intersynth synthesis agent now has a runtime dependency on interflux config.

The existing architecture is clear: intersynth is a companion plugin to interflux; interflux orchestrates intersynth by passing parameters. intersynth's input contract (its "## Input Contract" section) is a closed list of named parameters: `OUTPUT_DIR`, `VERDICT_LIB`, `CONTEXT`, `MODE`, `PROTECTED_PATHS`, `FINDINGS_TIMELINE`. intersynth does not read interflux config directories.

Introducing a config-file read from a sibling plugin's directory creates a lateral dependency that is currently absent from the codebase. This affects:

- **Portability:** synthesize-review is used by other callers (Clavain quality-gates, review mode). Those callers do not ship lorenzen.yaml.
- **Testability:** Unit-testing synthesize-review now requires the interflux config tree to be present.
- **Coupling:** A YAML key name change in interflux's discourse config silently breaks intersynth behavior.

Task 8 adds a `discourse` key to `reaction.yaml`, which is already passed (implicitly) through the interflux orchestration context. The correct seam is: the interflux orchestrator reads lorenzen.yaml and passes the relevant values as parameters to synthesize-review, the same way it passes FINDINGS_TIMELINE. intersynth applies the rules it receives; it does not resolve config paths.

**Smallest fix:** Add `LORENZEN_CONFIG` as an optional input parameter to synthesize-review's Input Contract. The orchestrator reads lorenzen.yaml and serializes the validation rules inline (or passes the YAML path). synthesize-review uses whatever it receives. If the parameter is absent, Step 3.7c is skipped. This keeps intersynth's boundary closed to interflux's filesystem layout.

---

## ARCH-03 — findings.json populated across two execution phases with no merge step

**Severity:** P2
**Section:** Task 6

Related to ARCH-01 but distinct: the plan defines `discourse_health` and `discourse_analysis` as siblings in findings.json, both at the top level. However, they are written by different processes at different times:

- `discourse_analysis.lorenzen` — written during synthesis (Step 3.7c), before findings.json is finalized
- `discourse_health` — written after synthesis, by discourse-health.sh, then merged by the orchestrator

The findings.json schema defined in Task 6 shows both blocks as co-present in the final output, but no step in the plan describes the merge operation. The verification checklist (step 5: "Grep for `discourse_health` in synthesize-review.md") only checks that the schema field is declared, not that the orchestrator actually merges it.

This is a schema-level promise without an implementation-level guarantee. A downstream consumer reading findings.json will observe either: (a) `discourse_health` is missing if the orchestrator skips the merge, or (b) `discourse_health` is present but `discourse_analysis.lorenzen` is missing if synthesis failed mid-step.

**Smallest fix:** Require Task 6 to specify the merge mechanism explicitly — either a `jq` one-liner in synthesize.md Step 3.9, or a shell function in discourse-health.sh that reads the existing findings.json and emits a merged file. Ensure the verification checklist tests for field presence in the actual output, not just in the schema declaration.

---

## ARCH-04 — discourse-health.sh re-derives metrics already available from synthesis

**Severity:** P2
**Section:** Task 3

The plan specifies that discourse-health.sh reads `findings.json` to compute participation Gini, novelty rate, and response relevance. These are post-hoc metrics over the same agent output data that synthesize-review already processed in Steps 3 through 6.5. Specifically:

- **Participation Gini** counts findings per agent. synthesize-review builds per-agent finding lists in Step 3 and Step 5.
- **Novelty rate** uses `convergence == 1` findings. synthesize-review computes `convergence` for every finding in Step 6.
- **Response relevance** counts findings with file:line evidence. synthesize-review parses Evidence fields in Steps 3.7 and 3.7b.

The shell script re-parses findings.json to re-derive information that synthesis already computed and could have emitted directly. This introduces a second parsing pass of the same data, creates a dependency on the findings.json serialization format (if the schema changes, discourse-health.sh must be updated independently), and adds a runtime Bash dependency on the synthesis output being present and well-formed before the health check can run.

If the health metrics were computed inside synthesis (where the raw data is already available), no separate script is needed. The `discourse_health` block could be emitted as part of the same Step 8 write, alongside `sycophancy_analysis`, `hearsay_analysis`, and `stemma_analysis` — all of which follow exactly this pattern.

**Smallest fix:** Compute Gini, novelty rate, and relevance proxy inside synthesize-review.md Step 3.8 (after sycophancy scoring, where per-agent and per-finding data is already loaded). Emit as `discourse_health` in Step 8. Retire discourse-health.sh as a standalone script; preserve sawyer.yaml threshold reads inside the synthesis agent. This removes the re-parse pass and keeps all metrics computation within the single synthesis execution boundary.

---

## ARCH-05 — sawyer.yaml subsumes convergence gate without a clear canonical owner

**Severity:** P3
**Section:** Task 1

sawyer.yaml includes `subsume_convergence_gate: true`, which means "when sawyer is enabled, the convergence check in reaction.yaml becomes one of sawyer's health checks." The convergence gate is currently owned by the reaction phase (reaction.md Step 2.5.0), and its threshold (`skip_if_convergence_above: 0.6`) lives in reaction.yaml.

The plan does not update reaction.md or reaction.yaml to reflect this subsumption. If sawyer is enabled and `subsume_convergence_gate: true`, does the Phase 2.5.0 convergence gate still execute independently? Does it short-circuit to sawyer's evaluation? The plan is silent on this control-flow question.

Without an explicit answer, implementors will either: run the convergence gate twice (once in reaction.md Step 2.5.0 under its old logic, once inside sawyer's health checks), or leave the gate unreachable in sawyer's domain while the reaction phase continues to run it independently. The first leads to conflicting gate decisions; the second makes `subsume_convergence_gate: true` a dead config key.

**Smallest fix:** Either remove `subsume_convergence_gate` from the initial plan and scope it as a Phase 2/3 extension (the comment at the bottom of reaction.yaml already alludes to future phases), or add a task that modifies reaction.md Step 2.5.0 to check for the sawyer subsumption flag and delegate accordingly. The current plan leaves a live config key with no corresponding runtime behavior.

---

## ARCH-06 — Move Type field extends the output contract asymmetrically

**Severity:** P3
**Section:** Task 2

Task 2 adds a `Move Type` field to the reaction-prompt.md output format. The reaction round produces `.reactions.md` files that are parsed by synthesize-review.md Step 3.7. Step 3.7 currently extracts: Finding ID, Stance, Independent Coverage, Rationale, Evidence, Verdict, and Reactive Additions.

The plan adds `Move Type` to the output template but does not update Step 3.7's parse logic to extract it. Task 5 (Step 3.7c) uses `Move Type` for legality validation, which implies the parse must capture it. But the parse step is defined in intersynth, and updating it is not listed as a task — it falls implicitly inside "Task 5: Add Lorenzen move validation to synthesis agent."

This is a minor sequencing gap rather than a blocking issue, but it means the parse contract and the validation contract are being updated in the same task, which makes Task 5's scope wider than its title suggests and its verification criteria incomplete. The verification checklist only checks for `move_legality` in synthesize-review.md — it does not verify the parse path from the `.reactions.md` file format to the Step 3.7c input.

**Smallest fix:** Split Task 5's work into two explicitly named sub-steps: (a) extend Step 3.7 parse to capture `Move Type` from `.reactions.md`, and (b) implement Step 3.7c validation using the parsed value. The verification checklist should add a grep confirming `Move Type` is extracted in Step 3.7 before being validated in Step 3.7c.

---

## Summary

The plan's core architectural question — is the discourse_health/discourse_analysis split clean or problematic — has a clear answer: it is problematic as specified. The split creates a double-write to findings.json with no defined merge protocol, and forces post-synthesis computation of metrics that synthesis already has the data to produce. The Lorenzen config boundary crossing (ARCH-02) compounds this by giving intersynth a filesystem dependency on interflux that no other step in the pipeline has.

The simplest path to a clean design: bring all discourse metrics computation into the synthesis subagent, pass lorenzen configuration as an input parameter, and emit all discourse fields in the single Step 8 write. discourse-health.sh can be retained as a standalone diagnostic utility (callable independently of a review run), but should not be the canonical path for populating findings.json.

ARCH-03 through ARCH-06 are implementable as-is but each leaves a precision gap that will surface during implementation or downstream consumption. They are worth resolving in the plan before executing.

**Verdict: needs-changes** — two P1 boundary issues require plan revision before implementation. P2 and P3 findings can be addressed during implementation with low risk.
