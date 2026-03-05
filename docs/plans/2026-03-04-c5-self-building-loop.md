---
artifact_type: plan
bead: iv-6ixw
stage: design
---
# C5: Self-Building Loop — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-6ixw
**Goal:** Wire Composer output into sprint execution so Clavain can orchestrate its own development with model/budget routing per phase.

**Architecture:** Three additions to clavain-cli: (1) `sprint-compose` stores a ComposePlan as an ic artifact, (2) `sprint-plan-phase` reads the stored plan and returns model+budget for a given stage, (3) the sprint executor exports `CLAVAIN_MODEL` and `CLAVAIN_PHASE_BUDGET` env vars. A `.clavain/agency-spec.yaml` in the Clavain project provides self-targeting config. Gate mode graduates from shadow to enforce for early-pipeline transitions.

**Tech Stack:** Go 1.21+, YAML (gopkg.in/yaml.v3), JSON, ic CLI, bd CLI

**Prior Learnings:**
- `docs/solutions/2026-03-03-c3-composer-dispatch-plan-generator.md` — nil map panic in Go struct merge; always guard with `if base.Stages == nil { make(...) }`. Safety floor warnings pattern.
- `docs/solutions/patterns/event-pipeline-shell-consumer-bugs-20260228.md` — `ic state set` reads value from stdin, not positional args. Use consistent scope IDs.
- `docs/solutions/best-practices/silent-api-misuse-patterns-intercore-20260221.md` — Use `errors.Is()` not `==` for sentinel errors. Sort results before JSON output.
- `docs/plans/2026-03-04-c4-cross-phase-handoff-protocol.md` — Handoff validation runs pre-check in `cmdEnforceGate()`. Shadow vs enforce mode driven by `getGateMode()` from agency-spec defaults.

---

### Task 1: Create self-targeting agency spec

**Files:**
- Create: `os/clavain/.clavain/agency-spec.yaml`

**Step 1: Create the .clavain directory if needed**

```bash
mkdir -p os/clavain/.clavain
```

**Step 2: Write the project-specific agency spec override**

```yaml
# Clavain self-building overrides
# Merged on top of config/agency-spec.yaml by loadAgencySpec() → findProjectSpecPath()

version: "1.0"

project:
  name: clavain
  language: go
  test_command: "go test ./cmd/clavain-cli/..."
  lint_command: "go vet ./..."

stages:
  ship:
    agents:
      required:
        - role: fd-architecture
          description: "Architecture review of implementation"
          model_tier: sonnet
        - role: fd-correctness
          description: "Correctness review — race conditions, data consistency"
          model_tier: sonnet
        - role: fd-quality
          description: "Code quality and style review"
          model_tier: sonnet
        - role: fd-self-modification
          description: "Safety review — autonomous code and prompt editing boundaries"
          model_tier: sonnet
```

Note: `mergeSpec()` replaces `agents.required` arrays entirely, so we must include the existing 3 ship agents plus the new `fd-self-modification`. The Composer's `matchRole()` will look for a fleet agent with role `fd-self-modification` — if none exists in the fleet registry yet, it emits `unmatched_role:fd-self-modification` as a warning (non-fatal).

**Step 3: Verify the project spec is loadable**

