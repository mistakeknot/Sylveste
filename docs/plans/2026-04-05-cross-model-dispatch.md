---
artifact_type: plan
bead: sylveste-9lp.9
prd: docs/prds/2026-04-05-cross-model-dispatch.md
brainstorm: docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md
features: [sylveste-ug8, sylveste-dpo, sylveste-3de, sylveste-jti, sylveste-65l]
---
# Implementation Plan: Cross-Model Dispatch

## Build Order

```
Phase 1: F4 (agent-roles.yaml) + F1 (core functions)  [parallel, no deps]
Phase 2: F2 (scoring hardening)                        [needs F4 for domain data]
Phase 3: F3 (dispatch integration)                     [needs F1+F2+F4]
Phase 4: F5 (observability)                            [needs F3]
```

F4 and F1 can be done in a single pass since F1's unit tests can stub agent-roles data, but having real data makes integration testing cleaner.

---

## Phase 1a: F4 — Agent-Roles Extension (sylveste-jti)

**Files:** `interverse/interflux/config/flux-drive/agent-roles.yaml`

### Task 1.1: Add domain_complexity and max_model fields

Add two new fields per agent in the existing roles structure. Values based on role analysis:

```yaml
roles:
  planner:
    description: Architectural decisions requiring high reasoning capability
    model_tier: opus
    min_model: sonnet
    domain_complexity: high      # NEW
    agents:
      - fd-architecture
      - fd-systems

  reviewer:
    description: Detailed checking requiring medium-high capability
    model_tier: sonnet
    min_model: sonnet
    domain_complexity: high      # NEW
    agents:
      - fd-correctness
      - fd-quality
      - fd-safety

  editor:
    description: Practical suggestions and domain-specific analysis
    model_tier: sonnet
    domain_complexity: medium    # NEW
    agents:
      - fd-performance
      - fd-user-product
      - fd-game-design

  checker:
    description: Pattern matching and cognitive lens application
    model_tier: haiku
    domain_complexity: low       # NEW
    max_model: sonnet            # NEW — checkers shouldn't get opus even on upgrade
    agents:
      - fd-perception
      - fd-resilience
      - fd-decisions
      - fd-people
```

Add header comment explaining the new fields:
```yaml
# domain_complexity: low|medium|high — minimum reasoning tier for coherent analysis
#   in this domain. Used by cross-model dispatch to prevent downgrading complex-domain
#   agents below their reasoning floor. low=pattern matching, medium=practical analysis,
#   high=architectural/correctness reasoning.
#
# max_model: haiku|sonnet|opus (optional) — maximum tier warranted for this role.
#   Prevents over-resourcing simple-domain agents during upgrade passes.
#   If absent, no ceiling is enforced.
```

**AC check:** All 7 F4 acceptance criteria met by this single edit.

---

## Phase 1b: F1 — Core Tier Adjustment Function (sylveste-ug8)

**Files:** `os/Clavain/scripts/lib-routing.sh`, `interverse/interflux/config/flux-drive/budget.yaml`

### Task 1.2: Add feature gate to budget.yaml

Append to the end of budget.yaml:

```yaml
# Cross-model dispatch — evidence-proportional tier routing for expansion pool
# Adjusts Stage 2 / speculative agent model tiers based on expansion score,
# domain complexity, and budget pressure. Safety floors always enforced.
cross_model_dispatch:
  enabled: true
  mode: shadow    # shadow = log adjustments without applying | enforce = apply adjustments
```

### Task 1.3: Add `_routing_downgrade()` to lib-routing.sh

Insert after `_routing_apply_safety_floor()` (after line ~91):

