---
artifact_type: plan
bead: iv-ojik9
stage: design
---
# Intent Contract Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-ojik9
**Goal:** Define a typed intent contract between Apps (L3), OS (L2), and Kernel (L1) so policy-governing writes go through Clavain and app surfaces are swappable.

**Architecture:** Shared Go types in `core/intercore/pkg/contract/` define Intent and IntentResult structs. Clavain-cli gets a new `intent submit` command that validates, enforces policy, and delegates to the kernel. Autarch imports `intercore/pkg/contract` directly in `pkg/clavain/` (NOT via `pkg/contract/` which has different semantics). Intercom deferred (no current clavain integration exists).

**Tech Stack:** Go 1.22, modernc.org/sqlite (pure Go), clavain-cli binary, ic binary

**Prior Learnings:**
- `docs/solutions/database-issues/toctou-gate-check-cas-dispatch-intercore-20260221.md` — TOCTOU race in gate checks. Intent router must use CAS (compare-and-swap) when advancing phases.
- `docs/solutions/best-practices/silent-api-misuse-patterns-intercore-20260221.md` — Silent failures from wrong arg order to ic commands. Typed intents eliminate this class of bugs.
- `docs/solutions/patterns/intercore-schema-upgrade-deployment-20260218.md` — Schema migration patterns for Intercore SQLite.

**Critical Constraints (from plan review):**
- `apps/autarch/pkg/contract/types.go` already contains cross-tool entity types (Initiative, Epic, Story, etc.). Do NOT add intent re-exports there — it would create a namespace collision. Import `intercore/pkg/contract` directly in `pkg/clavain/`.
- `ic events emit` hard-rejects `--source` other than `review` (line 342 of `cmd/ic/events.go`). Audit logging must use the Go library `AddIntentEvent()` directly, not shell out to `ic`.
- `cmdBeadClaim` calls `os.Exit(1)` on active claim conflict (line 245 of `claim.go`). Use `cmdSprintClaim` for `sprint.claim` intents — it returns errors properly.
- TOCTOU race between gate check and phase advance is a known kernel-level limitation. Document it, don't advertise as atomic.
- Never pass params as `--params=<json>` CLI flag — visible in `/proc`. Use stdin piping.

---

### Task 1: Create Shared Intent Types Package

**Files:**
- Create: `core/intercore/pkg/contract/intent.go`
- Create: `core/intercore/pkg/contract/intent_test.go`
- Create: `core/intercore/pkg/contract/errors.go`

**Step 1: Write the failing test**

```go
// core/intercore/pkg/contract/intent_test.go
package contract

import (
	"testing"
	"time"
)

func TestIntentValidation(t *testing.T) {
	tests := []struct {
		name    string
		intent  Intent
		wantErr string
	}{
		{
			name: "valid sprint.advance",
			intent: Intent{
				Type:           IntentSprintAdvance,
				BeadID:         "iv-abc123",
				IdempotencyKey: "session-x-step-5",
				SessionID:      "sess-123",
				Timestamp:      time.Now().Unix(),
				Params:         map[string]any{"phase": "executing"},
			},
			wantErr: "",
		},
		{
			name: "missing type",
			intent: Intent{
				BeadID:         "iv-abc123",
				IdempotencyKey: "key-1",
				SessionID:      "sess-123",
				Timestamp:      time.Now().Unix(),
			},
			wantErr: "intent type is required",
		},
		{
			name: "missing idempotency key",
			intent: Intent{
				Type:      IntentSprintAdvance,
				BeadID:    "iv-abc123",
				SessionID: "sess-123",
				Timestamp: time.Now().Unix(),
			},
			wantErr: "idempotency key is required",
		},
		{
			name: "invalid intent type",
			intent: Intent{
				Type:           "invalid.type",
				BeadID:         "iv-abc123",
				IdempotencyKey: "key-1",
				SessionID:      "sess-123",
				Timestamp:      time.Now().Unix(),
			},
			wantErr: "unknown intent type",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.intent.Validate()
			if tt.wantErr == "" {
				if err != nil {
					t.Errorf("unexpected error: %v", err)
				}
			} else {
				if err == nil {
					t.Fatalf("expected error containing %q, got nil", tt.wantErr)
				}
				if !contains(err.Error(), tt.wantErr) {
					t.Errorf("error %q does not contain %q", err.Error(), tt.wantErr)
				}
			}
		})
	}
}

func TestIntentResultJSON(t *testing.T) {
	r := IntentResult{
		OK:         false,
		IntentType: IntentGateEnforce,
		BeadID:     "iv-abc123",
		Error: &IntentError{
			Code:          ErrGateBlocked,
			Detail:        "plan must be reviewed first",
			Remediation:   "Run /interflux:flux-drive on the plan",
		},
	}
	if r.OK {
		t.Error("expected OK to be false")
	}
	if r.Error.Code != ErrGateBlocked {
		t.Errorf("expected error code %s, got %s", ErrGateBlocked, r.Error.Code)
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsAt(s, substr))
}

func containsAt(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
```

