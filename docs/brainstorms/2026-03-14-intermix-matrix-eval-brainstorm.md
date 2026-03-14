---
artifact_type: brainstorm
bead: Demarch-ome7
stage: discover
---
# intermix: Cross-Repo Matrix Evaluation Harness

## What We're Building

A new Interverse plugin (`interverse/intermix/`) that runs Skaffen against unfamiliar codebases across a matrix of (repo, task) pairs, classifies outcomes using a hybrid taxonomy, and produces structured reports showing where Skaffen fails and why.

**Not an optimization loop** — interlab optimizes a single metric via hill-climbing. intermix evaluates capability breadth across a 2D space (repos x tasks) with qualitative failure classification. Different problem, sibling architecture.

**Two components:**
1. **intermix** (`interverse/intermix/`) — Go MCP server providing 4 stateless tools (`init_matrix`, `run_cell`, `classify_result`, `report_matrix`) with JSONL persistence, ic events bridge, and subprocess-based Skaffen execution
2. **Clavain `/evaluate` skill** — Loop protocol for running the matrix: iterate cells, capture results, classify, generate report, create beads for failure patterns

## Why This Approach

### Sibling plugin, not extension of interlab

interlab and intermix share architectural DNA (stateless tools, JSONL state reconstruction, ic events, Go MCP server) but serve fundamentally different purposes:

| Concern | interlab | intermix |
|---------|----------|----------|
| Goal | Optimize a metric | Evaluate capability breadth |
| Loop | Single metric hill-climbing | Matrix of (repo, task) cells |
| Output | "Did the number improve?" | "Where does it fail and why?" |
| Decision | keep/discard/crash | success/partial/failure + classification |
| Git model | Experiment branch with commits | Throwaway clones per cell |

Extending interlab would conflate two concerns and muddy both interfaces. A new plugin with shared patterns is cleaner.

### Subprocess spawn for execution

intermix shells out to `skaffen --mode print --prompt "<task>" --timeout <N>s` in a cloned repo directory. This is:
- **Isolated** — each cell gets a fresh clone in `/tmp/intermix/<cell-id>/`
- **Observable** — stdout/stderr/exit code/timing captured
- **Realistic** — mirrors how a user would actually use Skaffen
- **Simple** — no complex agent coordination or TUI instrumentation

### YAML manifest for matrix definition

A single `intermix.yaml` defines repos (URLs, setup commands, language, complexity) and tasks (prompts, validation commands, difficulty, tags). Version-controllable, shareable, repeatable.

### Test-based validation

Each task includes a validation command. If the command passes (exit code 0) after Skaffen runs, the task is a success. Mirrors SWE-bench's approach. Supports both simple (`go test ./...`) and custom (`python3 check.py`) validators.

### Hybrid failure taxonomy

Fixed categories for aggregation + LLM-generated analysis for nuance:

**Fixed outcome categories:**
- `success` — Task completed correctly (validation passes)
- `partial` — Some progress, incomplete (validation fails but meaningful changes made)
- `wrong_approach` — Ran but did the wrong thing
- `context_limit` — Hit token/context limits
- `tool_failure` — Tool call failed/errored
- `no_progress` — Spun without making changes
- `crash` — Process died unexpectedly
- `timeout` — Exceeded time limit
- `setup_failure` — Couldn't clone/build/setup repo

**Severity:** `critical | degraded | acceptable`

**LLM analysis field:** After the fixed classification, a haiku subagent reads the cell output and writes a free-text analysis (root cause, what went wrong, suggested fix). Stored alongside the structured category.

## Key Decisions

### 1. Name: intermix

Evokes "mix of repos and tasks" — a test matrix that intermixes different codebases with different challenge types.

### 2. Four-tool interface

| Tool | Purpose |
|------|---------|
| `init_matrix` | Read `intermix.yaml`, validate repos/tasks, write config to JSONL, create campaign |
| `run_cell` | Clone repo, run setup, spawn Skaffen, capture output, run validation |
| `classify_result` | Apply fixed taxonomy + LLM analysis, write result to JSONL |
| `report_matrix` | Generate pass/fail heatmap, failure distribution, comparison across runs |

### 3. Subprocess execution model

```
run_cell(repo="chi", task="add-test"):
  1. git clone --depth=1 <repo_url> /tmp/intermix/<cell-id>/
  2. cd /tmp/intermix/<cell-id>/
  3. Run setup command (go mod download, npm install, etc.)
  4. skaffen --mode print --prompt "<task_prompt>" --timeout 300s
  5. Capture: exit_code, duration_ms, stdout, stderr, files_changed
  6. Run validation command
  7. Return structured CellResult
```

### 4. JSONL format mirrors interlab's segment model

