---
artifact_type: plan
bead: Sylveste-xe0
stage: design
prd: docs/prds/2026-03-11-skaffen-go-rewrite.md
requirements:
  - "Agent loop: observe→orient→decide→act→reflect→compound with clean exit"
  - "Phase FSM: brainstorm→plan→build→review→ship with explicit transitions"
  - "Constructor deps via interfaces: Router, Session, Emitter — all mockable"
  - "Hard tool gating per phase via tool.Registry"
  - "Deterministic tests with mock provider"
---
# F3: OODARC Agent Loop + Phase FSM

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-xe0
**Goal:** The main agent loop that wires F1 (provider) and F2 (tools) into the OODARC execution cycle. This is the brain of Skaffen — everything before was infrastructure.

**Architecture:** `internal/agent/` package. The `Agent` struct holds interface deps (Provider, Registry, Router, Session, Emitter) and runs the OODARC loop. Each OODARC step is a private method. Phase transitions are an explicit FSM. Dependencies F4/F5/F6 don't exist yet, so Router/Session/Emitter are minimal interfaces defined here with no-op defaults — the real implementations come in later features.

**Tech Stack:** Go 1.22, channels for streaming, `context` for cancellation, `sync` for goroutine-per-tool execution. No external dependencies.

**Patterns from F1/F2:** Same conventions — interfaces in package root, implementations in separate files, table-driven tests, mock provider via channel-based `StreamResponse`.

## Prior Learnings

- F1/F2 established the mock provider pattern: create a `chan StreamEvent`, push events, close channel, wrap in `NewStreamResponse`. Reuse this for agent loop tests.
- `tool.Registry.Execute()` already hard-gates by phase — the agent loop just passes the current phase through, doesn't need its own gating logic.
- `provider.CollectedResponse` has `StopReason` ("end_turn", "tool_use", "max_tokens") — the agent loop uses this to decide whether to continue (tool_use) or exit (end_turn).

---

## Must-Haves

**Truths** (observable behaviors):
- `go test ./internal/agent/...` passes
- Agent loop exits cleanly when provider returns `StopReason: "end_turn"`
- Agent loop executes tool calls and feeds results back to provider on `StopReason: "tool_use"`
- Phase FSM transitions in order: brainstorm→plan→build→review→ship
- Phase FSM rejects out-of-order transitions
- Tool calls are gated by current phase (delegated to `tool.Registry`)
- Context cancellation terminates the loop within one turn

**Artifacts** (files that must exist):
- `internal/agent/agent.go` — Agent struct, constructor, Run() method
- `internal/agent/loop.go` — OODARC step implementations
- `internal/agent/phase.go` — Phase FSM
- `internal/agent/deps.go` — Router, Session, Emitter interfaces + no-op defaults
- `internal/agent/agent_test.go` — deterministic loop tests with mock provider

**Key Links** (where breakage causes cascading failures):
- `Agent.Run()` is the entry point that F7 (CLI) calls — its signature must be stable
- The loop builds `provider.Message` with `tool_result` content blocks from `tool.ToolResult` — format must match Anthropic API
- Phase FSM drives `tool.Registry.Tools(phase)` — wrong phase = wrong tools exposed to LLM

---

### Task 1: Define dependency interfaces and no-op defaults ✅

**Files:**
- `internal/agent/deps.go` (new)

**Changes:**

```go
package agent

import "github.com/mistakeknot/skaffen/internal/tool"

// Router selects which model to use per turn.
// Stubbed here — real implementation comes in F4.
type Router interface {
    SelectModel(phase tool.Phase) (model string, reason string)
}

// Session persists conversation state.
// Stubbed here — real implementation comes in F5.
type Session interface {
    // SystemPrompt returns the system prompt for the current phase.
    SystemPrompt(phase tool.Phase) string
    // Save persists a turn (messages + usage) to the session log.
    Save(turn Turn) error
}

// Emitter receives structured evidence per turn.
// Stubbed here — real implementation comes in F6.
type Emitter interface {
    Emit(event Evidence) error
}

// Turn captures one loop iteration for session persistence.
type Turn struct {
    Phase      tool.Phase
    Messages   []provider.Message  // assistant response + tool results
    Usage      provider.Usage
    ToolCalls  int
}

// Evidence captures one turn's structured data for the reflect step.
type Evidence struct {
    Phase      tool.Phase `json:"phase"`
    TurnNumber int        `json:"turn"`
    ToolCalls  []string   `json:"tool_calls,omitempty"` // tool names used
    TokensIn   int        `json:"tokens_in"`
    TokensOut  int        `json:"tokens_out"`
    StopReason string     `json:"stop_reason"`
}

// NoOpRouter always returns the default model.
type NoOpRouter struct{ Model string }
func (r *NoOpRouter) SelectModel(_ tool.Phase) (string, string) {
    if r.Model == "" { return "claude-sonnet-4-20250514", "default" }
    return r.Model, "configured"
}

// NoOpSession discards all state.
type NoOpSession struct{ Prompt string }
func (s *NoOpSession) SystemPrompt(_ tool.Phase) string { return s.Prompt }
func (s *NoOpSession) Save(_ Turn) error { return nil }

// NoOpEmitter discards all evidence.
type NoOpEmitter struct{}
func (e *NoOpEmitter) Emit(_ Evidence) error { return nil }
```

