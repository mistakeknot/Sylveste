---
artifact_type: flux-drive-finding
agent: fd-correctness
bead: sylveste-9lp.9
reviewed: 2026-04-05
plan: /tmp/flux-drive-cross-model-dispatch-1775371273.md
source: os/Clavain/scripts/lib-routing.sh
---

# Correctness Review: Cross-Model Dispatch

### Findings Index

- HIGH    | C-01 | "Task 1.5 score=3 branch"         | Unknown max_model silently blocks upgrades instead of permitting them
- HIGH    | C-02 | "Task 1.5 final validation"        | Safety floor bypassed when regex fallback fires
- MEDIUM  | C-03 | "Task 3.1 step 2 tier_cap"         | Constitutional floor skipped for tier-capped agents; safety floor called out-of-function
- MEDIUM  | C-04 | "Task 3.1 step 4 downgrade cap"    | Downgrade cap cannot distinguish score-driven from pressure-driven downgrades
- MEDIUM  | C-05 | "Task 3.1 step 3 pressure recompute" | 2-pass cap produces non-converged pressure with no warning
- LOW     | C-06 | "Task 1.4 YAML parser"             | Field-order dependency: domain_complexity/max_model after agents: block causes stale carry-over
- LOW     | C-07 | "Task 1.5 score=3 branch"          | Sonnet-tier agents get no upgrade path at score=3 (design gap, not a bug)
- LOW     | C-08 | "Task 1.5 constitutional floor"    | Unknown const_floor tier silently ignored without warning

**Verdict: needs-changes**

---

## Summary

The implementation plan is structurally sound and the pipeline ordering (score adjust → budget pressure → constitutional floor → empty guard → safety floor → validate) is correct in the common case. However, three issues can violate invariants under specific but reachable inputs: an unknown `max_model` value blocks upgrades that should be allowed (C-01); the final validation fallback returns a model that bypassed the safety floor (C-02); and the tier-cap applied outside `routing_adjust_expansion_tier` skips the constitutional floor check before re-applying the safety floor (C-03). The downgrade cap (C-04) and pressure recompute cap (C-05) are approximations that can produce surprising outcomes without surfacing diagnostics.

The existing `lib-routing.sh` already contains `_routing_downgrade`, the new arrays, and `routing_adjust_expansion_tier` — all matching the plan spec. The YAML parser is already in place. Issues C-01 through C-03 exist in the already-committed code; the remaining findings apply to the expansion.md pseudocode that is not yet implemented.

---

## Invariants

The following invariants must hold. If any are violated, a 3 AM page is plausible.

1. **Safety floor is unconditional.** fd-safety, fd-correctness, and all `reviewer` role agents must never run below sonnet regardless of score, pressure, tier_cap, or fallback path.
2. **Constitutional floor <= safety floor.** The constitutional floor (from `min_model` in agent-roles.yaml) is a weaker constraint than the safety floor. If they conflict, the safety floor wins.
3. **Final validation fallback must not bypass floor.** Any fallback to the original model must re-apply the safety floor.
4. **Downgrade is bounded.** No more than half the pool may be downgraded in a single dispatch cycle.
5. **Budget pressure oscillation terminates.** The 2-pass cap must terminate even if pressure did not converge; the result must be safe regardless.
6. **Score=3 upgrade respects max_model ceiling.** An agent with `max_model: haiku` must not be upgraded by a score=3 signal.
7. **Score=1 does not downgrade high-complexity domains.** An agent with `domain_complexity: high` must not be downgraded by a score=1 signal.

---

## Issues Found

### C-01 — HIGH: Unknown max_model silently blocks score=3 upgrades

**Location:** `os/Clavain/scripts/lib-routing.sh` lines 539-545 (Task 1.5, score=3 branch)

**Code in question:**
```bash
local max_ceil; max_ceil=$(_routing_agent_field "$agent" "max_model")
if [[ "$model" == "haiku" || "$model" == "local:qwen3-8b" ]]; then
  if [[ -z "$max_ceil" || "$(_routing_model_tier "$max_ceil")" -ge 2 ]]; then
    model="sonnet"
  fi
fi
```

**The bug:** `_routing_model_tier` returns `0` for any unrecognized model string. If `max_model:` is set to a value not in the tier map — for example `local:qwen3-30b` when that alias is present but something like `claude-haiku-4` is not — `_routing_model_tier` returns `0`. The condition `0 -ge 2` is false, so the upgrade is blocked. This is the opposite of the intended semantics: an unrecognized ceiling should be treated as "no ceiling" (upgrade allowed), not as "ceiling below sonnet" (upgrade blocked).

