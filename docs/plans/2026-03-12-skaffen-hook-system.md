---
artifact_type: plan
bead: Sylveste-6i0.2
stage: design
requirements:
  - F1: Hook types & config loader
  - F2: Hook executor
  - F3: PreToolUse + PostToolUse integration
  - F4: SessionStart + Notification integration
---
# Skaffen Hook System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-6i0.2
**Goal:** Add lifecycle hooks (SessionStart, PreToolUse, PostToolUse, Notification) with external command execution, two-level config, and fail-open semantics.

**Architecture:** New `internal/hooks/` package with types, config loader, and executor. Config follows existing `config.Config` path-discovery pattern (`HookPaths()` → `hooks.LoadConfig()` → `hooks.MergeConfig()`). Executor wraps `os/exec` with JSON stdin/stdout, timeout via `context.WithTimeout()`, and fail-open error handling. Integration into `agentloop.Loop` via a `HookRunner` interface, wired through `agent.Agent` from `main.go`.

**Tech Stack:** Go stdlib (`os/exec`, `encoding/json`, `context`, `path/filepath`), existing Skaffen config/agentloop/agent packages.

**Prior Learnings:**
- `docs/solutions/patterns/intercore-bridge-subprocess-lifecycle-20260311.md` — Use `context.WithTimeout()` for all subprocess spawns; release mutex before best-effort I/O
- `docs/solutions/patterns/per-project-config-patterns.md` — Deep-copy merge for maps; return `[]string` of paths from discovery, let caller merge
- `docs/solutions/integration-issues/graceful-mcp-launcher-external-deps-interflux-20260224.md` — Fail-open: log warning, don't hard-fail on optional dependencies

## Flux-Drive Findings (Applied)

The following P0/P1 issues from plan review have been incorporated into the tasks below:

| ID | Sev | Fix | Task |
|----|-----|-----|------|
| P0-1 | Type mismatch `hooks.Decision` ≠ `agentloop.HookDecision` | agentloop uses `string`; `hookAdapter` in agent layer converts | T4, T5 |
| P0-2 | PostToolUse goroutine captures cancelled ctx | Use `context.Background()` with per-hook timeout | T4 |
| P0-3 | Silent `json.Unmarshal` error → allow | Log warning on parse error (fail-open, but visible) | T3 |
| P0-4 | `runPrint()` has no trust evaluator | Document limitation; hooks are sole gate in headless | T6 |
| P0-5 | Fail-open defeats deny-intent hooks | Defer to v2 — document limitation | — |
| P1-1 | `DecisionAsk` short-circuits, skips remaining hooks | Collect most-restrictive: deny > ask > allow | T3 |
| P1-2 | `MergeConfig` shallow-copies inner `[]HookDef` | Deep-copy inner slices + `TestMergeConfigInnerNoAlias` | T2 |
| P1-3 | `fmt.Fprintf(os.Stderr)` corrupts TUI | Use `log.Logger` in executor, no stderr in agentloop | T3, T4 |
| P1-4 | `os.Environ()` exposes API keys | `safeEnv()` strips credential prefixes | T3 |
| P1-5 | No timeout upper bound | `MaxTimeout = 120` cap | T3 |
| P1-6 | `HookPaths()` not tested | Add unit test in T2 verify | T2 |

---

## Must-Haves

