---
artifact_type: plan
bead: sylveste-r3jf
stage: design
requirements:
  - F2: Domain/Discipline Audit + Lattice Type Extension
  - G5: Canonical query authority (scaffold)
  - G11: Domain/Discipline audit
related_artifacts:
  prd: docs/prds/2026-04-21-persona-lens-ontology.md
  errata: docs/research/2026-04-27-lattice-reconciliation.md
---
# F2: Domain/Discipline Audit + Lattice Type Extension — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-r3jf
**Goal:** Run the lexical Domain/Discipline overlap audit and extend lattice's type system with persona/lens entity types and relationship metadata fields (G3/G4/G7), so F3 (schema) and F4 (connectors) have a stable target.

**Architecture:** Two sequenced workstreams in one plan. **Workstream A** (audit) ships a Python script under `interverse/lattice/scripts/` that reads fd-agent frontmatter (`domains:`) and Auraken/interlens lenses (`discipline:`), computes lexical overlap (token-set Jaccard + normalized edit distance), and writes a stable-schema JSON + rendered Markdown verdict. **Workstream B** (lattice extension) adds a `FieldSpec` type + relationship-metadata registry to `rules.py`, an entity-metadata registry to `families.py`, registers persona/lens/domain/discipline/source entity types, extends builtin rules with the persona/lens relationship vocabulary (`wields`, `bridges`, `same-as`, `cites`, `derives-from`, `in-domain`, `in-discipline`, `supersedes`), and registers G3/G4/G7 metadata fields. Workstream B reads workstream A's verdict to choose between four-type (collapsed `domain_discipline`) and five-type (separate `domain` + `discipline`) registration.

