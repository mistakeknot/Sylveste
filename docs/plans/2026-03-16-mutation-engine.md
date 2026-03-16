---
artifact_type: plan
bead: Demarch-vd1
stage: design
requirements:
  - D1: Mutation types in Campaign YAML
  - D2: ExperimentRecord extension
  - D3: Segment mutation tracking
  - D4: init_experiment response extension
  - D5: Skill update
---
# Mutation Engine Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans

**Bead:** Demarch-vd1
**Goal:** Add structured, deterministic mutation types to autoresearch campaigns — parameter sweeps, swaps, toggles, scales, removes, reorders, enum sweeps.
**Architecture:** Extend `internal/experiment/campaign.go` with mutation types + expansion. Extend `store.go` with mutation tracking. Extend `internal/tool/experiment_init.go` with next_mutation response.
**PRD:** `docs/specs/2026-03-16-mutation-engine-prd.md`

## Must-Haves
- **Truths**: Mutations expand deterministically. IDs are content-addressable. Resume skips completed mutations. Existing campaigns without mutations work unchanged.
- **Artifacts**: `Mutation`, `ExpandedMutation` types in `campaign.go`. `MutationID`/`MutationType` fields on `ExperimentRecord`. `NextMutation()` on `Segment`.
- **Key Links**: Campaign.Mutations → ExpandMutations() → Segment.pendingMutations → init_experiment returns next → agent executes → log_experiment records mutation_id

### Task 1: Mutation Types and Expansion
**Files:**
- Create: `os/Skaffen/internal/experiment/mutation.go`
- Create: `os/Skaffen/internal/experiment/mutation_test.go`
- Modify: `os/Skaffen/internal/experiment/campaign.go` (add Mutations field)

**Step 1:** Define mutation types:
```go
type MutationType string
const (
    MutationParameterSweep MutationType = "parameter_sweep"
    MutationSwap           MutationType = "swap"
    MutationToggle         MutationType = "toggle"
    MutationScale          MutationType = "scale"
    MutationRemove         MutationType = "remove"
    MutationReorder        MutationType = "reorder"
    MutationEnumSweep      MutationType = "enum_sweep"
)
```

**Step 2:** Define `Mutation` struct with type discriminator and type-specific fields:
```go
type Mutation struct {
    Type           MutationType `yaml:"type"`
    Param          string       `yaml:"param,omitempty"`
    File           string       `yaml:"file,omitempty"`
    Files          []string     `yaml:"files,omitempty"`
    Range          [2]float64   `yaml:"range,omitempty"`
    Step           float64      `yaml:"step,omitempty"`
    Values         []string     `yaml:"values,omitempty"`
    Target         string       `yaml:"target,omitempty"`
    Replacement    string       `yaml:"replacement,omitempty"`
    Flag           string       `yaml:"flag,omitempty"`
    Factors        []float64    `yaml:"factors,omitempty"`
    Items          []string     `yaml:"items,omitempty"`
    Lines          string       `yaml:"lines,omitempty"`
    MaxPermutations int         `yaml:"max_permutations,omitempty"`
    Description    string       `yaml:"description,omitempty"`
}
```

**Step 3:** Define `ExpandedMutation` — one per concrete experiment:
```go
type ExpandedMutation struct {
    ID          string            `json:"id"`
    Type        MutationType      `json:"type"`
    Description string            `json:"description"`
    Params      map[string]any    `json:"params"`
}
```

**Step 4:** Implement `ExpandMutations(mutations []Mutation) ([]ExpandedMutation, error)`:
- `parameter_sweep`: iterate range with step, generate ID `mutation:parameter_sweep:{param}:{value}`
- `swap`: single experiment, ID `mutation:swap:{target}:{replacement}`
- `toggle`: single experiment, ID `mutation:toggle:{flag}`
- `scale`: one per factor, ID `mutation:scale:{param}:{factor}`
- `remove`: single experiment, ID `mutation:remove:{target}`
- `reorder`: generate permutations up to `max_permutations` (default 24), ID `mutation:reorder:{items_hash}`
- `enum_sweep`: one per value, ID `mutation:enum_sweep:{param}:{value}`
- Warn to stderr if total expanded mutations > 50

**Step 5:** Validate mutations: type must be one of the 7, required fields per type.

**Step 6:** Tests: expand parameter_sweep produces correct count, IDs are deterministic, reorder respects max_permutations, invalid type errors, empty mutations returns empty slice.

<verify>
- run: cd os/Skaffen && go test -race ./internal/experiment/ -run TestMutation -count=1
  expect: exit 0
- run: cd os/Skaffen && go vet ./internal/experiment/
  expect: exit 0
</verify>

### Task 2: Campaign Extension
**Files:**
- Modify: `os/Skaffen/internal/experiment/campaign.go`
- Modify: `os/Skaffen/internal/experiment/campaign_test.go`

**Step 1:** Add `Mutations []Mutation` field to `Campaign` struct (after `Ideas`).

**Step 2:** In `validate()`, call `validateMutations()` for each mutation.

**Step 3:** In `LoadCampaign()`, after validation, expand mutations via `ExpandMutations()` and store on Campaign: add `ExpandedMutations []ExpandedMutation` field (computed, not from YAML).

**Step 4:** Add test with campaign YAML that includes mutations. Verify backward compat: existing testdata/routing-opt.yaml (no mutations) still loads fine.

