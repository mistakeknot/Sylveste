### Findings Index

- P1 | ARCH-01 | "Step 2.5.3-4" | Completion-signaling contract not applied to reaction agents
- P1 | ARCH-02 | "Step 2.5.0" | Peer-priming discount requires timestamp-level ordering not guaranteed by findings-helper.sh
- P1 | ARCH-03 | "Step 2.5.5" | session_id not acquired before interspect emission call
- P2 | ARCH-04 | "Step 2.5.3-4" | max_reactions_per_agent config key unused by spec
- P2 | ARCH-05 | "Step 2.5.3-4" | {agent_description} template variable has no resolution path
- P2 | ARCH-06 | "Step 2.5.0" | mode_overrides applied in config but not checked in spec prose

Verdict: needs-changes

### Summary

The reaction round spec (Phase 2.5) is architecturally coherent and well-sequenced for its core purpose: convergence gating, topology-aware peer visibility, fixative injection, and parallel reaction dispatch. The sequencing constraint at Step 2.5.2b is correct and necessary. The main structural gaps are a missing completion-wait step for reaction agents (the spec dispatches in background but provides no monitoring or partial-file retry logic equivalent to Phase 2's flux-watch pattern), a peer-priming discount that depends on sub-second timestamp ordering not enforced by the underlying JSONL writer, and a missing session_id acquisition step before the interspect emission calls. These are integration-layer gaps, not design errors — the design intent is sound.

### Issues Found

1. P1 | ARCH-01 | Completion-signaling contract not applied to reaction agents

Phase 2 launch establishes a well-specified completion contract: agents write to `.md.partial`, rename to `.md`, the orchestrator monitors via `flux-watch.sh`, retries once on partial-only files, and writes error stubs on failure. Step 2.5.3-4 dispatches reaction agents with `run_in_background: true` and a 60-second timeout but specifies no equivalent wait step. The spec says output lands in `{agent-name}.reactions.md` or `.reactions.error.md` but gives no instruction for: (a) monitoring via flux-watch or polling, (b) handling `.partial` files that exist at collection time, (c) the retry-once pattern from Phase 2. The Step 2.5.5 report counts `reactions_produced`, `reactions_empty`, and `reactions_errors` — implying the orchestrator must have already collected and classified all agent outputs — but the collection logic is not specified anywhere in Phase 2.5. The synthesis phase detects the reaction round completed by checking for `.reactions.md` files (synthesize.md Step 3.4d), which means silent partial-completion goes undetected.

Smallest viable fix: Add a Step 2.5.4a between dispatch and reporting. Specify: monitor via `flux-watch.sh {OUTPUT_DIR} {N} {timeout_seconds * 1000}` for reaction files (using a pattern filter or a separate count target). After timeout, collect `*.reactions.md` (produced), files with `Verdict: no-concerns` (empty), and `*.reactions.error.md` plus missing outputs (errors). Apply the same partial-file retry once from Phase 2. Optionally note that `.reactions.md.partial` files should follow the same `.partial` sentinel contract.

2. P1 | ARCH-02 | Peer-priming discount requires timestamp ordering not guaranteed by findings-helper.sh

Step 2.5.0 describes the peer-priming discount: "check if the first report timestamp in peer-findings.jsonl precedes a second agent's Findings Index entry." The discount logic requires attributing a specific timestamp to each Findings Index entry so the comparison `peer_findings.jsonl timestamp < agent_findings_index entry timestamp` is meaningful. However, `findings-helper.sh convergence` reads normalized titles from Findings Index markdown blocks — there are no timestamps in the Findings Index format (defined in `contracts/findings-index.md` and `shared-contracts.md`). The convergence function in `findings-helper.sh` has no timestamp-handling code whatsoever. The peer-priming discount as described relies on an ordering guarantee that the existing infrastructure does not implement.

Additionally, the convergence computation in `findings-helper.sh` does not apply this discount — it counts raw overlap by normalized title across agents. Implementing the discount in the shell script would require either: (a) timestamps embedded in Findings Index entries (a format change), or (b) cross-referencing agent output timestamps against `peer-findings.jsonl` write times using filesystem metadata (fragile, race-prone). The discount intent (avoid penalizing genuine shared discovery by deducting peer-primed confirmations from overlap) is architecturally correct, but the implementation path is unspecified.

Smallest viable fix: Either (a) document the discount as a future enhancement and remove the specification prose from Step 2.5.0 until the implementation path is defined, or (b) define the discount operationally: an overlap finding is peer-primed if its normalized title appears in `peer-findings.jsonl` AND at least one agent's Findings Index was written after the peer-findings entry (using file mtime of agent `.md` vs `peer-findings.jsonl` mtime — coarse but implementable). Whichever path is chosen, update `findings-helper.sh convergence` to implement it.

3. P1 | ARCH-03 | session_id not acquired before interspect emission call

`_interspect_emit_reaction_dispatched()` in `lib-interspect.sh` has `$1=session_id` as a required positional argument with `${1:?session_id required}` enforcement. The reaction spec (Step 2.5.0 and Step 2.5.5) calls this function but never specifies where `session_id` is acquired. The synthesize phase has the same gap. Other flux-drive phases also omit this — the launch phase references `lib-interspect.sh` functions at Step 2.1d but session_id acquisition is not in the launch spec either. For reaction specifically, this is a P1 because the skip-path emission at Step 2.5.0 is an early-exit path where the orchestrator may not have initialized the interspect library yet.

Smallest viable fix: Add a one-line callout in Step 2.5.0 before the first emission: "Acquire session_id: `source lib-interspect.sh && session_id=$(_interspect_session_id)` or use `$CLAUDE_SESSION_ID` if set." The shared-contracts or a new Phase 2.5 preamble section is the right place for this pattern, since it applies to all interspect-emitting phases.

4. P2 | ARCH-04 | max_reactions_per_agent config key unused by spec

`reaction.yaml` defines `max_reactions_per_agent: 3`. The reaction-prompt.md template hardcodes "at most 3" in the agent instruction ("React to at most 3 peer findings"). These two are currently in sync, but the spec at Step 2.5.3-4 never reads `max_reactions_per_agent` from config when filling the prompt template — it treats the limit as a prompt-side invariant. If an operator changes `max_reactions_per_agent` in config, the prompt template is not updated, and the config key becomes dead. This is a minor coupling issue: the limit is load-bearing for convergence scoring (hearsay weighting depends on how many reactions an agent produces) but is duplicated between config and template.

Smallest viable fix: In Step 2.5.3-4, when building the reaction prompt, substitute `{max_reactions}` from `config.max_reactions_per_agent` into the template alongside the other template variables. Update `reaction-prompt.md` to use `{max_reactions}` instead of the hardcoded "3".

5. P2 | ARCH-05 | {agent_description} template variable has no resolution path

The reaction-prompt.md template opens with `You are **{agent_name}** ({agent_description}).`. Step 2.5.3-4 lists the template variables filled by the orchestrator: `{agent_name}`, `{own_findings_index}`, `{peer_findings}`, `{fixative_context}`, `{output_path}`. The variable `{agent_description}` is absent from this list and from every other spec file. There is no documented source for agent description strings (agent markdown files have varying structures; `agent-roles.yaml` has a `description` per role, not per agent). The variable either silently resolves to an empty string (leaving a dangling parenthetical in the prompt) or causes a substitution error depending on implementation.

Smallest viable fix: Add `{agent_description}` to the template variable list in Step 2.5.3-4 with its source: "read the first sentence of the agent's `.md` file header, or fall back to the role description from `agent-roles.yaml`." Alternatively, remove the parenthetical from `reaction-prompt.md` if agent self-identification via `{agent_name}` alone is sufficient — the agents already carry domain knowledge from their initial review.

6. P2 | ARCH-06 | mode_overrides applied in config but not checked in spec prose

`reaction.yaml` defines `mode_overrides: { quality-gates: false, review: true, flux-drive: true }`. The spec opening states: "skip entirely in research mode." This covers one mode, but the config implies a finer-grained gate (quality-gates mode also skips). Phase 2.5 spec prose has no equivalent of the `[review only]` / `[research only]` markers used in Phase 3 (synthesize.md). The quality-gates mode skip is load-bearing for performance (documented inline as "speed > depth") but is invisible in the spec. An implementer reading only the spec prose would implement the reaction round in quality-gates mode.

Smallest viable fix: Add a mode check at the top of Phase 2.5, after the `reaction_round.enabled` check: "Also check `mode_overrides[MODE]` in config — if false, skip to Phase 3." This makes the quality-gates behavior explicit in the spec rather than hidden in the YAML comment.

### Improvements

1. Separate "empty" from "no-op" in the dispatch model. The spec and prompt both use "empty reaction" to mean `Verdict: no-concerns` (agent had nothing to add). The evidence schema has `reactions_empty` as a count. But an agent dispatched with no visible peer findings (skipped at Step 2.5.3-4 due to topology filtering) is a different case from an agent that saw peers and chose not to react. Both currently collapse into the same non-dispatch path ("skip agents with empty peer findings"). Distinguishing topology-skipped from criterion-not-met (no conditions 1/2/3 triggered) in the evidence payload would make the sycophancy and discourse health signals easier to interpret during calibration.

2. The fixative sequencing constraint (Step 2.5.2b MUST complete before 2.5.3) is correctly specified but the rationale embedded in the spec is the only enforcement. Consider adding an explicit checkpoint after Step 2.5.2b: "Write `{OUTPUT_DIR}/fixative-context.json` with the fired injections and Gini/novelty values before dispatching agents." This makes the sequencing constraint observable (synthesis can verify it ran) and gives `_interspect_emit_reaction_dispatched()` a machine-readable source for `fixative_injections` count rather than requiring the orchestrator to track it in memory across steps.

3. The convergence threshold scaling formula (`effective_threshold = config.skip_if_convergence_above * (agent_count / 5)`) uses a constant divisor of 5 that is not configurable. The formula is documented inline but the magic number 5 is unexplained. Document the rationale (5 is the "calibration fleet size" — the threshold was tuned at N=5 and the scaling corrects for smaller fleets) or add a `calibration_fleet_size` config key so the formula is transparent and adjustable if the standard fleet size changes.

4. The cleanup step at 2.5.1 (`rm -f {OUTPUT_DIR}/*.reactions.md {OUTPUT_DIR}/*.reactions.error.md`) is the correct place to prevent stale reaction files from contaminating a re-run. But it also silently removes reaction files from a previous Phase 2.5 run if flux-drive is invoked twice on the same OUTPUT_DIR without clearing it. The spec says OUTPUT_DIR is cleared before each run (core/protocol.md), but this is worth noting as a sequencing dependency: Step 2.5.1 is safe only if it runs after Phase 2 dispatch but before reaction agents write. If a re-entry scenario (partial run restart) is ever supported, Step 2.5.1 should check for a `reaction-skipped.json` marker before deleting.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 6 (P0: 0, P1: 3, P2: 3)
SUMMARY: Phase 2.5 is structurally sound and the sequencing model is correct, but three integration gaps — missing completion-wait for reaction agents, unimplemented peer-priming discount logic, and undocumented session_id acquisition — must be resolved before the spec can be used as a conformance reference without implementation guesswork.
---