The condition structure says: upgrade if (`max_ceil` is empty) OR (tier of `max_ceil` >= sonnet). But for an unknown/invalid `max_ceil`, tier is 0, so the OR branch is false, and the outer condition requires the empty-string branch to be true. Since `max_ceil` is non-empty (it holds the unrecognized string), the upgrade is silently blocked.

**Failure narrative:** An agent has `max_model: claude-haiku-4` (a future alias not yet in the tier map). Score=3 fires. `_routing_model_tier "claude-haiku-4"` returns 0. `0 -ge 2` is false. Upgrade blocked. The agent runs at haiku when it should have run at sonnet. No warning is emitted. The caller sees correct-looking behavior (haiku is a valid model) but the score=3 signal had no effect.

**Fix:** Treat tier=0 (unknown) as "no ceiling" and emit a warning:

```bash
local max_ceil; max_ceil=$(_routing_agent_field "$agent" "max_model")
local should_upgrade=1
if [[ -n "$max_ceil" ]]; then
  local ceil_tier; ceil_tier=$(_routing_model_tier "$max_ceil")
  if [[ $ceil_tier -eq 0 ]]; then
    echo "[routing] WARN: agent=$agent has unrecognized max_model='$max_ceil' — ceiling ignored" >&2
  elif [[ $ceil_tier -lt 2 ]]; then
    should_upgrade=0  # ceiling is below sonnet, block upgrade
  fi
fi
if [[ $should_upgrade -eq 1 && ("$model" == "haiku" || "$model" == "local:qwen3-8b") ]]; then
  model="sonnet"
fi
```

This is small and robust. The "no ceiling" path is now explicit and defaults correctly for both empty and unknown values.

---

### C-02 — HIGH: Safety floor bypassed on final validation fallback

**Location:** `os/Clavain/scripts/lib-routing.sh` lines 577-580 (Task 1.5, step 6)

**Code in question:**
```bash
if [[ ! "$model" =~ ^(haiku|sonnet|opus|local:.+)$ ]]; then
  echo "[routing] WARN: adjust returned invalid '$model' for $agent, falling back to $2" >&2
  model="$2"
fi
```

**The bug:** The fallback assigns `model="$2"`, which is the original `current_model` argument passed in by the caller. The safety floor was applied at step 5 of the pipeline. If the validation regex fails for some reason after step 5 (e.g., a model string containing an unexpected character introduced between step 4 and step 5, or a future refactor that reorders steps), the fallback reinstates `$2` — which has not been through the safety floor.

More concretely: if the caller passes `model=""` or `model="badvalue"` and something in steps 1-4 corrupts the value, step 5's safety floor runs on the corrupted value. If step 5 produces a result that the regex still rejects (e.g., the floor itself returned something unexpected due to a separate bug), the fallback skips the floor and returns the raw `$2`.

Invariant 1 states the safety floor is unconditional. The fallback path violates this.

**Failure narrative:** A future refactor stores `model="opus-3.7"` (a versioned alias) in the routing config. The regex at step 6 rejects it. The fallback fires and returns `opus-3.7` without re-applying the safety floor. If the agent is fd-safety and `opus-3.7` happens to not be recognized as >= sonnet by downstream dispatch logic, the agent runs below its floor.

**Fix:** Apply the safety floor to the fallback value before returning:

```bash
if [[ ! "$model" =~ ^(haiku|sonnet|opus|local:.+)$ ]]; then
  echo "[routing] WARN: adjust returned invalid '$model' for $agent, falling back to $2" >&2
  model=$(_routing_apply_safety_floor "$agent" "${2:-haiku}" "expansion-fallback")
fi
```

If `$2` is itself invalid, the safety floor will still clamp to the registered minimum. If `$2` is empty, `haiku` is used as the base before the floor clamps it up.

---

### C-03 — MEDIUM: Tier-cap block skips constitutional floor, double-applies safety floor

**Location:** Plan Task 3.1, step 2 pseudocode

**Code in question (expansion.md pseudocode):**
```
if tier_cap[agent] == "haiku":
    adjusted_model_tier = _routing_model_tier(adjusted_model)
    if adjusted_model_tier > 1:  # > haiku
        adjusted_model = "haiku"
        adjusted_model = _routing_apply_safety_floor(agent, adjusted_model, "tier-cap")
tentative_adjustments[agent] = adjusted_model
```

