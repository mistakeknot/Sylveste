#!/usr/bin/env python3
"""Shadow/replay evaluator for learned orchestration proposal receipts.

This is the phase-0 implementation for sylveste-9lp.25.3. It consumes the
labeled seed examples produced by sylveste-9lp.25.1 and emits non-executing
comparison records specified by the sylveste-9lp.25.2 experiment design.

Important boundary: this script never dispatches models, mutates Beads, changes
routing config, or executes a proposal. It only writes local JSONL/Markdown
research artifacts requested by the caller.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "docs" / "research" / "learned-orchestration" / "seed-examples-v0.jsonl"
DEFAULT_OUTPUT = ROOT / "docs" / "research" / "learned-orchestration" / "shadow-comparisons-v0.jsonl"
DEFAULT_REPORT = ROOT / "docs" / "research" / "learned-orchestration" / "shadow-report-v0.md"

REQUIRED_EXAMPLE_FIELDS = {
    "example_id",
    "source",
    "label",
    "negative_classes",
    "task_features",
    "chosen_route",
    "alternative_route",
    "outcome",
    "cost_observed",
    "quality_signal",
    "available_fields",
    "missing_fields",
    "usable_for",
}

NEGATIVE_LABELS = {
    "negative",
    "negative_fixed",
    "negative_open",
    "negative_shadow_projection",
    "instrumentation_gap",
}
POSITIVE_LABEL = "positive_control"

MODEL_RISK_CLASSES = {
    "bad_model_route",
    "provider_error_hidden",
    "stale_model_pin",
    "policy_refusal",
    "fallback_required",
    "prompt_topology_invalid",
    "under_escalation",
}
COST_RISK_CLASSES = {
    "cost_blowup",
    "cost_blowout_if_enforced",
    "context_overflow",
    "over_escalation",
    "fanout_blowup",
    "recursive_overrun",
}
CONTEXT_RISK_CLASSES = {
    "bad_context_route",
    "context_rot",
    "stale_compact_context",
    "missed_orchestration_phase",
}
TOPOLOGY_RISK_CLASSES = {
    "invalid_topology",
    "duplicate_system",
    "missed_prior_implementation",
    "recursive_overrun",
    "fanout_blowup",
    "prompt_topology_invalid",
}
GATE_RISK_CLASSES = {
    "false_pass",
    "missed_P0_P1",
    "premature_phase_advance",
    "outcome_misclassification",
    "under_activation",
    "routing_signal_unavailable",
    "no_production_callers",
}
INSTRUMENTATION_RISK_CLASSES = {
    "missing_quality_label",
    "unknown_model",
    "outcome_attribution_gap",
    "insufficient_quality_signal",
    "routing_signal_unavailable",
}

BUDGET_RISK_CLASSES = COST_RISK_CLASSES | {"recursive_overrun", "fanout_blowup"}
UNSAFE_NEEDS_BLOCK_CLASSES = (
    MODEL_RISK_CLASSES
    | COST_RISK_CLASSES
    | CONTEXT_RISK_CLASSES
    | TOPOLOGY_RISK_CLASSES
    | GATE_RISK_CLASSES
    | {"policy_refusal", "unsafe_authority_escalation"}
)


def load_examples(path: Path) -> list[dict[str, Any]]:
    """Load and validate normalized learned-orchestration seed examples."""
    examples: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    if not path.exists():
        raise FileNotFoundError(f"seed examples not found: {path}")

    for line_number, raw_line in enumerate(path.read_text().splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue
        try:
            example = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid JSON at {path}:{line_number}: {exc}") from exc

        missing = REQUIRED_EXAMPLE_FIELDS - set(example)
        if missing:
            eid = example.get("example_id", f"line-{line_number}")
            raise ValueError(f"{eid} missing required fields: {sorted(missing)}")

        if not isinstance(example["negative_classes"], list):
            raise ValueError(f"{example['example_id']} negative_classes must be a list")
        for object_field in ("source", "task_features", "chosen_route", "alternative_route", "outcome", "cost_observed", "quality_signal"):
            if not isinstance(example[object_field], dict):
                raise ValueError(f"{example['example_id']} {object_field} must be an object")
        for list_field in ("available_fields", "missing_fields", "usable_for"):
            if not isinstance(example[list_field], list):
                raise ValueError(f"{example['example_id']} {list_field} must be a list")

        eid = str(example["example_id"])
        if eid in seen_ids:
            raise ValueError(f"duplicate example_id: {eid}")
        seen_ids.add(eid)
        examples.append(example)

    return examples


def evaluate_examples(examples: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Replay examples and emit shadow comparison records."""
    return [evaluate_example(example) for example in examples]