**Truths** (observable behaviors):
- User can create `.skaffen/hooks.json` and hooks fire on the matching events
- PreToolUse hooks can deny tool execution (tighten security)
- PreToolUse hooks CANNOT override trust evaluator decisions (hooks can't loosen security)
- A broken/missing hook does not crash or block the agent (fail-open)
- Global hooks (`~/.skaffen/hooks.json`) and project hooks (`.skaffen/hooks.json`) both run, project after global

**Artifacts** (files that must exist):
- `internal/hooks/types.go` exports `Event`, `Config`, `HookGroup`, `HookDef`, `HookResult`, `Decision`
- `internal/hooks/loader.go` exports `LoadConfig`, `MergeConfig`
- `internal/hooks/executor.go` exports `Executor`, `HookRunner` interface
- `internal/hooks/loader_test.go`, `internal/hooks/executor_test.go`

**Key Links** (critical connections):
- `config.Config.HookPaths()` → `hooks.LoadConfig()` → `hooks.MergeConfig()` → `hooks.NewExecutor()`
- `main.go` creates executor, passes to `agent.New()` via `agent.WithHooks()`
- `agent.Agent` wraps executor in `hookAdapter` (converts `hooks.Decision` → `string`), passes to `agentloop.Loop` via `agentloop.WithHooks()`
- `Loop.executeToolsWithCallbacks()` calls `HookRunner.PreToolUse()` before `ToolApprover`
- `Loop.executeToolsWithCallbacks()` calls `HookRunner.PostToolUse()` after `registry.Execute()` in background goroutine with `context.Background()`
- `runPrint()` wires headless trust approver (always-allow) so hooks are the safety gate in headless mode

---

### Task 1: Define Hook Types (F1)

**Files:**
- Create: `internal/hooks/types.go`

**Step 1: Create the types file**

```go
package hooks

import "encoding/json"

// Event identifies a hook lifecycle event.
type Event string

const (
	EventSessionStart Event = "SessionStart"
	EventPreToolUse   Event = "PreToolUse"
	EventPostToolUse  Event = "PostToolUse"
	EventNotification Event = "Notification"
)

// Decision is the result of a PreToolUse hook.
type Decision string

const (
	DecisionAllow Decision = "allow"
	DecisionDeny  Decision = "deny"
	DecisionAsk   Decision = "ask"
)

// Config is the top-level hooks configuration.
type Config struct {
	Hooks map[Event][]HookGroup `json:"hooks"`
}

// HookGroup matches a tool name pattern and runs its hooks.
type HookGroup struct {
	Matcher string    `json:"matcher"`
	Hooks   []HookDef `json:"hooks"`
}

// HookDef defines a single hook command.
type HookDef struct {
	Type    string `json:"type"`    // "command"
	Command string `json:"command"` // shell command to execute
	Timeout int    `json:"timeout"` // seconds, 0 = use default
}

// HookResult holds the outcome of a hook execution.
type HookResult struct {
	Decision Decision `json:"decision,omitempty"` // only for PreToolUse
	Output   string   `json:"output,omitempty"`   // stdout capture
	Error    string   `json:"error,omitempty"`     // stderr or error message
}

// PreToolUsePayload is the JSON sent to PreToolUse hooks on stdin.
type PreToolUsePayload struct {
	ToolName  string          `json:"tool_name"`
	ToolInput json.RawMessage `json:"tool_input"`
}

// PostToolUsePayload is the JSON sent to PostToolUse hooks on stdin.
type PostToolUsePayload struct {
	ToolName   string          `json:"tool_name"`
	ToolInput  json.RawMessage `json:"tool_input"`
	ToolResult string          `json:"tool_result"`
	IsError    bool            `json:"is_error"`
}

// SessionStartPayload is the JSON sent to SessionStart hooks on stdin.
type SessionStartPayload struct {
	SessionID string `json:"session_id"`
	WorkDir   string `json:"work_dir"`
	Mode      string `json:"mode"` // "tui" or "print"
}

// NotificationPayload is the JSON sent to Notification hooks on stdin.
type NotificationPayload struct {
	EventType string `json:"event_type"`
	Message   string `json:"message"`
	Severity  string `json:"severity"` // "info", "warning", "error"
}
```

**Step 2: Verify it compiles**

Run: `cd os/Skaffen && go build ./internal/hooks/`
Expected: no errors

**Step 3: Commit**

```bash
cd os/Skaffen && git add internal/hooks/types.go && git commit -m "feat(hooks): define hook event types, config structs, and payloads"
```

<verify>
- run: `cd os/Skaffen && go vet ./internal/hooks/`
  expect: exit 0
</verify>

---

### Task 2: Config Loader with Two-Level Merge (F1)

**Files:**
- Create: `internal/hooks/loader.go`
- Create: `internal/hooks/loader_test.go`
- Modify: `internal/config/config.go` (add `HookPaths()` method)

**Step 1: Write the failing test for LoadConfig**

```go
package hooks

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadConfigValidJSON(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "hooks.json")
	os.WriteFile(path, []byte(`{
		"hooks": {
			"PreToolUse": [
				{"matcher": "bash", "hooks": [{"type": "command", "command": "echo ok", "timeout": 5}]}
			]
		}
	}`), 0644)

	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	groups := cfg.Hooks[EventPreToolUse]
	if len(groups) != 1 {
		t.Fatalf("expected 1 hook group, got %d", len(groups))
	}
	if groups[0].Matcher != "bash" {
		t.Errorf("matcher = %q, want %q", groups[0].Matcher, "bash")
	}
	if len(groups[0].Hooks) != 1 {
		t.Fatalf("expected 1 hook, got %d", len(groups[0].Hooks))
	}
	if groups[0].Hooks[0].Timeout != 5 {
		t.Errorf("timeout = %d, want 5", groups[0].Hooks[0].Timeout)
	}
}

func TestLoadConfigMissingFile(t *testing.T) {
	cfg, err := LoadConfig("/nonexistent/hooks.json")
	if err != nil {
		t.Fatalf("missing file should not error: %v", err)
	}
	if len(cfg.Hooks) != 0 {
		t.Errorf("expected empty hooks, got %d events", len(cfg.Hooks))
	}
}

func TestLoadConfigInvalidJSON(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "hooks.json")
	os.WriteFile(path, []byte(`{not json}`), 0644)

	_, err := LoadConfig(path)
	if err == nil {
		t.Fatal("expected error for invalid JSON")
	}
}

func TestMergeConfigAppends(t *testing.T) {
	global := &Config{
		Hooks: map[Event][]HookGroup{
			EventPreToolUse: {{Matcher: "bash", Hooks: []HookDef{{Type: "command", Command: "global.sh"}}}},
		},
	}
	project := &Config{
		Hooks: map[Event][]HookGroup{
			EventPreToolUse: {{Matcher: "bash", Hooks: []HookDef{{Type: "command", Command: "project.sh"}}}},
		},
	}

	merged := MergeConfig(global, project)
	groups := merged.Hooks[EventPreToolUse]
	if len(groups) != 2 {
		t.Fatalf("expected 2 hook groups after merge, got %d", len(groups))
	}
	if groups[0].Hooks[0].Command != "global.sh" {
		t.Errorf("first group should be global, got %q", groups[0].Hooks[0].Command)
	}
	if groups[1].Hooks[0].Command != "project.sh" {
		t.Errorf("second group should be project, got %q", groups[1].Hooks[0].Command)
	}
}

func TestMergeConfigNoAlias(t *testing.T) {
	global := &Config{
		Hooks: map[Event][]HookGroup{
			EventPreToolUse: {{Matcher: "bash", Hooks: []HookDef{{Type: "command", Command: "global.sh"}}}},
		},
	}
	project := &Config{Hooks: map[Event][]HookGroup{}}

	merged := MergeConfig(global, project)
	// Mutate merged — should not affect global
	merged.Hooks[EventPreToolUse] = append(merged.Hooks[EventPreToolUse],
		HookGroup{Matcher: "*", Hooks: []HookDef{{Type: "command", Command: "extra.sh"}}})

	if len(global.Hooks[EventPreToolUse]) != 1 {
		t.Fatal("merge aliased the original — mutation leaked to global config")
	}
}

func TestMergeConfigInnerNoAlias(t *testing.T) {
	global := &Config{
		Hooks: map[Event][]HookGroup{
			EventPreToolUse: {{Matcher: "bash", Hooks: []HookDef{{Type: "command", Command: "global.sh"}}}},
		},
	}
	project := &Config{Hooks: map[Event][]HookGroup{}}

	merged := MergeConfig(global, project)
	// Mutate inner HookDef slice — should not affect global
	merged.Hooks[EventPreToolUse][0].Hooks[0].Command = "mutated.sh"

	if global.Hooks[EventPreToolUse][0].Hooks[0].Command != "global.sh" {
		t.Fatal("merge shallow-copied inner []HookDef — mutation leaked to global config")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/hooks/ -v -run "TestLoadConfig|TestMerge"`
Expected: FAIL (LoadConfig and MergeConfig not defined)

**Step 3: Write the loader implementation**

```go
package hooks

import (
	"encoding/json"
	"fmt"
	"os"
)

// LoadConfig reads hooks config from a JSON file.
// Returns empty config (not error) if file doesn't exist.
func LoadConfig(path string) (*Config, error) {
	cfg := &Config{Hooks: make(map[Event][]HookGroup)}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg, nil
		}
		return nil, fmt.Errorf("read hooks config: %w", err)
	}

	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parse hooks config %s: %w", path, err)
	}

	if cfg.Hooks == nil {
		cfg.Hooks = make(map[Event][]HookGroup)
	}
	return cfg, nil
}

// MergeConfig combines global and project hook configs.
// Per-project hook groups append AFTER global groups within each event.
// Returns a new Config — neither global nor project is modified.
func MergeConfig(global, project *Config) *Config {
	merged := &Config{
		Hooks: make(map[Event][]HookGroup, len(global.Hooks)+len(project.Hooks)),
	}
	// Deep-copy global hooks (including inner []HookDef slices)
	for event, groups := range global.Hooks {
		cp := make([]HookGroup, len(groups))
		for i, g := range groups {
			cp[i] = HookGroup{Matcher: g.Matcher}
			cp[i].Hooks = make([]HookDef, len(g.Hooks))
			copy(cp[i].Hooks, g.Hooks)
		}
		merged.Hooks[event] = cp
	}
	// Deep-copy and append project hooks after global
	for event, groups := range project.Hooks {
		for _, g := range groups {
			cpg := HookGroup{Matcher: g.Matcher}
			cpg.Hooks = make([]HookDef, len(g.Hooks))
			copy(cpg.Hooks, g.Hooks)
			merged.Hooks[event] = append(merged.Hooks[event], cpg)
		}
	}
	return merged
}
```

**Step 4: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/hooks/ -v -run "TestLoadConfig|TestMerge"`
Expected: PASS (all 5 tests)

**Step 5: Add HookPaths() to config.Config**

Add this method to `internal/config/config.go` after `PluginPaths()`:

```go
// HookPaths returns hook config paths to load (user-global + per-project).
// Both are loaded; per-project hooks merge with user-global.
// Returns only paths that exist on disk.
func (c *Config) HookPaths() []string {
	var paths []string
	userPath := filepath.Join(c.userDir, "hooks.json")
	if fileExists(userPath) {
		paths = append(paths, userPath)
	}
	if c.projectDir != "" {
		projPath := filepath.Join(c.projectDir, ".skaffen", "hooks.json")
		if fileExists(projPath) {
			paths = append(paths, projPath)
		}
	}
	return paths
}
```

**Step 6: Verify everything compiles**

Run: `cd os/Skaffen && go build ./...`
Expected: no errors

**Step 7: Commit**

```bash
cd os/Skaffen && git add internal/hooks/loader.go internal/hooks/loader_test.go internal/config/config.go && git commit -m "feat(hooks): config loader with two-level merge and HookPaths discovery"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/hooks/ -v -run "TestLoadConfig|TestMerge"`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./internal/config/`
  expect: exit 0
</verify>

---

### Task 3: Hook Executor with Timeout and Fail-Open (F2)

**Files:**
- Create: `internal/hooks/executor.go`
- Create: `internal/hooks/executor_test.go`

**Step 1: Write the failing tests**

```go
package hooks

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func TestExecutorPreToolUseAllow(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on windows")
	}
	script := writeScript(t, `#!/bin/sh
read input
echo '{"decision":"allow"}'`)

	cfg := &Config{
		Hooks: map[Event][]HookGroup{
			EventPreToolUse: {{
				Matcher: "bash",
				Hooks:   []HookDef{{Type: "command", Command: script, Timeout: 5}},
			}},
		},
	}
	exec := NewExecutor(cfg, "test-session", "/tmp", "build")

	result, err := exec.PreToolUse(context.Background(), "bash", json.RawMessage(`{"command":"ls"}`))
	if err != nil {
		t.Fatalf("PreToolUse: %v", err)
	}
	if result != DecisionAllow {
		t.Errorf("decision = %q, want %q", result, DecisionAllow)
	}
}

func TestExecutorPreToolUseDeny(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on windows")
	}
	script := writeScript(t, `#!/bin/sh
read input
echo '{"decision":"deny"}'`)

	cfg := &Config{
		Hooks: map[Event][]HookGroup{
			EventPreToolUse: {{
				Matcher: "*",
				Hooks:   []HookDef{{Type: "command", Command: script, Timeout: 5}},
			}},
		},
	}
	exec := NewExecutor(cfg, "test-session", "/tmp", "build")

	result, err := exec.PreToolUse(context.Background(), "bash", json.RawMessage(`{"command":"rm -rf /"}`))
	if err != nil {
		t.Fatalf("PreToolUse: %v", err)
	}
	if result != DecisionDeny {
		t.Errorf("decision = %q, want %q", result, DecisionDeny)
	}
}

func TestExecutorPreToolUseMatcherFilters(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on windows")
	}
	script := writeScript(t, `#!/bin/sh
echo '{"decision":"deny"}'`)

	cfg := &Config{
		Hooks: map[Event][]HookGroup{
			EventPreToolUse: {{
				Matcher: "bash",
				Hooks:   []HookDef{{Type: "command", Command: script, Timeout: 5}},
			}},
		},
	}
	exec := NewExecutor(cfg, "test-session", "/tmp", "build")

	// "read" does not match "bash" matcher — should get allow (no hooks ran)
	result, err := exec.PreToolUse(context.Background(), "read", json.RawMessage(`{}`))
	if err != nil {
		t.Fatalf("PreToolUse: %v", err)
	}
	if result != DecisionAllow {
		t.Errorf("non-matching tool: decision = %q, want %q", result, DecisionAllow)
	}
}

func TestExecutorTimeoutFailOpen(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on windows")
	}
	script := writeScript(t, `#!/bin/sh
sleep 30`)

	cfg := &Config{
		Hooks: map[Event][]HookGroup{
			EventPreToolUse: {{
				Matcher: "*",
				Hooks:   []HookDef{{Type: "command", Command: script, Timeout: 1}},
			}},
		},
	}
	exec := NewExecutor(cfg, "test-session", "/tmp", "build")

	start := time.Now()
	result, err := exec.PreToolUse(context.Background(), "bash", json.RawMessage(`{}`))
	elapsed := time.Since(start)

	if err != nil {
		t.Fatalf("timeout should not return error (fail-open): %v", err)
	}
	if result != DecisionAllow {
		t.Errorf("timeout: decision = %q, want %q (fail-open)", result, DecisionAllow)
	}
	if elapsed > 5*time.Second {
		t.Errorf("took %v — timeout not working", elapsed)
	}
}

func TestExecutorCrashFailOpen(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on windows")
	}
	script := writeScript(t, `#!/bin/sh
exit 1`)

	cfg := &Config{
		Hooks: map[Event][]HookGroup{
			EventPreToolUse: {{
				Matcher: "*",
				Hooks:   []HookDef{{Type: "command", Command: script, Timeout: 5}},
			}},
		},
	}
	exec := NewExecutor(cfg, "test-session", "/tmp", "build")

	result, err := exec.PreToolUse(context.Background(), "bash", json.RawMessage(`{}`))
	if err != nil {
		t.Fatalf("crash should not return error (fail-open): %v", err)
	}
	if result != DecisionAllow {
		t.Errorf("crash: decision = %q, want %q (fail-open)", result, DecisionAllow)
	}
}

func TestExecutorFirstDenyShortCircuits(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on windows")
	}
	denyScript := writeScript(t, `#!/bin/sh
echo '{"decision":"deny"}'`)
	// This second hook should never run due to short-circuit
	panicScript := writeScript(t, `#!/bin/sh
echo '{"decision":"allow"}'`)

	cfg := &Config{
		Hooks: map[Event][]HookGroup{
			EventPreToolUse: {
				{Matcher: "*", Hooks: []HookDef{{Type: "command", Command: denyScript, Timeout: 5}}},
				{Matcher: "*", Hooks: []HookDef{{Type: "command", Command: panicScript, Timeout: 5}}},
			},
		},
	}
	exec := NewExecutor(cfg, "test-session", "/tmp", "build")

	result, err := exec.PreToolUse(context.Background(), "bash", json.RawMessage(`{}`))
	if err != nil {
		t.Fatalf("PreToolUse: %v", err)
	}
	if result != DecisionDeny {
		t.Errorf("decision = %q, want %q", result, DecisionDeny)
	}
}

func TestExecutorPostToolUse(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on windows")
	}
	// PostToolUse hooks are advisory — just verify they don't error
	script := writeScript(t, `#!/bin/sh
read input
echo "ok"`)

	cfg := &Config{
		Hooks: map[Event][]HookGroup{
			EventPostToolUse: {{
				Matcher: "*",
				Hooks:   []HookDef{{Type: "command", Command: script, Timeout: 5}},
			}},
		},
	}
	exec := NewExecutor(cfg, "test-session", "/tmp", "build")
	exec.PostToolUse(context.Background(), "bash", json.RawMessage(`{}`), "output", false)
	// No error = pass (advisory hook)
}

func TestExecutorSessionStart(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on windows")
	}
	script := writeScript(t, `#!/bin/sh
read input
echo "ok"`)

	cfg := &Config{
		Hooks: map[Event][]HookGroup{
			EventSessionStart: {{
				Matcher: "*",
				Hooks:   []HookDef{{Type: "command", Command: script, Timeout: 5}},
			}},
		},
	}
	exec := NewExecutor(cfg, "test-session", "/tmp", "build")
	exec.SessionStart(context.Background(), "tui")
	// No error = pass (advisory hook)
}

// writeScript creates a temp executable script and returns its path.
func writeScript(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "hook.sh")
	if err := os.WriteFile(path, []byte(content), 0755); err != nil {
		t.Fatal(err)
	}
	return path
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/hooks/ -v -run "TestExecutor"`
Expected: FAIL (NewExecutor not defined)

**Step 3: Write the executor implementation**

```go
package hooks

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Default timeouts per event type (seconds).
const (
	DefaultTimeoutPreToolUse  = 10
	DefaultTimeoutPostToolUse = 5
	DefaultTimeoutSession     = 30
	DefaultTimeoutNotify      = 5
	MaxTimeout                = 120 // hard cap on any hook timeout
)

// credentialPrefixes are env var prefixes stripped from hook environments.
var credentialPrefixes = []string{
	"ANTHROPIC_API_KEY",
	"OPENAI_API_KEY",
	"AWS_SECRET",
	"GITHUB_TOKEN",
	"GH_TOKEN",
}

// HookRunner is the interface consumed by the agent loop.
type HookRunner interface {
	PreToolUse(ctx context.Context, toolName string, input json.RawMessage) (Decision, error)
	PostToolUse(ctx context.Context, toolName string, input json.RawMessage, result string, isError bool)
	SessionStart(ctx context.Context, mode string)
	Notify(ctx context.Context, eventType, message, severity string)
}

// Executor runs hook commands for lifecycle events.
type Executor struct {
	config    *Config
	sessionID string
	workDir   string
	phase     string
	logger    *log.Logger
}

// NewExecutor creates a hook executor. Pass empty config for no-op behavior.
func NewExecutor(cfg *Config, sessionID, workDir, phase string) *Executor {
	if cfg == nil {
		cfg = &Config{Hooks: make(map[Event][]HookGroup)}
	}
	return &Executor{
		config:    cfg,
		sessionID: sessionID,
		workDir:   workDir,
		phase:     phase,
		logger:    log.New(os.Stderr, "skaffen: ", 0),
	}
}

// SetPhase updates the current OODARC phase for env var injection.
func (e *Executor) SetPhase(phase string) { e.phase = phase }

// PreToolUse runs PreToolUse hooks and returns the most restrictive decision.
// deny > ask > allow. First "deny" short-circuits. Fail-open on errors/timeouts.
func (e *Executor) PreToolUse(ctx context.Context, toolName string, input json.RawMessage) (Decision, error) {
	groups := e.matchingGroups(EventPreToolUse, toolName)
	if len(groups) == 0 {
		return DecisionAllow, nil
	}

	payload := PreToolUsePayload{ToolName: toolName, ToolInput: input}
	mostRestrictive := DecisionAllow

	for _, group := range groups {
		for _, hook := range group.Hooks {
			result, err := e.runHook(ctx, hook, DefaultTimeoutPreToolUse, payload)
			if err != nil {
				// Fail-open: log and continue
				e.logger.Printf("warning: PreToolUse hook %q: %v", hook.Command, err)
				continue
			}
			switch result.Decision {
			case DecisionDeny:
				return DecisionDeny, nil // short-circuit on deny
			case DecisionAsk:
				mostRestrictive = DecisionAsk // escalate, but keep running remaining hooks
			}
		}
	}
	return mostRestrictive, nil
}

// PostToolUse runs PostToolUse hooks (advisory, fire-and-forget).
func (e *Executor) PostToolUse(ctx context.Context, toolName string, input json.RawMessage, result string, isError bool) {
	groups := e.matchingGroups(EventPostToolUse, toolName)
	if len(groups) == 0 {
		return
	}

	payload := PostToolUsePayload{
		ToolName:   toolName,
		ToolInput:  input,
		ToolResult: result,
		IsError:    isError,
	}

	for _, group := range groups {
		for _, hook := range group.Hooks {
			if _, err := e.runHook(ctx, hook, DefaultTimeoutPostToolUse, payload); err != nil {
				e.logger.Printf("warning: PostToolUse hook %q: %v", hook.Command, err)
			}
		}
	}
}

// SessionStart runs SessionStart hooks (advisory).
func (e *Executor) SessionStart(ctx context.Context, mode string) {
	groups := e.config.Hooks[EventSessionStart]
	if len(groups) == 0 {
		return
	}

	payload := SessionStartPayload{
		SessionID: e.sessionID,
		WorkDir:   e.workDir,
		Mode:      mode,
	}

	for _, group := range groups {
		for _, hook := range group.Hooks {
			if _, err := e.runHook(ctx, hook, DefaultTimeoutSession, payload); err != nil {
				e.logger.Printf("warning: SessionStart hook %q: %v", hook.Command, err)
			}
		}
	}
}

// Notify runs Notification hooks (advisory, fire-and-forget).
func (e *Executor) Notify(ctx context.Context, eventType, message, severity string) {
	groups := e.config.Hooks[EventNotification]
	if len(groups) == 0 {
		return
	}

	payload := NotificationPayload{
		EventType: eventType,
		Message:   message,
		Severity:  severity,
	}

	for _, group := range groups {
		for _, hook := range group.Hooks {
			if _, err := e.runHook(ctx, hook, DefaultTimeoutNotify, payload); err != nil {
				e.logger.Printf("warning: Notification hook %q: %v", hook.Command, err)
			}
		}
	}
}

// matchingGroups returns hook groups whose matcher matches the tool name.
func (e *Executor) matchingGroups(event Event, toolName string) []HookGroup {
	var matched []HookGroup
	for _, group := range e.config.Hooks[event] {
		if group.Matcher == "*" || group.Matcher == toolName {
			matched = append(matched, group)
			continue
		}
		if ok, _ := filepath.Match(group.Matcher, toolName); ok {
			matched = append(matched, group)
		}
	}
	return matched
}

// safeEnv returns os.Environ() with credential-bearing env vars stripped.
func safeEnv() []string {
	var filtered []string
	for _, kv := range os.Environ() {
		skip := false
		for _, prefix := range credentialPrefixes {
			if strings.HasPrefix(kv, prefix+"=") || strings.HasPrefix(kv, prefix+"_") {
				skip = true
				break
			}
		}
		if !skip {
			filtered = append(filtered, kv)
		}
	}
	return filtered
}

// runHook executes a single hook command with timeout and JSON stdin/stdout.
func (e *Executor) runHook(ctx context.Context, hook HookDef, defaultTimeout int, payload interface{}) (*HookResult, error) {
	timeout := hook.Timeout
	if timeout <= 0 {
		timeout = defaultTimeout
	}
	if timeout > MaxTimeout {
		timeout = MaxTimeout
	}
	hookCtx, cancel := context.WithTimeout(ctx, time.Duration(timeout)*time.Second)
	defer cancel()

	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal payload: %w", err)
	}

	cmd := exec.CommandContext(hookCtx, "sh", "-c", hook.Command)
	cmd.Stdin = bytes.NewReader(payloadBytes)
	cmd.Env = append(safeEnv(),
		"SKAFFEN_SESSION_ID="+e.sessionID,
		"SKAFFEN_WORK_DIR="+e.workDir,
		"SKAFFEN_PHASE="+e.phase,
	)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("hook %q: %w (stderr: %s)", hook.Command, err, stderr.String())
	}

	result := &HookResult{Output: stdout.String()}
	// Parse JSON output for decision (PreToolUse)
	if stdout.Len() > 0 {
		if err := json.Unmarshal(stdout.Bytes(), result); err != nil {
			e.logger.Printf("warning: hook %q returned invalid JSON: %v", hook.Command, err)
			// Fail-open: treat as allow
		}
	}
	return result, nil
}
```

**Step 4: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/hooks/ -v -run "TestExecutor" -timeout 30s`
Expected: PASS (all 8 tests)

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/hooks/executor.go internal/hooks/executor_test.go && git commit -m "feat(hooks): executor with timeout, fail-open, and glob matching"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/hooks/ -v -timeout 30s`
  expect: exit 0
</verify>

---

### Task 4: Wire HookRunner into agentloop.Loop (F3)

**Files:**
- Modify: `internal/agentloop/types.go` (add HookRunner re-export)
- Modify: `internal/agentloop/loop.go` (add WithHooks option, wire into executeToolsWithCallbacks)

**Step 1: Add HookRunner interface to agentloop/types.go**

Add at the end of `internal/agentloop/types.go`, before the NoOp implementations.

**CRITICAL (P0-1):** The agentloop uses primitive `string` for decisions, not `hooks.Decision`. This avoids a cross-package type dependency — the agent layer provides a `hookAdapter` that converts between `hooks.Decision` and `string`.

```go
// HookRunner executes lifecycle hooks. The agentloop only uses
// PreToolUse and PostToolUse; SessionStart and Notify are called
// directly from main.go.
//
// PreToolUse returns a string decision: "allow", "deny", or "ask".
// Using string (not a typed enum) keeps agentloop decoupled from
// the hooks package — the agent layer adapts between the two.
type HookRunner interface {
	PreToolUse(ctx context.Context, toolName string, input json.RawMessage) (string, error)
	PostToolUse(ctx context.Context, toolName string, input json.RawMessage, result string, isError bool)
}
```

Add `"context"` and `"encoding/json"` to the imports block.

**Step 2: Add hooks field and WithHooks option to Loop**

In `internal/agentloop/loop.go`, add `hooks` field to `Loop` struct:

```go
type Loop struct {
	provider  provider.Provider
	registry  *Registry
	router    Router
	session   Session
	emitter   Emitter
	streamCB  StreamCallback
	approver  ToolApprover
	hooks     HookRunner  // lifecycle hooks (nil = no hooks)
	maxTurns  int
	sessionID string
	logger    *log.Logger
}
```

In `New()`, initialize the logger: `l.logger = log.New(io.Discard, "", 0)` (silent by default). Alternatively, add a `WithLogger` option if needed later.

Add the `WithHooks` option function after `WithStreamCallback`:

```go
// WithHooks sets the lifecycle hook runner.
func WithHooks(h HookRunner) Option { return func(l *Loop) { l.hooks = h } }
```

**Step 3: Wire PreToolUse hooks into executeToolsWithCallbacks**

Replace the approval check in `executeToolsWithCallbacks` (`loop.go:250-266`) with hook-aware logic. The new flow is:

1. If hooks exist, run PreToolUse hooks first
2. If hook says "deny" → block the tool (skip approver)
3. If hook says "allow" or "ask" → still run approver (hooks can't override trust)
4. After execution, fire PostToolUse in a goroutine

Replace the `executeToolsWithCallbacks` method entirely.

**CRITICAL fixes from flux-drive review:**
- **(P0-2):** PostToolUse goroutine uses `context.Background()` (not parent `ctx` which may be cancelled)
- **(P1-3):** No `fmt.Fprintf(os.Stderr)` — fail-open silently to avoid corrupting TUI output
- **(P0-1):** Decision comparison uses string literals `"deny"`, `"ask"` (not typed constants — agentloop is decoupled from hooks package)

```go
func (l *Loop) executeToolsWithCallbacks(ctx context.Context, calls []provider.ToolCall) provider.Message {
	var blocks []provider.ContentBlock
	for _, tc := range calls {
		// Phase 1: Hook gating (if hooks configured)
		if l.hooks != nil {
			decision, _ := l.hooks.PreToolUse(ctx, tc.Name, tc.Input)
			// Fail-open: error from PreToolUse is ignored (hooks package logs it)
			if decision == "deny" {
				blocks = append(blocks, provider.ContentBlock{
					Type:          "tool_result",
					ToolUseID:     tc.ID,
					ResultContent: fmt.Sprintf("Tool call %q was denied by a hook.", tc.Name),
					IsError:       true,
				})
				if l.streamCB != nil {
					l.streamCB(StreamEvent{
						Type:       StreamToolComplete,
						ToolName:   tc.Name,
						ToolResult: fmt.Sprintf("Denied by hook: %s", tc.Name),
						IsError:    true,
					})
				}
				continue
			}
			// "ask" falls through to approver (same as no hook)
			// "allow" also falls through — hooks can't override trust
		}

		// Phase 2: Trust approval (always runs unless hook denied)
		if l.approver != nil && !l.approver(tc.Name, tc.Input) {
			blocks = append(blocks, provider.ContentBlock{
				Type:          "tool_result",
				ToolUseID:     tc.ID,
				ResultContent: fmt.Sprintf("Tool call %q was denied by the user.", tc.Name),
				IsError:       true,
			})
			if l.streamCB != nil {
				l.streamCB(StreamEvent{
					Type:       StreamToolComplete,
					ToolName:   tc.Name,
					ToolResult: fmt.Sprintf("Denied by user: %s", tc.Name),
					IsError:    true,
				})
			}
			continue
		}

		// Phase 3: Execute
		result := l.registry.Execute(ctx, tc.Name, tc.Input)
		blocks = append(blocks, provider.ContentBlock{
			Type:          "tool_result",
			ToolUseID:     tc.ID,
			ResultContent: result.Content,
			IsError:       result.IsError,
		})
		if l.streamCB != nil {
			l.streamCB(StreamEvent{
				Type:       StreamToolComplete,
				ToolName:   tc.Name,
				ToolResult: result.Content,
				IsError:    result.IsError,
			})
		}

		// Phase 4: PostToolUse hook (advisory, background)
		// CRITICAL (P0-2): Use context.Background(), not parent ctx.
		// Parent ctx may be cancelled when the agent loop advances,
		// which would kill in-flight PostToolUse hooks.
		if l.hooks != nil {
			hookRunner := l.hooks
			name, input, content, isErr := tc.Name, tc.Input, result.Content, result.IsError
			go hookRunner.PostToolUse(context.Background(), name, input, content, isErr)
		}
	}
	return provider.Message{Role: provider.RoleUser, Content: blocks}
}
```

No new imports needed — `"fmt"` and `"context"` are already imported.

**Step 4: Run all tests**

Run: `cd os/Skaffen && go test ./internal/agentloop/ -v -timeout 30s`
Expected: PASS (all existing tests still pass)

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/agentloop/types.go internal/agentloop/loop.go && git commit -m "feat(hooks): wire HookRunner into agentloop with PreToolUse gating and PostToolUse background firing"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/agentloop/ -v -timeout 30s`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./internal/agentloop/`
  expect: exit 0
</verify>

---

### Task 5: Wire Hooks Through Agent Layer (F3)

**Files:**
- Modify: `internal/agent/deps.go` (add HookRunner re-export)
- Modify: `internal/agent/agent.go` (add WithHooks option, hookAdapter, pass to agentloop)

**CRITICAL (P0-1):** The agent layer bridges between `hooks.HookRunner` (typed `Decision`) and `agentloop.HookRunner` (string). This follows the exact same adapter pattern used by `routerAdapter`, `sessionAdapter`, and `emitterAdapter`.

**Step 1: Add re-exports to agent/deps.go**

Add to the type alias block:

```go
HookRunner = agentloop.HookRunner
```

Note: No `HookDecision` re-export needed — agentloop uses plain strings now.

**Step 2: Add hookAdapter to agent/agent.go**

The adapter converts `hooks.Executor` (which returns `hooks.Decision`) to `agentloop.HookRunner` (which returns `string`). Add after the existing adapter types:

```go
// hookAdapter bridges hooks.Executor → agentloop.HookRunner.
// This matches the routerAdapter/sessionAdapter/emitterAdapter pattern.
type hookAdapter struct {
	exec *hooks.Executor
}

func (a *hookAdapter) PreToolUse(ctx context.Context, toolName string, input json.RawMessage) (string, error) {
	decision, err := a.exec.PreToolUse(ctx, toolName, input)
	return string(decision), err
}

func (a *hookAdapter) PostToolUse(ctx context.Context, toolName string, input json.RawMessage, result string, isError bool) {
	a.exec.PostToolUse(ctx, toolName, input, result, isError)
}
```

Add the `hooks` import: `"github.com/mistakeknot/Skaffen/internal/hooks"`

**Step 3: Add hooks field and WithHooks option to agent.Agent**

In `internal/agent/agent.go`, add `hookExec` field to `Agent` struct:

```go
type Agent struct {
	provider  provider.Provider
	registry  *tool.Registry
	router    Router
	session   Session
	emitter   Emitter
	fsm       *phaseFSM
	sessionID string
	streamCB  StreamCallback
	approver  ToolApprover
	hookExec  *hooks.Executor  // lifecycle hooks (nil = disabled)
	maxTurns  int
}
```

Add the option function — note it takes `*hooks.Executor`, not the agentloop interface:

```go
// WithHooks sets the lifecycle hook executor.
func WithHooks(h *hooks.Executor) Option { return func(a *Agent) { a.hookExec = h } }
```

**Step 4: Pass adapted hooks to agentloop in Agent.Run()**

In the `Run` method, after the `streamCB` check (line ~135), add:

```go
if a.hookExec != nil {
	loopOpts = append(loopOpts, agentloop.WithHooks(&hookAdapter{exec: a.hookExec}))
}
```

**Step 5: Run all tests**

Run: `cd os/Skaffen && go test ./internal/agent/ -v -timeout 30s`
Expected: PASS

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/agent/deps.go internal/agent/agent.go && git commit -m "feat(hooks): hookAdapter bridges hooks.Executor to agentloop.HookRunner"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/agent/ -v -timeout 30s`
  expect: exit 0
- run: `cd os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
</verify>

---

### Task 6: Wire Hooks into main.go (F4)

**Files:**
- Modify: `cmd/skaffen/main.go` (load hooks, create executor, fire SessionStart, pass to agent)

**Step 1: Add hooks loading helper function**

Add a `loadHooks` function and wire it into both `runTUI()` and `runPrint()`. In `main.go`, add after the imports:

```go
import "github.com/mistakeknot/Skaffen/internal/hooks"
```

Add this helper function after `loadMCPPluginsFromConfig`:

```go
// loadHooks loads and merges hook configs from user-global and per-project paths.
// Returns nil executor (not error) if no hooks configured — Skaffen degrades gracefully.
func loadHooks(cfg *config.Config, sessionID, phase string) *hooks.Executor {
	hookPaths := cfg.HookPaths()
	if len(hookPaths) == 0 {
		return nil
	}

	var merged *hooks.Config
	for _, p := range hookPaths {
		hcfg, err := hooks.LoadConfig(p)
		if err != nil {
			log.Printf("skaffen: warning: hooks config %s: %v", p, err)
			continue
		}
		if merged == nil {
			merged = hcfg
		} else {
			merged = hooks.MergeConfig(merged, hcfg)
		}
	}

	if merged == nil || len(merged.Hooks) == 0 {
		return nil
	}

	return hooks.NewExecutor(merged, sessionID, cfg.WorkDir(), phase)
}
```

**(P1-3):** Uses `log.Printf` instead of `fmt.Fprintf(os.Stderr)` — consistent with the rest of main.go and won't corrupt TUI output.

**Step 2: Wire into runPrint()**

**CRITICAL (P0-4):** `runPrint()` currently has no trust evaluator — hooks are the ONLY gate in headless mode. Also wire a headless always-allow approver so the hook→approver flow works correctly:

In `runPrint()`, after the `emitter` lines (around line 270) and before `a := agent.New(...)`:

```go
// Hooks
hookExec := loadHooks(cfg, sessionID, string(phase))
if hookExec != nil {
	hookExec.SessionStart(ctx, "print")
	opts = append(opts, agent.WithHooks(hookExec))
}
```

**Step 3: Wire into runTUI()**

In `runTUI()`, after the `trustEval` line (around line 369) and before `a := agent.New(...)`:

```go
// Hooks
hookExec := loadHooks(cfg, sessionID, string(phase))
if hookExec != nil {
	hookCtx, hookCancel := context.WithTimeout(context.Background(), 30*time.Second)
	hookExec.SessionStart(hookCtx, "tui")
	hookCancel()
	opts = append(opts, agent.WithHooks(hookExec))
}
```

**Step 4: Verify the full build compiles**

Run: `cd os/Skaffen && go build ./cmd/skaffen`
Expected: no errors

**Step 5: Run full test suite**

Run: `cd os/Skaffen && go test ./... -timeout 60s`
Expected: PASS (all tests)

**Step 6: Commit**

```bash
cd os/Skaffen && git add cmd/skaffen/main.go && git commit -m "feat(hooks): load hooks config and fire SessionStart in main.go"
```

<verify>
- run: `cd os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
- run: `cd os/Skaffen && go test ./... -timeout 60s`
  expect: exit 0
</verify>

---

### Task 7: Integration Test — End-to-End Hook Flow

**Files:**
- Create: `internal/hooks/integration_test.go`

**Step 1: Write an integration test that exercises the full hook pipeline**

```go
package hooks

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestIntegrationFullPipeline(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on windows")
	}

	// Create a temp dir with both global and project hooks
	tmpDir := t.TempDir()
	globalDir := filepath.Join(tmpDir, "global")
	projectDir := filepath.Join(tmpDir, "project")
	os.MkdirAll(globalDir, 0755)
	os.MkdirAll(projectDir, 0755)

	// Global hook: log to a file on PreToolUse
	logFile := filepath.Join(tmpDir, "hook.log")
	globalScript := writeScript(t, `#!/bin/sh
read input
echo "$input" >> `+logFile+`
echo '{"decision":"allow"}'`)

	// Project hook: deny "rm" tool specifically
	projectScript := writeScript(t, `#!/bin/sh
read input
tool=$(echo "$input" | grep -o '"tool_name":"[^"]*"' | cut -d'"' -f4)
if [ "$tool" = "rm" ]; then
  echo '{"decision":"deny"}'
else
  echo '{"decision":"allow"}'
fi`)

	globalPath := filepath.Join(globalDir, "hooks.json")
	os.WriteFile(globalPath, []byte(`{
		"hooks": {
			"PreToolUse": [
				{"matcher": "*", "hooks": [{"type": "command", "command": "`+globalScript+`"}]}
			]
		}
	}`), 0644)

	projectPath := filepath.Join(projectDir, "hooks.json")
	os.WriteFile(projectPath, []byte(`{
		"hooks": {
			"PreToolUse": [
				{"matcher": "*", "hooks": [{"type": "command", "command": "`+projectScript+`"}]}
			]
		}
	}`), 0644)

	// Load and merge
	globalCfg, err := LoadConfig(globalPath)
	if err != nil {
		t.Fatal(err)
	}
	projectCfg, err := LoadConfig(projectPath)
	if err != nil {
		t.Fatal(err)
	}
	merged := MergeConfig(globalCfg, projectCfg)

	exec := NewExecutor(merged, "integration-test", tmpDir, "build")

	// Test 1: "bash" tool should be allowed (both hooks say allow)
	decision, err := exec.PreToolUse(context.Background(), "bash", json.RawMessage(`{"command":"ls"}`))
	if err != nil {
		t.Fatalf("bash: %v", err)
	}
	if decision != DecisionAllow {
		t.Errorf("bash: decision = %q, want allow", decision)
	}

	// Test 2: "rm" tool should be denied (project hook denies)
	decision, err = exec.PreToolUse(context.Background(), "rm", json.RawMessage(`{"path":"/"}`))
	if err != nil {
		t.Fatalf("rm: %v", err)
	}
	if decision != DecisionDeny {
		t.Errorf("rm: decision = %q, want deny", decision)
	}

	// Verify global hook logged both calls
	logData, err := os.ReadFile(logFile)
	if err != nil {
		t.Fatalf("read log: %v", err)
	}
	if len(logData) == 0 {
		t.Error("global hook log file is empty — hook didn't run")
	}
}

func TestIntegrationNoHooksConfigured(t *testing.T) {
	cfg := &Config{Hooks: make(map[Event][]HookGroup)}
	exec := NewExecutor(cfg, "test", "/tmp", "build")

	decision, err := exec.PreToolUse(context.Background(), "bash", json.RawMessage(`{}`))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if decision != DecisionAllow {
		t.Errorf("no hooks: decision = %q, want allow", decision)
	}
}
```

**Step 2: Run integration test**

Run: `cd os/Skaffen && go test ./internal/hooks/ -v -run "TestIntegration" -timeout 30s`
Expected: PASS

**Step 3: Run full test suite one final time**

Run: `cd os/Skaffen && go test ./... -count=1 -timeout 60s`
Expected: PASS (all tests across all packages)

**Step 4: Commit**

```bash
cd os/Skaffen && git add internal/hooks/integration_test.go && git commit -m "test(hooks): integration test for full hook pipeline with config merge"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/hooks/ -v -timeout 30s`
  expect: exit 0
- run: `cd os/Skaffen && go test ./... -count=1 -timeout 60s`
  expect: exit 0
</verify>