**The bug:** `routing_adjust_expansion_tier` already applies the constitutional floor (step 3) and safety floor (step 5) internally, returning a fully floored model. The tier-cap block then drives the model back down to haiku and applies `_routing_apply_safety_floor` directly — but it skips the constitutional floor check. For agents whose `min_model` is sonnet (e.g., all reviewers), the constitutional floor should prevent the tier-cap from succeeding. The plan's safety floor call will catch this specific case (since fd-safety and fd-correctness have `min_model: sonnet` in agent-roles.yaml, and `_routing_apply_safety_floor` reads from the same array). However, the constitutional floor is not the same as the safety floor: an agent could have `min_model: sonnet` via the constitutional floor but not have a safety floor entry if it is not in the `reviewer` role. Such an agent would be incorrectly tier-capped to haiku by this block.

**Additionally:** The safety floor is now called twice for tier-capped agents — once inside `routing_adjust_expansion_tier` and once in the tier-cap block. This is harmless for correctness but emits duplicate `[safety-floor]` log lines, polluting the calibration log.

**Fix:** Replace the raw `_routing_apply_safety_floor` call in the tier-cap block with a call to `routing_adjust_expansion_tier` using the capped model as the current_model and score=2 (neutral), or implement a dedicated helper that applies both floors:

```
if tier_cap[agent] == "haiku":
    adjusted_model_tier = _routing_model_tier(adjusted_model)
    if adjusted_model_tier > 1:
        # Apply tier cap then run both floors
        capped = _routing_apply_constitutional_floor(agent, "haiku")
        adjusted_model = _routing_apply_safety_floor(agent, capped, "tier-cap")
```

Where `_routing_apply_constitutional_floor` mirrors the constitutional floor logic already in `routing_adjust_expansion_tier` steps 3-4. Alternatively, add a `routing_apply_floors_only` wrapper that runs steps 3-5 without score/pressure logic.

---

### C-04 — MEDIUM: Downgrade cap cannot distinguish score-driven from pressure-driven downgrades

**Location:** Plan Task 3.1, step 4 pseudocode

**Code in question:**
```
downgraded_count = count(agents where adjusted_model < original_model)
max_downgrades = floor(len(candidates) / 2)
if downgraded_count > max_downgrades:
    # Restore lowest-scored agents to original model (they were downgraded last in merit order)
    # until downgraded_count <= max_downgrades
```

**The bug:** An agent can be downgraded by two independent mechanisms: (a) score=1 with `domain_complexity != high`, or (b) `budget_pressure == high`. The downgrade cap restores "lowest-scored agents to original model." But lowest-scored agents are the ones with score=1 — meaning the cap preferentially restores the agents whose score-based downgrade was most justified (weak evidence). High-scored agents that were downgraded only by budget pressure are not restored, even though their score indicates they warrant the original tier.

The merit-order sort means agents are processed highest-score-first for upgrades, but the downgrade cap restoration goes lowest-score-first. This means an agent with score=3 that was downgraded by pressure is kept downgraded while an agent with score=1 is restored to its original model. This inverts the intended priority.

**Failure narrative:** 6 agents in the pool. 4 are downgraded: 2 by score=1 (score-justified), 2 by budget pressure (score=2 or 3). `max_downgrades = floor(6/2) = 3`. `downgraded_count = 4 > 3`. Restoration loop takes the lowest-scored agent (score=1, downgrade justified) and restores it. The pressure-downgraded score=3 agent stays downgraded. Result: a strongly-evidenced agent runs below its warranted tier while a weakly-evidenced agent runs at full tier.

**Fix:** Track the downgrade reason per agent. The cap should restore pressure-only downgrades first (lowest confidence that the downgrade was warranted), then score-and-pressure, and leave score-only downgrades in place:

```
for each agent, track: downgrade_reason = "score" | "pressure" | "both"
restoration_priority = sort by: pressure-only first, then both, then score-only
                       then by score descending (restore highest-evidence agents first)
```

At minimum, add a `downgrade_reason` field to the adjustment record and document the restoration order explicitly so future modifications don't accidentally worsen it.

---

### C-05 — MEDIUM: 2-pass cap produces non-converged pressure with no diagnostic

**Location:** Plan Task 3.1, step 3

**Code in question:**
```
If `revised_pressure_label` differs from `pressure_label`, run a second pass with the revised pressure.
Cap at 2 passes to prevent oscillation.
```

**The bug:** A 2-pass cap prevents infinite loops but does not guarantee that the result after 2 passes is stable. Consider: first pass at "low" pressure upgrades several agents to sonnet; revised pressure is "high"; second pass at "high" downgrades those agents to haiku; revised pressure would now be "low" again — but the 3rd pass is suppressed. The final result uses the second pass's "high" pressure decisions, which were made on a pool that the first pass had already upgraded.

