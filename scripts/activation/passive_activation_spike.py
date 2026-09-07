#!/usr/bin/env python3
"""F0 passive-activation spike harness.

This is intentionally a small historical-evaluation harness, not a production
activation dashboard. It answers the F0 go/no-go question from sylveste-xofc:
can existing CASS traces + git history detect the three documented activation
sprint / shadow-mode cases well enough to ship a passive v1?
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
WINDOW_DAYS = 14
MS_PER_DAY = 24 * 60 * 60 * 1000

# Generic activation-gap vocabulary. These are deliberately not bead-specific;
# bead-specific queries only scope the search space to the historical fixture.
DEFAULT_POSITIVE_PATTERNS = [
    r"\bzombie\b",
    r"phase:done",
    r"already shipped",
    r"already committed",
    r"shadow\s+to\s+enforce",
    r"shadow[- ]mode",
    r"\boff\s+mode\b",
    r"cache\s+was\s+empty",
    r"never\s+deployed",
    r"DISCOVERY_UNAVAILABLE",
    r"delegation\.mode\s+switched",
    r"enforce\s+mode",
]
POSITIVE_RE = re.compile("|".join(f"(?:{p})" for p in DEFAULT_POSITIVE_PATTERNS), re.I)


@dataclass(frozen=True)
class Fixture:
    bead: str
    title: str
    anchor_commit: str
    anchor_label: str
    queries: tuple[str, ...]


FIXTURES = (
    Fixture(
        bead="iv-zsio",
        title="Discovery pipeline integration / interphase hooks",
        anchor_commit="607329f3",
        anchor_label="interphase fix commit claiming discovery_scan_beads no longer returns DISCOVERY_UNAVAILABLE",
        queries=(
            "iv-zsio",
            "DISCOVERY_UNAVAILABLE",
            "discovery_scan_beads",
            "interphase hooks never deployed",
            "plugin cache was empty",
        ),
    ),
    Fixture(
        bead="iv-godia",
        title="Routing decisions as kernel facts",
        anchor_commit="f9f038dd",
        anchor_label="plan-complete commit used as shipped/activation anchor; Demarch bead DB no longer local",
        queries=(
            "iv-godia",
            "routing decisions as kernel facts",
            "already committed",
            "zombie sweep",
        ),
    ),
    Fixture(
        bead="iv-2s7k7",
        title="Codex-first routing activation",
        anchor_commit="5213e1be",
        anchor_label="activation commit claiming all 4 layers verified and delegation.mode moved shadow→enforce",
        queries=(
            "iv-2s7k7",
            "delegation.mode switched from shadow to enforce",
            "codex-delegate agent",
            "bwrap sandbox auto-detection",
        ),
    ),
)


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def git_epoch_ms(commit: str) -> int:
    proc = run(["git", "show", "-s", "--format=%ct", commit])
    if proc.returncode != 0:
        raise RuntimeError(f"git show failed for {commit}: {proc.stderr.strip()}")
    return int(proc.stdout.strip()) * 1000


def iso(ms: int | None) -> str | None:
    if ms is None:
        return None
    return dt.datetime.fromtimestamp(ms / 1000, dt.timezone.utc).isoformat()


def short_duration(ms: int | None) -> str | None:
    if ms is None:
        return None
    seconds = ms // 1000
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    parts: list[str] = []
    if days:
        parts.append(f"{days}d")
    if hours or days:
        parts.append(f"{hours}h")
    parts.append(f"{minutes}m")
    return " ".join(parts)


def cass_hits(query: str) -> list[dict]:
    proc = run(["cass", "search", query, "--robot", "--limit", "50", "--mode", "lexical"])
    if proc.returncode != 0:
        return []
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []
    return data.get("hits", []) or []


def git_hits(bead: str) -> list[dict]:
    proc = run([
        "git",
        "log",
        "--all",
        "--format=%H%x00%ct%x00%s%x00%b%x1e",
        "--grep",
        bead,
    ])
    if proc.returncode != 0:
        return []
    hits: list[dict] = []
    for record in proc.stdout.split("\x1e"):
        if not record.strip():
            continue
        parts = record.strip("\n").split("\x00", 3)
        if len(parts) < 4:
            continue
        commit, epoch, subject, body = parts
        content = f"{subject}\n{body}".strip()
        hits.append(
            {
                "kind": "git",
                "created_at": int(epoch) * 1000,
                "source": commit[:8],
                "content": content,
            }
        )
    return hits


def normalize_cass_hit(hit: dict, query: str) -> dict:
    content = " ".join(
        str(hit.get(key) or "") for key in ("title", "snippet", "content")
    )
    return {
        "kind": "cass",
        "created_at": hit.get("created_at"),
        "source": hit.get("source_path"),
        "query": query,
        "content": content,
    }


def compact_excerpt(text: str, limit: int = 180) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    return text[: limit - 1] + "…" if len(text) > limit else text


def evaluate(fixture: Fixture) -> dict:
    anchor_ms = git_epoch_ms(fixture.anchor_commit)
    window_end_ms = anchor_ms + WINDOW_DAYS * MS_PER_DAY

    all_hits: list[dict] = []
    for query in fixture.queries:
        all_hits.extend(normalize_cass_hit(hit, query) for hit in cass_hits(query))
    all_hits.extend(git_hits(fixture.bead))

    scoped: list[dict] = []
    seen: set[tuple[str, int | None, str]] = set()
    for hit in all_hits:
        ts = hit.get("created_at")
        if not isinstance(ts, int):
            continue
        if ts < anchor_ms or ts > window_end_ms:
            continue
        content = hit.get("content", "")
        if not POSITIVE_RE.search(content):
            continue
        key = (hit.get("kind", ""), ts, hit.get("source", ""))
        if key in seen:
            continue
        seen.add(key)
        scoped.append(hit)

    scoped.sort(key=lambda h: h["created_at"])
    earliest = scoped[0] if scoped else None
    unique_cass_sessions = {
        h.get("source") for h in scoped if h.get("kind") == "cass" and h.get("source")
    }
    latency_ms = None if earliest is None else earliest["created_at"] - anchor_ms
    return {
        "bead": fixture.bead,
        "title": fixture.title,
        "anchor_commit": fixture.anchor_commit,
        "anchor_label": fixture.anchor_label,
        "anchor_ts": iso(anchor_ms),
        "caught": earliest is not None,
        "first_detection_ts": iso(None if earliest is None else earliest["created_at"]),
        "detection_latency": short_duration(latency_ms),
        "detection_latency_ms": latency_ms,
        "positive_hit_count": len(scoped),
        "distinct_positive_cass_sessions": len(unique_cass_sessions),
        "evidence": [
            {
                "kind": hit.get("kind"),
                "ts": iso(hit.get("created_at")),
                "source": hit.get("source"),
                "query": hit.get("query"),
                "excerpt": compact_excerpt(hit.get("content", "")),
            }
            for hit in scoped[:3]
        ],
    }


def build_report() -> dict:
    rows = [evaluate(fixture) for fixture in FIXTURES]
    caught = sum(1 for row in rows if row["caught"])
    return {
        "window_days": WINDOW_DAYS,
        "positive_patterns": DEFAULT_POSITIVE_PATTERNS,
        "fixtures_total": len(rows),
        "caught_total": caught,
        "recall": f"{caught}/{len(rows)}",
        "next_phase": "passive-v1" if caught >= 2 else "explicit-emit-v1",
        "rows": rows,
    }


def as_markdown(report: dict) -> str:
    lines = [
        "# Passive activation spike harness output",
        "",
        f"Recall: **{report['recall']}**",
        f"Decision: **{report['next_phase']}**",
        f"Window: {report['window_days']}d after fixture anchor commit",
        "",
        "| Bead | Caught | First detection | Latency | Distinct positive CASS sessions | Evidence hits |",
        "|---|---:|---|---:|---:|---:|",
    ]
    for row in report["rows"]:
        lines.append(
            "| {bead} | {caught} | {first_detection_ts} | {detection_latency} | {distinct_positive_cass_sessions} | {positive_hit_count} |".format(
                **row
            )
        )
    lines.extend(["", "## Evidence excerpts", ""])
    for row in report["rows"]:
        lines.append(f"### {row['bead']} — {row['title']}")
        lines.append(f"Anchor: `{row['anchor_commit']}` — {row['anchor_label']} ({row['anchor_ts']})")
        for item in row["evidence"]:
            src = item.get("source") or "unknown"
            query = f" query={item.get('query')!r}" if item.get("query") else ""
            lines.append(f"- `{item['kind']}` {item['ts']} `{src}`{query}: {item['excerpt']}")
        lines.append("")
    return "\n".join(lines)


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    args = parser.parse_args(list(argv) if argv is not None else None)
    report = build_report()
    if args.format == "markdown":
        print(as_markdown(report))
    else:
        print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
