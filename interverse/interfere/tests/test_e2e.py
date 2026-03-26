"""End-to-end streaming test for interfere server."""

from __future__ import annotations

import json

import pytest
from httpx import ASGITransport, AsyncClient

from server.main import create_app


@pytest.mark.asyncio
async def test_e2e_streaming_with_dry_run() -> None:
    """Verify full request path: HTTP -> queue -> stream response."""
    app = create_app(dry_run=True)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        async with client.stream(
            "POST",
            "/v1/chat/completions",
            json={
                "model": "test",
                "messages": [{"role": "user", "content": "hi"}],
                "stream": True,
            },
        ) as resp:
            assert resp.status_code == 200
            chunks = []
            async for line in resp.aiter_lines():
                if line.startswith("data: ") and line != "data: [DONE]":
                    data = json.loads(line[6:])
                    chunks.append(data)

            # At least one content chunk + one finish chunk
            assert len(chunks) >= 2

            # Last chunk should have finish_reason
            last = chunks[-1]
            assert last["choices"][0]["finish_reason"] == "stop"

            # Content chunks should have delta.content
            content_chunks = [
                c for c in chunks if c["choices"][0].get("delta", {}).get("content")
            ]
            assert len(content_chunks) >= 1

            # Reassemble text
            full_text = "".join(
                c["choices"][0]["delta"]["content"] for c in content_chunks
            )
            assert "interfere" in full_text.lower() or "hello" in full_text.lower()