The danger is not correctness violation per se (the safety floor still holds) but budget overrun: the 2nd pass at "high" pressure may over-downgrade, leaving the pool in a degraded state that does not reflect the actual available budget. The savings recycled in step 5 (upgrade pass) will then be computed on an artificially deflated cost baseline.

Additionally, the plan specifies no logging when the cap fires. An operator reviewing logs cannot tell whether the 2-pass cap was reached.

**Fix:** Two changes:

1. Emit a warning when the cap fires: `[routing] WARN: pressure recompute cap reached after 2 passes; pressure may not have converged. Final label: {revised_pressure_label}`.
2. Add a convergence check before capping: if pass 2 would produce a third distinct label, log it explicitly and document which direction the residual error leans (over-downgraded vs. under-downgraded).

The 2-pass cap is the right approximation for now; the fix is to make the approximation visible.

---

### C-06 — LOW: YAML parser stale carry-over when max_model/domain_complexity follow agents: block

**Location:** `os/Clavain/scripts/lib-routing.sh` lines 449-506 (Task 1.4 parser)

**The bug:** The parser resets `in_agents=0` when it encounters any non-list-item line while inside the agents block (line 503). This is correct for the canonical field order in the plan's YAML schema:

```yaml
  planner:
    description: ...
    model_tier: opus
    min_model: sonnet
    domain_complexity: high
    agents:
      - fd-architecture
```

But YAML does not enforce field order, and editors and merge tools can reorder fields. If someone writes:

```yaml
  planner:
    agents:
      - fd-architecture
    domain_complexity: high    # after agents:
```

The parser would: set `in_agents=1` on `agents:`, populate `_ROUTING_SF_AGENT_MIN` for fd-architecture with empty `current_domain_cx`, then encounter `domain_complexity: high`, which matches the domain_cx regex and sets `current_domain_cx="high"` — but `in_agents` was cleared when it hit the `domain_complexity:` line (line 503: non-list-item while `in_agents=1`). The `current_domain_cx` value is never written to the array for that agent because the agent population already completed.

**Impact:** If `domain_complexity: high` appears after `agents:`, the domain complexity protection (score=1 does not downgrade high-complexity agents) is silently absent. fd-correctness at score=1 would be downgraded to haiku despite `domain_complexity: high` in the YAML.

**Fix:** Add a header comment to agent-roles.yaml requiring canonical field order, and add a validation check in the YAML validation step (Task 4, F4 verification):

```bash
# Validate field order: domain_complexity and max_model must appear before agents:
python3 -c "
import yaml, sys
roles = yaml.safe_load(open('agent-roles.yaml'))['roles']
for name, role in roles.items():
    keys = list(role.keys())
    if 'agents' in keys:
        agents_idx = keys.index('agents')
        for field in ('domain_complexity', 'max_model'):
            if field in keys and keys.index(field) > agents_idx:
                print(f'ERROR: {name}.{field} must appear before agents:', file=sys.stderr)
                sys.exit(1)
"
```

This makes the field-order constraint explicit rather than implicit.

---

### C-07 — LOW: Sonnet-tier agents get no upgrade path at score=3 (design gap)

**Location:** `os/Clavain/scripts/lib-routing.sh` lines 539-545 (Task 1.5, score=3 branch)

**Observation:** The score=3 upgrade only fires when `model == "haiku" || model == "local:qwen3-8b"`. A sonnet-tier reviewer with score=3 is not upgraded to opus. The plan's spec calls this "upgrade haiku checkers" and the intent is clear, but the consequence is that the highest-evidence expansion signal cannot elevate a reviewer to opus even when the evidence is overwhelming.

This is not a correctness bug — it is consistent with the `max_model` ceiling for the `checker` role and the role-priority spec. However, the pool-level assertion in step 6 also only checks "at sonnet," so a sonnet reviewer with score=3 that was budget-pressure-downgraded to haiku will be restored to sonnet by the pool assertion, but a planner that started at opus and was downgraded to sonnet has no path back to opus via step 6.

**Recommendation:** Document this as an intentional design constraint in the function's comment block. If opus-tier planners should be restorable on score=3, the score=3 branch needs a second clause: `if model == "sonnet" && role == "planner" && no max_model ceiling`. This is a future iteration item, not a blocker.

---

### C-08 — LOW: Unknown constitutional floor tier silently ignored without warning

**Location:** `os/Clavain/scripts/lib-routing.sh` lines 562-568 (Task 1.5, step 3)