```jsonl
{"type":"config","name":"skaffen-v1-stress","repos":[...],"tasks":[...],"timestamp":"..."}
{"type":"cell_result","repo":"chi","task":"add-test","outcome":"success","severity":"acceptable","duration_ms":45000,"validation_passed":true,"files_changed":3,"llm_analysis":"...","timestamp":"..."}
{"type":"cell_result","repo":"chi","task":"refactor-handler","outcome":"context_limit","severity":"critical","duration_ms":300000,"validation_passed":false,"files_changed":0,"llm_analysis":"Skaffen exhausted context trying to understand chi's middleware chain...","timestamp":"..."}
```

### 5. Comparison across Skaffen versions

Each campaign is a segment in the JSONL. `report_matrix` can compare segments — showing which cells improved/regressed between Skaffen versions. This is the reusable harness value.

### 6. Circuit breakers (from interlab)

- Max cells per campaign (default: 100)
- Max consecutive failures (default: 5) — stop if everything is broken
- Per-cell timeout (default: 300s, configurable per task)
- Max total duration (default: 4h)

## Prior Art Considered

- **interlab** (Demarch) — inspire architecture, not extend. Different problem shape.
- **SWE-bench** — gold standard for agent eval, but heavyweight (Docker, full repo history, Python-only initially). intermix is lighter: YAML manifest, subprocess spawn, any language.
- **FeatureBench** — execution-based eval with test-driven tasks. Closest to our approach.
- **HAL Harness** — three-axis eval (model x benchmark x scaffold). intermix is two-axis (repo x task) but could grow.
- **Terminal-Bench** — multi-step workflow eval in sandboxed CLI. Relevant for Skaffen's print mode.
- **DPAI Arena** — broad lifecycle eval. Too heavyweight for our needs.

Verdict: No existing tool fits. SWE-bench is closest but requires too much infrastructure for an internal eval harness. Build our own, inspired by the patterns.

## Resolved: Repo Selection Strategy

**Approach:** Diverse archetypes + complexity gradient + language diversity (priority: TypeScript, Go, Python, Rust).

### Starter Matrix: 12 Repos