**Tech Stack:** Python 3.12 + `uv` + `pytest` + `ruff` (lattice's existing toolchain). `pyyaml` for frontmatter parsing (added to dev deps). Stdlib for the rest of the audit (`pathlib`, `json`, `difflib`, `dataclasses`) — no embeddings (G3 calibration discipline; embeddings deferred to F5).

**Modeling note (post-review):** The reconciliation doc (`docs/research/2026-04-27-lattice-reconciliation.md`) maps `bridges` and `same-as` to the Annotation rule conceptually. This plan places them as direct Artifact×Artifact edges in the Structure rule, with G3/G4 fields hanging off the edge via the relationship-metadata registry. Rationale: lens-to-lens edges are the natural query shape (e.g., "which lenses bridge to lens X"), and edge-metadata captures G3/G4 the same way a Relationship-entity wrapper would. Future Evidence annotation of specific edges remains possible — Evidence can `cites`/`derives-from` either endpoint or, if needed in V2, a separate `bridges-assessment` relationship can be added to the Annotation rule for explicit dispute/strengthen workflows. This decision is documented here rather than silently encoded.

**Prior Learnings:**
- `docs/research/assess-ontology-stores-2026-04-21.md` — earlier AGE assessment, **superseded** by lattice reconciliation. Do not use AGE/Cypher framing.
- `docs/research/2026-04-27-lattice-reconciliation.md` — authoritative scope for this plan; the seven PRD entity types map onto five lattice families (Persona→Actor; Lens/Domain/Discipline/Source→Artifact subtypes; Evidence→Evidence). `bridges`/`same-as` map onto the Annotation rule. F1 (Cypher benchmark) is orphan research; do not gate on it.
- Lattice connector pattern (`interverse/lattice/src/lattice/connectors/`) — F4 territory, **out of scope** for this plan. F2 only registers types; F4 wires importers.

**Counts (verified 2026-04-28):**
- 768 canonical fd-agents in `*/.claude/agents/` (excluding plugin caches), across 8 directories (apps/Auraken, apps/Autarch, apps/Khouri, .claude, interverse/interkasten, interverse/tldr-swinton, os/Clavain, os/Skaffen). 609 declare `domains:`, 25 declare singular `domain:`.
- 291 Auraken lenses at `apps/Auraken/src/auraken/lens_library_v2.json` with 113 distinct `discipline` values.
- 258 interlens lenses at `interverse/interlens/apps/api/all_lenses_for_analysis.json` (no `discipline` field — has `type`/`episode`).
- **Note:** PRD/bead-notes counts (660, 781, 288) are stale; the audit's actual totals are the canonical numbers and will be recorded in the JSON output as `corpus_counts`.

---

## Must-Haves

**Truths:**
- The audit produces a stable-schema JSON file at `docs/research/f2-domain-discipline-audit.json` that any future tool (e.g., lattice-web V0) can read without parsing Markdown.
- The audit's Markdown render at `docs/research/f2-domain-discipline-audit.md` ends with a single explicit recommendation token: `RECOMMENDATION: collapse` or `RECOMMENDATION: keep-separate`, with a one-paragraph rationale tied to numeric thresholds.
- After workstream B, `uv run pytest tests/ -v` in `interverse/lattice/` passes with all existing tests still green and ≥ 12 new tests covering the extensions.
- `register_relationship_metadata("bridges", ...)` makes `get_relationship_metadata("bridges")` return the three-field schema (`directed`, `activation_delay`, `strength`).
- Every registered persona/lens entity type appears in `list_entity_types()` after `_register_builtins()` runs.
- Workstream B's entity-type registration matches the audit verdict — collapse → register 4 (persona, lens, domain_discipline, source); keep-separate → register 5 (persona, lens, domain, discipline, source).

**Artifacts:**
- [`interverse/lattice/scripts/audit_domains.py`] exports `main()` and is `python -m`-runnable.
- [`interverse/lattice/scripts/__init__.py`] empty (package marker).
- [`interverse/lattice/tests/test_audit_domains.py`] exports test cases for parser, overlap math, and verdict logic.
- [`docs/research/f2-domain-discipline-audit.json`] canonical JSON with `corpus_counts`, `domains[]`, `disciplines[]`, `overlap_matrix`, `metrics`, `recommendation`.
- [`docs/research/f2-domain-discipline-audit.md`] rendered MD ending with `RECOMMENDATION: <verdict>`.
- [`interverse/lattice/src/lattice/schemas.py`] (new) exports `FieldSpec` — frozen dataclass shared by entity-metadata and relationship-metadata.
- [`interverse/lattice/src/lattice/rules.py`] imports `FieldSpec` from `schemas`; adds `register_relationship_metadata`, `get_relationship_metadata`, `_relationship_metadata` registry, plus G3/G4 metadata registrations.
- [`interverse/lattice/src/lattice/families.py`] imports `FieldSpec` from `schemas`; extends `EntityType` with `metadata_fields: list[FieldSpec]`; registers persona/lens entity types using a code-time `LATTICE_F2_VERDICT` constant; registers G7 evidence `strength_grade` metadata.
- [`interverse/lattice/pyproject.toml`] adds `pyyaml` dep (frontmatter parsing).
- [`interverse/lattice/tests/test_persona_lens_extensions.py`] new test file for the extensions.
- [`interverse/lattice/AGENTS.md`] gains a "Persona/Lens Type Catalog" section.

**Key Links:**
- Workstream A → audit JSON → Task 11 (entity-type registration shape) reads `recommendation` field.
- Workstream B's `FieldSpec` lives in a new `interverse/lattice/src/lattice/schemas.py` (zero internal lattice imports). Both `families.py` and `rules.py` import from `schemas.py`. This avoids the circular-import risk *and* keeps `families.py` focused on type-family logic.
- `get_valid_relationship_types(Actor, Artifact)` after Task 9 must include `wields`; after Task 9 `get_valid_relationship_types(Artifact, Artifact)` must include `in-domain`, `in-discipline`, `bridges`, `same-as`.
- Lattice's `_fresh_registry` and `_fresh_rules` test fixtures already isolate state — every new test must use them or risk leaking registrations.

---

## Task 1: Audit script skeleton + frontmatter parser

**Files:**
- Modify: `interverse/lattice/pyproject.toml` (add `pyyaml` to dependencies)
- Create: `interverse/lattice/scripts/__init__.py` (empty)
- Create: `interverse/lattice/scripts/audit_domains.py`
- Create: `interverse/lattice/tests/test_audit_domains.py`

**Step 0: Add pyyaml dep**
In `interverse/lattice/pyproject.toml`, add `"pyyaml>=6.0"` to `dependencies`. Then `cd interverse/lattice && uv sync --extra dev`.

**Step 1: Write the failing test**
```python
# interverse/lattice/tests/test_audit_domains.py
"""Tests for F2 domain/discipline audit."""
from pathlib import Path
import pytest

from scripts.audit_domains import (
    parse_fd_agent_frontmatter,
    parse_auraken_lenses,
    parse_interlens_lenses,
    AgentRecord,
    LensRecord,
)


def test_parse_fd_agent_frontmatter_with_domains_list(tmp_path):
    f = tmp_path / "fd-temporal-projection.md"
    f.write_text(
        "---\n"
        "model: sonnet\n"
        "tier: used\n"
        "domains:\n"
        "- forecasting\n"
        "- temporal-reasoning\n"
        "---\n"
        "# fd-temporal-projection — Task-Specific Reviewer\n"
    )
    rec = parse_fd_agent_frontmatter(f)
    assert isinstance(rec, AgentRecord)
    assert rec.name == "fd-temporal-projection"
    assert rec.domains == ["forecasting", "temporal-reasoning"]
    assert rec.path == f


def test_parse_fd_agent_frontmatter_with_singular_domain(tmp_path):
    f = tmp_path / "fd-foo.md"
    f.write_text("---\ndomain: governance\n---\n# fd-foo\n")
    rec = parse_fd_agent_frontmatter(f)
    assert rec.domains == ["governance"]


def test_parse_fd_agent_frontmatter_with_quoted_scalar(tmp_path):
    f = tmp_path / "fd-quoted.md"
    f.write_text('---\ndomain: "temporal reasoning"\n---\n# fd-quoted\n')
    rec = parse_fd_agent_frontmatter(f)
    assert rec.domains == ["temporal reasoning"]


def test_parse_fd_agent_frontmatter_with_inline_list(tmp_path):
    f = tmp_path / "fd-inline.md"
    f.write_text("---\ndomains: [forecasting, temporal-reasoning]\n---\n# fd-inline\n")
    rec = parse_fd_agent_frontmatter(f)
    assert set(rec.domains) == {"forecasting", "temporal-reasoning"}


def test_parse_fd_agent_frontmatter_handles_crlf(tmp_path):
    """Windows line endings must not silently zero out domains."""
    f = tmp_path / "fd-crlf.md"
    f.write_bytes(b"---\r\ndomains:\r\n- governance\r\n---\r\n# fd-crlf\r\n")
    rec = parse_fd_agent_frontmatter(f)
    assert rec.domains == ["governance"]


def test_parse_fd_agent_frontmatter_no_domains(tmp_path):
    f = tmp_path / "fd-bar.md"
    f.write_text("---\nmodel: sonnet\n---\n# fd-bar\n")
    rec = parse_fd_agent_frontmatter(f)
    assert rec.domains == []


def test_parse_fd_agent_frontmatter_no_frontmatter(tmp_path):
    f = tmp_path / "fd-empty.md"
    f.write_text("# fd-empty\nno frontmatter at all\n")
    rec = parse_fd_agent_frontmatter(f)
    assert rec.domains == []
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'scripts'` or `ImportError`.

**Step 3: Write minimal implementation**
```python
# interverse/lattice/scripts/audit_domains.py
"""F2 Domain/Discipline audit (G11).

Reads fd-agent frontmatter and Auraken/interlens lens libraries; computes
lexical overlap; emits a stable-schema JSON + rendered Markdown report
with an explicit collapse-vs-keep-separate recommendation.

Lexical-only by design — embeddings are deferred to F5 per the G3
calibration commitment in the persona-lens PRD.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

import yaml


@dataclass
class AgentRecord:
    name: str
    path: Path
    domains: list[str] = field(default_factory=list)


@dataclass
class LensRecord:
    id: str
    source: str  # "auraken" | "interlens"
    name: str
    discipline: str | None = None


# Match opening and closing `---` markers tolerantly: support both \n and \r\n
# line endings, and accept the closing fence either followed by a newline or at EOF.
_FRONTMATTER_RE = re.compile(r"^---\r?\n(.*?)\r?\n---(?:\r?\n|\Z)", re.DOTALL)


def _extract_frontmatter(text: str) -> str | None:
    m = _FRONTMATTER_RE.match(text)
    return m.group(1) if m else None


def _coerce_domains(value) -> list[str]:
    """Normalize a YAML-parsed value into a list of domain strings."""
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v).strip() for v in value if v is not None and str(v).strip()]
    return [str(value).strip()] if str(value).strip() else []


def parse_fd_agent_frontmatter(path: Path) -> AgentRecord:
    text = path.read_text(encoding="utf-8", errors="replace")
    fm_text = _extract_frontmatter(text)
    domains: list[str] = []
    if fm_text:
        try:
            fm = yaml.safe_load(fm_text) or {}
        except yaml.YAMLError:
            fm = {}
        if isinstance(fm, dict):
            # Prefer plural `domains:`; fall back to singular `domain:`.
            domains = _coerce_domains(fm.get("domains")) or _coerce_domains(fm.get("domain"))
    return AgentRecord(name=path.stem, path=path, domains=domains)


def parse_auraken_lenses(json_path: Path) -> list[LensRecord]:
    raw = json.loads(json_path.read_text(encoding="utf-8"))
    out: list[LensRecord] = []
    for entry in raw:
        out.append(LensRecord(
            id=entry["id"],
            source="auraken",
            name=entry.get("name", entry["id"]),
            discipline=entry.get("discipline") or None,
        ))
    return out


def parse_interlens_lenses(json_path: Path) -> list[LensRecord]:
    raw = json.loads(json_path.read_text(encoding="utf-8"))
    out: list[LensRecord] = []
    for entry in raw:
        out.append(LensRecord(
            id=entry["id"],
            source="interlens",
            name=entry.get("name", entry["id"]),
            discipline=None,  # interlens has no discipline field
        ))
    return out


def main() -> int:
    raise NotImplementedError("wired in Task 5")


if __name__ == "__main__":
    raise SystemExit(main())
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
Expected: 3 tests PASS.

**Step 5: Commit**
```bash
git add interverse/lattice/scripts/__init__.py \
        interverse/lattice/scripts/audit_domains.py \
        interverse/lattice/tests/test_audit_domains.py
git commit -m "feat(lattice/f2): audit script skeleton + fd-agent/lens parsers"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
  expect: exit 0
- run: `cd interverse/lattice && uv run python -c "from scripts.audit_domains import parse_fd_agent_frontmatter, AgentRecord; print(AgentRecord(name='x', path=__file__).domains)"`
  expect: contains "[]"
</verify>

---

## Task 2: Lexical overlap math (Jaccard + normalized edit distance)

**Files:**
- Modify: `interverse/lattice/scripts/audit_domains.py` (add overlap functions)
- Modify: `interverse/lattice/tests/test_audit_domains.py` (append tests)

**Step 1: Write the failing test (append to existing file)**
```python
from scripts.audit_domains import (
    tokenize,
    jaccard,
    normalized_edit_similarity,
    pair_similarity,
)


def test_tokenize_lowercases_and_splits():
    assert tokenize("Forecasting & Time-Series") == {"forecasting", "time", "series"}
    assert tokenize("management science") == {"management", "science"}


def test_tokenize_keeps_short_identifiers():
    # Domain identifiers like "r" (R language) or "go" must survive.
    assert tokenize("R") == {"r"}
    assert tokenize("go") == {"go"}


def test_jaccard_identical():
    assert jaccard({"a", "b"}, {"a", "b"}) == 1.0


def test_jaccard_disjoint():
    assert jaccard({"a"}, {"b"}) == 0.0


def test_jaccard_partial():
    # |∩|=1, |∪|=3 → 1/3
    assert abs(jaccard({"a", "b"}, {"a", "c"}) - 1 / 3) < 1e-9


def test_jaccard_both_empty():
    # convention: empty-vs-empty is 0 (avoids div-by-zero false-match)
    assert jaccard(set(), set()) == 0.0


def test_normalized_edit_similarity_identical():
    assert normalized_edit_similarity("foo", "foo") == 1.0


def test_normalized_edit_similarity_known_close():
    # difflib SequenceMatcher ratio for "governance" vs "governing" is well > 0.7
    assert normalized_edit_similarity("governance", "governing") > 0.7


def test_pair_similarity_combines_jaccard_and_edit():
    # exact match should give 1.0 from both axes
    sim = pair_similarity("management science", "management science")
    assert sim == 1.0
    # disjoint tokens should give a low score
    assert pair_similarity("forecasting", "perfumery") < 0.4
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
Expected: 8 new tests FAIL with `ImportError: cannot import name 'tokenize'`.

**Step 3: Write minimal implementation (append to `audit_domains.py`)**
```python
from difflib import SequenceMatcher

_TOKEN_RE = re.compile(r"[a-z0-9]+")


def tokenize(s: str) -> set[str]:
    """Lowercase and split on non-alphanumeric. No length filter — domain
    identifiers like `r` and `go` are atomic and must survive tokenization.
    """
    return set(_TOKEN_RE.findall(s.lower()))


def jaccard(a: set[str], b: set[str]) -> float:
    if not a and not b:
        return 0.0
    return len(a & b) / len(a | b)


def normalized_edit_similarity(a: str, b: str) -> float:
    """SequenceMatcher ratio — treats whole strings as char sequences."""
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()


def pair_similarity(a: str, b: str) -> float:
    """Combined token-set + edit-similarity score in [0, 1].

    Average of Jaccard(tokens) and normalized edit-distance similarity.
    Captures both word-overlap ("management science" vs "management") and
    near-spelling matches ("governance" vs "governing").
    """
    j = jaccard(tokenize(a), tokenize(b))
    e = normalized_edit_similarity(a, b)
    return (j + e) / 2.0
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
Expected: 11 tests PASS (3 from Task 1 + 8 new).

**Step 5: Commit**
```bash
git add interverse/lattice/scripts/audit_domains.py interverse/lattice/tests/test_audit_domains.py
git commit -m "feat(lattice/f2): tokenize + Jaccard + edit-similarity primitives"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
  expect: exit 0
</verify>

---

## Task 3: Overlap matrix + verdict logic

**Files:**
- Modify: `interverse/lattice/scripts/audit_domains.py`
- Modify: `interverse/lattice/tests/test_audit_domains.py`

**Step 1: Write the failing test**
```python
from scripts.audit_domains import (
    compute_overlap_matrix,
    decide_recommendation,
    OverlapResult,
)


def test_compute_overlap_matrix_basic():
    domains = {"governance", "forecasting"}
    disciplines = {"governance", "perfumery"}
    result = compute_overlap_matrix(domains, disciplines, threshold=0.7)
    assert isinstance(result, OverlapResult)
    # "governance" matches itself perfectly across spaces
    assert result.domain_match_count == 1   # 1 of 2 domains matches a discipline
    assert result.discipline_match_count == 1
    # exact match has score 1.0
    pairs = {(p["domain"], p["discipline"]): p["score"] for p in result.high_confidence_pairs}
    assert pairs[("governance", "governance")] == 1.0


def test_decide_recommendation_collapse_when_high_overlap():
    # Both directions ≥ 30% match → collapse
    result = OverlapResult(
        domain_match_count=8, domain_total=20,
        discipline_match_count=12, discipline_total=30,
        high_confidence_pairs=[],
        threshold=0.7,
    )
    rec = decide_recommendation(result)
    assert rec.verdict == "collapse"
    assert "0.40" in rec.rationale or "40%" in rec.rationale


def test_decide_recommendation_keep_when_low_overlap():
    result = OverlapResult(
        domain_match_count=2, domain_total=20,
        discipline_match_count=3, discipline_total=30,
        high_confidence_pairs=[],
        threshold=0.7,
    )
    rec = decide_recommendation(result)
    assert rec.verdict == "keep-separate"


def test_decide_recommendation_keep_when_asymmetric():
    # 50% of domains match disciplines but only 5% vice versa → keep
    result = OverlapResult(
        domain_match_count=10, domain_total=20,
        discipline_match_count=2, discipline_total=40,
        high_confidence_pairs=[],
        threshold=0.7,
    )
    rec = decide_recommendation(result)
    assert rec.verdict == "keep-separate"
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
Expected: 4 new tests FAIL.

**Step 3: Write minimal implementation**
```python
# Append to audit_domains.py

@dataclass
class OverlapResult:
    domain_match_count: int
    domain_total: int
    discipline_match_count: int
    discipline_total: int
    high_confidence_pairs: list[dict]  # [{domain, discipline, score}, ...]
    threshold: float


@dataclass
class Recommendation:
    verdict: str  # "collapse" | "keep-separate"
    rationale: str
    domain_coverage: float
    discipline_coverage: float


COLLAPSE_THRESHOLD = 0.30  # both directions must clear this


def compute_overlap_matrix(
    domains: set[str], disciplines: set[str], threshold: float = 0.7,
) -> OverlapResult:
    """For each domain × discipline pair, compute pair_similarity.
    Count how many domains have at least one discipline above `threshold`,
    and vice versa. Record the matched pairs for the report.
    """
    matched_pairs: list[dict] = []
    domain_matched: set[str] = set()
    discipline_matched: set[str] = set()
    for d in domains:
        for disc in disciplines:
            score = pair_similarity(d, disc)
            if score >= threshold:
                matched_pairs.append({"domain": d, "discipline": disc, "score": round(score, 4)})
                domain_matched.add(d)
                discipline_matched.add(disc)
    return OverlapResult(
        domain_match_count=len(domain_matched),
        domain_total=len(domains),
        discipline_match_count=len(discipline_matched),
        discipline_total=len(disciplines),
        high_confidence_pairs=sorted(matched_pairs, key=lambda p: -p["score"]),
        threshold=threshold,
    )


def decide_recommendation(result: OverlapResult) -> Recommendation:
    """Collapse iff both spaces clear COLLAPSE_THRESHOLD coverage; otherwise keep-separate.

    Rationale: collapsing is a one-way schema decision. Asymmetric overlap
    (one space substantially absorbs the other but not vice versa) signals
    that the spaces are nested or partially-overlapping, not equivalent —
    which is the keep-separate-with-bridges case.
    """
    dom_cov = result.domain_match_count / max(1, result.domain_total)
    disc_cov = result.discipline_match_count / max(1, result.discipline_total)
    if dom_cov >= COLLAPSE_THRESHOLD and disc_cov >= COLLAPSE_THRESHOLD:
        verdict = "collapse"
    else:
        verdict = "keep-separate"
    return Recommendation(
        verdict=verdict,
        rationale=(
            f"Domain coverage: {dom_cov:.2f} ({result.domain_match_count}/{result.domain_total}). "
            f"Discipline coverage: {disc_cov:.2f} ({result.discipline_match_count}/{result.discipline_total}). "
            f"Threshold: both ≥ {COLLAPSE_THRESHOLD:.2f} for collapse."
        ),
        domain_coverage=round(dom_cov, 4),
        discipline_coverage=round(disc_cov, 4),
    )
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
Expected: all 15 tests PASS.

**Step 5: Commit**
```bash
git add interverse/lattice/scripts/audit_domains.py interverse/lattice/tests/test_audit_domains.py
git commit -m "feat(lattice/f2): overlap matrix + collapse/keep-separate verdict logic"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
  expect: exit 0
</verify>

---

## Task 4: JSON output + Markdown render

**Files:**
- Modify: `interverse/lattice/scripts/audit_domains.py`
- Modify: `interverse/lattice/tests/test_audit_domains.py`

**Step 1: Write the failing test**
```python
from scripts.audit_domains import build_audit_payload, render_markdown


def test_build_audit_payload_has_stable_schema():
    payload = build_audit_payload(
        agents=[AgentRecord(name="fd-foo", path=Path("x.md"), domains=["governance"])],
        auraken_lenses=[LensRecord(id="l1", source="auraken", name="L1", discipline="governance")],
        interlens_lenses=[LensRecord(id="i1", source="interlens", name="I1", discipline=None)],
    )
    # Stable schema — these keys are part of the contract for downstream consumers.
    assert set(payload.keys()) >= {
        "schema_version", "generated_at", "corpus_counts",
        "domains", "disciplines", "overlap_matrix", "metrics", "recommendation",
    }
    assert payload["schema_version"] == "1.0"
    assert payload["corpus_counts"]["fd_agents"] == 1
    assert payload["corpus_counts"]["auraken_lenses"] == 1
    assert payload["corpus_counts"]["interlens_lenses"] == 1
    assert payload["domains"] == ["governance"]
    assert payload["disciplines"] == ["governance"]


def test_render_markdown_ends_with_recommendation_token():
    payload = build_audit_payload(
        agents=[AgentRecord(name="fd-foo", path=Path("x.md"), domains=["governance"])],
        auraken_lenses=[LensRecord(id="l1", source="auraken", name="L1", discipline="governance")],
        interlens_lenses=[],
    )
    md = render_markdown(payload)
    last_lines = [ln for ln in md.strip().split("\n") if ln.strip()][-3:]
    last_block = "\n".join(last_lines)
    assert "RECOMMENDATION:" in last_block
    assert payload["recommendation"]["verdict"] in last_block
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
Expected: 2 new tests FAIL.

**Step 3: Write minimal implementation**
```python
# Append to audit_domains.py

from datetime import datetime, timezone

SCHEMA_VERSION = "1.0"


def build_audit_payload(
    agents: list[AgentRecord],
    auraken_lenses: list[LensRecord],
    interlens_lenses: list[LensRecord],
) -> dict:
    domains: set[str] = set()
    for a in agents:
        domains.update(a.domains)
    disciplines: set[str] = {l.discipline for l in auraken_lenses if l.discipline}
    overlap = compute_overlap_matrix(domains, disciplines)
    rec = decide_recommendation(overlap)
    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "corpus_counts": {
            "fd_agents": len(agents),
            "auraken_lenses": len(auraken_lenses),
            "interlens_lenses": len(interlens_lenses),
            "distinct_domains": len(domains),
            "distinct_disciplines": len(disciplines),
        },
        "domains": sorted(domains),
        "disciplines": sorted(disciplines),
        "overlap_matrix": {
            "threshold": overlap.threshold,
            "high_confidence_pairs": overlap.high_confidence_pairs,
        },
        "metrics": {
            "domain_match_count": overlap.domain_match_count,
            "domain_total": overlap.domain_total,
            "discipline_match_count": overlap.discipline_match_count,
            "discipline_total": overlap.discipline_total,
            "domain_coverage": rec.domain_coverage,
            "discipline_coverage": rec.discipline_coverage,
        },
        "recommendation": {
            "verdict": rec.verdict,
            "rationale": rec.rationale,
        },
    }


