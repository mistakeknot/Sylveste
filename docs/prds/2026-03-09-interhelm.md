---
artifact_type: prd
bead: Demarch-ekh
stage: design
---

# PRD: Interhelm — Agent-as-Operator Runtime Diagnostics

## Problem

Agents can write and test code but have no structured way to verify running application behavior. For complex native apps (Tauri, Electron, CLI tools), screenshot-based debugging is slow, token-expensive, and lossy. There is no Interverse plugin for runtime observability.

## Solution

An Interverse plugin that teaches agents the "agent-as-operator" pattern: scaffold diagnostic HTTP servers and CLI tools that expose structured runtime state (including UI state) for any application. Agents query JSON endpoints instead of taking screenshots.

## Features

### F1: Runtime Diagnostics Skill
**What:** Skill that guides agents to scaffold a diagnostic HTTP server with all 4 core patterns plus UI state endpoint.
**Acceptance criteria:**
- [ ] SKILL.md in `skills/runtime-diagnostics/` with YAML frontmatter
- [ ] Covers Health, Diff, Assert, Smoke Test patterns with endpoint conventions
- [ ] Includes `/diag/ui/state` semantic UI state pattern
- [ ] Includes `/diag/schema` self-describing API pattern
- [ ] Framework-agnostic guidance (Tauri, Electron, web, CLI examples)
- [ ] References templates in `templates/` for concrete starting points

### F2: Smoke Test Design Skill
**What:** Skill teaching the executable contract pattern — smoke tests as the agreement between diagnostic server and CLI client.
**Acceptance criteria:**
- [ ] SKILL.md in `skills/smoke-test-design/` with YAML frontmatter
- [ ] Explains smoke test as executable contract (not just end-to-end test)
- [ ] Shows how to define verification points per subsystem
- [ ] Includes pass/fail reporting format

### F3: CUJ Verification Skill
**What:** Skill teaching how to use diagnostic endpoints to verify critical user journeys without screenshots.
**Acceptance criteria:**
- [ ] SKILL.md in `skills/cuj-verification/` with YAML frontmatter
- [ ] Shows how to map CUJ steps to `/diag/ui/state` queries
- [ ] Demonstrates state-before → action → state-after verification pattern
- [ ] Explains when screenshots are still needed vs. when structured queries suffice

### F4: Runtime Reviewer Agent
**What:** Agent that reviews debug server implementations for pattern completeness, security, and performance.
**Acceptance criteria:**
- [ ] Agent definition in `agents/review/runtime-reviewer.md` with YAML frontmatter
- [ ] Checks all 4 core patterns + UI state + schema endpoints exist
- [ ] Verifies diagnostic endpoints are dev-only (not in production builds)
- [ ] Checks for sensitive data leaks in state dumps
- [ ] Checks control endpoint guards
- [ ] Verifies state serialization doesn't block main thread
- [ ] Checks health check timeouts and diff snapshot size bounds

### F5: Browser-on-Native Hook
**What:** PostToolUse hook that detects agents using browser automation tools against native apps and suggests the diagnostic CLI instead.
**Acceptance criteria:**
- [ ] Hook in `hooks/hooks.json` targeting PostToolUse
- [ ] Detects screenshot/browser automation tool usage
- [ ] Suggests diagnostic CLI alternative in hook output
- [ ] Only triggers when project has diagnostic server configured

### F6: Auto-Health-Check Hook
**What:** PostToolUse hook that auto-runs health check after code changes to Rust/Tauri source files.
**Acceptance criteria:**
- [ ] Hook in `hooks/hooks.json` targeting PostToolUse on Edit/Write tools
- [ ] Triggers only for Rust/Tauri source file changes (`.rs` files in `src-tauri/`)
- [ ] Runs health check via diagnostic CLI
- [ ] Reports regressions without blocking the agent

### F7: CUJ Reminder Hook
**What:** PostToolUse hook that reminds agents to run CUJ verification after completing a feature.
**Acceptance criteria:**
- [ ] Hook in `hooks/hooks.json` targeting PostToolUse
- [ ] Triggers after significant code changes (heuristic: multiple files edited)
- [ ] Reminder is a suggestion, not a blocker
- [ ] Only triggers when project has CUJs defined

### F8: Rust/Hyper Server Templates
**What:** Diagnostic server skeleton with hyper routes for all patterns.
**Acceptance criteria:**
- [ ] Template files in `templates/rust-hyper/`
- [ ] Hyper route setup for `/diag/health`, `/diag/diff`, `/diag/assert`, `/diag/smoke-test`, `/diag/ui/state`, `/diag/schema`
- [ ] Control endpoint routes at `/control/*`
- [ ] Placeholder types for app-specific state
- [ ] Derive macro guidance (Clone, Serialize, Deserialize)
- [ ] Comments explaining customization points

### F9: CLI Client Templates
**What:** Thin CLI client wrapper with formatters and modes.
**Acceptance criteria:**
- [ ] Template files in `templates/cli/`
- [ ] Health, diff, assert, smoke-test, ui-state subcommands
- [ ] Formatted output (table, JSON, colored pass/fail)
- [ ] Watch mode (poll health endpoint)
- [ ] Connectivity check on startup
- [ ] REPL mode for interactive diagnosis

### F10: Plugin Scaffold
**What:** Standard Interverse plugin structure with all required files.
**Acceptance criteria:**
- [ ] `.claude-plugin/plugin.json` with correct component references
- [ ] `CLAUDE.md` — overview, quick commands, design decisions
- [ ] `AGENTS.md` — development guide, integration points
- [ ] `PHILOSOPHY.md` — purpose, north star, doctrine
- [ ] `README.md` — user-facing documentation
- [ ] `LICENSE` — MIT
- [ ] `.gitignore` — standard excludes
- [ ] `scripts/bump-version.sh`
- [ ] `tests/` — structural test suite (pytest)

## Non-goals

- **No runtime code in the plugin itself** — interhelm teaches patterns and provides templates, it doesn't ship a running diagnostic server
- **No accessibility tree export (v0.1)** — Layer 2 UI observability deferred to follow-up bead
- **No event stream pattern (v0.1)** — Layer 3 UI observability deferred to follow-up bead
- **No Python/Flask templates (v0.1)** — Rust/hyper only for initial release
- **No interpath CUJ format integration (v0.1)** — CUJ verification skill is standalone initially
- **No intercore dependency** — plugin is standalone

## Dependencies

- Plugin standard: `docs/canon/plugin-standard.md`
- Reference patterns: Shadow Work `sw-agent` + debug server (external, for reference only)
- Existing plugin examples: intertest (skills), interlock (hooks), interflux (agents)

## Open Questions

1. **Discovery mechanism** — How does an agent know a project has a diagnostic server? Convention (port scan for `/diag/schema`)? Project CLAUDE.md annotation? Decided during planning.
2. **State diff granularity** — Full state vs. subsystem filtering. Default to full state with optional filter parameter.
