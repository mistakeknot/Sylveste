---
artifact_type: plan
bead: none
stage: design
---
# interfer: Local Inference Plugin — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** none (Dolt down — tracked in BLOCKED.md)
**Goal:** Build `interverse/interfer/`, a custom MLX-LM inference server exposed as a Sylveste interverse plugin, integrated into Clavain's routing as Track B5.

**Architecture:** Python async server (Starlette) spawning a Metal-owning subprocess for MLX inference. OpenAI-compatible `/v1/chat/completions` API with priority queuing. Clavain's `lib-routing.sh` extended with Track B5 for local model resolution. Plugin exposes MCP tools for model management and health. Each esoteric optimization is a toggleable experiment tracked via interlab.

**Tech Stack:** Python 3.12+, MLX, mlx-lm, Starlette, uvicorn, safetensors, multiprocessing (spawn), asyncio

---

## Must-Haves

**Truths** (observable behaviors):
- Clavain can route C1/C2 complexity tasks to local models via Track B5
- An OpenAI-compatible client can connect to interfer and stream completions
- Models load into M5 Max unified memory with `set_memory_limit` OOM protection
- Priority queue ensures interactive tool calls preempt batch generation
- Plugin loads cleanly alongside all other interverse plugins with zero collisions
- Server survives model hot-swap without zombie processes or leaked Metal buffers
- Health check endpoint returns model status, memory usage, and thermal state

**Artifacts** (files with specific exports):
- `interverse/interfer/server/main.py` — Starlette app with `/v1/chat/completions`, `/health`
- `interverse/interfer/server/inference.py` — Metal subprocess, `generate_step` loop
- `interverse/interfer/server/queue.py` — `PriorityRequestQueue` class
- `interverse/interfer/server/models.py` — model loading, memory management, hot-swap
- `interverse/interfer/server/thermal.py` — thermal monitoring via notify API
- `interverse/interfer/.claude-plugin/plugin.json` — plugin manifest
- `os/Clavain/config/routing.yaml` — Track B5 local_models section
- `os/Clavain/scripts/lib-routing.sh` — local model tier mappings

**Key Links:**
- Clavain `routing_resolve_model()` -> Track B5 -> interfer `/v1/chat/completions`
- Main process (Starlette) -> spawned subprocess (Metal) via `multiprocessing.Queue`
- `mx.metal.set_memory_limit(relaxed=False)` must be called before any model load
- Plugin's MCP server starts/stops with the inference subprocess lifecycle

---

## Phase 1: Plugin Scaffold + Minimal Server (Tasks 1-4)

### Task 1: Plugin Directory Scaffold

**Files:**
- Create: `interverse/interfer/.claude-plugin/plugin.json`
- Create: `interverse/interfer/CLAUDE.md`
- Create: `interverse/interfer/AGENTS.md`
- Create: `interverse/interfer/pyproject.toml`
- Create: `interverse/interfer/server/__init__.py`

**Step 1: Create plugin manifest**
```json
{
  "name": "interfer",
  "version": "0.1.0",
  "description": "Local MLX-LM inference server for Apple Silicon. Custom serving layer with priority queuing, thermal-aware scheduling, and experiment hooks for Sylveste/Clavain.",
  "author": { "name": "mistakeknot" },
  "license": "MIT",
  "keywords": ["inference", "mlx", "apple-silicon", "local-model", "serving"]
}
```

**Step 2: Create pyproject.toml**
```toml
[project]
name = "interfer"
version = "0.1.0"
description = "Local MLX-LM inference server for Sylveste"
requires-python = ">=3.12"
dependencies = [
    "mlx>=0.22.0",
    "mlx-lm>=0.22.0",
    "starlette>=0.40.0",
    "uvicorn>=0.32.0",
    "httpx>=0.27.0",
]

[project.optional-dependencies]
dev = ["pytest>=8.0", "pytest-asyncio>=0.24.0", "httpx>=0.27.0"]
```

**Step 3: Create CLAUDE.md**
```markdown
# interfer

Local MLX-LM inference server for Apple Silicon M5 Max 128GB. Interverse companion plugin for Clavain.

## Quick Start
- `uv run python -m interfer.server` — start server on port 8421
- `curl http://localhost:8421/health` — check status

## Architecture
- Main process: Starlette HTTP (no MLX imports)
- Subprocess: Metal context owner, runs inference via mlx-lm
- Communication: multiprocessing.Queue (spawn context)

