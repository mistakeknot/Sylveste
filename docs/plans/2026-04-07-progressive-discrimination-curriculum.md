---
artifact_type: plan
bead: sylveste-uais
stage: design
requirements:
  - F1: Difficulty ladder
  - F2: Judicial holdings format
  - F3: Conversation integration spec
  - F4: User discrimination tracker
  - F5: Lens stack transition model
---
# Progressive Discrimination Curriculum — Implementation Plan (rev 2)

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-uais
**Goal:** Operationalize Forge calibration findings (30 near-miss pairs, 60 DQs, 16 stress tests) as a progressive user-facing curriculum within Auraken's conversation model.

**Architecture:** Three data layers feed into two runtime components. Layer 1: difficulty ladder (JSON, static) orders pairs by discrimination difficulty. Layer 2: judicial holdings (JSON, extends existing DQ records) adds operative-condition/rationale/scope to each DQ. Layer 3: conversation integration spec (design doc) defines the wax-and-gold depth model for DQ presentation. Runtime 1: discrimination tracker (PostgreSQL `discrimination_events` table, append-only) records per-user DQ resolution history and drives tier advancement. Runtime 2: lens stack orchestrator (Python module + session-serialized state) manages multi-lens sequences with explicit problem redefinition between phases. The curriculum decision point lives in `agent.py`'s conversation handler — post lens-selection, pre system-prompt build — where `user_id` and profile data are in scope.

**Tech Stack:** Python 3.12+, PostgreSQL + SQLAlchemy (existing profile system), JSON data files, pytest, Alembic migrations.

**Note on Go migration:** Auraken is migrating to Go incrementally. This plan stays in Python since the profile system and lens selector are still Python. Data formats (JSON, PostgreSQL schema) are language-agnostic and will survive the port. File a bead for Go port of the 3 new runtime modules (`discrimination.py`, `lens_stacks.py`, `curriculum.py`) once implementation is done.

**Review fixes applied (rev 2):** P0-1 data key fix, P0-2 tier rebalancing, P0-3 move curriculum decision to agent.py, P0-4 add depth_for_user(), P0-5 dead import, P1-1 separate table, P1-2 stack persistence, P1-3 sentence splitting, P1-4 was_correct derivation, P1-5 progression signal, P1-6 friction mechanism, P1-7 compensatory patterns, P1-8 stagnation detection, P1-9 patterns to JSON, P1-10 test conventions, P1-11 test fixtures, P1-12 logger.warning.

---

## Must-Haves

**Truths** (observable behaviors):
- All 30 near-miss pairs have a difficulty tier (easy/medium/hard) with ordering rationale
- All 60 DQs have judicial holdings (operative_condition, rationale, scope) referencing their stress test
- A spec doc defines when Auraken presents DQs vs routes silently, with concrete conversation examples at each wax-and-gold depth, and specifies how `was_correct` is determined from natural language
- User's DQ resolution history is persisted in a queryable `discrimination_events` table and survives session boundaries
- Lens stack transitions produce explicit problem redefinition with session-persistent state
- Curriculum decision point is in `agent.py` (not `select_lenses()`) where user_id and profile data are in scope

**Artifacts** (files with specific exports):
- [`data/calibration/difficulty_ladder.json`] — 30 entries with `tier`, `pair`, `dq_ref`, `rationale`
- [`data/calibration/build_difficulty_ladder.py`] — regeneration script, importable `build_ladder()`
- [`data/calibration/near_miss_forge_ready.json`] — updated with `holding` field per DQ
- [`data/calibration/restructure_holdings.py`] — restructuring script
- [`data/calibration/stack_patterns.json`] — named lens-stack patterns (language-neutral)
- [`docs/specs/conversation-integration-wax-and-gold.md`] — F3 spec
- [`src/auraken/discrimination.py`] exports `DiscriminationTracker`, `DiscriminationEvent` model, `depth_for_user`
- [`src/auraken/lens_stacks.py`] exports `StackOrchestrator`, `load_patterns`
- [`src/auraken/agent.py`] — curriculum integration between lens selection and prompt build

**Key Links** (connections where breakage cascades):
- `build_difficulty_ladder.py` reads `forge_stress_test_log.jsonl` + `near_miss_analysis.json` → `difficulty_ladder.json`
- `restructure_holdings.py` reads `near_miss_forge_ready.json` + `forge_stress_test_log.jsonl` → updates `near_miss_forge_ready.json`
- `agent.py` loads `difficulty_ladder.json` + user's `discrimination_events` → calls `should_present_dq()` + `depth_for_user()`
- `agent.py` constructs `StackOrchestrator` from session metadata for multi-turn stack progression
- `lens_stacks.py` reads `stack_patterns.json` for named patterns

---

### Task 1: F1 — Difficulty Ladder (data processing)

**Bead:** sylveste-9owj
**Depends:** none

**Files:**
- Create: `apps/Auraken/data/calibration/build_difficulty_ladder.py`
- Create: `apps/Auraken/data/calibration/difficulty_ladder.json` (generated output)
- Test: `apps/Auraken/tests/test_difficulty_ladder.py`

**Context:** 30 unique pairs in `near_miss_analysis.json` under the `"pairs"` key (fields: `lens_a`, `lens_b`, `co_occurrence_count`). 8 pairs stress-tested (16 tests, 2 per pair) in `forge_stress_test_log.jsonl`. Distribution: co_occurrence_count {2:11, 3:11, 4:5, 5:3}. No count=1 pairs exist in the file.

Tier definitions (revised from review — ensures >= 3 per tier):
- **easy:** Stress-tested pairs with all tests RESOLVED (4 pairs: AModel/TrustLong, Fence/Reckoning, Reckoning/SBI, Reckoning/Trilemma), PLUS untested pairs with co_occurrence_count=2 (11 pairs). Total: **15 pairs**.
- **medium:** Untested pairs with co_occurrence_count=3 (11 pairs). Total: **11 pairs**.
- **hard:** Stress-tested pairs with mixed RESOLVED/PARTIAL results (4 pairs: Approach/Micro, Approach/SBI, KM/Trilemma, Micro/TrustLong) — these involve lens-stack scenarios requiring sequential application. Total: **4 pairs**.

Untested pairs with count=4-5 are all the stress-tested pairs (routed through stress-test branch first), so the cookoff-frequency thresholds only apply to the 22 untested pairs with count 2-3.