**Step 2: Run test to verify it fails**

Run: `cd core/intercore && go test ./pkg/contract/ -v -run TestIntent`
Expected: FAIL — package doesn't exist yet

**Step 3: Write the intent types**

```go
// core/intercore/pkg/contract/intent.go
package contract

import "fmt"

// Intent type constants — all policy-governing mutations apps can submit.
const (
	// Sprint lifecycle
	IntentSprintCreate  = "sprint.create"
	IntentSprintAdvance = "sprint.advance"
	IntentSprintClaim   = "sprint.claim"
	IntentSprintRelease = "sprint.release"

	// Gate & policy
	IntentGateEnforce = "gate.enforce"
	IntentGateSkip    = "gate.skip"
	IntentBudgetCheck = "budget.check"
	IntentModelRoute  = "model.route"

	// Agent dispatch
	IntentAgentDispatch = "agent.dispatch"
	IntentAgentApprove  = "agent.approve"
	IntentAgentCancel   = "agent.cancel"
)

// validIntentTypes is the set of known intent types.
var validIntentTypes = map[string]bool{
	IntentSprintCreate:  true,
	IntentSprintAdvance: true,
	IntentSprintClaim:   true,
	IntentSprintRelease: true,
	IntentGateEnforce:   true,
	IntentGateSkip:      true,
	IntentBudgetCheck:   true,
	IntentModelRoute:    true,
	IntentAgentDispatch: true,
	IntentAgentApprove:  true,
	IntentAgentCancel:   true,
}

// Intent represents a typed, policy-governing mutation submitted by an app.
type Intent struct {
	Type           string         `json:"type"`
	BeadID         string         `json:"bead_id,omitempty"`
	IdempotencyKey string         `json:"idempotency_key"`
	SessionID      string         `json:"session_id"`
	Timestamp      int64          `json:"timestamp"`
	Params         map[string]any `json:"params,omitempty"`
}

// Validate checks required fields and type validity.
func (i *Intent) Validate() error {
	if i.Type == "" {
		return fmt.Errorf("intent type is required")
	}
	if !validIntentTypes[i.Type] {
		return fmt.Errorf("unknown intent type: %s", i.Type)
	}
	if i.IdempotencyKey == "" {
		return fmt.Errorf("idempotency key is required")
	}
	if i.SessionID == "" {
		return fmt.Errorf("session ID is required")
	}
	if i.Timestamp == 0 {
		return fmt.Errorf("timestamp is required")
	}
	return nil
}

// IntentResult is the structured response from the OS intent router.
type IntentResult struct {
	OK         bool           `json:"ok"`
	IntentType string         `json:"intent_type"`
	BeadID     string         `json:"bead_id,omitempty"`
	Data       map[string]any `json:"data,omitempty"`
	Error      *IntentError   `json:"error,omitempty"`
}

// IntentError is a structured, machine-readable error.
type IntentError struct {
	Code        ErrorCode `json:"code"`
	Detail      string    `json:"detail"`
	Remediation string    `json:"remediation,omitempty"`
}
```

**Step 4: Write the error codes**

```go
// core/intercore/pkg/contract/errors.go
package contract

// ErrorCode is a machine-readable error code for intent failures.
type ErrorCode string

const (
	ErrGateBlocked    ErrorCode = "GATE_BLOCKED"
	ErrClaimConflict  ErrorCode = "CLAIM_CONFLICT"
	ErrBudgetExceeded ErrorCode = "BUDGET_EXCEEDED"
	ErrInvalidIntent  ErrorCode = "INVALID_INTENT"
	ErrPhaseConflict  ErrorCode = "PHASE_CONFLICT"
	ErrNotFound       ErrorCode = "NOT_FOUND"
	ErrInternal       ErrorCode = "INTERNAL"
)
```

**Step 5: Run test to verify it passes**

Run: `cd core/intercore && go test ./pkg/contract/ -v -run TestIntent`
Expected: PASS

**Step 6: Commit**

```bash
cd core/intercore
git add pkg/contract/
git commit -m "feat(contract): add shared intent types for Apps-OS-Kernel contract

Defines Intent, IntentResult, IntentError structs and 11 canonical
intent type constants. These are the shared types that all layers
(Autarch, Clavain, Intercore) will use for typed communication.

Part of iv-ojik9."
```

---

### Task 2: Add `intent submit` Command to Clavain-CLI

**Files:**
- Modify: `os/clavain/cmd/clavain-cli/main.go:18-186` (add case to switch)
- Create: `os/clavain/cmd/clavain-cli/intent.go`
- Create: `os/clavain/cmd/clavain-cli/intent_test.go`
- Modify: `os/clavain/cmd/clavain-cli/go.mod` (add intercore dependency — note: clavain-cli has its own go.mod)

