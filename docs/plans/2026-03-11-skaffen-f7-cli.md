---
artifact_type: plan
bead: Sylveste-c4c
stage: design
prd: docs/prds/2026-03-11-skaffen-go-rewrite.md
requirements:
  - "Print mode: reads prompt from stdin or -p flag, streams response to stdout"
  - "Config flags: --provider, --model, --phase, --max-turns"
  - "Version subcommand with build info"
  - "Clean shutdown: SIGINT/SIGTERM, context cancellation"
  - "Wires F1 (provider) + F2 (tools) + F3 (agent) into a runnable binary"
---
# F7: CLI Entry Point

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-c4c
**Goal:** Make Skaffen a runnable binary. This wires all the infrastructure (F1 provider, F2 tools, F3 agent loop) into `cmd/skaffen/main.go` with print mode and basic configuration.

**Architecture:** `cmd/skaffen/main.go` uses stdlib `flag` for argument parsing (no external CLI framework). Print mode reads a prompt, creates the provider/registry/agent, calls `agent.Run()`, and prints the result. Signal handling via `os/signal` + context cancellation.

**Tech Stack:** Go 1.22 stdlib only. `flag` for args, `os/signal` for shutdown, `context` for cancellation.

**Scope for v0.1:** Print mode only. RPC mode deferred — no consumers yet. TOML config file deferred — flags are sufficient for v0.1.

## Prior Learnings

- Provider factory uses `init()` registration — must blank-import `anthropic` and `claudecode` packages to register them.
- `agent.New()` takes `provider.Provider` + `*tool.Registry` + options — clean wiring.
- Existing `cmd/skaffen/main.go` has version scaffold already working.

---

## Must-Haves

**Truths** (observable behaviors):
- `go build ./cmd/skaffen/` produces a binary
- `skaffen version` prints version + Go version
- `skaffen -p "hello"` sends prompt to Anthropic, prints streamed response
- `ANTHROPIC_API_KEY` missing → clear error message
- `Ctrl-C` during execution → clean shutdown (no hang, no panic)
- `skaffen -provider claude-code -p "hello"` uses Claude Code proxy

**Artifacts** (files that must exist):
- `cmd/skaffen/main.go` — entry point, flag parsing, wiring
- `cmd/skaffen/main_test.go` — flag parsing and version tests

---

### Task 1 ✅: Flag parsing and subcommand routing

**Files:**
- `cmd/skaffen/main.go` (rewrite existing scaffold)

**Changes:**

Replace the existing scaffold with proper flag parsing:

```go
var (
    flagProvider = flag.String("provider", "anthropic", "LLM provider (anthropic, claude-code)")
    flagModel    = flag.String("model", "", "Model override")
    flagPhase    = flag.String("phase", "build", "OODARC phase (brainstorm, plan, build, review, ship)")
    flagPrompt   = flag.String("p", "", "Prompt (reads stdin if empty)")
    flagMaxTurns = flag.Int("max-turns", 100, "Maximum agent loop turns")
    flagSystem   = flag.String("system", "", "System prompt")
)

func main() {
    flag.Parse()

    // Subcommand routing
    if flag.NArg() > 0 {
        switch flag.Arg(0) {
        case "version":
            printVersion()
            return
        }
    }

    if err := run(); err != nil {
        fmt.Fprintf(os.Stderr, "skaffen: %v\n", err)
        os.Exit(1)
    }
}
```

**Exit criteria:** `go build ./cmd/skaffen/` succeeds. `skaffen version` still works.

---

### Task 2 ✅: Signal handling and context setup

**Files:**
- `cmd/skaffen/main.go` (extend run function)

**Changes:**

```go
func run() error {
    // Context with signal handling
    ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    defer cancel()

    // ... rest of run()
}
```

**Exit criteria:** Compiles. SIGINT cancels the context.

---

### Task 3 ✅: Provider initialization

**Files:**
- `cmd/skaffen/main.go` (extend run function)

**Changes:**

```go
import (
    _ "github.com/mistakeknot/Skaffen/internal/provider/anthropic"
    _ "github.com/mistakeknot/Skaffen/internal/provider/claudecode"
)

// In run():
cfg := provider.ProviderConfig{
    Model: *flagModel,
}
if *flagProvider == "anthropic" {
    cfg.APIKey = os.Getenv("ANTHROPIC_API_KEY")
    if cfg.APIKey == "" {
        return fmt.Errorf("ANTHROPIC_API_KEY not set (use --provider claude-code for Claude Max)")
    }
}

p, err := provider.New(*flagProvider, cfg)
if err != nil {
    return fmt.Errorf("provider: %w", err)
}
```

**Exit criteria:** Missing API key → clear error. Unknown provider → clear error.

---

### Task 4 ✅: Tool registry and agent wiring

**Files:**
- `cmd/skaffen/main.go` (extend run function)

**Changes:**

```go
// In run():
reg := tool.NewRegistry()
tool.RegisterBuiltins(reg)

phase := tool.Phase(*flagPhase)
opts := []agent.Option{
    agent.WithMaxTurns(*flagMaxTurns),
    agent.WithStartPhase(phase),
}
if *flagSystem != "" {
    opts = append(opts, agent.WithSession(&agent.NoOpSession{Prompt: *flagSystem}))
}

a := agent.New(p, reg, opts...)
```

**Exit criteria:** Compiles. Agent created with correct options.

---

### Task 5 ✅: Prompt reading (flag or stdin)

**Files:**
- `cmd/skaffen/main.go` (extend run function)

**Changes:**

```go
// In run():
prompt := *flagPrompt
if prompt == "" {
    // Read from stdin
    data, err := io.ReadAll(os.Stdin)
    if err != nil {
        return fmt.Errorf("reading stdin: %w", err)
    }
    prompt = strings.TrimSpace(string(data))
}
if prompt == "" {
    return fmt.Errorf("no prompt provided (use -p or pipe to stdin)")
}
```

**Exit criteria:** `-p "hello"` works. Piped stdin works. Empty prompt → clear error.

---

### Task 6 ✅: Run agent and print result

**Files:**
- `cmd/skaffen/main.go` (complete run function)

**Changes:**

```go
// In run():
result, err := a.Run(ctx, prompt)
if err != nil {
    return err
}

fmt.Print(result.Response)

// Print usage to stderr
fmt.Fprintf(os.Stderr, "\n[%d turns, %d in / %d out tokens]\n",
    result.Turns, result.Usage.InputTokens, result.Usage.OutputTokens)

return nil
```

**Exit criteria:** `go build ./cmd/skaffen/` succeeds. Binary runs end-to-end with mock (tested in Task 7).

---

### Task 7 ✅: Tests

**Files:**
- `cmd/skaffen/main_test.go` (new)

**Changes:**

Test flag parsing and version output. We can't easily test the full run() without an API key, but we can test:

1. **Version output** — captures stdout, verifies format
2. **Phase validation** — invalid phase string handling
3. **Empty prompt detection** — no -p and no stdin → error

**Exit criteria:** `go test ./cmd/skaffen/ -v` passes.

---

### Task 8 ✅: Verify clean build

**Files:** none new

**Changes:**
- `go mod tidy`
- `go vet ./...`
- `go test ./...`
- `go build -o /tmp/skaffen ./cmd/skaffen/`
- Verify binary runs: `/tmp/skaffen version`

**Exit criteria:** Binary built and version works. All 47+ tests pass.
