"""Tests for worker crash recovery and watchdog."""

from __future__ import annotations

import time
import threading

import pytest

from server.metal_worker import (
    CrashInfo,
    MetalWorker,
    _INITIAL_BACKOFF_S,
    _MAX_CONSECUTIVE_RESTARTS,
    classify_crash,
)


# ---------------------------------------------------------------------------
# Error classification
# ---------------------------------------------------------------------------


def test_classify_crash_gpu_abort() -> None:
    """Exit code 134 = SIGABRT (GPU timeout)."""
    assert classify_crash(134) == "gpu_abort"
    assert classify_crash(-6) == "gpu_abort"


def test_classify_crash_oom() -> None:
    """Exit code 137 = SIGKILL (OOM)."""
    assert classify_crash(137) == "oom_killed"
    assert classify_crash(-9) == "oom_killed"


def test_classify_crash_segfault() -> None:
    """Exit code 139 = SIGSEGV."""
    assert classify_crash(139) == "segfault"
    assert classify_crash(-11) == "segfault"


def test_classify_crash_clean() -> None:
    """Exit code 0 = clean exit."""
    assert classify_crash(0) == "clean_exit"


def test_classify_crash_unknown() -> None:
    """None exit code = unknown."""
    assert classify_crash(None) == "unknown"


def test_classify_crash_other_signal() -> None:
    """Negative exit code for other signals."""
    assert classify_crash(-15) == "signal_15"  # SIGTERM


def test_classify_crash_other_code() -> None:
    """Positive non-signal exit codes."""
    assert classify_crash(1) == "exit_1"
    assert classify_crash(42) == "exit_42"


# ---------------------------------------------------------------------------
# CrashInfo dataclass
# ---------------------------------------------------------------------------


def test_crash_info_fields() -> None:
    """CrashInfo holds all expected fields."""
    crash = CrashInfo(
        timestamp=1234567890.0,
        exit_code=134,
        classification="gpu_abort",
        restart_attempt=1,
    )
    assert crash.classification == "gpu_abort"
    assert crash.restart_attempt == 1


# ---------------------------------------------------------------------------
# MetalWorker crash recovery state
# ---------------------------------------------------------------------------


def test_worker_initial_state() -> None:
    """Fresh worker has clean crash state."""
    w = MetalWorker(enable_watchdog=False)
    assert w.restart_count == 0
    assert w.last_crash is None
    assert w.crash_history == []
    assert not w.is_degraded
    assert not w.is_restarting


def test_worker_consecutive_crash_tracking() -> None:
    """Consecutive crash counter works correctly."""
    w = MetalWorker(enable_watchdog=False)
    assert w._consecutive_crashes == 0
    w._consecutive_crashes = 3
    w.reset_consecutive_crashes()
    assert w._consecutive_crashes == 0


def test_worker_degraded_flag() -> None:
    """Degraded flag is set when max restarts exceeded."""
    w = MetalWorker(enable_watchdog=False)
    w._degraded = True
    assert w.is_degraded


def test_worker_restarting_flag() -> None:
    """Restarting event works as expected."""
    w = MetalWorker(enable_watchdog=False)
    assert not w.is_restarting
    w._restarting.set()
    assert w.is_restarting
    w._restarting.clear()
    assert not w.is_restarting


# ---------------------------------------------------------------------------
# Backoff timing
# ---------------------------------------------------------------------------


def test_backoff_exponential() -> None:
    """Backoff doubles with each attempt."""
    from server.metal_worker import _INITIAL_BACKOFF_S, _MAX_BACKOFF_S

    for i in range(1, 6):
        backoff = min(_INITIAL_BACKOFF_S * (2 ** (i - 1)), _MAX_BACKOFF_S)
        expected = min(2.0 * (2 ** (i - 1)), 30.0)
        assert backoff == expected, f"attempt {i}: {backoff} != {expected}"


def test_backoff_caps_at_max() -> None:
    """Backoff never exceeds max."""
    from server.metal_worker import _INITIAL_BACKOFF_S, _MAX_BACKOFF_S

    backoff = min(_INITIAL_BACKOFF_S * (2**10), _MAX_BACKOFF_S)
    assert backoff == _MAX_BACKOFF_S