def render_markdown(payload: dict) -> str:
    cc = payload["corpus_counts"]
    rec = payload["recommendation"]
    metrics = payload["metrics"]
    pairs = payload["overlap_matrix"]["high_confidence_pairs"][:25]  # top 25
    lines = [
        f"# F2 Domain/Discipline Audit",
        f"",
        f"_Generated: {payload['generated_at']} (schema {payload['schema_version']})_",
        f"",
        f"## Corpus",
        f"",
        f"| Source | Count |",
        f"|---|---|",
        f"| fd-agents | {cc['fd_agents']} |",
        f"| Auraken lenses | {cc['auraken_lenses']} |",
        f"| interlens lenses | {cc['interlens_lenses']} |",
        f"| distinct domains | {cc['distinct_domains']} |",
        f"| distinct disciplines | {cc['distinct_disciplines']} |",
        f"",
        f"## Coverage",
        f"",
        f"- Domain coverage (domains with a near-match in disciplines): "
        f"**{metrics['domain_coverage']:.2%}** ({metrics['domain_match_count']}/{metrics['domain_total']})",
        f"- Discipline coverage (disciplines with a near-match in domains): "
        f"**{metrics['discipline_coverage']:.2%}** ({metrics['discipline_match_count']}/{metrics['discipline_total']})",
        f"",
        f"## Top high-confidence pairs (threshold {payload['overlap_matrix']['threshold']})",
        f"",
        f"| Domain | Discipline | Score |",
        f"|---|---|---|",
    ]
    for p in pairs:
        lines.append(f"| {p['domain']} | {p['discipline']} | {p['score']} |")
    if not pairs:
        lines.append(f"| _(none above threshold)_ | | |")
    lines += [
        f"",
        f"## Verdict",
        f"",
        rec["rationale"],
        f"",
        f"`RECOMMENDATION: {rec['verdict']}`",
        f"",
    ]
    return "\n".join(lines) + "\n"
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
Expected: all 17 tests PASS.