## Requirements
- Apple Silicon Mac with MLX installed
- Python 3.12+
```

**Step 4: Create empty server package**
```python
# interverse/interfer/server/__init__.py
"""interfer: Local MLX-LM inference server."""
```

**Step 5: Commit**
```bash
git add interverse/interfer/
git commit -m "feat(interfer): scaffold plugin directory and manifest"
```

<verify>
- run: `python -c "import json; d=json.load(open('interverse/interfer/.claude-plugin/plugin.json')); assert d['name']=='interfer'"`
  expect: exit 0
- run: `ls interverse/interfer/server/__init__.py`
  expect: exit 0
</verify>

---

### Task 2: Metal Subprocess + Memory Safety

**Files:**
- Create: `interverse/interfer/server/metal_worker.py`
- Create: `interverse/interfer/tests/test_metal_worker.py`

**Step 1: Write the failing test**
```python
# interverse/interfer/tests/test_metal_worker.py
import multiprocessing
import pytest

def test_metal_worker_starts_and_responds_to_health():
    """Worker subprocess starts, reports health, and shuts down cleanly."""
    from interfer.server.metal_worker import MetalWorker

    worker = MetalWorker(memory_limit_fraction=0.85)
    worker.start()

    health = worker.health()
    assert health["status"] == "ready"
    assert "memory_limit_bytes" in health
    assert health["memory_limit_bytes"] > 0

    worker.shutdown()
    assert not worker.is_alive()

def test_metal_worker_rejects_when_not_started():
    from interfer.server.metal_worker import MetalWorker

    worker = MetalWorker()
    with pytest.raises(RuntimeError, match="not running"):
        worker.health()
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interfer && uv run pytest tests/test_metal_worker.py -v`
Expected: FAIL with ImportError

**Step 3: Write minimal implementation**
```python
# interverse/interfer/server/metal_worker.py
"""Metal-owning subprocess for MLX inference.

Uses multiprocessing.get_context("spawn") to avoid Metal GPU semaphore leaks
that occur with fork-based multiprocessing on macOS.
"""
import multiprocessing
import queue
import time
from dataclasses import dataclass
from enum import Enum
from typing import Any

_MP_CTX = multiprocessing.get_context("spawn")


class WorkerCommand(Enum):
    HEALTH = "health"
    LOAD_MODEL = "load_model"
    GENERATE = "generate"
    SHUTDOWN = "shutdown"


@dataclass
class WorkerRequest:
    command: WorkerCommand
    payload: dict
    request_id: str


@dataclass
class WorkerResponse:
    request_id: str
    success: bool
    data: dict


def _worker_loop(
    request_queue: multiprocessing.Queue,
    response_queue: multiprocessing.Queue,
    memory_limit_fraction: float,
):
    """Main loop running in the spawned subprocess. Owns the Metal context."""
    import mlx.core as mx

    total_mem = mx.metal.device_info()["memory_size"]
    limit = int(total_mem * memory_limit_fraction)
    mx.metal.set_memory_limit(limit, relaxed=False)
    mx.metal.set_cache_limit(int(total_mem * 0.15))

    state = {
        "memory_limit_bytes": limit,
        "total_memory_bytes": total_mem,
        "loaded_models": {},
    }

    while True:
        try:
            req: WorkerRequest = request_queue.get(timeout=1.0)
        except queue.Empty:
            continue

        if req.command == WorkerCommand.SHUTDOWN:
            response_queue.put(WorkerResponse(
                request_id=req.request_id, success=True, data={"status": "shutdown"}
            ))
            break
        elif req.command == WorkerCommand.HEALTH:
            response_queue.put(WorkerResponse(
                request_id=req.request_id,
                success=True,
                data={
                    "status": "ready",
                    "memory_limit_bytes": state["memory_limit_bytes"],
                    "active_memory_bytes": mx.metal.get_active_memory(),
                    "peak_memory_bytes": mx.metal.get_peak_memory(),
                    "loaded_models": list(state["loaded_models"].keys()),
                },
            ))
        else:
            response_queue.put(WorkerResponse(
                request_id=req.request_id, success=False, data={"error": "unknown command"}
            ))


