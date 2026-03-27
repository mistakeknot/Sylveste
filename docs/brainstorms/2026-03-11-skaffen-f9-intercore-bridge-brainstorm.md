---
artifact_type: brainstorm
bead: Sylveste-j2f
stage: discover
---

# Skaffen v0.3: Intercore Bridge + Interspect Evidence

**Bead:** Sylveste-j2f

## What We're Building

Connect Skaffen's agent loop to Intercore so that:

1. **Evidence flows out** — every turn emits structured events to Intercore via `ic events record --source=interspect`, enabling Interspect to analyze agent behavior patterns
2. **Routing decisions are auditable** — every `SelectModel()` call records its decision via `ic route record`, creating a full audit trail for model selection
3. **Routing overrides flow in** — the router consumes overrides from `ic route model`, allowing Interspect (or manual operators) to steer model selection per phase/agent

This closes the feedback loop: Skaffen emits evidence → Interspect analyzes it → Interspect proposes overrides → Skaffen honors them.

## Why This Approach

### Fix in-place, don't create new packages

The existing `evidence/emitter.go` already has the structure — JSONL writing + ic bridge. It has 3 bugs in the bridge (wrong source, wrong flags, missing field) but the architecture is sound. Fixing in-place avoids indirection and keeps the evidence path in one file.

### ic as mandatory dependency

Rather than conditional bridging with fallback paths, Skaffen v0.3 requires `ic` on PATH and fails at startup if absent. This eliminates all `if icPath != ""` conditionals in the hot path and ensures every Skaffen session produces Intercore data. The ic binary is lightweight (single Go binary, no daemon) and is already available in all Sylveste development environments.

### Both providers support model steering

The decision gate from the original bead ("can ClaudeCodeProvider honor routing overrides?") is resolved: the claude-code provider already passes `--model <model>` to the Claude CLI (line 82-84 of claudecode.go). The Anthropic provider uses it in the API request. Overrides will be honored by both providers.

## Key Decisions

1. **Architecture: fix emitter in-place** — no new packages. The emitter fixes its 3 bridge bugs and adds routing decision recording. The router adds override consumption.

2. **Override priority: env > overrides > config > defaults** — environment variables remain the human escape hatch (highest priority). Interspect/manual overrides sit between env and config file. This means `SKAFFEN_MODEL_BUILD=opus` always wins.

3. **Record all routing decisions** — every `SelectModel()` call records to `ic route record`, not just "interesting" ones. Interspect needs the full dataset to detect patterns (e.g., "agent X always gets sonnet but performs badly on complex tasks").

4. **ic is mandatory** — Skaffen fails at startup if `ic` is not on PATH. No fallback file, no graceful degradation. This simplifies all bridge code to assume ic is always available.

5. **Claude-code provider already works** — `--model` flag is passed through. Decision gate resolved without code changes to the provider.

## Scope

### In scope
- Fix emitter bridge: correct source (`interspect`), correct flag (`--payload=`), add `agent_name`
- Add `ic health` check at Skaffen startup (fail if absent)
- Record routing decisions via `ic route record` after every `SelectModel()`
- Consume overrides from `ic route model --phase=<p> --agent=skaffen`
- Add override step to router resolution chain
- Emit richer evidence: outcome signals (from agent.Evidence), session/bead context
- Tests for all new paths

### Out of scope (separate beads)
- Interspect calibration pipeline (F3b, Sylveste-g3a) — consumes the evidence we emit
- Evidence-derived automatic overrides — requires calibration pipeline
- Override v2 phases array format — consumed as-is from ic, no need to define the format here

## Technical Details

### Intercore CLI Interface

**Evidence emission** (fix existing bridge):
```
ic events record \
  --source=interspect \
  --type=<event_type> \
  --payload='{"agent_name":"skaffen","context":"<evidence_json>"}' \
  --session=<session_id>
```

**Routing decision recording** (new):
```
ic route record \
  --agent=skaffen \
  --model=<selected_model> \
  --rule=<reason> \
  --phase=<phase> \
  --session=<session_id> \
  --complexity=<tier>
```

**Override query** (new):
```
ic route model --phase=<phase> --agent=skaffen
# Returns: model ID or empty (no override)
```

### Router Resolution Chain (updated)

```
1. Budget degradation (overrides everything when exhausted)
2. Complexity override (shadow or enforce)
3. Env var: SKAFFEN_MODEL_<PHASE>
4. Intercore override: ic route model --phase=<p> --agent=skaffen  ← NEW
5. Config file: routing.json phases map
6. Phase default: phaseDefaults map
```

### Evidence Schema Mapping

Current `agent.Evidence` struct → Interspect payload:
- `agent_name`: "skaffen" (hardcoded — Skaffen is one agent)
- `event_type`: map from Evidence fields (e.g., "turn_complete", "session_end")
- `context`: JSON-encoded Evidence struct (all fields)

## Open Questions

1. **Event types**: What `--type` values should Skaffen emit? Candidates: `turn_complete` (per turn), `session_start`, `session_end`, `budget_warning`, `model_degraded`. Need to check what Interspect expects vs. what it can flexibly consume.

2. **Override caching**: Should the router query `ic route model` on every `SelectModel()` call (subprocess per turn), or cache the result per-session with a TTL? Subprocess per turn is ~5ms overhead but adds up over 100 turns.

3. **Outcome signals**: The bead mentions "terminal state, bead outcome, retry count, test pass rate" as outcome signals. The current Evidence struct has `Outcome string` but not retry count or test pass rate. Should we extend Evidence now, or let the emitter synthesize these from the turn history at session end?
