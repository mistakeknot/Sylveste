---
artifact_type: plan
bead: Sylveste-j2f
stage: design
requirements:
  - F1: Mandatory ic startup check
  - F2: Fix emitter Intercore bridge
  - F3: Routing decision recording via ic route record
  - F4: Override consumption from ic route model
  - F5: Richer evidence signals with model/outcome metadata
---

# Skaffen v0.3: Intercore Bridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-j2f
**Goal:** Connect Skaffen to Intercore — fix evidence bridge, record routing decisions, consume overrides.

**Architecture:** The existing `evidence/emitter.go` gets its 3 bridge bugs fixed. The router gains an override query step (cached per-session) and a decision recording method. `main.go` adds an ic startup check. No new packages — changes touch emitter, router, agent loop, and main.

**Tech Stack:** Go, `os/exec` for ic CLI calls, `encoding/json` for payloads

---

## Must-Haves

**Truths** (observable behaviors):
- Skaffen exits with clear error if `ic` is not on PATH
- Skaffen exits with clear error if `ic health` fails
- Every agent turn emits an event to Intercore via `ic events record --source=interspect`
- Every `SelectModel()` call records a decision via `ic route record`
- Routing overrides from `ic route model` are honored (env > override > config > default)
- Evidence includes model name and routing reason

**Artifacts** (files that must exist):
- [`internal/evidence/emitter.go`] fixed bridge with correct source, flags, agent_name
- [`internal/router/router.go`] override query + decision recording
- [`internal/router/intercore.go`] ic CLI wrapper for routing queries/recording
- [`cmd/skaffen/main.go`] startup check
- [`internal/agent/deps.go`] Evidence struct with Model, ModelReason fields

**Key Links:**
- Agent loop (loop.go:44) calls `router.SelectModel()` → must also call recording
- Agent loop (loop.go:131) calls `emitter.Emit()` → evidence must include model info
- Main startup must validate ic before creating agent

---

### Task 1: Add ic CLI wrapper for router (internal/router/intercore.go)

**Files:**
- Create: `internal/router/intercore.go`
- Create: `internal/router/intercore_test.go`

This wrapper encapsulates all `ic` CLI calls the router needs: health check, override query, decision recording.

**Step 1: Write the test for ICClient**

Create `internal/router/intercore_test.go`:

```go
package router

import (
	"testing"
)

func TestICClient_HealthWithFakeBinary(t *testing.T) {
	// Use a fake ic binary that exits 0
	ic := &ICClient{icPath: "true"} // "true" command always exits 0
	if err := ic.Health(); err != nil {
		t.Errorf("Health with 'true': %v", err)
	}
}

func TestICClient_HealthWithBadBinary(t *testing.T) {
	ic := &ICClient{icPath: "false"} // "false" command always exits 1
	if err := ic.Health(); err == nil {
		t.Error("Health with 'false' should fail")
	}
}

func TestICClient_HealthMissingBinary(t *testing.T) {
	ic := &ICClient{icPath: "/nonexistent/ic"}
	if err := ic.Health(); err == nil {
		t.Error("Health with missing binary should fail")
	}
}

func TestICClient_QueryOverrideNoBinary(t *testing.T) {
	ic := &ICClient{icPath: "/nonexistent/ic"}
	model := ic.QueryOverride("build")
	if model != "" {
		t.Errorf("QueryOverride with missing binary = %q, want empty", model)
	}
}

func TestICClient_BuildRecordArgs(t *testing.T) {
	ic := &ICClient{icPath: "ic"}
	args := ic.buildRecordArgs(DecisionRecord{
		Agent:      "skaffen",
		Model:      "claude-sonnet-4-6",
		Rule:       "phase-default",
		Phase:      "build",
		SessionID:  "sess-123",
		Complexity: 3,
	})

	want := []string{
		"route", "record",
		"--agent=skaffen",
		"--model=claude-sonnet-4-6",
		"--rule=phase-default",
		"--phase=build",
		"--session=sess-123",
		"--complexity=3",
	}
	if len(args) != len(want) {
		t.Fatalf("args len = %d, want %d: %v", len(args), len(want), args)
	}
	for i, w := range want {
		if args[i] != w {
			t.Errorf("args[%d] = %q, want %q", i, args[i], w)
		}
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/router/ -run TestICClient -v`
Expected: FAIL — `ICClient` and `DecisionRecord` not defined

