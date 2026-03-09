---
artifact_type: plan
bead: Demarch-ekh
stage: design
requirements:
  - F10: Interhelm plugin scaffold
  - F1: Runtime diagnostics skill
  - F2: Smoke test design skill
  - F3: CUJ verification skill
  - F4: Runtime reviewer agent
  - F5: Browser-on-native detection hook
  - F6: Auto-health-check hook
  - F7: CUJ reminder hook
  - F8: Rust/hyper diagnostic server templates
  - F9: CLI client templates
---

# Interhelm Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-ekh
**Goal:** Create the interhelm Interverse plugin — agent-as-operator runtime diagnostics with skills, agent, hooks, and Rust templates.

**Architecture:** Standalone Interverse plugin at `interverse/interhelm/`. Pattern-based plugin (teaches agents to scaffold diagnostic servers, doesn't ship runtime code). Three skills teach the four core patterns + CUJ verification. One review agent validates implementations. Three PostToolUse hooks nudge agents toward diagnostic workflows. Rust/hyper templates in `templates/` provide concrete starting points.

**Tech Stack:** Markdown (skills, agent, docs), JSON (plugin.json, hooks.json), Bash (hooks, scripts), Rust (template code — not compiled, reference only), Python (structural tests via pytest).

**Prior Learnings:**
- `docs/solutions/integration-issues/plugin-loading-failures-interverse-20260215.md` — hooks.json MUST use event-key object format, not flat arrays. Silent failure on wrong format.
- `docs/solutions/integration-issues/plugin-validation-errors-cache-manifest-divergence-20260217.md` — plugin.json must declare ALL capabilities. Always bump version when adding components.
- Reference hooks.json: `interverse/interlock/hooks/hooks.json`
- Reference plugin.json: `interverse/interflux/.claude-plugin/plugin.json`
- Reference SKILL.md: `interverse/intertest/skills/systematic-debugging/SKILL.md`
- Reference agent.md: `interverse/interflux/agents/review/fd-architecture.md`

---

## Must-Haves

**Truths** (observable behaviors):
- Agent can discover interhelm skills when working on a project with a diagnostic server
- Runtime diagnostics skill guides scaffolding of all 4 core patterns + UI state endpoint
- Runtime reviewer agent catches missing patterns, security issues, and performance problems
- Browser-on-native hook fires when agent uses screenshot tools on native app projects
- Structural tests pass: `cd interverse/interhelm/tests && uv run pytest -q`

**Artifacts** (files that must exist):
- `interverse/interhelm/.claude-plugin/plugin.json` — declares 3 skills, 1 agent
- `interverse/interhelm/hooks/hooks.json` — declares 3 PostToolUse hooks
- `interverse/interhelm/skills/runtime-diagnostics/SKILL.md` — main skill
- `interverse/interhelm/skills/smoke-test-design/SKILL.md` — contract pattern
- `interverse/interhelm/skills/cuj-verification/SKILL.md` — screenshot-free CUJ validation
- `interverse/interhelm/agents/review/runtime-reviewer.md` — operational review agent
- `interverse/interhelm/templates/rust-hyper/` — server skeleton
- `interverse/interhelm/templates/cli/` — client skeleton

**Key Links:**
- plugin.json skill paths must match actual `skills/*/` directories
- plugin.json agent paths must match actual `agents/review/*.md` files
- hooks.json must use event-key object format (not flat array) or hooks silently fail

---

### Task 1: Plugin Scaffold — Directory Structure and plugin.json

**Files:**
- Create: `interverse/interhelm/.claude-plugin/plugin.json`
- Create: `interverse/interhelm/.gitignore`
- Create: `interverse/interhelm/LICENSE`

**Step 1: Create directory structure**

Run:
```bash
mkdir -p interverse/interhelm/{.claude-plugin,skills/{runtime-diagnostics,smoke-test-design,cuj-verification},agents/review,hooks,templates/{rust-hyper/src,cli/src},scripts,tests/structural}
```

**Step 2: Write plugin.json**

```json
{
  "name": "interhelm",
  "version": "0.1.0",
  "description": "Agent-as-operator runtime diagnostics — teaches agents to observe and control running applications via diagnostic HTTP servers and CLI tools.",
  "author": {
    "name": "mistakeknot",
    "email": "mistakeknot@vibeguider.org"
  },
  "repository": "https://github.com/mistakeknot/interhelm",
  "license": "MIT",
  "keywords": [
    "runtime",
    "diagnostics",
    "observability",
    "health-check",
    "operator",
    "native-apps"
  ],
  "skills": [
    "./skills/runtime-diagnostics",
    "./skills/smoke-test-design",
    "./skills/cuj-verification"
  ],
  "agents": [
    "./agents/review/runtime-reviewer.md"
  ]
}
```

**Step 3: Write .gitignore**

```
__pycache__/
*.pyc
.pytest_cache/
.venv/
.beads/
*.log
.DS_Store
Thumbs.db
*.swp
*.swo
*~
```

**Step 4: Write LICENSE**

MIT license with "Copyright (c) 2025 MK".

**Step 5: Validate plugin.json is valid JSON**

Run: `python3 -c "import json; json.load(open('interverse/interhelm/.claude-plugin/plugin.json'))"`
Expected: no output (success)

**Step 6: Commit**

```bash
git add interverse/interhelm/.claude-plugin/plugin.json interverse/interhelm/.gitignore interverse/interhelm/LICENSE
git commit -m "feat(interhelm): scaffold plugin directory and manifest"
```

<verify>
- run: `python3 -c "import json; d=json.load(open('interverse/interhelm/.claude-plugin/plugin.json')); assert d['name']=='interhelm'; assert len(d['skills'])==3; assert len(d['agents'])==1; print('OK')"`
  expect: contains "OK"
</verify>

---

### Task 2: Plugin Docs — CLAUDE.md, AGENTS.md, PHILOSOPHY.md, README.md

**Files:**
- Create: `interverse/interhelm/CLAUDE.md`
- Create: `interverse/interhelm/AGENTS.md`
- Create: `interverse/interhelm/PHILOSOPHY.md`
- Create: `interverse/interhelm/README.md`

**Step 1: Write CLAUDE.md**

```markdown
# interhelm

> See `AGENTS.md` for full development guide.

## Overview

3 skills, 1 agent, 3 hooks. Standalone plugin — no intercore dependency. Teaches agents the "agent-as-operator" pattern: observe and control running applications via diagnostic HTTP servers and CLI tools.

## Quick Commands

```bash
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"  # Manifest check
ls skills/*/SKILL.md | wc -l  # Should be 3
ls agents/review/*.md | wc -l  # Should be 1
python3 -c "import json; json.load(open('hooks/hooks.json'))"  # Hooks check
cd tests && uv run pytest -q  # Structural tests
```

## Design Decisions (Do Not Re-Ask)

- Standalone plugin — no intercore dependency, pattern works for any app
- Framework-agnostic — skills guide Tauri, Electron, web, CLI scaffolding
- Pattern plugin — teaches the pattern, doesn't ship runtime code
- Structured over visual — prefer JSON state queries over screenshots
- Templates are reference code — not compiled or tested as part of plugin
- Hooks are advisory — suggestions, not blockers
```

**Step 2: Write PHILOSOPHY.md**

```markdown
# interhelm Philosophy

## Purpose
Agent-as-operator runtime diagnostics — teaches agents to observe and control running applications via structured diagnostic interfaces instead of screenshot-based debugging.

## North Star
Every running application should be queryable by agents through structured APIs, making runtime verification as natural as running tests.

## Working Priorities
- Structured observability over visual inspection
- Pattern teaching over runtime code shipping
- Framework-agnostic guidance over framework-specific tooling

## Brainstorming Doctrine
1. Start from the agent's perspective — what does the agent need to know about runtime state?
2. Prefer patterns that produce parseable output over human-readable output.
3. Validate patterns against real applications (Shadow Work reference) before documenting.
4. Consider the token cost of each observability approach.

## Planning Doctrine
1. Each pattern (Health, Diff, Assert, Smoke Test) should be independently usable.
2. Templates should compile and run with minimal customization.
3. Skills should work for any framework, with framework-specific guidance as supplements.
4. Hooks should suggest, never block.

## Decision Filters
- Does this reduce the agent's need for screenshots?
- Does this produce structured, parseable output?
- Can this pattern work for native apps (Tauri, Electron) not just web apps?
- Is the pattern validated against a real implementation?

## Evidence Base
- Reference implementation: Shadow Work `sw-agent` + Rust debug server
- Battle-tested on P0 desync bug (25+ state fields requiring reset verification)
- Source confidence: high (extracted from production-grade implementation)
```

**Step 3: Write AGENTS.md**

```markdown
# interhelm — Development Guide

Agent-as-operator runtime diagnostics — teaches agents to observe and control running applications via diagnostic HTTP servers and CLI tools.

## Canonical References
1. `PHILOSOPHY.md` — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review `PHILOSOPHY.md` during:
- Intake/scoping
- Brainstorming
- Planning
- Execution kickoff
- Review/gates
- Handoff/retrospective

For brainstorming/planning outputs, add two short lines:
- `Alignment:` one sentence on how the proposal supports the module north star.
- `Conflict/Risk:` one sentence on any tension with philosophy (or `none`).

## Execution Rules
- Keep changes small, testable, and reversible.
- Run validation commands from `CLAUDE.md` before completion.
- Commit only intended files and push before handoff.

## Quick Reference

| Field | Value |
|-------|-------|
| Namespace | `interhelm:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 3 skills, 1 agent, 3 hooks |
| Templates | `templates/rust-hyper/`, `templates/cli/` |

## Core Patterns

| Pattern | Endpoint | Purpose |
|---------|----------|---------|
| Health | `GET /diag/health` | Structured pass/fail per subsystem |
| Diff | `POST /diag/diff` | Snapshot state, take action, show deltas |
| Assert | `POST /diag/assert` | Scriptable verification expressions |
| Smoke Test | `POST /diag/smoke-test` | End-to-end flow verification |
| UI State | `GET /diag/ui/state` | Semantic UI state (screenshot replacement) |
| Schema | `GET /diag/schema` | Self-describing API for discovery |

## Endpoint Architecture

- `/diag/*` — Read-only observations (health, state, UI, schema)
- `/control/*` — Mutations (restart, reset, step, trigger)
- Convention: diagnostic server runs on a known port (default 9876)
```

**Step 4: Write README.md**

```markdown
# interhelm

Agent-as-operator runtime diagnostics for the [Interverse](https://github.com/mistakeknot/Demarch) plugin ecosystem.

## What

Teaches agents to observe and control running applications via diagnostic HTTP servers and CLI tools. Instead of taking screenshots, agents query structured JSON endpoints for runtime state — including UI state.

## Installation

```bash
claude plugins install interhelm
```

## Core Patterns

| Pattern | What It Does |
|---------|-------------|
| **Health** | Structured pass/fail per subsystem |
| **Diff** | Snapshot state, take action, show what changed |
| **Assert** | Scriptable verification expressions |
| **Smoke Test** | End-to-end flow verification (executable contract) |

## UI Observability

The killer feature: `/diag/ui/state` returns semantic JSON describing what's on screen — active view, panel states, selections, form values. Agents verify CUJs without screenshots at near-zero token cost.

## Usage

The skills guide agents to scaffold a diagnostic server and CLI for your project:

1. **`runtime-diagnostics`** — Scaffolds the full diagnostic HTTP server with all patterns
2. **`smoke-test-design`** — Designs executable contracts between server and client
3. **`cuj-verification`** — Validates user journeys via structured state queries

## Templates

- `templates/rust-hyper/` — Rust diagnostic server skeleton (hyper)
- `templates/cli/` — Thin CLI client with formatters, watch mode, REPL

## Architecture

- **Standalone** — no intercore dependency
- **Framework-agnostic** — works with Tauri, Electron, web apps, CLI tools
- **Pattern plugin** — teaches the pattern, agents generate the implementation

## Design Decisions

See [PHILOSOPHY.md](PHILOSOPHY.md) for design bets and tradeoffs.

## License

MIT
```

**Step 5: Commit**

```bash
git add interverse/interhelm/{CLAUDE,AGENTS,PHILOSOPHY,README}.md
git commit -m "docs(interhelm): add CLAUDE.md, AGENTS.md, PHILOSOPHY.md, README.md"
```

<verify>
- run: `ls interverse/interhelm/{CLAUDE,AGENTS,PHILOSOPHY,README}.md | wc -l`
  expect: contains "4"
</verify>

---

### Task 3: Runtime Diagnostics Skill (F1)

**Files:**
- Create: `interverse/interhelm/skills/runtime-diagnostics/SKILL.md`

**Step 1: Write SKILL.md**

```markdown
---
name: runtime-diagnostics
description: "Use when you need to verify a running native app works correctly after code changes, can't use browser DevTools, need to check runtime state without screenshots, or want to confirm a Tauri/Electron app's simulation or UI didn't break. Guides scaffolding of a diagnostic HTTP server with Health, Diff, Assert, Smoke Test patterns plus semantic UI state endpoint."
---

# interhelm:runtime-diagnostics — Runtime Diagnostic Server Scaffolding

## When to Use

Use when:
- Verifying runtime behavior after code changes (not just test results)
- Working with native apps (Tauri, Electron) where browser tools don't work
- Debugging state desync, UI rendering, or subsystem health issues
- Replacing screenshot-based debugging with structured state queries

Do NOT use when:
- Unit tests are sufficient to verify the change
- Working with a web app that has browser DevTools access
- The app already has a diagnostic server (use it directly)

## Prerequisites

Check if the project already has a diagnostic server:

```bash
# Look for existing diagnostic endpoints
grep -r "/diag/" src/ src-tauri/ 2>/dev/null | head -5
# Check for existing health endpoints
grep -r "health" src/ --include="*.rs" --include="*.ts" -l 2>/dev/null | head -5
```

If found, skip scaffolding and use existing endpoints directly.

## Scaffolding Workflow

### Step 1: Identify Subsystems

Before writing any code, enumerate the app's subsystems that need observability:

1. Read the app's main state struct or store
2. List each logical subsystem (e.g., simulation, economy, UI, networking)
3. For each subsystem, identify:
   - Key state fields agents need to observe
   - Health check criteria (what makes it "healthy"?)
   - Control actions agents might need (restart, reset, step)

### Step 2: Scaffold the Diagnostic Server

Use the templates in `templates/rust-hyper/` as starting points. The server exposes two endpoint families:

**`/diag/*` — Read-only observations:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/diag/health` | GET | Structured pass/fail per subsystem |
| `/diag/schema` | GET | Self-describing API (available endpoints + params) |
| `/diag/ui/state` | GET | Semantic UI state — active view, panels, selections, values |
| `/diag/diff` | POST | Snapshot current state, optionally take N steps, return deltas |
| `/diag/assert` | POST | Evaluate assertion expression against current state |
| `/diag/smoke-test` | POST | Run full verification sequence, return per-check results |

**`/control/*` — Mutations:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/control/restart` | POST | Restart the application/simulation |
| `/control/reset` | POST | Reset specific subsystem to initial state |
| `/control/step` | POST | Advance simulation by N steps |

**Key implementation rules:**
- Diagnostic server runs on a separate thread/task (never block the main app loop)
- State access must be thread-safe (Arc<Mutex<T>> or channel-based)
- Health checks must have timeouts (default 5s per subsystem)
- Diff snapshots must be bounded in size (serialize only observable state, not caches)
- All `/diag/*` endpoints are read-only — never mutate state in diagnostic handlers
- Control endpoints should guard against concurrent mutations

### Step 3: Implement Health Checks

Each subsystem reports structured health:

```json
{
  "status": "healthy",
  "subsystems": {
    "simulation": { "status": "healthy", "details": { "tick": 1420, "entities": 156 } },
    "economy": { "status": "degraded", "details": { "reason": "negative balance in 3 accounts" } },
    "ui": { "status": "healthy", "details": { "active_view": "dashboard", "panels": 4 } }
  },
  "timestamp": "2026-03-09T14:30:00Z"
}
```

Health status values: `healthy`, `degraded`, `unhealthy`, `unknown`.

### Step 4: Implement UI State Endpoint

The `/diag/ui/state` endpoint returns semantic UI state — what's visible, selected, and active:

```json
{
  "active_view": "simulation",
  "panels": {
    "sidebar": { "visible": true, "selected_tab": "entities" },
    "main": { "visible": true, "content": "world_map" },
    "inspector": { "visible": true, "selected_entity": "country_42" }
  },
  "selections": {
    "current_entity": { "id": "country_42", "name": "Freedonia" },
    "current_tool": "inspect"
  },
  "form_values": {},
  "modal": null
}
```

This replaces screenshots. Agents query this endpoint instead of taking and OCR-ing screenshots.

### Step 5: Implement Diff Pattern

```
POST /diag/diff
{ "steps": 100, "filter": ["simulation", "economy"] }

Response:
{
  "before": { "simulation.tick": 1420, "economy.gdp": 50000 },
  "after": { "simulation.tick": 1520, "economy.gdp": 52300 },
  "deltas": { "simulation.tick": "+100", "economy.gdp": "+2300 (+4.6%)" }
}
```

### Step 6: Implement Assert Pattern

```
POST /diag/assert
{ "expression": "simulation.tick > 0 && economy.gdp > 0" }

Response:
{ "result": true, "expression": "simulation.tick > 0 && economy.gdp > 0", "values": { "simulation.tick": 1520, "economy.gdp": 52300 } }
```

### Step 7: Scaffold the CLI Client

Use `templates/cli/` as starting point. Minimum subcommands:

```
app-diag health              # GET /diag/health (formatted table)
app-diag ui                  # GET /diag/ui/state (formatted tree)
app-diag diff [--steps N]    # POST /diag/diff
app-diag assert "<expr>"     # POST /diag/assert
app-diag smoke-test          # POST /diag/smoke-test
app-diag watch [--interval]  # Poll health every N seconds
app-diag schema              # GET /diag/schema
```

### Step 8: Wire Up and Test

1. Start the app with diagnostic server enabled
2. Run `app-diag health` — verify all subsystems report
3. Run `app-diag ui` — verify UI state is accurate
4. Run `app-diag smoke-test` — verify end-to-end flow
5. Make a code change, restart, re-run health — verify no regressions

## Discovery Convention

Projects with a diagnostic server should document it in their `CLAUDE.md`:

```markdown
## Diagnostic Server

Port: 9876
CLI: `tools/app-diag`
Patterns: health, diff, assert, smoke-test, ui-state
```

Agents check for this section to know diagnostic endpoints are available.
```

**Step 2: Commit**

```bash
git add interverse/interhelm/skills/runtime-diagnostics/SKILL.md
git commit -m "feat(interhelm): add runtime-diagnostics skill — 4 patterns + UI state"
```

<verify>
- run: `test -f interverse/interhelm/skills/runtime-diagnostics/SKILL.md && head -3 interverse/interhelm/skills/runtime-diagnostics/SKILL.md | grep -c "name: runtime-diagnostics"`
  expect: contains "1"
</verify>

---

### Task 4: Smoke Test Design Skill (F2)

**Files:**
- Create: `interverse/interhelm/skills/smoke-test-design/SKILL.md`

**Step 1: Write SKILL.md**

```markdown
---
name: smoke-test-design
description: "Use when designing end-to-end verification for a running application — teaches the executable contract pattern where smoke tests serve as the agreement between diagnostic server and CLI client."
---

# interhelm:smoke-test-design — Executable Contract Pattern

## When to Use

Use when:
- Setting up end-to-end verification for a new application
- Adding subsystems that need runtime verification
- Defining the contract between diagnostic server and CLI client
- A critical user journey needs automated verification

## The Executable Contract

A smoke test is NOT just an end-to-end test. It is the **contract** between the diagnostic server and the CLI client — the authoritative definition of "this application works correctly."

### Anatomy of a Smoke Test

```json
POST /diag/smoke-test
{
  "checks": [
    { "name": "server_reachable", "type": "health", "expect": "status == 'healthy'" },
    { "name": "subsystems_up", "type": "health", "expect": "all_subsystems('healthy')" },
    { "name": "state_initialized", "type": "assert", "expect": "simulation.tick >= 0" },
    { "name": "ui_renders", "type": "ui_state", "expect": "active_view != null" },
    { "name": "can_step", "type": "diff", "params": { "steps": 1 }, "expect": "simulation.tick > before.simulation.tick" },
    { "name": "no_errors", "type": "health", "expect": "error_count == 0" }
  ]
}

Response:
{
  "passed": 5,
  "failed": 1,
  "total": 6,
  "results": [
    { "name": "server_reachable", "status": "pass", "duration_ms": 12 },
    { "name": "subsystems_up", "status": "pass", "duration_ms": 45 },
    { "name": "state_initialized", "status": "pass", "duration_ms": 8 },
    { "name": "ui_renders", "status": "pass", "duration_ms": 15 },
    { "name": "can_step", "status": "pass", "duration_ms": 230 },
    { "name": "no_errors", "status": "fail", "detail": "error_count = 2", "duration_ms": 10 }
  ]
}
```

### Design Principles

1. **Smoke tests are ordered** — each check builds on the previous (can't check state if server isn't reachable)
2. **Fail fast** — stop on first failure by default (optional: run all and report)
3. **Bounded duration** — total smoke test should complete in <30 seconds
4. **Deterministic** — same state should produce same results (no random input)
5. **Self-documenting** — check names describe what they verify

### Adding Checks for New Subsystems

When adding a new subsystem to the application:

1. Add a health check for the subsystem in `/diag/health`
2. Add at least one assertion for the subsystem's initial state
3. Add a diff check that verifies the subsystem responds to control actions
4. Update the smoke test to include the new checks
5. Run the smoke test — the new checks should pass with the subsystem active

### Contract Evolution

The smoke test is the source of truth. When it fails after a code change:
- If the change is intentional: update the smoke test expectations
- If the change is unintentional: the smoke test caught a regression — fix the code

Never delete a smoke test check to make tests pass. Either fix the code or update the expectation with a comment explaining why.
```

**Step 2: Commit**

```bash
git add interverse/interhelm/skills/smoke-test-design/SKILL.md
git commit -m "feat(interhelm): add smoke-test-design skill — executable contract pattern"
```

<verify>
- run: `test -f interverse/interhelm/skills/smoke-test-design/SKILL.md && head -3 interverse/interhelm/skills/smoke-test-design/SKILL.md | grep -c "name: smoke-test-design"`
  expect: contains "1"
</verify>

---

### Task 5: CUJ Verification Skill (F3)

**Files:**
- Create: `interverse/interhelm/skills/cuj-verification/SKILL.md`

**Step 1: Write SKILL.md**

```markdown
---
name: cuj-verification
description: "Use when verifying critical user journeys in a running application without screenshots — queries structured /diag/ui/state endpoints for semantic UI state instead of visual inspection."
---

# interhelm:cuj-verification — Screenshot-Free User Journey Validation

## When to Use

Use when:
- Verifying a CUJ works correctly after code changes
- The application is a native app (Tauri, Electron) where browser DevTools aren't available
- Screenshot-based verification is too slow or token-expensive
- You need deterministic, parseable verification results

Do NOT use when:
- The application doesn't have a diagnostic server with `/diag/ui/state`
- Visual appearance (colors, layout, animations) is what needs verification
- The CUJ involves external system interactions (API calls, file system) not exposed via diagnostics

## The Pattern: State-Before → Action → State-After

Instead of taking screenshots to verify UI changes, query the structured UI state endpoint:

### Step 1: Capture state before action

```bash
app-diag ui  # GET /diag/ui/state
```

Record: `active_view`, panel states, selections, form values.

### Step 2: Perform the action

Execute the user action via the diagnostic server's `/control/*` endpoints. This pattern works for actions exposed through control endpoints (restart, reset, step, select, create). For actions that require UI interaction (button clicks, drag-and-drop), you'll need to add corresponding `/control/*` endpoints first — see the `runtime-diagnostics` skill for guidance on scaffolding control endpoints.

### Step 3: Capture state after action

```bash
app-diag ui  # GET /diag/ui/state again
```

### Step 4: Assert expected changes

Compare before and after states. Verify:
- Active view changed (if navigation was expected)
- Panel content updated (if data was expected to change)
- Selection state reflects the action
- Form values were processed
- No unexpected side effects (other panels/views shouldn't change)

## Example: Verifying "User selects an entity and views details"

```bash
# Step 1: Before state
app-diag ui
# → { "active_view": "world_map", "panels": { "inspector": { "visible": false } } }

# Step 2: Action — select entity via control endpoint
curl -X POST http://localhost:9876/control/select -d '{"entity_id": "country_42"}'

# Step 3: After state
app-diag ui
# → { "active_view": "world_map", "panels": { "inspector": { "visible": true, "selected_entity": "country_42" } } }

# Step 4: Assert
app-diag assert "panels.inspector.visible == true && panels.inspector.selected_entity == 'country_42'"
# → { "result": true }
```

**Token cost comparison:**
- Screenshot approach: ~1500 tokens per screenshot × 2 screenshots = ~3000 tokens
- Structured approach: ~200 tokens per JSON response × 2 responses = ~400 tokens
- **7.5x cheaper** per verification step

## Multi-Step CUJ Verification

For CUJs with multiple steps, chain state-before/action/state-after sequences:

```bash
# CUJ: "User creates a new entity and verifies it appears"

# Step 1: Verify entity list count before
app-diag assert "simulation.entity_count == 156"

# Step 2: Create entity via control
curl -X POST http://localhost:9876/control/create_entity -d '{"type": "country", "name": "NewCountry"}'

# Step 3: Verify entity count increased
app-diag assert "simulation.entity_count == 157"

# Step 4: Verify entity appears in UI
app-diag assert "panels.entity_list.items | contains('NewCountry')"

# Step 5: Select the new entity
curl -X POST http://localhost:9876/control/select -d '{"entity_name": "NewCountry"}'

# Step 6: Verify inspector shows the new entity
app-diag assert "panels.inspector.selected_entity.name == 'NewCountry'"
```

## When Screenshots Are Still Needed

Structured state queries don't replace screenshots for:
- **Visual regression testing** — colors, fonts, layout, alignment
- **Animation verification** — transitions, loading spinners
- **Responsive design** — viewport-dependent layout changes
- **Accessibility visual cues** — focus rings, contrast

Use interhelm for **functional** CUJ verification. Use screenshots for **visual** verification.
```

**Step 2: Commit**

```bash
git add interverse/interhelm/skills/cuj-verification/SKILL.md
git commit -m "feat(interhelm): add cuj-verification skill — screenshot-free journey validation"
```

<verify>
- run: `test -f interverse/interhelm/skills/cuj-verification/SKILL.md && head -3 interverse/interhelm/skills/cuj-verification/SKILL.md | grep -c "name: cuj-verification"`
  expect: contains "1"
</verify>

---

### Task 6: Runtime Reviewer Agent (F4)

**Files:**
- Create: `interverse/interhelm/agents/review/runtime-reviewer.md`

**Step 1: Write agent definition**

```markdown
---
name: runtime-reviewer
description: "Reviews diagnostic server implementations for pattern completeness, security, and performance. Use when an agent has scaffolded a diagnostic HTTP server and CLI for a project. Examples: <example>user: \"I've implemented the debug server for my Tauri app\" assistant: \"I'll use the runtime-reviewer agent to verify completeness, security, and performance.\" <commentary>New diagnostic server needs validation against all four patterns plus security and performance checks.</commentary></example> <example>user: \"Review my /diag endpoints for issues\" assistant: \"I'll use the runtime-reviewer agent to check pattern coverage and operational quality.\" <commentary>Diagnostic endpoint review requires pattern completeness, security, and performance analysis.</commentary></example>"
model: sonnet
---

You are a Runtime Diagnostics Reviewer. You evaluate diagnostic server implementations for completeness, security, and operational quality.

## First Step (MANDATORY)

Read the project's `CLAUDE.md` and any diagnostic server documentation. Identify:
- Where the diagnostic server code lives
- Which framework is used (hyper, actix, axum, Express, Flask, etc.)
- What subsystems the app has
- Whether a CLI client exists

## Review Approach

### 1. Pattern Completeness

Check that all six core endpoints are implemented:

| Endpoint | Required | What to Check |
|----------|----------|---------------|
| `GET /diag/health` | Yes | Returns structured subsystem health with status enum (healthy/degraded/unhealthy/unknown) |
| `GET /diag/schema` | Yes | Self-describing — lists all available endpoints with parameters |
| `GET /diag/ui/state` | Yes | Returns semantic UI state (active view, panels, selections, form values) |
| `POST /diag/diff` | Yes | Accepts step count and optional filter, returns before/after/deltas |
| `POST /diag/assert` | Yes | Accepts expression string, returns boolean result with evaluated values |
| `POST /diag/smoke-test` | Yes | Runs ordered check sequence, returns per-check pass/fail with timing |

For each missing endpoint, report: which pattern is missing, why it matters, and a one-sentence scaffold hint.

Also verify:
- `/control/*` endpoints exist for mutations (restart, reset, step)
- Control and diagnostic endpoints are separated (no mutations in `/diag/*`)
- Schema endpoint accurately reflects available endpoints

### 2. Security Review

**Critical checks (flag as P0 if violated):**
- Diagnostic endpoints are NOT compiled into production builds (check for `#[cfg(debug_assertions)]` or equivalent feature gating)
- State dumps don't include: passwords, API keys, tokens, session secrets, PII
- Control endpoints have guards (at minimum: only accept localhost connections)

**Important checks (flag as P1):**
- Diagnostic server binds to localhost only (127.0.0.1), not 0.0.0.0
- No file system access through diagnostic endpoints
- Rate limiting or request size limits on control endpoints
- No shell command execution through diagnostic endpoints

### 3. Performance Review

**Critical checks (flag as P0 if violated):**
- State serialization does NOT hold a lock on the main application thread
- Diagnostic server runs on a separate thread/task from the main app loop

**Important checks (flag as P1):**
- Health checks have timeouts (default 5s per subsystem)
- Diff snapshots are bounded in size (not serializing caches, logs, or unbounded collections)
- Smoke test has a total timeout (default 30s)
- No unbounded allocations in diagnostic handlers (e.g., collecting all entities into a Vec)

**Nice-to-have checks (flag as P2):**
- Connection pooling for CLI client
- Async I/O for diagnostic requests
- Compression for large state responses

## Output Format

Report findings grouped by severity:

```
## Runtime Diagnostics Review

### P0 — Must Fix
- [finding with file:line reference]

### P1 — Should Fix
- [finding with file:line reference]

### P2 — Consider
- [finding with file:line reference]

### Passing
- Pattern completeness: N/6 endpoints implemented
- Security: [pass/fail summary]
- Performance: [pass/fail summary]
```
```

**Step 2: Commit**

```bash
git add interverse/interhelm/agents/review/runtime-reviewer.md
git commit -m "feat(interhelm): add runtime-reviewer agent — completeness, security, performance"
```

<verify>
- run: `test -f interverse/interhelm/agents/review/runtime-reviewer.md && head -3 interverse/interhelm/agents/review/runtime-reviewer.md | grep -c "name: runtime-reviewer"`
  expect: contains "1"
</verify>

---

### Task 7: Hooks — Browser-on-Native, Auto-Health, CUJ Reminder (F5, F6, F7)

**Files:**
- Create: `interverse/interhelm/hooks/hooks.json`
- Create: `interverse/interhelm/hooks/browser-on-native.sh`
- Create: `interverse/interhelm/hooks/auto-health-check.sh`
- Create: `interverse/interhelm/hooks/cuj-reminder.sh`

**Step 1: Write hooks.json**

Reference format: `interverse/interlock/hooks/hooks.json` (event-key objects, NOT flat arrays).

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "mcp__plugin_tuivision_tuivision__get_screenshot",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/browser-on-native.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/auto-health-check.sh",
            "timeout": 10,
            "async": true
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/cuj-reminder.sh",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ]
  }
}
```

**Step 2: Write browser-on-native.sh**

```bash
#!/usr/bin/env bash
# Hook: Detect browser/screenshot tool usage on native app projects
# Suggests diagnostic CLI instead of visual inspection
set -euo pipefail

# Check if project has a diagnostic server configured
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-.}"

# Look for diagnostic server markers in CLAUDE.md
if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
    if grep -qi "diagnostic server\|/diag/\|diag.*port" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null; then
        # Check if this is a native app (Tauri, Electron, etc.)
        is_native=false
        [[ -d "$PROJECT_ROOT/src-tauri" ]] && is_native=true
        [[ -f "$PROJECT_ROOT/electron-builder.yml" ]] && is_native=true
        [[ -f "$PROJECT_ROOT/forge.config.js" ]] && is_native=true

        if $is_native; then
            echo "interhelm: This project has a diagnostic server. Consider using the diagnostic CLI instead of screenshots for runtime verification. Run: interhelm:runtime-diagnostics"
        fi
    fi
fi
```

**Step 3: Write auto-health-check.sh**

```bash
#!/usr/bin/env bash
# Hook: Auto-run health check after Rust/Tauri source file changes
# Advisory only — reports regressions without blocking
# PostToolUse hooks receive JSON on stdin: {"tool_name", "tool_input", "tool_response"}
set -euo pipefail

# Parse the edited file path from stdin JSON
HOOK_INPUT=$(cat)
FILE_PATH=$(echo "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    # Edit tool: file_path is in tool_input
    inp = d.get('tool_input', {})
    if isinstance(inp, str):
        inp = json.loads(inp)
    print(inp.get('file_path', inp.get('command', '')))
except: pass
" 2>/dev/null) || FILE_PATH=""

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Check if the edited file is a Rust source file
case "$FILE_PATH" in
    *src-tauri/*.rs|*src/*.rs)
        ;;
    *)
        exit 0
        ;;
esac

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-.}"

# Check if project has a diagnostic CLI configured
if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
    diag_cli=$(grep -oP 'CLI:\s*`\K[^`]+' "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null || true)
    if [[ -n "$diag_cli" && -x "$PROJECT_ROOT/$diag_cli" ]]; then
        health_output=$("$PROJECT_ROOT/$diag_cli" health 2>/dev/null) || true
        if echo "$health_output" | grep -qi "unhealthy\|degraded\|fail"; then
            echo "interhelm: Health regression detected after editing Rust source. Run '$diag_cli health' for details."
        fi
    fi
fi
```

**Step 4: Write cuj-reminder.sh**

```bash
#!/usr/bin/env bash
# Hook: Remind agents to run CUJ verification after significant changes
# Triggers after git commit (detected via Bash tool running git commit)
# PostToolUse hooks receive JSON on stdin: {"tool_name", "tool_input", "tool_response"}
set -euo pipefail

# Parse the command from stdin JSON
HOOK_INPUT=$(cat)
COMMAND=$(echo "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', {})
    if isinstance(inp, str):
        inp = json.loads(inp)
    print(inp.get('command', ''))
except: pass
" 2>/dev/null) || COMMAND=""

# Only trigger on git commit commands
case "$COMMAND" in
    *"git commit"*)
        ;;
    *)
        exit 0
        ;;
esac

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-.}"

# Check if project has CUJs or diagnostic server
if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
    has_diag=$(grep -qi "diagnostic server\|/diag/" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null && echo "true" || echo "false")
    if [[ "$has_diag" == "true" ]]; then
        echo "interhelm: Consider running CUJ verification to confirm runtime behavior after this change. Skill: interhelm:cuj-verification"
    fi
fi
```

**Step 5: Make hook scripts executable**

Run:
```bash
chmod +x interverse/interhelm/hooks/browser-on-native.sh
chmod +x interverse/interhelm/hooks/auto-health-check.sh
chmod +x interverse/interhelm/hooks/cuj-reminder.sh
```

**Step 6: Validate hooks.json format**

Run: `python3 -c "import json; d=json.load(open('interverse/interhelm/hooks/hooks.json')); assert 'hooks' in d; assert 'PostToolUse' in d['hooks']; print('OK')"`
Expected: `OK`

**Step 7: Commit**

```bash
git add interverse/interhelm/hooks/
git commit -m "feat(interhelm): add 3 PostToolUse hooks — browser-on-native, auto-health, CUJ reminder"
```

<verify>
- run: `python3 -c "import json; d=json.load(open('interverse/interhelm/hooks/hooks.json')); print(len(d['hooks']['PostToolUse']))"`
  expect: contains "3"
- run: `test -x interverse/interhelm/hooks/browser-on-native.sh && echo 'executable'`
  expect: contains "executable"
</verify>

---

### Task 8: Rust/Hyper Server Templates (F8)

**Files:**
- Create: `interverse/interhelm/templates/rust-hyper/src/main.rs`
- Create: `interverse/interhelm/templates/rust-hyper/src/handlers.rs`
- Create: `interverse/interhelm/templates/rust-hyper/src/state.rs`
- Create: `interverse/interhelm/templates/rust-hyper/Cargo.toml`
- Create: `interverse/interhelm/templates/rust-hyper/README.md`

**Step 1: Write Cargo.toml template**

```toml
[package]
name = "app-diag-server"  # CUSTOMIZE: rename to your-app-diag-server
version = "0.1.0"
edition = "2021"

[dependencies]
hyper = { version = "1", features = ["server", "http1"] }
hyper-util = { version = "0.1", features = ["tokio"] }
http-body-util = "0.1"
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

**Step 2: Write state.rs template**

```rust
//! Application state types for the diagnostic server.
//!
//! CUSTOMIZE: Replace these placeholder types with your app's actual state.
//! The diagnostic server reads from this state to report health, diffs, and UI.

use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

/// Shared application state — wrap your app's state in this struct.
/// The Arc<Mutex<>> pattern ensures thread-safe access from the diagnostic server.
///
/// CUSTOMIZE: Add your subsystem states here.
pub type SharedState = Arc<Mutex<AppState>>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppState {
    // CUSTOMIZE: Add your subsystem states
    pub simulation: SimulationState,
    pub ui: UiState,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationState {
    pub tick: u64,
    pub entity_count: usize,
    pub running: bool,
    // CUSTOMIZE: Add your simulation fields
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UiState {
    pub active_view: String,
    pub panels: std::collections::HashMap<String, PanelState>,
    pub selections: std::collections::HashMap<String, serde_json::Value>,
    pub modal: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PanelState {
    pub visible: bool,
    pub content: Option<String>,
    pub selected_tab: Option<String>,
}

/// Health status for a subsystem.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HealthStatus {
    Healthy,
    Degraded,
    Unhealthy,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubsystemHealth {
    pub status: HealthStatus,
    pub details: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthReport {
    pub status: HealthStatus,
    pub subsystems: std::collections::HashMap<String, SubsystemHealth>,
    pub timestamp: String,
}

impl AppState {
    /// CUSTOMIZE: Implement health checks for each subsystem.
    pub fn health(&self) -> HealthReport {
        let mut subsystems = std::collections::HashMap::new();

        // CUSTOMIZE: Add health checks per subsystem
        subsystems.insert(
            "simulation".to_string(),
            SubsystemHealth {
                status: if self.simulation.running {
                    HealthStatus::Healthy
                } else {
                    HealthStatus::Degraded
                },
                details: serde_json::json!({
                    "tick": self.simulation.tick,
                    "entities": self.simulation.entity_count,
                }),
            },
        );

        let overall = if subsystems.values().all(|s| matches!(s.status, HealthStatus::Healthy)) {
            HealthStatus::Healthy
        } else {
            HealthStatus::Degraded
        };

        HealthReport {
            status: overall,
            subsystems,
            // CUSTOMIZE: use chrono::Utc::now().to_rfc3339() if chrono is available
            timestamp: format!("{:?}", std::time::SystemTime::now()),
        }
    }

    /// CUSTOMIZE: Return the semantic UI state.
    pub fn ui_state(&self) -> &UiState {
        &self.ui
    }
}
```

**Step 3: Write handlers.rs template**

```rust
//! HTTP handlers for diagnostic and control endpoints.
//!
//! All /diag/* handlers are read-only. All /control/* handlers may mutate state.

use crate::state::SharedState;
use http_body_util::Full;
use hyper::{body::Bytes, Request, Response, StatusCode};

type BoxBody = Full<Bytes>;

fn json_response(body: serde_json::Value) -> Response<BoxBody> {
    Response::builder()
        .header("content-type", "application/json")
        .body(Full::new(Bytes::from(body.to_string())))
        .unwrap()
}

fn error_response(status: StatusCode, msg: &str) -> Response<BoxBody> {
    Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Full::new(Bytes::from(
            serde_json::json!({"error": msg}).to_string(),
        )))
        .unwrap()
}

// ── Diagnostic Endpoints (read-only) ──────────────────────────────────

pub async fn handle_health(state: SharedState) -> Response<BoxBody> {
    let state = state.lock().unwrap();
    let report = state.health();
    json_response(serde_json::to_value(&report).unwrap())
}

pub async fn handle_schema(_state: SharedState) -> Response<BoxBody> {
    // CUSTOMIZE: Update this when you add endpoints
    json_response(serde_json::json!({
        "endpoints": {
            "/diag/health":     { "method": "GET",  "description": "Structured subsystem health" },
            "/diag/schema":     { "method": "GET",  "description": "This endpoint — API self-description" },
            "/diag/ui/state":   { "method": "GET",  "description": "Semantic UI state" },
            "/diag/diff":       { "method": "POST", "description": "State diff over N steps", "params": ["steps", "filter"] },
            "/diag/assert":     { "method": "POST", "description": "Evaluate assertion", "params": ["expression"] },
            "/diag/smoke-test": { "method": "POST", "description": "Run smoke test sequence" },
            "/control/restart": { "method": "POST", "description": "Restart application" },
            "/control/reset":   { "method": "POST", "description": "Reset subsystem" },
            "/control/step":    { "method": "POST", "description": "Step simulation", "params": ["count"] }
        }
    }))
}

pub async fn handle_ui_state(state: SharedState) -> Response<BoxBody> {
    let state = state.lock().unwrap();
    json_response(serde_json::to_value(state.ui_state()).unwrap())
}

pub async fn handle_diff(state: SharedState, _body: Request<hyper::body::Incoming>) -> Response<BoxBody> {
    // CUSTOMIZE: Implement snapshot-before, step N, snapshot-after, compute deltas
    // Returns 501 until implemented — prevents agents from mistaking stubs for working endpoints
    error_response(StatusCode::NOT_IMPLEMENTED, "diff not implemented — CUSTOMIZE handle_diff in handlers.rs")
}

pub async fn handle_assert(state: SharedState, _body: Request<hyper::body::Incoming>) -> Response<BoxBody> {
    // CUSTOMIZE: Parse expression from body, evaluate against state
    // Returns 501 until implemented — prevents false-positive assertions
    error_response(StatusCode::NOT_IMPLEMENTED, "assert not implemented — CUSTOMIZE handle_assert in handlers.rs")
}

pub async fn handle_smoke_test(state: SharedState) -> Response<BoxBody> {
    // CUSTOMIZE: Define your smoke test checks
    let state = state.lock().unwrap();
    let health = state.health();

    json_response(serde_json::json!({
        "passed": 1,
        "failed": 0,
        "total": 1,
        "results": [
            { "name": "health_check", "status": "pass", "duration_ms": 1 }
        ],
        "note": "CUSTOMIZE: add your smoke test checks"
    }))
}

// ── Control Endpoints (mutations) ─────────────────────────────────────

pub async fn handle_restart(_state: SharedState) -> Response<BoxBody> {
    // CUSTOMIZE: Implement restart logic
    json_response(serde_json::json!({"status": "restarted"}))
}

pub async fn handle_reset(_state: SharedState, _body: Request<hyper::body::Incoming>) -> Response<BoxBody> {
    // CUSTOMIZE: Reset specific subsystem
    json_response(serde_json::json!({"status": "reset"}))
}

pub async fn handle_step(state: SharedState, _body: Request<hyper::body::Incoming>) -> Response<BoxBody> {
    // CUSTOMIZE: Step simulation by N
    let mut state = state.lock().unwrap();
    state.simulation.tick += 1;
    json_response(serde_json::json!({"tick": state.simulation.tick}))
}

// ── Router ────────────────────────────────────────────────────────────

pub async fn route(
    state: SharedState,
    req: Request<hyper::body::Incoming>,
) -> Result<Response<BoxBody>, std::convert::Infallible> {
    let path = req.uri().path().to_string();
    let method = req.method().clone();

    let response = match (method.as_str(), path.as_str()) {
        // Diagnostic (read-only)
        ("GET", "/diag/health")      => handle_health(state).await,
        ("GET", "/diag/schema")      => handle_schema(state).await,
        ("GET", "/diag/ui/state")    => handle_ui_state(state).await,
        ("POST", "/diag/diff")       => handle_diff(state, req).await,
        ("POST", "/diag/assert")     => handle_assert(state, req).await,
        ("POST", "/diag/smoke-test") => handle_smoke_test(state).await,

        // Control (mutations)
        ("POST", "/control/restart") => handle_restart(state).await,
        ("POST", "/control/reset")   => handle_reset(state, req).await,
        ("POST", "/control/step")    => handle_step(state, req).await,

        _ => error_response(StatusCode::NOT_FOUND, "endpoint not found — try GET /diag/schema"),
    };

    Ok(response)
}
```

**Step 4: Write main.rs template**

```rust
//! Diagnostic HTTP server — run alongside your application.
//!
//! CUSTOMIZE:
//! 1. Replace AppState with your actual state type
//! 2. Pass your app's shared state to the server
//! 3. Gate behind #[cfg(debug_assertions)] or a feature flag
//!
//! Usage: Launch this server on a separate tokio task alongside your main app.

mod handlers;
mod state;

use hyper_util::rt::TokioIo;
use state::{AppState, SharedState, SimulationState, UiState};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use tokio::net::TcpListener;

/// Default diagnostic server port. CUSTOMIZE as needed.
const DIAG_PORT: u16 = 9876;

/// Start the diagnostic server. Call this from your app's main function.
///
/// ```rust
/// // In your app's main():
/// let state = Arc::new(Mutex::new(app_state));
/// tokio::spawn(start_diag_server(state.clone()));
/// ```
pub async fn start_diag_server(state: SharedState) {
    let addr = SocketAddr::from(([127, 0, 0, 1], DIAG_PORT));
    let listener = TcpListener::bind(addr).await.expect("Failed to bind diagnostic server");
    eprintln!("Diagnostic server listening on http://{addr}");

    loop {
        let (stream, _) = listener.accept().await.expect("Failed to accept connection");
        let state = state.clone();
        tokio::spawn(async move {
            let io = TokioIo::new(stream);
            let service = hyper::service::service_fn(move |req| {
                handlers::route(state.clone(), req)
            });
            if let Err(err) = hyper::server::conn::http1::Builder::new()
                .serve_connection(io, service)
                .await
            {
                eprintln!("Diagnostic server error: {err}");
            }
        });
    }
}

// Example: standalone server for testing the template
#[tokio::main]
async fn main() {
    // CUSTOMIZE: Replace with your actual app state
    let state: SharedState = Arc::new(Mutex::new(AppState {
        simulation: SimulationState {
            tick: 0,
            entity_count: 0,
            running: true,
        },
        ui: UiState {
            active_view: "dashboard".to_string(),
            panels: HashMap::new(),
            selections: HashMap::new(),
            modal: None,
        },
    }));

    start_diag_server(state).await;
}
```

**Step 5: Write template README**

```markdown
# Rust/Hyper Diagnostic Server Template

Skeleton for a diagnostic HTTP server using hyper 1.x.

## Quick Start

1. Copy this directory into your project: `cp -r templates/rust-hyper/ your-project/tools/diag-server/`
2. Customize `src/state.rs` with your app's actual state types
3. Customize handlers in `src/handlers.rs`
4. Launch the server alongside your app (see `src/main.rs` for the pattern)

## Customization Points

Every file has `CUSTOMIZE:` comments marking where to adapt to your app.

### state.rs
- Replace `AppState` fields with your subsystem states
- Implement `health()` with real subsystem checks
- Add your state types with `#[derive(Clone, Serialize, Deserialize)]`

### handlers.rs
- Implement `handle_diff` with real snapshot/delta logic
- Implement `handle_assert` with an expression evaluator
- Add smoke test checks in `handle_smoke_test`
- Add control handlers for your app's specific actions

### main.rs
- Change `DIAG_PORT` if needed
- Gate with `#[cfg(debug_assertions)]` for dev-only
- Pass your app's actual `SharedState`

## Endpoints

| Endpoint | Method | Type |
|----------|--------|------|
| `/diag/health` | GET | Diagnostic |
| `/diag/schema` | GET | Diagnostic |
| `/diag/ui/state` | GET | Diagnostic |
| `/diag/diff` | POST | Diagnostic |
| `/diag/assert` | POST | Diagnostic |
| `/diag/smoke-test` | POST | Diagnostic |
| `/control/restart` | POST | Control |
| `/control/reset` | POST | Control |
| `/control/step` | POST | Control |
```

**Step 6: Commit**

```bash
git add interverse/interhelm/templates/rust-hyper/
git commit -m "feat(interhelm): add Rust/hyper diagnostic server templates"
```

<verify>
- run: `ls interverse/interhelm/templates/rust-hyper/src/*.rs | wc -l`
  expect: contains "3"
- run: `test -f interverse/interhelm/templates/rust-hyper/Cargo.toml && echo 'exists'`
  expect: contains "exists"
</verify>

---

### Task 9: CLI Client Templates (F9)

**Files:**
- Create: `interverse/interhelm/templates/cli/src/main.rs`
- Create: `interverse/interhelm/templates/cli/Cargo.toml`
- Create: `interverse/interhelm/templates/cli/README.md`

**Step 1: Write Cargo.toml**

```toml
[package]
name = "app-diag"  # CUSTOMIZE: rename to your-app-diag
version = "0.1.0"
edition = "2021"

[dependencies]
clap = { version = "4", features = ["derive"] }
reqwest = { version = "0.12", features = ["json", "blocking"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
colored = "2"
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
```

**Step 2: Write main.rs**

```rust
//! Diagnostic CLI client — thin wrapper around the diagnostic HTTP server.
//!
//! CUSTOMIZE: Rename the binary, add project-specific subcommands.
//!
//! Usage:
//!   app-diag health              # Show subsystem health
//!   app-diag ui                  # Show UI state
//!   app-diag diff [--steps N]    # Run state diff
//!   app-diag assert "<expr>"     # Evaluate assertion
//!   app-diag smoke-test          # Run smoke test
//!   app-diag watch [--interval]  # Poll health
//!   app-diag schema              # Show available endpoints

use clap::{Parser, Subcommand};
use colored::*;
use serde_json::Value;

/// CUSTOMIZE: Change the default port to match your diagnostic server.
const DEFAULT_BASE_URL: &str = "http://127.0.0.1:9876";

#[derive(Parser)]
#[command(name = "app-diag", about = "Diagnostic CLI for your application")]
struct Cli {
    /// Base URL of the diagnostic server
    #[arg(long, default_value = DEFAULT_BASE_URL)]
    url: String,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Show subsystem health status
    Health,
    /// Show semantic UI state
    Ui,
    /// Run state diff (snapshot before, step N, snapshot after)
    Diff {
        /// Number of steps to advance
        #[arg(default_value = "1")]
        steps: u64,
    },
    /// Evaluate an assertion expression against current state
    Assert {
        /// Expression to evaluate (e.g., "simulation.tick > 0")
        expression: String,
    },
    /// Run smoke test sequence
    SmokeTest,
    /// Poll health endpoint at interval
    Watch {
        /// Poll interval in seconds
        #[arg(long, default_value = "5")]
        interval: u64,
    },
    /// Show available endpoints
    Schema,
}

fn get(url: &str, path: &str) -> Result<Value, Box<dyn std::error::Error>> {
    let resp = reqwest::blocking::get(format!("{url}{path}"))?;
    Ok(resp.json()?)
}

fn post(url: &str, path: &str, body: Value) -> Result<Value, Box<dyn std::error::Error>> {
    let client = reqwest::blocking::Client::new();
    let resp = client.post(format!("{url}{path}")).json(&body).send()?;
    Ok(resp.json()?)
}

fn check_connectivity(url: &str) -> bool {
    reqwest::blocking::get(format!("{url}/diag/health")).is_ok()
}

fn print_health(data: &Value) {
    let status = data["status"].as_str().unwrap_or("unknown");
    let status_colored = match status {
        "healthy" => status.green().bold(),
        "degraded" => status.yellow().bold(),
        "unhealthy" => status.red().bold(),
        _ => status.dimmed(),
    };
    println!("Overall: {status_colored}");

    if let Some(subsystems) = data["subsystems"].as_object() {
        for (name, info) in subsystems {
            let sub_status = info["status"].as_str().unwrap_or("unknown");
            let sub_colored = match sub_status {
                "healthy" => "✓".green(),
                "degraded" => "⚠".yellow(),
                "unhealthy" => "✗".red(),
                _ => "?".dimmed(),
            };
            println!("  {sub_colored} {name}: {sub_status}");
            if let Some(details) = info["details"].as_object() {
                for (k, v) in details {
                    println!("      {k}: {v}");
                }
            }
        }
    }
}

fn print_smoke_test(data: &Value) {
    let passed = data["passed"].as_u64().unwrap_or(0);
    let failed = data["failed"].as_u64().unwrap_or(0);
    let total = data["total"].as_u64().unwrap_or(0);

    println!(
        "Smoke Test: {}/{} passed",
        if failed == 0 {
            passed.to_string().green().bold()
        } else {
            passed.to_string().yellow().bold()
        },
        total
    );

    if let Some(results) = data["results"].as_array() {
        for r in results {
            let name = r["name"].as_str().unwrap_or("?");
            let status = r["status"].as_str().unwrap_or("?");
            let ms = r["duration_ms"].as_u64().unwrap_or(0);
            let icon = if status == "pass" {
                "✓".green()
            } else {
                "✗".red()
            };
            print!("  {icon} {name} ({ms}ms)");
            if status != "pass" {
                if let Some(detail) = r["detail"].as_str() {
                    print!(" — {}", detail.red());
                }
            }
            println!();
        }
    }
}

fn main() {
    let cli = Cli::parse();

    if !check_connectivity(&cli.url) {
        eprintln!(
            "{} Cannot reach diagnostic server at {}",
            "Error:".red().bold(),
            cli.url
        );
        eprintln!("Is the application running with the diagnostic server enabled?");
        std::process::exit(1);
    }

    match cli.command {
        Commands::Health => match get(&cli.url, "/diag/health") {
            Ok(data) => print_health(&data),
            Err(e) => eprintln!("Error: {e}"),
        },
        Commands::Ui => match get(&cli.url, "/diag/ui/state") {
            Ok(data) => println!("{}", serde_json::to_string_pretty(&data).unwrap()),
            Err(e) => eprintln!("Error: {e}"),
        },
        Commands::Diff { steps } => {
            match post(&cli.url, "/diag/diff", serde_json::json!({"steps": steps})) {
                Ok(data) => println!("{}", serde_json::to_string_pretty(&data).unwrap()),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        Commands::Assert { expression } => {
            match post(
                &cli.url,
                "/diag/assert",
                serde_json::json!({"expression": expression}),
            ) {
                Ok(data) => {
                    let result = data["result"].as_bool().unwrap_or(false);
                    if result {
                        println!("{} {}", "PASS".green().bold(), expression);
                    } else {
                        println!("{} {}", "FAIL".red().bold(), expression);
                    }
                    if let Some(values) = data["values"].as_object() {
                        for (k, v) in values {
                            println!("  {k} = {v}");
                        }
                    }
                }
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        Commands::SmokeTest => match post(&cli.url, "/diag/smoke-test", serde_json::json!({})) {
            Ok(data) => print_smoke_test(&data),
            Err(e) => eprintln!("Error: {e}"),
        },
        Commands::Watch { interval } => {
            println!("Watching health every {interval}s (Ctrl+C to stop)...\n");
            loop {
                match get(&cli.url, "/diag/health") {
                    Ok(data) => {
                        print!("\x1B[2J\x1B[H"); // clear screen
                        print_health(&data);
                    }
                    Err(e) => eprintln!("Error: {e}"),
                }
                std::thread::sleep(std::time::Duration::from_secs(interval));
            }
        }
        Commands::Schema => match get(&cli.url, "/diag/schema") {
            Ok(data) => println!("{}", serde_json::to_string_pretty(&data).unwrap()),
            Err(e) => eprintln!("Error: {e}"),
        },
    }
}
```

**Step 3: Write template README**

```markdown
# Diagnostic CLI Client Template

Thin CLI wrapper for the diagnostic HTTP server.

## Quick Start

1. Copy into your project: `cp -r templates/cli/ your-project/tools/app-diag/`
2. Rename the binary in `Cargo.toml`
3. Update `DEFAULT_BASE_URL` if your server uses a different port
4. Build: `cargo build --release`

## Commands

```
app-diag health              # Formatted health table
app-diag ui                  # JSON UI state
app-diag diff [--steps N]    # State diff
app-diag assert "<expr>"     # Assertion with PASS/FAIL
app-diag smoke-test          # Smoke test sequence
app-diag watch [--interval]  # Poll health
app-diag schema              # Available endpoints
```

## Customization

- Add project-specific subcommands as `Commands` variants
- Customize formatters for your state types
- Add `--format json|table|compact` output modes
```

**Step 4: Commit**

```bash
git add interverse/interhelm/templates/cli/
git commit -m "feat(interhelm): add CLI client templates — clap, formatters, watch mode"
```

<verify>
- run: `test -f interverse/interhelm/templates/cli/src/main.rs && echo 'exists'`
  expect: contains "exists"
- run: `test -f interverse/interhelm/templates/cli/Cargo.toml && echo 'exists'`
  expect: contains "exists"
</verify>

---

### Task 10: Scripts and Structural Tests (F10)

**Files:**
- Create: `interverse/interhelm/scripts/bump-version.sh`
- Create: `interverse/interhelm/tests/pyproject.toml`
- Create: `interverse/interhelm/tests/structural/conftest.py`
- Create: `interverse/interhelm/tests/structural/test_structure.py`
- Create: `interverse/interhelm/tests/structural/test_skills.py`

**Step 1: Write bump-version.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: bump-version.sh <version>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

# Update plugin.json
cd "$ROOT"
python3 -c "
import json, sys
with open('.claude-plugin/plugin.json', 'r+') as f:
    d = json.load(f)
    d['version'] = '$VERSION'
    f.seek(0)
    json.dump(d, f, indent=2)
    f.write('\n')
    f.truncate()
"
echo "Bumped to $VERSION"
```

**Step 2: Make script executable**

Run: `chmod +x interverse/interhelm/scripts/bump-version.sh`

**Step 3: Write pyproject.toml**

```toml
[project]
name = "interhelm-tests"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["pytest>=8.0", "pyyaml>=6.0"]

[tool.pytest.ini_options]
testpaths = ["structural"]
pythonpath = ["structural"]
```

**Step 4: Write conftest.py**

```python
"""Shared fixtures for structural tests."""

import json
from pathlib import Path

import pytest


@pytest.fixture(scope="session")
def project_root() -> Path:
    """Path to the repository root."""
    return Path(__file__).resolve().parent.parent.parent


@pytest.fixture(scope="session")
def skills_dir(project_root: Path) -> Path:
    return project_root / "skills"


@pytest.fixture(scope="session")
def agents_dir(project_root: Path) -> Path:
    return project_root / "agents"


@pytest.fixture(scope="session")
def scripts_dir(project_root: Path) -> Path:
    return project_root / "scripts"


@pytest.fixture(scope="session")
def plugin_json(project_root: Path) -> dict:
    """Parsed plugin.json."""
    with open(project_root / ".claude-plugin" / "plugin.json") as f:
        return json.load(f)
```

**Step 5: Write test_structure.py**

```python
"""Tests for plugin structure."""

import json
import os
from pathlib import Path


def test_plugin_json_valid(project_root):
    """plugin.json is valid JSON with required fields."""
    path = project_root / ".claude-plugin" / "plugin.json"
    assert path.exists(), "Missing .claude-plugin/plugin.json"
    data = json.loads(path.read_text())
    for field in ("name", "version", "description", "author"):
        assert field in data, f"plugin.json missing required field: {field}"
    assert data["name"] == "interhelm"


def test_plugin_json_skills_match_filesystem(project_root, plugin_json):
    """Every skill listed in plugin.json exists on disk."""
    for skill_path in plugin_json.get("skills", []):
        resolved = project_root / skill_path
        assert resolved.is_dir(), f"Skill dir not found: {skill_path}"
        assert (resolved / "SKILL.md").exists(), f"Missing SKILL.md in {skill_path}"


def test_plugin_json_agents_match_filesystem(project_root, plugin_json):
    """Every agent listed in plugin.json exists on disk."""
    for agent_path in plugin_json.get("agents", []):
        resolved = project_root / agent_path
        assert resolved.exists(), f"Agent not found: {agent_path}"


def test_required_root_files(project_root):
    """All required root-level files exist."""
    required = ["CLAUDE.md", "PHILOSOPHY.md", "LICENSE", ".gitignore", "README.md", "AGENTS.md"]
    for name in required:
        assert (project_root / name).exists(), f"Missing required file: {name}"


def test_hooks_json_valid(project_root):
    """hooks.json is valid JSON with correct structure."""
    path = project_root / "hooks" / "hooks.json"
    assert path.exists(), "Missing hooks/hooks.json"
    data = json.loads(path.read_text())
    assert "hooks" in data, "hooks.json missing 'hooks' key"
    # Validate event names are valid Claude Code hook events
    valid_events = {
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
        "PostToolUse", "PostToolUseFailure", "Notification", "SubagentStart",
        "SubagentStop", "Stop", "TeammateIdle", "TaskCompleted", "PreCompact",
        "SessionEnd",
    }
    for event in data["hooks"]:
        assert event in valid_events, f"Invalid hook event: {event}"


def test_hooks_scripts_executable(project_root):
    """All hook shell scripts are executable."""
    hooks_dir = project_root / "hooks"
    for script in hooks_dir.glob("*.sh"):
        assert os.access(script, os.X_OK), f"Hook script not executable: {script.name}"


def test_scripts_executable(project_root):
    """All shell scripts are executable."""
    scripts_dir = project_root / "scripts"
    if not scripts_dir.is_dir():
        return
    for script in scripts_dir.glob("*.sh"):
        assert os.access(script, os.X_OK), f"Script not executable: {script.name}"


def test_templates_exist(project_root):
    """Template directories exist with expected files."""
    rust_dir = project_root / "templates" / "rust-hyper"
    assert rust_dir.is_dir(), "Missing templates/rust-hyper/"
    assert (rust_dir / "Cargo.toml").exists(), "Missing rust-hyper/Cargo.toml"
    assert (rust_dir / "src" / "main.rs").exists(), "Missing rust-hyper/src/main.rs"

    cli_dir = project_root / "templates" / "cli"
    assert cli_dir.is_dir(), "Missing templates/cli/"
    assert (cli_dir / "Cargo.toml").exists(), "Missing cli/Cargo.toml"
    assert (cli_dir / "src" / "main.rs").exists(), "Missing cli/src/main.rs"
```

**Step 6: Write test_skills.py**

```python
"""Tests for skill content."""

import yaml
from pathlib import Path


def test_skill_count(skills_dir):
    """Expected number of skills."""
    skills = list(skills_dir.glob("*/SKILL.md"))
    assert len(skills) == 3, (
        f"Expected 3 skills, found {len(skills)}: {[s.parent.name for s in skills]}"
    )


def test_skill_frontmatter(skills_dir):
    """Each SKILL.md has valid YAML frontmatter with required fields."""
    for skill_md in skills_dir.glob("*/SKILL.md"):
        content = skill_md.read_text()
        assert content.startswith("---"), f"{skill_md}: missing frontmatter"
        # Extract frontmatter
        parts = content.split("---", 2)
        assert len(parts) >= 3, f"{skill_md}: malformed frontmatter"
        fm = yaml.safe_load(parts[1])
        assert "name" in fm, f"{skill_md}: frontmatter missing 'name'"
        assert "description" in fm, f"{skill_md}: frontmatter missing 'description'"
        # Name should match directory name
        assert fm["name"] == skill_md.parent.name, (
            f"{skill_md}: name '{fm['name']}' doesn't match dir '{skill_md.parent.name}'"
        )


def test_agent_count(agents_dir):
    """Expected number of agents."""
    agents = list(agents_dir.rglob("*.md"))
    assert len(agents) == 1, (
        f"Expected 1 agent, found {len(agents)}: {[a.name for a in agents]}"
    )


def test_agent_frontmatter(agents_dir):
    """Each agent .md has valid YAML frontmatter."""
    for agent_md in agents_dir.rglob("*.md"):
        content = agent_md.read_text()
        assert content.startswith("---"), f"{agent_md}: missing frontmatter"
        parts = content.split("---", 2)
        assert len(parts) >= 3, f"{agent_md}: malformed frontmatter"
        fm = yaml.safe_load(parts[1])
        assert "name" in fm, f"{agent_md}: frontmatter missing 'name'"
        assert "description" in fm, f"{agent_md}: frontmatter missing 'description'"
        assert "model" in fm, f"{agent_md}: frontmatter missing 'model'"
```

**Step 7: Run tests**

Run: `cd interverse/interhelm/tests && uv run pytest -q`
Expected: All tests pass

**Step 8: Commit**

```bash
git add interverse/interhelm/scripts/ interverse/interhelm/tests/
git commit -m "feat(interhelm): add bump-version script and structural test suite"
```

<verify>
- run: `cd interverse/interhelm/tests && uv run pytest -q 2>&1 | tail -1`
  expect: contains "passed"
</verify>

---

### Task 11: Final Validation and Close

**Step 1: Run full structural test suite**

Run: `cd interverse/interhelm/tests && uv run pytest -v`
Expected: All tests pass

**Step 2: Validate plugin.json**

Run: `python3 -c "import json; d=json.load(open('interverse/interhelm/.claude-plugin/plugin.json')); print(f'Skills: {len(d[\"skills\"])}, Agents: {len(d[\"agents\"])}')"`
Expected: `Skills: 3, Agents: 1`

**Step 3: Validate hooks.json**

Run: `python3 -c "import json; d=json.load(open('interverse/interhelm/hooks/hooks.json')); print(f'Hook events: {list(d[\"hooks\"].keys())}')"`
Expected: `Hook events: ['PostToolUse']`

**Step 4: Check all required files exist**

Run:
```bash
echo "=== Required Files ===" && \
for f in CLAUDE.md AGENTS.md PHILOSOPHY.md README.md LICENSE .gitignore; do \
  test -f "interverse/interhelm/$f" && echo "✓ $f" || echo "✗ $f MISSING"; \
done && \
echo "=== Components ===" && \
echo "Skills: $(ls interverse/interhelm/skills/*/SKILL.md | wc -l)" && \
echo "Agents: $(ls interverse/interhelm/agents/review/*.md | wc -l)" && \
echo "Hooks: $(ls interverse/interhelm/hooks/*.sh | wc -l)" && \
echo "Templates: $(ls -d interverse/interhelm/templates/*/ | wc -l)"
```

**Step 5: Commit final state (if any changes)**

```bash
git add interverse/interhelm/
git commit -m "feat(interhelm): v0.1.0 — agent-as-operator runtime diagnostics plugin"
```

<verify>
- run: `cd interverse/interhelm/tests && uv run pytest -q 2>&1 | tail -1`
  expect: contains "passed"
- run: `python3 -c "import json; d=json.load(open('interverse/interhelm/.claude-plugin/plugin.json')); assert d['version']=='0.1.0'; assert len(d['skills'])==3; assert len(d['agents'])==1; print('ALL OK')"`
  expect: contains "ALL OK"
</verify>
