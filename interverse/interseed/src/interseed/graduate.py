"""Graduation: promote mature ideas to beads + brainstorm docs."""

from __future__ import annotations

import asyncio
import json
import re
from datetime import date
from pathlib import Path

from .config import load_config
from .db import InterseedDB
from .models import Idea


def slugify(text: str, max_len: int = 40) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug[:max_len].rstrip("-")


async def graduate(
    db: InterseedDB, idea_id: str, config: dict | None = None
) -> tuple[str, str]:
    """Graduate an idea to a bead + brainstorm doc.

    Returns (bead_id, doc_path).
    Raises ValueError on guard failures.
    """
    if config is None:
        config = load_config()

    idea = db.get_idea(idea_id)

    # Re-entry guard
    if idea.graduated_bead_id and idea.graduated_bead_id != "PENDING":
        raise ValueError(
            f"Idea {idea_id} already graduated (bead: {idea.graduated_bead_id})"
        )

    grad_config = config.get("graduation", {})
    threshold = grad_config.get("confidence_threshold", 0.7)

    if idea.confidence < threshold:
        raise ValueError(
            f"Confidence {idea.confidence:.2f} < {threshold} threshold"
        )

    if not db.has_graduation_approval(idea_id):
        raise ValueError("No graduation_approval annotation found")

    # PENDING sentinel before external call
    if idea.graduated_bead_id != "PENDING":
        db.update_idea(idea_id, graduated_bead_id="PENDING")

    monorepo_root = grad_config.get("monorepo_root", "~/projects/Sylveste")
    monorepo_root = str(Path(monorepo_root).expanduser())

    # Safe: create_subprocess_exec with list args, no shell
    try:
        proc = await asyncio.create_subprocess_exec(
            "bd", "create",
            "--title", idea.thesis[:120],
            "--type", "feature",
            "--priority", "2",
            "--description",
            f"Graduated from idea garden. Evidence: {len(idea.evidence)} items, confidence: {idea.confidence:.2f}",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=monorepo_root,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=30
        )
    except FileNotFoundError:
        raise RuntimeError("bd CLI not found on PATH")
    except asyncio.TimeoutError:
        proc.terminate()
        await proc.wait()
        raise RuntimeError("bd create timed out")

    if proc.returncode != 0:
        raise RuntimeError(f"bd create failed: {stderr.decode()[:200]}")

    output = stdout.decode().strip()
    bead_id = _parse_bead_id(output)
    if not bead_id:
        raise RuntimeError(f"Could not parse bead ID from: {output}")

    brainstorm_dir = grad_config.get("brainstorm_dir", "docs/brainstorms/")
    doc_path = _write_brainstorm(idea, db, brainstorm_dir)

    db.update_idea(idea_id, maturity="mature", graduated_bead_id=bead_id)

    return bead_id, doc_path


def _parse_bead_id(output: str) -> str | None:
    for line in output.split("\n"):
        match = re.search(r"([\w]+-[\w]+)", line)
        if match:
            return match.group(1)
    return None


def _write_brainstorm(
    idea: Idea, db: InterseedDB, brainstorm_dir: str
) -> str:
    history = db.refinement_history(idea.id, limit=20)
    annotations = db.annotations_for(idea.id)

    slug = slugify(idea.thesis[:40])
    filename = f"{date.today()}-{slug}-brainstorm.md"
    path = Path(brainstorm_dir) / filename
    path.parent.mkdir(parents=True, exist_ok=True)

    evidence_list = (
        "\n".join(f"- {e}" for e in idea.evidence)
        if idea.evidence
        else "- (none)"
    )
    questions_list = (
        "\n".join(f"- {q}" for q in idea.open_questions)
        if idea.open_questions
        else "- (none)"
    )

    history_list = ""
    if history:
        history_list = "\n".join(
            f"- [{h.trigger}] {h.summary} "
            f"(conf {h.confidence_before:.1f} -> {h.confidence_after:.1f})"
            for h in reversed(history)
        )

    annotation_list = ""
    if annotations:
        annotation_list = "\n".join(
            f"- [{a.annotation_type}] {a.body}" for a in annotations
        )

    content = f"""---
artifact_type: brainstorm
bead: {idea.graduated_bead_id if idea.graduated_bead_id != 'PENDING' else 'pending'}
stage: discover
source: interseed-graduation
idea_id: {idea.id}
---

# {idea.thesis}

## What We're Building

{idea.thesis}

## Evidence

{evidence_list}

## Open Questions

{questions_list}

## Refinement History

{history_list or "No refinement history."}

## Human Feedback

{annotation_list or "No annotations."}

## Key Decisions

- Graduated from idea garden with confidence {idea.confidence:.2f}
- Keywords: {', '.join(idea.keywords)}
- Source: {idea.source}
"""

    path.write_text(content)
    return str(path)