def evaluate_example(example: dict[str, Any]) -> dict[str, Any]:
    proposal = propose_shadow_route(example)
    governor = decide_governor(example, proposal)
    record = {
        "comparison_id": f"shadow-v0-{example['example_id']}",
        "example_id": example["example_id"],
        "evaluator_version": "learned-orchestration-shadow-v0",
        "evaluator_mode": "replay_only",
        "production_side_effects": False,
        "model_dispatch_calls": 0,
        "beads_mutations": 0,
        "historical_route": historical_route(example),
        "static_baseline": static_baseline(example),
        "b2_baseline": b2_baseline(example),
        "b3_baseline": b3_baseline(example),
        "learned_proposal": proposal,
        "governor_decision": governor,
    }
    record["score"] = score_record(example, record)
    return record


def historical_route(example: dict[str, Any]) -> dict[str, Any]:
    return {
        "available": True,
        "source": example["source"],
        "route": example["chosen_route"],
        "outcome": example["outcome"],
        "quality_signal": example["quality_signal"],
    }


def static_baseline(example: dict[str, Any]) -> dict[str, Any]:
    return {
        "available": True,
        "baseline": "historical_static_fallback",
        "route": example["chosen_route"],
        "fallback_reason": "static v0 uses the recorded historical choice as the always-available fallback",
    }


def b2_baseline(example: dict[str, Any]) -> dict[str, Any]:
    features = example.get("task_features", {})
    complexity = str(features.get("complexity", "")).strip()
    normalized = _normalize_complexity(complexity)
    if normalized is None:
        return {
            "available": False,
            "requires": "raw complexity signals or derivable task_features.complexity",
            "reason": f"complexity signal is missing or ambiguous: {complexity or 'unknown'}",
        }

    tier = _tier_for_complexity(normalized, str(features.get("risk", "")))
    return {
        "available": True,
        "baseline": "B2_complexity_aware_shadow",
        "complexity": normalized,
        "proposed_model_tier": tier,
        "reason": "derived from task_features.complexity/risk only; no dispatch performed",
    }


def b3_baseline(example: dict[str, Any]) -> dict[str, Any]:
    # Phase 0 does not join real Interspect routing-calibration receipts. Keep this
    # explicit so missing B3 signal cannot be laundered into success.
    source = example.get("source", {})
    quality_source = str(example.get("quality_signal", {}).get("source", ""))
    joined_hint = "interspect" in json.dumps(source).lower() or "verdict" in quality_source.lower()
    reason = "no joined interspect verdict/routing-calibration outcome in seed record"
    if joined_hint:
        reason = "interspect/verdict evidence is present, but no route_id + model + acted_on/dismissed join is available"
    return {
        "available": False,
        "requires": "joined interspect verdict/routing-calibration outcome with model, route_id, and quality label",
        "reason": reason,
    }


