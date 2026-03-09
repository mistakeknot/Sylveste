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
