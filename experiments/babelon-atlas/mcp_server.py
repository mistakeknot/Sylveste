#!/usr/bin/env python3
"""Read-only MCP server over the symbol atlas, for agents building on Babelon.

Same wire style as bridger's mcp/server.py: stdio JSON-RPC, standard library
only, nothing to install. Point an MCP client at it:

  {"mcpServers": {"babelon-atlas": {
     "command": "python3",
     "args": ["/path/to/babelon-atlas/mcp_server.py"],
     "env": {"BABELON_ATLAS": "/path/to/symbol-atlas.json",
             "BABELON_ROOMS": "/path/to/invisible-rooms/rooms"}}}}

It never writes. It cannot reach jawnomicon's Neo4j or bridger's CanonGraph --
it reads the built atlas file, which is the point: the graphs stay where they
are and only the joined, tiered export travels.
"""

from __future__ import annotations

import json
import os
import pathlib
import sys
from typing import Any

import atlas as A

PROTOCOL_VERSION = "2024-11-05"

ATLAS_PATH = pathlib.Path(os.environ.get("BABELON_ATLAS", A.DEFAULT_ATLAS))
ROOMS_PATH = os.environ.get("BABELON_ROOMS")

TOOLS = [
    {
        "name": "symbol_lookup",
        "description": (
            "Look up one symbol by name or slug. Returns its gloss, how many "
            "sources attest it, its symbol-domain placement (world, subcategory, "
            "sense and furniture counts), and any creatures whose description "
            "cites it, with the citing sentence."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}},
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "symbol_search",
        "description": "Search symbol names and glosses for a keyword.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "limit": {"type": "integer", "minimum": 1, "maximum": 100, "default": 20},
            },
            "required": ["query"],
            "additionalProperties": False,
        },
    },
    {
        "name": "room_seed",
        "description": (
            "Draw one or more room seeds: a symbol that carries a domain, with "
            "its furniture counts and any linked creature. Use it to start a "
            "room from attested material rather than from a mood."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "world": {"type": "string", "description": "e.g. 'Creation and Cosmos'"},
                "linked": {"type": "boolean", "default": False,
                           "description": "only symbols that have a creature"},
                "count": {"type": "integer", "minimum": 1, "maximum": 10, "default": 1},
                "seed": {"type": "integer", "description": "reproducible draw"},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "convergence",
        "description": (
            "The tic watch. Reads a Babelon rooms/ directory and reports which "
            "words the rooms already share and how many, plus a per-room "
            "mechanism check (present, and one sentence). Moods are why twenty "
            "rooms turn into one room; this measures the drift directly."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "rooms_dir": {"type": "string",
                              "description": "defaults to $BABELON_ROOMS"},
                "limit": {"type": "integer", "minimum": 1, "maximum": 200, "default": 25},
            },
            "additionalProperties": False,
        },
    },
]


def _atlas() -> dict:
    return A.load_atlas(ATLAS_PATH)


def _symbol_payload(atlas: dict, symbol: dict) -> dict:
    out = dict(symbol)
    creatures = []
    for link in symbol.get("creatures") or []:
        creature = A.creature_by_id(atlas, link["id"])
        creatures.append({**link, **({"creature": creature} if creature else {})})
    if creatures:
        out["creatures"] = creatures
    return out


def _symbol_lookup(name: str) -> dict:
    atlas = _atlas()
    symbol = A.find(atlas, name)
    if not symbol:
        return {"found": False, "name": name}
    return {"found": True, "symbol": _symbol_payload(atlas, symbol)}


def _symbol_search(query: str, limit: int) -> dict:
    atlas = _atlas()
    needle = query.lower()
    hits = [
        s for s in atlas["symbols"]
        if needle in s["name"].lower() or needle in (s.get("gloss") or "").lower()
    ]
    return {
        "total": len(hits),
        "results": [
            {
                "name": s["name"],
                "slug": s["slug"],
                "register": s["register"],
                "gloss": s.get("gloss"),
                "in": s["in"],
                "world": (s.get("domain") or {}).get("world"),
            }
            for s in hits[:limit]
        ],
    }


def _room_seed(world: str | None, linked: bool, count: int, seed: int | None) -> dict:
    import random

    atlas = _atlas()
    pool = [s for s in atlas["symbols"] if s.get("domain")]
    if world:
        pool = [s for s in pool if s["domain"]["world"].lower().startswith(world.lower())]
    if linked:
        pool = [s for s in pool if s.get("creatures")]
    if not pool:
        return {"seeds": [], "note": "no symbol matches that filter"}
    drawn = random.Random(seed).sample(pool, min(count, len(pool)))
    return {"seeds": [_symbol_payload(atlas, s) for s in drawn]}