**Exit criteria:** `go vet ./internal/agent/` passes.

---

### Task 2: Phase FSM ✅

**Files:**
- `internal/agent/phase.go` (new)

**Changes:**

```go
package agent

import (
    "fmt"
    "github.com/mistakeknot/skaffen/internal/tool"
)

// phaseFSM manages phase transitions.
type phaseFSM struct {
    current tool.Phase
    order   []tool.Phase
    index   int
}

func newPhaseFSM(start tool.Phase) *phaseFSM {
    order := []tool.Phase{
        tool.PhaseBrainstorm,
        tool.PhasePlan,
        tool.PhaseBuild,
        tool.PhaseReview,
        tool.PhaseShip,
    }
    idx := 0
    for i, p := range order {
        if p == start { idx = i; break }
    }
    return &phaseFSM{current: start, order: order, index: idx}
}

// Current returns the current phase.
func (f *phaseFSM) Current() tool.Phase { return f.current }

// Advance moves to the next phase. Returns error if already at the end.
func (f *phaseFSM) Advance() error {
    if f.index >= len(f.order)-1 {
        return fmt.Errorf("cannot advance past %s", f.current)
    }
    f.index++
    f.current = f.order[f.index]
    return nil
}

// IsTerminal returns true if we're at the last phase.
func (f *phaseFSM) IsTerminal() bool {
    return f.index >= len(f.order)-1
}
```

**Exit criteria:** FSM unit test: advance through all phases, verify terminal detection, verify error on advance past ship.

---

### Task 3: Agent struct and constructor ✅

**Files:**
- `internal/agent/agent.go` (new)

**Changes:**

```go
package agent

import (
    "github.com/mistakeknot/skaffen/internal/provider"
    "github.com/mistakeknot/skaffen/internal/tool"
)

// Agent runs the OODARC loop.
type Agent struct {
    provider provider.Provider
    registry *tool.Registry
    router   Router
    session  Session
    emitter  Emitter
    fsm      *phaseFSM

    // Config
    maxTurns int // safety limit, default 100
}

// Option configures the agent.
type Option func(*Agent)

func WithMaxTurns(n int) Option { return func(a *Agent) { a.maxTurns = n } }
func WithRouter(r Router) Option { return func(a *Agent) { a.router = r } }
func WithSession(s Session) Option { return func(a *Agent) { a.session = s } }
func WithEmitter(e Emitter) Option { return func(a *Agent) { a.emitter = e } }
func WithStartPhase(p tool.Phase) Option { return func(a *Agent) { a.fsm = newPhaseFSM(p) } }

// New creates an Agent with the given provider, tool registry, and options.
func New(p provider.Provider, reg *tool.Registry, opts ...Option) *Agent {
    a := &Agent{
        provider: p,
        registry: reg,
        router:   &NoOpRouter{},
        session:  &NoOpSession{},
        emitter:  &NoOpEmitter{},
        fsm:      newPhaseFSM(tool.PhaseBuild), // default to build phase
        maxTurns: 100,
    }
    for _, opt := range opts {
        opt(a)
    }
    return a
}
```

**Exit criteria:** `go vet ./internal/agent/` passes. Constructor test: create agent with defaults, verify fields.

---

### Task 4: OODARC loop — Run() method ✅

**Files:**
- `internal/agent/loop.go` (new)

**Changes:**

The Run method implements the full OODARC cycle. Each iteration:
1. **Observe**: get current conversation history (messages so far)
2. **Orient**: select model (via Router), get available tools (via Registry for current phase), get system prompt (via Session)
3. **Decide**: call `provider.Stream()` with oriented context, collect response
4. **Act**: if StopReason is "tool_use", execute each tool call via Registry, build tool_result messages
5. **Reflect**: emit Evidence via Emitter
6. **Compound**: save Turn via Session