```bash
# --- Downgrade model one tier ---
# Usage: _routing_downgrade <model>
# Returns next lower tier. haiku stays haiku. Empty/unknown preserved or defaults to haiku.
_routing_downgrade() {
  case "${1:-}" in
    opus)               echo "sonnet" ;;
    sonnet)             echo "haiku" ;;
    haiku)              echo "haiku" ;;
    local:qwen3-30b)    echo "local:qwen3-8b" ;;  # Track B5
    local:qwen2.5-72b)  echo "local:qwen3-8b" ;;  # Track B5
    local:qwen3-8b)     echo "local:qwen3-8b" ;;  # Track B5: already lowest
    *)                  echo "${1:-haiku}" ;;       # unknown → preserve or default
  esac
}
```

### Task 1.4: Extend `_routing_load_cache()` with domain_complexity and max_model arrays

**Architectural decision (from plan review):** Do NOT create a new `_routing_agent_field()` function that spawns Python subprocesses. Instead, extend the existing safety floor cache parser (lines 430-474 of lib-routing.sh) to populate two new bash arrays during the same line-by-line parse pass.

Add two new global arrays after the existing `_ROUTING_SF_AGENT_MIN` declaration (line 45):

```bash
declare -gA _ROUTING_SF_AGENT_DOMAIN_CX=()      # [agent_name]=low|medium|high
declare -gA _ROUTING_SF_AGENT_MAX_MODEL=()       # [agent_name]=haiku|sonnet|opus (empty if no ceiling)
```

In the safety floor parser loop (lines 430-474), add parsing for `domain_complexity:` and `max_model:` alongside the existing `min_model:` parsing:

```bash
# Track current role's domain_complexity and max_model
local current_min="" current_domain_cx="" current_max_model="" in_agents=0

# ... existing min_model parsing ...

# domain_complexity field (NEW)
if [[ "$line" =~ ^[[:space:]]+domain_complexity:[[:space:]]* ]]; then
  current_domain_cx="${line#*domain_complexity:}"
  current_domain_cx="${current_domain_cx#"${current_domain_cx%%[![:space:]]*}"}"
  current_domain_cx="${current_domain_cx%"${current_domain_cx##*[![:space:]]}"}"
  continue
fi

# max_model field (NEW)
if [[ "$line" =~ ^[[:space:]]+max_model:[[:space:]]* ]]; then
  current_max_model="${line#*max_model:}"
  current_max_model="${current_max_model#"${current_max_model%%[![:space:]]*}"}"
  current_max_model="${current_max_model%"${current_max_model##*[![:space:]]}"}"
  continue
fi

# In agent list item: populate all three arrays
if [[ $in_agents -eq 1 && "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
  local agent_name="${line#*- }"
  # ... existing trimming ...
  [[ -n "$current_min" && -n "$agent_name" ]] && _ROUTING_SF_AGENT_MIN["$agent_name"]="$current_min"
  [[ -n "$current_domain_cx" && -n "$agent_name" ]] && _ROUTING_SF_AGENT_DOMAIN_CX["$agent_name"]="$current_domain_cx"
  [[ -n "$current_max_model" && -n "$agent_name" ]] && _ROUTING_SF_AGENT_MAX_MODEL["$agent_name"]="$current_max_model"
  continue
fi

# Role name reset — reset all three fields
if [[ "$line" =~ ^[[:space:]]{2}[a-z] && ! "$line" =~ ^[[:space:]]{4} ]]; then
  current_min="" current_domain_cx="" current_max_model=""
  in_agents=0
  continue
fi
```

Then add a simple lookup helper (3 lines, no subprocess):

```bash
# --- Look up agent field from pre-populated cache ---
# Usage: _routing_agent_field <agent> <field>
# Fields: min_model, domain_complexity, max_model
_routing_agent_field() {
  local agent="${1:-}" field="${2:-}"
  [[ -z "$agent" ]] && return 0
  # Strip namespace prefix
  [[ "$agent" == *:* ]] && agent="${agent##*:}"
  case "$field" in
    min_model)          echo "${_ROUTING_SF_AGENT_MIN[$agent]:-}" ;;
    domain_complexity)  echo "${_ROUTING_SF_AGENT_DOMAIN_CX[$agent]:-}" ;;
    max_model)          echo "${_ROUTING_SF_AGENT_MAX_MODEL[$agent]:-}" ;;
    *)                  echo "" ;;
  esac
}
```

