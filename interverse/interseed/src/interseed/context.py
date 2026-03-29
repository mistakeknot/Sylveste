"""Context gathering for idea refinement."""

from __future__ import annotations

import asyncio
import glob
import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path

from .config import load_config
from .db import InterseedDB
from .models import Annotation, Idea, RefinementLog


@dataclass
class RefinementContext:
    """Gathered context for refining an idea."""

    related_beads: list[str] = field(default_factory=list)
    related_brainstorms: list[str] = field(default_factory=list)
    history: list[RefinementLog] = field(default_factory=list)
    annotations: list[Annotation] = field(default_factory=list)

    def content_hash(self) -> str:
        """SHA256 of serialized context for idempotency checking."""
        data = json.dumps(
            {
                "beads": self.related_beads,
                "brainstorms": self.related_brainstorms,
                "history_ids": [h.id for h in self.history],
                "annotation_ids": [a.id for a in self.annotations],
            },
            sort_keys=True,
        )
        return hashlib.sha256(data.encode()).hexdigest()[:16]


async def gather_context(
    idea: Idea, db: InterseedDB, config: dict | None = None
) -> RefinementContext:
    """Pull project context relevant to the idea."""
    if config is None:
        config = load_config()

    ctx = RefinementContext()

    # Related beads (via bd search — safe: list args, no shell)
    if idea.keywords:
        search_terms = " ".join(idea.keywords[:3])
        ctx.related_beads = await _search_beads(search_terms)

    # Related brainstorms (glob + keyword check, bounded)
    brainstorm_dir = config.get("graduation", {}).get(
        "brainstorm_dir", "docs/brainstorms/"
    )
    ctx.related_brainstorms = _find_related_brainstorms(
        idea.keywords, brainstorm_dir
    )

    # Refinement history
    ctx.history = db.refinement_history(idea.id, limit=5)

    # Annotations
    ctx.annotations = db.annotations_for(idea.id)

    return ctx


async def _search_beads(keywords: str) -> list[str]:
    """Search beads for related work. Safe: uses list args, no shell."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "bd",
            "search",
            keywords,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=15)
        if proc.returncode == 0 and stdout:
            lines = stdout.decode().strip().split("\n")
            return lines[:5]
    except (FileNotFoundError, asyncio.TimeoutError):
        pass
    return []


def _find_related_brainstorms(
    keywords: list[str], brainstorm_dir: str, max_files: int = 20
) -> list[str]:
    """Find brainstorm files matching idea keywords."""
    pattern = str(Path(brainstorm_dir) / "*.md")
    files = sorted(
        glob.glob(pattern), key=lambda f: Path(f).stat().st_mtime, reverse=True
    )
    files = files[:max_files]

    matches = []
    lower_keywords = [kw.lower() for kw in keywords]

    for f in files:
        try:
            content = Path(f).read_text().lower()
            if any(kw in content for kw in lower_keywords):
                matches.append(f)
        except OSError:
            continue

    return matches[:5]