**Step 1: Write the failing test**
```python
# tests/test_difficulty_ladder.py
"""Tests for difficulty ladder generation."""
import json
from pathlib import Path

import pytest

from build_difficulty_ladder import build_ladder

CALIBRATION_DIR = Path(__file__).parent.parent / "data" / "calibration"


@pytest.fixture
def ladder():
    """Build ladder from real data files."""
    return build_ladder(
        stress_log=CALIBRATION_DIR / "forge_stress_test_log.jsonl",
        analysis=CALIBRATION_DIR / "near_miss_analysis.json",
        forge_ready=CALIBRATION_DIR / "near_miss_forge_ready.json",
    )


class TestDifficultyLadder:
    def test_all_30_pairs_assigned(self, ladder):
        assert len(ladder["ladder"]) == 30

    def test_at_least_3_per_tier(self, ladder):
        tiers = {}
        for entry in ladder["ladder"]:
            tiers.setdefault(entry["tier"], []).append(entry)
        for tier_name in ("easy", "medium", "hard"):
            assert len(tiers.get(tier_name, [])) >= 3, (
                f"Tier '{tier_name}' has {len(tiers.get(tier_name, []))} pairs, need >= 3"
            )

    def test_entry_schema(self, ladder):
        required = {"tier", "pair", "dq_ref", "rationale", "source"}
        for entry in ladder["ladder"]:
            missing = required - set(entry.keys())
            assert not missing, f"Entry {entry.get('pair')} missing: {missing}"
            assert entry["tier"] in ("easy", "medium", "hard")
            assert len(entry["pair"]) == 2
            assert entry["source"] in ("stress_test", "cookoff_frequency")

    def test_idempotent(self, ladder):
        ladder2 = build_ladder(
            stress_log=CALIBRATION_DIR / "forge_stress_test_log.jsonl",
            analysis=CALIBRATION_DIR / "near_miss_analysis.json",
            forge_ready=CALIBRATION_DIR / "near_miss_forge_ready.json",
        )
        assert ladder == ladder2

    def test_stress_tested_pairs_classified_correctly(self, ladder):
        """All-RESOLVED → easy, mixed → hard."""
        by_pair = {tuple(sorted(e["pair"])): e for e in ladder["ladder"]}
        # All-RESOLVED pairs should be easy
        assert by_pair[("A Model of Trust", "Trust Is a Long Game")]["tier"] == "easy"
        # Mixed RESOLVED/PARTIAL should be hard
        assert by_pair[("Approach or Avoid", "Microboundaries")]["tier"] == "hard"
```

**Step 2: Run tests to verify they fail**
Run: `cd apps/Auraken && uv run pytest tests/test_difficulty_ladder.py -v`
Expected: FAIL — module doesn't exist yet

**Step 3: Write the build script**
```python
# data/calibration/build_difficulty_ladder.py
"""Build difficulty ladder from stress test results + cookoff co-occurrence.

Tier assignment:
- Stress-tested all-RESOLVED → easy
- Stress-tested mixed RESOLVED/PARTIAL → hard (lens-stack scenarios)
- Untested co_occurrence_count=2 → easy
- Untested co_occurrence_count=3 → medium
- Untested co_occurrence_count>=4 → hard (but all are stress-tested, so this is a safety net)

Usage: python build_difficulty_ladder.py [--output path]
"""
import argparse
import json
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).parent
_DEFAULT_STRESS_LOG = HERE / "forge_stress_test_log.jsonl"
_DEFAULT_ANALYSIS = HERE / "near_miss_analysis.json"
_DEFAULT_FORGE_READY = HERE / "near_miss_forge_ready.json"
_DEFAULT_OUTPUT = HERE / "difficulty_ladder.json"


def _load_stress_tests(path: Path) -> dict[tuple[str, str], list[dict]]:
    tests_by_pair: dict[tuple[str, str], list[dict]] = defaultdict(list)
    with open(path) as f:
        for line in f:
            if not line.strip():
                continue
            test = json.loads(line)
            pair = tuple(sorted(test["pair"]))
            tests_by_pair[pair].append(test)
    return dict(tests_by_pair)


def _load_all_pairs(path: Path) -> list[tuple[str, str]]:
    with open(path) as f:
        data = json.load(f)
    pairs = set()
    for lens_name, info in data.get("lens_updates", {}).items():
        for feat in info.get("distinguishing_features", []):
            pair = tuple(sorted([lens_name, feat["discriminates_against"]]))
            pairs.add(pair)
    return sorted(pairs)


def _load_cookoff_frequency(path: Path) -> dict[tuple[str, str], int]:
    with open(path) as f:
        data = json.load(f)
    freq = {}
    for pair_entry in data.get("pairs", []):
        pair = tuple(sorted([pair_entry["lens_a"], pair_entry["lens_b"]]))
        freq[pair] = pair_entry.get("co_occurrence_count", 1)
    return freq


def _find_dq_ref(pair: tuple[str, str], forge_data: dict) -> str:
    for lens_name in pair:
        lens_info = forge_data.get("lens_updates", {}).get(lens_name, {})
        for feat in lens_info.get("distinguishing_features", []):
            other = feat["discriminates_against"]
            if tuple(sorted([lens_name, other])) == pair:
                return feat.get("question", "")
    return ""


def build_ladder(
    stress_log: Path = _DEFAULT_STRESS_LOG,
    analysis: Path = _DEFAULT_ANALYSIS,
    forge_ready: Path = _DEFAULT_FORGE_READY,
) -> dict:
    stress_tests = _load_stress_tests(stress_log)
    all_pairs = _load_all_pairs(forge_ready)
    cookoff_freq = _load_cookoff_frequency(analysis)

    with open(forge_ready) as f:
        forge_data = json.load(f)

    ladder = []
    for pair in all_pairs:
        tests = stress_tests.get(pair, [])
        dq_ref = _find_dq_ref(pair, forge_data)

        if tests:
            resolutions = [t["resolution"] for t in tests]
            partial_count = resolutions.count("PARTIAL")
            if partial_count == 0:
                tier = "easy"
                rationale = f"All stress tests RESOLVED — high-contrast discrimination"
            else:
                tier = "hard"
                rationale = f"Mixed RESOLVED/PARTIAL — requires sequential lens application"
            source = "stress_test"
        else:
            freq = cookoff_freq.get(pair, 2)
            if freq <= 2:
                tier = "easy"
                rationale = f"Co-occurrence count {freq} — low model confusion"
            elif freq <= 3:
                tier = "medium"
                rationale = f"Co-occurrence count {freq} — moderate model disagreement"
            else:
                tier = "hard"
                rationale = f"Co-occurrence count {freq} — high model disagreement"
            source = "cookoff_frequency"

        ladder.append({
            "pair": list(pair),
            "tier": tier,
            "dq_ref": dq_ref,
            "rationale": rationale,
            "source": source,
        })

    tier_order = {"easy": 0, "medium": 1, "hard": 2}
    ladder.sort(key=lambda e: (tier_order[e["tier"]], e["pair"]))

    return {
        "metadata": {
            "total_pairs": len(ladder),
            "stress_tested": len(stress_tests),
            "tiers": {
                t: len([e for e in ladder if e["tier"] == t])
                for t in ("easy", "medium", "hard")
            },
        },
        "ladder": ladder,
    }


def main():
    parser = argparse.ArgumentParser(description="Build difficulty ladder")
    parser.add_argument("--output", type=Path, default=_DEFAULT_OUTPUT)
    args = parser.parse_args()
    result = build_ladder()
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Wrote {len(result['ladder'])} pairs to {args.output}")
    for tier in ("easy", "medium", "hard"):
        print(f"  {tier}: {result['metadata']['tiers'][tier]} pairs")


if __name__ == "__main__":
    main()
```