def propose_shadow_route(example: dict[str, Any]) -> dict[str, Any]:
    label = str(example["label"])
    classes = set(map(str, example.get("negative_classes", [])))
    route = example.get("chosen_route", {})
    alternative = example.get("alternative_route", {})
    features = example.get("task_features", {})

    if label == POSITIVE_LABEL:
        proposed_model = route.get("model") or route.get("model_map") or "no-change"
        topology = route.get("topology") or route.get("policy") or "static"
        roles: list[str] = []
        failure_risks: list[str] = []
        confidence = 0.88
        rationale = "positive control: preserve historical/governed baseline; do not invent escalation"
        cost = {"tokens": "no-change", "usd": 0.0, "latency_class": "no-change"}
        context_plan = _context_plan(classes, alternative, positive_control=True)
    else:
        proposed_model = _proposed_model(example, classes)
        topology = _proposed_topology(example, classes)
        roles = _proposed_roles(classes)
        failure_risks = sorted(classes)
        confidence = _proposal_confidence(classes)
        rationale = _proposal_rationale(example, classes)
        cost = _expected_cost(example, classes)
        context_plan = _context_plan(classes, alternative, positive_control=False)

    recursion_request = {
        "enabled": False,
        "max_depth": 0,
        "stop_rule": "recursion disabled in phase-0 replay evaluator",
        "budget_usd": 0.0,
    }
    if classes & {"recursive_overrun", "fanout_blowup"}:
        recursion_request["stop_rule"] = "block unbounded fanout/recursion; require explicit depth, budget, and cache/daemon plan"

    return {
        "proposal_id": f"learned-proposal-v0-{example['example_id']}",
        "input_example_id": example["example_id"],
        "proposed_model": proposed_model,
        "proposed_roles": roles,
        "proposed_topology": topology,
        "evaluator_mode": "replay_only",
        "proposal_executed": False,
        "context_plan": context_plan,
        "recursion_request": recursion_request,
        "expected_cost": cost,
        "expected_quality": {"confidence": confidence, "rationale": rationale},
        "failure_risks": failure_risks,
        "evidence_refs": _evidence_refs(example),
        "proposer_version": "deterministic-proxy-v0",
    }


def decide_governor(example: dict[str, Any], proposal: dict[str, Any]) -> dict[str, Any]:
    label = str(example["label"])
    classes = set(map(str, example.get("negative_classes", [])))
    has_fallback = True
    budget_ok = not bool(classes & BUDGET_RISK_CLASSES)
    recursion = proposal.get("recursion_request", {})
    recursion_bound_ok = (
        recursion.get("enabled") is False
        and recursion.get("max_depth") == 0
        and float(recursion.get("budget_usd") or 0.0) == 0.0
    )
    evidence_minimum_ok = _evidence_minimum_ok(example)
    access_list_ok = True
    safety_floor_ok = label == POSITIVE_LABEL or not (classes & {"unsafe_authority_escalation"})

    if label == POSITIVE_LABEL:
        decision = "baseline_only"
        reason = "positive control: preserve governed baseline; record no-change comparison only"
    elif classes & INSTRUMENTATION_RISK_CLASSES or not evidence_minimum_ok:
        decision = "needs_human"
        reason = "labels or route/outcome joins are insufficient for enforcement; human/instrumentation cleanup required"
    elif classes & UNSAFE_NEEDS_BLOCK_CLASSES:
        decision = "block"
        reason = "known seed risk intersects safety/budget/topology/model gate; block enforcement and keep shadow receipt"
    else:
        decision = "authorize_shadow"
        reason = "bounded non-executing counterfactual may be recorded for review only"

    return {
        "governor_decision": decision,
        "decision_reason": reason,
        "policy_checks": {
            "safety_floor_ok": safety_floor_ok,
            "budget_ok": budget_ok,
            "recursion_bound_ok": recursion_bound_ok,
            "access_list_ok": access_list_ok,
            "evidence_minimum_ok": evidence_minimum_ok,
            "fallback_available": has_fallback,
        },
        "baseline_executed": "historical_static_fallback",
        "proposal_executed": False,
    }