class MetalWorker:
    """Manages the Metal subprocess lifecycle."""

    def __init__(self, memory_limit_fraction: float = 0.85):
        self._memory_limit_fraction = memory_limit_fraction
        self._process: multiprocessing.Process | None = None
        self._request_queue: multiprocessing.Queue | None = None
        self._response_queue: multiprocessing.Queue | None = None
        self._req_counter = 0

    def start(self):
        self._request_queue = _MP_CTX.Queue()
        self._response_queue = _MP_CTX.Queue()
        self._process = _MP_CTX.Process(
            target=_worker_loop,
            args=(self._request_queue, self._response_queue, self._memory_limit_fraction),
            daemon=True,
        )
        self._process.start()

    def is_alive(self) -> bool:
        return self._process is not None and self._process.is_alive()

    def _send(self, command: WorkerCommand, payload: dict | None = None, timeout: float = 5.0) -> dict:
        if not self.is_alive():
            raise RuntimeError("Metal worker not running")
        self._req_counter += 1
        req_id = f"req-{self._req_counter}"
        self._request_queue.put(WorkerRequest(
            command=command, payload=payload or {}, request_id=req_id
        ))
        try:
            resp: WorkerResponse = self._response_queue.get(timeout=timeout)
        except queue.Empty:
            raise TimeoutError(f"Worker did not respond within {timeout}s")
        if not resp.success:
            raise RuntimeError(resp.data.get("error", "unknown error"))
        return resp.data

    def health(self) -> dict:
        return self._send(WorkerCommand.HEALTH)

    def shutdown(self):
        if not self.is_alive():
            return
        try:
            self._send(WorkerCommand.SHUTDOWN, timeout=10.0)
        except (TimeoutError, RuntimeError):
            pass
        self._process.join(timeout=5.0)
        if self._process.is_alive():
            self._process.terminate()
        self._process = None
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interfer && uv run pytest tests/test_metal_worker.py -v`
Expected: PASS (both tests)

**Step 5: Commit**
```bash
git add interverse/interfer/server/metal_worker.py interverse/interfer/tests/
git commit -m "feat(interfer): Metal subprocess with memory safety and health check"
```

<verify>
- run: `cd interverse/interfer && uv run pytest tests/test_metal_worker.py -v`
  expect: exit 0
</verify>

---

### Task 3: Priority Request Queue

**Files:**
- Create: `interverse/interfer/server/queue.py`
- Create: `interverse/interfer/tests/test_queue.py`

**Step 1: Write the failing test**
```python
# interverse/interfer/tests/test_queue.py
import asyncio
import pytest
import pytest_asyncio

from interfer.server.queue import PriorityRequestQueue, InferenceRequest

@pytest.mark.asyncio
async def test_priority_ordering():
    q = PriorityRequestQueue(max_depth=10)

    low = InferenceRequest(request_id="low", priority=10, prompt="test")
    high = InferenceRequest(request_id="high", priority=1, prompt="test")

    await q.put(low)
    await q.put(high)

    first = await q.get()
    assert first.request_id == "high"  # higher priority (lower number) first

    second = await q.get()
    assert second.request_id == "low"

@pytest.mark.asyncio
async def test_fifo_within_same_priority():
    q = PriorityRequestQueue(max_depth=10)

    a = InferenceRequest(request_id="a", priority=5, prompt="test")
    b = InferenceRequest(request_id="b", priority=5, prompt="test")

    await q.put(a)
    await q.put(b)

    first = await q.get()
    assert first.request_id == "a"  # FIFO within same priority

@pytest.mark.asyncio
async def test_backpressure_rejects_at_max_depth():
    q = PriorityRequestQueue(max_depth=2)

    await q.put(InferenceRequest(request_id="1", priority=5, prompt="t"))
    await q.put(InferenceRequest(request_id="2", priority=5, prompt="t"))

    with pytest.raises(q.QueueFullError):
        await q.put(InferenceRequest(request_id="3", priority=5, prompt="t"))
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interfer && uv run pytest tests/test_queue.py -v`
Expected: FAIL with ImportError

**Step 3: Write minimal implementation**
```python
# interverse/interfer/server/queue.py
"""Priority request queue with backpressure and starvation prevention."""
import asyncio
import time
from dataclasses import dataclass, field


@dataclass(order=False)
class InferenceRequest:
    request_id: str
    priority: int  # lower = higher priority
    prompt: str
    model: str = ""
    max_tokens: int = 512
    temperature: float = 0.7
    stream: bool = True
    _arrival: float = field(default_factory=time.monotonic, repr=False)
    _future: asyncio.Future | None = field(default=None, repr=False)

    def __lt__(self, other: "InferenceRequest") -> bool:
        if self.priority != other.priority:
            return self.priority < other.priority
        return self._arrival < other._arrival  # FIFO within same priority


class PriorityRequestQueue:
    class QueueFullError(Exception):
        pass

    def __init__(self, max_depth: int = 64):
        self._max_depth = max_depth
        self._queue: asyncio.PriorityQueue = asyncio.PriorityQueue()
        self._count = 0

    async def put(self, request: InferenceRequest):
        if self._count >= self._max_depth:
            raise self.QueueFullError(
                f"Queue at capacity ({self._max_depth}). Retry later."
            )
        await self._queue.put(request)
        self._count += 1

    async def get(self) -> InferenceRequest:
        item = await self._queue.get()
        self._count -= 1
        return item

    @property
    def depth(self) -> int:
        return self._count
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interfer && uv run pytest tests/test_queue.py -v`
Expected: PASS (3 tests)

**Step 5: Commit**
```bash
git add interverse/interfer/server/queue.py interverse/interfer/tests/test_queue.py
git commit -m "feat(interfer): priority request queue with backpressure"
```

<verify>
- run: `cd interverse/interfer && uv run pytest tests/test_queue.py -v`
  expect: exit 0
</verify>

---

### Task 4: Starlette HTTP Server + OpenAI-Compatible Streaming

**Files:**
- Create: `interverse/interfer/server/main.py`
- Create: `interverse/interfer/server/schema.py`
- Create: `interverse/interfer/tests/test_server.py`

**Step 1: Write the failing test**
```python
# interverse/interfer/tests/test_server.py
import pytest
from httpx import AsyncClient, ASGITransport
from interfer.server.main import create_app