**Step 4: Run tests, generate ladder, commit**
```bash
cd apps/Auraken && uv run pytest tests/test_difficulty_ladder.py -v
uv run python data/calibration/build_difficulty_ladder.py
git add data/calibration/build_difficulty_ladder.py data/calibration/difficulty_ladder.json tests/test_difficulty_ladder.py
git commit -m "feat(auraken): F1 difficulty ladder — order 30 near-miss pairs by tier"
```

<verify>
- run: `cd apps/Auraken && uv run pytest tests/test_difficulty_ladder.py -v`
  expect: exit 0
- run: `cd apps/Auraken && python3 -c "import json; d=json.load(open('data/calibration/difficulty_ladder.json')); print(len(d['ladder']), 'pairs'); print(d['metadata']['tiers'])"`
  expect: contains "30 pairs"
</verify>

---

### Task 2: F2 — Judicial Holdings Format (data restructuring)

**Bead:** sylveste-5ca9
**Depends:** none

**Files:**
- Create: `apps/Auraken/data/calibration/restructure_holdings.py`
- Modify: `apps/Auraken/data/calibration/near_miss_forge_ready.json`
- Modify: `apps/Auraken/src/auraken/lenses.py:30-38` (extend `DistinguishingFeature`)
- Test: `apps/Auraken/tests/test_holdings.py`

**What:** Each DQ gets a `holding` subobject with `operative_condition`, `rationale`, `scope`, and `stress_test_ref`. The restructuring script uses regex-based sentence splitting (not naive `.split(".")`) to handle abbreviations like `vs.` and quoted periods.

**Step 1: Write the failing test**
```python
# tests/test_holdings.py
"""Tests for judicial holdings restructuring."""
import json
from pathlib import Path

import pytest

CALIBRATION_DIR = Path(__file__).parent.parent / "data" / "calibration"


@pytest.fixture
def forge_data():
    """Read the production forge-ready file after restructuring."""
    path = CALIBRATION_DIR / "near_miss_forge_ready.json"
    if not path.exists():
        pytest.skip("near_miss_forge_ready.json not found — run restructure first")
    return json.loads(path.read_text())


@pytest.fixture
def stress_tested_pairs():
    """Derive stress-tested pairs from the log (not hardcoded)."""
    path = CALIBRATION_DIR / "forge_stress_test_log.jsonl"
    pairs = set()
    with open(path) as f:
        for line in f:
            if not line.strip():
                continue
            test = json.loads(line)
            pairs.add(tuple(sorted(test["pair"])))
    return pairs


class TestHoldings:
    def test_all_dqs_have_holding(self, forge_data):
        required = {"operative_condition", "rationale", "scope"}
        for lens_name, info in forge_data.get("lens_updates", {}).items():
            for feat in info.get("distinguishing_features", []):
                holding = feat.get("holding")
                assert holding is not None, (
                    f"DQ for {lens_name} vs {feat['discriminates_against']} missing holding"
                )
                missing = required - set(holding.keys())
                assert not missing, f"Holding missing: {missing}"

    def test_holding_fields_non_empty(self, forge_data):
        for lens_name, info in forge_data.get("lens_updates", {}).items():
            for feat in info.get("distinguishing_features", []):
                holding = feat.get("holding", {})
                for field_name in ("operative_condition", "rationale", "scope"):
                    val = holding.get(field_name, "")
                    assert len(val) >= 10, (
                        f"Holding.{field_name} for {lens_name} vs "
                        f"{feat['discriminates_against']} too short: '{val}'"
                    )

    def test_stress_test_ref_where_available(self, forge_data, stress_tested_pairs):
        for lens_name, info in forge_data.get("lens_updates", {}).items():
            for feat in info.get("distinguishing_features", []):
                pair = tuple(sorted([lens_name, feat["discriminates_against"]]))
                holding = feat.get("holding", {})
                if pair in stress_tested_pairs:
                    assert holding.get("stress_test_ref"), (
                        f"Stress-tested pair {pair} missing stress_test_ref"
                    )

    def test_holding_count(self, forge_data):
        count = sum(
            1 for info in forge_data.get("lens_updates", {}).values()
            for feat in info.get("distinguishing_features", [])
            if feat.get("holding")
        )
        assert count == 60

    def test_scope_direction_consistent(self, forge_data):
        """Scope should say 'Prefer X over Y' where Y is the lens being updated."""
        for lens_name, info in forge_data.get("lens_updates", {}).items():
            for feat in info.get("distinguishing_features", []):
                holding = feat.get("holding", {})
                scope = holding.get("scope", "")
                other = feat["discriminates_against"]
                assert other in scope, (
                    f"Scope for {lens_name} vs {other} doesn't reference {other}: {scope}"
                )
```

**Step 2: Extend `DistinguishingFeature` dataclass**

Add to `src/auraken/lenses.py` before the existing `DistinguishingFeature`:
```python
@dataclass
class Holding:
    """Judicial holding — makes a DQ durable and independently revisable."""
    operative_condition: str
    rationale: str
    scope: str
    stress_test_ref: str = ""


@dataclass
class DistinguishingFeature:
    """A feature that distinguishes a lens from a specific near-miss."""
    discriminates_against: str
    feature: str
    question: str = ""
    holding: Holding | None = None
```