def _convergence(rooms_dir: str | None, limit: int) -> dict:
    target = rooms_dir or ROOMS_PATH
    if not target:
        return {"error": "no rooms_dir given and BABELON_ROOMS is unset"}
    path = pathlib.Path(target)
    paths = sorted(p for p in path.glob("*.md") if p.stem != "TEMPLATE")
    if not paths:
        return {"error": f"no rooms in {target}"}

    import collections

    rooms = [A.parse_room(p) for p in paths]
    use: dict[str, set[str]] = collections.defaultdict(set)
    for room in rooms:
        body = room["fields"].get("THE CITY", room["text"]).lower()
        for word in set(A.WORD.findall(body)):
            if word not in A.STOP:
                use[word].add(room["slug"])

    n = len(rooms)
    shared = sorted(
        ((w, sorted(r)) for w, r in use.items() if len(r) > 1),
        key=lambda item: (-len(item[1]), item[0]),
    )
    import re as _re

    mechanisms = []
    for room in rooms:
        mech = " ".join((room["fields"].get("MECHANISM") or "").split())
        mechanisms.append({
            "room": room["slug"],
            "author": room["meta"].get("author"),
            "present": bool(mech),
            "words": len(mech.split()),
            "sentences": len([s for s in _re.split(r"(?<=[.!?])\s+", mech) if s.strip()]),
        })
    return {
        "rooms": [r["slug"] for r in rooms],
        "shared_word_count": len(shared),
        "in_every_room": [w for w, r in shared if len(r) == n],
        "shared": [{"word": w, "breadth": len(r), "rooms": r} for w, r in shared[:limit]],
        "mechanisms": mechanisms,
        "incomplete": [
            {"room": room["slug"], "missing": field}
            for room in rooms
            for field in ("MECHANISM", "ACTION", "CONSEQUENCE", "DISCOVERABLE TEXT", "THE CITY")
            if not room["fields"].get(field)
        ],
    }


def _result(payload: Any) -> dict:
    return {"content": [{"type": "text",
                         "text": json.dumps(payload, ensure_ascii=False, indent=2)}]}


def _error(request_id: Any, message: str, code: int = -32602) -> dict:
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


def _call(name: str, arguments: dict, request_id: Any) -> dict:
    if name == "symbol_lookup":
        if not isinstance(arguments.get("name"), str):
            return _error(request_id, "symbol_lookup requires a string 'name'")
        return {"jsonrpc": "2.0", "id": request_id,
                "result": _result(_symbol_lookup(arguments["name"]))}
    if name == "symbol_search":
        if not isinstance(arguments.get("query"), str):
            return _error(request_id, "symbol_search requires a string 'query'")
        limit = arguments.get("limit", 20)
        if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 100:
            return _error(request_id, "limit must be an integer from 1 to 100")
        return {"jsonrpc": "2.0", "id": request_id,
                "result": _result(_symbol_search(arguments["query"], limit))}
    if name == "room_seed":
        count = arguments.get("count", 1)
        if isinstance(count, bool) or not isinstance(count, int) or not 1 <= count <= 10:
            return _error(request_id, "count must be an integer from 1 to 10")
        return {"jsonrpc": "2.0", "id": request_id,
                "result": _result(_room_seed(arguments.get("world"),
                                             bool(arguments.get("linked", False)),
                                             count, arguments.get("seed")))}
    if name == "convergence":
        limit = arguments.get("limit", 25)
        if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 200:
            return _error(request_id, "limit must be an integer from 1 to 200")
        return {"jsonrpc": "2.0", "id": request_id,
                "result": _result(_convergence(arguments.get("rooms_dir"), limit))}
    return _error(request_id, f"unknown tool: {name}")


def handle(request: dict) -> dict | None:
    request_id = request.get("id")
    method = request.get("method")
    if request_id is None:
        return None
    if method == "initialize":
        return {"jsonrpc": "2.0", "id": request_id, "result": {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "babelon-atlas", "version": "0.1.0"},
        }}
    if method == "ping":
        return {"jsonrpc": "2.0", "id": request_id, "result": {}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": request_id, "result": {"tools": TOOLS}}
    if method == "tools/call":
        params = request.get("params") or {}
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict):
            return _error(request_id, "tool arguments must be an object")
        return _call(params.get("name"), arguments, request_id)
    return _error(request_id, f"method not found: {method}", code=-32601)


def main() -> int:
    for line in sys.stdin:
        if not line.strip():
            continue
        request_id = None
        try:
            request = json.loads(line)
            if isinstance(request, dict):
                request_id = request.get("id")
            response = handle(request)
        except Exception:
            response = {"jsonrpc": "2.0", "id": request_id,
                        "error": {"code": -32603, "message": "internal error"}}
        if response is not None:
            sys.stdout.write(json.dumps(response, separators=(",", ":")) + "\n")
            sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