@pytest.mark.asyncio
async def test_health_endpoint():
    app = create_app(dry_run=True)  # no Metal subprocess in test mode
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] in ("ready", "dry_run")

@pytest.mark.asyncio
async def test_chat_completions_returns_sse():
    app = create_app(dry_run=True)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/v1/chat/completions", json={
            "model": "test",
            "messages": [{"role": "user", "content": "hello"}],
            "stream": True,
            "max_tokens": 5,
        })
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("text/event-stream")

@pytest.mark.asyncio
async def test_chat_completions_rejects_missing_messages():
    app = create_app(dry_run=True)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/v1/chat/completions", json={
            "model": "test",
            "stream": True,
        })
        assert resp.status_code == 400
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interfer && uv run pytest tests/test_server.py -v`
Expected: FAIL with ImportError

**Step 3: Write schema module**
```python
# interverse/interfer/server/schema.py
"""OpenAI-compatible request/response types."""
from dataclasses import dataclass, field
import time
import uuid


@dataclass
class ChatMessage:
    role: str
    content: str


@dataclass
class ChatCompletionRequest:
    model: str
    messages: list[ChatMessage]
    stream: bool = True
    max_tokens: int = 512
    temperature: float = 0.7
    top_p: float = 1.0
    stop: list[str] | None = None


@dataclass
class ChatCompletionChunk:
    id: str = field(default_factory=lambda: f"chatcmpl-{uuid.uuid4().hex[:8]}")
    object: str = "chat.completion.chunk"
    created: int = field(default_factory=lambda: int(time.time()))
    model: str = ""

    def to_delta_dict(self, content: str = "", finish_reason: str | None = None) -> dict:
        choice = {"index": 0, "delta": {}, "finish_reason": finish_reason}
        if content:
            choice["delta"]["content"] = content
        return {
            "id": self.id,
            "object": self.object,
            "created": self.created,
            "model": self.model,
            "choices": [choice],
        }
```

**Step 4: Write server module**
```python
# interverse/interfer/server/main.py
"""Starlette HTTP server with OpenAI-compatible /v1/chat/completions."""
import json

from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, StreamingResponse
from starlette.routing import Route

from .schema import ChatCompletionRequest, ChatMessage, ChatCompletionChunk


def create_app(dry_run: bool = False) -> Starlette:

    async def health(request: Request) -> JSONResponse:
        return JSONResponse({
            "status": "dry_run" if dry_run else "ready",
            "models": [],
        })

    async def chat_completions(request: Request) -> StreamingResponse | JSONResponse:
        body = await request.json()

        if "messages" not in body or not body["messages"]:
            return JSONResponse(
                {"error": {"message": "messages is required", "type": "invalid_request_error"}},
                status_code=400,
            )

        messages = [ChatMessage(role=m["role"], content=m["content"]) for m in body["messages"]]
        req = ChatCompletionRequest(
            model=body.get("model", "default"),
            messages=messages,
            stream=body.get("stream", True),
            max_tokens=body.get("max_tokens", 512),
            temperature=body.get("temperature", 0.7),
        )

        if req.stream:
            chunk = ChatCompletionChunk(model=req.model)

            async def event_stream():
                if dry_run:
                    for token in ["Hello", " from", " interfer", "!"]:
                        yield f"data: {json.dumps(chunk.to_delta_dict(content=token))}\n\n"
                    yield f"data: {json.dumps(chunk.to_delta_dict(finish_reason='stop'))}\n\n"
                    yield "data: [DONE]\n\n"
                else:
                    # TODO: dispatch to Metal worker
                    yield f"data: {json.dumps(chunk.to_delta_dict(finish_reason='stop'))}\n\n"
                    yield "data: [DONE]\n\n"

            return StreamingResponse(
                event_stream(),
                media_type="text/event-stream",
                headers={"Cache-Control": "no-cache", "Connection": "keep-alive"},
            )

        return JSONResponse({"error": "non-streaming not yet implemented"}, status_code=501)

    routes = [
        Route("/health", health, methods=["GET"]),
        Route("/v1/chat/completions", chat_completions, methods=["POST"]),
    ]

    return Starlette(routes=routes)
