"""Tests for thermal monitoring."""

from __future__ import annotations

import sys

import pytest

from server.thermal import ThermalMonitor, _THERMAL_LEVELS


@pytest.mark.skipif(sys.platform != "darwin", reason="macOS-only thermal API")
def test_thermal_monitor_reads_pressure() -> None:
    monitor = ThermalMonitor()
    state = monitor.read()

    known_levels = set(_THERMAL_LEVELS.values()) | {"unknown"}
    assert state.level in known_levels
    assert isinstance(state.should_throttle, bool)