This eliminates: Python dependency, subprocess spawning (30+ calls), file discovery duplication, string interpolation risk. The cache is populated once on first `_routing_load_cache()` call.

### Task 1.5: Add `routing_adjust_expansion_tier()` to lib-routing.sh

Insert after `_routing_agent_field()`. This is the core function:

```bash
# --- Adjust expansion pool agent model tier ---
# Usage: routing_adjust_expansion_tier <agent> <current_model> <expansion_score> <budget_pressure>
# Pipeline: score adjust → budget pressure → constitutional floor → safety floor → validate
# budget_pressure: "low" | "medium" | "high"
# Returns: adjusted model name
routing_adjust_expansion_tier() {
  local agent="$1" model="$2" score="${3:-2}" pressure="${4:-low}"

  # 1. Score-based tier adjustment
  case "$score" in
    3) # Strong evidence — upgrade haiku checkers if no max_model ceiling blocks it
       local max_ceil; max_ceil=$(_routing_agent_field "$agent" "max_model")
       if [[ "$model" == "haiku" || "$model" == "local:qwen3-8b" ]]; then
         if [[ -z "$max_ceil" || "$(_routing_model_tier "$max_ceil")" -ge 2 ]]; then
           model="sonnet"
         fi
       fi
       ;;
    2) ;; # Moderate evidence — keep model
    1) # Weak evidence — downgrade unless domain_complexity is high
       local dom_cx; dom_cx=$(_routing_agent_field "$agent" "domain_complexity")
       if [[ "${dom_cx:-low}" != "high" ]]; then
         model=$(_routing_downgrade "$model")
       fi
       ;;
    0) model="haiku" ;; # Should not reach dispatch
    *) ;; # Invalid score — keep model
  esac

  # 2. Budget pressure (applied after score, before floors)
  if [[ "$pressure" == "high" ]]; then
    model=$(_routing_downgrade "$model")
  fi

  # 3. Constitutional floor from agent-roles.yaml
  local const_floor; const_floor=$(_routing_agent_field "$agent" "min_model")
  if [[ -n "$const_floor" ]]; then
    local m_tier f_tier
    m_tier=$(_routing_model_tier "$model")
    f_tier=$(_routing_model_tier "$const_floor")
    [[ $m_tier -lt $f_tier ]] && model="$const_floor"
  fi

  # 4. INVARIANT: empty model guard — default to haiku before safety floor
  [[ -n "$model" ]] || model="haiku"

  # 5. Safety floor (ALWAYS LAST — non-negotiable)
  model=$(_routing_apply_safety_floor "$agent" "$model" "expansion")

  # 6. Final validation
  if [[ ! "$model" =~ ^(haiku|sonnet|opus|local:.+)$ ]]; then
    echo "[routing] WARN: adjust returned invalid '$model' for $agent, falling back to $2" >&2
    model="$2"
  fi

  echo "$model"
}
```

**AC check:** All 9 F1 acceptance criteria addressed. Feature gate in Task 1.2, `_routing_downgrade` edge cases in Task 1.3, constitutional floor + safety floor ordering + empty model guard + final validation in Task 1.5, score=3 upgrade + score=1 complexity check in Task 1.5.

---

## Phase 2: F2 — Expansion Scoring Hardening (sylveste-dpo)

**Files:** `interverse/interflux/skills/flux-drive/phases/expansion.md`

### Task 2.1: Add trigger_source_id to expansion scoring algorithm

In expansion.md § "Expansion scoring algorithm" (around line 142), modify the scoring to carry source IDs:

```
expansion_contributions = []  # list of (source_id, score_increment)

for each Stage 1 finding:
    source_id = "{agent}:{finding_index}"  # unique per finding
    if P0 in an adjacent agent's domain:
        expansion_contributions.append((source_id, 3))
    if P1 in an adjacent agent's domain:
        expansion_contributions.append((source_id, 2))

for each Stage 1 agent pair:
    if agents disagree on a finding in this agent's domain:
        source_id = "disagree:{agent_a}:{agent_b}:{finding}"
        expansion_contributions.append((source_id, 2))

if agent has domain injection criteria for a detected domain:
    source_id = "domain:{domain_name}"
    expansion_contributions.append((source_id, 1))

# Deduplication: keep max contribution per source_id (pool-wide)
deduplicated = {}
for (sid, inc) in expansion_contributions:
    deduplicated[sid] = max(deduplicated.get(sid, 0), inc)

expansion_score = min(sum(deduplicated.values()), 3)
```

### Task 2.2: Add merit-order sort before dispatch

In expansion.md, between Step 2.2b (expansion decision) and Step 2.2c (Stage 2 launch), add:

```markdown
#### Pre-dispatch sort (merit order)

Before dispatching Stage 2 agents, sort candidates by:
1. `expansion_score` descending (highest-confidence agents first)
2. `role_priority` descending: planner=4 > reviewer=3 > editor=2 > checker=1
3. `name` ascending (stable tiebreaker)

High-score agents get first claim on budget headroom. Process in this order
for both tier adjustment and dispatch.
```

### Task 2.3: Add domain intersection check

After the expansion scoring algorithm, before the expansion decision table, add:

```markdown
#### Domain intersection validation

For each expansion candidate with score > 0:
- Resolve the candidate's primary domain from `adjacency` map or agent focus
- Resolve the trigger finding's domain from the Stage 1 agent that produced it
- If `trigger_domain ∩ candidate_domain == ∅` (no adjacency relationship exists):
  - Log: `[expansion] {agent}: score={score} but no domain overlap with trigger — capping tier at haiku`
  - Set `tier_cap = haiku` for this candidate (applied during cross-model dispatch)
- This check prevents phantom adjacency inflation: a domain-specific P0 should not
  drive a non-adjacent agent to sonnet
```

**AC check:** All 6 F2 acceptance criteria addressed.

---

## Phase 3: F3 — Expansion Dispatch Integration (sylveste-3de)

**Files:** `interverse/interflux/skills/flux-drive/phases/expansion.md`

### Task 3.1: Wire tier adjustment into Step 2.2c (Stage 2 dispatch)

Replace the current Step 2.2c content with:

```markdown
### Step 2.2c: Stage 2 — Remaining agents (if expanded) [review only]

**Skip this step in research mode.**

#### Cross-model dispatch (if enabled)

Check feature gate:
```bash
cmd_enabled=$(python3 -c "import yaml; d=yaml.safe_load(open('budget.yaml')); print(d.get('cross_model_dispatch',{}).get('enabled','false'))" 2>/dev/null) || cmd_enabled="false"
cmd_mode=$(python3 -c "import yaml; d=yaml.safe_load(open('budget.yaml')); print(d.get('cross_model_dispatch',{}).get('mode','shadow'))" 2>/dev/null) || cmd_mode="shadow"
```

If `cmd_enabled == "true"`:

**1. Compute budget pressure:**
```
speculative_reserve = incremental_expansion.max_speculative × agent_defaults.review
effective_budget = remaining_budget - speculative_reserve
pressure_ratio = 1.0 - (effective_budget / sum(stage2_cost_estimates))
pressure_label = "low" if < 0.2, "medium" if 0.2-0.5, "high" if > 0.5
```

**2. First pass — tentative tier adjustment (sorted order):**
For each candidate in merit-order (from Task 2.2):
```
original_model = resolved_model_for(agent)  # from routing_resolve_agents output in Step 2.0.5, or agent frontmatter default
adjusted_model = routing_adjust_expansion_tier(agent, original_model, expansion_score, pressure_label)
# Apply tier_cap from domain intersection check (Task 2.3)
if tier_cap[agent] == "haiku":
    adjusted_model_tier = _routing_model_tier(adjusted_model)
    if adjusted_model_tier > 1:  # > haiku
        adjusted_model = "haiku"
        adjusted_model = _routing_apply_safety_floor(agent, adjusted_model, "tier-cap")