**Step 1: Write the failing test**

```go
// os/clavain/cmd/clavain-cli/intent_test.go
package main

import (
	"encoding/json"
	"testing"

	"github.com/mistakeknot/intercore/pkg/contract"
)

func TestParseIntentJSON(t *testing.T) {
	raw := `{
		"type": "sprint.advance",
		"bead_id": "iv-abc123",
		"idempotency_key": "sess-x-step-5",
		"session_id": "sess-123",
		"timestamp": 1772749697,
		"params": {"phase": "executing"}
	}`

	var intent contract.Intent
	if err := json.Unmarshal([]byte(raw), &intent); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if err := intent.Validate(); err != nil {
		t.Fatalf("validate: %v", err)
	}
	if intent.Type != contract.IntentSprintAdvance {
		t.Errorf("type = %s, want %s", intent.Type, contract.IntentSprintAdvance)
	}
	if intent.BeadID != "iv-abc123" {
		t.Errorf("bead_id = %s, want iv-abc123", intent.BeadID)
	}
}

func TestIntentResultMarshal(t *testing.T) {
	r := contract.IntentResult{
		OK:         true,
		IntentType: contract.IntentSprintAdvance,
		BeadID:     "iv-abc123",
		Data:       map[string]any{"from_phase": "planned", "to_phase": "executing"},
	}
	b, err := json.Marshal(r)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(b, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if decoded["ok"] != true {
		t.Error("expected ok=true")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/clavain && go test ./cmd/clavain-cli/ -v -run TestParseIntent`
Expected: FAIL — can't find intercore/pkg/contract

**Step 3: Add intercore dependency**

```bash
cd os/clavain/cmd/clavain-cli
go mod edit -replace github.com/mistakeknot/intercore=../../../../core/intercore
go mod tidy
```

**Step 4: Run test to verify it passes**

Run: `cd os/clavain/cmd/clavain-cli && go test . -v -run TestParseIntent`
Expected: PASS

**Step 5: Write the intent submit command handler**

