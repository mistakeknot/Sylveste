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

## Skills

| Skill | What it does |
|-------|-------------|
| `runtime-diagnostics` | Guides scaffolding of diagnostic HTTP server with Health, Diff, Assert, Smoke Test patterns + UI state |
| `smoke-test-design` | Teaches executable contract pattern — smoke tests as agreement between server and client |
| `cuj-verification` | Screenshot-free CUJ validation via structured `/diag/ui/state` queries |

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
