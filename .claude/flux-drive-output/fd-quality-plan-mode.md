# Quality Review: Plan Mode for Skaffen

Reviewed against the actual source in `os/Skaffen/internal/agent/` and the OODARC architecture described in `os/Skaffen/AGENTS.md`. Languages in scope: Go only.

---

## Finding 1 — Naming: `PlanModeGates` should stay exported, but the name is wrong

**Severity: moderate**

`DefaultGates` in `agent/gated_registry.go` is exported and named for what it is (the default gate matrix). A parallel variable for plan-mode gates should follow the same pattern.

`PlanModeGates` is acceptable by the 5-second rule (a reader immediately knows "the gates when plan mode is on"), but look at what it actually is: it is a subset of `DefaultGates` where write-capable tools are removed across all phases. A more precise name is `ReadOnlyGates`, because plan mode's defining invariant is that no write tools are admitted regardless of phase. This name also survives if a future mode (e.g. "audit mode") reuses the same constraint for a different purpose.

```go
// ReadOnlyGates defines the phase gate matrix used when plan mode is active.
// All phases are restricted to read-only tools; write, edit, and bash are excluded.
var ReadOnlyGates = map[string]map[string]bool{ ... }
```

If the plan insists on `PlanModeGates`, it must be exported (consistent with `DefaultGates`). Making it unexported would be inconsistent: callers constructing a `GatedRegistry` for plan mode via `NewGatedRegistry(inner, agent.PlanModeGates)` need the value to be accessible.

---

## Finding 2 — Error message coupling: UI copy in a library package

**Severity: real**

The proposed rejection message:

```
"plan mode is active — %s is read-only. Toggle with Shift+Tab or --plan-mode flag"
```

contains two UI-layer concerns:

1. **Keyboard binding** (`Shift+Tab`) — The `internal/agent` package has no awareness of the TUI. The `tui` package imports `agent`; the dependency must not run the other way. If the Shift+Tab binding changes, the library message will silently go stale. The `tui/app.go` layer should inject the hint string, not bake it into `GatedRegistry.Execute`.

2. **CLI flag name** (`--plan-mode`) — This couples the library to a specific CLI surface. `cmd/skaffen/main.go` is the right owner of flag names.

The existing rejection message in `GatedRegistry.Execute` is:

```go
fmt.Sprintf("tool %q not available in phase %q", name, phase)
```

The equivalent for plan mode should stay at the same abstraction level:

```go
fmt.Sprintf("tool %q is not available in plan mode (read-only)", name)
```

The TUI layer owns translating this into a user-facing message with keybinding hints. A clean seam: the `agent` package returns a structured `ToolResult` with `IsError: true`; the TUI can pattern-match on the content or (better) on a new sentinel — see Finding 4.

---

## Finding 3 — Interface pollution: `SetPlanMode()` on both `Agent` and `GatedRegistry`

**Severity: moderate**

The plan proposes adding `SetPlanMode(bool)` to both `Agent` and `GatedRegistry`. Examine the actual call path:

```
Agent.Run()
  → buildLoopRegistry(phase)      // reads agent.registry (tool.Registry)
  → agentloop.Loop.Run()
      → loop.reg.Execute(...)     // uses the flat agentloop.Registry built above
```

`Agent` holds a `*tool.Registry`, not a `*GatedRegistry`. The gating today happens at `buildLoopRegistry` time: `Agent.Run` calls `a.registry.Tools(phase)` which applies `tool.Registry`'s own gate matrix. `GatedRegistry` (in `agent/gated_registry.go`) is a separate, unused-by-`Agent` wrapper around `agentloop.Registry`.

Adding `SetPlanMode` to `GatedRegistry` is safe — it has no interface and is a concrete type used only in tests. But adding it to `Agent` is the design question.

The existing pattern in `Agent` for runtime mutation is the functional option pattern with post-construction setters:

```go
func (a *Agent) SetStreamCallback(cb StreamCallback)
func (a *Agent) SetToolApprover(fn ToolApprover)
func (a *Agent) SetModelOverride(model string) bool
```

`SetPlanMode(bool)` fits this pattern directly on `Agent` — it is not an interface method, just a setter on a concrete struct. No interface is widened. This is fine.

What to avoid: do not add `SetPlanMode` to the `Router`, `Session`, or `Emitter` interfaces. Those are small, coherent interfaces. Plan mode is an execution constraint, not a routing or session concern.

The question of whether to add `SetPlanMode` to `GatedRegistry` separately is whether anything outside `Agent` needs to toggle it. If `GatedRegistry` is only used in tests (which is what `gated_registry_test.go` suggests), then a setter there is low risk but also low value. Consider whether `Agent.SetPlanMode` can simply swap the gate matrix used at `buildLoopRegistry` time rather than delegating to `GatedRegistry`.

A concrete, non-interface-polluting implementation:

```go
// In agent.go, add one field:
type Agent struct {
    // ...existing fields...
    planMode bool
}

func (a *Agent) SetPlanMode(enabled bool) {
    a.planMode = enabled
}

// In buildLoopRegistry, select the gate map:
func (a *Agent) buildLoopRegistry(phase tool.Phase) *agentloop.Registry {
    defs := a.registry.Tools(phase)
    if a.planMode {
        // filter defs down to read-only names
    }
    // ...
}
```

This keeps `GatedRegistry` out of the plan-mode logic entirely, unless it genuinely needs to be used as a standalone gating layer.

---

## Finding 4 — Test approach: the verify commands are insufficient

**Severity: real**

The existing test suite uses two patterns:

- `gated_registry_test.go`: direct unit tests on `GatedRegistry` with stub tools
- `agent_test.go`: mock-provider integration tests that exercise the full `Agent.Run` loop

The plan mode verify commands (implied to be `go test ./...`) will only validate what is explicitly tested. Three gaps:

**Gap A: No test for `Agent.SetPlanMode` end-to-end.**

`TestPhaseGateRejection` (line 168 in `agent_test.go`) already shows the right shape — a mock provider that requests a disallowed tool, and an assertion that the loop recovers. A plan-mode test should mirror this: start the agent in build phase (where `write` is normally allowed), enable plan mode, verify the model receives a tool rejection for `write`, and verify the loop completes rather than erroring.

**Gap B: No test verifying `--plan-mode` flag wires through to `Agent.SetPlanMode`.**

The CLI flag surface (`cmd/skaffen/main.go`) is not covered by existing tests in `internal/`. Since `cmd/skaffen/` is a binary, this gap is acknowledged in the project (no integration tests requiring external services). The plan should call out that CLI flag wiring is manually verified, not tested.

**Gap C: No test for `ReadOnlyGates` (or `PlanModeGates`) gate matrix completeness.**

The existing `TestGatedToolsBrainstormExcludesWrite` style is the right pattern. A parallel table test should verify that every phase in `ReadOnlyGates` excludes `write`, `edit`, and `bash`. Without this, someone can accidentally re-admit a write tool in one phase without any test failure.

Suggested test structure:

```go
func TestReadOnlyGatesExcludeWriteTools(t *testing.T) {
    writeTools := []string{"write", "edit", "bash"}
    for phase, allowed := range ReadOnlyGates {
        for _, name := range writeTools {
            if allowed[name] {
                t.Errorf("ReadOnlyGates[%q] must not include %q", phase, name)
            }
        }
    }
}
```

---

## Finding 5 — `DefaultGates` duplication: two gate matrices for the same concept

**Severity: low / design note**

`tool/registry.go` has `defaultGates` (unexported, `map[Phase][]string`) and `agent/gated_registry.go` has `DefaultGates` (exported, `map[string]map[string]bool`). They encode the same policy with slightly different shapes. Adding a third matrix (`PlanModeGates` / `ReadOnlyGates`) in `agent/gated_registry.go` deepens this duplication.

This is not a blocker for the plan, but the implementation should decide: is `agent.DefaultGates` the canonical source of truth, or is `tool.defaultGates`? Right now `Agent.Run` → `buildLoopRegistry` calls `a.registry.Tools(phase)` which uses `tool.defaultGates` — so `agent.DefaultGates` is actually only used by `GatedRegistry` in tests, making it an orphan for the real execution path.

If plan mode gating is implemented by filtering inside `buildLoopRegistry` (as suggested in Finding 3), then `agent.DefaultGates` and any new `ReadOnlyGates` should also be removed to avoid dead code. If they must stay for testing `GatedRegistry` in isolation, the comment should say so explicitly.

---

## Summary Table

| # | Area | Finding | Severity |
|---|------|---------|----------|
| 1 | Naming | `PlanModeGates` → `ReadOnlyGates` (more precise invariant) | Moderate |
| 2 | Error messages | Remove UI keybinding + CLI flag name from `internal/agent` rejection string | Real |
| 3 | Interface design | `SetPlanMode` on `Agent` struct is fine; avoid adding it to `GatedRegistry` unless `GatedRegistry` is actually in the `Agent` execution path | Moderate |
| 4 | Tests | Add: (A) `Agent.SetPlanMode` end-to-end test, (B) `ReadOnlyGates` completeness table test | Real |
| 5 | Duplication | `agent.DefaultGates` is not used by `Agent.Run` — resolve or document before adding a sibling variable | Low |

---

## Files Reviewed

- `/home/mk/projects/Sylveste/os/Skaffen/internal/agent/gated_registry.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/agent/agent.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/agent/deps.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/agent/phase.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/agent/loop.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/agent/gated_registry_test.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/agent/agent_test.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/tool/registry.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/tui/settings.go`
- `/home/mk/projects/Sylveste/os/Skaffen/AGENTS.md`
- `/home/mk/projects/Sylveste/os/Skaffen/CLAUDE.md`
