---
artifact_type: plan
bead: sylveste-sttz.3
date: 2026-04-05
---

# Plan: Forge F3 — Stress Test Artifact Pipeline

## Context

F1 (schema) and F2 (command + routing) are shipped. Forge mode conversations work but produce no durable artifacts. This plan adds: structured log schema, `forge-artifact` block extraction from Claude responses, staging workflow for lens metadata diffs.

**Files to modify:** `apps/Auraken/src/auraken/forge.py`
**Files to create:** None (all additions go into forge.py)
**Directories to create:** `apps/Auraken/data/forge-logs/`, `apps/Auraken/data/forge-staging/`

## Tasks

### T1: StressTestLog dataclass + serialization

Add to `forge.py`:

```python
@dataclass
class StressTestLog:
    timestamp: str
    capability: str
    sub_mode: str
    input_scenario: str
    candidate_lenses: list[str]
    expected_final_lenses: list[str]
    contraindications_triggered: list[str]
    distinguishing_features_checked: list[str]
    resolution_rationale: str
    metadata_updates: list[dict]
```

Add `to_dict()` method for JSON serialization.

### T2: Artifact extraction from Claude responses

Add `extract_forge_artifacts(response_text: str) -> list[dict]`:
- Regex: `` ```forge-artifact\n(.*?)\n``` `` (dotall)
- Parse each match as JSON
- Validate `type` field exists
- Return list of parsed dicts
- On parse failure: log warning, skip malformed block, continue

### T3: Artifact dispatch by type

Add `dispatch_artifact(artifact: dict, session: ForgeSession) -> str | None`:
- `lens_update` → write to `data/forge-staging/{lens_id}-{timestamp}.json`
- `profile_rule` → write to `data/forge-staging/profile-rules/{timestamp}.json`
- `stress_test_log` (or no type but has `input_scenario`) → append to `data/forge-logs/{date}-{capability}.jsonl`
- Returns path of written artifact, or None on failure
- Creates directories if missing

### T4: Wire extraction into response path

In `telegram.py` `_respond` method and `_forge_command`:
- After `handle_message` returns, if forge session active:
  - Call `extract_forge_artifacts(reply)`
  - For each artifact: `dispatch_artifact(artifact, forge_session)`
  - Track in `forge_session.artifacts`

### T5: Apply staging command

Add `apply_staged_update(path: str, lens_library_path: Path) -> bool`:
- Read the staged JSON patch
- Load lens_library_v2.json
- Find matching lens by ID, update fields
- Write back
- Move staged file to `data/forge-staging/applied/`
- This is a helper for manual use — NOT auto-called

## Verification

- Existing 174 tests still pass
- Ruff lint clean on forge.py
- Manual test: `/forge stress-test lens-selection` → conversation → verify JSONL log written
