---
artifact_type: review
agent: fd-architecture
skill: flux-drive
bead: sylveste-9lp.9
reviewed_plan: /tmp/flux-drive-cross-model-dispatch-1775371273.md
date: 2026-04-05
---

# Architecture Review: Cross-Model Dispatch Implementation Plan

### Findings Index

- MEDIUM | A1 | "Phase 1b / Task 1.5 Step 1" | `score=3` upgrade skips non-haiku models silently
- HIGH   | A2 | "Phase 3 / Task 3.1 Step 2" | Feature gate read via Python subprocess inside dispatch hot path
- HIGH   | A3 | "Phase 3 / Task 3.1 Step 4" | Downgrade cap restores lowest-scored agents but leaves floor violations unrechecked
- MEDIUM | A4 | "Phase 3 / Task 3.1 Step 5" | Upgrade pass does not enforce `max_model` ceiling after recycling
- MEDIUM | A5 | "Phase 3 / Task 3.1 Step 6" | Pool-level quality assertion can override safety floors via unchecked upgrade
- LOW    | A6 | "Phase 2 / Task 2.3" | Domain intersection `tier_cap` bypassed by pool assertion in Step 6
- LOW    | A7 | "Phase 4 / Task 4.2" | Calibration emit condition includes `mode == "shadow"` — will emit for every unadjusted agent
- LOW    | A8 | "Phase 1b / Task 1.4" | Parser state machine does not reset `in_agents` on top-level section transition

Verdict: **needs-changes**

---

## Summary

The plan is architecturally sound at its core. The decision to extend the existing `_routing_load_cache()` parser rather than spawn Python subprocesses is the right call — it eliminates 30+ subprocess forks per dispatch and keeps the data access pattern consistent with the existing safety floor lookup. The pipeline order (score → budget → constitutional floor → empty guard → safety floor → validation) is correct and defensible. The shadow/enforce gate in budget.yaml is appropriately conservative.

The implementation as delivered has one high-severity integration fault (Python subprocess for feature gate inside the dispatch path), one high-severity correctness fault (downgrade cap restores models without rechecking floors), and several medium-severity gaps in the upgrade and pool assertion steps. None of these require structural rework. Each is a contained fix within the function or step where the issue lives.

The boundary between `lib-routing.sh` (mechanism) and `expansion.md` (protocol) is well-respected. `routing_adjust_expansion_tier()` is a pure function from the protocol's perspective: inputs in, adjusted model out. The protocol is responsible for sorting, pressure computation, the two-pass loop, and all pool-level logic. The library is responsible for per-agent floor enforcement. This split is correct and matches the existing `routing_resolve_model()` / dispatch boundary.

---

## Issues Found

### 1. [HIGH] A2 — Python subprocess for feature gate inside dispatch hot path

**Location:** expansion.md § Step 2.2c, "Check feature gate" code block.

The plan reads `budget.yaml` with `python3 -c "import yaml; ..."` at the start of Step 2.2c. This is the same subprocess pattern the plan explicitly rejects for agent field lookup (Task 1.4 architectural note: "Eliminates: Python dependency, subprocess spawning (30+ calls)"). Step 2.2c fires for every expansion dispatch, and Step 2.2a.6 also gates on `cross_model_dispatch.enabled`. A failed Python invocation silently falls back to `"false"`, disabling the entire feature without any log entry at the call site.

The fix is to read `budget.yaml` once at the start of the skill run (Step 2.0.5 already sources `lib-routing.sh`; a companion `_routing_load_budget_cache()` or a simple `yq`/`python3` call at skill initialization that stores the gate values in env vars would isolate the fallibility to startup, not hot dispatch). Alternatively, since `budget.yaml` is already co-located with `agent-roles.yaml`, the `_routing_load_cache()` extension added in Task 1.4 could trivially parse the `cross_model_dispatch` section and expose it via a helper — no Python, no subprocesses, same parse pass.

The fallback (`|| cmd_enabled="false"`) means a missing `python3` or missing `yaml` module silently disables cross-model dispatch. This is a failure mode with no observable signal beyond absence of the feature.

### 2. [HIGH] A3 — Downgrade cap restores models without rechecking floors

**Location:** expansion.md § Step 2.2c, "Step 4: Downgrade cap."

The cap restores the "lowest-scored agents to original model" when `downgraded_count > max_downgrades`. The restored `original_model` was the value from Step 2.0.5 — it passed through `routing_resolve_agents` which applies safety floors and interspect overrides. That is safe. However, the agents being restored are the lowest-scored ones, which were processed last in merit order. For those agents, the tentative adjustment in Step 2 may have already applied a `tier_cap = haiku` from the domain intersection check (Task 2.3). Restoring the original model discards the `tier_cap`. After restoration, no floor recheck is specified.

The smallest fix: after restoring an agent to its original model, reapply the domain intersection `tier_cap` check and then `_routing_apply_safety_floor()`. This is one conditional per restored agent.

### 3. [MEDIUM] A1 — `score=3` upgrade path silently skips non-haiku starting models