**Step 3: Write the ICClient implementation**

Create `internal/router/intercore.go`:

```go
package router

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

// ICClient wraps the ic (Intercore) CLI binary for routing operations.
type ICClient struct {
	icPath string
}

// NewICClient finds the ic binary on PATH and returns a client.
// Returns an error if ic is not found.
func NewICClient() (*ICClient, error) {
	path, err := exec.LookPath("ic")
	if err != nil {
		return nil, fmt.Errorf("ic not found on PATH: %w (install intercore CLI)", err)
	}
	return &ICClient{icPath: path}, nil
}

// Health runs `ic health` and returns an error if it fails.
func (c *ICClient) Health() error {
	cmd := exec.Command(c.icPath, "health")
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("ic health failed: %w (output: %s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// QueryOverride queries `ic route model --phase=<p> --agent=skaffen --json`
// and returns the model ID, or empty string if no override exists.
func (c *ICClient) QueryOverride(phase string) string {
	cmd := exec.Command(c.icPath, "route", "model",
		"--phase="+phase,
		"--agent=skaffen",
	)
	out, err := cmd.Output()
	if err != nil {
		return "" // no override or ic error — fall through
	}
	model := strings.TrimSpace(string(out))
	if model == "" {
		return ""
	}
	return model
}

// DecisionRecord holds the fields for an ic route record call.
type DecisionRecord struct {
	Agent      string
	Model      string
	Rule       string
	Phase      string
	SessionID  string
	Complexity int
}

// RecordDecision fires `ic route record` in the background (fire-and-forget).
func (c *ICClient) RecordDecision(rec DecisionRecord) {
	args := c.buildRecordArgs(rec)
	cmd := exec.Command(c.icPath, args...)
	go cmd.Run() // fire-and-forget
}

func (c *ICClient) buildRecordArgs(rec DecisionRecord) []string {
	args := []string{
		"route", "record",
		"--agent=" + rec.Agent,
		"--model=" + rec.Model,
		"--rule=" + rec.Rule,
		"--phase=" + rec.Phase,
	}
	if rec.SessionID != "" {
		args = append(args, "--session="+rec.SessionID)
	}
	if rec.Complexity > 0 {
		args = append(args, "--complexity="+strconv.Itoa(rec.Complexity))
	}
	return args
}
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/router/ -run TestICClient -v`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/router/intercore.go internal/router/intercore_test.go
git commit -m "feat(router): add ICClient wrapper for ic CLI routing operations"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/router/ -run TestICClient -v`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go vet ./internal/router/`
  expect: exit 0
</verify>

---

### Task 2: Add ic startup check to main.go (F1)

**Files:**
- Modify: `cmd/skaffen/main.go`

**Step 1: Write the checkIntercore function and wire it into both runPrint and runTUI**

Add to `cmd/skaffen/main.go`:

```go
// checkIntercore validates that ic (Intercore CLI) is available and healthy.
// Skaffen v0.3+ requires Intercore for evidence and routing.
func checkIntercore() (*router.ICClient, error) {
	ic, err := router.NewICClient()
	if err != nil {
		return nil, fmt.Errorf("intercore required: %w\nInstall: go install github.com/mistakeknot/intercore/cmd/ic@latest", err)
	}
	if err := ic.Health(); err != nil {
		return nil, fmt.Errorf("intercore unhealthy: %w\nEnsure ic database is initialized: ic sentinel check startup", err)
	}
	return ic, nil
}
```

Wire into both `runPrint()` and `runTUI()` — add as the first thing after flag parsing:

```go
// In runPrint(), after signal context setup:
ic, err := checkIntercore()
if err != nil {
    return err
}

// In runTUI(), after provider setup:
ic, err := checkIntercore()
if err != nil {
    return err
}
```

The `ic` variable is needed later for Task 4 (passing to the router).

**Step 2: Run build to verify it compiles**

