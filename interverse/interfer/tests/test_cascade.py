"""Tests for the confidence cascade."""

from __future__ import annotations

from server.cascade import (
    CascadeConfig,
    CascadeDecision,
    CascadeResult,
    CascadeStats,
    ConfidenceCascade,
)
from server.main import _cascade_decide


def test_cascade_decision_accept() -> None:
    """High confidence maps to ACCEPT."""
    cascade = ConfidenceCascade.__new__(ConfidenceCascade)
    cascade._config = CascadeConfig()
    assert cascade._decide(0.9) == CascadeDecision.ACCEPT
    assert cascade._decide(0.8) == CascadeDecision.ACCEPT


def test_cascade_decision_escalate() -> None:
    """Mid confidence (cloud_threshold <= c < accept_threshold) maps to ESCALATE."""
    cascade = ConfidenceCascade.__new__(ConfidenceCascade)
    cascade._config = CascadeConfig()  # cloud=0.4, accept=0.8
    assert cascade._decide(0.7) == CascadeDecision.ESCALATE
    assert cascade._decide(0.5) == CascadeDecision.ESCALATE
    assert cascade._decide(0.4) == CascadeDecision.ESCALATE


def test_cascade_decision_cloud() -> None:
    """Low confidence (< cloud_threshold=0.4) maps to CLOUD."""
    cascade = ConfidenceCascade.__new__(ConfidenceCascade)
    cascade._config = CascadeConfig()
    assert cascade._decide(0.39) == CascadeDecision.CLOUD
    assert cascade._decide(0.1) == CascadeDecision.CLOUD


def test_cascade_stats_rates() -> None:
    """Stats compute rates correctly."""
    stats = CascadeStats(
        total_requests=10,
        accepts=6,
        escalations=3,
        cloud_fallbacks=1,
        total_probe_time_s=2.0,
    )
    assert stats.accept_rate == 0.6
    assert stats.escalation_rate == 0.3
    assert stats.cloud_rate == 0.1
    d = stats.to_dict()
    assert d["accept_rate"] == 0.6


def test_cascade_stats_empty() -> None:
    """Empty stats return zero rates."""
    stats = CascadeStats()
    assert stats.accept_rate == 0.0
    assert stats.cloud_rate == 0.0


def test_cascade_config_defaults() -> None:
    """Default config has expected thresholds."""
    cfg = CascadeConfig()
    assert cfg.accept_threshold == 0.8
    assert cfg.escalate_threshold == 0.6
    assert cfg.cloud_threshold == 0.4
    assert cfg.probe_tokens == 3
    assert cfg.enabled is True


def test_cascade_result_fields() -> None:
    """CascadeResult holds all expected fields."""
    r = CascadeResult(
        decision=CascadeDecision.ACCEPT,
        model_used="local:test",
        probe_confidence=0.85,
        probe_tokens=["Hello", " world"],
        probe_time_s=0.05,
        models_tried=["local:test"],
        escalation_count=0,
    )
    assert r.decision == CascadeDecision.ACCEPT
    assert r.model_used == "local:test"
    assert len(r.probe_tokens) == 2


# ---------------------------------------------------------------------------
# HTTP-layer cascade decision function
# ---------------------------------------------------------------------------


def test_cascade_decide_mirrors_class_method() -> None:
    """The standalone _cascade_decide matches ConfidenceCascade._decide."""
    cfg = CascadeConfig()
    assert _cascade_decide(cfg, 0.9) == CascadeDecision.ACCEPT
    assert _cascade_decide(cfg, 0.8) == CascadeDecision.ACCEPT
    assert _cascade_decide(cfg, 0.5) == CascadeDecision.ESCALATE
    assert _cascade_decide(cfg, 0.4) == CascadeDecision.ESCALATE
    assert _cascade_decide(cfg, 0.39) == CascadeDecision.CLOUD
    assert _cascade_decide(cfg, 0.0) == CascadeDecision.CLOUD


def test_cascade_decide_custom_thresholds() -> None:
    """Custom thresholds shift decision boundaries."""
    cfg = CascadeConfig(accept_threshold=0.9, cloud_threshold=0.3)
    assert _cascade_decide(cfg, 0.95) == CascadeDecision.ACCEPT
    assert _cascade_decide(cfg, 0.85) == CascadeDecision.ESCALATE
    assert _cascade_decide(cfg, 0.3) == CascadeDecision.ESCALATE
    assert _cascade_decide(cfg, 0.29) == CascadeDecision.CLOUD


# ---------------------------------------------------------------------------
# Cascade stats in /metrics
# ---------------------------------------------------------------------------


def test_cascade_stats_to_dict_with_requests() -> None:
    """Stats.to_dict includes avg_probe_time_s when there are requests."""
    stats = CascadeStats(
        total_requests=4,
        accepts=2,
        escalations=1,
        cloud_fallbacks=1,
        total_probe_time_s=0.4,
    )
    d = stats.to_dict()
    assert d["avg_probe_time_s"] == 0.1
    assert d["total_requests"] == 4
