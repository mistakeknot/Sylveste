---
artifact_type: plan
bead: Demarch-6i0.18
stage: design
requirements:
  - F1: SubagentRunner — goroutine lifecycle management
  - F2: Type Registry — subagent type definitions
  - F3: ScopedSession — context isolation with selective injection
  - F4: Agent Tool — LLM-invocable subagent dispatch
  - F5: Intercore reservation bridge — write coordination
  - F6: TUI inline collapsible blocks — subagent output display
  - F7: AggregatingEmitter — evidence stream merge
---
# Skaffen Subagent System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-6i0.18
**Goal:** Add a subagent system to Skaffen so the LLM can spawn parallel child agents via an Agent tool, with Explore (read-only) and General (write-capable) built-in types, extensible via `.skaffen/agents/` config.

**Architecture:** Each subagent is a fresh `agentloop.Loop` goroutine with scoped context (no full parent conversation). Write-capable subagents coordinate via Intercore `ic coordination reserve`. A new `internal/subagent/` package owns all subagent types; the `Agent` tool is registered in the phase-gated tool registry. TUI shows subagent results as inline collapsible blocks.

**Tech Stack:** Go 1.22, Bubble Tea (bubbletea/lipgloss), existing agentloop/provider/tool packages, Intercore CLI bridge (`ic coordination reserve/release`).

**Prior Learnings:**
- `docs/solutions/patterns/synthesis-subagent-context-isolation-20260216.md` — agents write findings to disk, synthesis compresses output to ~100-byte JSON verdicts. Apply to AggregatingEmitter.
- `docs/solutions/patterns/intercore-bridge-subprocess-lifecycle-20260311.md` — always use `context.WithTimeout` (5s) for `ic` subprocess calls. Release mutex before best-effort I/O.
- `docs/solutions/patterns/cas-spawn-link-orphan-cleanup-20260219.md` — CAS guard on spawn-link operations; kill orphans on link failure.
- `docs/solutions/patterns/bubble-tea-pointer-cache-safety-20260223.md` — Bubble Tea serializes Update/View; pointer fields on Models are safe without mutexes. Use `atomic.Bool` only for external goroutine state.

---

## Must-Haves

**Truths** (observable behaviors):
- LLM can invoke an `Agent` tool to spawn Explore or General subagents
- Multiple subagents run concurrently (up to configurable max)
- Subagent results appear inline in the TUI chat viewport
- Write-capable subagents are blocked if file patterns conflict with another reservation
- Custom subagent types can be defined in `.skaffen/agents/<name>.toml`

**Artifacts** (files with specific exports):
- [`internal/subagent/types.go`] exports `SubagentType`, `SubagentTask`, `SubagentResult`, `SubagentStatus`
- [`internal/subagent/registry.go`] exports `TypeRegistry`, `NewTypeRegistry`
- [`internal/subagent/runner.go`] exports `Runner`, `NewRunner`, `StatusCallback`
- [`internal/subagent/session.go`] exports `ScopedSession`
- [`internal/subagent/emitter.go`] exports `AggregatingEmitter`
- [`internal/subagent/tool.go`] exports `AgentTool`
- [`internal/subagent/reservation.go`] exports `ReservationBridge`

**Key Links:**
- `AgentTool.Execute()` calls `Runner.Run()` which spawns goroutines each running `agentloop.New(...).Run()`
- `Runner` creates a `ScopedSession` and `AggregatingEmitter` per subagent goroutine
- `ReservationBridge.Reserve()` calls `ic coordination reserve` before write-capable subagents start
- TUI receives `SubagentStatusMsg` from `StatusCallback` and updates collapsible block rendering

---

### Task 1: Core types (F1, F2)

**Files:**
- Create: `os/Skaffen/internal/subagent/types.go`
- Test: `os/Skaffen/internal/subagent/types_test.go`

**Step 1: Write the test for SubagentType validation**

```go
package subagent

import "testing"

func TestSubagentType_Validate(t *testing.T) {
	tests := []struct {
		name    string
		st      SubagentType
		wantErr bool
	}{
		{
			name:    "valid explore type",
			st:      SubagentType{Name: "explore", Description: "Read-only", Tools: []string{"read", "grep", "glob", "ls"}, ReadOnly: true, MaxTurns: 10},
			wantErr: false,
		},
		{
			name:    "missing name",
			st:      SubagentType{Description: "No name", Tools: []string{"read"}, MaxTurns: 10},
			wantErr: true,
		},
		{
			name:    "zero max turns defaults",
			st:      SubagentType{Name: "test", Description: "Test", Tools: []string{"read"}},
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.st.Validate()
			if (err != nil) != tt.wantErr {
				t.Errorf("Validate() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestSubagentType_Validate -v`
