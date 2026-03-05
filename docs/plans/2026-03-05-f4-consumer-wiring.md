---
artifact_type: plan
bead: iv-nh3d7
stage: design
---
# F4: Consumer Wiring — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-nh3d7
**Goal:** Wire flux-drive and sprint executor to consume Composer dispatch plans, replacing hardcoded agent selection with agency-spec-driven dispatch.

**Architecture:** Extend existing `lib-compose.sh` with stored-artifact-first retrieval and helper functions. Modify flux-drive `launch.md` Step 2.0.4 to use the Composer plan as authoritative agent source. Add sprint env var injection to the SessionStart hook.

**Tech Stack:** Bash (lib-compose.sh, hook, tests), Markdown (launch.md skill updates)

**Prior Learnings:**
- Existing `lib-compose.sh` at `os/clavain/scripts/lib-compose.sh` — minimal stub with `compose_dispatch()` (on-demand only) and `compose_available()`. Needs extension, not replacement.
- Go CLI binary is `clavain-cli-go` (not `clavain-cli`). The `_compose_find_cli()` resolver already handles this correctly.
- `selfbuild.go` has `sprint-env-vars` command ready — outputs `export CLAVAIN_MODEL=X` shell statements.
- `sprint-scan.sh` already detects active sprints in SessionStart via `sprint_find_active()` from `lib-sprint.sh`.
- Bats test convention: `tests/shell/test_*.bats`, source `test_helper` which sets `$HOOKS_DIR` and `$FIXTURES_DIR`.
- launch.md Step 2.0.4 already has placeholder code for Composer integration — needs to be made real.
- `session-start.sh` assembles `additionalContext` with priority-based shedding. Sprint env vars go to `CLAUDE_ENV_FILE`, not additionalContext.

**Review Findings Addressed:**

From fd-architecture and fd-quality reviews (2026-03-05):
- A1: Keep existing one-liner source pattern in launch.md (`${CLAVAIN_SOURCE_DIR:-$CLAUDE_PLUGIN_ROOT}/scripts/lib-compose.sh`)
- A3: Cache sprint data in `SPRINT_ACTIVE_JSON` module-level var from `sprint_brief_scan` — do NOT call `sprint_find_active` again (iv-zlht)
- A4: Delegate `_compose_has_agency_spec` to canonical spec resolution, include `.clavain/` project-local path
- A6: Mark dispatch loop as pseudocode with explicit implementation note
- F4-1: Source lib-compose.sh is transitive via sprint-scan.sh → lib-sprint.sh; verify availability, don't add redundant source
- F4-2: Test file named `test_lib_compose.bats` (not `lib_compose.bats`) to match `test_*.bats` glob convention
- F4-3: Use `BATS_TEST_TMPDIR` for temp dirs in tests (auto-cleanup)
- F4-4: Update header comment from `$sprint_id` to `$bead_id`
- F4-6: `compose_warn_if_expected` always returns 0 (side-effect function, not predicate)
- F4-7: Use `local` for intermediate variables in bats test bodies

---

### Task 1: Extend lib-compose.sh with stored-artifact retrieval and helper functions [x]

**Files:**
- Edit: `os/clavain/scripts/lib-compose.sh`

**What to do:**

Extend the existing file. Keep `_compose_find_cli()` and `compose_available()` as-is. Rewrite `compose_dispatch()` and add new helpers. Update the header comment.

**Step 1: Update header comment**

Change the usage example from `$sprint_id` to `$bead_id`:
```bash
# Usage:
#   source lib-compose.sh
#   plan=$(compose_dispatch "$bead_id" "$stage")
#   echo "$plan" | jq '.agents[]'
```

**Step 2: Add `_compose_has_agency_spec()` function**

After `_compose_find_cli()`, add a function that checks whether any agency-spec.yaml exists in the config resolution path. Includes the project-local `.clavain/` override path (highest priority per lib-spec.sh).

