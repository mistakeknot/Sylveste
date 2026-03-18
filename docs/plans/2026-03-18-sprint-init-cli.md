# Plan: clavain-cli sprint-init

**Bead:** Demarch-czxk
**PRD:** docs/prds/2026-03-18-sprint-init-cli.md
**Date:** 2026-03-18

## Context

Sprint bootstrap in `sprint.md` requires 4+ separate Bash tool calls visible in Claude Code's tool-call chrome. We're adding a `clavain-cli sprint-init` subcommand that consolidates these into one call with formatted output.

**Key constraint:** clavain-cli has zero charmbracelet/lipgloss deps. We will NOT add masaq as a dependency. Instead, we'll use ANSI truecolor escapes with Tokyo Night hex values inlined as constants, and `mattn/go-isatty` (already indirect dep) for TTY detection.

## Tasks

### Task 1: Add `sprint-init` subcommand (Go)

**File:** `os/Clavain/cmd/clavain-cli/init.go` (new)

Create `cmdSprintInit(args []string) error` that:

1. Validates bead ID (args[0]) — `bd show <id>` for title
2. Reads complexity — reuses `tryComplexityOverride()` from complexity.go, falls back to "3"
3. Reads phase — `bd state <id> phase`
4. Reads budget — reuses `resolveRunID()` + `readBudgetResult()` from budget.go
5. Reads title from `bd show` output (parse first line)
6. Writes interstat attribution — `echo <bead> > /tmp/interstat-bead-<sid>` + `ic session attribute`
7. Outputs formatted banner to stdout

All queries run in parallel (goroutines + WaitGroup, same pattern as `cmdSprintReadState`).

Output format (TTY, truecolor):
```
── Sprint: Demarch-czxk ─────────────────────────
 Title:      clavain-cli sprint-init: consolidated...
 Complexity: 3/5 (moderate)
 Phase:      planned → execute
 Budget:     42k / 120k (35%)
──────────────────────────────────────────────────
```

NO_COLOR / non-TTY output (plain text, same structure, no ANSI):
```
-- Sprint: Demarch-czxk ---------------------
 Title:      clavain-cli sprint-init...
 Complexity: 3/5 (moderate)
 Phase:      planned
 Budget:     42k / 120k (35%)
---------------------------------------------
```

**Color constants** (Tokyo Night, inlined — no masaq import):
- Border/label: `#7aa2f7` (primary blue)
- Value: `#c0caf5` (foreground)
- Phase/complexity label: `#7dcfff` (info cyan)
- Budget healthy: `#9ece6a` (success green)
- Budget >70%: `#e0af68` (warning amber)
- Budget >90%: `#f7768e` (error red)

**TTY detection:** `isatty.IsTerminal(os.Stdout.Fd())` — already have `mattn/go-isatty` as indirect dep; promote to direct.

### Task 2: Wire into main.go

**File:** `os/Clavain/cmd/clavain-cli/main.go`

Add case `"sprint-init"` → `cmdSprintInit(args)` in the switch, under Sprint CRUD section.
Add to help text under Sprint State section.

### Task 3: Tests

**File:** `os/Clavain/cmd/clavain-cli/init_test.go` (new)

- Test `formatBanner()` (the pure formatting function) with various inputs
- Test color stripping when NO_COLOR=1
- Test graceful degradation (missing bd, missing ic, missing phase state)
- Test budget percentage formatting (0%, 50%, 75%, 95%)

### Task 4: Update sprint.md

**File:** `os/Clavain/commands/sprint.md`

Replace the "Environment Bootstrap" section (lines 24-39) + interstat registration (lines 33-37) + complexity routing (lines 42-53) with:

```markdown
## Environment Bootstrap + Status

```bash
clavain-cli sprint-init "$CLAVAIN_BEAD_ID"
```

This consolidates environment validation, interstat registration, and complexity/budget read into a single call with formatted output.

Read the complexity value from the output to decide routing:
- **1-2:** AskUserQuestion — "Skip to plan" or "Full workflow"
- **3:** Standard workflow
- **4-5:** Full workflow, Opus orchestration
```

### Task 5: Build and install

```bash
cd os/Clavain/cmd/clavain-cli && go build -o ~/.local/bin/clavain-cli .
```

Verify: `clavain-cli sprint-init Demarch-czxk`

## Build Sequence

Task 1 → Task 2 → Task 3 → Task 5 (verify) → Task 4

Task 4 (sprint.md update) comes last so we can verify the CLI works first.

## Risks

- **Budget query requires ic run** — beads without an ic run (manually created, pre-sprint) won't have budget data. Graceful: show "Budget: (no run)" instead.
- **Title parsing from bd show** — format may vary. Use regex, fall back to bead ID.
- **Truecolor support** — some terminals don't support it. ANSI 256-color fallback is fine; NO_COLOR covers the rest.