def score_record(example: dict[str, Any], record: dict[str, Any]) -> dict[str, Any]:
    label = str(example["label"])
    classes = set(map(str, example.get("negative_classes", [])))
    risks = set(map(str, record["learned_proposal"].get("failure_risks", [])))
    decision = record["governor_decision"]["governor_decision"]
    positive = label == POSITIVE_LABEL
    negative = label in NEGATIVE_LABELS

    risk_class_hit = True if positive else bool(classes & risks)
    budget_risk = bool(classes & BUDGET_RISK_CLASSES)
    would_have_blocked_failure = bool(negative and decision in {"block", "needs_human", "baseline_only"})
    would_have_regressed_positive = bool(positive and decision not in {"baseline_only", "authorize_shadow"})
    false_negative = bool(negative and (not risk_class_hit or decision == "authorize_shadow"))
    false_positive = bool(positive and decision in {"block", "needs_human"})

    return {
        "risk_class_hit": risk_class_hit,
        "cost_delta_usd": _cost_delta_usd(example),
        "would_have_blocked_failure": would_have_blocked_failure,
        "would_have_regressed_positive_control": would_have_regressed_positive,
        "false_negative": false_negative,
        "false_positive": false_positive,
        "over_escalation": "over_escalation" in classes,
        "under_escalation": "under_escalation" in classes,
        "budget_risk": budget_risk,
        "notes": _score_notes(example, record),
    }


def summarize(records: list[dict[str, Any]]) -> dict[str, Any]:
    total = len(records)
    positives = [r for r in records if not r["learned_proposal"].get("failure_risks")]
    negatives = [r for r in records if r["learned_proposal"].get("failure_risks")]
    positive_regressions = sum(1 for r in positives if r["score"]["would_have_regressed_positive_control"])
    false_positives = sum(1 for r in positives if r["score"]["false_positive"])
    false_negatives = sum(1 for r in negatives if r["score"]["false_negative"])
    risk_hits = sum(1 for r in negatives if r["score"]["risk_class_hit"])
    policy_blocks = sum(1 for r in negatives if r["score"]["would_have_blocked_failure"])
    fallback_available = sum(1 for r in records if r["governor_decision"]["policy_checks"].get("fallback_available"))
    safety_ok = sum(1 for r in records if r["governor_decision"]["policy_checks"].get("safety_floor_ok"))
    evidence_traceable = sum(1 for r in records if r["learned_proposal"].get("evidence_refs"))

    negative_count = len(negatives)
    positive_count = len(positives)
    negative_recall = risk_hits / negative_count if negative_count else 1.0
    policy_block_correctness = policy_blocks / negative_count if negative_count else 1.0
    fallback_rate = fallback_available / total if total else 1.0
    safety_floor_rate = safety_ok / total if total else 1.0
    false_unsafe_rate = false_positives / positive_count if positive_count else 0.0

    # Phase 0 can only justify more shadow collection. Enforce mode stays blocked
    # until .25.2 Phase 1 gates have at least 30 joined examples and human sign-off.
    phase0_recommendation = "NO_GO_ENFORCE__KEEP_SHADOW"
    prospective_shadow_gate = (
        total >= 30
        and negative_count >= 10
        and positive_count >= 5
        and positive_regressions == 0
        and negative_recall >= 0.70
        and policy_block_correctness == 1.0
        and fallback_rate == 1.0
        and safety_floor_rate == 1.0
    )

    return {
        "total_examples": total,
        "negative_examples": negative_count,
        "positive_controls": positive_count,
        "risk_class_hits": risk_hits,
        "negative_recall": round(negative_recall, 4),
        "positive_control_regressions": positive_regressions,
        "false_positives": false_positives,
        "false_negatives": false_negatives,
        "false_unsafe_proposal_rate": round(false_unsafe_rate, 4),
        "over_escalations": sum(1 for r in records if r["score"]["over_escalation"]),
        "under_escalations": sum(1 for r in records if r["score"]["under_escalation"]),
        "budget_risk_cases": sum(1 for r in records if r["score"]["budget_risk"]),
        "policy_block_correctness": round(policy_block_correctness, 4),
        "fallback_availability": round(fallback_rate, 4),
        "safety_floor_preservation": round(safety_floor_rate, 4),
        "evidence_traceability": round((evidence_traceable / total) if total else 1.0, 4),
        "phase0_recommendation": phase0_recommendation,
        "prospective_shadow_gate_met": prospective_shadow_gate,
        "enforce_threshold": "blocked until >=30 joined examples, >=10 negatives, >=5 positives, 100% positive preservation, 100% safety/fallback, and human sign-off",
    }