Update `_load_v2_entry` to parse `holding` from JSON into the `Holding` dataclass when present.

**Step 3: Write the restructuring script**
```python
# data/calibration/restructure_holdings.py
"""Restructure 60 DQs into judicial holdings format.

Uses regex-based sentence splitting to avoid corrupting text with
abbreviations (vs., e.g.) or quoted periods.

Usage: python restructure_holdings.py [--dry-run]
"""
import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).parent
FORGE_READY = HERE / "near_miss_forge_ready.json"
STRESS_LOG = HERE / "forge_stress_test_log.jsonl"

# Split on period followed by space and uppercase letter —
# avoids splitting on "vs.", "e.g.", abbreviations, quotes
_SENTENCE_SPLIT = re.compile(r'(?<=[a-z])\.\s+(?=[A-Z])')


def _load_stress_refs() -> dict[tuple[str, str], str]:
    refs: dict[tuple[str, str], list[str]] = {}
    with open(STRESS_LOG) as f:
        for line in f:
            if not line.strip():
                continue
            test = json.loads(line)
            pair = tuple(sorted(test["pair"]))
            summary = (
                f"{test['resolution']} on '{test.get('input_scenario', '?')}': "
                f"{test.get('resolution_rationale', '')[:120]}"
            )
            refs.setdefault(pair, []).append(summary)
    return {pair: " | ".join(sums) for pair, sums in refs.items()}


def generate_holding(lens_name: str, feat: dict, stress_ref: str) -> dict:
    other = feat["discriminates_against"]
    feature_text = feat["feature"]

    sentences = _SENTENCE_SPLIT.split(feature_text)
    sentences = [s.strip().rstrip(".") + "." for s in sentences if s.strip()]

    operative = f"When {sentences[0][0].lower()}{sentences[0][1:]}" if sentences else f"When this distinction applies."
    rationale = sentences[-1] if len(sentences) > 1 else f"The distinction between {lens_name} and {other} is load-bearing here."
    scope = f"Prefer {other} over {lens_name}."

    return {
        "operative_condition": operative,
        "rationale": rationale,
        "scope": scope,
        "stress_test_ref": stress_ref,
    }


def restructure(dry_run: bool = False) -> dict:
    data = json.loads(FORGE_READY.read_text())
    stress_refs = _load_stress_refs()
    count = 0

    for lens_name, info in data.get("lens_updates", {}).items():
        for feat in info.get("distinguishing_features", []):
            pair = tuple(sorted([lens_name, feat["discriminates_against"]]))
            stress_ref = stress_refs.get(pair, "")
            feat["holding"] = generate_holding(lens_name, feat, stress_ref)
            count += 1

    if not dry_run:
        FORGE_READY.write_text(json.dumps(data, indent=2) + "\n")
        print(f"Updated {count} DQs with holdings in {FORGE_READY}")
    else:
        print(f"Dry run: would update {count} DQs")
        first_lens = next(iter(data.get("lens_updates", {})))
        first_feat = data["lens_updates"][first_lens]["distinguishing_features"][0]
        print(json.dumps(first_feat["holding"], indent=2))
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    restructure(dry_run=args.dry_run)


if __name__ == "__main__":
    main()
```

**Step 4: Run, review, commit**
```bash
cd apps/Auraken
uv run python data/calibration/restructure_holdings.py --dry-run
uv run python data/calibration/restructure_holdings.py
uv run pytest tests/test_holdings.py -v
git add data/calibration/restructure_holdings.py data/calibration/near_miss_forge_ready.json \
  src/auraken/lenses.py tests/test_holdings.py
git commit -m "feat(auraken): F2 judicial holdings — restructure 60 DQs with condition/rationale/scope"
```

<verify>
- run: `cd apps/Auraken && uv run pytest tests/test_holdings.py -v`
  expect: exit 0
</verify>

---

### Task 3: F3 — Conversation Integration Spec (design document)

**Bead:** sylveste-ddmg
**Depends:** task-1, task-2

**Files:**
- Create: `apps/Auraken/docs/specs/conversation-integration-wax-and-gold.md`

**Step 1: Read philosophy and OODARC references**

Read `apps/Auraken/PHILOSOPHY.md` and grep OODARC in `src/auraken/forge.py`.

**Step 2: Write the spec**

The spec MUST cover these sections (each is required, not optional):

1. **Three-depth model with concrete examples** — For each depth (deep gold, shallow gold, wax), 2 conversation transcript examples using real DQs from the difficulty ladder.

2. **Tier-to-depth mapping** — Explicit function: `easy → wax` (teach vocabulary to beginners), `medium → shallow_gold` (name after applying), `hard → deep_gold` (embody without naming for advanced users). This mapping is implemented in `depth_for_user()` in Task 6.

3. **Decision tree: when to present DQ vs route silently** — Flow: (a) lens selector identifies 2 near-miss candidates → (b) check difficulty_ladder for pair tier → (c) check user's discrimination tier from tracker → (d) if DQ tier <= user tier, present it at mapped depth; if above, route silently → (e) exception: 1 in 5 above-tier DQs are presented anyway as "stretch" challenges (prevents glass ceiling).

4. **Correctness signal: how `was_correct` is determined** — The user's DQ answer is free-text, not multiple-choice. Auraken uses a lightweight Haiku judgment call (same pattern as `select_lenses()`) to classify the user's response against the DQ's `holding.scope` field. Input: user's natural-language response + the DQ question + both lens names. Output: `{"chosen_lens": "X", "confidence": 0.8}`. If confidence < 0.5, don't record a resolution (ambiguous answer). This is the core mechanism — it must be spec'd before F4 can implement it.

5. **Graceful wrong-answer handling** — When user's DQ answer points to the less-appropriate lens: apply their chosen lens for 1-2 turns (not indefinitely). If the user expresses friction or asks a follow-up that suggests the lens isn't working, use that as the teaching moment: "Notice how the advice feels generic? That's because this situation resists analytical decomposition." If no friction emerges within 2 turns, move on without comment (the user may be right and the stress test may be context-dependent).

6. **Progression signal** — When a user is being silently routed (DQ above tier), Auraken occasionally (1 in 5) drops a hint: "There's a subtler distinction here that we'll explore as we go." This prevents the glass ceiling feeling without overwhelming.