**Step 5: Commit**
```bash
git add interverse/lattice/scripts/audit_domains.py interverse/lattice/tests/test_audit_domains.py
git commit -m "feat(lattice/f2): JSON payload + Markdown render with verdict token"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
  expect: exit 0
</verify>

---

## Task 5: Wire `main()` to discover canonical inputs and write artifacts

**Files:**
- Modify: `interverse/lattice/scripts/audit_domains.py` (replace `main()` and add CLI args)
- Modify: `interverse/lattice/tests/test_audit_domains.py` (add an end-to-end test against a tmp tree)

**Step 1: Write the failing test**
```python
import subprocess
import sys


def test_main_end_to_end(tmp_path, monkeypatch):
    # Build a synthetic monorepo
    repo = tmp_path / "repo"
    agents_dir = repo / ".claude" / "agents"
    agents_dir.mkdir(parents=True)
    (agents_dir / "fd-governance.md").write_text(
        "---\ndomains:\n- governance\n---\n# fd-governance\n"
    )
    auraken_path = repo / "apps" / "Auraken" / "src" / "auraken" / "lens_library_v2.json"
    auraken_path.parent.mkdir(parents=True)
    auraken_path.write_text(json.dumps([
        {"id": "l1", "name": "L1", "discipline": "governance"},
    ]))
    interlens_path = repo / "interverse" / "interlens" / "apps" / "api" / "all_lenses_for_analysis.json"
    interlens_path.parent.mkdir(parents=True)
    interlens_path.write_text(json.dumps([{"id": "i1", "name": "I1"}]))
    out_json = tmp_path / "audit.json"
    out_md = tmp_path / "audit.md"

    from scripts.audit_domains import run_audit
    payload = run_audit(
        repo_root=repo,
        auraken_path=auraken_path,
        interlens_path=interlens_path,
        json_out=out_json,
        md_out=out_md,
    )
    assert out_json.exists() and out_md.exists()
    written = json.loads(out_json.read_text())
    assert written["corpus_counts"]["fd_agents"] == 1
    assert written["recommendation"]["verdict"] in {"collapse", "keep-separate"}
    assert "RECOMMENDATION:" in out_md.read_text()
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py::test_main_end_to_end -v`
Expected: FAIL — `run_audit` is not defined.

**Step 3: Write minimal implementation (replace the stub `main()`)**
```python
import argparse
import sys

CANONICAL_AGENT_DIRS_GLOB = "**/.claude/agents/fd-*.md"
EXCLUDE_PATH_PARTS = ("plugins/cache", "node_modules", ".git")


def discover_fd_agents(repo_root: Path) -> list[Path]:
    out: list[Path] = []
    for p in repo_root.glob(CANONICAL_AGENT_DIRS_GLOB):
        if any(part in str(p) for part in EXCLUDE_PATH_PARTS):
            continue
        out.append(p)
    return sorted(out)


def run_audit(
    repo_root: Path,
    auraken_path: Path,
    interlens_path: Path,
    json_out: Path,
    md_out: Path,
) -> dict:
    agent_paths = discover_fd_agents(repo_root)
    agents = [parse_fd_agent_frontmatter(p) for p in agent_paths]
    auraken = parse_auraken_lenses(auraken_path) if auraken_path.exists() else []
    interlens = parse_interlens_lenses(interlens_path) if interlens_path.exists() else []
    payload = build_audit_payload(agents, auraken, interlens)
    json_out.parent.mkdir(parents=True, exist_ok=True)
    md_out.parent.mkdir(parents=True, exist_ok=True)
    json_out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    md_out.write_text(render_markdown(payload), encoding="utf-8")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="F2 Domain/Discipline audit")
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--auraken",
        type=Path,
        default=Path("apps/Auraken/src/auraken/lens_library_v2.json"),
    )
    parser.add_argument(
        "--interlens",
        type=Path,
        default=Path("interverse/interlens/apps/api/all_lenses_for_analysis.json"),
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        default=Path("docs/research/f2-domain-discipline-audit.json"),
    )
    parser.add_argument(
        "--md-out",
        type=Path,
        default=Path("docs/research/f2-domain-discipline-audit.md"),
    )
    args = parser.parse_args()
    payload = run_audit(
        repo_root=args.repo_root,
        auraken_path=args.auraken,
        interlens_path=args.interlens,
        json_out=args.json_out,
        md_out=args.md_out,
    )
    print(f"Audit complete. Verdict: {payload['recommendation']['verdict']}", file=sys.stderr)
    print(f"  JSON: {args.json_out}", file=sys.stderr)
    print(f"  MD:   {args.md_out}", file=sys.stderr)
    return 0
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
Expected: all 18 tests PASS.