```go
func (a *Agent) Run(ctx context.Context, task string) (*RunResult, error) {
    messages := []provider.Message{
        {Role: provider.RoleUser, Content: []provider.ContentBlock{
            {Type: "text", Text: task},
        }},
    }

    var totalUsage provider.Usage
    turn := 0

    for turn < a.maxTurns {
        turn++

        // Orient
        model, _ := a.router.SelectModel(a.fsm.Current())
        tools := a.registry.Tools(a.fsm.Current())
        systemPrompt := a.session.SystemPrompt(a.fsm.Current())

        // Convert tool.ToolDef → provider.ToolDef
        providerTools := convertToolDefs(tools)

        cfg := provider.Config{
            Model:     model,
            MaxTokens: 8192,
            System:    systemPrompt,
        }

        // Decide
        stream, err := a.provider.Stream(ctx, messages, providerTools, cfg)
        if err != nil {
            return nil, fmt.Errorf("turn %d: stream: %w", turn, err)
        }
        collected, err := stream.Collect()
        if err != nil {
            return nil, fmt.Errorf("turn %d: collect: %w", turn, err)
        }

        // Accumulate usage
        totalUsage.InputTokens += collected.Usage.InputTokens
        totalUsage.OutputTokens += collected.Usage.OutputTokens

        // Build assistant message from response
        assistantMsg := buildAssistantMessage(collected)
        messages = append(messages, assistantMsg)

        // Act — execute tool calls if stop_reason is "tool_use"
        if collected.StopReason == "tool_use" && len(collected.ToolCalls) > 0 {
            toolResultMsg := a.executeTools(ctx, collected.ToolCalls)
            messages = append(messages, toolResultMsg)
        }

        // Reflect
        toolNames := make([]string, len(collected.ToolCalls))
        for i, tc := range collected.ToolCalls { toolNames[i] = tc.Name }
        a.emitter.Emit(Evidence{
            Phase: a.fsm.Current(), TurnNumber: turn,
            ToolCalls: toolNames,
            TokensIn: collected.Usage.InputTokens,
            TokensOut: collected.Usage.OutputTokens,
            StopReason: collected.StopReason,
        })

        // Compound
        a.session.Save(Turn{
            Phase: a.fsm.Current(),
            Usage: collected.Usage,
            ToolCalls: len(collected.ToolCalls),
        })

        // Check exit conditions
        if collected.StopReason == "end_turn" {
            return &RunResult{
                Response: collected.Text, Usage: totalUsage,
                Turns: turn, Phase: a.fsm.Current(),
            }, nil
        }

        // Check context cancellation
        select {
        case <-ctx.Done():
            return nil, ctx.Err()
        default:
        }
    }

    return nil, fmt.Errorf("exceeded max turns (%d)", a.maxTurns)
}

// RunResult holds the outcome of a completed agent run.
type RunResult struct {
    Response string
    Usage    provider.Usage
    Turns    int
    Phase    tool.Phase
}
```

Key helpers:
- `buildAssistantMessage(collected)` → builds `Message{Role: "assistant", Content: [text + tool_use blocks]}`
- `executeTools(ctx, toolCalls)` → runs each tool via `a.registry.Execute()`, returns `Message{Role: "user", Content: [tool_result blocks]}`
- `convertToolDefs(toolDefs)` → converts `tool.ToolDef` → `provider.ToolDef`

**Exit criteria:** `go vet ./internal/agent/` passes. Code compiles.

---

### Task 5: Helper functions for message building ✅

**Files:**
- `internal/agent/loop.go` (append to existing)

**Changes:**

