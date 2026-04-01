"""Thermal monitoring via macOS notify API (no sudo required).

Reads com.apple.system.thermalpressurelevel via libSystem notify_register_check
and notify_get_state. Works on any macOS version with no elevated privileges.
"""

from __future__ import annotations

import ctypes
import ctypes.util
import sys
from dataclasses import dataclass

_THERMAL_LEVELS: dict[int, str] = {
    0: "nominal",
    1: "moderate",
    2: "heavy",
    3: "trapping",
    4: "sleeping",
}


@dataclass(frozen=True)
class ThermalState:
    """Snapshot of macOS thermal pressure level.

    Attributes:
        level: Human-readable name (nominal, moderate, heavy, trapping, sleeping).
        raw_value: Integer returned by notify_get_state (0-4).
    """

    level: str
    raw_value: int

    @property
    def should_throttle(self) -> bool:
        """True when thermal pressure is heavy or above (raw_value >= 2)."""
        return self.raw_value >= 2


class ThermalMonitor:
    """Reads macOS thermal pressure via the notify(3) API.

    Uses ctypes to call notify_register_check and notify_get_state from
    /usr/lib/libSystem.B.dylib. No subprocess, no sudo, no IOKit.

    Raises RuntimeError on non-macOS platforms.
    """

    _NOTIFY_NAME = b"com.apple.system.thermalpressurelevel"

    def __init__(self) -> None:
        if sys.platform != "darwin":
            raise RuntimeError(f"ThermalMonitor requires macOS, got {sys.platform!r}")

        self._lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib")

        # uint32_t notify_register_check(const char *name, int *out_token)
        self._lib.notify_register_check.argtypes = [
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_int),
        ]
        self._lib.notify_register_check.restype = ctypes.c_uint32

        # uint32_t notify_get_state(int token, uint64_t *out_state)
        self._lib.notify_get_state.argtypes = [
            ctypes.c_int,
            ctypes.POINTER(ctypes.c_uint64),
        ]
        self._lib.notify_get_state.restype = ctypes.c_uint32

        self._token = ctypes.c_int()
        status = self._lib.notify_register_check(
            self._NOTIFY_NAME, ctypes.byref(self._token)
        )
        if status != 0:
            raise RuntimeError(f"notify_register_check failed with status {status}")

    def read(self) -> ThermalState:
        """Read the current thermal pressure level.

        Returns a ThermalState with the human-readable level name and raw
        integer value. Unknown raw values are mapped to "unknown".
        """
        state = ctypes.c_uint64()
        status = self._lib.notify_get_state(self._token, ctypes.byref(state))
        if status != 0:
            raise RuntimeError(f"notify_get_state failed with status {status}")

        raw = int(state.value)
        level = _THERMAL_LEVELS.get(raw, "unknown")
        return ThermalState(level=level, raw_value=raw)