Expected: FAIL (package doesn't exist yet)

**Step 3: Write the types**

```go
package subagent

import (
	"errors"
	"time"

	"github.com/mistakeknot/Skaffen/internal/agentloop"
	"github.com/mistakeknot/Skaffen/internal/provider"
)

// SubagentType defines a type of subagent (e.g., "explore", "general").
type SubagentType struct {
	Name         string   `toml:"name"`
	Description  string   `toml:"description"`
	Tools        []string `toml:"tools"`        // tool whitelist (empty = all)
	SystemPrompt string   `toml:"system_prompt"` // template with {{.TaskPrompt}}, {{.InjectedContext}}
	MaxTurns     int      `toml:"max_turns"`     // 0 = default (25)
	TokenBudget  int      `toml:"token_budget"`  // 0 = inherit from parent
	ReadOnly     bool     `toml:"read_only"`     // skip Intercore reservation
	Model        string   `toml:"model"`         // empty = inherit from parent
	Timeout      Duration `toml:"timeout"`       // 0 = default (120s)
}

// Duration wraps time.Duration for TOML unmarshaling.
type Duration struct{ time.Duration }

func (d *Duration) UnmarshalText(text []byte) error {
	var err error
	d.Duration, err = time.ParseDuration(string(text))
	return err
}

// Validate checks required fields.
func (st *SubagentType) Validate() error {
	if st.Name == "" {
		return errors.New("subagent type: name is required")
	}
	if st.MaxTurns == 0 {
		st.MaxTurns = 25
	}
	if st.Timeout.Duration == 0 {
		st.Timeout.Duration = 120 * time.Second
	}
	return nil
}

// SubagentStatus represents the current state of a running subagent.
type SubagentStatus int

const (
	StatusPending  SubagentStatus = iota
	StatusRunning
	StatusDone
	StatusFailed
)

func (s SubagentStatus) String() string {
	switch s {
	case StatusPending:
		return "pending"
	case StatusRunning:
		return "running"
	case StatusDone:
		return "done"
	case StatusFailed:
		return "failed"
	default:
		return "unknown"
	}
}

// SubagentTask is the input for spawning a subagent.
type SubagentTask struct {
	ID              string   // unique identifier (generated by runner)
	Type            string   // subagent type name (must exist in registry)
	Prompt          string   // task-specific prompt
	Description     string   // short label (3-5 words) for TUI display
	InjectedContext string   // optional context from parent
	FilePatterns    []string // glob patterns for Intercore reservation (write-capable only)
}

// SubagentResult is the output of a completed subagent.
type SubagentResult struct {
	ID          string
	Description string
	Response    string
	Usage       provider.Usage
	Turns       int
	Error       error
	Evidence    []agentloop.Evidence
	Status      SubagentStatus
	Duration    time.Duration
}

// StatusUpdate is sent via StatusCallback during subagent execution.
type StatusUpdate struct {
	ID          string
	Description string
	Status      SubagentStatus
	Turn        int
	MaxTurns    int
	TokensUsed  int
	Error       error
}

// StatusCallback receives real-time status updates from running subagents.
type StatusCallback func(StatusUpdate)
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestSubagentType_Validate -v`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/subagent/types.go internal/subagent/types_test.go
git commit -m "feat(subagent): add core types for subagent system"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/subagent/ -v`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./internal/subagent/`
  expect: exit 0
</verify>

---

### Task 2: Type Registry (F2)

**Files:**
- Create: `os/Skaffen/internal/subagent/registry.go`
- Test: `os/Skaffen/internal/subagent/registry_test.go`

**Step 1: Write the test**

```go
package subagent

import (
	"os"
	"path/filepath"
	"testing"
)

func TestTypeRegistry_Builtins(t *testing.T) {
	reg := NewTypeRegistry("")
	// Explore must exist
	st, err := reg.Get("explore")
	if err != nil {
		t.Fatalf("Get(explore): %v", err)
	}
	if !st.ReadOnly {
		t.Error("explore should be read-only")
	}
	if len(st.Tools) == 0 {
		t.Error("explore should have tools")
	}

	// General must exist
	st, err = reg.Get("general")
	if err != nil {
		t.Fatalf("Get(general): %v", err)
	}
	if st.ReadOnly {
		t.Error("general should not be read-only")
	}

	// List includes both builtins
	all := reg.List()
	if len(all) < 2 {
		t.Errorf("List() = %d types, want >= 2", len(all))
	}

	// Unknown type returns error
	_, err = reg.Get("nonexistent")
	if err == nil {
		t.Error("Get(nonexistent) should return error")
	}
}

func TestTypeRegistry_CustomTOML(t *testing.T) {
	dir := t.TempDir()
	toml := `name = "researcher"
description = "Research-only agent"
tools = ["read", "grep", "glob"]
read_only = true
max_turns = 15
system_prompt = "You are a researcher. {{.TaskPrompt}}"
`
	if err := os.WriteFile(filepath.Join(dir, "researcher.toml"), []byte(toml), 0644); err != nil {
		t.Fatal(err)
	}

	reg := NewTypeRegistry(dir)
	st, err := reg.Get("researcher")
	if err != nil {
		t.Fatalf("Get(researcher): %v", err)
	}
	if st.MaxTurns != 15 {
		t.Errorf("MaxTurns = %d, want 15", st.MaxTurns)
	}
	if !st.ReadOnly {
		t.Error("researcher should be read-only")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestTypeRegistry -v`
Expected: FAIL (NewTypeRegistry not defined)

**Step 3: Write the registry**

```go
package subagent

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/BurntSushi/toml"
)

// TypeRegistry holds subagent type definitions.
type TypeRegistry struct {
	types map[string]SubagentType
}

// NewTypeRegistry creates a registry with built-in types and loads custom
// types from configDir (e.g., ".skaffen/agents/"). If configDir is empty
// or doesn't exist, only built-in types are available.
func NewTypeRegistry(configDir string) *TypeRegistry {
	r := &TypeRegistry{types: make(map[string]SubagentType)}

	// Built-in: explore (read-only)
	r.types["explore"] = SubagentType{
		Name:        "explore",
		Description: "Fast read-only agent for codebase exploration. Has access to Read, Grep, Glob, and Ls tools only.",
		Tools:       []string{"read", "grep", "glob", "ls"},
		ReadOnly:    true,
		MaxTurns:    10,
		SystemPrompt: "You are a focused codebase exploration agent. Answer the question using only the available read-only tools. Be concise and direct.\n\n{{.TaskPrompt}}",
	}

	// Built-in: general (full access)
	r.types["general"] = SubagentType{
		Name:        "general",
		Description: "General-purpose agent with full tool access for multi-step tasks.",
		Tools:       nil, // nil = all tools
		ReadOnly:    false,
		MaxTurns:    25,
		SystemPrompt: "You are a focused agent working on a specific task. Complete the task using the available tools. Be concise.\n\n{{.TaskPrompt}}",
	}

	// Load custom types from config dir
	if configDir != "" {
		r.loadFromDir(configDir)
	}

	return r
}

// Get returns a subagent type by name.
func (r *TypeRegistry) Get(name string) (SubagentType, error) {
	st, ok := r.types[name]
	if !ok {
		return SubagentType{}, fmt.Errorf("unknown subagent type %q", name)
	}
	return st, nil
}

// List returns all registered types sorted by name.
func (r *TypeRegistry) List() []SubagentType {
	names := make([]string, 0, len(r.types))
	for name := range r.types {
		names = append(names, name)
	}
	sort.Strings(names)

	result := make([]SubagentType, len(names))
	for i, name := range names {
		result[i] = r.types[name]
	}
	return result
}

// Names returns sorted type names (for Agent tool schema enum).
func (r *TypeRegistry) Names() []string {
	names := make([]string, 0, len(r.types))
	for name := range r.types {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

func (r *TypeRegistry) loadFromDir(dir string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return // dir doesn't exist — silently skip
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".toml") {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		var st SubagentType
		if _, err := toml.DecodeFile(path, &st); err != nil {
			slog.Warn("skipping invalid subagent type", "path", path, "error", err)
			continue
		}
		if err := st.Validate(); err != nil {
			slog.Warn("skipping invalid subagent type", "path", path, "error", err)
			continue
		}
		r.types[st.Name] = st
	}
}
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestTypeRegistry -v`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/subagent/registry.go internal/subagent/registry_test.go
git commit -m "feat(subagent): add type registry with built-in explore/general types"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/subagent/ -v`
  expect: exit 0
</verify>

---

### Task 3: ScopedSession (F3)

**Files:**
- Create: `os/Skaffen/internal/subagent/session.go`
- Test: `os/Skaffen/internal/subagent/session_test.go`

**Step 1: Write the test**

```go
package subagent

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Skaffen/internal/agentloop"
	"github.com/mistakeknot/Skaffen/internal/provider"
)

