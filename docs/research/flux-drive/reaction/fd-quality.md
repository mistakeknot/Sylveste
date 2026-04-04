### Findings Index

- P1 | Q-01 | "Step 2.5.0" | `mode_overrides` consumed nowhere in reaction.md
- P1 | Q-02 | "Step 2.5.0" | Skip-path emits wrong event type label
- P1 | Q-03 | "Step 2.5.3-4" | `{agent_description}` template variable undefined in orchestrator spec
- P1 | Q-04 | "Step 2.5.0" | Peer-priming discount algorithm leaves timestamp source unspecified
- P2 | Q-05 | "Step 2.5.3-4" | Agents-with-empty-peer-findings skip rule produces silent no-op without event record
- P2 | Q-06 | "Step 2.5.5" | `session_id` call-site argument omitted from both emit call descriptions
- P2 | Q-07 | "Step 2.5.2" | `severity_filter_p2_light` interaction with topology visibility is unspecified
- P2 | Q-08 | "Step 2.5.2b" | Collapse trigger condition uses `collapse_threshold: 2` but spec says "BOTH" — numeric vs boolean semantics diverge
- P2 | Q-09 | "Step 2.5.3-4" | Timeout enforcement responsibility not assigned (orchestrator vs agent runtime)
- P2 | Q-10 | "reaction-prompt.md" | `partially-agree` maps to `distinction` in Move Type table but prompt body maps same to `defense` in earlier rule

Verdict: needs-changes

### Summary

The reaction.md spec is structurally sound and integrates cleanly with the surrounding discourse protocol files. The convergence gate, topology-aware visibility, discourse fixative, and interspect emission sections are all present and internally consistent at a high level. However, ten issues were found, two of which are P1: the `mode_overrides` block in `reaction.yaml` is declared but never consumed by the orchestration spec (silent behavioral gap in quality-gates mode), and the skip-path emits an event labeled `interspect-reaction` while the actual interspect function name is `_interspect_emit_reaction_dispatched` — the prose conflates the log-tag with the event type, which will confuse implementors. The P2 issues are primarily specification-level ambiguities that an implementor would need to resolve by inspecting sibling files rather than reading this spec in isolation.

### Issues Found

**1. P1 | Q-01 — `mode_overrides` consumed nowhere in reaction.md**

`reaction.yaml` declares `mode_overrides: { quality-gates: false, review: true, flux-drive: true }`. The `reaction.md` spec only tests `reaction_round.enabled` (line 5). There is no instruction to check the current `MODE` against `mode_overrides` before Step 2.5.0. An orchestrator running in `quality-gates` mode would execute the reaction round when the config says it should be skipped. The SKILL.md header (`[review mode only]`) partially mitigates this for the review/research split, but `quality-gates` is a third mode not covered by that guard. The spec needs an explicit early-exit condition: "If current MODE appears in `mode_overrides` with value `false`, skip to Phase 3."

**2. P1 | Q-02 — Skip-path emits wrong event type label**

Step 2.5.0 (skip branch) says: "emit an `interspect-reaction` event ... via `_interspect_emit_reaction_dispatched()`". The string `interspect-reaction` is the `review_type` tag passed to `_interspect_insert_evidence` inside that function (confirmed in `lib-interspect.sh` line 3001), not the event type. The event type stored is `reaction_dispatched`. Calling this an `interspect-reaction` event in the spec creates a terminology mismatch — readers looking for `interspect-reaction` in the evidence schema will not find it. The spec should say: "emit a `reaction_dispatched` evidence record (type: skip) via `_interspect_emit_reaction_dispatched()`."

**3. P1 | Q-03 — `{agent_description}` template variable undefined**

`reaction-prompt.md` line 3 uses `{agent_description}` in the agent identity header: "You are **{agent_name}** ({agent_description})." Step 2.5.3-4 lists the variables filled into the template as `{agent_name}`, `{own_findings_index}`, `{peer_findings}`, `{fixative_context}`, `{output_path}`. The variable `{agent_description}` is absent from the orchestrator's fill list. An implementor following reaction.md will produce a reaction prompt with a literal `{agent_description}` placeholder. The spec must either list this variable and specify its source (e.g., agent frontmatter `description` field) or the prompt template must be corrected to remove it.

**4. P1 | Q-04 — Peer-priming discount timestamp source unspecified**

Step 2.5.0 peer-priming discount: "For each finding title in the overlap set, check if the first report timestamp in peer-findings.jsonl precedes a second agent's Findings Index entry." The Findings Index is a static file with no per-entry timestamps — only the `peer-findings.jsonl` entries have timestamps (from `findings-helper.sh`). The instruction implies comparing a JSONL timestamp against a Findings Index entry timestamp, but the Findings Index format (defined in `shared-contracts.md`) contains no timestamp field. An implementor cannot execute this algorithm as written. The spec must clarify what "a second agent's Findings Index entry" timestamp means — presumably the `.md` file modification time or the agent completion time tracked separately — and specify where that value comes from.

**5. P2 | Q-05 — Empty-peer-findings skip produces no event record**

Step 2.5.3-4 says: "Skip agents with empty peer findings." There is no instruction to record which agents were skipped or why, and no corresponding field in the `reaction-dispatched` evidence payload (the payload counts `agents_dispatched`, not `agents_skipped`). If all agents are skipped this way (because topology left everyone isolated before the isolation fallback fires), the Step 2.5.5 report and the interspect evidence will show 0 dispatched with no explanation. The spec should at minimum instruct the orchestrator to log or count skipped agents, and ideally note that the isolation fallback in Step 2.5.2a should prevent this case from occurring silently.

