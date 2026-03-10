---
artifact_type: plan
bead: Demarch-csq
stage: design
requirements:
  - F1: Maturation Ladder (6 Levels)
  - F2: Conformance Audit Mode
  - F3: Test Updates
---
# Diagnostic Maturation Skill — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-csq
**Goal:** Add a 4th skill to interhelm that guides agents from skeleton diagnostic server to production-grade operator toolkit via a 6-level maturation ladder and conformance audit mode.

**Architecture:** Single SKILL.md file containing structured guidance (no runtime code). Two modes: maturation (step-by-step guide through 6 levels) and audit (evaluate existing server against the ladder). Shadow Work's sw-agent (1,525 lines, 6 files) is the reference implementation — patterns are distilled as guidance, not copy-paste templates.

**Tech Stack:** Markdown (SKILL.md with YAML frontmatter)

**Prior Learnings:** `docs/solutions/patterns/interhelm-plugin-sprint-learnings-20260309.md` — template code needs same review rigor as production code; PostToolUse hook contracts use JSON stdin.

---

## Must-Haves

**Truths** (observable behaviors):
- Agent can invoke `interhelm:diagnostic-maturation` and receive structured guidance for their current level
- Agent can run audit mode and get a report of which levels are implemented and what's missing
- `python3 -c "import json; print(len(json.load(open('.claude-plugin/plugin.json'))['skills']))"` returns `4`
- `cd tests && uv run pytest -q` passes with all structural tests green

**Artifacts** (files that must exist):
- `interverse/interhelm/skills/diagnostic-maturation/SKILL.md` with valid frontmatter (`name`, `description`)
- `interverse/interhelm/.claude-plugin/plugin.json` lists 4 skills

**Key Links:**
- plugin.json `skills` array must reference `./skills/diagnostic-maturation`
- test_skills.py `test_skill_count` must expect 4
- SKILL.md `name` field must match directory name `diagnostic-maturation`

---

### Task 1: Create the Diagnostic Maturation Skill

**Files:**
- Create: `interverse/interhelm/skills/diagnostic-maturation/SKILL.md`

**Step 1: Create the SKILL.md**

Write the full skill file. The skill has two modes (maturation and audit) and covers 6 levels of diagnostic server maturity, distilled from Shadow Work's sw-agent reference implementation.

