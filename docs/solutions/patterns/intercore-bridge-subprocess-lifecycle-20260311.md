---
artifact_type: reflection
bead: Sylveste-j2f
stage: reflect
category: pattern
tags: [subprocess, goroutine, os-exec, fire-and-forget, intercore]
---

# Intercore Bridge: Subprocess Lifecycle in Fire-and-Forget Patterns

## Context

Skaffen v0.3 connects to Intercore via `ic` CLI subprocesses for evidence emission, routing decision recording, and override queries. The initial implementation used `go cmd.Run()` (bare goroutine, no timeout, no context) for fire-and-forget recording. Quality gates caught this as a P0 zombie leak risk.

## Pattern: Bounded Fire-and-Forget Subprocess

When spawning fire-and-forget subprocesses from a hot loop (e.g., per-turn agent loop), always bound the subprocess lifetime:

```go
// BAD: unbounded goroutine + subprocess
go cmd.Run()

// GOOD: context-bounded, self-cleaning
go func() {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    exec.CommandContext(ctx, binary, args...).Run()
}()
```

**Why 5s timeout:** `ic route record` is a local SQLite write (~5ms typical). 5s is 1000x headroom. On shutdown, worst case is 5s delay, not zombie accumulation.

**Why not WaitGroup:** Recording is truly best-effort. Blocking shutdown to wait for recording completion would delay ctrl+c responsiveness. The timeout makes WaitGroup unnecessary — goroutines self-terminate.

## Pattern: Graceful Degradation for Optional Dependencies

The initial design made `ic` mandatory (hard exit on startup if missing). Quality gates flagged this as breaking CI/containers. The fix:

```go
// BAD: hard gate on optional dependency
ic, err := checkIntercore()
if err != nil { return err }

// GOOD: warn and degrade
func checkIntercore() *router.ICClient {
    ic, err := router.NewICClient()
    if err != nil {
        fmt.Fprintf(os.Stderr, "warning: intercore unavailable\n")
        return nil
    }
    // ...
    return ic
}
```

**Key insight:** The `NewWithIC(cfg, nil, sessionID)` path was already tested (`TestNewWithIC_NilIC`). The graceful degradation path existed in the code — we just weren't using it. The brainstorm decided "mandatory ic" to simplify conditionals, but quality gates correctly identified that simplifying the hot path shouldn't break the cold path (startup in environments without ic).

## Pattern: Release Mutex Before Best-Effort I/O

```go
// BAD: blocking I/O under lock
func (e *Emitter) Emit(ev Evidence) error {
    e.mu.Lock()
    defer e.mu.Unlock()
    e.appendJSONL(ev)      // fast local write
    e.bridgeToIntercore(ev) // slow subprocess — blocks all concurrent Emit()
}

// GOOD: release lock before best-effort I/O
func (e *Emitter) Emit(ev Evidence) error {
    e.mu.Lock()
    err := e.appendJSONL(ev)
    e.mu.Unlock()
    if err != nil { return err }
    e.bridgeToIntercore(ev) // no lock held
}
```

**Rule:** Only hold the mutex for the operation that requires serialization (JSONL append). Best-effort bridge calls don't need serialization and shouldn't block the critical path.

## Execution Observations

- **4-stage Codex delegation** worked well for this plan shape (3 independent foundation tasks, 2 sequential router tasks, 1 wiring task, 1 verification)
- **Override cache per-session** is acceptable for v0.3 but noted as P3 for long-running TUI sessions
- **Phase string duplication** (literal list vs map keys) was caught by quality gates — always derive from the canonical source
- **Resolution order comment/code mismatch** is a recurring pattern — when code uses last-write-wins, the comment must describe precedence in the same direction as the code reads
