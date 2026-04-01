"""OpenAI-compatible request/response types for interfer."""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from typing import Any


@dataclass
class ChatMessage:
    """A single message in a chat conversation."""

    role: str
    content: str


@dataclass
class ChatCompletionRequest:
    """OpenAI-compatible chat completion request."""

    model: str
    messages: list[ChatMessage]
    stream: bool = True
    max_tokens: int = 512
    temperature: float = 0.7
    top_p: float = 0.95
    stop: list[str] | None = None


@dataclass
class ChatCompletionChunk:
    """OpenAI-compatible streaming chunk response."""

    id: str = field(default_factory=lambda: f"chatcmpl-{uuid.uuid4().hex[:12]}")
    object: str = "chat.completion.chunk"
    created: int = field(default_factory=lambda: int(time.time()))
    model: str = ""

    def to_delta_dict(
        self,
        content: str = "",
        finish_reason: str | None = None,
    ) -> dict[str, Any]:
        """Return an OpenAI-format SSE delta dictionary."""
        delta: dict[str, str] = {}
        if content:
            delta["content"] = content

        choice: dict[str, Any] = {
            "index": 0,
            "delta": delta,
            "finish_reason": finish_reason,
        }

        return {
            "id": self.id,
            "object": self.object,
            "created": self.created,
            "model": self.model,
            "choices": [choice],
        }