<verify>
- run: cd os/Skaffen && go test -race ./internal/experiment/ -run TestCampaign -count=1
  expect: exit 0
- run: cd os/Skaffen && go test -race ./internal/experiment/ -run TestLoadCampaign -count=1
  expect: exit 0
</verify>

### Task 3: ExperimentRecord + Segment Extension
**Files:**
- Modify: `os/Skaffen/internal/experiment/store.go`
- Modify: `os/Skaffen/internal/experiment/store_test.go`

**Step 1:** Add `MutationID string` and `MutationType string` to `ExperimentRecord` (omitempty for backward compat).

**Step 2:** Add mutation tracking to `Segment`:
- `completedMutations map[string]bool` — populated from JSONL on resume
- `pendingMutations []ExpandedMutation` — set by caller after OpenSegment
- `SetPendingMutations(all []ExpandedMutation)` — filters out completed, stores remainder
- `NextMutation() *ExpandedMutation` — returns first pending, or nil

**Step 3:** In `LoadSegment`, collect `MutationID` from each experiment record into `completedMutations`.

**Step 4:** Extend `Snapshot` with `PendingMutations int` count.

**Step 5:** In `LogExperiment`, if `rec.MutationID != ""`, add to `completedMutations` and shift `pendingMutations`.

**Step 6:** Tests: SetPendingMutations filters completed, NextMutation returns first pending, LogExperiment with mutation_id marks complete, resume reconstructs completedMutations correctly.

<verify>
- run: cd os/Skaffen && go test -race ./internal/experiment/ -run TestStore -count=1
  expect: exit 0
</verify>

### Task 4: init_experiment Response Extension
**Files:**
- Modify: `os/Skaffen/internal/tool/experiment_init.go`

**Step 1:** After opening/resuming segment, call `segment.SetPendingMutations(campaign.ExpandedMutations)`.

**Step 2:** Call `segment.NextMutation()`. If non-nil, include in response as `next_mutation` object.

**Step 3:** Add `NextMutation *ExpandedMutation` to `initResult` struct (omitempty).

**Step 4:** Update status message: if mutations pending, show "N mutations + M ideas remaining".

<verify>
- run: cd os/Skaffen && go build ./internal/tool/
  expect: exit 0
</verify>

### Task 5: log_experiment Mutation Tracking
**Files:**
- Modify: `os/Skaffen/internal/tool/experiment_log.go`

**Step 1:** Add `mutation_id` and `mutation_type` to `logParams` schema (optional fields).

**Step 2:** Pass through to `ExperimentRecord` when logging.

**Step 3:** After logging, call `segment.NextMutation()` and include in response as `next_mutation` (so the skill knows what's next without calling init again).

**Step 4:** Add `NextMutation *ExpandedMutation` to `logResult` struct (omitempty).

<verify>
- run: cd os/Skaffen && go build ./internal/tool/
  expect: exit 0
</verify>

### Task 6: Skill Update
**Files:**
- Modify: `os/Clavain/skills/autoresearch/SKILL.md`

**Step 1:** Update "Pick an idea" section to check `next_mutation` first:

```markdown
### 1. Pick next experiment
Check `next_mutation` from init_experiment or log_experiment response:
- If `next_mutation` is present: execute the structured mutation
- If `next_mutation` is null: fall back to ideas list
- If no ideas: generate hypotheses or end campaign
```

**Step 2:** Add mutation execution guidance per type:
- `parameter_sweep` / `enum_sweep` / `scale`: find the parameter in the specified file, change its value
- `swap`: find the target pattern, replace with the replacement
- `toggle`: find the flag, flip its value
- `remove`: find and remove the specified code block
- `reorder`: find the items and reorder them as specified

**Step 3:** Update TUI display guidance: "N mutations + M ideas remaining" when mutations are active.

<verify>
- run: test -f os/Clavain/skills/autoresearch/SKILL.md && echo "exists"
  expect: contains "exists"
</verify>

### Task 7: Integration Test
**Files:**
- Modify: `os/Skaffen/internal/experiment/integration_test.go`

**Step 1:** Add `TestMutationDrivenCampaign` that:
1. Creates a campaign with 3 mutations (1 parameter_sweep with 3 values, 1 swap, 1 toggle)
2. Opens segment, sets pending mutations
3. Iterates: NextMutation → make change → LogExperiment with mutation_id → verify NextMutation advances
4. After all mutations exhausted, NextMutation returns nil
5. Verify JSONL records have correct mutation_id/mutation_type
6. Resume from JSONL and verify completed mutations are skipped

<verify>
- run: cd os/Skaffen && go test -race ./internal/experiment/ -run TestMutation -count=1
  expect: exit 0
</verify>

### Task 8: Testdata Campaign with Mutations
**Files:**
- Create: `os/Skaffen/internal/experiment/testdata/with-mutations.yaml`

Sample campaign demonstrating all mutation types for documentation and testing.

<verify>
- run: cd os/Skaffen && go test -race ./internal/experiment/ -run TestLoadCampaign -count=1
  expect: exit 0
</verify>

## Execution Order

```
[1: Mutation types] → [2: Campaign ext] → [3: Segment ext] → [4: Init ext] → [5: Log ext]
                                                                               [6: Skill]
                                                                               [7: Integration test]
                                                                               [8: Testdata]
```

Tasks 1-5 are sequential (each builds on the previous). Tasks 6-8 can parallel after Task 5.
