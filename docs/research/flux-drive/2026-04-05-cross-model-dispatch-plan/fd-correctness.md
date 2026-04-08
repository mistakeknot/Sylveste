---
agent: fd-correctness
plan: docs/plans/2026-04-05-cross-model-dispatch.md
date: 2026-04-05
---
# fd-correctness Findings: Cross-Model Dispatch Plan

## F-C1 [P1] `_routing_agent_field()` duplicates existing `_routing_find_roles_config()`

**Location:** Task 1.4, file search logic

`_routing_find_roles_config()` already exists in lib-routing.sh (line 124) with a correct, tested search path list using `CLAVAIN_ROLES_CONFIG`, `INTERFLUX_ROOT`, and relative paths. Task 1.4 proposes a new search block inside `_routing_agent_field()` using different env vars (`CLAVAIN_INTERFLUX_CONFIG`, `_ROUTING_CONFIG_PATH`) plus a `find` glob fallback that uses a different path pattern than `_routing_find_roles_config()`.

**Consequence:** Two divergent file-location strategies for the same file. If the roles file moves or a new env var is added, only one will be updated. The `find` glob pattern for plugin cache also doesn't match the actual path structure used by `_routing_find_roles_config()`.

**Fix:** Replace the custom search block in `_routing_agent_field()` with a call to `_routing_find_roles_config()`:
```bash
local roles_file
roles_file=$(_routing_find_roles_config) || roles_file=""
[[ -z "$roles_file" || ! -f "$roles_file" ]] && return 0
```

---

## F-C2 [P1] PRD AC "local models→unchanged" vs plan's local model downgrade behavior

**Location:** Task 1.3, `_routing_downgrade()`, PRD F1 AC

PRD F1 AC states: "`_routing_downgrade()` handles ... **local models→unchanged**"

The plan implements `local:qwen3-30b` → `local:qwen3-8b` and `local:qwen2.5-72b` → `local:qwen3-8b`. These ARE downgrades (sonnet-equivalent → haiku-equivalent). The PRD says "unchanged."

**Consequence:** If the PRD is correct, local model users should not experience tier downgrades. If the plan is correct, the PRD AC is wrong. This is an unresolved contradiction between the two artifacts.

**Recommendation:** Clarify intent and update whichever document is wrong. If local models ARE meant to downgrade, the PRD AC needs to say "local models downgrade within tier" not "unchanged."

---

## F-C3 [P1] Shell injection in `_routing_agent_field()` Python subprocess string interpolation

**Location:** Task 1.4, python3 inline script

The function interpolates `$short_name` and `$field` directly into the Python one-liner passed to `python3 -c`. If an agent name contained special characters (single quotes, semicolons), the embedded Python syntax would break or execute unintended code. The field name `$field` is caller-controlled.

**Consequence:** Low probability but the pattern is unsafe by construction. It also fails silently if an agent name contains a single quote (returning empty string instead of the field value).

**Fix:** Pass values via environment variables rather than string interpolation into the Python source code. The roles file path should also be passed as `sys.argv[1]` rather than interpolated.

---

## F-C4 [P2] `_routing_model_tier` comparison using `-ge` on subshell output — correct but undocumented

**Location:** Task 1.5, score=3 upgrade block

```bash
if [[ -z "$max_ceil" || "$(_routing_model_tier "$max_ceil")" -ge 2 ]]; then
```

This works correctly: `_routing_model_tier` echoes a numeric string, `-ge` does integer comparison. For unknown ceiling values, `_routing_model_tier` returns "0", and `0 -ge 2` is false → upgrade blocked. This is the correct fallback behavior.

**Finding:** Logic is correct but the comment should clarify that "0 (unknown tier) blocks upgrade" to prevent future misreadings. P3 documentation gap.

---

## F-C5 [P2] Empty model guard is unreachable at its current placement

**Location:** Task 1.5, step 4

The empty model guard `[[ -n "$model" ]] || model="haiku"` is placed after:
1. Score adjust (step 1) — always outputs a known model
2. Budget pressure (step 2) — calls `_routing_downgrade` which handles empty input (returns "haiku")
3. Constitutional floor (step 3) — if `$model` were empty, `_routing_model_tier ""` = 0, which is less than any floor tier, so the floor would clamp `model` to `$const_floor` (non-empty)

By step 4, `$model` is guaranteed non-empty by the prior steps. The guard is functionally unreachable.

**Recommendation:** Move the guard to be the very first line of the function (before any processing) as the stated intent is "before safety floor." This makes the defensive check actually meaningful.

---

## F-C6 [P2] F5 dispatch log missing "constitutional floor status" (PRD AC gap)

**Location:** Task 4.1, log format; PRD F5 AC

PRD F5 AC: "Dispatch log includes: domain_complexity, **constitutional floor status**, pool audit result"

Task 4.1 log format captures safety floor clamping with a shield symbol but has no explicit marker for constitutional floor clamping (the `min_model` check in step 3). The `{reason}` field is undefined — it might include constitutional floor, but it is not specified.

**Fix:** Add an explicit `[const-floor]` tag in the `{reason}` field when constitutional floor clamps the model, separate from the safety floor marker.

---

## F-C7 [P3] Final validation fallback to original `$2` after safety floor already ran

**Location:** Task 1.5, step 6

If final validation fails, the function falls back to `$2` (original model). But step 5 (safety floor) already ran and produced the value now in `$model`. If safety floor returned an unexpected value that triggered step 6, falling back to `$2` (the pre-floor original) might bypass the safety floor. Fallback to `haiku` would be a safer absolute floor.

## Summary

| ID | Severity | Topic |
|----|----------|-------|
| F-C1 | P1 | Duplicate file search duplicates `_routing_find_roles_config()` |
| F-C2 | P1 | PRD AC "local models unchanged" contradicts plan's downgrade behavior |
| F-C3 | P1 | Unsafe string interpolation in python3 subprocess |
| F-C4 | P3 | Minor documentation gap on tier comparison semantics |
| F-C5 | P2 | Empty model guard is unreachable at its stated placement |
| F-C6 | P2 | F5 log missing constitutional floor status marker (PRD AC gap) |
| F-C7 | P3 | Final validation fallback to original model may bypass safety floor |