**Code in question:**
```bash
local const_floor; const_floor=$(_routing_agent_field "$agent" "min_model")
if [[ -n "$const_floor" ]]; then
  local m_tier f_tier
  m_tier=$(_routing_model_tier "$model")
  f_tier=$(_routing_model_tier "$const_floor")
  [[ $m_tier -lt $f_tier ]] && model="$const_floor"
fi
```

If `const_floor` is set to an unrecognized value, `f_tier=0`. Since even haiku is tier 1, `m_tier -lt 0` is always false. The constitutional floor is silently skipped. Contrast with `_routing_apply_safety_floor`, which emits a warning when the floor model has tier 0.

**Impact:** Low, because `min_model` values in agent-roles.yaml are constrained to `haiku|sonnet|opus` by convention and the YAML validation in F4 verification would catch typos. But the constitutional floor block has no defensive parity with the safety floor block.

**Fix:** Mirror the safety floor's warning behavior:

```bash
if [[ $f_tier -eq 0 ]]; then
  echo "[routing] WARN: agent=$agent has unrecognized min_model='$const_floor' in agent-roles.yaml — constitutional floor ignored" >&2
fi
```

---

## Improvements

### I-01 — Make `routing_adjust_expansion_tier` callable on the fallback result

The final validation (step 6) could be simplified if the function guarantees it never returns an invalid model. Add an assertion in the unit tests that no valid combination of (agent, model, score, pressure) produces an output matching `^(haiku|sonnet|opus|local:.+)$` negation. If that assertion holds, the regex fallback becomes a defensive belt-and-suspenders guard, not a correctional path, and the fallback-to-$2 risk (C-02) is practically unreachable. Document this explicitly.

### I-02 — Add `_routing_apply_floors_only` wrapper

The tier-cap block in Task 3.1 needs to apply both the constitutional floor and the safety floor. Rather than inlining this logic again (and risking drift with the logic already in `routing_adjust_expansion_tier`), add a wrapper that runs only steps 3-5:

```bash
# Applies constitutional floor + empty guard + safety floor. No score/pressure logic.
# Use for post-hoc clamping (e.g., after tier-cap application).
_routing_apply_floors_only() {
  local agent="$1" model="$2" caller="${3:-floors-only}"
  local const_floor; const_floor=$(_routing_agent_field "$agent" "min_model")
  if [[ -n "$const_floor" ]]; then
    local m_tier f_tier
    m_tier=$(_routing_model_tier "$model")
    f_tier=$(_routing_model_tier "$const_floor")
    if [[ $f_tier -gt 0 && $m_tier -lt $f_tier ]]; then
      model="$const_floor"
    fi
  fi
  [[ -n "$model" ]] || model="haiku"
  model=$(_routing_apply_safety_floor "$agent" "$model" "$caller")
  echo "$model"
}
```

The tier-cap block then becomes: `adjusted_model=$(_routing_apply_floors_only "$agent" "haiku" "tier-cap")`, and both floors are applied correctly without duplicating the safety floor call.

### I-03 — Add downgrade reason tracking from the start

Even if C-04's full fix is deferred, add a comment in the plan noting that `tentative_adjustments` should store `{model, downgrade_reason}` rather than just `{model}`. The data structure is easier to change before the code is written than after. Suggested structure:

```
tentative_adjustments[agent] = {
  model: <string>,
  original_model: <string>,
  downgrade_reason: "score" | "pressure" | "both" | null,
  score: <int>,
  domain_complexity: <string>,
}
```

### I-04 — Pressure recompute convergence annotation

The plan should explicitly state the invariant that the 2-pass cap is conservative in the direction of over-downgrading (the 2nd pass at "high" pressure cannot over-upgrade). This is true because: the upgrade pass (step 5) runs after the pressure recompute and is bounded by `tokens_saved`. Documenting this invariant makes future modifications safer and confirms the cap is safe to use even without convergence.

### I-05 — Score=3 upgrade: document the local model upgrade path

`_routing_downgrade` handles `local:qwen3-30b` and `local:qwen2.5-72b` → `local:qwen3-8b`. But the score=3 upgrade checks only `haiku` and `local:qwen3-8b`. A local-model agent at `local:qwen3-8b` (haiku-equivalent) would be upgraded to `sonnet` (a cloud model), not to `local:qwen3-30b`. This may be intentional (Track B5 is cloud-preferred on upgrade) but should be documented. If local-only routing is a future requirement, the score=3 branch will need a `local:` prefix check.

<!-- flux-drive:complete -->