```markdown
---
name: diagnostic-maturation
description: "Use when you have a basic diagnostic server scaffold and need to evolve it into a production-grade operator toolkit. Guides through 6 maturation levels (domain health → smoke tests → assert language → CLI formatting → diff engine → REPL+watch) with verification gates at each level. Also provides conformance audit mode to evaluate existing diagnostic servers against the maturation ladder."
---

# interhelm:diagnostic-maturation — Diagnostic Server Maturation Guide

## When to Use

Use when:
- You've scaffolded a diagnostic server (via `interhelm:runtime-diagnostics` or manually) and it only returns basic boolean health
- You want to build CLI operator tools that call the server's diagnostic endpoints
- You need to audit an existing diagnostic server's maturity level
- You're evolving beyond the scaffold toward production-grade operator tooling

Do NOT use when:
- You don't have a diagnostic server yet (use `interhelm:runtime-diagnostics` first to scaffold endpoints)
- You're building monitoring/alerting infrastructure (this is operator tooling, not ops)
- The app is a web service with existing APM (Datadog, New Relic, etc.)

**Relationship to `runtime-diagnostics`:** That skill scaffolds the *server-side endpoints* (health, diff, assert, smoke-test HTTP routes). This skill guides building the *CLI-side operator tools* that call those endpoints — the client layer, formatting, interactive modes, and the domain modeling that makes health checks meaningful.

## Mode Selection

Infer the mode from context:
- If the prompt mentions "audit", "assess", "evaluate", or "what level" → **Audit mode** (§ Conformance Audit)
- If the prompt mentions "improve", "evolve", "mature", "next level", or "add" → **Maturation mode** (§ Maturation Ladder)
- If ambiguous, default to **Audit mode** first (assess current state, then guide improvement)

---

## Maturation Ladder

Six levels from skeleton to production-grade. Each level is independently useful. Levels are sequential by default — each builds on the previous — but agents can skip levels if the app doesn't need them (e.g., skip L5 Diff Engine if the app has no snapshot-comparison use case).

**Domain translation:** The examples below use Shadow Work (a geopolitical simulation) as the reference. To apply to your domain, map "subsystem" to your app's major independent functional areas. Examples:
- **File sync tool:** watcher, transfer queue, conflict resolver, network layer
- **CLI dev tool:** parser, linter, formatter, cache
- **Game engine:** renderer, physics, audio, input, networking
- **API server:** auth, data layer, job queue, external integrations

### Level 1: Domain Health Modeling

**The hardest and most important level.** Most agents stop at "return true for healthy" — the real work is deciding WHAT to check.

**Process:**

1. **Identify subsystems.** List the 3-8 major subsystems of your application. Examples from Shadow Work (6 subsystems): simulation engine, economy, finance, emergence/AI, countries/entities, error tracking.

   Ask yourself: "If this subsystem is broken, would the app behave incorrectly?" If yes, it's a subsystem.

2. **Define states per subsystem.** Each subsystem has three states:
   - **Healthy** — operating within normal parameters
   - **Degraded** — functional but outside ideal range (e.g., tick time >100ms but <500ms)
   - **Unhealthy** — broken or producing incorrect results

3. **Wire detail fields.** Each subsystem's health response should include domain-specific metrics, not just a boolean. Examples:
   ```
   Simulation: { status, tick_count, avg_tick_ms, last_tick_ms, speed }
   Economy:    { status, gdp_total, trade_volume, active_markets }
   Finance:    { status, total_treasury, tax_revenue_rate }
   ```

4. **Set meaningful thresholds.** Define concrete numbers for state transitions:
   ```
   Simulation healthy:  avg_tick_ms < 100
   Simulation degraded: avg_tick_ms >= 100 && avg_tick_ms < 500
   Simulation unhealthy: avg_tick_ms >= 500 OR tick_count == 0
   ```

5. **Implement the aggregated health endpoint.** Return per-subsystem status with detail fields:
   ```json
   {
     "overall": "degraded",
     "subsystems": {
       "simulation": { "status": "healthy", "tick_count": 4200, "avg_tick_ms": 42 },
       "economy":    { "status": "degraded", "gdp_total": 0, "active_markets": 12 }
     }
   }
   ```

**You know you're done when:**
- **Structural check:** `curl /diag/health | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'subsystems' in d; assert len(d['subsystems'])>=3; assert all('status' in v for v in d['subsystems'].values()); print('L1 PASS')"` prints `L1 PASS`
- **Design check (human judgment):** Each subsystem has at least one metric beyond `status`, and thresholds for healthy/degraded/unhealthy are documented in code comments or a config file

---

### Level 2: Smoke Test Suite

**Build 5-15 end-to-end assertions that verify the app is working correctly.** These are not unit tests — they exercise the running app through its diagnostic endpoints.

**Process:**

1. **Design test categories.** Group tests by subsystem. Each test has a name, assertion, and expected result. Example from Shadow Work (12-point suite):
   ```
   connectivity:    Can reach the debug server
   simulation:      Sim is running (not paused, tick count > 0)
   economy:         GDP is positive
   finance:         Treasury is non-negative
   countries:       Country count > 0
   emergence:       Agent count matches expected
   trade:           Trade volume > 0
   error-rate:      Error count below threshold
   ```

