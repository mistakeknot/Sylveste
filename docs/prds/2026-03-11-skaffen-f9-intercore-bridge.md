---
artifact_type: prd
bead: Demarch-j2f
stage: design
---

# PRD: Skaffen v0.3 — Intercore Bridge + Interspect Evidence

## Problem

Skaffen emits evidence locally (JSONL files) but doesn't feed it to Intercore. The existing bridge code has 3 bugs that prevent any data from reaching Interspect. Routing decisions are unaudited. There's no way for Interspect to steer Skaffen's model selection via overrides.

## Solution

Fix the Intercore bridge, make `ic` a mandatory dependency, record all routing decisions, and consume routing overrides from Intercore. This closes the feedback loop: Skaffen emits evidence → Interspect analyzes → Interspect proposes overrides → Skaffen honors them.

## Features

### F1: Mandatory ic Startup Check

**What:** Skaffen requires `ic` (Intercore CLI) on PATH and validates connectivity at startup.

**Acceptance criteria:**
- [ ] `main.go` calls `exec.LookPath("ic")` before creating the agent; exits with clear error if not found
- [ ] Runs `ic health` to verify Intercore DB is accessible; exits with clear error if health check fails
- [ ] Both `runPrint()` and `runTUI()` perform the check
- [ ] Error message includes: what's missing, how to install ic

### F2: Fix Emitter Bridge

**What:** Correct the 3 bugs in `evidence/emitter.go` that prevent events from reaching Intercore.

**Acceptance criteria:**
- [ ] Source changed from `--source=skaffen` to `--source=interspect`
- [ ] Flag changed from `--data=` to `--payload=`
- [ ] Payload includes `agent_name: "skaffen"` field (required by Intercore's interspect source)
- [ ] Payload wraps Evidence struct as JSON in the `context` field
- [ ] `--type=` flag set to appropriate event type (e.g., `turn_complete`)
- [ ] `--session=` flag passes the session ID
- [ ] Remove conditional `if e.icPath != ""` — ic is now mandatory (always available)
- [ ] Test verifies correct CLI args are constructed

### F3: Routing Decision Recording

**What:** Record every `SelectModel()` call to Intercore via `ic route record`.

**Acceptance criteria:**
- [ ] After `SelectModel()` returns, fire-and-forget `ic route record` with: agent, model, rule (reason), phase, session, complexity tier
- [ ] Recording is async (goroutine) — must not block the agent loop
- [ ] Recording failures are logged but don't fail the turn
- [ ] Router exposes a `RecordDecision()` method or the agent loop calls it after `SelectModel()`
- [ ] Test verifies correct CLI args for route record

### F4: Override Consumption

**What:** Router queries `ic route model` for per-phase overrides and inserts them in the resolution chain.

**Acceptance criteria:**
- [ ] Router queries `ic route model --phase=<p> --agent=skaffen --json` at session start (once, cached)
- [ ] Override result cached for the session lifetime (no per-turn subprocess)
- [ ] Resolution chain order: budget > complexity > env > **ic override** > config > default
- [ ] Empty/error response from ic means "no override" — falls through to config
- [ ] `SelectModel()` returns reason `"intercore-override"` when an override is applied
- [ ] Test with mock ic response verifies override is applied correctly

### F5: Richer Evidence Signals

**What:** Extend evidence emission with outcome signals and routing metadata.

**Acceptance criteria:**
- [ ] Evidence struct gets new fields: `Model string`, `ModelReason string` (from SelectModel)
- [ ] Emitter includes `--type=turn_complete` for per-turn events
- [ ] Emitter includes `--type=session_end` for final summary event
- [ ] Session-end event includes: total turns, total tokens, final outcome, budget state
- [ ] Agent loop calls `Emit()` with model/reason populated from router

## Non-goals

- **Interspect calibration pipeline** — consuming evidence to propose overrides is Demarch-g3a
- **Override v2 phases array format** — we consume whatever `ic route model` returns; format definition lives in Intercore
- **Automatic override proposal** — requires the calibration pipeline
- **Per-tool evidence** — tool-level signals (which tools failed, which succeeded) are future work
- **Override UI/management** — Interspect plugins handle override CRUD

## Dependencies

- `ic` binary on PATH (Intercore CLI v0.3+)
- Intercore DB accessible (`ic health` returns ok)
- `ic events record --source=interspect` supports the payload schema (already implemented)
- `ic route record` and `ic route model` commands (already implemented)

## Open Questions

1. **Override cache invalidation** — caching per-session is simple but means mid-session override changes aren't picked up. Acceptable for v0.3?
2. **Event type taxonomy** — using `turn_complete` and `session_end` for now. Should we register these as known types in Intercore, or is free-form acceptable?