```bash
_compose_has_agency_spec() {
    # Check project-local override first (highest priority per lib-spec.sh)
    local project_dir="${SPRINT_LIB_PROJECT_DIR:-.}"
    [[ -f "${project_dir}/.clavain/agency-spec.yaml" ]] && return 0
    # Then check standard config dirs
    for dir in "${CLAVAIN_CONFIG_DIR:-}" "${CLAVAIN_DIR:-}/config" "${CLAVAIN_SOURCE_DIR:-}/config" "${CLAUDE_PLUGIN_ROOT:-}/config"; do
        [[ -z "$dir" ]] && continue
        [[ -f "${dir}/agency-spec.yaml" ]] && return 0
    done
    return 1
}
```

**Step 3: Rewrite `compose_dispatch()` with stored-first logic**

Replace the existing `compose_dispatch()` with: (1) try reading stored ic artifact via `clavain-cli-go get-artifact <bead_id> compose_plan`, (2) if that fails or no bead_id, fall back to on-demand `clavain-cli-go compose --stage=<stage>`.

```bash
compose_dispatch() {
    local bead_id="${1:-}"
    local stage="${2:?compose_dispatch: stage required}"
    local cli=""
    cli=$(_compose_find_cli) || { echo ""; return 1; }

    # Try stored artifact first (if bead_id provided)
    if [[ -n "$bead_id" ]]; then
        local artifact_path=""
        artifact_path=$("$cli" get-artifact "$bead_id" "compose_plan" 2>/dev/null) || artifact_path=""
        if [[ -n "$artifact_path" && -f "$artifact_path" ]]; then
            # Stored plans are an array of ComposePlan; extract the matching stage
            local plan=""
            plan=$(jq -c --arg s "$stage" '.[] | select(.stage == $s)' "$artifact_path" 2>/dev/null) || plan=""
            if [[ -z "$plan" ]]; then
                # Try single plan format (not array)
                plan=$(jq -c --arg s "$stage" 'select(.stage == $s)' "$artifact_path" 2>/dev/null) || plan=""
            fi
            if [[ -n "$plan" ]]; then
                echo "$plan"
                return 0
            fi
        fi
    fi

    # Fallback: on-demand compose
    local args=(compose --stage="$stage")
    [[ -n "$bead_id" ]] && args+=(--sprint="$bead_id")
    "$cli" "${args[@]}" 2>/dev/null
}
```

**Step 4: Add helper functions**

After `compose_dispatch()`:

```bash
# compose_agents_json <plan_json>
# Extracts the agents array from a ComposePlan JSON string.
compose_agents_json() {
    local plan="${1:?compose_agents_json: plan required}"
    echo "$plan" | jq -c '.agents // []'
}

# compose_has_agents <plan_json>
# Returns 0 if the plan has a non-empty agents array.
compose_has_agents() {
    local plan="${1:-}"
    [[ -z "$plan" ]] && return 1
    local count=""
    count=$(echo "$plan" | jq '.agents | length' 2>/dev/null) || return 1
    [[ "$count" -gt 0 ]]
}

# compose_warn_if_expected <error_message>
# If agency-spec exists (user opted into Composer), print the error to stderr.
# If no agency-spec, silently succeed (Composer not configured = expected absence).
# Always returns 0 — this is a side-effect function, not a predicate.
compose_warn_if_expected() {
    local err="${1:-compose failed}"
    if _compose_has_agency_spec; then
        echo "compose: WARNING — $err (agency-spec found, Composer should be functional)" >&2
    fi
    return 0
}
```

**Acceptance test:** After editing, verify `bash -n os/clavain/scripts/lib-compose.sh` passes (syntax check).

---

### Task 2: Create test fixtures and bats tests for lib-compose.sh [x]

**Files:**
- Create: `os/clavain/tests/fixtures/compose-plan-array.json`
- Create: `os/clavain/tests/fixtures/compose-plan-single.json`
- Create: `os/clavain/tests/fixtures/compose-plan-empty-agents.json`
- Create: `os/clavain/tests/shell/test_lib_compose.bats`