2. **Implement pass/fail/skip semantics:**
   - **Pass** — assertion succeeded
   - **Fail** — assertion failed (the thing we're checking is broken)
   - **Skip** — can't evaluate (endpoint unreachable, data not yet available)

   Skip is critical — without it, agents can't distinguish "feature is broken" from "feature hasn't loaded yet."

3. **Run tests sequentially** and collect results. Return structured output:
   ```json
   {
     "passed": 10, "failed": 1, "skipped": 1, "total": 12,
     "tests": [
       { "name": "connectivity", "status": "pass", "ms": 12 },
       { "name": "economy-gdp", "status": "fail", "detail": "GDP is 0" },
       { "name": "emergence-agents", "status": "skip", "detail": "emergence not initialized" }
     ]
   }
   ```

4. **Wire a CLI command:** `<app>-agent smoke` that runs the suite and prints colored output.

**You know you're done when:** Running `<app>-agent smoke` prints a pass/fail/skip summary with per-test results, and at least 5 tests cover different subsystems.

---

### Level 3: Assert Language

**Build a lightweight expression evaluator for scripted verification.** This lets agents (and humans) run ad-hoc assertions without modifying code.

**Process:**

1. **Define expression syntax.** Keep it simple — compound assertions joined by `&&`:
   ```
   health.simulation.status == healthy && health.simulation.avg_tick_ms < 100
   ```

2. **Build a state context.** Flatten the diagnostic server's state into a queryable namespace:
   ```
   health.simulation.status → "healthy"
   health.simulation.tick_count → 4200
   health.economy.gdp_total → 1500000
   ```

3. **Evaluate clauses.** For each clause (split on `&&`):
   - Parse left-hand side (dotted path into state context)
   - Parse operator (`==`, `!=`, `<`, `>`, `<=`, `>=`, `contains`)
   - Parse right-hand side (literal value)
   - Resolve LHS against state context
   - Compare and return pass/fail with explanation

4. **Report results per clause** with colored output:
   ```
   ✓ health.simulation.status == healthy
   ✗ health.economy.gdp_total > 1000000 (actual: 0)
   RESULT: FAIL (1/2 passed)
   ```

5. **Wire a CLI command:** `<app>-agent assert "<expression>"`

**You know you're done when:** `<app>-agent assert "health.simulation.status == healthy && health.simulation.tick_count > 0"` evaluates both clauses against live state and prints per-clause pass/fail.

---

### Level 4: CLI Formatting

**Build human-readable output with compact numbers, colored status, and aligned tables.**

**Process:**

1. **Compact number formatting.** Large numbers should be human-readable:
   ```
   1234        → "1,234"
   1500000     → "1.5M"
   2300000000  → "2.3B"
   4500000000000 → "4.5T"
   ```
   Thresholds: K (≥1,000), M (≥1,000,000), B (≥1,000,000,000), T (≥1,000,000,000,000).

2. **Percentage and currency helpers:**
   ```
   pct(0.1534) → "15.3%"
   money(1500000) → "$1.5M"
   ```

3. **Status coloring.** Use ANSI colors consistently:
   ```
   healthy/pass  → green
   degraded/skip → yellow
   unhealthy/fail → red
   ```

4. **Table padding.** Right-align numbers, left-align text. Use consistent column widths:
   ```
   Country          GDP      Population   Status
   United States    $21.4T   331M         healthy
   China            $14.7T   1.4B         degraded
   ```

5. **Apply formatting to all existing commands** (status, smoke, assert, health).

**You know you're done when:** All CLI commands produce aligned, colored output with compact numbers. Large values like 1500000000 display as "1.5B", not raw integers.

---

### Level 5: Diff Engine

**Build snapshot-before/after comparison with domain-specific deltas.**

**Process:**

1. **Capture snapshots.** Before an operation (e.g., advancing 100 simulation ticks), snapshot the full diagnostic state:
   ```
   snapshot_before = GET /diag/state
   ```

2. **Run the operation.** Execute the action being tested.

3. **Capture after state:**
   ```
   snapshot_after = GET /diag/state
   ```

4. **Compute domain-specific deltas.** Don't just diff JSON — compute meaningful changes:
   ```
   Simulation: +100 ticks, avg_tick_ms 42→38 (-9.5%)
   Economy:    GDP $1.5M→$1.8M (+20.0%), 3 new markets
   Countries:  2 countries changed status
   ```

5. **Wire a CLI command:** `<app>-agent diff <command>` that snapshots, runs, snapshots, and shows deltas.

**You know you're done when:** `<app>-agent diff "step 100"` shows before/after comparison with domain-specific deltas (not raw JSON diff), formatted with compact numbers and colors.

---

### Level 6: Interactive REPL + Watch Mode

**Add interactive exploration and continuous monitoring.**

**Process:**

1. **REPL mode.** Interactive prompt that accepts any CLI command without the binary prefix:
   ```
   > status
   (shows status)
   > assert "health.simulation.status == healthy"
   ✓ health.simulation.status == healthy
   > smoke
   12/12 passed
   > help
   (shows available commands)
   ```

   Key features:
   - Command history (readline/rustyline)
   - Tab completion for commands
   - `.exit` or Ctrl+D to quit

2. **Watch mode.** Poll a command at an interval and redisplay:
   ```
   <app>-agent watch status 5    # refresh status every 5 seconds
   <app>-agent watch smoke 30    # run smoke tests every 30 seconds
   ```

   Key features:
   - Clear screen between updates (if TTY detected; print separator lines otherwise)
   - Show timestamp of last update
   - Ctrl+C to stop
   - Highlight changes since last update
   - Graceful degradation in non-TTY environments (agent shells, piped output): skip ANSI colors, use text separators instead of screen clears

3. **Wire CLI commands:** `<app>-agent repl` and `<app>-agent watch <cmd> [interval]`

**You know you're done when:** `<app>-agent repl` gives an interactive prompt with history, and `<app>-agent watch status 5` continuously refreshes the display.

---

## Conformance Audit

Evaluate an existing diagnostic server against the maturation ladder.

### Process

1. **Discover the diagnostic server.** Find the diagnostic endpoint configuration:
   ```bash
   # Look for diagnostic server code
   grep -r "/diag/" src/ src-tauri/ --include="*.rs" --include="*.ts" --include="*.py" -l 2>/dev/null
   # Look for CLI tools
   find tools/ bin/ -name "*agent*" -o -name "*diag*" 2>/dev/null
   ```

2. **Check each level.** For each maturation level, look for evidence of implementation:

   | Level | Check for | Evidence |
   |-------|-----------|----------|
   | L1: Domain Health | Per-subsystem health with detail fields | Health endpoint returns JSON with >1 subsystem, each having status + metrics |
   | L2: Smoke Tests | Structured test suite with pass/fail/skip | File with test definitions, CLI command that runs them, results with counts |
   | L3: Assert Language | Expression evaluator | CLI command accepting assertion strings, clause-by-clause evaluation |
   | L4: CLI Formatting | Compact numbers, colored output | Formatter module with compactNum/pct/money helpers, ANSI color usage |
   | L5: Diff Engine | Snapshot comparison | Before/after capture, domain-specific delta computation |
   | L6: REPL + Watch | Interactive and continuous modes | Readline/prompt loop, polling with interval |

3. **Report findings.** For each level, report:
   - **Implemented** — evidence found, list what exists
   - **Partial** — some elements present, list gaps
   - **Missing** — no evidence found

4. **Provide next steps.** For the first missing or partial level, provide actionable guidance:
   ```
   Current Level: 3/6 (Assert Language)

   Implemented:
     L1 Domain Health: ✓ 6 subsystems with thresholds
     L2 Smoke Tests:   ✓ 12-point suite with pass/fail/skip
     L3 Assert:        ✓ Expression evaluator with && support

   Missing:
     L4 CLI Formatting: No compact number helpers found. Start with:
       - Create a formatter module with compactNum(), pct(), money()
       - Apply to status and smoke test output
     L5 Diff Engine:   No snapshot comparison found
     L6 REPL + Watch:  No interactive mode found

   Recommended next: Level 4 (CLI Formatting)
   ```

### Shadow Work Reference

Shadow Work's sw-agent is a Level 6 implementation (1,525 lines across 6 files):
- **L1:** 6 subsystems (simulation, economy, finance, emergence, countries, errors) with healthy/degraded/unhealthy per subsystem
- **L2:** 12-point smoke test suite with SmokeTest class (pass/fail/skip semantics, timing)
- **L3:** `runAssert(client, expr)` — splits on `&&`, evaluates against flattened state context
- **L4:** `compactNum()` (T/B/M/K), `pct()`, `money()`, `pad()`/`padLeft()` helpers
- **L5:** Snapshot-before/after with per-subsystem deltas
- **L6:** Interactive REPL with readline + `watch` command with configurable interval

Use this as a reference for what "done" looks like at each level, adapted to your app's domain.
```

**Step 2: Verify the skill directory and file exist**

Run:
```bash
ls -la interverse/interhelm/skills/diagnostic-maturation/SKILL.md
```
Expected: File exists with non-zero size.

**Step 3: Validate frontmatter**

Run:
```bash
cd interverse/interhelm && python3 -c "
import yaml
content = open('skills/diagnostic-maturation/SKILL.md').read()
parts = content.split('---', 2)
fm = yaml.safe_load(parts[1])
assert fm['name'] == 'diagnostic-maturation', f'name mismatch: {fm[\"name\"]}'
assert 'description' in fm, 'missing description'
print(f'OK: name={fm[\"name\"]}, description length={len(fm[\"description\"])}')
"
```
Expected: `OK: name=diagnostic-maturation, description length=...`

<verify>
- run: `python3 -c "import yaml; c=open('interverse/interhelm/skills/diagnostic-maturation/SKILL.md').read(); fm=yaml.safe_load(c.split('---',2)[1]); assert fm['name']=='diagnostic-maturation' and 'description' in fm; print('OK')"`
  expect: contains "OK"
</verify>

Note: All verify blocks assume cwd is the monorepo root (`/home/mk/projects/Demarch`).

---

### Task 2: Update plugin.json, Tests, and Commit Together

**Files:**
- Modify: `interverse/interhelm/.claude-plugin/plugin.json`
- Modify: `interverse/interhelm/tests/structural/test_skills.py`

**Note:** plugin.json and test_skills.py MUST be committed together to avoid a broken intermediate state where the test expects 3 skills but plugin.json lists 4.

**Step 1: Add the 4th skill entry to plugin.json**

Add `"./skills/diagnostic-maturation"` to the `skills` array in plugin.json:

```json
"skills": [
    "./skills/runtime-diagnostics",
    "./skills/smoke-test-design",
    "./skills/cuj-verification",
    "./skills/diagnostic-maturation"
]
```

**Step 2: Update expected skill count in test_skills.py**

Change the assertion in `test_skill_count` from 3 to 4:

```python
def test_skill_count(skills_dir):
    """Expected number of skills."""
    skills = list(skills_dir.glob("*/SKILL.md"))
    assert len(skills) == 4, (
        f"Expected 4 skills, found {len(skills)}: {[s.parent.name for s in skills]}"
    )
```

**Step 3: Run tests**

Run (from monorepo root):
```bash
cd interverse/interhelm/tests && uv run pytest -q
```
Expected: All tests pass, including `test_skill_count` expecting 4.

**Step 4: Commit all together**

```bash
git add -f interverse/interhelm/skills/diagnostic-maturation/SKILL.md interverse/interhelm/.claude-plugin/plugin.json interverse/interhelm/tests/structural/test_skills.py
git commit -m "feat(interhelm): add diagnostic-maturation skill (4th skill)

Guides agents from skeleton diagnostic server to production-grade
operator toolkit via 6-level maturation ladder and conformance audit."
```

<verify>
- run: `python3 -c "import json; d=json.load(open('interverse/interhelm/.claude-plugin/plugin.json')); assert len(d['skills'])==4; print('OK')"`
  expect: contains "OK"
- run: `cd interverse/interhelm/tests && uv run pytest structural/test_skills.py -q`
  expect: exit 0
</verify>

---

### Task 3: Update CLAUDE.md Skill Count

**Files:**
- Modify: `interverse/interhelm/CLAUDE.md`

**Step 1: Update overview line**

Change "3 skills" to "4 skills" in the overview:

```markdown
## Overview

4 skills, 1 agent, 3 hooks. Standalone plugin — no intercore dependency.
```

**Step 2: Update quick commands**

Change the skill count check comment:

```bash
ls skills/*/SKILL.md | wc -l  # Should be 4
```

**Step 3: Commit**

```bash
git add -f interverse/interhelm/CLAUDE.md
git commit -m "docs(interhelm): update CLAUDE.md for 4 skills"
```

<verify>
- run: `grep -c "4 skills" interverse/interhelm/CLAUDE.md`
  expect: contains "1"
</verify>