**Step 5: Commit**
```bash
git add interverse/lattice/scripts/audit_domains.py interverse/lattice/tests/test_audit_domains.py
git commit -m "feat(lattice/f2): wire audit main() with canonical-input discovery"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/test_audit_domains.py -v`
  expect: exit 0
- run: `cd interverse/lattice && uv run ruff check src/ scripts/ tests/`
  expect: exit 0
</verify>

---

## Task 6: Run audit, commit artifacts, record verdict on bead

**Files:**
- Create: `docs/research/f2-domain-discipline-audit.json`
- Create: `docs/research/f2-domain-discipline-audit.md`

**Step 1: Run the audit from the monorepo root**
```bash
cd interverse/lattice
uv run python -m scripts.audit_domains \
  --repo-root ../.. \
  --auraken ../../apps/Auraken/src/auraken/lens_library_v2.json \
  --interlens ../../interverse/interlens/apps/api/all_lenses_for_analysis.json \
  --json-out ../../docs/research/f2-domain-discipline-audit.json \
  --md-out  ../../docs/research/f2-domain-discipline-audit.md
```

**Step 2: Sanity-check the output**
- Eyeball top-of-MD `## Corpus` table — fd-agents should be ~768, Auraken ~291, interlens ~258.
- Eyeball top high-confidence pairs — they should be plausible domain/discipline alignments.
- Tail of MD must end with `RECOMMENDATION: collapse` or `RECOMMENDATION: keep-separate`.

**Step 3: Record verdict on the bead**
```bash
verdict=$(jq -r '.recommendation.verdict' docs/research/f2-domain-discipline-audit.json)
bd set-state sylveste-r3jf "f2_audit_verdict=$verdict" \
  --reason "F2 audit complete; lattice extension shape determined"
echo "Recorded verdict: $verdict"
```

**Step 4: Commit artifacts**
```bash
git add docs/research/f2-domain-discipline-audit.json docs/research/f2-domain-discipline-audit.md
git commit -m "docs(f2): domain/discipline audit results — verdict $(jq -r '.recommendation.verdict' docs/research/f2-domain-discipline-audit.json)"
```

<verify>
- run: `jq -r '.recommendation.verdict' docs/research/f2-domain-discipline-audit.json`
  expect: contains "collapse"
- run: `tail -3 docs/research/f2-domain-discipline-audit.md`
  expect: contains "RECOMMENDATION:"
- run: `bd state sylveste-r3jf f2_audit_verdict`
  expect: contains "collapse"
</verify>

> **Workstream A complete. Workstream B begins below — the entity-type registration in Task 11 reads `f2_audit_verdict` to choose between four-type (collapse) and five-type (keep-separate) registration.**

---

## Task 7: Add `schemas.py` with `FieldSpec` + entity-metadata on `EntityType`

**Files:**
- Create: `interverse/lattice/src/lattice/schemas.py` (new — holds `FieldSpec`)
- Modify: `interverse/lattice/src/lattice/families.py` (import `FieldSpec` from `schemas`; extend `EntityType`)
- Create: `interverse/lattice/tests/test_persona_lens_extensions.py`

`FieldSpec` is a generic schema primitive used by *both* entity-metadata and relationship-metadata. Putting it in its own zero-dependency module avoids the otherwise-circular `rules.py` ↔ `families.py` import (when `rules.py` would need `FieldSpec` and `families.py` would also need it).

**Step 1: Write the failing test**
```python
# interverse/lattice/tests/test_persona_lens_extensions.py
"""Tests for persona/lens entity-type extensions and relationship metadata."""
import pytest

from lattice.schemas import FieldSpec
from lattice.families import (
    EntityType, TypeFamily,
    register_entity_type, get_entity_type,
    reset_registry,
    _register_builtins,
)


@pytest.fixture(autouse=True)
def _fresh():
    from lattice.rules import _register_builtin_rules, reset_rules
    reset_registry(); _register_builtins()
    reset_rules(); _register_builtin_rules()
    yield
    reset_registry(); _register_builtins()
    reset_rules(); _register_builtin_rules()


class TestFieldSpec:
    def test_scalar_field(self):
        fs = FieldSpec(name="strength", type_name="float")
        assert fs.name == "strength"
        assert fs.type_name == "float"
        assert fs.enum_values == ()
        assert fs.required is True

    def test_enum_field(self):
        fs = FieldSpec(
            name="activation_delay",
            type_name="enum",
            enum_values=("immediate", "short", "medium", "long"),
        )
        assert "immediate" in fs.enum_values

    def test_field_spec_is_hashable(self):
        # frozen dataclass — usable as dict keys / set members
        fs = FieldSpec(name="x", type_name="bool")
        assert hash(fs) is not None


class TestEntityMetadataFields:
    def test_entity_type_supports_metadata_fields(self):
        finding = EntityType(
            name="finding",
            families=[TypeFamily.EVIDENCE],
            diagnostic_property="finding_id",
            metadata_fields=[
                FieldSpec(
                    name="strength_grade", type_name="enum",
                    enum_values=("sahih", "hasan", "da'if", "mawdu"),
                ),
            ],
        )
        register_entity_type(finding)
        et = get_entity_type("finding")
        assert et is not None
        assert len(et.metadata_fields) == 1
        assert et.metadata_fields[0].name == "strength_grade"

    def test_existing_entity_types_still_work(self):
        # Backwards-compat: existing types have empty metadata_fields by default.
        et = get_entity_type("file")
        assert et is not None
        assert et.metadata_fields == []
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/lattice && uv run pytest tests/test_persona_lens_extensions.py -v`
Expected: FAIL — `cannot import name 'FieldSpec'`.

**Step 3: Write minimal implementation**

Create `interverse/lattice/src/lattice/schemas.py`:
```python
"""Schema primitives shared across families and rules.

`FieldSpec` describes one typed field on either an entity-type's metadata
(e.g., `finding.strength_grade`) or a relationship-type's metadata (e.g.,
`bridges.activation_delay`). Frozen to enable use as dict keys / set members.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

FieldType = Literal["bool", "int", "float", "str", "enum"]


@dataclass(frozen=True)
class FieldSpec:
    """A typed field schema entry.

    Attributes:
        name: Field name (e.g., "strength_grade", "activation_delay").
        type_name: One of "bool", "int", "float", "str", "enum".
        enum_values: Allowed values when type_name == "enum"; empty otherwise.
        required: Whether the field must be set on the entity/relationship.
    """
    name: str
    type_name: FieldType
    enum_values: tuple[str, ...] = ()
    required: bool = True
```

In `interverse/lattice/src/lattice/families.py`, import `FieldSpec` from the new module and extend `EntityType`:
```python
from lattice.schemas import FieldSpec  # add this import

@dataclass
class EntityType:
    name: str
    families: list[TypeFamily]
    diagnostic_property: str
    lifecycle_transitions: dict[str, list[TypeFamily]] = field(default_factory=dict)
    metadata_fields: list[FieldSpec] = field(default_factory=list)
```

Update `_register_builtins` to copy `metadata_fields` via `list(et.metadata_fields)` (FieldSpec is frozen, so a shallow copy is safe).

**Step 4: Run test to verify it passes**
Run: `cd interverse/lattice && uv run pytest tests/ -v`
Expected: all existing tests still PASS + 4 new tests PASS.

**Step 5: Commit**
```bash
git add interverse/lattice/src/lattice/schemas.py interverse/lattice/src/lattice/families.py interverse/lattice/tests/test_persona_lens_extensions.py
git commit -m "feat(lattice): FieldSpec in schemas.py + EntityType.metadata_fields for typed schemas"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/ -v`
  expect: exit 0
