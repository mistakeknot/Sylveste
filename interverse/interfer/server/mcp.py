"""MCP server for interfer — exposes health, model listing, and generation to Claude Code.

Launched via: uv run python -m server.mcp
Declared in .claude-plugin/plugin.json mcpServers.interfer
"""

from __future__ import annotations

import json
import sys

import httpx

INTERFERE_URL = "http://localhost:8421"


def _request(method: str, path: str, body: dict | None = None) -> dict:
    """Make a request to the interfer HTTP server."""
    try:
        if method == "GET":
            r = httpx.get(f"{INTERFERE_URL}{path}", timeout=5.0)
        else:
            r = httpx.post(f"{INTERFERE_URL}{path}", json=body, timeout=120.0)
        return r.json()
    except Exception as e:
        return {"error": str(e)}


def handle_request(req: dict) -> dict:
    """Handle a JSON-RPC request from Claude Code."""
    method = req.get("method", "")
    params = req.get("params", {})
    req_id = req.get("id")

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "interfer", "version": "0.1.0"},
            },
        }

    if method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "tools": [
                    {
                        "name": "interfer_health",
                        "description": "Check interfer server health, thermal state, and loaded models",
                        "inputSchema": {"type": "object", "properties": {}},
                    },
                    {
                        "name": "interfer_models",
                        "description": "List loaded models in the interfer Metal subprocess",
                        "inputSchema": {"type": "object", "properties": {}},
                    },
                    {
                        "name": "interfer_load",
                        "description": "Preload a model into the Metal subprocess",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "model": {
                                    "type": "string",
                                    "description": "HuggingFace model ID (e.g., mlx-community/Qwen3.5-35B-A3B-4bit)",
                                },
                            },
                            "required": ["model"],
                        },
                    },
                ],
            },
        }

    if method == "tools/call":
        tool_name = params.get("name", "")
        tool_args = params.get("arguments", {})

        if tool_name == "interfer_health":
            result = _request("GET", "/health")
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(result, indent=2)}],
                },
            }

        if tool_name == "interfer_models":
            result = _request("GET", "/health")
            models = result.get("models", [])
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps({"loaded_models": models}, indent=2),
                        }
                    ],
                },
            }

        if tool_name == "interfer_load":
            model = tool_args.get("model", "")
            result = _request("POST", "/v1/models/load", {"model": model})
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(result, indent=2)}],
                },
            }

        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": -32601, "message": f"Unknown tool: {tool_name}"},
        }

    if method == "notifications/initialized":
        return None  # No response for notifications

    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": -32601, "message": f"Unknown method: {method}"},
    }


def main() -> None:
    """Run the MCP server on stdin/stdout (stdio transport)."""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            resp = handle_request(req)
            if resp is not None:
                sys.stdout.write(json.dumps(resp) + "\n")
                sys.stdout.flush()
        except json.JSONDecodeError:
            sys.stderr.write(f"Invalid JSON: {line[:100]}\n")
        except Exception as e:
            sys.stderr.write(f"Error: {e}\n")


if __name__ == "__main__":
    main()
