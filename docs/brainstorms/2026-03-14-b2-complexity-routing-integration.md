# Brainstorm: Apply Complexity-Aware Routing Across All Subagents

**Bead:** iv-jgdct
**Date:** 2026-03-14
**Status:** Draft

## Problem

B2 complexity-aware routing infrastructure (iv-k8xn) is fully built but has **zero production callers**. The classification engine (`routing_classify_complexity`) and override resolver (`routing_resolve_model_complex`) work correctly in tests, but no dispatch point supplies complexity signals. Every subagent gets the same model tier regardless of task difficulty.

### Root Cause

`routing_resolve_agents()` (line 1114-1118 of lib-routing.sh) already branches on `_ROUTING_CX_MODE` and calls `routing_resolve_model_complex` — but **never passes `--complexity <tier>`**. Without a tier, `routing_resolve_model_complex` hits its zero-cost bypass (line 787) and returns the base B1 result. The function exists, the branch exists, but the signal is never provided.

### Impact

- C5 tasks (architectural, multi-system) get Sonnet when they should get Opus
- C1 tasks (typo fix, config tweak) get Sonnet when Haiku suffices
- Shadow mode logs are empty because no tier is ever classified
- Cost savings from B2 are unrealized (estimated 15-30% on trivial tasks)

## Architecture

### What Exists (B2 Infrastructure)

1. **Classification**: `routing_classify_complexity --prompt-tokens N --file-count M --reasoning-depth D` → C1-C5
2. **Resolution**: `routing_resolve_model_complex --complexity C3 --phase P --agent A` → model with tier override
3. **Config**: routing.yaml `complexity:` section with thresholds and per-tier overrides
4. **Mode control**: off (zero-cost) → shadow (log-only) → enforce (apply overrides)
5. **Safety floors**: Post-complexity clamping ensures critical agents never drop below minimum

### What's Missing: Signal Collection + Injection

Each dispatch point needs to:
1. **Measure** complexity signals (token count, file count, reasoning depth)
2. **Classify** via `routing_classify_complexity`
3. **Pass** the classified tier to `routing_resolve_agents --complexity <tier>`

### Dispatch Points Inventory

| Dispatch Point | Location | Mechanism | Signal Source |
|---|---|---|---|
| flux-drive review | interflux/skills/flux-drive/phases/launch.md Step 2.0.5 | `routing_resolve_agents` | Document being reviewed (token count, file scope) |
| flux-drive research | interflux/skills/flux-drive/phases/launch.md Step 2.1-research | `routing_resolve_agents` | Research question (reasoning depth from query) |
| sprint brainstorm | clavain skills/brainstorm | Agent tool `model:` param | Task description (heuristic from bead) |
| sprint work execution | clavain skills/work | Agent tool `model:` param | Plan step complexity |
| quality-gates | clavain commands/quality-gates.md | `routing_resolve_agents` | Diff size, file count |

## Approaches

### Approach A: Add `--complexity` to `routing_resolve_agents` + caller updates

**How it works:**
1. Add `--complexity <tier>` flag to `routing_resolve_agents()`. When provided, passes it through to `routing_resolve_model_complex`.
2. Update flux-drive launch.md Step 2.0.5 to classify complexity before calling `routing_resolve_agents`.
3. Update quality-gates to classify before dispatch.

**Signal collection at flux-drive:**
```bash
# Count tokens in review target (document or diff)
prompt_tokens=$(wc -c < "$REVIEW_FILE" | awk '{print int($1/4)}')  # rough char-to-token
file_count=$(echo "$CHANGED_FILES" | wc -l)
# Reasoning depth: heuristic from document type
reasoning_depth=3  # default moderate; bump for architecture docs, security reviews
COMPLEXITY=$(routing_classify_complexity --prompt-tokens "$prompt_tokens" --file-count "$file_count" --reasoning-depth "$reasoning_depth")
MODEL_MAP=$(routing_resolve_agents --phase "$PHASE" --agents "$AGENTS" --complexity "$COMPLEXITY")
```

**Pros:** Minimal code change, uses existing infrastructure, zero-cost bypass works
**Cons:** Same tier for all agents in a batch (a C5 doc promotes all agents equally)

### Approach B: Per-agent complexity classification

**How it works:** Each agent gets its own complexity classification based on its specific domain scope, not the global document.

**Example:** For a PR touching 20 files, fd-safety might classify as C4 (security-sensitive patterns across many files) while fd-quality classifies as C2 (standard code style, well-scoped).

**Pros:** More granular, better cost optimization
**Cons:** Requires domain-aware classification (much more complex), breaks the batch model of `routing_resolve_agents`

### Approach C: Staged rollout — A first, B later

**How it works:** Ship Approach A (global complexity per batch) in shadow mode. Monitor logs for 1 week. If shadow logs show reasonable tier assignments, switch to enforce. Approach B becomes a future refinement if cost data shows per-agent granularity would help.

**Pros:** Fast to ship, safe rollout, evidence-driven refinement
**Cons:** None significant — this is the standard B2 rollout pattern

## Recommendation

**Approach C (staged rollout of A).**

The infrastructure is already designed for shadow → enforce progression. Approach A is 80% of the value with 20% of the work. Per-agent classification (B) can be added later as a B2.1 refinement if the shadow logs justify it.

### Implementation Plan (High Level)

1. **lib-routing.sh**: Add `--complexity` flag to `routing_resolve_agents()` — 5 lines
2. **flux-drive launch.md**: Add complexity classification before `routing_resolve_agents` call — 10 lines
3. **quality-gates.md**: Add complexity classification before dispatch — similar pattern
4. **Verify**: routing.yaml already has `mode: shadow` — shadow logs will appear immediately
5. **Test**: Run flux-drive on a known doc, verify shadow logs show tier classification

### Signals Heuristic

| Signal | Source | Calculation |
|---|---|---|
| `prompt_tokens` | Review target file(s) | `wc -c / 4` (char-to-token approximation) |
| `file_count` | Git diff or target file list | `wc -l` of file list |
| `reasoning_depth` | Document type + keyword heuristic | Default 3; +1 for security/architecture, -1 for formatting/typo |

### Success Criteria

- Shadow mode: `[B2-shadow]` log lines appear when flux-drive dispatches agents
- Shadow logs show reasonable tier assignments (C5 for large reviews, C1 for small ones)
- After enforce: C1/C2 tasks use Haiku, C4/C5 use Opus, C3 inherits B1 default
- Zero-cost bypass: when mode=off, no additional overhead

## Open Questions

1. Should sprint brainstorm/work phases also classify complexity? (Lower priority — these already use bead-level complexity from `/route`)
2. Should we expose complexity tier in flux-drive debug output?
3. Is char/4 a good enough token approximation, or should we use tiktoken?

## Related

- iv-k8xn (closed) — Built B2 infrastructure
- iv-i198 — B3 adaptive routing (depends on B2 being active)
- Interspect routing overrides — separate from B2, reads `.claude/routing-overrides.json`
