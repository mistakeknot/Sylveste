"""interseed CLI — idea garden management."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import datetime, timezone

from .config import get_db_path, load_config
from .db import InterseedDB


def _connect(config: dict | None = None) -> InterseedDB:
    if config is None:
        config = load_config()
    db = InterseedDB(get_db_path(config))
    db.connect()
    return db


def cmd_plant(args: argparse.Namespace) -> None:
    """Plant a new idea (fast — no LLM call)."""
    db = _connect()
    try:
        thesis = " ".join(args.text)
        if not thesis.strip():
            print("Error: idea text is required", file=sys.stderr)
            sys.exit(1)

        idea = db.plant_idea(thesis=thesis, source=args.source)

        if args.json:
            print(
                json.dumps(
                    {
                        "id": idea.id,
                        "thesis": idea.thesis,
                        "keywords": idea.keywords,
                        "enriched": idea.enriched,
                    }
                )
            )
        else:
            print(f"Captured idea {idea.id} (seed, pending enrichment)")
            print(f"  Thesis: {idea.thesis}")
    finally:
        db.close()


def cmd_enrich(args: argparse.Namespace) -> None:
    """Enrich unenriched ideas with Claude structuring."""
    db = _connect()
    try:
        if args.idea_id:
            ideas = [db.get_idea(args.idea_id)]
        else:
            ideas = db.list_ideas(enriched_only=False)
            ideas = [i for i in ideas if not i.enriched]

        if not ideas:
            print("No ideas to enrich.")
            return

        for idea in ideas:
            result = asyncio.run(_enrich_one(idea.id, idea.thesis))
            if result:
                db.update_idea(
                    idea.id,
                    thesis=result["thesis"],
                    keywords=result["keywords"],
                    open_questions=result.get("open_questions", []),
                    enriched=1,
                )
                print(f"Enriched {idea.id}: {result['thesis']}")
                print(f"  Keywords: {', '.join(result['keywords'])}")
            else:
                print(f"Failed to enrich {idea.id}", file=sys.stderr)
    finally:
        db.close()


async def _enrich_one(idea_id: str, raw_text: str) -> dict | None:
    """Call Claude CLI to structure a raw idea. Passes text via stdin (safe)."""
    prompt = (
        "Given this rough idea, extract:\n"
        "1. A clear one-sentence thesis\n"
        "2. 3-5 keywords for matching\n"
        "3. 1-3 open questions worth investigating\n\n"
        'Respond as JSON only: {"thesis": "...", "keywords": [...], "open_questions": [...]}'
    )

    # Safe: uses create_subprocess_exec (list args, no shell)
    # Text passed via stdin, not positional args
    try:
        proc = await asyncio.create_subprocess_exec(
            "claude",
            "-p",
            "--output-format",
            "text",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(input=f"{prompt}\n\nRaw idea: {raw_text}".encode()),
            timeout=60,
        )
    except FileNotFoundError:
        print("claude CLI not found on PATH", file=sys.stderr)
        return None
    except asyncio.TimeoutError:
        proc.terminate()
        await proc.wait()
        print(f"Claude CLI timed out for idea {idea_id}", file=sys.stderr)
        return None

    if proc.returncode != 0:
        print(f"Claude CLI error: {stderr.decode()[:200]}", file=sys.stderr)
        return None

    text = stdout.decode().strip()
    # Extract JSON from response (may have markdown fencing)
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
        print(
            f"Failed to parse Claude response as JSON: {text[:200]}", file=sys.stderr
        )
        return None


def cmd_list(args: argparse.Namespace) -> None:
    """List ideas with human-readable status."""
    db = _connect()
    try:
        ideas = db.list_ideas(maturity=args.maturity)
        if not ideas:
            print("No ideas in the garden.")
            return

        for idea in ideas:
            enriched_marker = "" if idea.enriched else " [pending enrichment]"
            evidence_count = len(idea.evidence)
            questions_count = len(idea.open_questions)
            print(
                f"  {idea.id}  [{idea.maturity}]  conf={idea.confidence:.1f}  "
                f"evidence={evidence_count}  questions={questions_count}"
                f"{enriched_marker}"
            )
            print(f"    {idea.thesis}")
            if idea.keywords:
                print(f"    tags: {', '.join(idea.keywords)}")
            print()
    finally:
        db.close()


def cmd_delete(args: argparse.Namespace) -> None:
    """Delete an idea."""
    db = _connect()
    try:
        db.delete_idea(args.idea_id)
        print(f"Deleted idea {args.idea_id}")
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        db.close()


def cmd_annotate(args: argparse.Namespace) -> None:
    """Add an annotation to an idea."""
    db = _connect()
    try:
        ann = db.add_annotation(
            idea_id=args.idea_id,
            source="manual",
            annotation_type=args.type,
            body=args.body,
        )
        print(f"Annotation {ann.id} added to idea {args.idea_id}")
    finally:
        db.close()


def cmd_refine(args: argparse.Namespace) -> None:
    """Refine ideas with Claude."""
    from .refine import refine_all, refine_one

    db = _connect()
    config = load_config()
    try:
        if args.idea_id:
            idea = db.get_idea(args.idea_id)
            log = asyncio.run(refine_one(idea, db, trigger="manual", config=config))
            if log:
                print(
                    f"Refined {idea.id}: {log.summary} "
                    f"(conf {log.confidence_before:.1f} -> {log.confidence_after:.1f})"
                )
            else:
                print(f"No changes for {idea.id} (context unchanged or error)")
        else:
            limit = args.limit or config.get("refinement", {}).get("limit", 10)
            logs = asyncio.run(
                refine_all(db, trigger="scheduled", limit=limit, config=config)
            )
            if logs:
                for log in logs:
                    print(
                        f"  {log.idea_id}: {log.summary} "
                        f"(conf {log.confidence_before:.1f} -> {log.confidence_after:.1f})"
                    )
                print(f"\nRefined {len(logs)} idea(s).")
            else:
                print("No ideas refined (all up to date or no eligible ideas).")
    finally:
        db.close()


def cmd_graduate(args: argparse.Namespace) -> None:
    """Graduate a mature idea to a bead + brainstorm doc."""
    from .graduate import graduate

    db = _connect()
    config = load_config()
    try:
        bead_id, doc_path = asyncio.run(graduate(db, args.idea_id, config))
        print(f"Graduated idea {args.idea_id}")
        print(f"  Bead: {bead_id}")
        print(f"  Brainstorm: {doc_path}")
    except (ValueError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        db.close()


def cmd_status(args: argparse.Namespace) -> None:
    """Show garden status."""
    db = _connect()
    try:
        stats = db.stats()
        print(f"Ideas: {stats['total']}")
        for maturity, count in sorted(stats["by_maturity"].items()):
            print(f"  {maturity}: {count}")
        if stats["unenriched"]:
            print(f"  pending enrichment: {stats['unenriched']}")
        if stats["last_refinement"]:
            print(f"Last refinement: {stats['last_refinement']}")
    finally:
        db.close()


def cli() -> None:
    parser = argparse.ArgumentParser(
        prog="interseed", description="Idea garden: capture, refine, graduate"
    )
    sub = parser.add_subparsers(dest="command")

    # plant
    p_plant = sub.add_parser("plant", help="Plant a new idea (fast, no LLM)")
    p_plant.add_argument("text", nargs="+", help="Raw idea text")
    p_plant.add_argument(
        "--source", default="cli", choices=["cli", "auraken", "manual"]
    )
    p_plant.add_argument(
        "--json", action="store_true", help="JSON output for machine parsing"
    )
    p_plant.set_defaults(func=cmd_plant)

    # enrich
    p_enrich = sub.add_parser("enrich", help="Enrich unenriched ideas with Claude")
    p_enrich.add_argument("idea_id", nargs="?", help="Specific idea to enrich")
    p_enrich.set_defaults(func=cmd_enrich)

    # refine
    p_refine = sub.add_parser("refine", help="Refine ideas with Claude")
    p_refine.add_argument("idea_id", nargs="?", help="Specific idea to refine")
    p_refine.add_argument("--limit", type=int, help="Max ideas per run")
    p_refine.set_defaults(func=cmd_refine)

    # list
    p_list = sub.add_parser("list", help="List ideas")
    p_list.add_argument(
        "--maturity", choices=["seed", "sprouting", "growing", "mature"]
    )
    p_list.set_defaults(func=cmd_list)

    # delete
    p_delete = sub.add_parser("delete", help="Delete an idea")
    p_delete.add_argument("idea_id", help="Idea ID to delete")
    p_delete.set_defaults(func=cmd_delete)

    # annotate
    p_ann = sub.add_parser("annotate", help="Add annotation to an idea")
    p_ann.add_argument("idea_id", help="Idea ID")
    p_ann.add_argument(
        "--type",
        required=True,
        choices=["comment", "steer", "graduation_approval"],
    )
    p_ann.add_argument("--body", required=True, help="Annotation text")
    p_ann.set_defaults(func=cmd_annotate)

    # graduate
    p_grad = sub.add_parser("graduate", help="Graduate a mature idea to a bead")
    p_grad.add_argument("idea_id", help="Idea ID to graduate")
    p_grad.set_defaults(func=cmd_graduate)

    # status
    p_status = sub.add_parser("status", help="Garden status summary")
    p_status.set_defaults(func=cmd_status)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    cli()