7. **OODARC integration** — DQ presentation maps to Orient phase.

8. **Philosophy alignment** — Check each decision against: camera-not-engine, preserve-cognitive-struggle, questions-are-the-product, anti-dependency, invisible-lenses.

9. **Compensatory pattern response** — When `compensatory_patterns()` detects consistent avoidance: Auraken notes it internally (logged, not surfaced). Only surfaces to user if they explicitly ask "What am I avoiding?" or similar meta-cognitive inquiry. No proactive confrontation — that violates camera-not-engine.

**Step 3: Verify and commit**
```bash
# Verify required sections exist
grep -c "Tier-to-depth mapping\|Correctness signal\|Graceful wrong-answer\|Progression signal\|Compensatory pattern" \
  apps/Auraken/docs/specs/conversation-integration-wax-and-gold.md
# Should output >= 5
git add apps/Auraken/docs/specs/conversation-integration-wax-and-gold.md
git commit -m "docs(auraken): F3 conversation integration spec — wax-and-gold depth model"
```

<verify>
- run: `grep -c "Tier-to-depth\|Correctness signal\|Graceful wrong-answer\|Progression signal\|Compensatory pattern" apps/Auraken/docs/specs/conversation-integration-wax-and-gold.md`
  expect: contains "5"
</verify>

---

### Task 4: F4 — User Discrimination Tracker (runtime code)

**Bead:** sylveste-1zei
**Depends:** task-3

**Files:**
- Create: `apps/Auraken/src/auraken/discrimination.py`
- Modify: `apps/Auraken/src/auraken/models.py` (add `DiscriminationEvent` model)
- Create: `apps/Auraken/alembic/versions/xxxx_add_discrimination_events.py`
- Test: `apps/Auraken/tests/test_discrimination.py`

**Key design change from rev 1:** Uses a separate `discrimination_events` table (append-only, indexed on `user_id, created_at`) instead of JSONB on CoreProfile. Mirrors the existing `ProfileEpisode` pattern. Unbounded growth is handled by querying only the N most recent events.

**Step 1: Write the failing test**
```python
# tests/test_discrimination.py
"""Tests for discrimination tracker."""
from datetime import datetime, timezone

import pytest

from auraken.discrimination import (
    ADVANCEMENT_THRESHOLD,
    DiscriminationTracker,
    ResolutionRecord,
    depth_for_user,
)


class TestResolutionRecord:
    def test_roundtrip(self):
        rec = ResolutionRecord(
            dq_pair=("Trilemma", "Kobayashi Maru"),
            user_answer="structural_constraints",
            correct_lens="Trilemma",
            was_correct=True,
            confidence=0.85,
            tier="easy",
            timestamp=datetime(2026, 4, 7, tzinfo=timezone.utc),
        )
        d = rec.to_dict()
        roundtrip = ResolutionRecord.from_dict(d)
        assert roundtrip.was_correct == rec.was_correct
        assert roundtrip.confidence == rec.confidence


class TestAdvancementLogic:
    def test_no_history_stays_easy(self):
        tracker = DiscriminationTracker(history=[])
        assert tracker.current_tier == "easy"

    def test_advance_easy_to_medium(self):
        history = [
            ResolutionRecord(
                dq_pair=(f"Lens{i}", f"Lens{i+1}"),
                user_answer="correct", correct_lens=f"Lens{i}",
                was_correct=True, confidence=0.9, tier="easy",
            )
            for i in range(ADVANCEMENT_THRESHOLD)
        ]
        tracker = DiscriminationTracker(history=history)
        assert tracker.current_tier == "medium"

    def test_advance_through_to_hard(self):
        easy_recs = [
            ResolutionRecord(
                dq_pair=(f"E{i}", f"E{i+1}"),
                user_answer="c", correct_lens=f"E{i}",
                was_correct=True, confidence=0.9, tier="easy",
            )
            for i in range(ADVANCEMENT_THRESHOLD)
        ]
        medium_recs = [
            ResolutionRecord(
                dq_pair=(f"M{i}", f"M{i+1}"),
                user_answer="c", correct_lens=f"M{i}",
                was_correct=True, confidence=0.9, tier="medium",
            )
            for i in range(ADVANCEMENT_THRESHOLD)
        ]
        tracker = DiscriminationTracker(history=easy_recs + medium_recs)
        assert tracker.current_tier == "hard"

    def test_wrong_answers_dont_count(self):
        history = [
            ResolutionRecord(
                dq_pair=(f"L{i}", f"L{i+1}"),
                user_answer="w", correct_lens=f"L{i}",
                was_correct=False, confidence=0.9, tier="easy",
            )
            for i in range(10)
        ]
        tracker = DiscriminationTracker(history=history)
        assert tracker.current_tier == "easy"

    def test_regression_detection(self):
        history = [
            ResolutionRecord(
                dq_pair=("A", "B"), user_answer="a", correct_lens="A",
                was_correct=True, confidence=0.9, tier="easy",
                timestamp=datetime(2026, 4, 1, tzinfo=timezone.utc),
            ),
            ResolutionRecord(
                dq_pair=("A", "B"), user_answer="b", correct_lens="A",
                was_correct=False, confidence=0.8, tier="easy",
                timestamp=datetime(2026, 4, 7, tzinfo=timezone.utc),
            ),
        ]
        tracker = DiscriminationTracker(history=history)
        regressions = tracker.detect_regressions()
        assert len(regressions) == 1

    def test_stagnation_detection(self):
        """User attempts many DQs at a tier but never reaches threshold."""
        history = [
            ResolutionRecord(
                dq_pair=(f"L{i}", f"L{i+1}"),
                user_answer="x", correct_lens=f"L{i}",
                was_correct=(i % 3 != 0),  # 2/3 correct, never reaches 5 consecutive
                confidence=0.7, tier="easy",
            )
            for i in range(15)
        ]
        tracker = DiscriminationTracker(history=history)
        stagnation = tracker.detect_stagnation()
        assert stagnation is not None
        assert stagnation["tier"] == "easy"


class TestDepthMapping:
    def test_easy_maps_to_wax(self):
        assert depth_for_user("easy") == "wax"

    def test_medium_maps_to_shallow_gold(self):
        assert depth_for_user("medium") == "shallow_gold"

    def test_hard_maps_to_deep_gold(self):
        assert depth_for_user("hard") == "deep_gold"
```