**Location:** `lib-routing.sh` `routing_adjust_expansion_tier()` Step 1, `score=3` branch.

The upgrade condition is `if [[ "$model" == "haiku" || "$model" == "local:qwen3-8b" ]]`. If an agent starts at sonnet and scores 3, nothing happens — the model stays at sonnet, no upgrade to opus. This is a silent no-op. The PRD says "upgrade one tier" (score=3 upgrade path), but the implementation only upgrades from haiku. A score-3 sonnet agent that could benefit from opus is silently left at sonnet.

Whether upgrading sonnet→opus at score=3 is intended is a policy question, not a bug per se, but the existing silence is the issue — a caller cannot distinguish "upgrade not warranted" from "upgrade not implemented for this starting tier." The plan's comment reads "upgrade haiku checkers," which suggests the constraint is intentional (only haiku-tier agents upgrade). If so, the implementation is correct but the comment on the function's caller contract should state this ceiling explicitly.

Smallest fix if intent is "haiku only": add a comment in the `score=3` branch stating sonnet agents are not upgraded even at score=3. If intent is "upgrade one tier": change condition to upgrade any model that is below the `max_model` ceiling.

### 4. [MEDIUM] A4 — Upgrade pass does not enforce `max_model` ceiling after recycling

**Location:** expansion.md § Step 2.2c, "Step 5: Upgrade pass."

The upgrade pass description says "Apply safety floor and max_model ceiling" in a parenthetical, but does not spell out the order of operations or that this must call `_routing_apply_safety_floor()`. The prose says "Upgrade one tier: haiku→sonnet or sonnet→opus" without specifying what blocks a checker (max_model=sonnet) from being upgraded to opus if it was at sonnet. If the candidate selected for recycling is a checker-role agent starting at sonnet, the upgrade pass would push it to opus, bypassing the `max_model=sonnet` ceiling in agent-roles.yaml.

Smallest fix: the upgrade pass must call `_routing_agent_field "$agent" max_model` and compare tiers before executing the upgrade, the same way `routing_adjust_expansion_tier()` does at score=3.

### 5. [MEDIUM] A5 — Pool-level quality assertion can override safety floors via unchecked upgrade

**Location:** expansion.md § Step 2.2c, "Step 6: Pool-level quality assertion."

The assertion fires "if planner_reviewer_at_sonnet == 0" and upgrades the "highest-scored planner/reviewer to sonnet." Planner and reviewer roles already have `min_model: sonnet` enforced by `routing_adjust_expansion_tier()` Step 3 (constitutional floor). If the pool assertion reaches a state where no planner/reviewer is at sonnet, it means either: (a) there are no planner/reviewer agents in the pool, or (b) a planner/reviewer was somehow placed below sonnet — which would be a bug in the floor logic, not something the assertion should silently paper over.

Case (a) is not a quality problem: if no planners/reviewers exist in the pool, asserting "at least one at sonnet" by upgrading an editor-role agent to sonnet is a category error. The assertion should only upgrade planner/reviewer-role agents, and if none exist, it should log a note rather than doing nothing silently.

Case (b) is a symptom of a floor failure. Silently upgrading masks the root cause.

Smallest fix: the assertion should log the pool composition (agent, role, tier) when it fires, and only upgrade agents whose role is planner or reviewer. If no such agent exists, log the gap and do not upgrade editors or checkers as a proxy.

### 6. [LOW] A6 — Domain intersection `tier_cap` can be overridden by pool assertion

**Location:** expansion.md § Steps 2.2c Step 2 and Step 6 interaction.

The domain intersection check (Task 2.3) sets `tier_cap = haiku` for candidates with no domain overlap with their trigger. This cap is applied in Step 2 during tentative adjustment. However, Step 6 (pool assertion) can upgrade any planner/reviewer, and if a planner/reviewer had a `tier_cap = haiku` applied from domain intersection, the assertion would upgrade it past that cap. The tier_cap from domain intersection is not consulted in Step 6.

This interaction is low-severity because planners and reviewers (fd-architecture, fd-correctness, fd-quality, fd-safety) have strong adjacency in the existing adjacency map, making a domain intersection cap on them unlikely in practice. But the logic gap exists.

Smallest fix: Step 6 should check `tier_cap[agent]` before upgrading, skipping agents with an active haiku cap.

### 7. [LOW] A7 — Calibration emit condition emits for all agents in shadow mode

**Location:** expansion.md § Step 2.2c, "Calibration emit."

The condition is `where adjusted_model != original_model OR mode == "shadow"`. The `OR mode == "shadow"` clause means every dispatched agent emits a calibration record in shadow mode, regardless of whether any adjustment was computed. This inflates calibration data with unadjusted agents and makes the calibration dataset harder to use — `grep cmd-calibration | jq` will return records for agents whose `original == adjusted`, making "did the adjustment fire?" ambiguous without further filtering.

Smallest fix: emit only when `adjusted_model != original_model` regardless of mode, and add a `mode: shadow|enforce` field to the log line. The mode field already appears in the dispatch log summary (Task 4.1), so it is available.