```go
// os/clavain/cmd/clavain-cli/intent.go
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/mistakeknot/intercore/pkg/contract"
)

// cmdIntentSubmit handles: clavain-cli intent submit
// Accepts JSON intent payload on stdin (preferred — avoids /proc exposure).
// Also supports flags for simple intents without params.
func cmdIntentSubmit(args []string) error {
	var intent contract.Intent

	// Check for stdin JSON (piped input) — this is the primary path.
	// Params should NEVER be passed as CLI flags (visible in /proc/cmdline).
	stat, _ := os.Stdin.Stat()
	if (stat.Mode() & os.ModeCharDevice) == 0 {
		data, err := io.ReadAll(os.Stdin)
		if err != nil {
			return writeError(contract.ErrInvalidIntent, "failed to read stdin", "")
		}
		if err := json.Unmarshal(data, &intent); err != nil {
			return writeError(contract.ErrInvalidIntent, fmt.Sprintf("invalid JSON: %v", err), "")
		}
	} else {
		// Flags path: only for simple intents without sensitive params.
		// NOTE: --params is intentionally NOT supported as a flag (security: /proc exposure).
		var intentType string
		for i := 0; i < len(args); i++ {
			switch {
			case strings.HasPrefix(args[i], "--type="):
				intentType = strings.TrimPrefix(args[i], "--type=")
			case strings.HasPrefix(args[i], "--bead="):
				intent.BeadID = strings.TrimPrefix(args[i], "--bead=")
			case strings.HasPrefix(args[i], "--session="):
				intent.SessionID = strings.TrimPrefix(args[i], "--session=")
			case strings.HasPrefix(args[i], "--key="):
				intent.IdempotencyKey = strings.TrimPrefix(args[i], "--key=")
			}
		}
		intent.Type = intentType
	}

	// Validate
	if err := intent.Validate(); err != nil {
		return writeError(contract.ErrInvalidIntent, err.Error(), "")
	}

	// Route to handler
	result := routeIntent(&intent)

	// Output structured JSON
	return json.NewEncoder(os.Stdout).Encode(result)
}

// routeIntent dispatches a validated intent to the appropriate handler.
// This is the policy enforcement point — all writes go through here.
func routeIntent(intent *contract.Intent) *contract.IntentResult {
	switch intent.Type {
	case contract.IntentSprintAdvance:
		return handleSprintAdvance(intent)
	case contract.IntentSprintCreate:
		return handleSprintCreate(intent)
	case contract.IntentSprintClaim:
		return handleSprintClaim(intent)
	case contract.IntentSprintRelease:
		return handleSprintRelease(intent)
	case contract.IntentGateEnforce:
		return handleGateEnforce(intent)
	case contract.IntentBudgetCheck:
		return handleBudgetCheck(intent)
	default:
		return &contract.IntentResult{
			OK:         false,
			IntentType: intent.Type,
			BeadID:     intent.BeadID,
			Error: &contract.IntentError{
				Code:   contract.ErrInvalidIntent,
				Detail: fmt.Sprintf("intent type %q not yet implemented", intent.Type),
			},
		}
	}
}

// handleSprintAdvance wraps the existing cmdSprintAdvance logic with typed I/O.
// NOTE: TOCTOU limitation — there is a race between gate check and phase advance.
// This is a known kernel-level limitation (see docs/solutions/database-issues/toctou-gate-check-cas-dispatch-intercore-20260221.md).
// CAS-based atomic advance requires Intercore kernel changes (deferred to F5).
func handleSprintAdvance(intent *contract.Intent) *contract.IntentResult {
	phase, _ := intent.Params["phase"].(string)
	artifactPath, _ := intent.Params["artifact_path"].(string)

	args := []string{intent.BeadID, phase}
	if artifactPath != "" {
		args = append(args, artifactPath)
	}

	if err := cmdSprintAdvance(args); err != nil {
		errStr := err.Error()
		code := contract.ErrInternal
		remediation := ""
		switch {
		case strings.Contains(errStr, "gate") || strings.Contains(errStr, "blocked"):
			code = contract.ErrGateBlocked
			remediation = "Run /interflux:flux-drive on the plan"
		case strings.Contains(errStr, "phase"):
			code = contract.ErrPhaseConflict
		}
		return &contract.IntentResult{
			OK:         false,
			IntentType: intent.Type,
			BeadID:     intent.BeadID,
			Error:      &contract.IntentError{Code: code, Detail: errStr, Remediation: remediation},
		}
	}

	return &contract.IntentResult{
		OK:         true,
		IntentType: intent.Type,
		BeadID:     intent.BeadID,
		Data:       map[string]any{"phase": phase},
	}
}

// handleSprintCreate wraps cmdSprintCreate with typed I/O.
func handleSprintCreate(intent *contract.Intent) *contract.IntentResult {
	title, _ := intent.Params["title"].(string)
	if title == "" {
		title = "Untitled sprint"
	}

	args := []string{title}
	if err := cmdSprintCreate(args); err != nil {
		return &contract.IntentResult{
			OK:         false,
			IntentType: intent.Type,
			Error:      &contract.IntentError{Code: contract.ErrInternal, Detail: err.Error()},
		}
	}
	return &contract.IntentResult{
		OK:         true,
		IntentType: intent.Type,
		BeadID:     intent.BeadID,
	}
}

// handleSprintClaim wraps bead claiming with typed I/O.
// IMPORTANT: Uses cmdSprintClaim (not cmdBeadClaim) — cmdBeadClaim calls os.Exit(1)
// on active claim conflicts instead of returning an error, which would kill
// the entire clavain-cli process. cmdSprintClaim uses ic lock for proper
// concurrency control and returns errors cleanly.
func handleSprintClaim(intent *contract.Intent) *contract.IntentResult {
	args := []string{intent.BeadID, intent.SessionID}
	if err := cmdSprintClaim(args); err != nil {
		code := contract.ErrInternal
		if strings.Contains(err.Error(), "claimed") || strings.Contains(err.Error(), "conflict") || strings.Contains(err.Error(), "lock") {
			code = contract.ErrClaimConflict
		}
		return &contract.IntentResult{
			OK:         false,
			IntentType: intent.Type,
			BeadID:     intent.BeadID,
			Error:      &contract.IntentError{Code: code, Detail: err.Error()},
		}
	}
	return &contract.IntentResult{
		OK:         true,
		IntentType: intent.Type,
		BeadID:     intent.BeadID,
	}
}

// handleSprintRelease wraps bead release with typed I/O.
func handleSprintRelease(intent *contract.Intent) *contract.IntentResult {
	args := []string{intent.BeadID}
	if err := cmdBeadRelease(args); err != nil {
		return &contract.IntentResult{
			OK:         false,
			IntentType: intent.Type,
			BeadID:     intent.BeadID,
			Error:      &contract.IntentError{Code: contract.ErrInternal, Detail: err.Error()},
		}
	}
	return &contract.IntentResult{
		OK:         true,
		IntentType: intent.Type,
		BeadID:     intent.BeadID,
	}
}

// handleGateEnforce wraps gate enforcement with typed I/O.
func handleGateEnforce(intent *contract.Intent) *contract.IntentResult {
	targetPhase, _ := intent.Params["target_phase"].(string)
	artifactPath, _ := intent.Params["artifact_path"].(string)

	args := []string{intent.BeadID, targetPhase, artifactPath}
	if err := cmdEnforceGate(args); err != nil {
		return &contract.IntentResult{
			OK:         false,
			IntentType: intent.Type,
			BeadID:     intent.BeadID,
			Error: &contract.IntentError{
				Code:        contract.ErrGateBlocked,
				Detail:      err.Error(),
				Remediation: "Run /interflux:flux-drive on the plan to satisfy the gate precondition",
			},
		}
	}
	return &contract.IntentResult{
		OK:         true,
		IntentType: intent.Type,
		BeadID:     intent.BeadID,
	}
}

// handleBudgetCheck wraps budget checking with typed I/O.
func handleBudgetCheck(intent *contract.Intent) *contract.IntentResult {
	args := []string{intent.BeadID}
	if err := cmdBudgetRemaining(args); err != nil {
		return &contract.IntentResult{
			OK:         false,
			IntentType: intent.Type,
			BeadID:     intent.BeadID,
			Error:      &contract.IntentError{Code: contract.ErrBudgetExceeded, Detail: err.Error()},
		}
	}
	return &contract.IntentResult{
		OK:         true,
		IntentType: intent.Type,
		BeadID:     intent.BeadID,
	}
}

// writeError writes a structured error to stdout and returns nil (error already reported).
func writeError(code contract.ErrorCode, detail, remediation string) error {
	result := contract.IntentResult{
		OK: false,
		Error: &contract.IntentError{
			Code:        code,
			Detail:      detail,
			Remediation: remediation,
		},
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
```