Run: `cd os/clavain && SPRINT_LIB_PROJECT_DIR=. go run ./cmd/clavain-cli compose --stage=ship 2>&1 | head -5`
Expected: JSON output starting with `{` (plan may have warnings, that's fine)

**Step 4: Commit**

```bash
git add os/clavain/.clavain/agency-spec.yaml
git commit -m "feat(clavain): C5 self-targeting agency spec with fd-self-modification safety gate"
```

---

### Task 2: Add sprint-compose command

**Files:**
- Modify: `os/clavain/cmd/clavain-cli/compose.go` (add `cmdSprintCompose`)
- Modify: `os/clavain/cmd/clavain-cli/main.go` (register command)
- Test: `os/clavain/cmd/clavain-cli/compose_test.go` (add test)

**Step 1: Write the failing test**

Add to `compose_test.go`:

```go
func TestSprintComposeStoresAllStages(t *testing.T) {
	// sprint-compose runs compose for ALL stages and returns a combined plan.
	// We test the composeSprint function directly (no ic needed).
	fleet := loadTestFleet(t)
	spec := loadTestSpec(t)
	cal := loadTestCalibration(t)

	plans := composeSprint(spec, fleet, cal, nil, "test-sprint", 100000)

	// Should have plans for both stages in test spec (ship, build)
	if len(plans) != 2 {
		t.Fatalf("composeSprint returned %d stage plans, want 2", len(plans))
	}

	// Verify ship stage has agents
	var shipPlan *ComposePlan
	for i := range plans {
		if plans[i].Stage == "ship" {
			shipPlan = &plans[i]
			break
		}
	}
	if shipPlan == nil {
		t.Fatal("no ship stage in composeSprint output")
	}
	if len(shipPlan.Agents) == 0 {
		t.Error("ship stage has no agents")
	}

	// Verify sprint ID is set on all plans
	for _, p := range plans {
		if p.Sprint != "test-sprint" {
			t.Errorf("stage %s: sprint = %q, want test-sprint", p.Stage, p.Sprint)
		}
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -run TestSprintComposeStoresAllStages -v`
Expected: FAIL — `composeSprint` undefined

**Step 3: Write composeSprint function**

Add to `compose.go`, before `cmdCompose`:

```go
// composeSprint runs compose for ALL stages in the agency spec.
// Returns a slice of ComposePlan — one per stage.
func composeSprint(spec *AgencySpec, fleet *FleetRegistry, cal *InterspectCalibration, overrides *RoutingOverrides, sprintID string, totalBudget int64) []ComposePlan {
	var plans []ComposePlan

	// Sort stage names for deterministic output
	var stageNames []string
	for name := range spec.Stages {
		stageNames = append(stageNames, name)
	}
	sort.Strings(stageNames)

	for _, stageName := range stageNames {
		stageSpec := spec.Stages[stageName]
		stageBudget := totalBudget * int64(stageSpec.Budget.Share) / 100
		if stageBudget < int64(stageSpec.Budget.MinTokens) {
			stageBudget = int64(stageSpec.Budget.MinTokens)
		}
		plan := composePlan(stageName, sprintID, stageBudget, stageSpec, fleet, cal, overrides)
		plans = append(plans, plan)
	}
	return plans
}
```

**Step 4: Write cmdSprintCompose**

Add to `compose.go`:

```go
// cmdSprintCompose runs compose for all stages and stores the result as an ic artifact.
// Usage: sprint-compose <bead_id>
// Outputs: JSON array of ComposePlan on stdout.
func cmdSprintCompose(args []string) error {
	if len(args) < 1 || args[0] == "" {
		return fmt.Errorf("usage: sprint-compose <bead_id>")
	}
	beadID := args[0]

	// Load inputs
	fleet, err := loadFleetRegistry()
	if err != nil {
		return fmt.Errorf("sprint-compose: %w", err)
	}
	spec, err := loadAgencySpec()
	if err != nil {
		return fmt.Errorf("sprint-compose: %w", err)
	}
	cal := loadInterspectCalibration()
	overrides := loadRoutingOverrides()

	// Get total budget from ic run
	var totalBudget int64 = 1000000 // default 1M
	runID, runErr := resolveRunID(beadID)
	if runErr == nil {
		var run Run
		if err := runICJSON(&run, "run", "status", runID); err == nil && run.TokenBudget > 0 {
			totalBudget = run.TokenBudget
		}
	}

	// Compose all stages
	plans := composeSprint(spec, fleet, cal, overrides, beadID, totalBudget)

	// Output JSON
	data, err := json.MarshalIndent(plans, "", "  ")
	if err != nil {
		return fmt.Errorf("sprint-compose: marshal: %w", err)
	}
	fmt.Println(string(data))

	// Store as ic artifact (best-effort)
	if runErr == nil && runID != "" {
		// Write to temp file, then register as artifact
		tmpPath := filepath.Join(os.TempDir(), fmt.Sprintf("clavain-compose-%s.json", beadID))
		if err := os.WriteFile(tmpPath, data, 0644); err == nil {
			runIC("run", "artifact", "add", runID, "--phase=brainstorm", "--path="+tmpPath, "--type=compose_plan")
		}
	}

	return nil
}
```

**Step 5: Register command in main.go**

Add to the switch statement in `main.go`, in the Compose section:

```go
case "sprint-compose":
    err = cmdSprintCompose(args)
```

Add to `printHelp()` in the Compose section:

```
  sprint-compose      <bead_id>                             Compose all stages for sprint
```

**Step 6: Run test to verify it passes**

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -run TestSprintComposeStoresAllStages -v`
Expected: PASS

**Step 7: Commit**

```bash
git add os/clavain/cmd/clavain-cli/compose.go os/clavain/cmd/clavain-cli/compose_test.go os/clavain/cmd/clavain-cli/main.go
git commit -m "feat(clavain): sprint-compose — compose all stages for a sprint"
```

---

### Task 3: Add sprint-plan-phase command

**Files:**
- Create: `os/clavain/cmd/clavain-cli/selfbuild.go`
- Modify: `os/clavain/cmd/clavain-cli/main.go`
- Test: `os/clavain/cmd/clavain-cli/selfbuild_test.go`

**Step 1: Write the failing test**

Create `selfbuild_test.go`:

```go
package main

import (
	"testing"
)

func TestPhaseTierFromComposePlans(t *testing.T) {
	// Build a mock compose plan set
	plans := []ComposePlan{
		{
			Stage:  "discover",
			Budget: 100000,
			Agents: []PlanAgent{
				{AgentID: "brainstorm-facilitator", Model: "sonnet", Role: "brainstorm-facilitator"},
			},
		},
		{
			Stage:  "build",
			Budget: 400000,
			Agents: []PlanAgent{
				{AgentID: "implementer", Model: "opus", Role: "implementer"},
			},
		},
	}

	tests := []struct {
		phase     string
		wantModel string
		wantBudget int64
		wantFound bool
	}{
		{"brainstorm", "sonnet", 100000, true},         // brainstorm is in discover stage
		{"executing", "opus", 400000, true},             // executing is in build stage
		{"nonexistent", "", 0, false},                   // unknown phase
	}

	for _, tt := range tests {
		t.Run(tt.phase, func(t *testing.T) {
			model, budget, found := phaseTierFromPlans(plans, tt.phase)
			if found != tt.wantFound {
				t.Fatalf("phaseTierFromPlans(%q) found=%v, want %v", tt.phase, found, tt.wantFound)
			}
			if found {
				if model != tt.wantModel {
					t.Errorf("model = %q, want %q", model, tt.wantModel)
				}
				if budget != tt.wantBudget {
					t.Errorf("budget = %d, want %d", budget, tt.wantBudget)
				}
			}
		})
	}
}

func TestPhaseToStageMapping(t *testing.T) {
	// Verify all known phases map to a stage
	tests := []struct {
		phase string
		stage string
	}{
		{"brainstorm", "discover"},
		{"brainstorm-reviewed", "design"},
		{"strategized", "design"},
		{"planned", "design"},
		{"plan-reviewed", "design"},
		{"executing", "build"},
		{"shipping", "ship"},
		{"reflect", "reflect"},
	}

	for _, tt := range tests {
		t.Run(tt.phase, func(t *testing.T) {
			got := phaseToStage(tt.phase)
			if got != tt.stage {
				t.Errorf("phaseToStage(%q) = %q, want %q", tt.phase, got, tt.stage)
			}
		})
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -run "TestPhaseTier|TestPhaseToStage" -v`
Expected: FAIL — `phaseTierFromPlans` undefined (or won't compile)

**Step 3: Write selfbuild.go**

```go
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// phaseToStage maps a sprint phase name to an agency spec stage name.
// This is the authoritative mapping used by the self-building loop.
func phaseToStage(phase string) string {
	switch phase {
	case "brainstorm":
		return "discover"
	case "brainstorm-reviewed", "strategized", "planned", "plan-reviewed":
		return "design"
	case "executing":
		return "build"
	case "shipping":
		return "ship"
	case "reflect":
		return "reflect"
	default:
		return ""
	}
}

// phaseTierFromPlans finds the model tier and budget for a phase from compose plans.
// Uses phaseToStage to map phase → stage, then looks up the matching ComposePlan.
// Returns the dominant model (from the first required agent) and the stage budget.
func phaseTierFromPlans(plans []ComposePlan, phase string) (model string, budget int64, found bool) {
	stage := phaseToStage(phase)
	if stage == "" {
		return "", 0, false
	}

	for _, p := range plans {
		if p.Stage == stage {
			// Find the dominant model: first required agent, or first agent
			m := ""
			for _, a := range p.Agents {
				if a.Required {
					m = a.Model
					break
				}
			}
			if m == "" && len(p.Agents) > 0 {
				m = p.Agents[0].Model
			}
			if m == "" {
				m = "sonnet" // safe default
			}
			return m, p.Budget, true
		}
	}
	return "", 0, false
}

// cmdSprintPlanPhase reads the stored ComposePlan and returns model + budget for a phase.
// Usage: sprint-plan-phase <bead_id> <phase>
// Output: JSON {"model": "opus", "budget": 400000, "stage": "build"} or error.
func cmdSprintPlanPhase(args []string) error {
	if len(args) < 2 || args[0] == "" || args[1] == "" {
		return fmt.Errorf("usage: sprint-plan-phase <bead_id> <phase>")
	}
	beadID := args[0]
	phase := args[1]

	// Try to load compose plan from ic artifact
	plans, err := loadComposePlans(beadID)
	if err != nil {
		// Fallback: compute from agency spec directly
		spec, specErr := loadAgencySpec()
		if specErr != nil {
			return fmt.Errorf("sprint-plan-phase: no compose plan and no agency spec: %w", specErr)
		}
		stage := phaseToStage(phase)
		if stage == "" {
			return fmt.Errorf("sprint-plan-phase: unknown phase %q", phase)
		}
		stageSpec, ok := spec.Stages[stage]
		if !ok {
			return fmt.Errorf("sprint-plan-phase: unknown stage %q for phase %q", stage, phase)
		}
		result := map[string]interface{}{
			"model":    stageSpec.Budget.ModelTierHint,
			"budget":   stageSpec.Budget.MinTokens,
			"stage":    stage,
			"fallback": true,
		}
		data, _ := json.Marshal(result)
		fmt.Println(string(data))
		return nil
	}

	model, budget, found := phaseTierFromPlans(plans, phase)
	if !found {
		return fmt.Errorf("sprint-plan-phase: phase %q not mapped to any stage", phase)
	}

	result := map[string]interface{}{
		"model":  model,
		"budget": budget,
		"stage":  phaseToStage(phase),
	}
	data, _ := json.Marshal(result)
	fmt.Println(string(data))
	return nil
}

// loadComposePlans loads stored compose plans from ic artifact.
func loadComposePlans(beadID string) ([]ComposePlan, error) {
	runID, err := resolveRunID(beadID)
	if err != nil {
		return nil, err
	}

	var artifacts []Artifact
	if err := runICJSON(&artifacts, "run", "artifact", "list", runID); err != nil {
		return nil, err
	}

	// Find compose_plan artifact
	for _, a := range artifacts {
		if a.Type == "compose_plan" {
			data, err := os.ReadFile(a.Path)
			if err != nil {
				continue
			}
			var plans []ComposePlan
			if err := json.Unmarshal(data, &plans); err != nil {
				// Try single plan (backward compat)
				var single ComposePlan
				if err2 := json.Unmarshal(data, &single); err2 == nil {
					return []ComposePlan{single}, nil
				}
				continue
			}
			return plans, nil
		}
	}
	return nil, fmt.Errorf("no compose_plan artifact found for %s", beadID)
}

// cmdSprintEnvVars outputs export statements for CLAVAIN_MODEL and CLAVAIN_PHASE_BUDGET.
// Intended to be eval'd by the sprint executor: eval $(clavain-cli sprint-env-vars <bead_id> <phase>)
// Usage: sprint-env-vars <bead_id> <phase>
func cmdSprintEnvVars(args []string) error {
	if len(args) < 2 || args[0] == "" || args[1] == "" {
		return fmt.Errorf("usage: sprint-env-vars <bead_id> <phase>")
	}
	beadID := args[0]
	phase := args[1]

	// Try compose plans first
	plans, err := loadComposePlans(beadID)
	if err == nil {
		model, budget, found := phaseTierFromPlans(plans, phase)
		if found {
			fmt.Printf("export CLAVAIN_MODEL=%s\n", model)
			fmt.Printf("export CLAVAIN_PHASE_BUDGET=%d\n", budget)
			fmt.Printf("export CLAVAIN_STAGE=%s\n", phaseToStage(phase))
			return nil
		}
	}

	// Fallback: agency spec model_tier_hint
	spec, specErr := loadAgencySpec()
	if specErr != nil {
		// No compose plan and no spec — emit empty exports (fail-soft)
		fmt.Fprintf(os.Stderr, "sprint-env-vars: no compose plan or agency spec for %s\n", beadID)
		return nil
	}
	stage := phaseToStage(phase)
	if stage == "" {
		return nil // Unknown phase — fail-soft
	}
	stageSpec, ok := spec.Stages[stage]
	if !ok {
		return nil
	}
	model := stageSpec.Budget.ModelTierHint
	if model == "" {
		model = "sonnet"
	}
	fmt.Printf("export CLAVAIN_MODEL=%s\n", model)
	fmt.Printf("export CLAVAIN_PHASE_BUDGET=%d\n", stageSpec.Budget.MinTokens)
	fmt.Printf("export CLAVAIN_STAGE=%s\n", stage)
	_ = strings // satisfy import if not used elsewhere
	return nil
}
```

**Step 4: Register commands in main.go**

Add to the switch statement:

```go
case "sprint-plan-phase":
    err = cmdSprintPlanPhase(args)
case "sprint-env-vars":
    err = cmdSprintEnvVars(args)
```

Add to `printHelp()`:

```
  sprint-plan-phase   <bead_id> <phase>                    Get model+budget for phase from compose plan
  sprint-env-vars     <bead_id> <phase>                    Output export statements for sprint env vars
```

**Step 5: Run tests**

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -run "TestPhaseTier|TestPhaseToStage" -v`
Expected: PASS

**Step 6: Commit**

```bash
git add os/clavain/cmd/clavain-cli/selfbuild.go os/clavain/cmd/clavain-cli/selfbuild_test.go os/clavain/cmd/clavain-cli/main.go
git commit -m "feat(clavain): sprint-plan-phase and sprint-env-vars — compose plan consumption"
```

---

### Task 4: Graduate gate mode for early-pipeline transitions

**Files:**
- Modify: `os/clavain/config/agency-spec.yaml`
- Modify: `os/clavain/cmd/clavain-cli/handoff.go` (per-stage gate mode)
- Test: `os/clavain/cmd/clavain-cli/handoff_test.go`

**Step 1: Write the failing test**

Add to `handoff_test.go`:

```go
func TestGetGateModePerStage(t *testing.T) {
	// When per-stage gate modes are defined, they should override the default.
	// This test uses in-memory spec (no file loading).
	spec := &AgencySpec{
		Defaults: SpecDefaults{GateMode: "shadow"},
		Stages: map[string]StageSpec{
			"discover": {Gates: map[string]interface{}{"gate_mode": "enforce"}},
			"design":   {Gates: map[string]interface{}{"gate_mode": "enforce"}},
			"build":    {},
			"ship":     {},
		},
	}

	tests := []struct {
		targetPhase string
		wantMode    string
	}{
		{"strategized", "enforce"},    // discover→design transition
		{"planned", "enforce"},        // within design
		{"executing", "shadow"},       // build stage, no per-stage override
		{"shipping", "shadow"},        // ship stage, no per-stage override
	}

	for _, tt := range tests {
		t.Run(tt.targetPhase, func(t *testing.T) {
			mode := getGateModeForPhase(spec, tt.targetPhase)
			if mode != tt.wantMode {
				t.Errorf("getGateModeForPhase(%q) = %q, want %q", tt.targetPhase, mode, tt.wantMode)
			}
		})
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -run TestGetGateModePerStage -v`
Expected: FAIL — `getGateModeForPhase` undefined

**Step 3: Update agency-spec.yaml**

Edit `config/agency-spec.yaml` to add per-stage gate modes. In the `discover` stage, add after `gates: {}`:

Replace `gates: {}` in discover with:
```yaml
    gates:
      gate_mode: enforce
```

In the `design` stage, add `gate_mode: enforce` to the existing gates map:
```yaml
    gates:
      gate_mode: enforce
      plan_reviewed: ...
```

Leave `build` and `ship` gates unchanged (inherit default `shadow`).

**Step 4: Add getGateModeForPhase to handoff.go**

```go
// getGateModeForPhase checks for per-stage gate_mode override, falling back to spec defaults.
// Maps the target phase to a stage via phaseToStage, then checks the stage's gates.
func getGateModeForPhase(spec *AgencySpec, targetPhase string) string {
	stage := phaseToStage(targetPhase)
	if stage != "" {
		if stageSpec, ok := spec.Stages[stage]; ok {
			if stageSpec.Gates != nil {
				if gm, ok := stageSpec.Gates["gate_mode"]; ok {
					if mode, ok := gm.(string); ok && mode != "" {
						return mode
					}
				}
			}
		}
	}
	// Fall back to spec defaults
	if spec.Defaults.GateMode != "" {
		return spec.Defaults.GateMode
	}
	return "shadow"
}
```

Note: This requires `Gates` in `StageSpec` to be `map[string]interface{}` instead of the current implicit struct. Check if `StageSpec.Gates` needs a type change — currently it's implicitly empty in the Go struct. We need to add it.

Add to `compose.go` in `StageSpec`:

```go
type StageSpec struct {
	// ... existing fields ...
	Gates map[string]interface{} `yaml:"gates"`
}
```

Wait — `StageSpec` already has no Gates field. The agency-spec.yaml has gates as complex nested objects. We need a flexible type. Add:

```go
Gates map[string]interface{} `yaml:"gates,omitempty"`
```

**Step 5: Update cmdEnforceGate to use per-phase gate mode**

In `handoff.go`, modify the block in `cmdEnforceGate` that checks `getGateMode()`:

Replace:
```go
mode := getGateMode()
```

With:
```go
spec, specErr := loadAgencySpec()
var mode string
if specErr == nil {
    mode = getGateModeForPhase(spec, targetPhase)
} else {
    mode = "shadow"
}
```

**Step 6: Run tests**

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -run TestGetGateModePerStage -v`
Expected: PASS

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -v`
Expected: All tests PASS (verify no regressions)

**Step 7: Commit**

```bash
git add os/clavain/config/agency-spec.yaml os/clavain/cmd/clavain-cli/handoff.go os/clavain/cmd/clavain-cli/handoff_test.go os/clavain/cmd/clavain-cli/compose.go
git commit -m "feat(clavain): graduate gate mode to enforce for discover→design and design→build"
```

---

### Task 5: Update test fixtures for self-targeting

**Files:**
- Modify: `os/clavain/cmd/clavain-cli/testdata/agency-spec.yaml`
- Create: `os/clavain/cmd/clavain-cli/testdata/project-agency-spec.yaml`

**Step 1: Add discover stage to test agency spec**

The test spec currently has only `ship` and `build`. Add `discover` and `design` stages (minimal) so gate mode tests can work with loaded fixtures:

```yaml
  discover:
    description: "Brainstorm and explore"
    phases: [brainstorm]
    requires:
      capabilities: []
    budget:
      share: 10
      min_tokens: 2000
      model_tier_hint: sonnet
    gates:
      gate_mode: enforce
    agents:
      required:
        - role: brainstorm-facilitator
          description: "Brainstorm facilitator"
          model_tier: sonnet
      optional: []
  design:
    description: "Strategy and planning"
    phases: [strategized, planned, plan-reviewed]
    requires:
      capabilities: []
    budget:
      share: 25
      min_tokens: 5000
      model_tier_hint: opus
    gates:
      gate_mode: enforce
    agents:
      required:
        - role: strategist
          description: "Strategy writer"
          model_tier: opus
      optional: []
```

**Step 2: Create project override fixture**

Write `testdata/project-agency-spec.yaml`:

```yaml
version: "1.0"
stages:
  ship:
    agents:
      required:
        - role: fd-architecture
          description: "Architecture review"
          model_tier: sonnet
        - role: fd-correctness
          description: "Correctness review"
          model_tier: sonnet
        - role: fd-quality
          description: "Quality review"
          model_tier: sonnet
        - role: fd-self-modification
          description: "Self-modification safety review"
          model_tier: sonnet
```

**Step 3: Write merge test with project override**

Add to `compose_test.go`:

```go
func TestMergeProjectOverride(t *testing.T) {
	spec := loadTestSpec(t)

	// Load project override
	data, err := os.ReadFile(filepath.Join("testdata", "project-agency-spec.yaml"))
	if err != nil {
		t.Fatalf("load project override: %v", err)
	}
	var override AgencySpec
	if err := yaml.Unmarshal(data, &override); err != nil {
		t.Fatalf("parse project override: %v", err)
	}

	mergeSpec(spec, &override)

	ship := spec.Stages["ship"]
	// Should now have 4 required agents (3 original + fd-self-modification)
	if len(ship.Agents.Required) != 4 {
		t.Errorf("merged ship required agents = %d, want 4", len(ship.Agents.Required))
	}

	// Verify fd-self-modification is present
	found := false
	for _, a := range ship.Agents.Required {
		if a.Role == "fd-self-modification" {
			found = true
			break
		}
	}
	if !found {
		t.Error("fd-self-modification not found in merged spec")
	}
}
```

**Step 4: Run tests**

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -v`
Expected: All tests PASS

**Step 5: Fix any test count assertions broken by new stages**

The test `TestLoadAgencySpec` asserts `len(spec.Stages) != 2`. With discover and design added, this becomes 4. Update the assertion:

```go
if len(spec.Stages) != 4 {
    t.Fatalf("expected 4 stages, got %d", len(spec.Stages))
}
```

**Step 6: Commit**

```bash
git add os/clavain/cmd/clavain-cli/testdata/ os/clavain/cmd/clavain-cli/compose_test.go
git commit -m "test(clavain): add discover/design stages and project override fixtures"
```

---

### Task 6: End-to-end smoke test

**Files:**
- Test: `os/clavain/cmd/clavain-cli/selfbuild_test.go` (add integration tests)

**Step 1: Write self-building loop integration test**

Add to `selfbuild_test.go`:

```go
func TestSelfBuildLoopComposeMerge(t *testing.T) {
	// Simulates: load base spec + project override → compose all stages → extract phase tier
	// This is the core self-building loop path without ic/bd dependencies.

	// Load base spec
	spec := loadTestSpec(t)

	// Load project override and merge
	data, err := os.ReadFile(filepath.Join("testdata", "project-agency-spec.yaml"))
	if err != nil {
		t.Fatalf("load project override: %v", err)
	}
	var override AgencySpec
	if err := yaml.Unmarshal(data, &override); err != nil {
		t.Fatalf("parse override: %v", err)
	}
	mergeSpec(spec, &override)

	// Load fleet
	fleet := loadTestFleet(t)
	cal := loadTestCalibration(t)

	// Compose all stages
	plans := composeSprint(spec, fleet, cal, nil, "self-build-test", 1000000)
	if len(plans) == 0 {
		t.Fatal("composeSprint returned no plans")
	}

	// Verify self-targeting: fd-self-modification should appear in ship stage
	var shipPlan *ComposePlan
	for i := range plans {
		if plans[i].Stage == "ship" {
			shipPlan = &plans[i]
			break
		}
	}
	if shipPlan == nil {
		t.Fatal("no ship stage plan")
	}

	// fd-self-modification won't match (not in test fleet), but should produce warning
	hasUnmatchedWarning := false
	for _, w := range shipPlan.Warnings {
		if w == "unmatched_role:fd-self-modification" {
			hasUnmatchedWarning = true
			break
		}
	}
	if !hasUnmatchedWarning {
		t.Error("expected unmatched_role:fd-self-modification warning (agent not in test fleet)")
	}

	// Verify phase tier extraction works for each known phase
	phaseTests := []struct {
		phase     string
		wantStage string
	}{
		{"brainstorm", "discover"},
		{"strategized", "design"},
		{"executing", "build"},
		{"shipping", "ship"},
		{"reflect", "reflect"},
	}

	for _, tt := range phaseTests {
		model, budget, found := phaseTierFromPlans(plans, tt.phase)
		// reflect stage may not exist in test spec, so found may be false
		if tt.wantStage == "reflect" {
			continue // test spec doesn't have reflect
		}
		if !found {
			t.Errorf("phaseTierFromPlans(%q) not found, want stage %q", tt.phase, tt.wantStage)
			continue
		}
		if model == "" {
			t.Errorf("phaseTierFromPlans(%q) model is empty", tt.phase)
		}
		if budget <= 0 {
			t.Errorf("phaseTierFromPlans(%q) budget=%d, want > 0", tt.phase, budget)
		}
	}
}

func TestGateModeGraduationIntegration(t *testing.T) {
	// Verify that the test agency-spec.yaml has enforce mode for discover and design
	spec := loadTestSpec(t)

	// discover should have gate_mode: enforce
	discoverGates := spec.Stages["discover"].Gates
	if discoverGates == nil {
		t.Fatal("discover stage has no gates")
	}
	mode, ok := discoverGates["gate_mode"]
	if !ok || mode != "enforce" {
		t.Errorf("discover gate_mode = %v, want enforce", mode)
	}

	// design should have gate_mode: enforce
	designGates := spec.Stages["design"].Gates
	if designGates == nil {
		t.Fatal("design stage has no gates")
	}
	mode, ok = designGates["gate_mode"]
	if !ok || mode != "enforce" {
		t.Errorf("design gate_mode = %v, want enforce", mode)
	}

	// ship should NOT have gate_mode (inherits shadow)
	shipGates := spec.Stages["ship"].Gates
	if shipGates != nil {
		if _, hasGateMode := shipGates["gate_mode"]; hasGateMode {
			t.Error("ship stage should not have explicit gate_mode (should inherit shadow)")
		}
	}
}
```

**Step 2: Run all tests**

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -v`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add os/clavain/cmd/clavain-cli/selfbuild_test.go
git commit -m "test(clavain): C5 end-to-end smoke test — self-build loop compose + gate graduation"
```

---

### Task 7: Build binary and run smoke tests

**Step 1: Build the binary**

Run: `cd os/clavain && go build -o /tmp/clavain-cli ./cmd/clavain-cli/`
Expected: Build succeeds with no errors

**Step 2: Run all tests**

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -v -count=1`
Expected: All tests PASS

**Step 3: CLI smoke tests**

Run compose from the Clavain project directory to verify self-targeting:

```bash
cd os/clavain
SPRINT_LIB_PROJECT_DIR=. CLAVAIN_CONFIG_DIR=config /tmp/clavain-cli compose --stage=ship 2>&1
```

Expected: JSON output with agents including `fd-self-modification` in unmatched_role warning (since it's not in the fleet registry yet).

Run sprint-plan-phase with fallback (no ic):

```bash
CLAVAIN_CONFIG_DIR=config /tmp/clavain-cli sprint-plan-phase "test-bead" "executing" 2>&1
```

Expected: JSON with `{"model":"opus","budget":10000,"stage":"build","fallback":true}` (falls back to agency spec since no ic)

Run sprint-env-vars with fallback:

```bash
CLAVAIN_CONFIG_DIR=config /tmp/clavain-cli sprint-env-vars "test-bead" "brainstorm" 2>&1
```

Expected: `export CLAVAIN_MODEL=sonnet` and `export CLAVAIN_PHASE_BUDGET=2000` and `export CLAVAIN_STAGE=discover`

**Step 4: Final commit with all changes**

```bash
git add -A
git commit -m "feat(clavain): C5 self-building loop — compose plan integration, gate graduation, self-targeting config"
```

**Step 5: Push**

```bash
git push
```