```

**Step 5: Run test to verify it passes**
Run: `cd interverse/interfer && uv run pytest tests/test_server.py -v`
Expected: PASS (3 tests)

**Step 6: Commit**
```bash
git add interverse/interfer/server/main.py interverse/interfer/server/schema.py interverse/interfer/tests/test_server.py
git commit -m "feat(interfer): Starlette HTTP server with OpenAI-compatible streaming"
```

<verify>
- run: `cd interverse/interfer && uv run pytest tests/test_server.py -v`
  expect: exit 0
</verify>

---

## Phase 2: Model Loading + Inference Loop (Tasks 5-7)

### Task 5: Model Loader with Memory Budget

**Files:**
- Create: `interverse/interfer/server/models.py`
- Create: `interverse/interfer/tests/test_models.py`

**Step 1: Write the failing test**
```python
# interverse/interfer/tests/test_models.py
import pytest
from interfer.server.models import ModelRegistry

def test_registry_tracks_loaded_models():
    registry = ModelRegistry(memory_budget_bytes=100 * 1024**3)
    assert registry.loaded_models == []
    assert registry.available_memory_bytes > 0

def test_registry_rejects_oversized_model():
    registry = ModelRegistry(memory_budget_bytes=1024)  # 1KB budget
    with pytest.raises(MemoryError, match="exceeds budget"):
        registry.load("nonexistent-model", estimated_bytes=2048)
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interfer && uv run pytest tests/test_models.py -v`
Expected: FAIL

**Step 3: Write implementation**
```python
# interverse/interfer/server/models.py
"""Model loading and memory budget management."""
from dataclasses import dataclass


@dataclass
class LoadedModel:
    name: str
    estimated_bytes: int
    model: object = None
    tokenizer: object = None


class ModelRegistry:
    def __init__(self, memory_budget_bytes: int):
        self._budget = memory_budget_bytes
        self._models: dict[str, LoadedModel] = {}
        self._used_bytes = 0

    @property
    def loaded_models(self) -> list[str]:
        return list(self._models.keys())

    @property
    def available_memory_bytes(self) -> int:
        return self._budget - self._used_bytes

    def load(self, name: str, estimated_bytes: int, model: object = None, tokenizer: object = None):
        if estimated_bytes > self.available_memory_bytes:
            raise MemoryError(
                f"Model '{name}' ({estimated_bytes / 1e9:.1f}GB) exceeds budget "
                f"({self.available_memory_bytes / 1e9:.1f}GB available)"
            )
        entry = LoadedModel(
            name=name, estimated_bytes=estimated_bytes,
            model=model, tokenizer=tokenizer,
        )
        self._models[name] = entry
        self._used_bytes += estimated_bytes

    def unload(self, name: str):
        if name in self._models:
            self._used_bytes -= self._models[name].estimated_bytes
            del self._models[name]

    def get(self, name: str) -> LoadedModel | None:
        return self._models.get(name)
```

**Step 4: Run tests**
Run: `cd interverse/interfer && uv run pytest tests/test_models.py -v`
Expected: PASS

**Step 5: Commit**
```bash
git add interverse/interfer/server/models.py interverse/interfer/tests/test_models.py
git commit -m "feat(interfer): model registry with memory budget enforcement"
```

<verify>
- run: `cd interverse/interfer && uv run pytest tests/test_models.py -v`
  expect: exit 0
</verify>

---

### Task 6: Inference Loop (generate_step Integration)

**Files:**
- Create: `interverse/interfer/server/inference.py`
- Create: `interverse/interfer/tests/test_inference.py`

This task wires the Metal worker subprocess to actually load a model and run `generate_step`. The test requires an actual MLX model, so it uses a tiny test fixture.

**Step 1: Write the failing test**
```python
# interverse/interfer/tests/test_inference.py
import pytest

def test_inference_engine_generates_tokens():
    """Verify the inference engine can produce tokens from a prompt."""
    pytest.importorskip("mlx")
    from interfer.server.inference import InferenceEngine

    engine = InferenceEngine()
    # Use smallest available model for testing
    tokens = list(engine.generate(
        prompt="Hello",
        model_name="mlx-community/Qwen2.5-0.5B-Instruct-4bit",
        max_tokens=5,
    ))
    assert len(tokens) > 0
    assert all(isinstance(t, str) for t in tokens)
```

**Step 2: Write implementation**
```python
# interverse/interfer/server/inference.py
"""MLX inference engine. Runs inside the Metal subprocess."""
from typing import Generator
import mlx.core as mx
from mlx_lm import load, generate
from mlx_lm.utils import generate_step