**Step 6: Register the command in main.go**

Add to the switch statement in `os/clavain/cmd/clavain-cli/main.go` after the "Intent" comment, before the `case "help"` block (around line 167):

```go
	// Intent contract
	case "intent":
		if len(args) > 0 && args[0] == "submit" {
			err = cmdIntentSubmit(args[1:])
		} else {
			fmt.Fprintf(os.Stderr, "clavain-cli intent: unknown subcommand (use 'intent submit')\n")
			os.Exit(1)
		}
```

Also add to the help text in `printHelp()`:

```
Intent Contract:
  intent submit   Submit a typed intent (JSON on stdin preferred; flags: --type, --bead, --session, --key)
                  Params must be passed via stdin JSON, not as flags (security: /proc exposure)
```

**Step 7: Run tests**

Run: `cd os/clavain/cmd/clavain-cli && go test . -v -run TestIntent`
Expected: PASS

**Step 8: Build and smoke test**

Run: `cd os/clavain/cmd/clavain-cli && go build -o /tmp/clavain-cli-test .`
Run: `echo '{"type":"sprint.advance","bead_id":"iv-test","idempotency_key":"test-1","session_id":"test","timestamp":1772749697,"params":{"phase":"executing"}}' | /tmp/clavain-cli-test intent submit`
Expected: JSON output with `ok` field

**Step 9: Commit**

```bash
cd os/clavain
git add cmd/clavain-cli/intent.go cmd/clavain-cli/intent_test.go cmd/clavain-cli/main.go cmd/clavain-cli/go.mod cmd/clavain-cli/go.sum
git commit -m "feat(clavain-cli): add intent submit command for typed contract

New clavain-cli intent submit command accepts typed intent JSON
via stdin (preferred) or simple flags, validates, enforces policy,
and returns structured IntentResult JSON. Uses cmdSprintClaim for
claim intents (not cmdBeadClaim which os.Exit's on conflicts).

Part of iv-ojik9."
```

---

### Task 3: Add Intent Client Methods to Autarch

**Files:**
- Modify: `apps/autarch/pkg/clavain/client.go`
- Create: `apps/autarch/pkg/clavain/intent.go`
- Create: `apps/autarch/pkg/clavain/intent_test.go`

**Step 1: Add intercore dependency to Autarch**

```bash
cd apps/autarch
go mod edit -replace github.com/mistakeknot/intercore=../../core/intercore
go mod tidy
```

**Step 2: Write the failing test**

```go
// apps/autarch/pkg/clavain/intent_test.go
package clavain

import (
	"testing"

	"github.com/mistakeknot/intercore/pkg/contract"
)

func TestBuildIntent(t *testing.T) {
	intent := contract.Intent{
		Type:           contract.IntentSprintAdvance,
		BeadID:         "iv-abc123",
		IdempotencyKey: "sess-123-sprint.advance-iv-abc123",
		SessionID:      "sess-123",
		Timestamp:      1772749697,
		Params:         map[string]any{"phase": "executing"},
	}
	if err := intent.Validate(); err != nil {
		t.Fatalf("validate: %v", err)
	}
}
```

Note: Autarch imports `intercore/pkg/contract` directly — NOT via `autarch/pkg/contract/` which contains cross-tool entity types (Initiative, Epic, etc.) with different semantics.

**Step 3: Run test to verify it passes**

Run: `cd apps/autarch && go test ./pkg/clavain/ -v -run TestBuildIntent`
Expected: PASS