**Step 2: Write the discrimination module**
```python
# src/auraken/discrimination.py
"""User discrimination tracker — DQ resolution history + tier advancement.

Uses a separate discrimination_events table (append-only, indexed).
Loads only the N most recent events for tier computation.
"""
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

ADVANCEMENT_THRESHOLD = 5
STAGNATION_THRESHOLD = 12  # attempts at a tier without advancing
TIERS = ("easy", "medium", "hard")
TIER_TO_DEPTH = {"easy": "wax", "medium": "shallow_gold", "hard": "deep_gold"}
TIER_ORDER = {"easy": 0, "medium": 1, "hard": 2}


def depth_for_user(user_tier: str) -> str:
    """Map user's discrimination tier to wax-and-gold depth."""
    return TIER_TO_DEPTH.get(user_tier, "wax")


def should_present_dq(dq_tier: str, user_tier: str) -> bool:
    """Present if DQ tier <= user tier (at or below their level)."""
    return TIER_ORDER.get(dq_tier, 0) <= TIER_ORDER.get(user_tier, 0)


@dataclass
class ResolutionRecord:
    dq_pair: tuple[str, str]
    user_answer: str
    correct_lens: str
    was_correct: bool
    confidence: float = 0.0  # Haiku judgment confidence
    tier: str = "easy"
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def to_dict(self) -> dict:
        return {
            "dq_pair": list(self.dq_pair),
            "user_answer": self.user_answer,
            "correct_lens": self.correct_lens,
            "was_correct": self.was_correct,
            "confidence": self.confidence,
            "tier": self.tier,
            "timestamp": self.timestamp.isoformat(),
        }

    @classmethod
    def from_dict(cls, d: dict) -> "ResolutionRecord":
        a, b = d["dq_pair"]
        return cls(
            dq_pair=(a, b),
            user_answer=d["user_answer"],
            correct_lens=d["correct_lens"],
            was_correct=d["was_correct"],
            confidence=d.get("confidence", 0.0),
            tier=d["tier"],
            timestamp=datetime.fromisoformat(d["timestamp"]),
        )


class DiscriminationTracker:
    def __init__(self, history: list[ResolutionRecord] | None = None):
        self.history = history or []

    @property
    def current_tier(self) -> str:
        tier_idx = 0
        for tier in TIERS[:-1]:
            correct_at_tier = sum(
                1 for r in self.history if r.tier == tier and r.was_correct
            )
            if correct_at_tier >= ADVANCEMENT_THRESHOLD:
                tier_idx += 1
            else:
                break
        return TIERS[min(tier_idx, len(TIERS) - 1)]

    def detect_regressions(self) -> list[dict]:
        first_resolved: dict[tuple[str, str], datetime] = {}
        regressions: list[dict] = []
        for rec in sorted(self.history, key=lambda r: r.timestamp):
            if rec.was_correct and rec.dq_pair not in first_resolved:
                first_resolved[rec.dq_pair] = rec.timestamp
            elif not rec.was_correct and rec.dq_pair in first_resolved:
                regressions.append({
                    "pair": rec.dq_pair,
                    "first_resolved": first_resolved[rec.dq_pair],
                    "failed_at": rec.timestamp,
                })
        return regressions

    def detect_stagnation(self) -> dict | None:
        """Detect when user has many attempts at a tier without advancing."""
        tier = self.current_tier
        attempts_at_tier = sum(1 for r in self.history if r.tier == tier)
        correct_at_tier = sum(
            1 for r in self.history if r.tier == tier and r.was_correct
        )
        if attempts_at_tier >= STAGNATION_THRESHOLD and correct_at_tier < ADVANCEMENT_THRESHOLD:
            return {
                "tier": tier,
                "attempts": attempts_at_tier,
                "correct": correct_at_tier,
            }
        return None

    def compensatory_patterns(self) -> list[dict]:
        """Detect consistent avoidance of certain problem types.

        Returns typed dicts with surface_as field:
        - "internal": log only (default, until conversational design is specified)
        - "conversational": surface to user on explicit meta-cognitive inquiry
        """
        lens_attempts: dict[str, int] = {}
        lens_correct: dict[str, int] = {}
        for rec in self.history:
            for lens in rec.dq_pair:
                lens_attempts[lens] = lens_attempts.get(lens, 0) + 1
                if rec.was_correct:
                    lens_correct[lens] = lens_correct.get(lens, 0) + 1
        patterns = []
        for lens, attempts in lens_attempts.items():
            if attempts >= 3:
                correct = lens_correct.get(lens, 0)
                rate = correct / attempts
                if rate < 0.3:
                    patterns.append({
                        "lens": lens,
                        "correct": correct,
                        "attempts": attempts,
                        "rate": rate,
                        "surface_as": "internal",
                    })
        return patterns
```

**Step 3: Add `DiscriminationEvent` model to models.py**

Add after the `ProfileEpisode` class:
```python
class DiscriminationEvent(Base):
    """Append-only record of a DQ resolution — mirrors ProfileEpisode pattern."""
    __tablename__ = "discrimination_events"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=False
    )
    dq_pair_a: Mapped[str] = mapped_column(String, nullable=False)
    dq_pair_b: Mapped[str] = mapped_column(String, nullable=False)
    tier: Mapped[str] = mapped_column(String, nullable=False)
    was_correct: Mapped[bool] = mapped_column(Boolean, nullable=False)
    confidence: Mapped[float] = mapped_column(Float, default=0.0)
    user_answer: Mapped[str] = mapped_column(Text, default="")
    correct_lens: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        Index("ix_discrimination_events_user_created", "user_id", "created_at"),
    )
```

**Step 4: Create Alembic migration**
```bash
cd apps/Auraken && uv run alembic revision --autogenerate -m "add discrimination_events table"
```

**Step 5: Run tests, commit**
```bash
cd apps/Auraken && uv run pytest tests/test_discrimination.py -v
git add src/auraken/discrimination.py src/auraken/models.py tests/test_discrimination.py alembic/
git commit -m "feat(auraken): F4 discrimination tracker — events table + tier advancement"
```

<verify>
- run: `cd apps/Auraken && uv run pytest tests/test_discrimination.py -v`
  expect: exit 0
</verify>

---

### Task 5: F5 — Lens Stack Transition Model (runtime code)

**Bead:** sylveste-csa7
**Depends:** task-3

**Files:**
- Create: `apps/Auraken/data/calibration/stack_patterns.json`
- Create: `apps/Auraken/src/auraken/lens_stacks.py`
- Test: `apps/Auraken/tests/test_lens_stacks.py`