**Step 1: Create fixture files**

`compose-plan-array.json` — array of ComposePlan objects (normal sprint-compose output):
```json
[
  {
    "stage": "build",
    "sprint": "iv-test",
    "budget": 100000,
    "estimated_total": 75000,
    "warnings": [],
    "agents": [
      {"agent_id": "fd-architecture", "subagent_type": "interflux:fd-architecture", "model": "sonnet", "estimated_tokens": 25000, "role": "architecture-review", "required": true, "model_source": "fleet_preferred"},
      {"agent_id": "fd-safety", "subagent_type": "interflux:fd-safety", "model": "sonnet", "estimated_tokens": 25000, "role": "safety-review", "required": true, "model_source": "safety_floor"}
    ]
  },
  {
    "stage": "ship",
    "sprint": "iv-test",
    "budget": 50000,
    "estimated_total": 30000,
    "warnings": ["budget_low"],
    "agents": [
      {"agent_id": "fd-quality", "subagent_type": "interflux:fd-quality", "model": "haiku", "estimated_tokens": 15000, "role": "quality-review", "required": false, "model_source": "routing_fallback"}
    ]
  }
]
```

`compose-plan-single.json` — single ComposePlan (backward compat format):
```json
{
  "stage": "build",
  "sprint": "iv-single",
  "budget": 80000,
  "estimated_total": 60000,
  "warnings": [],
  "agents": [
    {"agent_id": "fd-correctness", "subagent_type": "interflux:fd-correctness", "model": "sonnet", "estimated_tokens": 30000, "role": "correctness-review", "required": true, "model_source": "fleet_preferred"}
  ]
}
```

`compose-plan-empty-agents.json` — plan with no agents (unmatched roles):
```json
{
  "stage": "discover",
  "sprint": "iv-empty",
  "budget": 50000,
  "estimated_total": 0,
  "warnings": ["unmatched_role:brainstorm-facilitator"],
  "agents": []
}
```

**Step 2: Write bats tests**

`test_lib_compose.bats`:

```bash
#!/usr/bin/env bats
# Tests for scripts/lib-compose.sh

setup() {
    load test_helper
    SCRIPTS_DIR="$BATS_TEST_DIRNAME/../../scripts"
    source "$SCRIPTS_DIR/lib-compose.sh"
}

@test "compose_has_agents: returns 0 for plan with agents" {
    local plan
    plan=$(cat "$FIXTURES_DIR/compose-plan-single.json")
    run compose_has_agents "$plan"
    assert_success
}

@test "compose_has_agents: returns 1 for plan with empty agents" {
    local plan
    plan=$(cat "$FIXTURES_DIR/compose-plan-empty-agents.json")
    run compose_has_agents "$plan"
    assert_failure
}

@test "compose_has_agents: returns 1 for empty string" {
    run compose_has_agents ""
    assert_failure
}

@test "compose_agents_json: extracts agents array" {
    local plan
    plan=$(cat "$FIXTURES_DIR/compose-plan-single.json")
    run compose_agents_json "$plan"
    assert_success
    local count
    count=$(echo "$output" | jq 'length')
    [ "$count" -eq 1 ]
}

@test "compose_agents_json: extracts agent subagent_type" {
    local plan
    plan=$(cat "$FIXTURES_DIR/compose-plan-single.json")
    run compose_agents_json "$plan"
    assert_success
    local agent_type
    agent_type=$(echo "$output" | jq -r '.[0].subagent_type')
    [ "$agent_type" = "interflux:fd-correctness" ]
}

@test "compose_warn_if_expected: silent when no agency-spec" {
    _compose_has_agency_spec() { return 1; }
    run compose_warn_if_expected "test error"
    assert_success
    assert_output ""
}

@test "compose_warn_if_expected: warns and returns 0 when agency-spec exists" {
    _compose_has_agency_spec() { return 0; }
    run compose_warn_if_expected "test error"
    assert_success
}

@test "_compose_has_agency_spec: finds spec in CLAUDE_PLUGIN_ROOT" {
    mkdir -p "$BATS_TEST_TMPDIR/config"
    touch "$BATS_TEST_TMPDIR/config/agency-spec.yaml"
    CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR" run _compose_has_agency_spec
    assert_success
}

@test "_compose_has_agency_spec: finds spec in project-local .clavain/" {
    mkdir -p "$BATS_TEST_TMPDIR/.clavain"
    touch "$BATS_TEST_TMPDIR/.clavain/agency-spec.yaml"
    SPRINT_LIB_PROJECT_DIR="$BATS_TEST_TMPDIR" CLAVAIN_CONFIG_DIR="" CLAVAIN_DIR="" CLAVAIN_SOURCE_DIR="" CLAUDE_PLUGIN_ROOT="" \
        run _compose_has_agency_spec
    assert_success
}

@test "_compose_has_agency_spec: returns 1 when no spec exists" {
    SPRINT_LIB_PROJECT_DIR="$BATS_TEST_TMPDIR" CLAVAIN_CONFIG_DIR="" CLAVAIN_DIR="" CLAVAIN_SOURCE_DIR="" CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR" \
        run _compose_has_agency_spec
    assert_failure
}

@test "compose_dispatch: stub test for stored-artifact path" {
    # Stub _compose_find_cli to return a mock script that cats a fixture
    local mock_cli="$BATS_TEST_TMPDIR/mock-cli"
    cat > "$mock_cli" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "get-artifact" ]]; then
    echo "$BATS_TEST_TMPDIR/stored-plan.json"
elif [[ "$1" == "compose" ]]; then
    echo '{"stage":"build","agents":[]}'
fi
MOCK
    chmod +x "$mock_cli"
    cp "$FIXTURES_DIR/compose-plan-array.json" "$BATS_TEST_TMPDIR/stored-plan.json"
    _compose_find_cli() { echo "$mock_cli"; }
    export BATS_TEST_TMPDIR

    run compose_dispatch "iv-test" "build"
    assert_success
    # Should get the build stage plan from the stored artifact
    local agent_count
    agent_count=$(echo "$output" | jq '.agents | length')
    [ "$agent_count" -eq 2 ]
}

@test "source lib-compose.sh has no side effects" {
    run bash -c "source '$SCRIPTS_DIR/lib-compose.sh' 2>&1"
    assert_success
    assert_output ""
}
```

**Acceptance test:** Run `cd os/clavain && bats tests/shell/test_lib_compose.bats` — all tests should pass.

---

### Task 3: Update flux-drive launch.md Step 2.0.4 with real Composer integration [x]

**Files:**
- Edit: `interverse/interflux/skills/flux-drive/phases/launch.md`

**What to do:**

Replace the existing Step 2.0.4 (lines 19-44) with a concrete implementation. Use the existing one-liner source pattern from the stub (not a for-loop probe — review finding A1).

**Replace lines 19-44 with:**

````markdown
### Step 2.0.4: Composer dispatch plan (optional)

If the Composer is available, use it instead of manual triage + routing. The Composer is authoritative — when it provides agents, skip Steps 2.0.5-2.2 entirely.