**Step 4: Write the intent submission method**

```go
// apps/autarch/pkg/clavain/intent.go
package clavain

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"time"

	"github.com/mistakeknot/intercore/pkg/contract"
)

// SubmitIntent sends a typed intent through clavain-cli via stdin and returns the structured result.
// Params are passed via stdin JSON (not CLI flags) to avoid /proc/cmdline exposure.
func (c *Client) SubmitIntent(ctx context.Context, intent *contract.Intent) (*contract.IntentResult, error) {
	if err := intent.Validate(); err != nil {
		return nil, fmt.Errorf("invalid intent: %w", err)
	}

	payload, err := json.Marshal(intent)
	if err != nil {
		return nil, fmt.Errorf("marshal intent: %w", err)
	}

	// Pipe JSON via stdin — never pass params as CLI flags (visible in /proc)
	cmd := exec.CommandContext(ctx, c.cliPath, "intent", "submit")
	cmd.Stdin = bytes.NewReader(payload)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("intent submit: %w", err)
	}

	var result contract.IntentResult
	if err := json.Unmarshal(out, &result); err != nil {
		return nil, fmt.Errorf("unmarshal intent result: %w", err)
	}
	return &result, nil
}

// SprintAdvanceIntent submits a typed sprint.advance intent.
// Idempotency key is deterministic: session+type+bead — safe for retries.
func (c *Client) SprintAdvanceIntent(ctx context.Context, beadID, phase, sessionID string) (*contract.IntentResult, error) {
	return c.SubmitIntent(ctx, &contract.Intent{
		Type:           contract.IntentSprintAdvance,
		BeadID:         beadID,
		IdempotencyKey: fmt.Sprintf("%s-sprint.advance-%s", sessionID, beadID),
		SessionID:      sessionID,
		Timestamp:      time.Now().Unix(),
		Params:         map[string]any{"phase": phase},
	})
}

// GateEnforceIntent submits a typed gate.enforce intent.
// Idempotency key is deterministic: session+gate+phase+bead — safe for retries.
func (c *Client) GateEnforceIntent(ctx context.Context, beadID, targetPhase, artifactPath, sessionID string) (*contract.IntentResult, error) {
	return c.SubmitIntent(ctx, &contract.Intent{
		Type:           contract.IntentGateEnforce,
		BeadID:         beadID,
		IdempotencyKey: fmt.Sprintf("%s-gate-%s-%s", sessionID, targetPhase, beadID),
		SessionID:      sessionID,
		Timestamp:      time.Now().Unix(),
		Params:         map[string]any{"target_phase": targetPhase, "artifact_path": artifactPath},
	})
}
```

**Step 5: Verify build**

Run: `cd apps/autarch && go build ./...`
Expected: PASS

**Step 6: Commit**

```bash
cd apps/autarch
git add go.mod go.sum pkg/clavain/intent.go pkg/clavain/intent_test.go
git commit -m "feat(autarch): add typed intent submission via stdin pipe

SubmitIntent pipes JSON to clavain-cli stdin (not CLI flags, avoids
/proc exposure). SprintAdvanceIntent and GateEnforceIntent use
deterministic idempotency keys (session+type+bead) for safe retries.
Imports intercore/pkg/contract directly (not via pkg/contract/).

Part of iv-ojik9."
```

---

### Task 4: Add Intent Event Logging to Intercore

**Files:**
- Modify: `core/intercore/internal/event/event.go` (add SourceIntent constant)
- Modify: `core/intercore/internal/event/store.go` (add AddIntentEvent method)
- Create: `core/intercore/internal/event/intent_test.go`

**Step 1: Write the failing test**

```go
// core/intercore/internal/event/intent_test.go
package event

import (
	"context"
	"database/sql"
	"testing"

	_ "modernc.org/sqlite"
)

func TestAddIntentEvent(t *testing.T) {
	db := setupTestDB(t)
	defer db.Close()

	store := NewStore(db)
	err := store.AddIntentEvent(context.Background(),
		"sprint.advance",   // intent type
		"iv-abc123",        // bead ID
		"sess-x-step-5",   // idempotency key
		"sess-123",         // session ID
		"",                 // run ID (may not exist yet)
		true,               // success
		"",                 // error detail
	)
	if err != nil {
		t.Fatalf("AddIntentEvent: %v", err)
	}
}

func setupTestDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	db.SetMaxOpenConns(1)

	// Create the intent_events table
	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS intent_events (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		intent_type TEXT NOT NULL,
		bead_id TEXT NOT NULL,
		idempotency_key TEXT NOT NULL,
		session_id TEXT NOT NULL,
		run_id TEXT,
		success INTEGER NOT NULL DEFAULT 0,
		error_detail TEXT,
		created_at INTEGER NOT NULL DEFAULT (unixepoch())
	)`)
	if err != nil {
		t.Fatal(err)
	}
	return db
}
```

**Step 2: Run test to verify it fails**

Run: `cd core/intercore && go test ./internal/event/ -v -run TestAddIntentEvent`
Expected: FAIL — AddIntentEvent method doesn't exist

**Step 3: Add SourceIntent constant**

Add to `core/intercore/internal/event/event.go` line 12 (after `SourceReview`):

```go
	SourceIntent = "intent"
