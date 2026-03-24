---
artifact_type: reflection
bead: Demarch-6i0.11
stage: reflect
category: patterns
title: Per-project config — deep-copy merge and project root detection
---

# Per-Project Config Patterns

Sprint: Demarch-6i0.11 (Per-project config directory `.skaffen/`)
Complexity: Estimated 2 (simple), actual 2 — plan review was the valuable step, not execution.

## What Was Built

Added per-project `.skaffen/` directory support to Skaffen. Three merge layers (routing config, plugin config, shared `initConfig()` helper) give project-specific overrides for model routing and MCP plugins. Project root detected via git root + `.skaffen/` directory presence, with walk-up fallback.

## Key Pattern: Deep-Copy Map Merge

Go struct copies are shallow — map fields alias the original. `MergeConfig` must allocate fresh maps:

```go
merged := &Config{
    Phases: make(map[tool.Phase]string, len(base.Phases)+len(project.Phases)),
}
for k, v := range base.Phases { merged.Phases[k] = v }
for k, v := range project.Phases { merged.Phases[k] = v }
```

This was caught by plan review (flux-drive) BEFORE implementation. The `TestMergeConfigNoAlias` test validates it — mutating merged must not affect base.

**When to apply:** Any Go function that merges two config structs containing maps. The `*base` copy trick (`merged := *base`) shares all map references.

## Key Pattern: Multi-Path Config Resolution

Return `[]string` of paths (not a single merged config) from the discovery layer. Let the caller load and merge:

```go
func (c *Config) RoutingPaths() []string { /* user-global, then per-project */ }
```

This keeps the config package path-only (no routing domain knowledge) and lets the caller control merge order.

## Lesson: Plan Review Catches More Than Code Review

The flux-drive plan review (Step 4) caught 2 P0 bugs and 5 P1 issues — all fixed before any code was written. The implementation was then mechanical and passed all tests on first run. For simple features, the plan review IS the quality gate. Code review found nothing new.

## Lesson: Stale Quality Gate Outputs

Quality gate agent outputs persist across sprints in `.clavain/quality-gates/`. When agents fail to overwrite (e.g., due to timing or naming), you get ghost findings from prior reviews. Consider clearing the output directory at the start of each quality gates run, or namespacing by bead ID.

## Complexity Calibration

- Estimated: 2/5 (simple) — correct
- Actual effort: ~30 min implementation, all tests passed first try
- The full sprint workflow (10 steps) was overkill for this — a `/work` dispatch would have been more efficient
- Sprint steps 1-4 (brainstorm, strategy, plan, plan-review) were valuable; steps 7-9 (quality-gates, resolve, reflect) added overhead without catching new issues
