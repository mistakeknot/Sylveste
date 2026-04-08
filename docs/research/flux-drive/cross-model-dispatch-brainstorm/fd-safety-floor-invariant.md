### Findings Index
- P0 | SFI-1 | "Implementation Sketch" | Budget pressure override applied AFTER safety floor in the sketch — but code shows floor is last, creating ambiguity about double-downgrade
- P1 | SFI-2 | "Implementation Sketch" | _routing_downgrade function does not exist — no guarantee it respects tier ordering
- P1 | SFI-3 | "Constraints" | Project agents with min_model in agent-roles.yaml not covered by the brainstorm's safety floor discussion
- P2 | SFI-4 | "Implementation Sketch" | Namespace stripping in _routing_apply_safety_floor uses greedy `##*:` — handles `interflux:review:fd-safety` correctly, but new function must match
Verdict: needs-changes

## Summary

The brainstorm correctly identifies safety floors as "non-negotiable" and places the floor clamp as the last operation in `routing_adjust_expansion_tier`. However, analysis of the actual `_routing_apply_safety_floor` implementation in `lib-routing.sh` reveals a P0-level ambiguity: the budget pressure override could double-downgrade an agent below its floor if the function is called with an already-downgraded model. The sketch's order of operations is correct in principle (downgrade -> budget pressure -> floor clamp), but the missing `_routing_downgrade` function is a gap.

## Issues Found

### 1. [P0] SFI-1: Double-downgrade scenario under budget pressure

**File:** brainstorm lines 131-141 (implementation sketch)
**Codebase ref:** `os/Clavain/scripts/lib-routing.sh`, lines 65-90 (`_routing_apply_safety_floor`)

The sketch applies operations in order: (1) expansion score downgrade, (2) budget pressure downgrade, (3) safety floor clamp. This ordering is correct — the floor is last, so it can always clamp up. **The invariant holds as written.**

However, the P0 concern is about *implementation drift*: the brainstorm says "Safety floor (always last)" but doesn't enforce this structurally. If a future maintainer adds a post-floor adjustment (e.g., a cost cap), the invariant breaks silently. The existing `_routing_apply_safety_floor` in lib-routing.sh is called at the end of `routing_resolve_model` (line 710) — the same "last operation" pattern. But `routing_adjust_expansion_tier` is a NEW function that creates a second code path where the floor must also be last.

**Failure scenario:** A reviewer agent (fd-correctness, min_model=sonnet) starts at sonnet. Score=1 downgrades to haiku. Budget pressure="high" would downgrade again — but haiku can't go lower. Floor clamps back to sonnet. This works. But if `_routing_downgrade("haiku")` returns something unexpected (empty string? error?), the floor lookup on an empty model would return the empty string (line 67 of lib-routing.sh: `[[ -z "$model" ]] && { echo "$model"; return 0; }` — returns empty on empty input).

**Smallest fix:** Add a guard in `routing_adjust_expansion_tier`: after all downgrades but before the floor, assert `[[ -n "$model" ]] || model="haiku"`. And add a comment: `# INVARIANT: safety floor must be the LAST operation. Do not add adjustments after this line.`

### 2. [P1] SFI-2: _routing_downgrade does not exist yet

**File:** brainstorm line 131, Scope line 185
**Codebase ref:** `os/Clavain/scripts/lib-routing.sh` (searched — no `_routing_downgrade` function exists)

The brainstorm lists `_routing_downgrade()` as in-scope but provides no implementation. The function must enforce tier ordering: opus -> sonnet -> haiku, never skipping a tier (opus -> haiku directly). It must also handle edge cases:
- What does `_routing_downgrade("haiku")` return? Haiku (already lowest)? Error?
- What does `_routing_downgrade("local:qwen3-8b")` return? lib-routing.sh maps this to tier 1 (haiku-equivalent) — the downgrade function needs to handle local model names.
- What does `_routing_downgrade("")` return?

**Existing pattern:** `_routing_model_tier()` at line 48 provides the tier ordering. The downgrade function should use this:
```bash
_routing_downgrade() {
  local model="$1"
  case "$(_routing_model_tier "$model")" in
    3) echo "sonnet" ;;  # opus -> sonnet
    2) echo "haiku" ;;   # sonnet -> haiku
    1) echo "$model" ;;  # haiku -> haiku (floor)
    0) echo "$model" ;;  # unknown -> unchanged
  esac
}
```

### 3. [P1] SFI-3: Project agents not covered by safety floor discussion

**File:** brainstorm "Constraints" section, lines 174-179
**Codebase ref:** `interverse/interflux/config/flux-drive/agent-roles.yaml`

The brainstorm discusses safety floors for fd-safety and fd-correctness (the exempt agents from budget.yaml). But agent-roles.yaml declares min_model for TWO roles:
- `planner` (fd-architecture, fd-systems): min_model = sonnet
- `reviewer` (fd-correctness, fd-quality, fd-safety): min_model = sonnet

This means fd-architecture, fd-systems, and fd-quality ALSO have safety floors at sonnet. The brainstorm's implementation sketch would correctly clamp these (since `_routing_apply_safety_floor` reads from agent-roles.yaml), but the brainstorm's narrative only mentions fd-safety and fd-correctness as having floors. If a reviewer reads the brainstorm without checking agent-roles.yaml, they might think only 2 agents have floors when actually 5 do.

Additionally, Project Agents (generated by flux-gen, stored in `.claude/agents/fd-*.md`) have no entries in agent-roles.yaml. The floor lookup would find nothing and skip clamping. This is probably fine for generated agents, but the brainstorm should state this explicitly.

**Smallest fix:** Add to Constraints: "Safety floors apply to all agents with min_model declared in agent-roles.yaml (currently: planner and reviewer roles — 5 agents). Project-specific agents have no declared floor and can be freely downgraded."

### 4. [P2] SFI-4: Namespace stripping consistency

**File:** `os/Clavain/scripts/lib-routing.sh`, line 72

The existing `_routing_apply_safety_floor` uses `floor_key="${floor_key##*:}"` (greedy strip) to handle namespaced agent IDs like `interflux:review:fd-safety` -> `fd-safety`. The new `routing_adjust_expansion_tier` function in the brainstorm receives `agent` as its first parameter. If the caller passes a namespaced ID, the function must strip it the same way before passing to `_routing_apply_safety_floor`.

The sketch at line 140 calls `_routing_apply_safety_floor "$agent" "$model" "expansion"` — if `$agent` is already the short name, this works. If it's namespaced, `_routing_apply_safety_floor` handles the stripping internally. So this is actually safe as-is. Noting for completeness.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 4 (P0: 1, P1: 2, P2: 1)
SUMMARY: Safety floor ordering is correct in principle but the missing _routing_downgrade function and empty-model edge case create a P0 path where the floor could be bypassed. The _routing_downgrade implementation should mirror _routing_model_tier for consistency.
---
<!-- flux-drive:complete -->