def write_jsonl(records: list[dict[str, Any]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "\n".join(json.dumps(record, sort_keys=True) for record in records) + "\n"
    path.write_text(text)


def render_report(records: list[dict[str, Any]], summary: dict[str, Any]) -> str:
    decisions = Counter(r["governor_decision"]["governor_decision"] for r in records)
    lines = [
        "# sylveste-9lp.25.3 — learned orchestration shadow evaluator report",
        "",
        "No production routing changes; replay-only receipts.",
        "",
        "## Verdict",
        "",
        f"- Phase-0 recommendation: `{summary['phase0_recommendation']}`.",
        f"- Enforce threshold: {summary['enforce_threshold']}.",
        f"- Prospective shadow gate met: `{str(summary['prospective_shadow_gate_met']).lower()}`.",
        "",
        "## Corpus",
        "",
        f"- Total examples: {summary['total_examples']}",
        f"- Negative / instrumentation examples: {summary['negative_examples']}",
        f"- Positive controls: {summary['positive_controls']}",
        "",
        "## Metrics",
        "",
        f"- Negative recall: {summary['negative_recall']:.2%}",
        f"- Positive-control regressions: {summary['positive_control_regressions']}",
        f"- False positives: {summary['false_positives']}",
        f"- False negatives: {summary['false_negatives']}",
        f"- False-unsafe proposal rate: {summary['false_unsafe_proposal_rate']:.2%}",
        f"- Policy block correctness: {summary['policy_block_correctness']:.2%}",
        f"- Fallback availability: {summary['fallback_availability']:.2%}",
        f"- Safety-floor preservation: {summary['safety_floor_preservation']:.2%}",
        f"- Evidence traceability: {summary['evidence_traceability']:.2%}",
        f"- Over-escalation cases: {summary['over_escalations']}",
        f"- Under-escalation cases: {summary['under_escalations']}",
        f"- Budget-risk cases: {summary['budget_risk_cases']}",
        "",
        "## Governor decisions",
        "",
    ]
    for decision in sorted(decisions):
        lines.append(f"- `{decision}`: {decisions[decision]}")

    lines.extend([
        "",
        "## Baseline caveats",
        "",
        "- Static fallback is always available and equals the recorded historical route.",
        "- B2 is derived only where a task complexity signal is present; ambiguous `mixed` examples are marked unavailable.",
        "- B3 is marked unavailable in phase 0 unless a route_id/model/outcome join exists; seed prose is not laundered into a calibration label.",
        "",
        "## Next gate",
        "",
        "Keep this evaluator in shadow/replay mode. The next useful move is collecting joined route/outcome receipts until the Phase-1 gate from `sylveste-9lp.25.2` is satisfiable.",
        "",
        "## Per-example receipts",
        "",
        "| Example | Decision | Risk hit | FP | FN | Budget risk | Notes |",
        "|---|---|---:|---:|---:|---:|---|",
    ])
    for record in records:
        score = record["score"]
        notes = str(score["notes"]).replace("|", "\\|")
        lines.append(
            f"| {record['example_id']} | {record['governor_decision']['governor_decision']} | "
            f"{_yn(score['risk_class_hit'])} | {_yn(score['false_positive'])} | {_yn(score['false_negative'])} | "
            f"{_yn(score['budget_risk'])} | {notes} |"
        )
    lines.append("")
    return "\n".join(lines)


def write_report(records: list[dict[str, Any]], summary: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_report(records, summary))


def _normalize_complexity(raw: str) -> str | None:
    if not raw or raw.lower() == "mixed":
        return None
    matches = re.findall(r"C(\d)", raw.upper())
    if not matches:
        return None
    # Use the highest mentioned complexity as the conservative B2 signal.
    return f"C{max(int(m) for m in matches)}"


def _tier_for_complexity(complexity: str, risk: str) -> str:
    rank = int(complexity[1:])
    risk_l = risk.lower()
    if rank >= 4 or any(term in risk_l for term in ("safety", "policy", "architecture", "phase")):
        return "opus_or_sonnet_plus_verifier"
    if rank == 3:
        return "sonnet"
    return "haiku_or_sonnet_low"


def _proposed_model(example: dict[str, Any], classes: set[str]) -> str:
    alternative = example.get("alternative_route", {})
    if "model" in alternative:
        return str(alternative["model"])
    if "model_map" in alternative:
        return str(alternative["model_map"])
    if classes & {"policy_refusal", "fallback_required", "prompt_topology_invalid"}:
        return "sonnet-with-haiku-fallback"
    if classes & {"bad_model_route", "stale_model_pin", "under_escalation"}:
        return "supported-current-model-or-preflight-reject"
    if classes & GATE_RISK_CLASSES:
        return "no-change-with-governor-gate"
    return "no-change"


def _proposed_topology(example: dict[str, Any], classes: set[str]) -> str:
    alternative = example.get("alternative_route", {})
    if "topology" in alternative:
        return str(alternative["topology"])
    if classes & {"recursive_overrun", "fanout_blowup"}:
        return "bounded-cache-daemon-or-single-flight"
    if classes & {"invalid_topology", "duplicate_system", "missed_prior_implementation"}:
        return "reconcile-existing-system-before-new-topology"
    if classes & GATE_RISK_CLASSES:
        return "verifier_gated"
    if classes & CONTEXT_RISK_CLASSES:
        return "context-gated-sequential"
    return "static"


def _proposed_roles(classes: set[str]) -> list[str]:
    roles: list[str] = []
    if classes & (MODEL_RISK_CLASSES | GATE_RISK_CLASSES):
        roles.extend(["planner", "verifier"])
    if classes & (CONTEXT_RISK_CLASSES | TOPOLOGY_RISK_CLASSES):
        roles.extend(["retriever", "architect", "verifier"])
    if classes & INSTRUMENTATION_RISK_CLASSES:
        roles.extend(["instrumentation-checker", "human-reviewer"])
    if not roles:
        roles.append("shadow-reviewer")
    # Stable de-duplication.
    return list(dict.fromkeys(roles))


def _context_plan(classes: set[str], alternative: dict[str, Any], *, positive_control: bool) -> dict[str, Any]:
    if positive_control:
        return {"artifacts": [], "summary_strategy": "none", "max_context_tokens": 0}
    artifacts = []
    if classes & (CONTEXT_RISK_CLASSES | TOPOLOGY_RISK_CLASSES):
        artifacts.append("prior implementation / shipped-state evidence")
    if classes & INSTRUMENTATION_RISK_CLASSES:
        artifacts.append("route_id + dispatch_id + verdict outcome join")
    if not artifacts:
        artifacts.append("seed example evidence refs")
    if "context" in alternative:
        artifacts.append(str(alternative["context"]))
    strategy = "beads_only"
    if classes & CONTEXT_RISK_CLASSES:
        strategy = "fresh_single_source_summary"
    if classes & TOPOLOGY_RISK_CLASSES:
        strategy = "stateful_repl_summary"
    return {"artifacts": artifacts, "summary_strategy": strategy, "max_context_tokens": 12000}


def _proposal_confidence(classes: set[str]) -> float:
    if classes & INSTRUMENTATION_RISK_CLASSES:
        return 0.52
    if classes & (MODEL_RISK_CLASSES | COST_RISK_CLASSES | GATE_RISK_CLASSES | TOPOLOGY_RISK_CLASSES):
        return 0.74
    return 0.60


def _proposal_rationale(example: dict[str, Any], classes: set[str]) -> str:
    if classes & INSTRUMENTATION_RISK_CLASSES:
        return "seed identifies missing joined labels; proposal can only request instrumentation/human review"
    if classes & COST_RISK_CLASSES:
        return "seed risk indicates cost, context, fanout, or recursion budget pressure; keep bounded and shadow-only"
    if classes & MODEL_RISK_CLASSES:
        return "seed risk indicates unsupported/stale/refusing model route; require preflight or fallback"
    if classes & TOPOLOGY_RISK_CLASSES:
        return "seed risk indicates topology/prior-implementation hazard; require reconciliation/verifier gate"
    if classes & GATE_RISK_CLASSES:
        return "seed risk indicates gate/outcome misclassification; require PASS/WARN/FAIL separation before advance"
    source = example.get("source", {}).get("id", example.get("example_id"))
    return f"deterministic v0 proposal from seed evidence {source}"


def _expected_cost(example: dict[str, Any], classes: set[str]) -> dict[str, Any]:
    if classes & {"cost_blowup", "context_overflow", "fanout_blowup", "recursive_overrun", "cost_blowout_if_enforced"}:
        return {"tokens": "bounded_or_reduced", "usd": 0.0, "latency_class": "lower_than_failed_route_or_blocked"}
    if classes & {"over_escalation"}:
        return {"tokens": "no-increase", "usd": 0.0, "latency_class": "unknown_until_quality_labels"}
    if classes & {"under_escalation", "bad_model_route", "policy_refusal"}:
        return {"tokens": "may_increase_for_preflight_or_fallback", "usd": "unknown", "latency_class": "medium"}
    return {"tokens": "unknown", "usd": "unknown", "latency_class": "unknown"}


def _evidence_refs(example: dict[str, Any]) -> list[str]:
    refs = [str(example["example_id"])]
    source = example.get("source", {})
    if "id" in source:
        refs.append(str(source["id"]))
    if "ids" in source:
        refs.extend(map(str, source["ids"]))
    if "path" in source:
        refs.append(str(source["path"]))
    return list(dict.fromkeys(refs))


def _evidence_minimum_ok(example: dict[str, Any]) -> bool:
    available = set(map(str, example.get("available_fields", [])))
    missing = set(map(str, example.get("missing_fields", [])))
    classes = set(map(str, example.get("negative_classes", [])))
    if classes & INSTRUMENTATION_RISK_CLASSES:
        return False
    if "quality outcome per session" in " ".join(missing).lower():
        return False
    return bool(available and example.get("quality_signal"))


def _cost_delta_usd(example: dict[str, Any]) -> float | None:
    observed = example.get("cost_observed", {})
    for key in ("delta_usd", "cost_delta_usd"):
        value = observed.get(key)
        if isinstance(value, (int, float)):
            return float(value)
    return None


def _score_notes(example: dict[str, Any], record: dict[str, Any]) -> str:
    label = example["label"]
    decision = record["governor_decision"]["governor_decision"]
    if label == POSITIVE_LABEL:
        return "positive control preserved as baseline/no-change"
    if decision == "needs_human":
        return "requires joined labels/instrumentation before scoring authority"
    if decision == "block":
        return "known seed risk blocks enforcement; shadow receipt only"
    return "authorized only as non-executing shadow counterfactual"


def _yn(value: Any) -> str:
    return "yes" if bool(value) else "no"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Replay learned-orchestration seed examples in shadow mode")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT, help="seed examples JSONL")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="comparison receipts JSONL")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT, help="markdown report path")
    args = parser.parse_args(argv)

    try:
        examples = load_examples(args.input)
        records = evaluate_examples(examples)
        summary = summarize(records)
        write_jsonl(records, args.output)
        write_report(records, summary, args.report)
    except Exception as exc:  # pragma: no cover - CLI guardrail
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(f"wrote {len(records)} shadow comparison records to {args.output}")
    print(f"wrote shadow evaluator report to {args.report}")
    print(f"recommendation: {summary['phase0_recommendation']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
