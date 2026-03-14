# Plan: B2 Complexity-Aware Routing Integration

**Bead:** iv-jgdct
**PRD:** docs/prds/2026-03-14-b2-complexity-routing-integration.md
**Date:** 2026-03-14
**Revised:** 2026-03-14 (post flux-drive plan review — addresses A1, A2, F1, F3, A5)

## Overview

Wire complexity signal collection into production dispatch points so the existing B2 classification (C1-C5) and model override logic actually runs. Two changes: (1) extend `routing_resolve_agents` to accept raw complexity signals and classify internally, fixing the fast-path guard by moving `_routing_load_cache` before the guard, and (2) update flux-drive launch to pass signal measurements to `routing_resolve_agents`.

## Review Findings Addressed

| Finding | Fix |
|---|---|
| A1/F1: Arg-scan loop can't distinguish flags from values | Eliminated — move `_routing_load_cache` before fast path, check `_ROUTING_CX_MODE` directly |
| A2: Classification in launch.md splits routing contract | `routing_resolve_agents` accepts `--prompt-tokens/--file-count/--reasoning-depth` and classifies internally |
| F3: `REASONING_DEPTH=3` guarantees C3+ on every call | Use `REASONING_DEPTH=1` as neutral baseline in launch.md |
| A5: Wrong test path | Fixed to `tests/shell/test_routing.bats` |
| F2: Fast path not bypassed when mode=shadow without explicit flag | Fixed by checking `_ROUTING_CX_MODE` in fast-path guard |

## Steps

### Step 1: Extend `routing_resolve_agents` with signal inputs and fix fast-path guard

**File:** `os/Clavain/scripts/lib-routing.sh`

**Change 1a — Move `_routing_load_cache` before fast-path guard:**

The cache load is idempotent (guarded by `_ROUTING_CACHE_POPULATED`). Moving it before the fast-path makes `_ROUTING_CX_MODE` available for the guard condition.

```bash
routing_resolve_agents() {
  _routing_load_cache  # Moved here — idempotent, makes _ROUTING_CX_MODE available

  # Fast path: delegate to compiled Go router when available.
  # Skips when CLAVAIN_RUN_ID is set, complexity mode is active, or Go router unavailable.
  if [[ -z "${CLAVAIN_RUN_ID:-}" && "${_ROUTING_CX_MODE:-off}" == "off" ]] && command -v ic >/dev/null 2>&1; then
    # ... existing fast path (unchanged) ...
  fi

  # Remove duplicate _routing_load_cache call that was here before
```

**Change 1b — Add signal flags to arg parser:**

```bash
local phase="" agents_csv="" category_override=""
local cx_prompt_tokens="" cx_file_count="" cx_reasoning_depth=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)            phase="$2"; shift 2 ;;
    --agents)           agents_csv="$2"; shift 2 ;;
    --category)         category_override="$2"; shift 2 ;;
    --prompt-tokens)    cx_prompt_tokens="$2"; shift 2 ;;
    --file-count)       cx_file_count="$2"; shift 2 ;;
    --reasoning-depth)  cx_reasoning_depth="$2"; shift 2 ;;
    *) shift ;;
  esac
done
```

**Change 1c — Classify internally when signals are provided:**

After the arg parser, before the per-agent loop:

```bash
# B2: classify complexity from raw signals when any are provided
local complexity=""
if [[ -n "$cx_prompt_tokens" || -n "$cx_file_count" || -n "$cx_reasoning_depth" ]]; then
  local cx_args=()
  [[ -n "$cx_prompt_tokens" ]]   && cx_args+=(--prompt-tokens "$cx_prompt_tokens")
  [[ -n "$cx_file_count" ]]      && cx_args+=(--file-count "$cx_file_count")
  [[ -n "$cx_reasoning_depth" ]] && cx_args+=(--reasoning-depth "$cx_reasoning_depth")
  complexity="$(routing_classify_complexity "${cx_args[@]}")"
fi
```

**Change 1d — Pass classified tier to resolver:**

Replace lines 1109-1118 with:

```bash
# Resolve model — use complexity-aware resolver when tier is available or mode is active
local model=""
local resolve_args=(--phase "$phase" --agent "$agent_id")
[[ -n "$category" ]] && resolve_args+=(--category "$category")

if [[ -n "$complexity" ]]; then
  model="$(routing_resolve_model_complex --complexity "$complexity" "${resolve_args[@]}")"
elif [[ "${_ROUTING_CX_MODE:-off}" != "off" ]]; then
  model="$(routing_resolve_model_complex --complexity "" "${resolve_args[@]}")"
else
  model="$(routing_resolve_model "${resolve_args[@]}")"
fi
```