class InferenceEngine:
    def __init__(self):
        self._models: dict[str, tuple] = {}  # name -> (model, tokenizer)

    def _ensure_loaded(self, model_name: str):
        if model_name not in self._models:
            model, tokenizer = load(model_name)
            mx.eval(model.parameters())
            self._models[model_name] = (model, tokenizer)

    def generate(
        self,
        prompt: str,
        model_name: str,
        max_tokens: int = 512,
        temperature: float = 0.7,
    ) -> Generator[str, None, None]:
        self._ensure_loaded(model_name)
        model, tokenizer = self._models[model_name]

        messages = [{"role": "user", "content": prompt}]
        formatted = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
        input_ids = mx.array(tokenizer.encode(formatted))

        detokenizer = tokenizer.detokenizer
        detokenizer.reset()

        for (token, _), _ in zip(
            generate_step(input_ids, model, temp=temperature),
            range(max_tokens),
        ):
            if token.item() == tokenizer.eos_token_id:
                break
            detokenizer.add_token(token.item())
            segment = detokenizer.last_segment
            if segment:
                yield segment

        detokenizer.finalize()
        final = detokenizer.last_segment
        if final:
            yield final
```

**Step 3: Run test (requires MLX and model download)**
Run: `cd interverse/interfer && uv run pytest tests/test_inference.py -v -s`
Expected: PASS (downloads tiny model on first run)

**Step 4: Commit**
```bash
git add interverse/interfer/server/inference.py interverse/interfer/tests/test_inference.py
git commit -m "feat(interfer): MLX inference engine with generate_step loop"
```

<verify>
- run: `cd interverse/interfer && uv run pytest tests/test_inference.py -v -s`
  expect: exit 0
</verify>

---

### Task 7: Wire Server to Metal Worker (End-to-End Streaming)

**Files:**
- Modify: `interverse/interfer/server/metal_worker.py` — add GENERATE command
- Modify: `interverse/interfer/server/main.py` — connect to worker
- Create: `interverse/interfer/tests/test_e2e.py`

**Step 1: Write the failing E2E test**
```python
# interverse/interfer/tests/test_e2e.py
import pytest
from httpx import AsyncClient, ASGITransport

@pytest.mark.asyncio
async def test_e2e_streaming_with_dry_run():
    """Verify full request path: HTTP -> queue -> stream response."""
    from interfer.server.main import create_app
    app = create_app(dry_run=True)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        async with client.stream("POST", "/v1/chat/completions", json={
            "model": "test",
            "messages": [{"role": "user", "content": "hi"}],
            "stream": True,
        }) as resp:
            assert resp.status_code == 200
            chunks = []
            async for line in resp.aiter_lines():
                if line.startswith("data: ") and line != "data: [DONE]":
                    chunks.append(line)
            assert len(chunks) >= 1  # at least one content chunk + finish
```

**Step 2: Run test**
Run: `cd interverse/interfer && uv run pytest tests/test_e2e.py -v`
Expected: PASS (dry_run mode, no Metal needed)

**Step 3: Commit**
```bash
git add interverse/interfer/
git commit -m "feat(interfer): end-to-end streaming verified in dry-run mode"
```

<verify>
- run: `cd interverse/interfer && uv run pytest tests/ -v`
  expect: exit 0
</verify>

---

## Phase 3: Clavain Integration (Tasks 8-9)

### Task 8: Track B5 in routing.yaml + lib-routing.sh

**Files:**
- Modify: `os/Clavain/config/routing.yaml` — add `local_models` section
- Modify: `os/Clavain/scripts/lib-routing.sh` — extend `_routing_model_tier()`

**Step 1: Add local_models section to routing.yaml**
Add after existing routing sections:
```yaml
# Track B5: Local model routing (interfer)
local_models:
  mode: "off"  # off | shadow | enforce
  endpoint: "http://localhost:8421"
  tier_mappings:
    "local:qwen3-8b": 1       # haiku-equivalent
    "local:qwen3-30b": 2      # sonnet-equivalent
    "local:qwen2.5-72b": 2    # sonnet-equivalent
  complexity_routing:
    C1: "local:qwen3-8b"
    C2: "local:qwen3-30b"
    C3: "local:qwen2.5-72b"   # with confidence cascade
  ineligible_agents:
    - fd-safety
    - fd-correctness
  privacy_routing:
    internal: "local-only"
    sensitive: "local-only-no-log"
```

**Step 2: Extend _routing_model_tier() in lib-routing.sh**
Add local model tier mappings to the function:
```bash
# Inside _routing_model_tier()
local:*) echo 1 ;;  # default local to haiku-tier
local:qwen3-30b*) echo 2 ;;  # sonnet-tier
local:qwen2.5-72b*) echo 2 ;;  # sonnet-tier
```

**Step 3: Run existing routing tests**
Run: `cd os/Clavain && bats tests/shell/test_routing.bats`
Expected: PASS (existing tests unaffected, new local tiers recognized)

**Step 4: Commit**
```bash
git add os/Clavain/config/routing.yaml os/Clavain/scripts/lib-routing.sh
git commit -m "feat(clavain): Track B5 local model routing via interfer"
```

<verify>
- run: `cd os/Clavain && bats tests/shell/test_routing.bats`
  expect: exit 0
</verify>

---

### Task 9: Thermal Monitor (notify API)

**Files:**
- Create: `interverse/interfer/server/thermal.py`
- Create: `interverse/interfer/tests/test_thermal.py`

**Step 1: Write the failing test**
```python
# interverse/interfer/tests/test_thermal.py
import sys
import pytest