```

**Step 4: Add AddIntentEvent method to store**

Add to `core/intercore/internal/event/store.go`:

```go
// AddIntentEvent records an intent submission event for audit trail.
func (s *Store) AddIntentEvent(ctx context.Context, intentType, beadID, idempotencyKey, sessionID, runID string, success bool, errorDetail string) error {
	errorDetail = s.redactStr(errorDetail)

	successInt := 0
	if success {
		successInt = 1
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO intent_events (
			intent_type, bead_id, idempotency_key, session_id, run_id, success, error_detail
		) VALUES (?, ?, ?, ?, NULLIF(?, ''), ?, NULLIF(?, ''))`,
		intentType, beadID, idempotencyKey, sessionID, runID, successInt, errorDetail,
	)
	if err != nil {
		return fmt.Errorf("add intent event: %w", err)
	}
	return nil
}
```

**Step 5: Run test to verify it passes**

Run: `cd core/intercore && go test ./internal/event/ -v -run TestAddIntentEvent`
Expected: PASS

**Step 6: Add schema migration**

Check current user_version and add migration for `intent_events` table. This follows the pattern from `docs/solutions/patterns/intercore-schema-upgrade-deployment-20260218.md`.

Add to the migration chain in `core/intercore/cmd/ic/migrate.go` (or equivalent):

```sql
CREATE TABLE IF NOT EXISTS intent_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    intent_type TEXT NOT NULL,
    bead_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    session_id TEXT NOT NULL,
    run_id TEXT,
    success INTEGER NOT NULL DEFAULT 0,
    error_detail TEXT,
    created_at INTEGER NOT NULL DEFAULT (unixepoch())
);
CREATE INDEX IF NOT EXISTS idx_intent_events_bead ON intent_events(bead_id);
CREATE INDEX IF NOT EXISTS idx_intent_events_idem ON intent_events(idempotency_key);
```

**Step 7: Commit**

```bash
cd core/intercore
git add internal/event/ cmd/ic/
git commit -m "feat(intercore): add intent event audit logging

New intent_events table and AddIntentEvent store method for
recording all intent submissions (success and failure) as an
audit trail. Indexed by bead_id and idempotency_key.

Part of iv-ojik9."
```

---

### Task 5: Wire Intent Audit Logging into Clavain Router

**Files:**
- Modify: `os/clavain/cmd/clavain-cli/intent.go` (add audit logging after each intent)

> **CRITICAL:** `ic events emit` hard-rejects `--source` other than `review` (line 342 of `core/intercore/cmd/ic/events.go`).
> Do NOT shell out to `ic events emit --source=intent` — it will always fail.
> Instead, import `core/intercore/internal/event` as a Go library and call `AddIntentEvent()` directly.
> This is feasible because clavain-cli already depends on intercore (added in Task 2).

**Step 1: Add audit logging call after routeIntent**

In `cmdIntentSubmit`, after `result := routeIntent(&intent)`, add:

```go
	// Audit log: record every intent submission to intercore events
	logIntentEvent(&intent, result)
```

**Step 2: Write the logging function**

Add to `intent.go`:

```go
// logIntentEvent records the intent submission in Intercore's event store.
// Uses Go library call directly — ic events emit rejects --source=intent.
// Fails silently — audit logging must not block intent execution.
func logIntentEvent(intent *contract.Intent, result *contract.IntentResult) {
	dbPath := findICDB()
	if dbPath == "" {
		return // No DB found — skip audit silently
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return
	}
	defer db.Close()
	db.SetMaxOpenConns(1)

	store := event.NewStore(db)
	errorDetail := ""
	if result.Error != nil {
		errorDetail = string(result.Error.Code) + ": " + result.Error.Detail
	}

	_ = store.AddIntentEvent(
		context.Background(),
		intent.Type,
		intent.BeadID,
		intent.IdempotencyKey,
		intent.SessionID,
		"", // run ID — may not exist yet
		result.OK,
		errorDetail,
	)
}

// findICDB locates the intercore database file.
func findICDB() string {
	// Check standard locations
	candidates := []string{
		".ic.db",
		os.Getenv("IC_DB"),
	}
	for _, c := range candidates {
		if c != "" {
			if _, err := os.Stat(c); err == nil {
				return c
			}
		}
	}
	return ""
}
```

Note: Add these imports to intent.go:
```go
import (
	"context"
	"database/sql"
	// ... existing imports ...
	"github.com/mistakeknot/intercore/internal/event"
	_ "modernc.org/sqlite"
)
```

**Step 3: Verify build**

Run: `cd os/clavain/cmd/clavain-cli && go build .`
Expected: PASS

**Step 4: Commit**

```bash
cd os/clavain
git add cmd/clavain-cli/intent.go cmd/clavain-cli/go.mod cmd/clavain-cli/go.sum
git commit -m "feat(clavain-cli): wire intent audit logging via Go library call

Every intent submission (success or failure) is recorded in
Intercore's intent_events table. Uses Go library AddIntentEvent()
directly — ic events emit rejects --source=intent.
Logging is best-effort and never blocks intent execution.

Part of iv-ojik9."
```

---

### Task 6: Architecture Note and Completion

**Files:**
- Modify: `docs/brainstorms/2026-03-05-intent-contract-brainstorm.md` (add implementation status)
- Create: `docs/architecture/intent-contract.md`

**Step 1: Write the architecture note**

```markdown
# Intent Contract Architecture

**Status:** Phase 1-2 implemented (shared types + OS router). Phase 3 (Autarch migration) has client methods ready. Phase 4 (Intercom) deferred — no current clavain integration exists.

## Layer Boundaries

```
┌─────────────┐   ┌─────────────┐
│   Autarch   │   │  Intercom   │   L3: App surfaces
│  (Go CLI)   │   │ (TS/Rust)   │   Submit typed intents
└──────┬──────┘   └──────┬──────┘
       │                 │
       │   Intent{type, bead_id, idempotency_key, ...}
       │                 │
┌──────▼─────────────────▼──────┐
│          Clavain (OS)          │   L2: Policy enforcement
│  clavain-cli intent submit     │   Validates, routes, audits
└──────────────┬─────────────────┘
               │
               │   ic (CLI) / future: library
               │
┌──────────────▼─────────────────┐
│        Intercore (Kernel)       │   L1: Durable state
│    SQLite WAL, events, gates    │   Persists, queries
└────────────────────────────────┘
```

## Shared Types

Package: `core/intercore/pkg/contract/`

- `Intent` — typed mutation request with idempotency key
- `IntentResult` — structured response with machine-readable error codes
- `IntentError` — code + detail + remediation
- 11 intent types across sprint lifecycle, gates, budget, agent dispatch

## Error Codes

| Code | Meaning |
|------|---------|
| `GATE_BLOCKED` | Gate precondition not met |
| `CLAIM_CONFLICT` | Bead already claimed by another session |
| `BUDGET_EXCEEDED` | Token budget exhausted |
| `INVALID_INTENT` | Malformed or unknown intent type |
| `PHASE_CONFLICT` | Phase transition not allowed |
| `NOT_FOUND` | Bead or resource not found |
| `INTERNAL` | Unexpected error |

## Known Limitations

- **TOCTOU race:** Gate check and phase advance are not atomic — a concurrent session could modify state between the check and the write. This is a kernel-level limitation requiring CAS (compare-and-swap) support in Intercore. Documented in `docs/solutions/database-issues/toctou-gate-check-cas-dispatch-intercore-20260221.md`.

## Future Work

- **F4: Intercom migration** — Intercom currently has zero clavain integration. When it adds one, it should use typed intents from the start.
- **F5: Kernel library bindings** — Replace `ic` CLI shelling with `core/intercore/pkg/client/` Go library for ~50ms latency reduction per intent.
- **Idempotency dedup** — Cache intent results by idempotency key (in-memory or SQLite).
- **MCP transport** — Expose intents as MCP tool calls via Clavain's existing MCP server.
- **Atomic gate+advance** — Requires Intercore kernel CAS support (F5 prerequisite).
```

**Step 2: Commit**

```bash
git add docs/architecture/intent-contract.md
git commit -m "docs: add intent contract architecture note

Documents the layer boundaries, shared types, error codes, and
future work for the Apps-OS-Kernel intent contract.

Part of iv-ojik9."
```

---

## Dependency Graph

```
Task 1 (shared types) ──► Task 2 (clavain-cli intent submit) ──► Task 5 (audit wiring)
         │                         │
         │                         └──► Task 3 (Autarch client)
         │
         └──► Task 4 (intercore event logging) ──► Task 5 (audit wiring)

Task 6 (architecture note) — independent
```

## Scope Note: Deferred Features

- **F4 (Intercom migration):** Intercom has zero references to clavain-cli. There's no SylvesteAdapter to migrate. When Intercom adds clavain integration, it should use typed intents from the start rather than building a string-based adapter first. Deferred entirely.
- **F5 (Kernel library bindings):** Optional performance optimization. The CLI path works. Deferred to a follow-up bead.
- **Idempotency dedup cache:** Tracked in the architecture note as future work. The idempotency key is in the contract types and audit log, but dedup enforcement is deferred.
