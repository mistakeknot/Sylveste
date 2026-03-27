---
artifact_type: brainstorm
bead: Sylveste-6qb.8
stage: design
---
# Brainstorm: Separate Agent Loop Library from OODARC Workflow Engine

**Bead:** Sylveste-6qb.8
**Goal:** Refactor Skaffen's `internal/agent/` into two layers: (1) a universal agent loop library (Decide→Act core) and (2) an OODARC workflow engine built on top. Other consumers (Intercom, Autarch) import the library without the phased workflow.

## Current Architecture

The agent package has these key files:
- `agent.go` — Agent struct, constructor with functional options, `Run()` entry point
- `loop.go` — The main OODARC loop (Observe→Orient→Decide→Act→Reflect→Compound), tool execution, streaming
- `phase.go` — Phase FSM (Brainstorm→Plan→Build→Review→Ship), linear progression only
- `streaming.go` — StreamEvent types and StreamCallback for TUI
- `deps.go` — Router, Session, Emitter interfaces + NoOp stubs

### Where Phase is Coupled Today

Phase (`tool.Phase`) flows through **4 interfaces** at every turn:

1. **Router**: `SelectModel(phase)` — model selection defaults per phase (Opus for brainstorm, Sonnet for build)
2. **Tool Registry**: `Tools(phase)` returns filtered tool list; `Execute(ctx, phase, name, input)` validates phase gating
3. **Session**: `SystemPrompt(phase, budget)` — phase-specific system prompts
4. **Evidence/Emitter**: Evidence struct records phase for telemetry

The FSM itself is private to agent package and linear-only (no backward, no skip).

### What's Universal (Library Material)

These pieces don't inherently need phases:
- Provider abstraction (LLM streaming, tool call parsing)
- Tool registry (register tools, execute them, return results)
- Budget tracking (token accounting, degradation)
- Complexity classification (input token heuristics)
- Streaming callbacks (text, tool start/complete, turn complete)
- Tool approval gating (approver function before execution)
- Session persistence (save/load turns)
- Evidence emission (telemetry)
- The Decide→Act core loop (call LLM → parse response → execute tools → repeat until end_turn)

### What's OODARC-Specific (Workflow Material)

These pieces are meaningfully phase-dependent:
- Phase FSM (the 5-phase state machine)
- Phase-gated tool access (build-only writes, brainstorm read-only)
- Phase-aware model routing (Opus for brainstorm, Sonnet for build)
- Phase-specific system prompts
- Phase transitions between agent runs

## Design Options

### Option A: Extract `agentloop` Sub-Package

Split `internal/agent/` into:
- `internal/agentloop/` — Universal loop library
- `internal/agent/` — OODARC workflow built on agentloop

The agentloop package defines:
- `Loop` struct with provider, tools, budget, streaming
- `Loop.Run(ctx, task, opts)` — the Decide→Act core
- Generic `SelectionHints` instead of phase for model routing
- Flat tool registry (no phase gates)
- `RunConfig` with model, system prompt, available tools

OODARC agent wraps Loop:
- Manages phase FSM
- Calls `Loop.Run()` with phase-filtered tools and phase-selected model
- Handles phase transitions between runs

**Pros:** Clean separation, Intercom imports `agentloop` only, no phase concepts leak
**Cons:** Two packages to maintain, some interface duplication, migration effort

### Option B: Make Phase Optional in Existing Package

Keep everything in `internal/agent/` but make phase optional:
- `SelectModel(phase)` → `SelectModel(hints SelectionHints)` where phase is one hint
- Tool registry supports both `Tools(phase)` and `AllTools()`
- `Execute` supports both gated and ungated modes
- `WithPhaseGating(fsm)` option enables OODARC mode

**Pros:** Minimal code movement, backward compatible, incremental migration
**Cons:** Phase is still visible in the API even when unused, harder to enforce separation

### Option C: Interface-Based Abstraction

Define a `Workflow` interface that the agent loop calls for decisions:
```go
type Workflow interface {
    SelectModel(hints SelectionHints) (model, reason string)
    AvailableTools() []ToolDef
    SystemPrompt(budget int) string
    OnTurnComplete(turn Turn)
}
```
OODARC implements this interface. A `SimpleWorkflow` (no phases) also implements it.

**Pros:** Most flexible, workflow is pluggable, single agent package
**Cons:** Another layer of indirection, Workflow interface might grow unbounded

## Recommendation

**Option A (extract `agentloop` sub-package)** is the cleanest long-term choice. It enforces the boundary at the import level — Intercom literally cannot import OODARC concepts because they live in a different package. The migration is straightforward because the current code is already well-interfaced.

Key API changes for the library:

### Router Change
```go
// Before (phase-coupled)
SelectModel(phase tool.Phase) (model, reason string)

// After (hint-based)
type SelectionHints struct {
    Phase    string // optional, empty for non-phased consumers
    Urgency  string // "interactive", "batch", "background"
    TaskType string // "code", "chat", "analysis"
}
SelectModel(hints SelectionHints) (model, reason string)
```

### Tool Registry Change
```go
// Before (phase-gated)
Tools(phase Phase) []ToolDef
Execute(ctx, phase, name, input) ToolResult

// After (flat + optional gating)
type Registry struct { ... }
func (r *Registry) Tools() []ToolDef                           // all registered tools
func (r *Registry) Execute(ctx, name, input) ToolResult        // no phase check
func (r *Registry) WithGates(gates GateMap) *GatedRegistry     // opt-in gating

type GatedRegistry struct { ... }
func (g *GatedRegistry) Tools(phase string) []ToolDef          // filtered
func (g *GatedRegistry) Execute(ctx, phase, name, input) ToolResult // gated
```

### Session Change
```go
// Before
SystemPrompt(phase tool.Phase, budget int) string

// After
SystemPrompt(hints PromptHints) string
type PromptHints struct {
    Phase  string // optional
    Budget int
    Model  string // let session tailor prompt to model capability
}
```

## Migration Path

1. Create `internal/agentloop/` with the core loop, flat registry, hint-based router interface
2. Move Provider, StreamEvent, StreamCallback, ToolApprover, RunResult into agentloop
3. Create `agentloop.Loop` struct with the Decide→Act core from current loop.go
4. Refactor `internal/agent/Agent` to embed/wrap `agentloop.Loop`
5. OODARC agent adapts phase to SelectionHints, filters tools, wraps session
6. Update TUI to work with the new interfaces (minimal — it already uses Agent, not Loop directly)
7. Verify all 295 tests pass (82 TUI + 65 masaq + 148 Skaffen)

## Risk Assessment

- **Medium risk**: The refactoring touches core agent internals but the interfaces are already clean
- **Test safety**: 82 integration tests on the TUI layer + unit tests on each package provide a safety net
- **Intercom dependency**: This unblocks Sylveste-mvy (Intercom Go rewrite) — high leverage
- **Multi-session**: Likely 2-3 sessions to complete fully (extract → migrate → test → clean up)

## Open Questions

1. Should `agentloop` be a separate Go module (publishable) or just an internal package?
   - Start as `internal/agentloop/` — promote to module when Intercom needs it
2. Where does Evidence/Emitter live? It records phase but that's an optional field.
   - Keep in agentloop with phase as `string` (not `tool.Phase`), empty when unused
3. Should the flat Registry be the default and GatedRegistry the wrapper, or vice versa?
   - Flat Registry as default — gating is the OODARC-specific concern