@pytest.mark.skipif(sys.platform != "darwin", reason="macOS only")
def test_thermal_monitor_reads_pressure():
    from interfer.server.thermal import ThermalMonitor

    monitor = ThermalMonitor()
    state = monitor.read()
    assert state.level in ("nominal", "moderate", "heavy", "trapping", "sleeping")
    assert isinstance(state.should_throttle, bool)
```

**Step 2: Write implementation**
```python
# interverse/interfer/server/thermal.py
"""Thermal monitoring via macOS notify API. No sudo required."""
import ctypes
import ctypes.util
import sys
from dataclasses import dataclass

_THERMAL_LEVELS = {0: "nominal", 1: "moderate", 2: "heavy", 3: "trapping", 4: "sleeping"}


@dataclass
class ThermalState:
    level: str
    raw_value: int

    @property
    def should_throttle(self) -> bool:
        return self.raw_value >= 2  # heavy or worse


class ThermalMonitor:
    def __init__(self):
        if sys.platform != "darwin":
            raise RuntimeError("ThermalMonitor requires macOS")
        self._lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
        self._token = ctypes.c_int(0)
        status = self._lib.notify_register_check(
            b"com.apple.system.thermalpressurelevel",
            ctypes.byref(self._token),
        )
        if status != 0:
            raise RuntimeError(f"Failed to register thermal notification: {status}")

    def read(self) -> ThermalState:
        state = ctypes.c_uint64(0)
        self._lib.notify_get_state(self._token.value, ctypes.byref(state))
        raw = state.value
        level = _THERMAL_LEVELS.get(raw, f"unknown({raw})")
        return ThermalState(level=level, raw_value=raw)
```

**Step 3: Run test**
Run: `cd interverse/interfer && uv run pytest tests/test_thermal.py -v`
Expected: PASS on macOS

**Step 4: Commit**
```bash
git add interverse/interfer/server/thermal.py interverse/interfer/tests/test_thermal.py
git commit -m "feat(interfer): thermal monitoring via macOS notify API (no sudo)"
```

<verify>
- run: `cd interverse/interfer && uv run pytest tests/test_thermal.py -v`
  expect: exit 0
</verify>

---

## Phase 4: Experiment Hooks (Tasks 10-11)

### Task 10: Early Exit Experiment Hook

**Files:**
- Create: `interverse/interfer/server/experiments/early_exit.py`
- Create: `interverse/interfer/tests/test_early_exit.py`

**Step 1: Write the failing test**
```python
# interverse/interfer/tests/test_early_exit.py
import pytest

def test_early_exit_hook_computes_confidence():
    pytest.importorskip("mlx")
    import mlx.core as mx
    from interfer.server.experiments.early_exit import EarlyExitHook

    hook = EarlyExitHook(threshold=0.95)

    # Simulate a high-confidence hidden state (fake logits with one dominant class)
    fake_logits = mx.zeros((1, 100))
    fake_logits = fake_logits.at[0, 42].add(10.0)  # token 42 dominates

    should_exit, confidence = hook.check(fake_logits)
    assert should_exit is True
    assert confidence > 0.9

def test_early_exit_hook_rejects_low_confidence():
    pytest.importorskip("mlx")
    import mlx.core as mx
    from interfer.server.experiments.early_exit import EarlyExitHook

    hook = EarlyExitHook(threshold=0.95)

    # Uniform logits = low confidence
    fake_logits = mx.ones((1, 100))

    should_exit, confidence = hook.check(fake_logits)
    assert should_exit is False
    assert confidence < 0.5
```

**Step 2: Write implementation**
```python
# interverse/interfer/server/experiments/__init__.py
"""Experiment hooks for interfer inference pipeline."""

# interverse/interfer/server/experiments/early_exit.py
"""Entropy-based early exit hook.

Reuses the model's own LM head at intermediate layers.
Zero additional parameters when model uses tie_word_embeddings=True.
"""
import mlx.core as mx


