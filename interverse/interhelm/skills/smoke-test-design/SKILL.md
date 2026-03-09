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
