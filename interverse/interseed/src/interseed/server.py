"""interseed MCP server — exposes idea garden tools."""

from __future__ import annotations

import asyncio
import json
import logging
import signal
import sys
from typing import Any

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

from .config import get_db_path, load_config
from .db import InterseedDB

logger = logging.getLogger(__name__)


def create_server(config: dict | None = None) -> tuple[Server, dict]:
    """Create and configure the MCP server."""
    if config is None:
        config = load_config()

    server = Server("interseed")

    db = InterseedDB(get_db_path(config))
    db.connect()
    ctx = {"db": db, "config": config}

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="interseed_status",
                description="Show idea garden status: counts by maturity, unenriched, last refinement time.",
                inputSchema={"type": "object", "properties": {}},
            ),
            Tool(
                name="interseed_list_ideas",
                description="List ideas in the garden, optionally filtered by maturity stage.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "maturity": {
                            "type": "string",
                            "description": "Filter by maturity: seed, sprouting, growing, mature",
                            "enum": ["seed", "sprouting", "growing", "mature"],
                        },
                        "limit": {
                            "type": "integer",
                            "description": "Max ideas to return (default 20)",
                        },
                    },
                },
            ),
            Tool(
                name="interseed_plant",
                description="Plant a new idea in the garden (fast, no LLM). Returns the new idea.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "text": {
                            "type": "string",
                            "description": "Raw idea text to capture",
                        },
                        "source": {
                            "type": "string",
                            "description": "Source of the idea",
                            "enum": ["cli", "auraken", "manual"],
                        },
                    },
                    "required": ["text"],
                },
            ),
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[TextContent]:
        if name == "interseed_status":
            stats = db.stats()
            lines = [f"Ideas: {stats['total']}"]
            for maturity, count in sorted(stats["by_maturity"].items()):
                lines.append(f"  {maturity}: {count}")
            if stats["unenriched"]:
                lines.append(f"  pending enrichment: {stats['unenriched']}")
            if stats["last_refinement"]:
                lines.append(f"Last refinement: {stats['last_refinement']}")
            return [TextContent(type="text", text="\n".join(lines))]

        elif name == "interseed_list_ideas":
            maturity = arguments.get("maturity")
            limit = arguments.get("limit", 20)
            ideas = db.list_ideas(maturity=maturity, limit=limit)
            if not ideas:
                return [TextContent(type="text", text="No ideas in the garden.")]

            lines = []
            for idea in ideas:
                evidence_count = len(idea.evidence)
                questions_count = len(idea.open_questions)
                enriched = "" if idea.enriched else " [pending enrichment]"
                lines.append(
                    f"{idea.id} [{idea.maturity}] conf={idea.confidence:.1f} "
                    f"evidence={evidence_count} questions={questions_count}{enriched}"
                )
                lines.append(f"  {idea.thesis}")
                if idea.keywords:
                    lines.append(f"  tags: {', '.join(idea.keywords)}")
                lines.append("")
            return [TextContent(type="text", text="\n".join(lines))]

        elif name == "interseed_plant":
            text = arguments.get("text", "").strip()
            if not text:
                return [TextContent(type="text", text="Error: text is required")]
            source = arguments.get("source", "manual")
            idea = db.plant_idea(thesis=text, source=source)
            return [
                TextContent(
                    type="text",
                    text=f"Planted idea {idea.id} (seed, pending enrichment)\n  {idea.thesis}",
                )
            ]

        return [TextContent(type="text", text=f"Unknown tool: {name}")]

    return server, ctx


async def run() -> None:
    server, ctx = create_server()
    options = server.create_initialization_options()
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, options)


def main() -> None:
    asyncio.run(run())


if __name__ == "__main__":
    main()