**Key design changes from rev 1:** Named patterns live in `data/calibration/stack_patterns.json` (language-neutral, editable without code change). `StackOrchestrator` state serializes to/from dict for session-level persistence (stored in `Session.messages` metadata between turns).

**Step 1: Create stack_patterns.json**
```json
{
  "patterns": {
    "Boundary Protocol": {
      "lenses": ["Approach or Avoid", "Microboundaries", "Situation-Behavior-Impact"],
      "description": "Unblock motivation -> Set boundary -> Communicate it.",
      "source": "Forge stress test: Dilemma 3524"
    },
    "Constraint Scrutiny": {
      "lenses": ["Kobayashi Maru", "Trilemma"],
      "description": "Question whether constraints are real -> If real, choose which to sacrifice.",
      "source": "Forge stress test: Dilemma 257"
    },
    "Trust Diagnosis": {
      "lenses": ["A Model of Trust", "Trust Is a Long Game"],
      "description": "Diagnose which trust dimension failed -> Decide whether to invest in recovery.",
      "source": "Forge stress test: Dilemma 3440/2891"
    }
  }
}
```

**Step 2: Write the failing test**
```python
# tests/test_lens_stacks.py
"""Tests for lens stack transition model."""
import json
from pathlib import Path

import pytest

from auraken.lens_stacks import (
    StackOrchestrator,
    load_patterns,
)

PATTERNS_FILE = Path(__file__).parent.parent / "data" / "calibration" / "stack_patterns.json"


class TestLoadPatterns:
    def test_loads_at_least_3(self):
        patterns = load_patterns(PATTERNS_FILE)
        assert len(patterns) >= 3

    def test_pattern_structure(self):
        patterns = load_patterns(PATTERNS_FILE)
        for name, p in patterns.items():
            assert "lenses" in p and len(p["lenses"]) >= 2
            assert "description" in p


class TestStackOrchestrator:
    def test_single_lens_no_transition(self):
        orch = StackOrchestrator(lenses=["Trilemma"])
        result = orch.next_phase("three competing priorities")
        assert result["lens"] == "Trilemma"
        assert result["transition_text"] is None

    def test_multi_lens_produces_redefinition(self):
        orch = StackOrchestrator(
            lenses=["Approach or Avoid", "Microboundaries"],
            depth="shallow_gold",
        )
        r1 = orch.next_phase("paralyzed about confronting someone")
        assert r1["lens"] == "Approach or Avoid"
        assert r1["problem_redefinition"] is None

        r2 = orch.next_phase("chose to approach, needs boundaries")
        assert r2["lens"] == "Microboundaries"
        assert r2["problem_redefinition"] is not None
        assert r2["transition_text"] is not None

    def test_deep_gold_hides_lens_names(self):
        orch = StackOrchestrator(
            lenses=["Approach or Avoid", "Microboundaries"],
            depth="deep_gold",
        )
        orch.next_phase("stuck")
        r2 = orch.next_phase("chose to engage")
        assert r2["transition_text"] is not None
        assert "Approach" not in r2["transition_text"]
        assert "Microboundaries" not in r2["transition_text"]

    def test_serialize_restore(self):
        orch = StackOrchestrator(
            lenses=["A", "B", "C"], depth="wax",
        )
        orch.next_phase("first input")
        state = orch.to_dict()

        restored = StackOrchestrator.from_dict(state)
        assert restored.phase_index == 1
        assert restored.lenses == ["A", "B", "C"]

    def test_annealing(self):
        orch = StackOrchestrator(
            lenses=["A", "B"], annealing_seconds=300,
        )
        orch.next_phase("first")
        r2 = orch.next_phase("second")
        assert r2["annealing_suggested"] is True
        assert r2["annealing_seconds"] == 300
```

**Step 3: Write the lens stacks module**
```python
# src/auraken/lens_stacks.py
"""Lens stack transition model — reference-frame inversions.

Each lens redefines the problem. Transitions are explicit.
Named patterns in data/calibration/stack_patterns.json.
State serializes for session persistence.
"""
import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

_DEFAULT_PATTERNS_FILE = (
    Path(__file__).parent.parent.parent / "data" / "calibration" / "stack_patterns.json"
)

_TRANSITION_TEMPLATES = {
    "deep_gold": "Your answer just changed what this problem is about.",
    "shallow_gold": (
        "Notice the shift? A moment ago the question was about {prev_domain}. "
        "Now it's about {next_domain}."
    ),
    "wax": (
        "We've moved from {prev_lens} to {next_lens}. "
        "The first lens addressed {prev_domain} — now we're looking at {next_domain}."
    ),
}


def load_patterns(path: Path = _DEFAULT_PATTERNS_FILE) -> dict[str, dict]:
    if not path.exists():
        logger.warning("Stack patterns not found at %s", path)
        return {}
    data = json.loads(path.read_text())
    return data.get("patterns", {})


class StackOrchestrator:
    def __init__(
        self,
        lenses: list[str],
        depth: str = "shallow_gold",
        annealing_seconds: int = 0,
        phase_index: int = 0,
    ):
        self.lenses = lenses
        self.depth = depth
        self.annealing_seconds = annealing_seconds
        self.phase_index = phase_index

    def next_phase(self, user_input: str) -> dict:
        idx = self.phase_index
        lens = self.lenses[min(idx, len(self.lenses) - 1)]

        result = {
            "lens": lens,
            "phase_index": idx,
            "problem_redefinition": None,
            "transition_text": None,
            "annealing_suggested": False,
            "annealing_seconds": 0,
        }

        if idx > 0 and idx < len(self.lenses):
            prev_lens = self.lenses[idx - 1]
            result["problem_redefinition"] = user_input
            result["transition_text"] = self._format_transition(prev_lens, lens)
            if self.annealing_seconds > 0:
                result["annealing_suggested"] = True
                result["annealing_seconds"] = self.annealing_seconds

        self.phase_index += 1
        return result

    def _format_transition(self, prev_lens: str, next_lens: str) -> str:
        template = _TRANSITION_TEMPLATES.get(self.depth, _TRANSITION_TEMPLATES["shallow_gold"])
        if self.depth == "deep_gold":
            return template
        return template.format(
            prev_lens=prev_lens,
            next_lens=next_lens,
            prev_domain=prev_lens.lower(),
            next_domain=next_lens.lower(),
        )

    @property
    def is_complete(self) -> bool:
        return self.phase_index >= len(self.lenses)

    def to_dict(self) -> dict:
        return {
            "lenses": self.lenses,
            "depth": self.depth,
            "annealing_seconds": self.annealing_seconds,
            "phase_index": self.phase_index,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "StackOrchestrator":
        return cls(
            lenses=d["lenses"],
            depth=d.get("depth", "shallow_gold"),
            annealing_seconds=d.get("annealing_seconds", 0),
            phase_index=d.get("phase_index", 0),
        )
```