Run: `cd os/Skaffen && go build ./cmd/skaffen/`
Expected: Compiles (may warn about unused `ic` variable — that's fine, Task 4 will use it)

**Step 3: Commit**

```bash
cd os/Skaffen && git add cmd/skaffen/main.go
git commit -m "feat(main): add mandatory ic startup check (F1)"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./cmd/skaffen/`
  expect: exit 0
</verify>

---

### Task 3: Fix emitter bridge bugs (F2)

**Files:**
- Modify: `internal/evidence/emitter.go`
- Modify: `internal/evidence/emitter_test.go`

**Step 1: Write tests for the fixed bridge**

Add to `internal/evidence/emitter_test.go`:

```go
func TestBridgeArgs(t *testing.T) {
	// Test that bridgeToIntercore constructs correct CLI args
	e := &evidence.JSONLEmitter{} // need to export or test via BuildBridgeArgs
	// Since bridgeToIntercore is unexported, test via the public BridgeArgs method
	args := e.BridgeArgs(makeEvidence(1))

	// Verify source is interspect (not skaffen)
	found := false
	for _, a := range args {
		if a == "--source=interspect" {
			found = true
		}
		if a == "--source=skaffen" {
			t.Error("source should be interspect, not skaffen")
		}
		if strings.HasPrefix(a, "--data=") {
			t.Error("should use --payload=, not --data=")
		}
	}
	if !found {
		t.Error("missing --source=interspect")
	}

	// Verify payload contains agent_name
	for _, a := range args {
		if strings.HasPrefix(a, "--payload=") {
			payload := strings.TrimPrefix(a, "--payload=")
			if !strings.Contains(payload, `"agent_name"`) {
				t.Error("payload missing agent_name")
			}
			if !strings.Contains(payload, `"skaffen"`) {
				t.Error("payload agent_name should be skaffen")
			}
		}
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/evidence/ -run TestBridgeArgs -v`
Expected: FAIL — `BridgeArgs` method doesn't exist

**Step 3: Fix emitter.go — correct all 3 bugs and expose BridgeArgs for testing**

Rewrite `bridgeToIntercore` in `internal/evidence/emitter.go`:

```go
// interspectPayload wraps evidence for ic events record --source=interspect.
type interspectPayload struct {
	AgentName string          `json:"agent_name"`
	Context   json.RawMessage `json:"context"`
}

// BridgeArgs returns the ic CLI args for bridging an evidence event.
// Exported for testing.
func (e *JSONLEmitter) BridgeArgs(ev agent.Evidence) []string {
	contextJSON, err := json.Marshal(ev)
	if err != nil {
		return nil
	}
	payload := interspectPayload{
		AgentName: "skaffen",
		Context:   contextJSON,
	}
	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return nil
	}

	eventType := "turn_complete"
	if ev.Outcome == "success" && ev.StopReason == "end_turn" {
		eventType = "session_end"
	}

	args := []string{
		"events", "record",
		"--source=interspect",
		"--type=" + eventType,
		"--payload=" + string(payloadJSON),
	}
	if ev.SessionID != "" {
		args = append(args, "--session="+ev.SessionID)
	}
	return args
}

// bridgeToIntercore shells out to `ic events record` (best-effort).
func (e *JSONLEmitter) bridgeToIntercore(ev agent.Evidence) {
	args := e.BridgeArgs(ev)
	if args == nil {
		return
	}
	cmd := exec.Command(e.icPath, args...)
	cmd.Run() // ignore errors — intercore bridge is best-effort
}
```

Also remove the `if e.icPath != ""` check in `Emit()` since ic is now mandatory (icPath is always set). Actually, keep the check — the emitter is constructed with `New()` which auto-detects. We'll just ensure ic is on PATH via the startup check (Task 2). The emitter shouldn't hard-fail on bridge errors.

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/evidence/ -run TestBridgeArgs -v`
Expected: PASS

**Step 5: Run all evidence tests**

Run: `cd os/Skaffen && go test ./internal/evidence/ -v`
Expected: All pass

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/evidence/emitter.go internal/evidence/emitter_test.go
git commit -m "fix(evidence): correct Intercore bridge — interspect source, --payload flag, agent_name (F2)"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/evidence/ -v`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go vet ./internal/evidence/`
  expect: exit 0
</verify>

---

### Task 4: Add override consumption to router (F4)

**Files:**
- Modify: `internal/router/router.go`
- Modify: `internal/router/config.go`
- Modify: `internal/router/router_test.go`

This task adds the override query step to `SelectModel()`. Overrides are cached per-session (queried once at router construction).

**Step 1: Write tests for override consumption**

Add to `internal/router/router_test.go`:

```go
func TestOverrideApplied(t *testing.T) {
	r := New(&Config{})
	// Simulate an override for the build phase
	r.overrides = map[string]string{"build": ModelOpus}
	model, reason := r.SelectModel(tool.PhaseBuild)
	if model != ModelOpus {
		t.Errorf("override: model = %q, want opus", model)
	}
	if reason != "intercore-override" {
		t.Errorf("override: reason = %q, want intercore-override", reason)
	}
}

func TestOverrideNotAppliedForOtherPhase(t *testing.T) {
	r := New(&Config{})
	r.overrides = map[string]string{"build": ModelOpus}
	model, reason := r.SelectModel(tool.PhaseBrainstorm)
	// Brainstorm default is opus anyway, but reason should be phase-default
	if reason == "intercore-override" {
		t.Error("override should not apply to brainstorm")
	}
	_ = model
}

func TestEnvOverrideBeatsIntercoreOverride(t *testing.T) {
	// Env override has higher priority than intercore override
	cfg := &Config{}
	r := New(cfg)
	r.overrides = map[string]string{"build": ModelHaiku}
	// Set env var
	t.Setenv("SKAFFEN_MODEL_BUILD", "opus")
	model, reason := r.SelectModel(tool.PhaseBuild)
	if model != ModelOpus {
		t.Errorf("env should beat intercore: model = %q, want opus", model)
	}
	if reason != "env-override" {
		t.Errorf("reason = %q, want env-override", reason)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/router/ -run TestOverride -v`
Expected: FAIL — `overrides` field doesn't exist on DefaultRouter

**Step 3: Add override support to router.go**

Add `overrides` field to `DefaultRouter` and `ic` field:

```go
// In DefaultRouter struct, add:
overrides  map[string]string // phase -> model, from ic route model
ic         *ICClient
sessionID  string
```

Update `New()` to accept an ICClient:

```go
// NewWithIC creates a DefaultRouter with Intercore integration.
func NewWithIC(cfg *Config, ic *ICClient, sessionID string) *DefaultRouter {
	r := New(cfg)
	r.ic = ic
	r.sessionID = sessionID
	if ic != nil {
		r.overrides = make(map[string]string)
		for _, phase := range []string{"brainstorm", "plan", "build", "review", "ship"} {
			if model := ic.QueryOverride(phase); model != "" {
				r.overrides[phase] = model
			}
		}
	}
	return r
}
```

Update `SelectModel()` to check overrides — insert between env var and config file:

```go
// In SelectModel(), after env var check, before config file:

// Intercore override (between env and config)
if m, ok := r.overrides[string(phase)]; ok && m != "" {
    model = resolveModelAlias(m)
    reason = "intercore-override"
}

// ... then env var check moves AFTER this (env beats override)
```

Wait — the resolution order needs to be: env > intercore > config > default. Currently the code builds up from default and each layer overwrites. So the order of checks in the code should be: default → config → intercore → env (last write wins). Let me restructure:

```go
func (r *DefaultRouter) SelectModel(phase tool.Phase) (string, string) {
	// Start with phase default
	model := phaseDefaults[phase]
	reason := "phase-default"
	if model == "" {
		model = ModelSonnet
		reason = "fallback-default"
	}

	// Config file override
	if m, ok := r.cfg.Phases[phase]; ok && m != "" {
		model = resolveModelAlias(m)
		reason = "config-file"
	}

	// Intercore override (above config, below env)
	if m, ok := r.overrides[string(phase)]; ok && m != "" {
		model = resolveModelAlias(m)
		reason = "intercore-override"
	}

	// Env var override (highest explicit priority)
	if m := r.cfg.envOverride(phase); m != "" {
		model = resolveModelAlias(m)
		reason = "env-override"
	}

	// Complexity override (shadow logs but doesn't change; enforce applies)
	r.lastOverride = nil
	if r.complexity != nil {
		model, reason, r.lastOverride = r.complexity.MaybeOverride(model, reason, r.inputTokens)
	}

	// Budget degradation (overrides everything when exhausted)
	if r.budget != nil {
		model, reason = r.budget.MaybeDegrade(model, reason)
	}

	return model, reason
}
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/router/ -run TestOverride -v`
Expected: PASS

**Step 5: Run all router tests**

Run: `cd os/Skaffen && go test ./internal/router/ -v`
Expected: All pass

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/router/router.go internal/router/router_test.go
git commit -m "feat(router): consume Intercore overrides — env > override > config > default (F4)"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/router/ -v`
  expect: exit 0
</verify>

---

### Task 5: Add routing decision recording (F3)

**Files:**
- Modify: `internal/router/router.go`
- Modify: `internal/router/router_test.go`

**Step 1: Write test for decision recording**

Add to `internal/router/router_test.go`:

```go
func TestRecordDecisionCalled(t *testing.T) {
	// Create a router with a mock IC client
	r := New(&Config{})
	r.sessionID = "test-session"
	// We can't easily mock the ICClient, but we can test that
	// the method exists and builds the right record
	rec := r.buildDecisionRecord(tool.PhaseBuild, "claude-sonnet-4-6", "phase-default")
	if rec.Agent != "skaffen" {
		t.Errorf("agent = %q, want skaffen", rec.Agent)
	}
	if rec.Model != "claude-sonnet-4-6" {
		t.Errorf("model = %q", rec.Model)
	}
	if rec.Rule != "phase-default" {
		t.Errorf("rule = %q", rec.Rule)
	}
	if rec.Phase != "build" {
		t.Errorf("phase = %q", rec.Phase)
	}
	if rec.SessionID != "test-session" {
		t.Errorf("session = %q", rec.SessionID)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/router/ -run TestRecordDecision -v`
Expected: FAIL — `buildDecisionRecord` doesn't exist

**Step 3: Add recording to SelectModel**

Add to `internal/router/router.go`:

```go
// buildDecisionRecord creates a DecisionRecord from the current routing state.
func (r *DefaultRouter) buildDecisionRecord(phase tool.Phase, model, reason string) DecisionRecord {
	rec := DecisionRecord{
		Agent:     "skaffen",
		Model:     model,
		Rule:      reason,
		Phase:     string(phase),
		SessionID: r.sessionID,
	}
	if r.lastOverride != nil {
		rec.Complexity = r.lastOverride.Tier
	}
	return rec
}
```

Then update `SelectModel()` to call recording at the end (after all resolution):

```go
// At the end of SelectModel(), before the return:
if r.ic != nil {
    r.ic.RecordDecision(r.buildDecisionRecord(phase, model, reason))
}

return model, reason
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/router/ -run TestRecordDecision -v`
Expected: PASS

**Step 5: Run all router tests**

Run: `cd os/Skaffen && go test ./internal/router/ -v -race`
Expected: All pass, no races (RecordDecision is fire-and-forget goroutine)

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/router/router.go internal/router/router_test.go
git commit -m "feat(router): record every routing decision via ic route record (F3)"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/router/ -v -race`
  expect: exit 0
</verify>

---

### Task 6: Add Model and ModelReason to Evidence (F5)

**Files:**
- Modify: `internal/agent/deps.go`
- Modify: `internal/agent/loop.go`
- Modify: `internal/evidence/emitter_test.go`

**Step 1: Write test that Evidence includes model info**

Update `makeEvidence` in `internal/evidence/emitter_test.go` to include model fields:

```go
func makeEvidence(turn int) agent.Evidence {
	return agent.Evidence{
		Timestamp:   "2026-03-11T12:00:00Z",
		SessionID:   "test-session",
		Phase:       tool.PhaseBuild,
		TurnNumber:  turn,
		ToolCalls:   []string{"read", "edit"},
		TokensIn:    100,
		TokensOut:   50,
		StopReason:  "tool_use",
		DurationMs:  250,
		Outcome:     "tool_use",
		Model:       "claude-sonnet-4-6",
		ModelReason: "phase-default",
	}
}
```

Add test:

```go
func TestEmitIncludesModelInfo(t *testing.T) {
	dir := t.TempDir()
	e := evidence.New(dir, "model")

	if err := e.Emit(makeEvidence(1)); err != nil {
		t.Fatalf("Emit: %v", err)
	}

	data, err := os.ReadFile(filepath.Join(dir, "model.jsonl"))
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}

	var ev agent.Evidence
	if err := json.Unmarshal([]byte(strings.TrimSpace(string(data))), &ev); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if ev.Model != "claude-sonnet-4-6" {
		t.Errorf("Model = %q, want claude-sonnet-4-6", ev.Model)
	}
	if ev.ModelReason != "phase-default" {
		t.Errorf("ModelReason = %q, want phase-default", ev.ModelReason)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/evidence/ -run TestEmitIncludesModelInfo -v`
Expected: FAIL — `Model` and `ModelReason` fields don't exist on Evidence

**Step 3: Add fields to Evidence struct**

In `internal/agent/deps.go`, add to the `Evidence` struct:

```go
Model       string `json:"model,omitempty"`
ModelReason string `json:"model_reason,omitempty"`
```

**Step 4: Wire model info into evidence emission in loop.go**

In `internal/agent/loop.go`, line ~44, capture the model and reason:

```go
model, modelReason := a.router.SelectModel(a.fsm.Current())
```

Then in the evidence construction (~line 110), add:

```go
ev := Evidence{
    // ... existing fields ...
    Model:       model,
    ModelReason: modelReason,
}
```

**Step 5: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/evidence/ -run TestEmitIncludesModelInfo -v`
Expected: PASS

**Step 6: Run all tests**

Run: `cd os/Skaffen && go test ./... -race`
Expected: All pass

**Step 7: Commit**

```bash
cd os/Skaffen && git add internal/agent/deps.go internal/agent/loop.go internal/evidence/emitter_test.go
git commit -m "feat(evidence): add Model and ModelReason to evidence (F5)"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./... -race`
  expect: exit 0
</verify>

---

### Task 7: Wire ICClient into main.go and router construction

**Files:**
- Modify: `cmd/skaffen/main.go`

This task connects the ICClient from Task 2's startup check to the router from Task 4.

**Step 1: Update runPrint() and runTUI() to use NewWithIC**

In both functions, replace:

```go
modelRouter := router.New(routerCfg)
```

with:

```go
modelRouter := router.NewWithIC(routerCfg, ic, sessionID)
```

The `ic` variable comes from `checkIntercore()` (Task 2). The `sessionID` is already computed in both functions.

**Step 2: Build and verify**

Run: `cd os/Skaffen && go build ./cmd/skaffen/`
Expected: Compiles cleanly — `ic` is now used (no unused variable warning)

**Step 3: Run all tests**

Run: `cd os/Skaffen && go test ./... -race`
Expected: All pass

**Step 4: Commit**

```bash
cd os/Skaffen && git add cmd/skaffen/main.go
git commit -m "feat(main): wire ICClient into router for override consumption and decision recording"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./cmd/skaffen/`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./... -race`
  expect: exit 0
</verify>

---

### Task 8: Final integration test and cleanup

**Files:**
- Modify: `internal/router/intercore_test.go` (add integration-style test)
- Verify: all packages build and test

**Step 1: Add end-to-end router test with overrides**

Add to `internal/router/intercore_test.go`:

```go
func TestNewWithIC_NilIC(t *testing.T) {
	// NewWithIC with nil IC should behave like New
	r := NewWithIC(&Config{}, nil, "test-session")
	model, reason := r.SelectModel(tool.PhaseBuild)
	if model != ModelSonnet {
		t.Errorf("nil IC: model = %q, want sonnet", model)
	}
	if reason != "phase-default" {
		t.Errorf("nil IC: reason = %q, want phase-default", reason)
	}
}

func TestNewWithIC_SessionID(t *testing.T) {
	r := NewWithIC(&Config{}, nil, "my-session")
	if r.sessionID != "my-session" {
		t.Errorf("sessionID = %q, want my-session", r.sessionID)
	}
}
```

**Step 2: Run full test suite**

Run: `cd os/Skaffen && go test ./... -race -count=1`
Expected: All pass

**Step 3: Run go vet**

Run: `cd os/Skaffen && go vet ./...`
Expected: No issues

**Step 4: Commit**

```bash
cd os/Skaffen && git add internal/router/intercore_test.go
git commit -m "test(router): add integration tests for NewWithIC and nil IC fallback"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./... -race -count=1`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go vet ./...`
  expect: exit 0
</verify>