**6. P2 | Q-06 — `session_id` argument omitted from emit call descriptions**

Step 2.5.0 and Step 2.5.5 both describe calling `_interspect_emit_reaction_dispatched()` with a list of named arguments. Neither mention the first positional argument `session_id` that the function requires (`session_id="${1:?session_id required}"`). An implementor building the call site from the spec alone will produce a call that fails with "session_id required". The spec should include `session_id` as a required field in both emit descriptions and note its source (e.g., `$CLAUDE_SESSION_ID`).

**7. P2 | Q-07 — `severity_filter_p2_light` and topology visibility interaction unspecified**

Step 2.5.2 filters findings to P0/P1 (with optional P2 via `severity_filter_p2_light`). Step 2.5.2a applies topology-based visibility. It is unclear whether the `summary` visibility level for adjacent roles includes P2 findings when `severity_filter_p2_light` is true, or whether severity filtering happens before topology filtering. If filtering happens before topology, P2 findings appear in `full` visibility blocks but not in `summary` blocks, which could create asymmetric information across roles. The spec should state the ordering and intent explicitly.

**8. P2 | Q-08 — `collapse_threshold: 2` vs "BOTH" — numeric vs boolean semantics**

`discourse-fixative.yaml` sets `collapse_threshold: 2` with the comment "fires if imbalance AND convergence both trigger." The spec (Step 2.5.2b) says "Collapse: fires if imbalance AND convergence both trigger." The YAML value `2` and the prose "BOTH" are consistent in intent but the spec does not say how the numeric threshold is evaluated. If a future third trigger is added, does collapse require `count >= 2` (any two) or does `collapse_threshold` mean the exact count of the two named triggers? The spec should state explicitly: "Collapse fires when the count of triggered injections equals `collapse_threshold` (currently 2 — gini and novelty both triggered)."

**9. P2 | Q-09 — Timeout enforcement responsibility not assigned**

Step 2.5.3-4 specifies `Timeout: timeout_seconds from config (default: 60s)` for dispatched reaction agents. It does not state who enforces this timeout or what happens on breach: does the orchestrator kill the agent, does it proceed to Step 2.5.5 counting the agent as an error, or does it wait indefinitely? The monitoring contract in `shared-contracts.md` covers Phase 2 agents but is not referenced here. The spec should explicitly reference the monitoring contract, confirm the same polling/inotifywait mechanism applies, and state that a timed-out agent counts toward `reactions_errors` in the Step 2.5.5 report.

**10. P2 | Q-10 — `partially-agree` → `distinction` vs `defense` contradiction in reaction-prompt.md**

`reaction-prompt.md` contains two move-type assignment descriptions that conflict. The "Output Format" section defines the stance/move-type pairing in the structured output block but does not enumerate mappings. The "Move Type Assignment" section at the bottom (the canonical reference) maps `partially-agree` → `distinction`. However, the earlier "Instructions" section contains no note about `distinction` — readers who stop at the output format block do not learn about `distinction` as a valid move type. More critically, the "Instructions" section only lists `agree`/`partially-agree`/`disagree`/`missed-this` as valid stances, but the Move Type Assignment section lists `concession` as a separate move type triggered by "agree while withdrawing a prior finding" — a stance not enumerated in the stance list. The stance list and move type table should be reconciled into a single authoritative table.

### Improvements

**1. Add a MODE guard at the top of Step 2.5.0**

Insert before the convergence gate: "Check `mode_overrides` in `reaction.yaml`. If the current `MODE` maps to `false` (e.g., `quality-gates: false`), skip to Phase 3 immediately." This closes the behavioral gap for modes other than review/research without requiring changes to the `[review mode only]` header convention.

**2. Add `{agent_description}` to the fill list in Step 2.5.3-4**

Add: "Fill `{agent_description}` from the agent's frontmatter `description` field (first non-example sentence). If unavailable, use the agent's role description from `agent-roles.yaml`." This makes the template fill list exhaustive and prevents literal placeholder leakage.

**3. Clarify the peer-priming discount to use a concrete comparator**

Replace the current timestamp comparison prose with: "A finding is peer-primed if it appears in `peer-findings.jsonl` AND the JSONL entry timestamp precedes the file modification time of the second agent's `.md` output. Use `stat -c %Y` (Linux) or `stat -f %m` (macOS) to get the `.md` modification time." This removes the dependency on a phantom per-entry timestamp in the Findings Index.

**4. Unify the reaction-prompt stance and move-type tables**

Move the "Move Type Assignment" section above the output format block in `reaction-prompt.md`, and add `concession` as an explicit entry in the stance list. This prevents readers from building an incomplete mental model from the first pass through the instructions.

**5. Add a cross-reference to the monitoring contract for reaction timeout handling**

At the end of Step 2.5.3-4, add: "Monitor for reaction completion using the same mechanism as Phase 2 agents (see `shared-contracts.md` — Monitoring Contract). Timed-out agents count toward `reactions_errors` in Step 2.5.5. Do not wait beyond `timeout_seconds`."

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 10 (P0: 0, P1: 4, P2: 6)
SUMMARY: The reaction round spec is coherent at the system level but has four P1 gaps — a silent mode_overrides bypass, a wrong event-type label in the skip path, an undefined template variable, and an unexecutable peer-priming timestamp algorithm — that would cause observable implementation divergence. No blocking correctness defects; safe to ship after resolving P1 items.
---