### 8. [LOW] A8 — Parser state machine does not reset `in_agents` on top-level section transition

**Location:** `lib-routing.sh` `_routing_load_cache()`, agent-roles.yaml parse loop.

The agent-roles.yaml parser tracks `in_agents=1` when inside an `agents:` block. The reset condition is a role-name line (`^[[:space:]]{2}[a-z]` not at 4+ indent). If a future agent-roles.yaml adds a top-level section after `roles:` (e.g., `experiments:` — which already exists in the file), and that section contains a line matching `^[[:space:]]+-[[:space:]]`, the parser will incorrectly populate agent arrays from non-agent content. The file as currently implemented does not trigger this bug because `experiments:` content is at deeper indent, but the guard is absent.

The existing file already has an `experiments:` top-level key with nested content at 2-space indent. The role-name reset fires on any `^[[:space:]]{2}[a-z]` line, which does cover `experiments:` members like `  exp1_complexity_routing:`. This makes the bug latent rather than active. Still, an explicit `[[ "$line" =~ ^roles: ]]` section guard or a check for `section="roles"` would make the intent clear and prevent future regression.

---

## Improvements

### 1. Read budget gate once at skill initialization, not per-dispatch

Move the `budget.yaml` feature gate read to a `_routing_load_budget_gate()` function co-located with `_routing_load_cache()` in `lib-routing.sh`, or to a one-time initialization block at the start of Step 2.0.5 in the skill. Store results in env vars (`CMD_ENABLED`, `CMD_MODE`). This eliminates the Python subprocess, eliminates the silent disable risk, and makes the gate consistent across Step 2.2a.6 (speculative) and Step 2.2c (main dispatch) without duplicating the read. The `_routing_load_cache()` call already happens at Step 2.0.5 — piggyback the budget gate parse on the same call.

Rationale: the plan's own architectural note for Task 1.4 ("eliminates Python dependency, subprocess spawning") applies equally here. Consistency with the established pattern costs nothing and closes the failure mode.

### 2. Centralize post-adjustment floor recheck into a named function

The sequence "apply tier_cap → apply safety floor" appears in at least three places: Step 2 (tentative adjustment), the downgrade cap restoration (Step 4), and the upgrade pass (Step 5). Extract this into a named helper in the skill or a second public function in `lib-routing.sh`:

```bash
# Apply all post-adjustment clamping: tier_cap, max_model, safety floor.
routing_clamp_adjusted_model <agent> <model> <tier_cap>
```

This prevents the floor-skip bug in Steps 4 and 5 structurally (you cannot forget to call it if all restoration/upgrade paths route through one function) and makes the invariant auditable.

Rationale: the current plan describes the clamping inline in each step's prose. Prose descriptions diverge; a shared function does not. The safety floor is described as "ALWAYS LAST — non-negotiable"; a single call site for all post-adjustment clamping is the mechanical enforcement of that statement.

### 3. Make pool assertion scope explicit in the protocol text

Add a sentence to Step 6: "Only planner-role and reviewer-role agents are candidates for the pool assertion upgrade. If no such agents exist in the pool, log the absence and skip the upgrade." This eliminates the category error of upgrading editors as proxies for planners, and it documents the expected behavior when the assertion fires on an unusual pool composition (e.g., all planner/reviewer agents were dropped by AgentDropout before this step).

Rationale: the current protocol text says "upgrade highest-scored planner/reviewer" which implies the filter, but does not handle the zero-match case. The pool assertion is the last guardrail before dispatch — its behavior in edge cases must be unambiguous.

### 4. Add explicit wiring call to lib-routing.sh for budget gate parsing

If the budget gate remains in `expansion.md` (markdown protocol, not bash), document a `_routing_load_budget_gate_from_env()` pattern at the top of Step 2.2c: callers that have already read budget.yaml elsewhere (e.g., budget enforcement in Step 2.2b already reads the file) should pass gate values as environment variables rather than re-reading the file. This is consistent with how `INTERSPECT_ROUTING_MODE` overrides the calibration mode in `lib-routing.sh` — env vars are the protocol for cross-boundary config passing.

Rationale: the existing `lib-routing.sh` already uses `${INTERSPECT_ROUTING_MODE:-}` env var override for calibration mode. Applying the same pattern to the budget gate flag makes the cross-boundary interface consistent.

### 5. Separate F5 calibration emit into two cases: observed and shadow-observed

The current calibration emit fires one log line per adjusted agent. Split into:
- `[cmd-calibration]` — agent was adjusted AND dispatched at the adjusted model (enforce mode)
- `[cmd-calibration-shadow]` — agent adjustment was computed but not applied (shadow mode)

This makes downstream `grep | jq` analysis unambiguous: calibrate from `cmd-calibration` lines; analyze model sensitivity from `cmd-calibration-shadow` lines. The closed-loop OODARC pattern (PHILOSOPHY.md) requires that calibration data feeds back into routing decisions — mixing shadow observations with actual outcomes corrupts that loop.

<!-- flux-drive:complete -->