tentative_adjustments[agent] = adjusted_model
```

**3. Recompute pressure from adjusted costs:**
```
adjusted_total = sum(cost_estimate(agent, tentative_adjustments[agent]) for agent in candidates)
revised_pressure_ratio = 1.0 - (effective_budget / adjusted_total)
revised_pressure_label = classify(revised_pressure_ratio)
```
If `revised_pressure_label` differs from `pressure_label`, run a second pass with the revised pressure. Cap at 2 passes to prevent oscillation.

**4. Downgrade cap:**
```
downgraded_count = count(agents where adjusted_model < original_model)
max_downgrades = floor(len(candidates) / 2)
if downgraded_count > max_downgrades:
    # Restore lowest-scored agents to original model (they were downgraded last in merit order)
    # until downgraded_count <= max_downgrades
```

**5. Upgrade pass (savings recycling):**
```
tokens_saved = sum(cost(original) - cost(adjusted) for each agent)
if tokens_saved > 10000:
    # Find highest-scored score=2 agent that was NOT upgraded
    # Upgrade one tier: haiku→sonnet or sonnet→opus
    # Apply safety floor and max_model ceiling
```

**6. Pool-level quality assertion (runs AFTER upgrade pass):**
```
planner_reviewer_at_sonnet = count(agents where role in (planner, reviewer) AND tier >= sonnet)
if planner_reviewer_at_sonnet == 0:
    # Upgrade highest-scored planner/reviewer to sonnet
```

**7. Shadow vs enforce:**
```
if cmd_mode == "shadow":
    # Log all adjustments with [shadow] prefix
    # Dispatch at original models from Step 2.0.5 map
else:
    # Dispatch at adjusted models
```

**8. Dispatch Stage 2 agents** with `run_in_background: true`, passing the final model per agent.

If `cmd_enabled == "false"`:
Launch Stage 2 agents with `run_in_background: true` using models from Step 2.0.5 map (existing behavior, unchanged).
```

### Task 3.2: Wire tier adjustment into Step 2.2a.6 (speculative launches)

In expansion.md § Step 2.2a.6, after computing partial expansion_score, add:

```markdown
**Cross-model dispatch for speculative launches:**

If `cross_model_dispatch.enabled`:
1. Apply speculative discount: `effective_score = max(expansion_score - 1, 1)`
   Note: since speculative triggers at score>=3, discount yields score=2 ("keep model") —
   the discount prevents the score=3 upgrade path, not the base tier. This is intentional:
   speculative evidence is partial, so upgrades shouldn't fire, but the base tier is preserved.
2. Budget pressure: use current `remaining_budget` (no speculative reserve needed — this IS the speculative launch)
3. Call `routing_adjust_expansion_tier(agent, model, effective_score, pressure_label)`
4. If `mode == "shadow"`: log with `[shadow][speculative]` prefix, dispatch at original model
5. If `mode == "enforce"`: dispatch at adjusted model

Log: `[speculative Stage 2] Launching {agent} at {model} (score={original_score}, discounted={effective_score})`
```

**AC check:** All 10 F3 acceptance criteria addressed across Tasks 3.1 and 3.2.

---

## Phase 4: F5 — Observability (sylveste-65l)

**Files:** `interverse/interflux/skills/flux-drive/phases/expansion.md`, `interverse/interflux/skills/flux-drive/phases/synthesize.md`

### Task 4.1: Add dispatch log format

In Step 2.2c, after the dispatch loop, add the log block:

```
Cross-model dispatch (Stage 2):
  {agent}: {original} → {adjusted} (score={score}, domain_complexity={dc}, {reason})
  ...
  🛡 {agent}: {model} → {floor_model} (safety floor clamped)
Budget pressure: {pressure_ratio:.2f} ({pressure_label}), reserve: {reserve}
Pool audit: {n} planners/reviewers at sonnet ✓|✗
Savings: ~{tokens_saved} tokens{" (recycled {recycled} → upgraded {agent} {from}→{to})" if upgrade_pass_fired}
Mode: {shadow|enforce}
```

### Task 4.2: Add calibration emit

After all Stage 2 agents complete (in Step 2.3 or synthesis), emit calibration data:

```
For each tier-adjusted agent (where adjusted_model != original_model OR mode == "shadow"):
    Log: [cmd-calibration] agent={name} score={score} original={orig} adjusted={adj}
         findings={count} max_severity={P0|P1|P2|P3|none} downgraded={true|false}
```

This structured log line enables future analysis: `grep cmd-calibration <logs> | jq` to build the calibration dataset.

### Task 4.3: Add escalation advisory

In Step 2.3 (agent completion monitoring), after reading each completed agent's findings:

```
if agent was tier-adjusted AND agent's max_finding_severity in (P0, P1):
    Log: [tier-escalation] {agent} was downgraded {orig}→{adj} but returned {severity} finding
         — candidate for tier escalation in future runs
```

### Task 4.4: Add tier field to agent output

In the agent prompt template (Step 2.2 / launch.md), add to the output format instructions:

```
Include `tier: {model}` in your findings metadata (the model you are running on).
```

This is a one-line addition to the agent prompt template. Agents include it in their output frontmatter.

**AC check:** All 7 F5 acceptance criteria addressed across Tasks 4.1-4.4.

---

## Verification Strategy

### Per-feature verification

| Feature | Verification |
|---------|-------------|
| F1 | Bash unit test: source lib-routing.sh, call `routing_adjust_expansion_tier` with known inputs, assert outputs. Test cases: score=3 upgrade (haiku→sonnet), score=3 with max_model=haiku (stays haiku), score=1 downgrade (sonnet→haiku), score=1+domain_complexity=high (stays sonnet), budget_pressure=high (extra downgrade), safety floor clamp (fd-safety never below sonnet), empty model guard (""→haiku→floor), unknown model fallback, constitutional floor read from cache. |
| F2 | Bash unit test: construct sample expansion_contributions list with duplicate source_ids, verify dedup produces correct score. Verify sort order matches merit-order spec. Verify domain intersection check caps tier when no overlap. |
| F3 | Run flux-drive with `cross_model_dispatch.mode: shadow` — verify logs show tier adjustments without applying them. Then switch to `enforce` and verify dispatch uses adjusted models. |
| F4 | Validate YAML: `python3 -c "import yaml; yaml.safe_load(open('agent-roles.yaml'))"`. Verify all roles have domain_complexity. |
| F5 | Grep logs for `[cmd-calibration]`, `[tier-escalation]`, and `Cross-model dispatch` format. Verify all fields present. |

### Integration test

Full pipeline: run `/interflux:flux-drive` on a document with expansion (needs Stage 1 to produce findings that trigger Stage 2). Verify:
1. Stage 2 agents receive different models based on expansion score
2. Safety-floored agents never below sonnet
3. Pool-level assertion holds
4. Calibration data logged
5. Shadow mode works (logs but doesn't apply)

---

## File Change Summary

| File | Change Type | Scope |
|------|------------|-------|
| `interverse/interflux/config/flux-drive/agent-roles.yaml` | Edit | Add domain_complexity + max_model per role |
| `interverse/interflux/config/flux-drive/budget.yaml` | Edit | Add cross_model_dispatch section |
| `os/Clavain/scripts/lib-routing.sh` | Edit | Add 3 functions (~80 lines) |
| `interverse/interflux/skills/flux-drive/phases/expansion.md` | Edit | Modify scoring, add sort, add Step 2.2c dispatch integration |

4 files modified. ~80 lines of bash, ~150 lines of markdown, ~10 lines of YAML. No new files created.