**Step 4: Run tests, commit**
```bash
cd apps/Auraken && uv run pytest tests/test_lens_stacks.py -v
git add data/calibration/stack_patterns.json src/auraken/lens_stacks.py tests/test_lens_stacks.py
git commit -m "feat(auraken): F5 lens stack transitions — session-persistent orchestrator"
```

<verify>
- run: `cd apps/Auraken && uv run pytest tests/test_lens_stacks.py -v`
  expect: exit 0
</verify>

---

### Task 6: Integration — Wire Into agent.py

**Bead:** sylveste-uais (parent epic)
**Depends:** task-1, task-2, task-4, task-5

**Files:**
- Modify: `apps/Auraken/src/auraken/agent.py:385-420` (post lens-selection curriculum hook)
- Create: `apps/Auraken/src/auraken/curriculum.py` (thin coordination layer)
- Test: `apps/Auraken/tests/test_curriculum.py`

**Key design change from rev 1:** The curriculum decision lives in `agent.py` between `select_lenses()` (line 385) and `build_system_prompt()` (line 410). This is where `user_id` is in scope and the profile can be loaded. No annotation on lens dicts — the DQ is injected into the system prompt directly or suppressed.

**Step 1: Write the failing test**
```python
# tests/test_curriculum.py
"""Tests for curriculum integration layer."""
import json
import logging
from pathlib import Path

import pytest

from auraken.curriculum import CurriculumEngine


@pytest.fixture
def engine():
    ladder_path = Path(__file__).parent.parent / "data" / "calibration" / "difficulty_ladder.json"
    if ladder_path.exists():
        data = json.loads(ladder_path.read_text())
        return CurriculumEngine(ladder=data["ladder"])
    return CurriculumEngine(ladder=[
        {"pair": ["Trilemma", "Kobayashi Maru"], "tier": "easy",
         "dq_ref": "q", "rationale": "r", "source": "stress_test"},
    ])


class TestCurriculumEngine:
    def test_find_entry(self, engine):
        if len(engine.ladder) > 1:
            first = engine.ladder[0]
            entry = engine.find_entry(tuple(first["pair"]))
            assert entry is not None

    def test_missing_pair_returns_none(self, engine):
        assert engine.find_entry(("Nonexistent", "Also Nonexistent")) is None

    def test_logs_warning_when_ladder_missing(self, caplog):
        with caplog.at_level(logging.WARNING):
            eng = CurriculumEngine(ladder_path=Path("/nonexistent/ladder.json"))
        assert "not found" in caplog.text
        assert len(eng.ladder) == 0
```

**Step 2: Write curriculum.py**
```python
# src/auraken/curriculum.py
"""Curriculum engine — loads difficulty ladder, provides DQ lookup.

The curriculum decision (present DQ or route silently) is made in
agent.py post lens-selection, not here. This module only provides
data access. should_present_dq() and depth_for_user() live in
discrimination.py where they belong (they're about user tier, not data).
"""
import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

_DEFAULT_LADDER = Path(__file__).parent.parent.parent / "data" / "calibration" / "difficulty_ladder.json"


class CurriculumEngine:
    def __init__(
        self,
        ladder: list[dict] | None = None,
        ladder_path: Path = _DEFAULT_LADDER,
    ):
        if ladder is not None:
            self.ladder = ladder
        elif ladder_path.exists():
            data = json.loads(ladder_path.read_text())
            self.ladder = data.get("ladder", [])
        else:
            logger.warning("Curriculum ladder not found at %s — DQ presentation disabled", ladder_path)
            self.ladder = []

        self._index: dict[tuple[str, str], dict] = {}
        for entry in self.ladder:
            pair = tuple(sorted(entry["pair"]))
            self._index[pair] = entry

    def find_entry(self, pair: tuple[str, str]) -> dict | None:
        return self._index.get(tuple(sorted(pair)))

    def dq_tier(self, pair: tuple[str, str]) -> str | None:
        entry = self.find_entry(pair)
        return entry["tier"] if entry else None
```

**Step 3: Wire into agent.py**

In `agent.py`, between `select_lenses()` (line 385) and `build_system_prompt()` (line 410), add:

```python
# --- Curriculum hook: DQ presentation decision ---
dq_prompt_section = ""
if len(relevant_lenses) == 2:
    from auraken.curriculum import CurriculumEngine
    from auraken.discrimination import (
        DiscriminationTracker,
        ResolutionRecord,
        depth_for_user,
        should_present_dq,
    )
    pair = tuple(sorted([relevant_lenses[0]["name"], relevant_lenses[1]["name"]]))
    engine = CurriculumEngine()
    entry = engine.find_entry(pair)
    if entry is not None:
        # Load user's discrimination history from DB
        # (query last 50 events, construct tracker)
        user_events = await _load_discrimination_events(user_id, limit=50)
        records = [ResolutionRecord.from_dict(e) for e in user_events]
        tracker = DiscriminationTracker(history=records)
        user_tier = tracker.current_tier
        depth = depth_for_user(user_tier)

        if should_present_dq(entry["tier"], user_tier):
            dq_prompt_section = (
                f"\n## Discrimination Question\n"
                f"Present this question naturally in conversation "
                f"(depth: {depth}): {entry['dq_ref']}\n\n"
            )
```

Then append `dq_prompt_section` to `system_prompt` (same pattern as `rec_prompt_section`).

**Step 4: Run tests, commit**
```bash
cd apps/Auraken && uv run pytest tests/test_curriculum.py tests/test_lenses.py -v
git add src/auraken/curriculum.py src/auraken/agent.py tests/test_curriculum.py
git commit -m "feat(auraken): wire curriculum into agent.py — DQ presentation in conversation handler"
```

<verify>
- run: `cd apps/Auraken && uv run pytest tests/test_curriculum.py -v`
  expect: exit 0
- run: `cd apps/Auraken && uv run pytest tests/ -v --timeout=30`
  expect: exit 0
</verify>