</verify>

---

## Task 8: Add relationship-metadata registry in `rules.py`

**Files:**
- Modify: `interverse/lattice/src/lattice/rules.py`
- Modify: `interverse/lattice/tests/test_persona_lens_extensions.py`

**Step 1: Write the failing test**
```python
from lattice.rules import (
    register_relationship_metadata, get_relationship_metadata,
    list_relationship_metadata, reset_relationship_metadata,
)


class TestRelationshipMetadata:
    def test_register_and_get(self):
        reset_relationship_metadata()
        register_relationship_metadata("bridges", [
            FieldSpec("directed", "bool"),
            FieldSpec("activation_delay", "enum",
                      enum_values=("immediate", "short", "medium", "long")),
            FieldSpec("strength", "float"),
        ])
        spec = get_relationship_metadata("bridges")
        assert len(spec) == 3
        assert {f.name for f in spec} == {"directed", "activation_delay", "strength"}

    def test_unknown_relationship_returns_empty(self):
        reset_relationship_metadata()
        assert get_relationship_metadata("nonexistent") == []

    def test_list_relationship_metadata(self):
        reset_relationship_metadata()
        register_relationship_metadata("a", [FieldSpec("x", "bool")])
        register_relationship_metadata("b", [FieldSpec("y", "int")])
        names = {name for name, _ in list_relationship_metadata()}
        assert names == {"a", "b"}
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/lattice && uv run pytest tests/test_persona_lens_extensions.py -v`
Expected: 3 new tests FAIL with `ImportError`.

**Step 3: Write minimal implementation**

In `interverse/lattice/src/lattice/rules.py`:
```python
from lattice.schemas import FieldSpec
# (existing) from lattice.families import TypeFamily

# ─── Relationship Metadata Registry ──────────────────────────────

_relationship_metadata: dict[str, list[FieldSpec]] = {}


def register_relationship_metadata(
    relationship_type: str, fields: list[FieldSpec],
) -> None:
    """Register the metadata schema for a relationship type.

    Overwrites if the relationship_type already has metadata.
    """
    _relationship_metadata[relationship_type] = list(fields)


def get_relationship_metadata(relationship_type: str) -> list[FieldSpec]:
    """Return the FieldSpec list for a relationship type, or [] if unset."""
    return list(_relationship_metadata.get(relationship_type, []))


def list_relationship_metadata() -> list[tuple[str, list[FieldSpec]]]:
    """Return all registered (relationship_type, fields) pairs."""
    return [(k, list(v)) for k, v in _relationship_metadata.items()]


def reset_relationship_metadata() -> None:
    """Clear all relationship metadata. For testing."""
    _relationship_metadata.clear()
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/lattice && uv run pytest tests/ -v`
Expected: all PASS.

**Step 5: Commit**
```bash
git add interverse/lattice/src/lattice/rules.py interverse/lattice/tests/test_persona_lens_extensions.py
git commit -m "feat(lattice): relationship-metadata registry (G3/G4 schema host)"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/ -v`
  expect: exit 0
</verify>

---

## Task 9: Extend builtin rules with persona/lens relationship vocabulary

**Files:**
- Modify: `interverse/lattice/src/lattice/rules.py` (extend `_BUILTIN_RULES` valid_relationships)
- Modify: `interverse/lattice/tests/test_persona_lens_extensions.py`

**Step 1: Write the failing test**
```python
from lattice.rules import get_valid_relationship_types


class TestExtendedRelationshipVocabulary:
    def test_stewardship_includes_wields(self):
        rels = get_valid_relationship_types(TypeFamily.ACTOR, TypeFamily.ARTIFACT)
        assert "wields" in rels  # Persona wields Lens

    def test_structure_includes_in_domain_in_discipline(self):
        rels = get_valid_relationship_types(TypeFamily.ARTIFACT, TypeFamily.ARTIFACT)
        assert "in-domain" in rels
        assert "in-discipline" in rels
        assert "bridges" in rels      # Lens-Lens bridge edges (G4 metadata via registry)
        assert "same-as" in rels      # Lens dedup edges (G3 metadata via registry)

    def test_evidence_production_includes_cites_and_derives_from(self):
        rels = get_valid_relationship_types(TypeFamily.PROCESS, TypeFamily.EVIDENCE)
        assert "cites" in rels
        assert "derives-from" in rels

    def test_lifecycle_includes_supersedes(self):
        # `supersedes` belongs in the Lifecycle rule (temporal succession), not Structure.
        # Lifecycle is a wildcard rule (family_a=family_b=None), so it applies to any pair.
        rels = get_valid_relationship_types(TypeFamily.ARTIFACT, TypeFamily.ARTIFACT)
        assert "supersedes" in rels
        # Ensure supersedes did NOT leak into the Structure rule's vocabulary directly —
        # it should only appear via the Lifecycle wildcard.
        from lattice.rules import _BUILTIN_RULES
        structure_rule = next(r for r in _BUILTIN_RULES if r.name == "structure")
        assert "supersedes" not in structure_rule.valid_relationships

    def test_existing_relationships_preserved(self):
        # Sanity: don't regress existing vocabulary.
        rels_struct = get_valid_relationship_types(TypeFamily.ARTIFACT, TypeFamily.ARTIFACT)
        for r in ("imports", "depends-on", "references", "blocks", "parent-child"):
            assert r in rels_struct
        rels_steward = get_valid_relationship_types(TypeFamily.ACTOR, TypeFamily.ARTIFACT)
        for r in ("owns", "maintains", "created", "reviewed"):
            assert r in rels_steward
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/lattice && uv run pytest tests/test_persona_lens_extensions.py::TestExtendedRelationshipVocabulary -v`
Expected: 4 of 5 FAIL.

**Step 3: Write minimal implementation**

In `interverse/lattice/src/lattice/rules.py`, extend `_BUILTIN_RULES`:
- Stewardship (Actor × Artifact): append `"wields"`
- Structure (Artifact × Artifact): append `"in-domain"`, `"in-discipline"`, `"bridges"`, `"same-as"` *(NOT `supersedes`)*
- Evidence Production: append `"cites"`, `"derives-from"`
- Lifecycle (any × any): append `"supersedes"` alongside `"transitions-to"`

```python
# Update inline:

InteractionRule(
    name="stewardship",
    family_a=TypeFamily.ACTOR,
    family_b=TypeFamily.ARTIFACT,
    valid_relationships=["owns", "maintains", "created", "reviewed", "wields"],
),
InteractionRule(
    name="structure",
    family_a=TypeFamily.ARTIFACT,
    family_b=TypeFamily.ARTIFACT,
    valid_relationships=[
        "imports", "depends-on", "references", "blocks", "parent-child",
        "in-domain", "in-discipline", "bridges", "same-as",
    ],
    symmetric=False,
),
InteractionRule(
    name="evidence-production",
    family_a=None,
    family_b=TypeFamily.EVIDENCE,
    valid_relationships=[
        "produces", "evaluates", "asserts-about", "measures",
        "cites", "derives-from",
    ],
),
InteractionRule(
    name="lifecycle",
    family_a=None,
    family_b=None,
    valid_relationships=["transitions-to", "supersedes"],
),
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/lattice && uv run pytest tests/ -v`
Expected: all PASS, including the existing `test_seven_builtin_rules` which still asserts 7 rules.

**Step 5: Commit**
```bash
git add interverse/lattice/src/lattice/rules.py interverse/lattice/tests/test_persona_lens_extensions.py
git commit -m "feat(lattice): extend rules with persona/lens vocabulary (wields/bridges/same-as/cites/derives-from/in-domain/in-discipline/supersedes)"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/ -v`
  expect: exit 0
</verify>

---

## Task 10: Register G3/G4 relationship metadata + G7 entity metadata as builtins

**Files:**
- Modify: `interverse/lattice/src/lattice/rules.py` (add `_BUILTIN_RELATIONSHIP_METADATA`)
- Modify: `interverse/lattice/src/lattice/families.py` (extend the `finding` builtin with `strength_grade`)
- Modify: `interverse/lattice/tests/test_persona_lens_extensions.py`