func TestScopedSession_SystemPrompt(t *testing.T) {
	s := NewScopedSession(
		"You are a researcher. {{.TaskPrompt}}",
		"Find all Go files that import context",
		"The project uses Go 1.22",
	)
	prompt := s.SystemPrompt(agentloop.PromptHints{})
	if !strings.Contains(prompt, "Find all Go files") {
		t.Error("prompt should contain task prompt")
	}
	if !strings.Contains(prompt, "Go 1.22") {
		t.Error("prompt should contain injected context")
	}
}

func TestScopedSession_Isolation(t *testing.T) {
	s := NewScopedSession("system", "task", "")

	// Initially empty
	if len(s.Messages()) != 0 {
		t.Error("should start with no messages")
	}

	// Save a turn
	s.Save(agentloop.Turn{
		Messages: []provider.Message{{Role: provider.RoleAssistant}},
	})
	if len(s.Messages()) != 1 {
		t.Errorf("after save, got %d messages, want 1", len(s.Messages()))
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestScopedSession -v`
Expected: FAIL

**Step 3: Write the session**

```go
package subagent

import (
	"strings"

	"github.com/mistakeknot/Skaffen/internal/agentloop"
	"github.com/mistakeknot/Skaffen/internal/provider"
)

// ScopedSession provides isolated conversation context for a subagent.
// It implements agentloop.Session with a fixed system prompt (template-expanded)
// and an independent message history.
type ScopedSession struct {
	systemPrompt string
	messages     []provider.Message
}

// NewScopedSession creates a session with a template-expanded system prompt.
// The template supports {{.TaskPrompt}} and {{.InjectedContext}} placeholders.
func NewScopedSession(promptTemplate, taskPrompt, injectedContext string) *ScopedSession {
	expanded := promptTemplate
	expanded = strings.ReplaceAll(expanded, "{{.TaskPrompt}}", taskPrompt)
	expanded = strings.ReplaceAll(expanded, "{{.InjectedContext}}", injectedContext)
	return &ScopedSession{
		systemPrompt: expanded,
	}
}

// SystemPrompt returns the expanded system prompt.
func (s *ScopedSession) SystemPrompt(_ agentloop.PromptHints) string {
	return s.systemPrompt
}

// Save appends turn messages to the isolated history.
func (s *ScopedSession) Save(turn agentloop.Turn) error {
	s.messages = append(s.messages, turn.Messages...)
	return nil
}

// Messages returns the isolated message history.
func (s *ScopedSession) Messages() []provider.Message {
	return s.messages
}
```

**Step 4: Run test**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestScopedSession -v`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/subagent/session.go internal/subagent/session_test.go
git commit -m "feat(subagent): add ScopedSession with template expansion"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/subagent/ -v`
  expect: exit 0
</verify>

---

### Task 4: AggregatingEmitter (F7)

**Files:**
- Create: `os/Skaffen/internal/subagent/emitter.go`
- Test: `os/Skaffen/internal/subagent/emitter_test.go`

**Step 1: Write the test**

```go
package subagent

import (
	"sync"
	"testing"

	"github.com/mistakeknot/Skaffen/internal/agentloop"
)

type collectEmitter struct {
	mu     sync.Mutex
	events []agentloop.Evidence
}

func (c *collectEmitter) Emit(ev agentloop.Evidence) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.events = append(c.events, ev)
	return nil
}

func TestAggregatingEmitter_TagsEvents(t *testing.T) {
	parent := &collectEmitter{}
	agg := NewAggregatingEmitter("sub-1", "explore", parent)

	agg.Emit(agentloop.Evidence{TurnNumber: 1, TokensIn: 100})
	agg.Emit(agentloop.Evidence{TurnNumber: 2, TokensIn: 200})

	// Flush to parent
	agg.Flush()

	if len(parent.events) != 2 {
		t.Fatalf("parent got %d events, want 2", len(parent.events))
	}
	for _, ev := range parent.events {
		if ev.SessionID != "sub-1" {
			t.Errorf("SessionID = %q, want sub-1", ev.SessionID)
		}
	}
}

func TestAggregatingEmitter_TotalUsage(t *testing.T) {
	parent := &collectEmitter{}
	agg := NewAggregatingEmitter("sub-1", "explore", parent)

	agg.Emit(agentloop.Evidence{TokensIn: 100, TokensOut: 50})
	agg.Emit(agentloop.Evidence{TokensIn: 200, TokensOut: 75})

	total := agg.TotalUsage()
	if total.InputTokens != 300 {
		t.Errorf("InputTokens = %d, want 300", total.InputTokens)
	}
	if total.OutputTokens != 125 {
		t.Errorf("OutputTokens = %d, want 125", total.OutputTokens)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestAggregating -v`
Expected: FAIL

**Step 3: Write the emitter**

```go
package subagent

import (
	"sync"

	"github.com/mistakeknot/Skaffen/internal/agentloop"
	"github.com/mistakeknot/Skaffen/internal/provider"
)

// AggregatingEmitter buffers evidence from a subagent, tags events with
// subagent metadata, and flushes to a parent emitter on completion.
type AggregatingEmitter struct {
	subagentID   string
	subagentType string
	parent       agentloop.Emitter

	mu     sync.Mutex
	events []agentloop.Evidence
	usage  provider.Usage
}

// NewAggregatingEmitter creates an emitter that buffers events for a subagent.
func NewAggregatingEmitter(subagentID, subagentType string, parent agentloop.Emitter) *AggregatingEmitter {
	return &AggregatingEmitter{
		subagentID:   subagentID,
		subagentType: subagentType,
		parent:       parent,
	}
}

// Emit buffers an evidence event, tagging it with subagent metadata.
func (e *AggregatingEmitter) Emit(ev agentloop.Evidence) error {
	ev.SessionID = e.subagentID // tag with subagent ID for attribution

	e.mu.Lock()
	defer e.mu.Unlock()

	e.events = append(e.events, ev)
	e.usage.InputTokens += ev.TokensIn
	e.usage.OutputTokens += ev.TokensOut
	return nil
}

// Flush sends all buffered events to the parent emitter.
func (e *AggregatingEmitter) Flush() {
	e.mu.Lock()
	events := make([]agentloop.Evidence, len(e.events))
	copy(events, e.events)
	e.mu.Unlock()

	for _, ev := range events {
		e.parent.Emit(ev) // ignore errors — parent emission is best-effort
	}
}

// Events returns a copy of buffered evidence events.
func (e *AggregatingEmitter) Events() []agentloop.Evidence {
	e.mu.Lock()
	defer e.mu.Unlock()
	out := make([]agentloop.Evidence, len(e.events))
	copy(out, e.events)
	return out
}

// TotalUsage returns aggregated token usage across all turns.
func (e *AggregatingEmitter) TotalUsage() provider.Usage {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.usage
}
```

**Step 4: Run test**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestAggregating -v`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/subagent/emitter.go internal/subagent/emitter_test.go
git commit -m "feat(subagent): add AggregatingEmitter with buffering and flush"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/subagent/ -v`
  expect: exit 0
</verify>

---

### Task 5: Intercore Reservation Bridge (F5)

**Files:**
- Create: `os/Skaffen/internal/subagent/reservation.go`
- Test: `os/Skaffen/internal/subagent/reservation_test.go`

**Step 1: Write the test**

```go
package subagent

import "testing"

func TestReservationBridge_BuildArgs(t *testing.T) {
	b := &ReservationBridge{icPath: "/usr/bin/ic", projectDir: "/home/mk/projects/test"}

	args := b.buildReserveArgs("sub-1", "*.go", 120)
	expected := []string{
		"coordination", "reserve",
		"--owner=sub-1",
		"--scope=/home/mk/projects/test",
		"--pattern=*.go",
		"--exclusive",
		"--ttl=120",
	}
	if len(args) != len(expected) {
		t.Fatalf("args length = %d, want %d: %v", len(args), len(expected), args)
	}
	for i, a := range args {
		if a != expected[i] {
			t.Errorf("args[%d] = %q, want %q", i, a, expected[i])
		}
	}
}

func TestReservationBridge_Unavailable(t *testing.T) {
	b := &ReservationBridge{} // no ic path
	err := b.Reserve("sub-1", []string{"*.go"}, 120)
	if err != nil {
		t.Error("Reserve should succeed (no-op) when ic unavailable")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestReservation -v`
Expected: FAIL

**Step 3: Write the bridge**

Note: `ic coordination reserve` exits 0 on success, 1 on conflict, 2+ on error. We follow the existing `context.WithTimeout` pattern from the intercore bridge learnings.

```go
package subagent

import (
	"context"
	"fmt"
	"log/slog"
	"os/exec"
	"strconv"
	"time"
)

// ReservationBridge wraps the Intercore `ic coordination reserve/release` CLI
// for file-level write coordination between subagents.
type ReservationBridge struct {
	icPath     string
	projectDir string
}

// NewReservationBridge creates a bridge. If ic is not found on PATH,
// the bridge degrades gracefully (Reserve/Release are no-ops with a warning).
func NewReservationBridge(projectDir string) *ReservationBridge {
	b := &ReservationBridge{projectDir: projectDir}
	if path, err := exec.LookPath("ic"); err == nil {
		b.icPath = path
	} else {
		slog.Warn("ic not found on PATH — subagent file reservations disabled")
	}
	return b
}

// Reserve acquires exclusive file reservations for the given patterns.
// Returns nil if ic is unavailable (graceful degradation).
// Returns an error if a conflict is detected (exit code 1).
func (b *ReservationBridge) Reserve(owner string, patterns []string, ttlSeconds int) error {
	if b.icPath == "" {
		return nil // no ic — degrade gracefully
	}
	for _, pattern := range patterns {
		args := b.buildReserveArgs(owner, pattern, ttlSeconds)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		cmd := exec.CommandContext(ctx, b.icPath, args...)
		out, err := cmd.CombinedOutput()
		cancel()
		if err != nil {
			if cmd.ProcessState != nil && cmd.ProcessState.ExitCode() == 1 {
				return fmt.Errorf("file reservation conflict for pattern %q: %s", pattern, out)
			}
			return fmt.Errorf("reservation failed for pattern %q: %w (%s)", pattern, err, out)
		}
	}
	return nil
}

// Release releases all reservations owned by the given owner.
func (b *ReservationBridge) Release(owner string) {
	if b.icPath == "" {
		return
	}
	args := []string{
		"coordination", "release",
		"--owner=" + owner,
		"--scope=" + b.projectDir,
	}
	// Fire-and-forget with bounded timeout (per intercore-bridge-subprocess-lifecycle learnings)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		exec.CommandContext(ctx, b.icPath, args...).Run()
	}()
}

func (b *ReservationBridge) buildReserveArgs(owner, pattern string, ttlSeconds int) []string {
	return []string{
		"coordination", "reserve",
		"--owner=" + owner,
		"--scope=" + b.projectDir,
		"--pattern=" + pattern,
		"--exclusive",
		"--ttl=" + strconv.Itoa(ttlSeconds),
	}
}
```

**Step 4: Run test**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestReservation -v`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/subagent/reservation.go internal/subagent/reservation_test.go
git commit -m "feat(subagent): add Intercore reservation bridge for write coordination"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/subagent/ -v`
  expect: exit 0
</verify>

---

### Task 6: SubagentRunner (F1)

**Files:**
- Create: `os/Skaffen/internal/subagent/runner.go`
- Test: `os/Skaffen/internal/subagent/runner_test.go`

**Step 1: Write the test**

```go
package subagent

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/mistakeknot/Skaffen/internal/agentloop"
	"github.com/mistakeknot/Skaffen/internal/provider"
)

// mockProvider implements provider.Provider for testing.
type mockProvider struct {
	response string
}

func (m *mockProvider) Name() string { return "mock" }
func (m *mockProvider) Stream(_ context.Context, msgs []provider.Message, _ []provider.ToolDef, _ provider.Config) (*provider.StreamResponse, error) {
	return provider.NewMockStream(m.response, provider.Usage{InputTokens: 10, OutputTokens: 5}), nil
}

func TestRunner_ConcurrentExecution(t *testing.T) {
	reg := NewTypeRegistry("")
	prov := &mockProvider{response: "result"}
	reservation := &ReservationBridge{} // no ic
	var callCount atomic.Int32

	runner := NewRunner(reg, prov, reservation, RunnerConfig{
		MaxConcurrent: 3,
		StatusCB: func(u StatusUpdate) {
			if u.Status == StatusDone {
				callCount.Add(1)
			}
		},
	})

	tasks := []SubagentTask{
		{Type: "explore", Prompt: "task 1", Description: "find files"},
		{Type: "explore", Prompt: "task 2", Description: "search code"},
	}

	results, err := runner.Run(context.Background(), tasks)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if len(results) != 2 {
		t.Fatalf("got %d results, want 2", len(results))
	}
	for _, r := range results {
		if r.Status != StatusDone {
			t.Errorf("result %s status = %v, want Done", r.ID, r.Status)
		}
		if r.Response == "" {
			t.Errorf("result %s has empty response", r.ID)
		}
	}
	if callCount.Load() != 2 {
		t.Errorf("status callback called %d times for Done, want 2", callCount.Load())
	}
}

func TestRunner_Timeout(t *testing.T) {
	reg := NewTypeRegistry("")
	// Override explore type with very short timeout for test
	reg.types["explore"] = SubagentType{
		Name:     "explore",
		Tools:    []string{"read"},
		ReadOnly: true,
		MaxTurns: 100, // high turns — should hit timeout first
		Timeout:  Duration{50 * time.Millisecond},
	}
	prov := &slowProvider{delay: 200 * time.Millisecond}
	reservation := &ReservationBridge{}

	runner := NewRunner(reg, prov, reservation, RunnerConfig{MaxConcurrent: 1})
	tasks := []SubagentTask{{Type: "explore", Prompt: "slow task", Description: "slow"}}

	results, _ := runner.Run(context.Background(), tasks)
	if len(results) != 1 {
		t.Fatalf("got %d results, want 1", len(results))
	}
	if results[0].Status != StatusFailed {
		t.Errorf("status = %v, want Failed", results[0].Status)
	}
	if results[0].Error == nil {
		t.Error("expected timeout error")
	}
}

// slowProvider delays responses for timeout testing.
type slowProvider struct {
	delay time.Duration
}

func (p *slowProvider) Name() string { return "slow-mock" }
func (p *slowProvider) Stream(ctx context.Context, _ []provider.Message, _ []provider.ToolDef, _ provider.Config) (*provider.StreamResponse, error) {
	select {
	case <-time.After(p.delay):
		return provider.NewMockStream("late", provider.Usage{}), nil
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}
```

Note: This test requires `provider.NewMockStream` — a test helper. Check if it exists, otherwise add it. If it doesn't exist, create a minimal version in `provider/mock_test.go` or use the existing test infrastructure.

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestRunner -v`
Expected: FAIL (Runner not defined)

**Step 3: Write the runner**

```go
package subagent

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/mistakeknot/Skaffen/internal/agentloop"
	"github.com/mistakeknot/Skaffen/internal/provider"
)

// RunnerConfig configures the SubagentRunner.
type RunnerConfig struct {
	MaxConcurrent int            // max goroutines (default 5)
	StatusCB      StatusCallback // optional real-time status updates
	ParentEmitter agentloop.Emitter // optional — subagent evidence flushes here
}

// Runner spawns, monitors, and collects results from subagent goroutines.
type Runner struct {
	registry    *TypeRegistry
	provider    provider.Provider
	reservation *ReservationBridge
	config      RunnerConfig
}

// NewRunner creates a subagent runner.
func NewRunner(reg *TypeRegistry, prov provider.Provider, res *ReservationBridge, cfg RunnerConfig) *Runner {
	if cfg.MaxConcurrent <= 0 {
		cfg.MaxConcurrent = 5
	}
	if cfg.ParentEmitter == nil {
		cfg.ParentEmitter = &agentloop.NoOpEmitter{}
	}
	return &Runner{
		registry:    reg,
		provider:    prov,
		reservation: res,
		config:      cfg,
	}
}

// Run executes subagent tasks concurrently, respecting MaxConcurrent.
// Returns results for all tasks (including failed ones). The overall error
// is non-nil only if something fundamental goes wrong (not per-task failures).
func (r *Runner) Run(ctx context.Context, tasks []SubagentTask) ([]SubagentResult, error) {
	if len(tasks) == 0 {
		return nil, nil
	}

	// Assign IDs
	for i := range tasks {
		if tasks[i].ID == "" {
			tasks[i].ID = fmt.Sprintf("sub-%d", i)
		}
	}

	sem := make(chan struct{}, r.config.MaxConcurrent)
	var wg sync.WaitGroup
	results := make([]SubagentResult, len(tasks))

	for i, task := range tasks {
		i, task := i, task
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}        // acquire
			defer func() { <-sem }() // release

			results[i] = r.runOne(ctx, task)
		}()
	}

	wg.Wait()
	return results, nil
}

func (r *Runner) runOne(ctx context.Context, task SubagentTask) SubagentResult {
	start := time.Now()

	result := SubagentResult{
		ID:          task.ID,
		Description: task.Description,
	}

	// Look up type
	st, err := r.registry.Get(task.Type)
	if err != nil {
		result.Error = err
		result.Status = StatusFailed
		r.emitStatus(StatusUpdate{ID: task.ID, Description: task.Description, Status: StatusFailed, Error: err})
		return result
	}

	// Acquire file reservations for write-capable subagents
	if !st.ReadOnly && len(task.FilePatterns) > 0 {
		ttl := int(st.Timeout.Seconds())
		if ttl == 0 {
			ttl = 120
		}
		if err := r.reservation.Reserve(task.ID, task.FilePatterns, ttl); err != nil {
			result.Error = fmt.Errorf("reservation: %w", err)
			result.Status = StatusFailed
			r.emitStatus(StatusUpdate{ID: task.ID, Description: task.Description, Status: StatusFailed, Error: result.Error})
			return result
		}
		defer r.reservation.Release(task.ID)
	}

	// Set up per-subagent context with timeout
	timeout := st.Timeout.Duration
	if timeout == 0 {
		timeout = 120 * time.Second
	}
	subCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	// Build scoped session
	sess := NewScopedSession(st.SystemPrompt, task.Prompt, task.InjectedContext)

	// Build aggregating emitter
	emitter := NewAggregatingEmitter(task.ID, task.Type, r.config.ParentEmitter)

	// Build tool registry (filtered by type definition)
	reg := r.buildRegistry(st)

	// Build router (inherit parent model or use type override)
	router := &agentloop.NoOpRouter{}
	if st.Model != "" {
		router.Model = st.Model
	}

	// Emit running status
	r.emitStatus(StatusUpdate{ID: task.ID, Description: task.Description, Status: StatusRunning})

	// Create and run the loop
	loop := agentloop.New(r.provider, reg,
		agentloop.WithSession(sess),
		agentloop.WithEmitter(emitter),
		agentloop.WithRouter(router),
		agentloop.WithMaxTurns(st.MaxTurns),
		agentloop.WithSessionID(task.ID),
		agentloop.WithStreamCallback(func(ev agentloop.StreamEvent) {
			if ev.Type == agentloop.StreamTurnComplete {
				r.emitStatus(StatusUpdate{
					ID:          task.ID,
					Description: task.Description,
					Status:      StatusRunning,
					Turn:        ev.TurnNumber,
					MaxTurns:    st.MaxTurns,
					TokensUsed:  ev.Usage.InputTokens + ev.Usage.OutputTokens,
				})
			}
		}),
	)

	loopResult, err := loop.Run(subCtx, task.Prompt, agentloop.LoopConfig{
		Hints: agentloop.SelectionHints{
			Phase:    "subagent",
			Urgency:  "batch",
			TaskType: "analysis",
		},
	})

	result.Duration = time.Since(start)

	if err != nil {
		result.Error = err
		result.Status = StatusFailed
		result.Evidence = emitter.Events()
		result.Usage = emitter.TotalUsage()
		r.emitStatus(StatusUpdate{ID: task.ID, Description: task.Description, Status: StatusFailed, Error: err})
		return result
	}

	result.Response = loopResult.Response
	result.Usage = loopResult.Usage
	result.Turns = loopResult.Turns
	result.Evidence = emitter.Events()
	result.Status = StatusDone

	// Flush evidence to parent
	emitter.Flush()

	r.emitStatus(StatusUpdate{
		ID:          task.ID,
		Description: task.Description,
		Status:      StatusDone,
		Turn:        result.Turns,
		MaxTurns:    st.MaxTurns,
		TokensUsed:  result.Usage.InputTokens + result.Usage.OutputTokens,
	})

	return result
}

// buildRegistry creates a flat agentloop.Registry with only the tools
// allowed by the subagent type definition.
func (r *Runner) buildRegistry(st SubagentType) *agentloop.Registry {
	reg := agentloop.NewRegistry()
	// If st.Tools is nil (general type), register all built-in tools.
	// If st.Tools is set, register only listed tools.
	// For now, we register a placeholder — the actual tools are injected
	// by the caller (AgentTool) which has access to the parent's tool registry.
	return reg
}

func (r *Runner) emitStatus(u StatusUpdate) {
	if r.config.StatusCB != nil {
		r.config.StatusCB(u)
	}
}
```

**Step 4: Check if provider.NewMockStream exists; if not, create test helper**

Run: `cd os/Skaffen && grep -r "NewMockStream" internal/provider/`

If it doesn't exist, create `internal/provider/mock.go`:

```go
package provider

// NewMockStream creates a mock StreamResponse for testing.
// It returns a single end_turn event with the given text and usage.
func NewMockStream(text string, usage Usage) *StreamResponse {
	events := []StreamEvent{
		{Type: EventTextDelta, Text: text},
		{Type: EventDone, Usage: &usage, StopReason: "end_turn"},
	}
	return newMockStreamFromEvents(events)
}
```

This depends on StreamResponse internals. If StreamResponse uses a channel or iterator pattern, adapt accordingly. Read `internal/provider/stream.go` to check.

**Step 5: Run test**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestRunner -v`
Expected: PASS

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/subagent/runner.go internal/subagent/runner_test.go
git add internal/provider/mock.go  # if created
git commit -m "feat(subagent): add Runner with concurrent goroutine lifecycle"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/subagent/ -v`
  expect: exit 0
- run: `cd os/Skaffen && go test -race ./internal/subagent/ -v`
  expect: exit 0
</verify>

---

### Task 7: Agent Tool (F4)

**Files:**
- Create: `os/Skaffen/internal/subagent/tool.go`
- Test: `os/Skaffen/internal/subagent/tool_test.go`

**Step 1: Write the test**

```go
package subagent

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
)

func TestAgentTool_Schema(t *testing.T) {
	reg := NewTypeRegistry("")
	tool := NewAgentTool(reg, nil)

	schema := tool.Schema()
	var s map[string]interface{}
	if err := json.Unmarshal(schema, &s); err != nil {
		t.Fatalf("Schema() not valid JSON: %v", err)
	}
	// Should have required fields
	required, _ := s["required"].([]interface{})
	requiredNames := make([]string, len(required))
	for i, r := range required {
		requiredNames[i], _ = r.(string)
	}
	for _, name := range []string{"subagent_type", "prompt", "description"} {
		found := false
		for _, r := range requiredNames {
			if r == name {
				found = true
			}
		}
		if !found {
			t.Errorf("missing required field %q", name)
		}
	}
}

func TestAgentTool_InvalidType(t *testing.T) {
	reg := NewTypeRegistry("")
	tool := NewAgentTool(reg, nil)

	input := `{"subagent_type":"nonexistent","prompt":"test","description":"test"}`
	result := tool.Execute(context.Background(), json.RawMessage(input))
	if !result.IsError {
		t.Error("should error on unknown type")
	}
	if !strings.Contains(result.Content, "unknown subagent type") {
		t.Errorf("error message = %q, want 'unknown subagent type'", result.Content)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestAgentTool -v`
Expected: FAIL

**Step 3: Write the tool**

```go
package subagent

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/mistakeknot/Skaffen/internal/agentloop"
)

// AgentTool is a tool.Tool (via agentloop.Tool) that allows the LLM to spawn subagents.
type AgentTool struct {
	registry *TypeRegistry
	runner   *Runner
}

// agentToolInput defines the JSON input schema for the Agent tool.
type agentToolInput struct {
	SubagentType string   `json:"subagent_type"`
	Prompt       string   `json:"prompt"`
	Description  string   `json:"description"`
	Context      []string `json:"context,omitempty"`
	FilePatterns []string `json:"file_patterns,omitempty"`
}

// NewAgentTool creates an Agent tool. Runner can be nil during schema-only
// usage (e.g., startup before provider is connected).
func NewAgentTool(reg *TypeRegistry, runner *Runner) *AgentTool {
	return &AgentTool{registry: reg, runner: runner}
}

// SetRunner sets the runner after construction (for lazy initialization).
func (t *AgentTool) SetRunner(r *Runner) {
	t.runner = r
}

func (t *AgentTool) Name() string { return "Agent" }

func (t *AgentTool) Description() string {
	return "Launch a subagent to handle a focused task autonomously. " +
		"Use for parallel research, codebase exploration, or delegating independent work. " +
		"Multiple Agent calls in a single turn run concurrently."
}

func (t *AgentTool) Schema() json.RawMessage {
	typeNames := t.registry.Names()
	typeEnum, _ := json.Marshal(typeNames)

	// Build type descriptions for the enum
	var typeDescs []string
	for _, name := range typeNames {
		st, _ := t.registry.Get(name)
		typeDescs = append(typeDescs, fmt.Sprintf("%s: %s", name, st.Description))
	}

	schema := fmt.Sprintf(`{
		"type": "object",
		"required": ["subagent_type", "prompt", "description"],
		"properties": {
			"subagent_type": {
				"type": "string",
				"enum": %s,
				"description": "The type of subagent to spawn. Available types:\n%s"
			},
			"prompt": {
				"type": "string",
				"description": "The task for the subagent to perform. Be specific and self-contained."
			},
			"description": {
				"type": "string",
				"description": "A short (3-5 word) description shown in the UI status."
			},
			"context": {
				"type": "array",
				"items": {"type": "string"},
				"description": "Optional context strings to inject into the subagent's session."
			},
			"file_patterns": {
				"type": "array",
				"items": {"type": "string"},
				"description": "Glob patterns for files this subagent will modify. Required for write-capable types."
			}
		}
	}`, typeEnum, strings.Join(typeDescs, "\n"))

	return json.RawMessage(schema)
}

func (t *AgentTool) Execute(ctx context.Context, params json.RawMessage) agentloop.ToolResult {
	var input agentToolInput
	if err := json.Unmarshal(params, &input); err != nil {
		return agentloop.ToolResult{Content: fmt.Sprintf("invalid input: %v", err), IsError: true}
	}

	// Validate type exists
	if _, err := t.registry.Get(input.SubagentType); err != nil {
		return agentloop.ToolResult{Content: err.Error(), IsError: true}
	}

	if t.runner == nil {
		return agentloop.ToolResult{Content: "subagent runner not initialized", IsError: true}
	}

	// Build injected context from context array
	injected := strings.Join(input.Context, "\n\n")

	task := SubagentTask{
		Type:            input.SubagentType,
		Prompt:          input.Prompt,
		Description:     input.Description,
		InjectedContext: injected,
		FilePatterns:    input.FilePatterns,
	}

	results, err := t.runner.Run(ctx, []SubagentTask{task})
	if err != nil {
		return agentloop.ToolResult{Content: fmt.Sprintf("subagent failed: %v", err), IsError: true}
	}
	if len(results) == 0 {
		return agentloop.ToolResult{Content: "no results from subagent", IsError: true}
	}

	r := results[0]
	if r.Error != nil {
		return agentloop.ToolResult{
			Content: fmt.Sprintf("Subagent %q failed: %v", r.Description, r.Error),
			IsError: true,
		}
	}

	// Format result with metadata
	content := fmt.Sprintf("Subagent %q completed (%d turns, %d tokens):\n\n%s",
		r.Description, r.Turns, r.Usage.InputTokens+r.Usage.OutputTokens, r.Response)

	return agentloop.ToolResult{Content: content, IsError: false}
}
```

**Step 4: Run test**

Run: `cd os/Skaffen && go test ./internal/subagent/ -run TestAgentTool -v`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/subagent/tool.go internal/subagent/tool_test.go
git commit -m "feat(subagent): add Agent tool for LLM-invocable subagent dispatch"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/subagent/ -v`
  expect: exit 0
</verify>

---

### Task 8: TUI Collapsible Block Component (F6)

**Files:**
- Create: `os/Skaffen/internal/tui/subagent.go`
- Test: `os/Skaffen/internal/tui/subagent_test.go`

**Step 1: Write the test**

```go
package tui

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Skaffen/internal/subagent"
)

func TestSubagentBlock_CollapsedView(t *testing.T) {
	b := newSubagentBlock("sub-1", "find all Go files")
	b.update(subagent.StatusUpdate{
		ID:          "sub-1",
		Description: "find all Go files",
		Status:      subagent.StatusDone,
		Turn:        3,
		MaxTurns:    10,
		TokensUsed:  1234,
	})
	b.response = "Found 42 Go files in the project."

	view := b.View(80, false) // collapsed
	if !strings.Contains(view, "find all Go files") {
		t.Error("collapsed view should contain description")
	}
	if !strings.Contains(view, "done") {
		t.Error("collapsed view should show status")
	}
	if !strings.Contains(view, "1.2k") {
		t.Error("collapsed view should show token count")
	}
}

func TestSubagentBlock_ExpandedView(t *testing.T) {
	b := newSubagentBlock("sub-1", "find files")
	b.response = "Found files:\n- main.go\n- types.go"
	b.update(subagent.StatusUpdate{Status: subagent.StatusDone})

	view := b.View(80, true) // expanded
	if !strings.Contains(view, "main.go") {
		t.Error("expanded view should contain response")
	}
}

func TestSubagentBlock_RunningSpinner(t *testing.T) {
	b := newSubagentBlock("sub-1", "searching")
	b.update(subagent.StatusUpdate{
		Status:   subagent.StatusRunning,
		Turn:     2,
		MaxTurns: 10,
	})

	view := b.View(80, false)
	if !strings.Contains(view, "searching") {
		t.Error("running view should contain description")
	}
	if !strings.Contains(view, "turn 2/10") {
		t.Error("running view should show turn progress")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/tui/ -run TestSubagentBlock -v`
Expected: FAIL

**Step 3: Write the component**

```go
package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Skaffen/internal/subagent"
	"github.com/mistakeknot/Masaq/theme"
)

// subagentBlock renders a single subagent result as a collapsible inline block.
type subagentBlock struct {
	id          string
	description string
	status      subagent.SubagentStatus
	turn        int
	maxTurns    int
	tokensUsed  int
	response    string
	errMsg      string
}

func newSubagentBlock(id, description string) *subagentBlock {
	return &subagentBlock{
		id:          id,
		description: description,
		status:      subagent.StatusPending,
	}
}

func (b *subagentBlock) update(u subagent.StatusUpdate) {
	b.status = u.Status
	b.turn = u.Turn
	b.maxTurns = u.MaxTurns
	b.tokensUsed = u.TokensUsed
	if u.Error != nil {
		b.errMsg = u.Error.Error()
	}
}

func (b *subagentBlock) View(width int, expanded bool) string {
	c := theme.Current().Semantic()

	var icon string
	var statusText string
	var iconColor lipgloss.AdaptiveColor

	switch b.status {
	case subagent.StatusPending:
		icon = "○"
		statusText = "pending"
		iconColor = c.FgDim
	case subagent.StatusRunning:
		icon = "◐"
		statusText = fmt.Sprintf("turn %d/%d", b.turn, b.maxTurns)
		iconColor = c.Primary
	case subagent.StatusDone:
		icon = "✓"
		statusText = fmt.Sprintf("done, %s tokens", formatTokens(b.tokensUsed))
		iconColor = c.Success
	case subagent.StatusFailed:
		icon = "✗"
		statusText = "failed"
		if b.errMsg != "" {
			statusText = fmt.Sprintf("failed: %s", truncate(b.errMsg, 40))
		}
		iconColor = c.Error
	}

	toggle := "▸"
	if expanded {
		toggle = "▾"
	}

	iconStyle := lipgloss.NewStyle().Foreground(iconColor.Color())
	dimStyle := lipgloss.NewStyle().Foreground(c.FgDim.Color())

	header := fmt.Sprintf("%s %s %s %s",
		iconStyle.Render(icon),
		toggle,
		b.description,
		dimStyle.Render("("+statusText+")"),
	)

	if !expanded || b.response == "" {
		return header
	}

	// Expanded: show response below header
	bodyStyle := lipgloss.NewStyle().
		Foreground(c.Fg.Color()).
		PaddingLeft(4).
		Width(width - 4)
	body := bodyStyle.Render(b.response)

	return header + "\n" + body
}

// subagentTracker manages multiple subagent blocks for the TUI.
type subagentTracker struct {
	blocks   map[string]*subagentBlock
	order    []string // insertion order for deterministic rendering
	expanded map[string]bool
}

func newSubagentTracker() *subagentTracker {
	return &subagentTracker{
		blocks:   make(map[string]*subagentBlock),
		expanded: make(map[string]bool),
	}
}

func (t *subagentTracker) update(u subagent.StatusUpdate) {
	b, ok := t.blocks[u.ID]
	if !ok {
		b = newSubagentBlock(u.ID, u.Description)
		t.blocks[u.ID] = b
		t.order = append(t.order, u.ID)
	}
	b.update(u)
}

func (t *subagentTracker) setResponse(id, response string) {
	if b, ok := t.blocks[id]; ok {
		b.response = response
	}
}

func (t *subagentTracker) toggle(id string) {
	t.expanded[id] = !t.expanded[id]
}

func (t *subagentTracker) View(width int) string {
	if len(t.order) == 0 {
		return ""
	}
	var lines []string
	for _, id := range t.order {
		b := t.blocks[id]
		lines = append(lines, b.View(width, t.expanded[id]))
	}
	return strings.Join(lines, "\n")
}

// formatTokens returns a human-readable token count (e.g., "1.2k", "45k").
func formatTokens(n int) string {
	if n < 1000 {
		return fmt.Sprintf("%d", n)
	}
	if n < 10000 {
		return fmt.Sprintf("%.1fk", float64(n)/1000)
	}
	return fmt.Sprintf("%dk", n/1000)
}

// truncate shortens a string to maxLen, adding "..." if truncated.
func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}
```

**Step 4: Run test**

Run: `cd os/Skaffen && go test ./internal/tui/ -run TestSubagentBlock -v`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tui/subagent.go internal/tui/subagent_test.go
git commit -m "feat(tui): add collapsible subagent block component"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tui/ -run TestSubagentBlock -v`
  expect: exit 0
</verify>

---

### Task 9: Wire subagent system into main.go and TUI

**Files:**
- Modify: `os/Skaffen/cmd/skaffen/main.go` — register Agent tool
- Modify: `os/Skaffen/internal/tui/app.go` — add subagent status handling
- Modify: `os/Skaffen/internal/tool/builtin.go` — export tool list for subagent registry filtering

**Step 1: Add Agent tool registration to main.go**

In `cmd/skaffen/main.go`, after `tool.RegisterBuiltins(reg)` and MCP tool loading, add:

```go
// Initialize subagent system
subagentConfigDir := filepath.Join(workDir, ".skaffen", "agents")
typeReg := subagent.NewTypeRegistry(subagentConfigDir)
agentTool := subagent.NewAgentTool(typeReg, nil) // runner set after provider init

// Register Agent tool for all phases
reg.RegisterForPhases(agentTool, []tool.Phase{
    tool.PhaseBrainstorm, tool.PhasePlan, tool.PhaseBuild, tool.PhaseReview,
})
```

After provider is initialized, wire the runner:

```go
reservation := subagent.NewReservationBridge(workDir)
runner := subagent.NewRunner(typeReg, prov, reservation, subagent.RunnerConfig{
    MaxConcurrent: 5,
    ParentEmitter: emitter,
    StatusCB: func(u subagent.StatusUpdate) {
        // Send to TUI if in TUI mode
        if program != nil {
            program.Send(subagentStatusMsg(u))
        }
    },
})
agentTool.SetRunner(runner)
```

**Step 2: Add subagent status message handling to TUI**

In `internal/tui/app.go`, add a new message type and handler:

```go
// subagentStatusMsg wraps a subagent.StatusUpdate for the Bubble Tea message loop.
type subagentStatusMsg subagent.StatusUpdate
```

In `appModel`, add the tracker field:

```go
subagents *subagentTracker
```

Initialize in `newAppModel`:

```go
subagents: newSubagentTracker(),
```

In `Update`, add a case for the new message type:

```go
case subagentStatusMsg:
    m.subagents.update(subagent.StatusUpdate(msg))
    // Render updated subagent blocks into viewport
    m.viewport.AppendContent("\r" + m.subagents.View(m.width))
```

**Step 3: Ensure AgentTool bridges between tool.Tool and agentloop.Tool**

The Agent tool implements `agentloop.Tool` (Name/Description/Schema/Execute returning `agentloop.ToolResult`). But `tool.Registry.Register` expects `tool.Tool` (which returns `tool.ToolResult`). Create a bridge in the registration step — or make AgentTool implement both by also satisfying `tool.Tool`:

Add to `subagent/tool.go`:

```go
// ExecuteTool satisfies tool.Tool interface (returns tool.ToolResult).
func (t *AgentTool) ExecuteTool(ctx context.Context, params json.RawMessage) tool.ToolResult {
    r := t.Execute(ctx, params)
    return tool.ToolResult{Content: r.Content, IsError: r.IsError}
}
```

Or, since `tool.Tool` and `agentloop.Tool` have the same `Execute` signature (both return a struct with Content/IsError), just make `AgentTool.Execute` return `tool.ToolResult` and have the `toolBridge` in `agent.go` handle the conversion as it does for all other tools.

**Step 4: Run full test suite**

Run: `cd os/Skaffen && go test ./... -count=1`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add cmd/skaffen/main.go internal/tui/app.go internal/tool/builtin.go
git commit -m "feat: wire subagent system into main.go and TUI"
```

<verify>
- run: `cd os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
- run: `cd os/Skaffen && go test ./... -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./...`
  expect: exit 0
</verify>

---

### Task 10: Integration test — end-to-end subagent flow

**Files:**
- Create: `os/Skaffen/internal/subagent/integration_test.go`

**Step 1: Write the integration test**

```go
//go:build integration

package subagent

import (
	"context"
	"testing"
	"time"
)

func TestIntegration_ExploreSubagent(t *testing.T) {
	// Uses mock provider — no real LLM calls
	reg := NewTypeRegistry("")
	prov := &mockProvider{response: "Found 3 Go files matching the pattern."}
	reservation := NewReservationBridge(".")

	var statuses []StatusUpdate
	runner := NewRunner(reg, prov, reservation, RunnerConfig{
		MaxConcurrent: 2,
		StatusCB: func(u StatusUpdate) {
			statuses = append(statuses, u)
		},
	})

	tasks := []SubagentTask{
		{
			Type:        "explore",
			Prompt:      "Find all Go files that import 'context'",
			Description: "find context imports",
		},
		{
			Type:            "explore",
			Prompt:          "List all test files",
			Description:     "list tests",
			InjectedContext: "The project root is os/Skaffen/",
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	results, err := runner.Run(ctx, tasks)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}

	if len(results) != 2 {
		t.Fatalf("got %d results, want 2", len(results))
	}

	for i, r := range results {
		if r.Status != StatusDone {
			t.Errorf("result[%d] status = %v, want Done (error: %v)", i, r.Status, r.Error)
		}
		if r.Response == "" {
			t.Errorf("result[%d] has empty response", i)
		}
	}

	// Verify status callbacks were received
	hasRunning := false
	hasDone := false
	for _, s := range statuses {
		if s.Status == StatusRunning {
			hasRunning = true
		}
		if s.Status == StatusDone {
			hasDone = true
		}
	}
	if !hasRunning {
		t.Error("no StatusRunning callback received")
	}
	if !hasDone {
		t.Error("no StatusDone callback received")
	}
}
```

**Step 2: Run integration test**

Run: `cd os/Skaffen && go test -tags integration ./internal/subagent/ -run TestIntegration -v`
Expected: PASS

**Step 3: Commit**

```bash
cd os/Skaffen && git add internal/subagent/integration_test.go
git commit -m "test(subagent): add integration test for explore subagent flow"
```

<verify>
- run: `cd os/Skaffen && go test -tags integration ./internal/subagent/ -v`
  expect: exit 0
- run: `cd os/Skaffen && go test -race ./internal/subagent/ -v`
  expect: exit 0
</verify>