```bash
COMPOSER_ACTIVE=0
COMPOSE_PLAN=""

# Source lib-compose.sh from Clavain (keep existing one-liner pattern)
source "${CLAVAIN_SOURCE_DIR:-$CLAUDE_PLUGIN_ROOT}/scripts/lib-compose.sh" 2>/dev/null || true

if type compose_available &>/dev/null && compose_available 2>/dev/null; then
    # Map flux-drive phase to Composer stage
    _fd_stage="${PHASE:-build}"
    case "$_fd_stage" in
        plan-review|planned) _fd_stage="design" ;;
        executing|build)     _fd_stage="build" ;;
        shipping|ship)       _fd_stage="ship" ;;
    esac

    COMPOSE_PLAN=$(compose_dispatch "${CLAVAIN_BEAD_ID:-}" "$_fd_stage" 2>/dev/null) || COMPOSE_PLAN=""

    if [[ -n "$COMPOSE_PLAN" ]] && compose_has_agents "$COMPOSE_PLAN"; then
        COMPOSER_ACTIVE=1

        # Log warnings from plan
        _warnings=$(echo "$COMPOSE_PLAN" | jq -r '.warnings[]?' 2>/dev/null) || _warnings=""
        if [[ -n "$_warnings" ]]; then
            echo "Composer warnings:"
            echo "$_warnings" | while read -r w; do echo "  - $w"; done
        fi

        # Log agent roster
        _agent_count=$(echo "$COMPOSE_PLAN" | jq '.agents | length' 2>/dev/null) || _agent_count=0
        echo "Composer: ${_agent_count} agents selected for stage ${_fd_stage}"
    else
        # Composer returned no agents — warn if agency-spec exists (user expects Composer)
        compose_warn_if_expected "no agents for stage ${_fd_stage}" 2>/dev/null
    fi
else
    # Composer not available — warn if agency-spec exists
    compose_warn_if_expected "compose_available returned false" 2>/dev/null
fi
```

**If `COMPOSER_ACTIVE=1`:** Skip Steps 2.0.5 (routing_resolve_agents), 2.1e (trust multiplier), 2.2 (triage dispatch), and 2.2a.5 (AgentDropout). Go directly to agent dispatch using the plan.

**Implementation note:** The loop below is pseudocode showing the iteration pattern. Replace the loop body with the same Agent() invocation used in Step 2.2, passing `_agent_type` as `subagent_type` and `_agent_model` as the `model:` parameter.

```bash
# Iterate Composer plan agents (pseudocode — wire to Agent() per Step 2.2 pattern)
echo "$COMPOSE_PLAN" | jq -c '.agents[]' | while read -r _agent; do
    _agent_type=$(echo "$_agent" | jq -r '.subagent_type')
    _agent_model=$(echo "$_agent" | jq -r '.model')
    _agent_id=$(echo "$_agent" | jq -r '.agent_id')
    _required=$(echo "$_agent" | jq -r '.required')
    echo "Dispatching: ${_agent_id} (model: ${_agent_model}, required: ${_required})"
    # TODO: Replace with Agent() tool dispatch matching Step 2.2 invocation pattern
done
```

Steps 2.1 (knowledge injection), 2.1a (domain criteria), 2.1d (overlays), and 2.1c (temp files) still run — they prepare prompt content that applies regardless of how agents were selected.

**If `COMPOSER_ACTIVE=0`:** Fall through to existing Steps 2.0.5-2.2 unchanged (backward compatible).
````

**Additionally**, add a guard at the top of Step 2.0.5 (line ~46):

```markdown
**Skip this step if `COMPOSER_ACTIVE=1`** — the Composer already selected agents with model tiers.
```

And at the top of Step 2.2 (line ~297):

```markdown
**Condition**: Use this step when `DISPATCH_MODE = task` (default) **AND `COMPOSER_ACTIVE=0`**. When `COMPOSER_ACTIVE=1`, agents were already dispatched from the Composer plan in Step 2.0.4.
```

---

### Task 4: Add sprint env var injection to SessionStart hook [x]

**Files:**
- Edit: `os/clavain/hooks/sprint-scan.sh` (export cached sprint data)
- Edit: `os/clavain/hooks/session-start.sh` (consume cached data for env var injection)

**IMPORTANT ordering note:** The env var injection block (in session-start.sh) uses `_compose_find_cli` which is defined in lib-compose.sh. lib-compose.sh is sourced transitively by sprint-scan.sh via lib-sprint.sh. Therefore, the injection block MUST appear AFTER `source "${SCRIPT_DIR}/sprint-scan.sh"` (line 212). Do NOT add a redundant explicit source of lib-compose.sh.

**Step 1: Export sprint data from sprint_brief_scan (sprint-scan.sh)**