**Verify:**
```bash
source os/Clavain/scripts/lib-routing.sh
# Should show [B2-shadow] log lines on stderr (mode is shadow)
routing_resolve_agents --phase executing --agents "fd-safety,fd-architecture" --prompt-tokens 5000 --file-count 20 --reasoning-depth 1
# Without signals, behavior is identical to current (B1 only via Go fast path)
routing_resolve_agents --phase executing --agents "fd-safety,fd-architecture"
```

### Step 2: Update flux-drive launch to pass signals

**File:** `interverse/interflux/skills/flux-drive/phases/launch.md` Step 2.0.5

After sourcing lib-routing.sh and determining phase, add signal measurement. Classification happens inside `routing_resolve_agents` — launch.md only measures and passes raw numbers.

**New content between current steps 2 (determine phase) and 3 (call routing_resolve_agents):**

```markdown
2b. **Measure review complexity signals** (B2 — progressive enhancement):
   Measure complexity signals from the review target for B2 routing. These are passed as raw values — classification happens inside the routing library.
   ```bash
   # Approximate token count from review file size (chars / 4)
   REVIEW_TOKENS=0
   if [[ -n "${REVIEW_FILE:-}" && -f "$REVIEW_FILE" ]]; then
     REVIEW_TOKENS=$(( $(wc -c < "$REVIEW_FILE") / 4 ))
   fi
   # File count from changed files (newline-separated diff output)
   REVIEW_FILE_COUNT=$(git diff --name-only HEAD 2>/dev/null | wc -l || echo "0")
   # Reasoning depth: neutral baseline (let token count and file count drive classification)
   REVIEW_DEPTH=1
   ```
```

**Update the `routing_resolve_agents` call:**

```bash
# Before:
MODEL_MAP=$(routing_resolve_agents --phase "$PHASE" --agents "fd-safety,fd-architecture,fd-quality")

# After:
MODEL_MAP=$(routing_resolve_agents --phase "$PHASE" --agents "$TRIAGED_AGENTS" \
  --prompt-tokens "$REVIEW_TOKENS" --file-count "$REVIEW_FILE_COUNT" --reasoning-depth "$REVIEW_DEPTH")
```

**Update debug output:**

```
Model routing: phase=executing, tokens=${REVIEW_TOKENS}, files=${REVIEW_FILE_COUNT}
  fd-safety=sonnet, fd-architecture=sonnet, fd-quality=sonnet
```

**Verify:** Run flux-drive on a document and check stderr for `[B2-shadow]` lines.

### Step 3: Update tests

**File:** `os/Clavain/tests/shell/test_routing.bats`

Add tests:

1. `routing_resolve_agents with --prompt-tokens classifies and passes tier to resolver`
2. `routing_resolve_agents with --prompt-tokens 5000 classifies as C4/C5 in shadow mode`
3. `routing_resolve_agents with --prompt-tokens 100 classifies as C1 in shadow mode`
4. `routing_resolve_agents without signal flags behaves as before (B1 only)`
5. `routing_resolve_agents skips ic fast path when complexity mode is shadow`

**Verify:** `bats os/Clavain/tests/shell/test_routing.bats`

### Step 4: Update SKILL-compact.md reference

**File:** `interverse/interflux/skills/flux-drive/SKILL-compact.md`

Update Step 2.0.5 reference:

```
- Step 2.0.5: Measure review complexity signals (token count, file count), then resolve agent models via `routing_resolve_agents()` with `--prompt-tokens/--file-count/--reasoning-depth` from Clavain's `lib-routing.sh`. Classification happens inside the library. Pass `model:` param to each Agent tool call. Fallback: skip if lib-routing.sh unavailable (agents use frontmatter defaults).
```

### Step 5: Add enforce-mode prerequisite comment to routing.yaml

**File:** `os/Clavain/config/routing.yaml`

Add a comment under `complexity.mode`:

```yaml
complexity:
  mode: shadow  # Before setting enforce: verify quality-gates integration (iv-jgdct)
```

## Files Modified

| File | Change |
|---|---|
| `os/Clavain/scripts/lib-routing.sh` | Move cache load, fix fast-path guard, add signal flags, classify internally |
| `interverse/interflux/skills/flux-drive/phases/launch.md` | Pass signal measurements to `routing_resolve_agents` |
| `interverse/interflux/skills/flux-drive/SKILL-compact.md` | Update reference |
| `os/Clavain/tests/shell/test_routing.bats` | Add tests for signal flags and fast-path bypass |
| `os/Clavain/config/routing.yaml` | Add enforce-mode prerequisite comment |

## Risk Assessment

- **Low risk:** All changes are additive. Without signal flags, behavior is identical to current. Shadow mode prevents any actual model changes.
- **Fast-path bypass:** When complexity mode is shadow/enforce, the Go fast path is skipped. This adds ~50ms per dispatch. Acceptable for validation.
- **No threshold changes:** routing.yaml thresholds and overrides are unchanged.
- **Contract ownership:** Classification stays in lib-routing.sh. Callers only measure and pass raw numbers.