**Step 1: Write the failing test**
```python
class TestBuiltinMetadata:
    def test_bridges_metadata_registered_by_default(self):
        # _register_builtin_rules should also register relationship metadata.
        spec = get_relationship_metadata("bridges")
        names = {f.name for f in spec}
        assert names == {"directed", "activation_delay", "strength"}
        delay = next(f for f in spec if f.name == "activation_delay")
        assert delay.type_name == "enum"
        assert set(delay.enum_values) == {"immediate", "short", "medium", "long"}

    def test_same_as_metadata_registered_by_default(self):
        spec = get_relationship_metadata("same-as")
        names = {f.name for f in spec}
        assert {"source_independence", "corroborator_count"} <= names

    def test_finding_has_strength_grade_metadata(self):
        et = get_entity_type("finding")
        names = {f.name for f in et.metadata_fields}
        assert "strength_grade" in names
        sg = next(f for f in et.metadata_fields if f.name == "strength_grade")
        assert sg.type_name == "enum"
        assert set(sg.enum_values) == {"sahih", "hasan", "da'if", "mawdu"}
```

**Step 2: Run test to verify it fails**
Expected: FAIL — metadata not registered yet.

**Step 3: Write minimal implementation**

In `rules.py`, add a builtin metadata table and call it from `_register_builtin_rules`:
```python
_BUILTIN_RELATIONSHIP_METADATA: dict[str, list[FieldSpec]] = {
    "bridges": [
        FieldSpec("directed", "bool"),
        FieldSpec(
            "activation_delay", "enum",
            enum_values=("immediate", "short", "medium", "long"),
        ),
        FieldSpec("strength", "float"),
    ],
    "same-as": [
        FieldSpec("source_independence", "bool"),
        FieldSpec("corroborator_count", "int"),
        FieldSpec("confidence", "float", required=False),
        FieldSpec("method", "str", required=False),
    ],
}


def _register_builtin_rules() -> None:
    for rule in _BUILTIN_RULES:
        register_rule(rule)
    for rel_type, fields in _BUILTIN_RELATIONSHIP_METADATA.items():
        register_relationship_metadata(rel_type, fields)
```

In `families.py`, update the `finding` builtin entry to include `metadata_fields=[FieldSpec("strength_grade", "enum", enum_values=("sahih", "hasan", "da'if", "mawdu"))]`. Also update `_register_builtins` so it copies `metadata_fields` (using `[FieldSpec(**asdict(f)) for f in et.metadata_fields]` is wrong since FieldSpec is frozen — just `list(et.metadata_fields)` is correct because frozen dataclasses are immutable).

**Step 4: Run test to verify it passes**
Run: `cd interverse/lattice && uv run pytest tests/ -v`
Expected: all PASS.

**Step 5: Commit**
```bash
git add interverse/lattice/src/lattice/rules.py interverse/lattice/src/lattice/families.py interverse/lattice/tests/test_persona_lens_extensions.py
git commit -m "feat(lattice): register G3/G4/G7 metadata as builtins (bridges, same-as, finding.strength_grade)"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/ -v`
  expect: exit 0
</verify>

---

## Task 11: Register persona/lens entity types (verdict baked in at code time)

**Files:**
- Modify: `interverse/lattice/src/lattice/families.py` (extend `_BUILTINS` + add `LATTICE_F2_VERDICT` constant)
- Modify: `interverse/lattice/tests/test_persona_lens_extensions.py`

**Mechanism (post-review):** The verdict is hard-coded as a module-level `Final[Literal[...]]` constant in `families.py`. No filesystem walk, no import-time JSON read. Reasons (per plan review consensus):
1. Eliminates silent-fallback risk on installed wheels and out-of-tree checkouts.
2. Verdict-change becomes a single-line code commit — auditable in git history.
3. Tests can override deterministically via env var (`LATTICE_F2_VERDICT`); the constant is the *default* the env var overrides.

**Step 0: Read the verdict from bead state and bake it in**
```bash
verdict=$(bd state sylveste-r3jf f2_audit_verdict)
# Sanity check
case "$verdict" in
  collapse|keep-separate) echo "Baking verdict: $verdict" ;;
  *) echo "ERROR: unexpected verdict '$verdict' — expected 'collapse' or 'keep-separate'" >&2; exit 1 ;;
esac
```

The Step-3 implementation below is written for `keep-separate`. **If verdict is `collapse`, change the constant value before running the tests.**

**Step 1: Write the failing test**
```python
from lattice.families import list_entity_types


class TestPersonaLensEntityTypes:
    def test_persona_registered_as_actor(self):
        et = get_entity_type("persona")
        assert et is not None
        assert TypeFamily.ACTOR in et.families
        assert et.diagnostic_property == "persona_identity_uuid"

    def test_persona_has_supersedes_lifecycle(self):
        et = get_entity_type("persona")
        # G8: editing creates a new node with supersedes edge → modeled as lifecycle event.
        assert "edit_creates_new" in et.lifecycle_transitions

    def test_lens_registered_as_artifact(self):
        et = get_entity_type("lens")
        assert et is not None
        assert TypeFamily.ARTIFACT in et.families
        assert et.diagnostic_property == "lens_identity_uuid"

    def test_lens_has_supersedes_lifecycle(self):
        et = get_entity_type("lens")
        assert "edit_creates_new" in et.lifecycle_transitions

    def test_source_registered_as_artifact(self):
        et = get_entity_type("source")
        assert et is not None
        assert TypeFamily.ARTIFACT in et.families

    def test_baked_verdict_matches_audit_artifact(self):
        """The hard-coded LATTICE_F2_VERDICT constant must agree with the
        committed audit JSON. If they disagree, someone updated one but not
        the other — that's a coherence bug.
        """
        import json
        from pathlib import Path
        from lattice.families import LATTICE_F2_VERDICT

        # parents: [0]=tests/, [1]=lattice/, [2]=interverse/, [3]=Sylveste/
        audit_path = Path(__file__).resolve().parents[3] / "docs" / "research" / "f2-domain-discipline-audit.json"
        if not audit_path.exists():
            pytest.skip("F2 audit artifact not committed yet — run Task 6 first")
        verdict_in_artifact = json.loads(audit_path.read_text())["recommendation"]["verdict"]
        assert LATTICE_F2_VERDICT == verdict_in_artifact, (
            f"Verdict drift: families.py says {LATTICE_F2_VERDICT!r} but "
            f"audit JSON says {verdict_in_artifact!r}. Re-bake the constant."
        )

    def test_collapse_registers_four_types(self, monkeypatch):
        """When verdict='collapse', expect 4 persona/lens types
        (persona, lens, source, domain_discipline) — no separate
        domain/discipline.
        """
        monkeypatch.setenv("LATTICE_F2_VERDICT", "collapse")
        # Force fixture re-registration with the env-overridden verdict.
        from lattice.families import _register_builtins
        reset_registry()
        _register_builtins()
        names = {et.name for et in list_entity_types()}
        assert "domain_discipline" in names
        assert "domain" not in names
        assert "discipline" not in names

    def test_keep_separate_registers_five_types(self, monkeypatch):
        monkeypatch.setenv("LATTICE_F2_VERDICT", "keep-separate")
        from lattice.families import _register_builtins
        reset_registry()
        _register_builtins()
        names = {et.name for et in list_entity_types()}
        assert "domain" in names
        assert "discipline" in names
        assert "domain_discipline" not in names
```

**Step 2: Run test to verify it fails**
Expected: 5 FAIL (last one skips if no audit yet, fails if audit verdict mismatches registration).

**Step 3: Write minimal implementation**

In `families.py`, add a module-level constant + an env-var override hook. The constant is the *default*; the env var overrides only for testing.

