# Skaffen Cross-Repo Stress Test — First Campaign Results

**Date:** 2026-03-14
**Bead:** Sylveste-ome7 (epic), Sylveste-vmen (F6)
**Infrastructure:** intermix parallel batch runner (tmux + MCP tools)

## Campaign Configuration

- **Matrix:** 3 repos × 3 tasks = 9 cells (quarter-matrix)
- **Repos:** chi (Go), zod (TypeScript), click (Python)
- **Tasks:** add-test (easy), refactor-extract (medium), add-feature (hard)
- **Agent:** Skaffen v0.1.0 (`skaffen -mode print -p`) → claudecode provider → `claude --print`
- **Timeout:** 600s per cell
- **Model:** Claude (via Claude Max subscription)

## Heatmap

```
       add-feature  add-test  refactor-extract
chi    PART         PART      PART
click  PART         PART      PART
zod    PASS         PASS      PASS

Legend: PASS=success PART=partial TOUT=timeout FAIL=crash
```

## Summary

| Metric | Value |
|--------|-------|
| Total cells | 9 |
| Success | 3 (33.3%) |
| Partial | 6 (66.7%) |
| Timeout/crash | 0 |

## By Repository

| Repo | Language | Pass Rate | Notes |
|------|----------|-----------|-------|
| zod | TypeScript | 3/3 (100%) | Clean sweep. pnpm setup worked. Validation (vitest) passed. |
| chi | Go | 0/3 (0%) | All partial. Validation failed: `GOTOOLCHAIN` not set in validation env. |
| click | Python | 0/3 (0%) | All partial. Validation failed: pytest couldn't import click (venv not activated). |

## By Task

| Task | Difficulty | Pass Rate |
|------|-----------|-----------|
| add-test | easy | 1/3 |
| refactor-extract | medium | 1/3 |
| add-feature | hard | 1/3 |

All tasks had identical pass rates — the failures were environmental, not task-difficulty related.

## Failure Analysis

### Pattern: Environment isolation (6/6 failures)

All chi and click failures share the same root cause: **the validation command runs in a different environment than the setup/skaffen execution**.

- **Chi (Go):** Setup uses `export GOTOOLCHAIN=go1.23.0+auto && go mod download`, which downloads Go 1.23. But the validation command (`go test ./...`) runs in a fresh shell without `GOTOOLCHAIN`, so it fails with "toolchain not available".
- **Click (Python):** Setup uses `uv venv .venv && uv pip install -e .`, which creates a virtualenv. But Skaffen's `claude -p` and the validation command (`pytest`) don't activate the venv, so imports fail.

### What worked

Despite validation failures, **all 9 cells produced code changes**:
- chi cells: 1 file changed each
- click cells: 3 files changed each
- zod cells: 1 file changed each

The AI code generation worked across all languages. Skaffen successfully:
1. Read and understood unfamiliar codebases
2. Identified targets (untested functions, long functions, feature gaps)
3. Wrote code changes
4. (For zod) Verified changes pass tests

### Token Usage

Sampled from pane captures:
- zod-refactor-extract: 37 in / 9,186 out tokens (1 turn)
- zod-add-feature: 32 in / 9,892 out tokens (1 turn)
- Average ~10K output tokens per cell

## Infrastructure Bugs Found & Fixed

### Bug 1: tmux send-keys concatenation
`tmux send-keys` joins arguments without spaces. `skaffen --mode print --prompt text` was sent as `skaffen--modeprint--prompttext`.
**Fix:** Pass entire command as single string argument.

### Bug 2: Skaffen flag names
Plan used `--prompt` but Skaffen uses `-p` (Go `flag` package uses single-dash).
**Fix:** Updated `BuildSkaffenCommand` to use `-mode` and `-p`.

### Bug 3: Shell word splitting of prompt
Even with single-string send-keys, multi-word `-p` argument was split by the shell.
**Fix:** Added `BuildSkaffenShellCommand()` that single-quotes the prompt with proper escaping.

### Bug 4: GOTOOLCHAIN not auto-downloading
`GOTOOLCHAIN=auto` on Go 1.22 doesn't auto-download newer toolchains. Need explicit `GOTOOLCHAIN=go1.23.0+auto`.
**Fix:** Updated manifest setup commands.

## Recommendations

### P1: Fix validation environment
The validation runner (`RunValidation`) needs to inherit the setup environment. Options:
1. Run validation inside the same tmux session (shares env)
2. Write env vars to a `.env` file during setup, source it before validation
3. Use `bash -c 'source .venv/bin/activate && pytest'` for Python repos

### P2: Add setup validation step
Add a pre-flight check between setup and skaffen spawn that verifies the language runtime is accessible (e.g., `go version`, `python3 -c 'import click'`).

### P3: Increase default timeout
All cells hit 600s. While skaffen completed faster, the tmux session stayed open. Consider: detect skaffen exit from pane output (look for the token usage line) rather than waiting for session exit.

## Raw Data

- Campaign dir: `/tmp/intermix-campaign-20260314/`
- Per-cell JSONL: `cells/*.jsonl`
- Run details: `cells/*.run.json`
- Evidence: `evidence/` (if harvested)