**Go (primary — Skaffen's strongest):**

| ID | Archetype | Size | Repo |
|----|-----------|------|------|
| chi | web-framework | small | go-chi/chi |
| cobra | cli-framework | medium | spf13/cobra |
| zap | logging-lib | medium | uber-go/zap |
| viper | config-lib | medium | spf13/viper |

**TypeScript (priority):**

| ID | Archetype | Size | Repo |
|----|-----------|------|------|
| zod | validation-lib | small | colinhacks/zod |
| fastify | web-framework | large | fastify/fastify |
| commander | cli-framework | small | tj/commander.js |

**Python (priority):**

| ID | Archetype | Size | Repo |
|----|-----------|------|------|
| click | cli-framework | medium | pallets/click |
| httpx | http-client | medium | encode/httpx |
| pydantic | validation-lib | large | pydantic/pydantic |

**Rust (priority):**

| ID | Archetype | Size | Repo |
|----|-----------|------|------|
| clap | cli-framework | medium | clap-rs/clap |
| axum | web-framework | medium | tokio-rs/axum |

**Why these 12:** Each covers a different archetype. Within CLI frameworks (cobra, commander, click, clap) we get a complexity gradient across 4 languages from the same problem shape. Popular repos with strong test suites give us free validation oracles.

## Resolved: Task Design

**Approach:** Hybrid — 3 generic templates (applied to all repos) + 2 repo-specific tasks per repo.

### Generic Task Templates (baseline)

Applied to every repo in the matrix. The skill auto-generates concrete prompts by scanning the codebase for targets.

**1. ADD-TEST (easy)**
```
Find a function in this repo that lacks test coverage and write a unit test for it.
```
Validation: language-appropriate test runner passes (`go test`, `npm test`, `pytest`, `cargo test`)

**2. REFACTOR-EXTRACT (medium)**
```
Extract <function/method> into its own file/module with proper imports.
All existing tests must still pass.
```
Validation: test runner passes + new file exists

**3. ADD-FEATURE (hard)**
```
Add <small feature> to <module> with tests.
The feature should [specific behavior].
```
Validation: new tests pass + existing tests pass

### Repo-Specific Tasks (depth, 2 per repo)

Hand-crafted per repo based on actual issues, code patterns, and known challenges. Examples:

- **chi:** Add middleware that logs request duration; Fix a routing edge case with trailing slashes
- **cobra:** Add a new subcommand with flag validation; Refactor help text generation
- **zod:** Add a custom validator type; Fix error message formatting for nested schemas
- **click:** Add a progress bar to a CLI command; Fix parameter validation for file paths

These are designed during `init_matrix` by the skill scanning each repo and selecting interesting targets.

### Matrix Size

12 repos × 5 tasks (3 generic + 2 specific) = **60 cells**. At ~5 min average per cell = ~5 hours for a full campaign. Suitable for overnight/background execution.

## Resolved: Failure-to-Bead Pipeline

**Approach:** report_matrix auto-creates beads from failure pattern clusters. Delta reports with bead resolution on repeat campaigns.

### Bead Creation (after campaign)

1. Group `cell_result` entries by `(outcome, severity)`
2. Within each group, cluster by LLM analysis similarity (haiku classifies themes)
3. For each cluster with ≥2 cells:
   - `bd create --title="[intermix] <pattern>" --type=bug --priority=<from severity>`
   - Description includes: affected cells, common LLM analysis themes, example outputs
   - Link as child of the parent epic (e.g., Demarch-ome7)
4. Report includes: `"● 3 beads created from 4 failure patterns"`

### Regression Detection (repeat campaigns)

When `report_matrix` finds a previous campaign segment in the JSONL:

1. Load previous campaign results
2. For each cell, compare outcome:
   - `was_fail → now_pass` = **FIXED**
   - `was_pass → now_fail` = **REGRESSED**
   - same = **STABLE**
3. Map to bead lifecycle:
   - FIXED cells → auto-close linked bead with reason `"Resolved in campaign <name>"`
   - REGRESSED cells → reopen bead, escalate priority by 1
   - New failures → cluster → create new beads
4. Report summary:
   ```
   ✔ 2 patterns fixed (beads closed)
   ✖ 1 regression (bead reopened)
   ○ 1 new pattern (bead created)
   ```

### The Flywheel

```
intermix campaign → failure patterns → beads created
     ↑                                      ↓
  next campaign ← Skaffen fixes ← developer works bead
     ↓
  delta report → beads closed (fixed) / reopened (regressed)
```

This makes intermix a **continuous improvement engine** — each run feeds the next, failures compound into actionable work, fixes are automatically verified.

## Resolved: Parallel Execution & Cost

**Decision: Sequential by default, no concurrency in v1.**

Rationale:
- **Eval data correctness > speed.** A false `tool_failure` from a 429 rate limit looks like a Skaffen bug. Sequential execution eliminates API pressure as a confounding variable.
- **5 hours for 60 cells is fine.** This runs overnight/background, not interactively. Nobody watches it.
- **Simplicity wins in v1.** No goroutine management, no rate limit backoff, no partial failure handling, no result ordering. JSONL is append-in-order, trivially debuggable.
- **Smarter speedup: `--filter=failed`.** Re-running only the 8 failed cells after a fix is a bigger win than parallelizing all 60. Add this to `run_cell` before adding concurrency.

Future: if campaigns grow beyond 100 cells or turnaround time matters, add `--concurrency=N` with token-bucket rate limiting. Not v1.

**Decision: Self-contained cost tracking in JSONL.**

Each `cell_result` includes `tokens_used` (parsed from Skaffen's output if available, estimated from duration otherwise). `report_matrix` sums per-cell, per-repo, per-task, and per-campaign totals. No interstat dependency — keeps intermix standalone. interstat can read the JSONL later if cross-tool cost analysis is needed.

## Resolved: Task Generation

**Decision: Auto-scan for generic template targets, hand-curate repo-specific tasks.**

Generic templates (ADD-TEST, REFACTOR-EXTRACT, ADD-FEATURE) use `target: auto` in the YAML. During `init_matrix`, the skill scans each repo to pick concrete targets:
- ADD-TEST: find functions without test coverage (e.g., no matching `_test.go` / `test_*.py` / `*.test.ts`)
- REFACTOR-EXTRACT: find large functions (>50 lines) that could be split
- ADD-FEATURE: find modules with clear extension points (interfaces, plugin registries)

Auto-scanning is reliable for test targets (low risk of trivial/impossible). Refactor and feature targets are best-effort — if the scan finds nothing suitable, skip that cell and log `skipped` in the JSONL.

Repo-specific tasks are hand-curated in `intermix.yaml` with explicit prompts and validation commands. 24 tasks (2 × 12 repos) is a one-time investment. These are the high-value tasks that test interesting code patterns specific to each repo.

## Resolved: Skaffen Configuration

**Decision: Per-repo overrides in YAML, not a full third axis.**

The primary evaluation matrix is 2D: (repo × task). Adding a third axis (Skaffen config) triples the matrix to 180+ cells — too expensive for v1, and the question "does Skaffen work on unfamiliar repos?" is independent of which model it uses.

`intermix.yaml` supports optional `skaffen_config` per repo for practical overrides:
```yaml
repos:
  - id: pydantic
    url: github.com/pydantic/pydantic
    skaffen_config:
      timeout: 600s    # large repo needs more time
```

Future: to test "Skaffen with Haiku vs. Opus," add a `configs:` section to the YAML and let `report_matrix` compare campaigns run with different configs. Not v1.

## Open Questions (for planning)

None — all design questions resolved. Ready for `/clavain:write-plan`.
