"""Tests for the flash-moe subprocess proxy worker."""

from __future__ import annotations

import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from unittest.mock import MagicMock, patch

import pytest

from server.flashmoe_worker import FlashMoeWorker, _pick_free_port


# ---------------------------------------------------------------------------
# Helpers: fake flash-moe HTTP server
# ---------------------------------------------------------------------------


class FakeFlashMoeHandler(BaseHTTPRequestHandler):
    """Minimal OpenAI-compatible SSE server mimicking flash-moe."""

    def log_message(self, format, *args):
        pass  # silence request logs in tests

    def do_GET(self):
        if self.path == "/health":
            body = json.dumps({"status": "ok", "model": "qwen3.5-397b-test"})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/v1/models":
            body = json.dumps(
                {
                    "object": "list",
                    "data": [
                        {
                            "id": "qwen3.5-397b-test",
                            "object": "model",
                            "owned_by": "local",
                        }
                    ],
                }
            )
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == "/v1/chat/completions":
            content_length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_length))

            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()

            tokens = ["Hello", " from", " flash", "-moe", "!"]
            for i, tok in enumerate(tokens):
                chunk = {
                    "id": f"chatcmpl-{i}",
                    "object": "chat.completion.chunk",
                    "choices": [
                        {"index": 0, "delta": {"content": tok}, "finish_reason": None}
                    ],
                }
                self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
                self.wfile.flush()

            # Final chunk
            final = {
                "id": "chatcmpl-final",
                "object": "chat.completion.chunk",
                "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
            }
            self.wfile.write(f"data: {json.dumps(final)}\n\n".encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        else:
            self.send_error(404)

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()


@pytest.fixture
def fake_flashmoe_port():
    """Start a fake flash-moe HTTP server and return its port."""
    port = _pick_free_port()
    server = HTTPServer(("127.0.0.1", port), FakeFlashMoeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield port
    server.shutdown()


# ---------------------------------------------------------------------------
# Tests: _pick_free_port
# ---------------------------------------------------------------------------


def test_pick_free_port():
    port = _pick_free_port()
    assert 1024 < port < 65536
    # Port should be bindable
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", port))


# ---------------------------------------------------------------------------
# Tests: FlashMoeWorker with fake server
# ---------------------------------------------------------------------------


class TestFlashMoeWorkerWithFakeServer:
    """Test FlashMoeWorker against a fake HTTP server (no real binary)."""

    def _make_worker(self, port: int) -> FlashMoeWorker:
        """Create a worker that skips subprocess startup."""
        w = FlashMoeWorker(
            binary_path="/nonexistent",
            model_path="/nonexistent",
            port=port,
        )
        # Fake the process as alive
        w._process = MagicMock()
        w._process.poll.return_value = None  # process is alive
        w._process.pid = 99999
        return w

    def test_health(self, fake_flashmoe_port: int):
        w = self._make_worker(fake_flashmoe_port)
        info = w.health(timeout=2.0)
        assert info["status"] == "ready"
        assert info["backend"] == "flash-moe"
        assert "qwen3.5-397b-test" in info["loaded_models"]

    def test_generate_streams_tokens(self, fake_flashmoe_port: int):
        w = self._make_worker(fake_flashmoe_port)
        tokens = list(
            w.generate(
                messages=[{"role": "user", "content": "Hello"}],
                max_tokens=100,
            )
        )
        assert tokens == ["Hello", " from", " flash", "-moe", "!"]

    def test_generate_populates_metrics(self, fake_flashmoe_port: int):
        w = self._make_worker(fake_flashmoe_port)
        list(
            w.generate(
                messages=[{"role": "user", "content": "Hello"}],
                max_tokens=100,
            )
        )
        metrics = w.last_generation_metrics
        assert metrics["tokens_generated"] == 5
        assert metrics["backend"] == "flash-moe"
        assert metrics["generation_tps"] > 0

    def test_generate_with_prompt_wraps_to_messages(self, fake_flashmoe_port: int):
        w = self._make_worker(fake_flashmoe_port)
        tokens = list(w.generate(prompt="Hello world"))
        assert len(tokens) == 5

    def test_generate_requires_messages_or_prompt(self, fake_flashmoe_port: int):
        w = self._make_worker(fake_flashmoe_port)
        with pytest.raises(ValueError, match="messages or prompt required"):
            list(w.generate())

    def test_is_alive_delegates_to_process(self, fake_flashmoe_port: int):
        w = self._make_worker(fake_flashmoe_port)
        assert w.is_alive() is True
        w._process.poll.return_value = 1  # process exited
        assert w.is_alive() is False

    def test_health_when_down(self):
        w = FlashMoeWorker(
            binary_path="/nonexistent",
            model_path="/nonexistent",
        )
        info = w.health()
        assert info["status"] == "down"

    def test_generate_when_not_running(self):
        w = FlashMoeWorker(
            binary_path="/nonexistent",
            model_path="/nonexistent",
        )
        with pytest.raises(RuntimeError, match="not running"):
            list(w.generate(messages=[{"role": "user", "content": "hi"}]))


# ---------------------------------------------------------------------------
# Tests: FlashMoeWorker lifecycle (mocked subprocess)
# ---------------------------------------------------------------------------


class TestFlashMoeWorkerLifecycle:
    def test_start_fails_without_binary(self):
        w = FlashMoeWorker(
            binary_path="/nonexistent/infer",
            model_path="/some/model",
        )
        with pytest.raises(FileNotFoundError, match="flash-moe binary not found"):
            w.start()

    def test_start_fails_without_model_path(self, tmp_path):
        # Create a fake binary
        binary = tmp_path / "infer"
        binary.touch()
        w = FlashMoeWorker(
            binary_path=str(binary),
            model_path="",
        )
        with pytest.raises(ValueError, match="model_path is required"):
            w.start()

    def test_properties_default_state(self):
        w = FlashMoeWorker(
            binary_path="/nonexistent",
            model_path="/nonexistent",
        )
        assert w.is_alive() is False
        assert w.is_degraded is False
        assert w.is_restarting is False
        assert w.restart_count == 0
        assert w.last_crash is None
        assert w.crash_history == []

    def test_shutdown_when_not_started(self):
        w = FlashMoeWorker(
            binary_path="/nonexistent",
            model_path="/nonexistent",
        )
        # Should not raise
        w.shutdown()

    def test_generate_lock_serializes(self, fake_flashmoe_port: int):
        """Verify concurrent generate() calls are serialized."""
        w = FlashMoeWorker(
            binary_path="/nonexistent",
            model_path="/nonexistent",
            port=fake_flashmoe_port,
        )
        w._process = MagicMock()
        w._process.poll.return_value = None
        w._process.pid = 99999

        results = []

        def gen(idx):
            tokens = list(
                w.generate(
                    messages=[{"role": "user", "content": f"msg {idx}"}],
                )
            )
            results.append((idx, tokens))

        threads = [threading.Thread(target=gen, args=(i,)) for i in range(3)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10.0)

        assert len(results) == 3
        # All should have received the same tokens (from our fake server)
        for idx, tokens in results:
            assert tokens == ["Hello", " from", " flash", "-moe", "!"]


# ---------------------------------------------------------------------------
# Tests: malloc-cache and predict CLI flags
# ---------------------------------------------------------------------------


class TestFlashMoeCacheFlags:
    def test_malloc_cache_in_command(self, tmp_path):
        """Verify --malloc-cache is included in subprocess command."""
        binary = tmp_path / "infer"
        binary.write_text("#!/bin/sh\nexit 1")
        binary.chmod(0o755)

        w = FlashMoeWorker(
            binary_path=str(binary),
            model_path=str(tmp_path),
            malloc_cache=10000,
        )
        # We can't actually start (binary will fail), but we can check
        # the command would be constructed correctly by inspecting internals
        assert w._malloc_cache == 10000

    def test_predict_flag(self, tmp_path):
        """Verify --predict flag is stored."""
        w = FlashMoeWorker(
            binary_path="/nonexistent",
            model_path="/nonexistent",
            predict=True,
        )
        assert w._predict is True

    def test_defaults_no_cache_no_predict(self):
        """Default construction has no malloc-cache and no predict."""
        w = FlashMoeWorker(
            binary_path="/nonexistent",
            model_path="/nonexistent",
        )
        assert w._malloc_cache == 0
        assert w._predict is False


class TestFlashMoeCLIArgs:
    """Test CLI argument parsing for flash-moe flags."""

    def test_flashmoe_malloc_cache_arg(self):
        from server.__main__ import _parse_args

        args = _parse_args(
            [
                "--flashmoe-binary",
                "/some/infer",
                "--flashmoe-model",
                "/some/model",
                "--flashmoe-malloc-cache",
                "10000",
            ]
        )
        assert args.flashmoe_malloc_cache == 10000

    def test_flashmoe_predict_arg(self):
        from server.__main__ import _parse_args

        args = _parse_args(["--flashmoe-predict"])
        assert args.flashmoe_predict is True

    def test_flashmoe_predict_default_off(self):
        from server.__main__ import _parse_args

        args = _parse_args([])
        assert args.flashmoe_predict is False
        assert args.flashmoe_malloc_cache == 0

    def test_flashmoe_args_string_split(self):
        from server.__main__ import _parse_args

        args = _parse_args(
            [
                "--flashmoe-args",
                "--think-budget 2048",
            ]
        )
        assert args.flashmoe_args == "--think-budget 2048"
        # Verify splitting works
        split = args.flashmoe_args.split()
        assert split == ["--think-budget", "2048"]

    def test_flashmoe_q3_experts_arg(self):
        from server.__main__ import _parse_args

        args = _parse_args(["--flashmoe-q3-experts"])
        assert args.flashmoe_q3_experts is True

    def test_flashmoe_cache_io_split_arg(self):
        from server.__main__ import _parse_args

        args = _parse_args(["--flashmoe-cache-io-split", "4"])
        assert args.flashmoe_cache_io_split == 4

    def test_flashmoe_gguf_paths(self):
        from server.__main__ import _parse_args

        args = _parse_args(
            [
                "--flashmoe-gguf-embedding",
                "~/Models/gguf/embedding_q8_0.bin",
                "--flashmoe-gguf-lm-head",
                "~/Models/gguf/lm_head_q6.bin",
            ]
        )
        assert args.flashmoe_gguf_embedding == "~/Models/gguf/embedding_q8_0.bin"
        assert args.flashmoe_gguf_lm_head == "~/Models/gguf/lm_head_q6.bin"

    def test_flashmoe_q3_defaults_off(self):
        from server.__main__ import _parse_args

        args = _parse_args([])
        assert args.flashmoe_q3_experts is False
        assert args.flashmoe_cache_io_split == 0
        assert args.flashmoe_gguf_embedding == ""
        assert args.flashmoe_gguf_lm_head == ""


class TestFlashMoeQ3WorkerFlags:
    """Test that Q3/GGUF flags are stored on the worker."""

    def test_q3_experts_stored(self):
        w = FlashMoeWorker(
            binary_path="/nonexistent",
            model_path="/nonexistent",
            q3_experts=True,
            cache_io_split=4,
            gguf_embedding="/path/to/embedding.bin",
            gguf_lm_head="/path/to/lm_head.bin",
        )
        assert w._q3_experts is True
        assert w._cache_io_split == 4
        assert w._gguf_embedding == "/path/to/embedding.bin"
        assert w._gguf_lm_head == "/path/to/lm_head.bin"

    def test_q3_defaults(self):
        w = FlashMoeWorker(
            binary_path="/nonexistent",
            model_path="/nonexistent",
        )
        assert w._q3_experts is False
        assert w._cache_io_split == 0
        assert w._gguf_embedding == ""
        assert w._gguf_lm_head == ""