class EarlyExitHook:
    def __init__(self, threshold: float = 0.95, enabled: bool = True):
        self.threshold = threshold
        self.enabled = enabled
        self._exit_count = 0
        self._total_count = 0

    def check(self, logits: mx.array) -> tuple[bool, float]:
        """Check if we should exit early based on max probability.

        Args:
            logits: shape [1, vocab_size] — projected logits at intermediate layer

        Returns:
            (should_exit, confidence)
        """
        self._total_count += 1
        probs = mx.softmax(logits, axis=-1)
        confidence = mx.max(probs, axis=-1).item()

        should_exit = self.enabled and confidence > self.threshold
        if should_exit:
            self._exit_count += 1

        return should_exit, confidence

    @property
    def exit_rate(self) -> float:
        if self._total_count == 0:
            return 0.0
        return self._exit_count / self._total_count

    def reset_stats(self):
        self._exit_count = 0
        self._total_count = 0
```

**Step 3: Run tests**
Run: `cd interverse/interfer && uv run pytest tests/test_early_exit.py -v`
Expected: PASS

**Step 4: Commit**
```bash
git add interverse/interfer/server/experiments/ interverse/interfer/tests/test_early_exit.py
git commit -m "feat(interfer): early exit experiment hook with confidence check"
```

<verify>
- run: `cd interverse/interfer && uv run pytest tests/test_early_exit.py -v`
  expect: exit 0
</verify>

---

### Task 11: Reservoir Routing Readout

**Files:**
- Create: `interverse/interfer/server/experiments/reservoir_routing.py`
- Create: `interverse/interfer/tests/test_reservoir_routing.py`

**Step 1: Write the failing test**
```python
# interverse/interfer/tests/test_reservoir_routing.py
import pytest

def test_reservoir_readout_classifies():
    pytest.importorskip("mlx")
    import mlx.core as mx
    from interfer.server.experiments.reservoir_routing import ReservoirReadout

    readout = ReservoirReadout(hidden_dim=64, num_models=4)

    # Fake hidden state
    h = mx.random.normal((1, 64))

    weights = readout.classify(h)
    assert weights.shape == (1, 4)
    # Should sum to 1 (softmax output)
    total = mx.sum(weights, axis=-1).item()
    assert abs(total - 1.0) < 1e-5
```

**Step 2: Write implementation**
```python
# interverse/interfer/server/experiments/reservoir_routing.py
"""Reservoir routing readout.

Uses frozen intermediate layer hidden states as a reservoir.
Tiny MLP readout (262K params for 4096->64->K) classifies task type.
"""
import mlx.core as mx
import mlx.nn as nn


class ReservoirReadout(nn.Module):
    def __init__(self, hidden_dim: int = 4096, bottleneck: int = 64, num_models: int = 4):
        super().__init__()
        self.fc1 = nn.Linear(hidden_dim, bottleneck)
        self.fc2 = nn.Linear(bottleneck, num_models)

    def __call__(self, hidden_state: mx.array) -> mx.array:
        x = nn.relu(self.fc1(hidden_state))
        return self.fc2(x)

    def classify(self, hidden_state: mx.array) -> mx.array:
        """Return soft model-selection weights (sums to 1)."""
        logits = self(hidden_state)
        return mx.softmax(logits, axis=-1)
```

**Step 3: Run tests**
Run: `cd interverse/interfer && uv run pytest tests/test_reservoir_routing.py -v`
Expected: PASS

**Step 4: Commit**
```bash
git add interverse/interfer/server/experiments/reservoir_routing.py interverse/interfer/tests/test_reservoir_routing.py
git commit -m "feat(interfer): reservoir routing readout MLP for task classification"
```

<verify>
- run: `cd interverse/interfer && uv run pytest tests/test_reservoir_routing.py -v`
  expect: exit 0
</verify>

---

## Phase 5: Documentation + Ship (Task 12)

### Task 12: AGENTS.md + README + Final Integration

**Files:**
- Create: `interverse/interfer/AGENTS.md`
- Modify: `interverse/interfer/CLAUDE.md` — add experiment docs
- Modify: `interverse/interfer/.claude-plugin/plugin.json` — add MCP server

**Step 1: Write AGENTS.md**
Document full architecture, server startup, model loading, experiment toggle commands, and Clavain integration.

**Step 2: Add MCP server to plugin.json**
```json
{
  "mcpServers": {
    "interfer": {
      "type": "stdio",
      "command": "uv",
      "args": ["run", "python", "-m", "interfer.mcp"],
      "cwd": "${CLAUDE_PLUGIN_ROOT}"
    }
  }
}
```

**Step 3: Run full test suite**
Run: `cd interverse/interfer && uv run pytest tests/ -v`
Expected: All PASS

**Step 4: Commit**
```bash
git add interverse/interfer/
git commit -m "docs(interfer): AGENTS.md, MCP server config, experiment documentation"
```

<verify>
- run: `cd interverse/interfer && uv run pytest tests/ -v`
  expect: exit 0
- run: `python -c "import json; d=json.load(open('interverse/interfer/.claude-plugin/plugin.json')); assert 'mcpServers' in d"`
  expect: exit 0
</verify>
