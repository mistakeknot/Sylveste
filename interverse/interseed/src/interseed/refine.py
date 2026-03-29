"""Refinement engine for interseed ideas."""

from __future__ import annotations

import asyncio
import json
import logging

from .config import load_config
from .context import RefinementContext, gather_context
from .db import InterseedDB
from .models import Idea, RefinementLog

logger = logging.getLogger(__name__)


def compute_maturity(confidence: float) -> str:
    if confidence < 0.3:
        return "seed"
    if confidence < 0.5:
        return "sprouting"
    if confidence < 0.7:
        return "growing"
    return "mature"


async def refine_all(
    db: InterseedDB,
    trigger: str = "scheduled",
    limit: int = 10,
    config: dict | None = None,
) -> list[RefinementLog]:
    """Process all eligible ideas. Returns list of refinement logs."""
    if config is None:
        config = load_config()

    stale_minutes = config.get("refinement", {}).get("lock_stale_minutes", 10)
    ideas = db.list_refinable(limit=limit)
    results = []

    for idea in ideas:
        if not db.try_lock(idea.id, stale_minutes=stale_minutes):
            logger.info("Skipping %s: locked by another process", idea.id)
            continue

        try:
            log_entry = await refine_one(idea, db, trigger=trigger, config=config)
            if log_entry:
                results.append(log_entry)
        finally:
            db.unlock(idea.id)

    return results


async def refine_one(
    idea: Idea,
    db: InterseedDB,
    trigger: str = "manual",
    config: dict | None = None,
) -> RefinementLog | None:
    """Refine a single idea. Returns log entry or None if skipped."""
    if config is None:
        config = load_config()

    ctx = await gather_context(idea, db, config)

    # Idempotency: skip if context hash unchanged
    ctx_hash = ctx.content_hash()
    last_hash = db.last_context_hash(idea.id)
    if ctx_hash == last_hash:
        logger.info("Skipping %s: context unchanged (hash %s)", idea.id, ctx_hash)
        return None

    # Call Claude — no DB transaction held during this call
    refinement = await _call_refinement(idea, ctx, config)
    if refinement is None:
        return None

    # Write in a single short transaction
    new_confidence = refinement.get("confidence", idea.confidence)
    new_maturity = compute_maturity(new_confidence)
    new_evidence = idea.evidence + refinement.get("new_evidence", [])

    db.update_idea(
        idea.id,
        thesis=refinement.get("thesis", idea.thesis),
        evidence=new_evidence,
        confidence=new_confidence,
        maturity=new_maturity,
        open_questions=refinement.get("open_questions", idea.open_questions),
    )

    return db.log_refinement(
        idea_id=idea.id,
        trigger=trigger,
        summary=refinement.get("summary", "Refined"),
        confidence_before=idea.confidence,
        confidence_after=new_confidence,
        new_evidence=refinement.get("new_evidence", []),
        context_hash=ctx_hash,
    )


async def _call_refinement(
    idea: Idea, ctx: RefinementContext, config: dict | None = None
) -> dict | None:
    """Call Claude to refine an idea. Text via stdin (safe, no shell)."""
    model = (config or {}).get("refinement", {}).get("model", "claude-sonnet-4-6")

    history_text = ""
    if ctx.history:
        history_text = "Refinement history:\n" + "\n".join(
            f"- [{h.trigger}] {h.summary} (conf {h.confidence_before:.1f} -> {h.confidence_after:.1f})"
            for h in ctx.history[:3]
        )

    annotations_text = ""
    if ctx.annotations:
        annotations_text = "Human feedback:\n" + "\n".join(
            f"- [{a.annotation_type}] {a.body}" for a in ctx.annotations
        )

    beads_text = ""
    if ctx.related_beads:
        beads_text = "Related beads (active work):\n" + "\n".join(
            f"- {b}" for b in ctx.related_beads
        )

    brainstorms_text = ""
    if ctx.related_brainstorms:
        brainstorms_text = "Related brainstorms:\n" + "\n".join(
            f"- {b}" for b in ctx.related_brainstorms
        )

    prompt = f"""You are refining an idea in an idea garden. This idea has been through {len(ctx.history)} refinement cycles.

Current state:
- Thesis: {idea.thesis}
- Evidence: {json.dumps(idea.evidence)}
- Confidence: {idea.confidence}
- Open questions: {json.dumps(idea.open_questions)}

{history_text or "No prior refinements."}

{annotations_text or "No human feedback yet."}

{beads_text or "No related active work found."}

{brainstorms_text or "No related brainstorms found."}

Your job:
1. Refine the thesis if new evidence warrants it
2. Add new evidence items (cite sources when possible)
3. Update confidence (0.0-1.0) based on evidence strength
4. Update open questions (answer resolved ones, add new ones)
5. Write a 1-sentence summary of what changed

If nothing meaningful has changed, set confidence to the same value and summary to "No meaningful changes".

Respond as JSON only: {{"thesis": "...", "new_evidence": [...], "confidence": 0.X, "open_questions": [...], "summary": "..."}}"""

    # Safe: create_subprocess_exec with list args, text via stdin
    try:
        proc = await asyncio.create_subprocess_exec(
            "claude", "-p",
            "--model", model,
            "--output-format", "text",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(input=prompt.encode()), timeout=60
        )
    except FileNotFoundError:
        logger.error("claude CLI not found on PATH")
        return None
    except asyncio.TimeoutError:
        proc.terminate()
        await proc.wait()
        logger.error("Claude CLI timed out for idea %s", idea.id)
        return None

    if proc.returncode != 0:
        logger.error("Claude CLI error: %s", stderr.decode()[:200])
        return None

    text = stdout.decode().strip()
    if "```" in text:
        lines = text.split("\n")
        json_lines = []
        in_block = False
        for line in lines:
            if line.startswith("```"):
                in_block = not in_block
                continue
            if in_block:
                json_lines.append(line)
        text = "\n".join(json_lines)

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        logger.error("Failed to parse refinement response: %s", text[:200])
        return None
