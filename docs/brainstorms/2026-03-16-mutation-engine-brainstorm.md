# Systematic Mutation Engine for Autoresearch

**Bead:** Demarch-vd1
**Date:** 2026-03-16
**Status:** Brainstorm

## Problem

The current autoresearch system relies entirely on LLM-generated hypotheses via free-text `ideas` in the campaign YAML. This works for creative exploration but has three weaknesses:

1. **Non-reproducible** — the same idea string produces different code changes across sessions
2. **Non-composable** — can't systematically combine mutations (e.g., "try all normalization types × all learning rates")
3. **Non-trackable** — you can't distinguish "parameter X was swept from 0.1 to 0.5" from "the agent happened to try two values"

Hyperspace AGI solved this with 14 deterministic mutation types that drive 1,369+ experiments overnight. Each mutation is a structured operation, not a prose description.

## Design Space

### What is a mutation?

A mutation is a **structured code transformation** that the agent can execute deterministically. Unlike free-text ideas, mutations have:

- **Type** — what kind of change (sweep a parameter, swap an implementation, toggle a flag)
- **Target** — where in the code (file path, function name, config key)
- **Parameters** — what values to try (range, alternatives, scale factors)
- **Identity** — a unique string for tracking (e.g., `sweep:threshold:0.3`)

### Mutation types

| Type | Description | YAML Example | Generated Experiments |
|------|-------------|--------------|----------------------|
| `parameter_sweep` | Try a range of values for a numeric parameter | `{param: "threshold", file: "router.go", range: [0.1, 0.5], step: 0.05}` | 9 experiments |
| `swap` | Replace one implementation with another | `{target: "LayerNorm", replacement: "RMSNorm", files: ["*.go"]}` | 1 experiment |
| `toggle` | Enable/disable a boolean flag | `{flag: "cache_enabled", file: "config.go"}` | 1 experiment (flip current state) |
| `scale` | Multiply a numeric value by factors | `{param: "batch_size", file: "train.go", factors: [0.5, 2.0, 4.0]}` | 3 experiments |
| `remove` | Delete a code block or feature | `{target: "Orient phase skip", file: "agent.go", lines: "45-52"}` | 1 experiment |
| `reorder` | Change execution order of items | `{items: ["phase_a", "phase_b", "phase_c"], file: "pipeline.go"}` | 6 experiments (permutations, capped) |
| `enum_sweep` | Try each value from a list | `{param: "model", values: ["haiku", "sonnet", "opus"], file: "router.go"}` | 3 experiments |

### How mutations interact with ideas

Mutations and ideas are **complementary, not exclusive**:

```yaml
ideas:
  - "Refactor the hot loop to reduce allocations"
  - "Use sync.Pool for temporary buffers"

mutations:
  - type: parameter_sweep
    param: context_reserve
    file: internal/session/context.go
    range: [2048, 8192]
    step: 1024
  - type: swap
    target: json.Marshal
    replacement: jsoniter.Marshal
    files: ["internal/tool/*.go"]
```

The agent processes mutations first (deterministic, exhaustive), then moves to ideas (creative, open-ended). This gives structure to the early campaign and creativity to the tail.

### Mutation expansion

A `parameter_sweep` with `range: [0.1, 0.5], step: 0.05` expands to 9 individual experiments at campaign load time. Each gets a unique ID: `mutation:parameter_sweep:threshold:0.10`, `mutation:parameter_sweep:threshold:0.15`, etc.

The `Segment` tracks which mutations have been tried (by ID) so resume correctly skips completed mutations.

### Where mutations live in the architecture

```
Campaign YAML                   (mutations: [...])
    ↓ LoadCampaign
Campaign struct                 (Mutations []Mutation)
    ↓ ExpandMutations
[]ExpandedMutation              (one per experiment to run)
    ↓ init_experiment reads
Segment.PendingMutations        (unexpanded mutations minus completed)
    ↓ skill picks next
init_experiment returns          (next_mutation: {...} or null)
    ↓ agent executes
run_experiment / log_experiment  (mutation_id in ExperimentRecord)
```

### Key design decisions

**D1: Mutations expand at load time, not at experiment time.**
The full list of experiments is known upfront. The skill can show "12 mutations + 3 ideas remaining" in the TUI. Resume is deterministic — check which mutation IDs are in the JSONL, skip those.

**D2: Mutation identity is content-addressable.**
`mutation:parameter_sweep:threshold:0.15` — type:param:value. Two campaigns with the same mutation produce the same ID. This enables cross-campaign deduplication (future: Demarch-2ik).

**D3: The agent still makes the code changes.**
Mutations describe WHAT to change, not HOW. The agent reads the mutation spec and implements it using Edit/Write tools. This preserves the agent's ability to handle complex mutations (e.g., swapping an entire normalization implementation) while giving it precise direction.

**D4: Composable mutations are v2.**
Cartesian products (sweep × swap) generate combinatorial explosions. v1 is flat list — each mutation is independent. v2 adds `compose: [{type: sweep, ...}, {type: swap, ...}]` with product generation.

### ExperimentRecord extension

Add `mutation_id` and `mutation_type` to track which mutation produced each experiment:

```go
type ExperimentRecord struct {
    // ... existing fields ...
    MutationID   string `json:"mutation_id,omitempty"`
    MutationType string `json:"mutation_type,omitempty"`
}
```

### init_experiment extension

When mutations exist and haven't all been tried, `init_experiment` returns the next mutation in its response:

```json
{
    "campaign_name": "routing-opt",
    "resumed": false,
    "next_mutation": {
        "id": "mutation:parameter_sweep:threshold:0.15",
        "type": "parameter_sweep",
        "description": "Set threshold to 0.15 in internal/router/router.go",
        "param": "threshold",
        "value": 0.15,
        "file": "internal/router/router.go"
    }
}
```

When all mutations are exhausted, `next_mutation` is null and the agent falls back to ideas.

### Skill changes

The SKILL.md loop changes from "Pick an idea" to:

1. Check `next_mutation` from init/log response
2. If mutation: execute the structured change (edit the file, set the value)
3. If no mutation: fall back to ideas list
4. If no ideas: generate hypotheses or end campaign

## Open Questions

1. **Max permutations for `reorder`?** Factorial growth — cap at 6 (720 permutations for 6 items is too many). Default cap: `max_permutations: 24`.

2. **Should mutations specify exact code patterns?** e.g., `{target: "threshold := 0.3", replacement: "threshold := {value}"}`. This makes mutations truly deterministic but brittle to code changes. Compromise: specify file + param name, let the agent find and change it.

3. **Mutation ordering strategy?** Options: sequential (as listed), random, adaptive (try middle of sweep first, then binary search toward optimum). v1: sequential. v2: adaptive.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Sweep generates too many experiments | Medium | Medium | Budget cap still applies; warn if expansion > 50 |
| Agent misinterprets mutation spec | Low | Low | Mutation spec is structured, not ambiguous |
| Mutation identity collision | Low | Low | Content-addressable IDs are deterministic |
