---
artifact_type: plan
bead: sylveste-sttz
date: 2026-04-05
---

# Plan: Forge Mode v1.5 — Reflexive Self-Improvement Workflow

## Context

Design: `apps/Auraken/docs/designs/forge-mode.md`
Contraindications design: `apps/Auraken/docs/designs/lens-contraindications.md`
Flux-review: `docs/research/flux-drive/forge-mode-reflexive-self-improvement/`

Forge Mode is a builder-only workflow where Auraken turns its cognitive augmentation on itself. Three sub-modes: Stress Test (Dojo), Profile Sim (Lab), Meta (Mirror for the Builder). v1.5 = mk-only development workflow; v2.0 = user-facing.

## Dependency Chain

```
F1 (schema) → F2 (command) → F3 (artifacts) → F4 (coverage)
```

F1 is a hard prerequisite — forge can't write metadata without the fields existing. F2 is independently useful (the conversation itself is valuable even without structured artifact output). F3 and F4 add rigor.

## F1: Lens Schema Extension (sylveste-sttz.1)

**Files:** `apps/Auraken/src/auraken/lenses.py`, `apps/Auraken/src/auraken/lens_library_v2.json`

Add four fields to `Lens` dataclass:

```python
# Contraindication metadata (Forge Mode safety layer)
contraindications: list[str] = field(default_factory=list)
near_miss_lenses: list[str] = field(default_factory=list)
failure_signatures: list[str] = field(default_factory=list)

# Contrastive pairs, not standalone strings (flux-review P1 fix)
distinguishing_features: list[DistinguishingFeature] = field(default_factory=list)
```

**Flux-review P1 addressed:** `distinguishing_features` uses a structured type instead of flat strings:

```python
@dataclass
class DistinguishingFeature:
    """A feature that distinguishes this lens from a specific near-miss."""
    discriminates_against: str  # lens ID this feature contrasts with
    feature: str                # the distinguishing observation
    question: str = ""          # optional probing question to surface it
```

This departs from the original design doc (which uses `list[str]`) to address the cognitive science finding: a distinguishing feature only means something relative to the specific near-miss it discriminates against.

**Backward compatibility:** all fields default to empty lists. `from_dict()` handles missing keys. Validate `discriminates_against` references valid lens IDs at load time (warn, don't crash).

**Verification:** `uv run pytest tests/ -v` passes, existing lens loading unchanged.

## F2: /forge Command + Mode Routing (sylveste-sttz.2)

**Files:** `apps/Auraken/src/auraken/telegram.py`, `apps/Auraken/src/auraken/forge.py` (new), `apps/Auraken/src/auraken/prompts.py`

### telegram.py changes

Register `/forge` command handler. Gate on builder user ID (`settings.builder_telegram_id`). Add config field to `config.py`.

```python
app.add_handler(CommandHandler("forge", self._forge_command))
```

### forge.py — new module

Core forge mode state and prompt injection:

- `ForgeMode` enum: `STRESS_TEST`, `PROFILE_SIM`, `META`
- `ForgeSession` dataclass: tracks active sub-mode, capability being tested, artifacts produced
- `forge_system_prompt(mode, context)` → system prompt section injected alongside the base OODARC prompt
- Session state: stored in-memory per user (only mk uses it). Cleared on `/exit` or session end.

### prompts.py changes

`build_system_prompt()` gains an optional `forge_session` parameter. When present, appends forge-specific instructions:
- Stress Test: "Generate edge case scenarios for {capability}. When you find a failure mode, output structured metadata updates."
- Profile Sim: "Simulate user profile evolution. When you find architecture gaps, output rule refinements."
- Meta: "Apply lenses to the product decision. Output reframes as brainstorm docs."

### Flow

1. `/forge stress-test lens-selection` → parse sub-mode + capability
2. Create `ForgeSession(mode=STRESS_TEST, capability="lens-selection")`
3. Inject forge system prompt into next `_call_claude()` via `build_system_prompt(forge_session=session)`
4. Conversation proceeds normally through OODARC, but the agent knows it's in forge mode
5. `/exit` or new `/forge` clears the session

**Verification:** manual test via Telegram — `/forge stress-test lens-selection` produces a scenario.

## F3: Stress Test Artifact Pipeline (sylveste-sttz.3)

**Files:** `apps/Auraken/src/auraken/forge.py`, new `apps/Auraken/data/forge-logs/` directory

### Structured log schema

```python
@dataclass
class StressTestLog:
    timestamp: str
    capability: str          # what was being stress-tested
    input_scenario: str      # the generated scenario text
    candidate_lenses: list[str]  # lens IDs returned by selector
    expected_final_lenses: list[str]
    contraindications_triggered: list[str]
    distinguishing_features_checked: list[str]
    resolution_rationale: str
    metadata_updates: list[dict]  # diffs to lens JSON
```

### Artifact extraction

The forge system prompt instructs Claude to output metadata updates in a structured format (fenced JSON blocks tagged `forge-artifact`). Post-response parsing extracts:
1. Lens metadata diffs → staged as updates to `lens_library_v2.json` (not auto-applied — builder reviews)
2. Stress test log → appended to `data/forge-logs/{date}-{capability}.jsonl`

### Review workflow

Staged diffs written to `data/forge-staging/`. Builder reviews with `git diff` before applying. This addresses the flux-review finding about ambiguous staging gates.

## F4: Coverage Index + Progressive Difficulty (sylveste-sttz.4)

**Files:** `apps/Auraken/src/auraken/forge.py`, new `apps/Auraken/data/forge-coverage.json`

### Coverage index

JSON matrix of lens pairs with `near_miss_lenses` relationships:

```json
{
  "pairs": {
    "lens_sunk_cost::lens_values_conflict": {
      "status": "tested",
      "last_tested": "2026-04-05",
      "sessions": 3,
      "stable_runs": 2,
      "converged": false
    }
  }
}
```

Updated automatically when a stress test log references a lens pair.

### Difficulty estimation

When the builder starts a stress test without specifying a pair, suggest the next pair by:
1. Filter to untested pairs first
2. Among untested, rank by difficulty: `shared_forces_count + shared_scale_count + when_to_apply_overlap`
3. Start with easiest (most different) → progress to hardest (most similar)

### Convergence signal

3 consecutive stress test sessions where a pair is tested and no metadata update is required → mark `converged: true`. Forge prompt tells the agent: "This pair has converged — suggest a harder pair or a multi-lens ambiguity scenario."

## Implementation Sequence

1. **F1** — schema extension (30 min). Unblocks everything else.
2. **F2** — command + mode routing (1 session). The core value — forge conversations work even without F3/F4.
3. **F3** — artifact pipeline (1 session). Adds structured output.
4. **F4** — coverage index (1 session). Adds progression and convergence.

## Original Intent (cut from v1.5, saved for v2.0)

- User-facing forge mode for power users who want to see how the agent works
- Automated regression test runner from stress test logs
- Multi-lens ambiguity scenarios (3+ lenses) — deferred until pairwise coverage is solid
- Integration with lens_evolution.py effectiveness scoring
