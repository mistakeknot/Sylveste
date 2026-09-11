#!/usr/bin/env python3
"""Smoke tests: the join's invariants, and the MCP wire."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ATLAS = HERE / "symbol-atlas.json"


def test_atlas_is_structure_tier():
    atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
    assert atlas["manifest"]["schema"] == "babelon-symbol-atlas/1"
    assert atlas["manifest"]["tier"] == "structure"


def test_structure_tier_ships_no_extracted_source_text():
    """The copyright contract, enforced rather than asserted."""
    atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
    for symbol in atlas["symbols"]:
        domain = symbol.get("domain") or {}
        assert "senses" not in domain, f"{symbol['name']} ships de Vries/Cooper sense text"
        assert "furniture" not in domain, f"{symbol['name']} ships ARAS furniture text"
    for creature in atlas["creatures"]:
        assert "short_description" not in creature, f"{creature['name']} ships prose"


def test_every_symbol_declares_its_provenance():
    atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
    for symbol in atlas["symbols"]:
        assert symbol["in"], symbol["name"]
        assert set(symbol["in"]) <= {"jawnomicon", "bridger"}
        # A jawnomicon row always carries an original gloss; a bridger-only row
        # never invents one.
        if "jawnomicon" in symbol["in"]:
            assert symbol["gloss"]
        else:
            assert symbol["gloss"] is None


def test_creature_links_resolve():
    atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
    known = {c["id"] for c in atlas["creatures"]}
    for symbol in atlas["symbols"]:
        for link in symbol.get("creatures") or []:
            assert link["id"] in known, f"{symbol['name']} -> unknown creature {link['id']}"
            assert link["evidence"], "a link without its citing sentence is not evidence"


def _rpc(*requests, env=None):
    payload = "".join(json.dumps(r) + "\n" for r in requests)
    proc = subprocess.run(
        [sys.executable, str(HERE / "mcp_server.py")],
        input=payload, capture_output=True, text=True, timeout=120,
        cwd=HERE, env=env,
    )
    assert proc.returncode == 0, proc.stderr
    return [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]


def test_mcp_lists_its_tools():
    responses = _rpc({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    names = [t["name"] for t in responses[0]["result"]["tools"]]
    assert names == ["symbol_lookup", "symbol_search", "room_seed", "convergence"]


def test_mcp_lookup_returns_a_joined_symbol():
    responses = _rpc({
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": "symbol_lookup", "arguments": {"name": "rainbow"}},
    })
    payload = json.loads(responses[0]["result"]["content"][0]["text"])
    assert payload["found"]
    assert payload["symbol"]["in"] == ["jawnomicon", "bridger"]
    assert payload["symbol"]["domain"]["world"] == "Creation and Cosmos"


def test_mcp_rejects_bad_arguments():
    responses = _rpc({
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": "room_seed", "arguments": {"count": 99}},
    })
    assert responses[0]["error"]["code"] == -32602


def test_mcp_unknown_tool_is_an_error_not_a_crash():
    responses = _rpc({
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": "drop_tables", "arguments": {}},
    })
    assert "unknown tool" in responses[0]["error"]["message"]
