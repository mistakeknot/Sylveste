from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts import learned_orchestration_shadow as los

SEED_PATH = ROOT / "docs" / "research" / "learned-orchestration" / "seed-examples-v0.jsonl"


def test_load_seed_examples_validates_required_schema() -> None:
    examples = los.load_examples(SEED_PATH)

    assert len(examples) == 14
    assert {example["example_id"] for example in examples} == {f"lo-seed-{i:03d}" for i in range(1, 15)}
    for example in examples:
        assert los.REQUIRED_EXAMPLE_FIELDS <= set(example)
        assert isinstance(example["negative_classes"], list)


def test_shadow_evaluator_emits_contract_records_for_every_seed() -> None:
    examples = los.load_examples(SEED_PATH)
    records = los.evaluate_examples(examples)

    assert len(records) == 14
    for record in records:
        assert record["comparison_id"].startswith("shadow-v0-")
        assert record["example_id"].startswith("lo-seed-")
        assert record["static_baseline"]["available"] is True
        assert "historical_route" in record
        assert record["b2_baseline"]["available"] in {True, False}
        assert record["b3_baseline"]["available"] in {True, False}
        assert record["learned_proposal"]["evaluator_mode"] == "replay_only"
        assert record["learned_proposal"]["proposal_executed"] is False
        assert record["governor_decision"]["proposal_executed"] is False
        assert record["governor_decision"]["governor_decision"] in {
            "authorize_shadow",
            "block",
            "needs_human",
            "baseline_only",
        }
        assert record["score"]["risk_class_hit"] in {True, False}
        assert record["score"]["would_have_regressed_positive_control"] in {True, False}


def test_phase0_scoring_preserves_positive_controls_and_reports_seed_risks() -> None:
    records = los.evaluate_examples(los.load_examples(SEED_PATH))
    report = los.summarize(records)

    assert report["total_examples"] == 14
    assert report["positive_controls"] == 3
    assert report["positive_control_regressions"] == 0
    assert report["negative_examples"] == 11
    assert report["negative_recall"] >= 0.70
    assert report["policy_block_correctness"] == 1.0
    assert report["fallback_availability"] == 1.0
    assert report["phase0_recommendation"] == "NO_GO_ENFORCE__KEEP_SHADOW"


def test_cli_writes_jsonl_comparisons_and_markdown_report(tmp_path: Path) -> None:
    output_path = tmp_path / "shadow-comparisons-v0.jsonl"
    report_path = tmp_path / "shadow-report-v0.md"

    exit_code = los.main([
        "--input",
        str(SEED_PATH),
        "--output",
        str(output_path),
        "--report",
        str(report_path),
    ])

    assert exit_code == 0
    rows = [json.loads(line) for line in output_path.read_text().splitlines() if line.strip()]
    assert len(rows) == 14
    assert rows[0]["comparison_id"] == "shadow-v0-lo-seed-001"
    report = report_path.read_text()
    assert "# sylveste-9lp.25.3 — learned orchestration shadow evaluator report" in report
    assert "NO_GO_ENFORCE__KEEP_SHADOW" in report
    assert "No production routing changes; replay-only receipts." in report
