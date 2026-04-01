---
bead: sylveste-3pv
date: 2026-03-28
type: plan
complexity: C3
---

# Plan: Worker Crash Auto-Recovery

## Problem

Metal worker crash (segfault, OOM, GPU timeout) = server useless until
manual restart. No detection, no recovery, no error categorization.

## Tasks

### Task 1: Add restart() method to MetalWorker

Clean up dead process, recreate queues, spawn fresh worker.
Track restart count and last restart time.

### Task 2: Watchdog thread

Background thread that polls `is_alive()` every 2 seconds.
On crash: log error, classify cause (exit code), auto-restart
with exponential backoff (2s, 4s, 8s, max 30s). Cap at 5
consecutive restarts before giving up (enters degraded mode).

### Task 3: Graceful degradation in HTTP layer

When worker is restarting:
- /health returns `{"status": "restarting", "restart_count": N}`
- /v1/chat/completions returns 503 with Retry-After header
- /metrics includes restart_count and degraded flag

When max restarts exceeded:
- /health returns `{"status": "degraded"}`
- /v1/chat/completions returns 503 permanently

### Task 4: Error categorization

Classify crash by exit code:
- Exit 134 (SIGABRT): GPU timeout / Metal error
- Exit 137 (SIGKILL): OOM killed
- Exit 139 (SIGSEGV): Segfault
- Exit -N (signal N): Other signal
- Other: Unknown

Expose in /metrics and /health.

### Task 5: Tests

- Test restart after simulated crash
- Test backoff timing
- Test max restart cap
- Test HTTP 503 during restart
- Test health endpoint during degraded mode

## File Change Summary

| File | Change |
|------|--------|
| `server/metal_worker.py` | restart(), watchdog thread, error classification |
| `server/main.py` | 503 during restart, health status changes |
| `tests/test_metal_worker.py` | NEW — crash recovery tests |
| `tests/test_server.py` | Degraded mode HTTP tests |
