---
artifact_type: brainstorm
bead: Sylveste-ekh
stage: discover
---

# Interhelm: Agent-as-Operator Runtime Diagnostics

**Bead:** Sylveste-ekh
**GitHub Issue:** #7

## What We're Building

An Interverse plugin that teaches agents to observe and control running applications via diagnostic HTTP servers and CLI tools. The "agent-as-operator" pattern — agents don't just write code, they verify the running application behaves correctly without relying on screenshots or browser automation.

**Core problem:** The Interverse has plugins for code-time quality (intertest, intercheck, intertrace) but nothing for runtime observability. When agents make code changes to complex native apps (Tauri, Electron, CLI tools), they have no structured way to verify runtime behavior. Currently they either rely on test suites (which don't cover runtime integration) or attempt browser tools (which don't work with native apps).

**Killer feature:** Structured UI state observability. Instead of taking screenshots and OCR-ing them, agents query `/diag/ui/state` for semantic JSON — active view, panel states, selections, form values. Near-zero token cost vs. screenshot-heavy workflows.

## Why This Approach

**Mix of three strategies:**

1. **Distilled templates** — Generalizable Rust/hyper diagnostic server skeletons and CLI client templates in `templates/`. Agents customize to each project's state shape. Avoids the boilerplate generation problem (hyper routing, derive macros, state extraction are non-trivial to get right from scratch).

2. **Rich pattern docs** — Skills teach the *why* and *when* of each pattern, not just the *how*. Framework-agnostic guidance that works for Tauri, Electron, web apps, CLI tools.

3. **Reference lineage** — The patterns are battle-tested from Shadow Work's `sw-agent` + Rust debug server, which diagnosed a P0 desync bug where `restart_simulation` failed to reset ~25 state fields. Templates are distilled from this real implementation.

## Key Decisions

### Four Core Patterns (from Shadow Work)

| Pattern | What It Does | Endpoint Convention |
|---------|-------------|-------------------|
| **Health** | Structured pass/fail per subsystem | `GET /diag/health` |
| **Diff** | Snapshot state, take action, show deltas | `POST /diag/diff` |
| **Assert** | Scriptable verification expressions | `POST /diag/assert` |
| **Smoke Test** | End-to-end flow verification (executable contract) | `POST /diag/smoke-test` |

### UI Observability (Layered, V0.1 = Layer 1)

| Layer | Pattern | V0.1? | Description |
|-------|---------|-------|-------------|
| 1 | **Semantic UI state API** | Yes | `/diag/ui/state` returns structured JSON: active view, panel states, selections, form values. Replaces most screenshot needs. |
| 2 | **Accessibility tree export** | Follow-up | Serialize the app's accessibility tree. Less custom instrumentation, noisier output, framework-dependent. |
| 3 | **Event stream + assertions** | Follow-up | Structured event stream (user actions, state transitions, renders). Agent subscribes and asserts. Most powerful for temporal CUJs. |

### Endpoint Architecture

- `/diag/*` — Read-only observations (health, state, UI, schema)
- `/control/*` — Mutations (restart, reset, step simulation)
- `/diag/schema` — Self-describing API (agents discover available endpoints)
- `/diag/health` — Structured subsystem checks with pass/fail
- `/diag/ui/state` — Semantic UI state (the screenshot killer)

### Plugin Components

**Skills (3):**
- `runtime-diagnostics/SKILL.md` — Guides agents to scaffold a diagnostic HTTP server + CLI for their project. Covers all 4 patterns + UI state endpoint.
- `smoke-test-design/SKILL.md` — Teaches the executable contract pattern (smoke test as agreement between server and client).
- (implied) CUJ verification skill — how to use diagnostic endpoints to verify critical user journeys without screenshots.

**Agent (1):**
- `runtime-reviewer` — Full operational review of debug server implementations:
  - **Pattern completeness**: All 4 core patterns implemented + UI state endpoint + schema endpoint for self-description
  - **Security**: Diagnostic endpoints are dev-only (not in production builds), no sensitive data leaks in state dumps, control endpoints have guards
  - **Performance**: State serialization doesn't block main thread, health checks have timeouts, diff snapshots are bounded in size

**Hooks (3):**
1. **Browser-on-native detection** (PostToolUse) — Catches agents trying to use browser automation tools against native apps and suggests the diagnostic CLI instead.
2. **Auto-health-check** (PostToolUse) — After code changes to Rust/Tauri source files, auto-runs health check to catch regressions immediately.
3. **CUJ reminder** (PostToolUse) — After completing a feature, reminds agents to run CUJ verification via the diagnostic workflow.

**Templates:**
- `templates/rust-hyper/` — Diagnostic server skeleton: hyper routes, health check structure, diff snapshots, assert expression parser, UI state endpoint
- `templates/cli/` — Thin CLI client wrapper with formatters, REPL mode, watch mode, connectivity check

### Design Principles

- **Standalone plugin** — No intercore dependency. The pattern works for any app.
- **Framework-agnostic** — Skills guide scaffolding for Tauri, Electron, web apps, CLI tools.
- **The skill teaches the pattern, not the implementation** — Agents generate the debug server and CLI for each project, guided by templates and patterns.
- **Structured over visual** — Prefer JSON state queries over screenshots. Near-zero token cost, deterministic, parseable.

### Naming

"Helm" — at the helm, steering the running application. Operator role, not just observer. Banks-adjacent nautical resonance (Culture ships).

## Open Questions

1. **Template language support** — V0.1 ships Rust/hyper templates. Should Python (Flask/FastAPI) templates follow in v0.2, or are they a separate concern?
2. **CUJ integration with interpath** — interpath already defines CUJs. How tightly should interhelm's verification endpoints integrate with interpath's CUJ format?
3. **Discovery mechanism** — How does an agent know a project has a diagnostic server available? Convention (check for `/diag/schema` on a known port)? Project config?
4. **State diff granularity** — Should diff snapshots capture all state or allow filtering by subsystem? The Shadow Work implementation captures everything, which gets verbose for large apps.

## Follow-Up Beads (to create after v0.1)

- Accessibility tree export pattern (Layer 2 UI observability)
- Event stream + assertions pattern (Layer 3 UI observability)
- Python/Flask diagnostic server templates
- interpath CUJ integration