```python
import os
from typing import Final, Literal

# Baked at code time from the F2 audit JSON. To re-bake: read
# `bd state sylveste-r3jf f2_audit_verdict` and update this line.
# Last updated: 2026-04-28 (Task 11 of plan 2026-04-28-f2-domain-audit-and-lattice-extension).
LATTICE_F2_VERDICT: Final[Literal["collapse", "keep-separate"]] = "keep-separate"


def _effective_verdict() -> Literal["collapse", "keep-separate"]:
    """Return the verdict to use during registration.

    Default: the baked-in constant. Override via `LATTICE_F2_VERDICT` env var
    for tests that need to exercise the alternate shape.
    """
    override = os.environ.get("LATTICE_F2_VERDICT")
    if override in ("collapse", "keep-separate"):
        return override  # type: ignore[return-value]
    return LATTICE_F2_VERDICT


# Add to _BUILTINS list (after the existing entries):
_PERSONA_LENS_BUILTINS_COMMON = [
    EntityType(
        name="persona",
        families=[TypeFamily.ACTOR],
        diagnostic_property="persona_identity_uuid",
        lifecycle_transitions={
            "edit_creates_new": [TypeFamily.ACTOR],  # G8: immutable; new node supersedes
        },
    ),
    EntityType(
        name="lens",
        families=[TypeFamily.ARTIFACT],
        diagnostic_property="lens_identity_uuid",
        lifecycle_transitions={
            "edit_creates_new": [TypeFamily.ARTIFACT],  # G8
        },
    ),
    EntityType(
        name="source",
        families=[TypeFamily.ARTIFACT],
        diagnostic_property="source_id",
    ),
]

_PERSONA_LENS_BUILTINS_KEEP = [
    EntityType(name="domain", families=[TypeFamily.ARTIFACT], diagnostic_property="domain_name"),
    EntityType(name="discipline", families=[TypeFamily.ARTIFACT], diagnostic_property="discipline_name"),
]

_PERSONA_LENS_BUILTINS_COLLAPSE = [
    EntityType(
        name="domain_discipline",
        families=[TypeFamily.ARTIFACT],
        diagnostic_property="domain_discipline_name",
    ),
]


def _persona_lens_builtins() -> list[EntityType]:
    extras = (
        _PERSONA_LENS_BUILTINS_COLLAPSE
        if _effective_verdict() == "collapse"
        else _PERSONA_LENS_BUILTINS_KEEP
    )
    return _PERSONA_LENS_BUILTINS_COMMON + extras
```

In `_register_builtins`, after registering `_BUILTINS`, also iterate `_persona_lens_builtins()`. Because `_persona_lens_builtins()` is called *fresh* each time `_register_builtins()` runs, the env-var override takes effect cleanly when test fixtures call `reset_registry(); _register_builtins()` after `monkeypatch.setenv`.

**Step 4: Run test to verify it passes**
Run: `cd interverse/lattice && uv run pytest tests/ -v`
Expected: all PASS (including the audit-verdict-gated test once Task 6 has produced the audit JSON).

**Step 5: Commit**

Before committing, verify the constant matches the audit verdict. Use Python to parse the actual assignment (rather than a brittle sed regex that could be confused by quoted strings inside the type annotation):
```bash
audit_verdict=$(jq -r '.recommendation.verdict' docs/research/f2-domain-discipline-audit.json)
constant_value=$(cd interverse/lattice && uv run python -c "from lattice.families import LATTICE_F2_VERDICT; print(LATTICE_F2_VERDICT)")
[[ "$audit_verdict" == "$constant_value" ]] || { echo "MISMATCH: audit=$audit_verdict constant=$constant_value" >&2; exit 1; }
```

```bash
git add interverse/lattice/src/lattice/families.py interverse/lattice/tests/test_persona_lens_extensions.py
git commit -m "feat(lattice): register persona/lens/source + verdict-baked domain[/discipline] entity types"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/ -v`
  expect: exit 0
- run: `cd interverse/lattice && LATTICE_F2_VERDICT=collapse uv run python -c "from lattice.families import list_entity_types; names = {e.name for e in list_entity_types()}; print('domain_discipline' in names)"`
  expect: contains "True"
- run: `cd interverse/lattice && LATTICE_F2_VERDICT=keep-separate uv run python -c "from lattice.families import list_entity_types; names = {e.name for e in list_entity_types()}; print('domain' in names and 'discipline' in names)"`
  expect: contains "True"
- run: `grep -c "_read_audit_verdict\|filesystem walk" interverse/lattice/src/lattice/families.py`
  expect: contains "0"
</verify>

---

## Task 12: Document persona/lens type catalog in `AGENTS.md`

**Files:**
- Modify: `interverse/lattice/AGENTS.md`

**Step 1: Append a new section** (no test — pure docs)

After the existing "Interaction Matrix" section, append:

```markdown
## Persona/Lens Type Extensions (F2 — sylveste-r3jf)

Five additional entity types extend the core five families to cover the persona/lens ontology (per PRD `docs/prds/2026-04-21-persona-lens-ontology.md` and reconciliation `docs/research/2026-04-27-lattice-reconciliation.md`):

| Type | Family | Diagnostic | Notes |
|---|---|---|---|
| persona | Actor | `persona_identity_uuid` | G8: edits create new node via `edit_creates_new` lifecycle event |
| lens | Artifact | `lens_identity_uuid` | G8: same lifecycle pattern as persona |
| source | Artifact | `source_id` | Origin reference for lens provenance chains |
| domain *or* domain_discipline | Artifact | `domain_name` *or* `domain_discipline_name` | Audit-verdict-gated: collapsed (one type) or kept-separate (two types). See `docs/research/f2-domain-discipline-audit.json`. |
| discipline (only when keep-separate) | Artifact | `discipline_name` | |

### Relationship Vocabulary Additions

| Rule | Added relationships |
|---|---|
| Stewardship (Actor × Artifact) | `wields` (e.g., Persona wields Lens) |
| Structure (Artifact × Artifact) | `in-domain`, `in-discipline`, `bridges`, `same-as`, `supersedes` |
| Evidence Production (any × Evidence) | `cites`, `derives-from` |

### Relationship Metadata (G3/G4)

- `bridges` (G4): `directed: bool`, `activation_delay: enum[immediate, short, medium, long]`, `strength: float`. Maps Auraken's `bridge_score` → `strength`.
- `same-as` (G3): `source_independence: bool`, `corroborator_count: int`, `confidence: float?`, `method: str?`. Auto-detected dedup edges emit as `candidate-same-as` (a separate type — F5 territory); curator promotion is required for `same-as`.

### Entity Metadata (G7)

- `finding.strength_grade: enum[sahih, hasan, da'if, mawdu]` — jarh wa-ta'dil grading on Evidence findings (V1 covers Evidence only; Lens-level credibility is V2).

### What F2 does *not* do

Three importer connectors (fd-agents, Auraken, interlens) are F4 territory (`sylveste-t2cs`). DDL/storage migration is F3 (`sylveste-dsbl`). F2 only registers the type system surface those features will target.
```

**Step 2: Commit**
```bash
git add interverse/lattice/AGENTS.md
git commit -m "docs(lattice): persona/lens type catalog (F2 extensions)"
```

<verify>
- run: `grep -A 2 "Persona/Lens Type Extensions" interverse/lattice/AGENTS.md`
  expect: contains "F2"
</verify>

---

## Task 13: Final pass — pytest, ruff, record vetting signals

**Files:** none (validation only)

**Step 1: Run the full test suite**
```bash
cd interverse/lattice
uv run pytest tests/ -v
```
Expected: all PASS, ≥ 12 new tests in `test_persona_lens_extensions.py` plus all `test_audit_domains.py` tests.

**Step 2: Run lint**
```bash
cd interverse/lattice
uv run ruff check src/ scripts/ tests/
```
Expected: zero issues.

**Step 3: Record sprint vetting signals**
```bash
bd set-state sylveste-r3jf vetted_at="$(date +%s)" --reason "F2 plan executed; tests + lint clean"
bd set-state sylveste-r3jf vetted_sha="$(git rev-parse HEAD)" --reason "F2 plan executed; tests + lint clean"
bd set-state sylveste-r3jf tests_passed="true" --reason "F2 plan executed; tests + lint clean"
bd set-state sylveste-r3jf sprint_or_work_flow="true" --reason "F2 plan executed; tests + lint clean"
```

<verify>
- run: `cd interverse/lattice && uv run pytest tests/ -v 2>&1 | tail -5`
  expect: contains "passed"
- run: `cd interverse/lattice && uv run ruff check src/ scripts/ tests/`
  expect: exit 0
- run: `bd state sylveste-r3jf tests_passed`
  expect: contains "true"
</verify>

---

## Lessons Learned

_(filled in by `/clavain:resolve` or post-execution if quality-gates surfaces a plan-level miss)_