In `sprint_brief_scan()`, after the existing `sprint_find_active` call (lines 352-365), export the result as a module-level variable so session-start.sh can reuse it without calling `sprint_find_active` again (review finding A3, iv-zlht anti-pattern).

Add after the sprint_brief_scan function closes (after line 372), or better: inside `sprint_brief_scan` after line 365, add:

```bash
# Export for session-start.sh to reuse (avoid duplicate sprint_find_active call — iv-zlht)
SPRINT_ACTIVE_JSON="$_scan_active_sprints"
```

This sets a module-level variable that persists after `sprint_brief_scan` returns.

**Step 2: Add env var injection to session-start.sh**

Insert after line 217 (after `sprint_context` is assembled), reading from the cached `SPRINT_ACTIVE_JSON`:

```bash
# Sprint Composer env var injection (F4)
# If an active sprint exists, export CLAVAIN_MODEL and CLAVAIN_PHASE_BUDGET
# so downstream skills/agents get Composer-driven model routing.
# Uses SPRINT_ACTIVE_JSON cached by sprint_brief_scan (do NOT re-call sprint_find_active — iv-zlht).
if [[ -n "${CLAUDE_ENV_FILE:-}" && -n "${SPRINT_ACTIVE_JSON:-}" ]]; then
    _f4_count=$(echo "$SPRINT_ACTIVE_JSON" | jq 'length' 2>/dev/null) || _f4_count=0
    if [[ "$_f4_count" -gt 0 ]]; then
        _f4_bead=$(echo "$SPRINT_ACTIVE_JSON" | jq -r '.[0].id')
        _f4_phase=$(echo "$SPRINT_ACTIVE_JSON" | jq -r '.[0].phase')
        # _compose_find_cli available via lib-compose.sh (transitive: sprint-scan.sh → lib-sprint.sh)
        _f4_cli=$(_compose_find_cli 2>/dev/null) || _f4_cli=""
        if [[ -n "$_f4_cli" ]]; then
            _f4_envs=$("$_f4_cli" sprint-env-vars "$_f4_bead" "$_f4_phase" 2>/dev/null) || _f4_envs=""
            if [[ -n "$_f4_envs" ]]; then
                echo "$_f4_envs" >> "$CLAUDE_ENV_FILE"
            fi
        fi
    fi
fi
```

**Acceptance test:** Verify `bash -n os/clavain/hooks/session-start.sh` passes (syntax check). Note: `bash -n` does not check for undefined functions — verify manually that `_compose_find_cli` is available by confirming lib-compose.sh is sourced transitively before this block.

---

### Task 5: Integration verification [x]

**Files:** None (verification only)

**Step 1: Syntax check all modified files**

```bash
bash -n os/clavain/scripts/lib-compose.sh
bash -n os/clavain/hooks/session-start.sh
bash -n os/clavain/hooks/sprint-scan.sh
```

**Step 2: Run lib-compose bats tests**

```bash
cd os/clavain && bats tests/shell/test_lib_compose.bats
```

**Step 3: Run existing session-start bats tests (regression check)**

```bash
cd os/clavain && bats tests/shell/session_start.bats
```

**Step 4: Verify launch.md is well-formed**

Read the modified launch.md and confirm:
- Step 2.0.4 is self-contained
- Skip guards are in place at Steps 2.0.5 and 2.2
- Backward compatibility: COMPOSER_ACTIVE=0 path is unchanged
- Dispatch loop is marked as pseudocode

**Step 5: Verify Go CLI commands exist**

```bash
clavain-cli-go sprint-env-vars --help 2>&1 || true
clavain-cli-go get-artifact --help 2>&1 || true
clavain-cli-go compose --help 2>&1 || true
```

**Step 6: Verify transitive sourcing chain**

Confirm the sourcing chain: session-start.sh → sprint-scan.sh → lib-sprint.sh → lib-compose.sh. Check that `_compose_find_cli` is defined after `source "${SCRIPT_DIR}/sprint-scan.sh"` by grepping lib-sprint.sh for the lib-compose.sh source line.