```go
// buildAssistantMessage constructs the assistant message from a collected response.
func buildAssistantMessage(c *provider.CollectedResponse) provider.Message {
    var blocks []provider.ContentBlock
    if c.Text != "" {
        blocks = append(blocks, provider.ContentBlock{Type: "text", Text: c.Text})
    }
    for _, tc := range c.ToolCalls {
        blocks = append(blocks, provider.ContentBlock{
            Type:  "tool_use",
            ID:    tc.ID,
            Name:  tc.Name,
            Input: tc.Input,
        })
    }
    return provider.Message{Role: provider.RoleAssistant, Content: blocks}
}

// executeTools runs tool calls and builds the tool_result message.
func (a *Agent) executeTools(ctx context.Context, calls []provider.ToolCall) provider.Message {
    var blocks []provider.ContentBlock
    for _, tc := range calls {
        result := a.registry.Execute(ctx, a.fsm.Current(), tc.Name, tc.Input)
        blocks = append(blocks, provider.ContentBlock{
            Type:          "tool_result",
            ToolUseID:     tc.ID,
            ResultContent: result.Content,
            IsError:       result.IsError,
        })
    }
    return provider.Message{Role: provider.RoleUser, Content: blocks}
}

// convertToolDefs converts tool.ToolDef to provider.ToolDef.
func convertToolDefs(defs []tool.ToolDef) []provider.ToolDef {
    out := make([]provider.ToolDef, len(defs))
    for i, d := range defs {
        out[i] = provider.ToolDef{
            Name:        d.Name,
            Description: d.Description,
            InputSchema: d.InputSchema,
        }
    }
    return out
}
```

**Exit criteria:** Compiles. Helpers are tested implicitly through the agent loop tests in Task 7.

---

### Task 6: Phase transition support in the loop ✅

**Files:**
- `internal/agent/loop.go` (extend Run method)

**Changes:**

Add `AdvancePhase()` method on Agent that the CLI (F7) or a special tool can call to trigger phase transitions:

```go
// AdvancePhase transitions to the next OODARC phase.
func (a *Agent) AdvancePhase() error {
    return a.fsm.Advance()
}

// CurrentPhase returns the current OODARC phase.
func (a *Agent) CurrentPhase() tool.Phase {
    return a.fsm.Current()
}
```

For now, phase transitions are external (CLI-driven). The agent loop itself stays in one phase per `Run()` call. Multi-phase orchestration will be layered in F7 when the CLI can drive phase-to-phase flow. This keeps the loop simple and testable.

**Exit criteria:** Methods compile, tested in Task 7.

---

### Task 7: Deterministic agent loop tests ✅

**Files:**
- `internal/agent/agent_test.go` (new)

**Changes:**

Use the mock provider pattern from F1: create channels, push events, close. Test cases:

1. **Simple text response** — provider returns text with `end_turn` → loop exits after 1 turn, RunResult has response text
2. **Tool use → result → text** — provider returns tool_use, then after tool_result, returns text with end_turn → loop executes tool, feeds result back, exits after 2 turns
3. **Max turns exceeded** — provider always returns tool_use → loop hits maxTurns limit and returns error
4. **Context cancellation** — cancel context mid-loop → loop returns context.Canceled
5. **Phase gate rejection** — mock provider requests a tool not available in current phase → tool_result has IsError=true, loop continues
6. **Phase FSM advance** — start at brainstorm, advance to plan, verify current phase
7. **Multiple tool calls in one turn** — provider returns 2 tool_use blocks → both executed, both results fed back

Mock provider:
```go
type mockProvider struct {
    responses []*provider.StreamResponse
    callIdx   int
}

func (m *mockProvider) Stream(ctx context.Context, msgs []provider.Message, tools []provider.ToolDef, cfg provider.Config) (*provider.StreamResponse, error) {
    if m.callIdx >= len(m.responses) {
        return nil, fmt.Errorf("no more responses")
    }
    resp := m.responses[m.callIdx]
    m.callIdx++
    return resp, nil
}

func (m *mockProvider) Name() string { return "mock" }
```

Helper to build mock stream from events:
```go
func mockStream(events ...provider.StreamEvent) *provider.StreamResponse {
    ch := make(chan provider.StreamEvent, len(events))
    for _, e := range events {
        ch <- e
    }
    close(ch)
    return provider.NewStreamResponse(ch)
}
```

**Exit criteria:** `go test ./internal/agent/ -v` — all 7 test cases pass.

---

### Task 8: Phase FSM unit tests ✅

**Files:**
- `internal/agent/agent_test.go` (append to existing)

**Changes:**

Table-driven FSM tests:
- Start at brainstorm, advance 4 times → reaches ship
- Advance past ship → returns error
- IsTerminal at ship → true
- IsTerminal at build → false
- Start at build → skip brainstorm and plan
- Current returns correct phase at each step

**Exit criteria:** All FSM tests pass.

---

### Task 9: Verify clean build ✅

**Files:** none new

**Changes:**
- `go mod tidy`
- `go vet ./...`
- `go test ./...` (all packages including provider and tool)
- `go build ./cmd/skaffen/`
- Verify no import cycles between `agent`, `provider`, and `tool` packages

**Exit criteria:** `go build ./...` and `go test ./...` pass. Zero import cycles.
