---
artifact_type: reflection
bead: Demarch-6i0.2
stage: reflect
category: patterns
title: Hook system adapter pattern and security layering
date: 2026-03-12
keywords: [hooks, adapter-pattern, fail-open, credential-stripping, agentloop]
---

# Hook System: Adapter Pattern and Security Layering

## What Was Built

Skaffen hook system with 4 lifecycle events (SessionStart, PreToolUse, PostToolUse, Notification),
two-level config merge (user-global + per-project), and security-oriented tool gating. 8 commits,
~1100 insertions across 12 files, 14 new tests.

## Key Pattern: Three-Layer Hook Adapter

The hook system spans three packages with deliberate decoupling:

1. **`hooks/`** — self-contained, no agent system dependencies. Types use `Decision` enum.
2. **`agentloop/`** — defines `HookRunner` with `string` returns. No import of `hooks/`.
3. **`agent/`** — `hookAdapter` bridges typed `Decision` to string, matching existing
   `routerAdapter`/`sessionAdapter`/`emitterAdapter` pattern.

**Why this matters:** When quality gates flagged the duplicate `HookRunner` interface (hooks/ had
its own that was never consumed polymorphically), we deleted it without touching any other package.
The layering contained the blast radius.

**How to apply:** Any new cross-layer feature in Skaffen should follow this pattern: self-contained
implementation package → agentloop interface using primitives → agent adapter bridging types.

## Lesson: Fail-Open vs Fail-Closed is Per-Hook Policy

Initial implementation used global fail-open semantics (hook crash → allow). Quality gates correctly
identified this as a P0: security hooks (deny-lists, approval gates) need fail-closed behavior.

**Fix:** Added `on_error` field to `HookDef` — `"allow"` (default, backward compat) or `"deny"`
(fail-closed for security hooks).

**How to apply:** When building any gating system, always ask: "What should happen when the gate
itself fails?" The answer is rarely one-size-fits-all. Make it configurable per-gate.

## Lesson: Credential Stripping Needs Suffix Patterns

Initial `safeEnv()` used a static prefix blocklist (5 entries). Quality gates flagged this as
incomplete — real environments have `GITLAB_TOKEN`, custom `*_SECRET` vars, etc.

**Fix:** Added suffix matching (`_SECRET`, `_TOKEN`, `_API_KEY`, `_PASSWORD`) plus proper key
parsing (split on `=`, match key only). Catches unknowable custom credentials.

**How to apply:** For any env-stripping or credential-filtering code, suffix patterns catch the
long tail that prefix lists miss. Always parse the key before matching — never match against
raw `KEY=VALUE` strings.

## Lesson: Headless Mode Needs Explicit "Ask" Handling

Hooks can return "ask" to escalate to human approval. In TUI mode, the trust evaluator handles
this. In headless (print) mode, there's no approver — "ask" silently degraded to "allow".

**Fix:** When `decision == "ask"` and no approver is registered, deny the tool call with an
explicit error message.

**How to apply:** Any permission system with an "escalate to human" path must define what happens
when no human is available. The safe default is deny, not allow.

## Quality Gate Stats

- 4 agents dispatched (architecture, quality, safety, correctness)
- 2 P0 found and fixed (safeEnv, fail-open bypass)
- 4 P1 found (3 fixed, 1 deferred: goroutine bounding)
- 6 P2 documented for follow-up
- All 540 tests pass after fixes
