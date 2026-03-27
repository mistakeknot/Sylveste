---
artifact_type: prd
bead: Sylveste-6qb.8
stage: design
---
# PRD: Separate Agent Loop Library from OODARC Workflow

**Bead:** Sylveste-6qb.8
**Brainstorm:** docs/brainstorms/2026-03-12-skaffen-agent-loop-separation.md
**Decision:** Option A — extract `internal/agentloop/` sub-package

## Problem

Skaffen's agent loop is coupled to the OODARC 5-phase workflow. Every consumer (Intercom chat daemon, Autarch web UI) must adopt the phased workflow even if they just need a basic Decide→Act loop. This blocks the Intercom Go rewrite (Sylveste-mvy) because Intercom shouldn't force chat messages through Brainstorm→Plan→Build→Review→Ship.

## Solution

Split `internal/agent/` into two layers:
1. **`internal/agentloop/`** — Universal agent loop library. Provider abstraction, flat tool registry, hint-based routing, streaming, approval gating, session persistence, evidence emission. No phase concepts.
2. **`internal/agent/`** — OODARC workflow engine. Wraps agentloop with phase FSM, phase-gated tool access, phase-aware routing, and phase transitions.

## Key Interface Changes

### Router: Phase → Hints
```go
// agentloop defines
type SelectionHints struct {
    Phase    string // optional — empty for non-phased consumers
    Urgency  string // "interactive", "batch", "background"
    TaskType string // "code", "chat", "analysis"
}
type Router interface {
    SelectModel(hints SelectionHints) (model, reason string)
    RecordUsage(usage provider.Usage)
    BudgetState() BudgetState
    ContextWindow(model string) int
}
```

### Tool Registry: Flat + Optional Gating
```go
// agentloop defines flat registry
type Registry struct { ... }
func (r *Registry) Register(t Tool)
func (r *Registry) Tools() []ToolDef              // all tools
func (r *Registry) Execute(ctx, name, input) ToolResult  // no phase check

// agent wraps with gating
type GatedRegistry struct {
    inner *agentloop.Registry
    gates map[string]map[string]bool  // phase → {tool → allowed}
}
func (g *GatedRegistry) Tools(phase string) []ToolDef
func (g *GatedRegistry) Execute(ctx, phase, name, input) ToolResult
```

### Session: Phase → Hints
```go
type PromptHints struct {
    Phase  string // optional
    Budget int
    Model  string
}
type Session interface {
    SystemPrompt(hints PromptHints) string
    Save(turn Turn) error
    Messages() []provider.Message
}
```

## Success Criteria

- [ ] `agentloop.Loop.Run(ctx, task)` works with zero phase references
- [ ] `agent.Agent.Run(ctx, task)` preserves identical OODARC behavior (all 295 tests pass)
- [ ] Intercom can import `internal/agentloop` without importing `internal/agent`
- [ ] No regressions: 81 TUI tests + 65 masaq tests + 149 other Skaffen tests all pass

## Non-Goals

- Changing the OODARC phase order or adding new phases
- Publishing agentloop as a separate Go module (internal package for now)
- Modifying the TUI layer (it talks to Agent, not Loop)
- Changing provider implementations (Anthropic, Claude Code)

## Risks

- **Medium**: Refactoring core internals, but clean interfaces and 295 tests provide safety
- **Low**: TUI layer is unaffected (talks to Agent which wraps Loop)
- **Blocked if**: Evidence struct changes break evidence pipeline consumers
