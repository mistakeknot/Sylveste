# fd-fingerprint-concurrency-model — Style Fingerprinting Go Port Findings

**Target:** `docs/brainstorms/2026-04-12-style-fingerprinting-go-port-brainstorm.md`
**Agent:** fd-fingerprint-concurrency-model (mutex granularity, lock contention under burst messages, map reference leaking through lock boundary, read-copy-update patterns for concurrent readers)
**Track:** Adjacent (Project Agents)
**Decision Lens:** Evaluates whether `sync.Mutex` on `Fingerprint` provides correct concurrent access for the stated use case (burst messages arriving simultaneously for the same user), whether the lock granularity is appropriate, and whether internal state can leak through the lock boundary.

---

## Finding C-1: `BuildMirroring` must not return references to internal maps — concurrent access after lock release

**Severity: P1**
**File:** `apps/Auraken/src/auraken/style.py:346-459` — `build_mirroring_instructions`

The brainstorm specifies that `BuildMirroring` acquires a lock, reads the fingerprint, and generates instruction strings. The function reads vocabulary counter maps (`laughter`, `affirmation`, `intensifier`, `hedge`, `opener`) to find the top token. The generated string contains only the token name (e.g., `"If something is funny, use 'haha'"`), so the string output does not reference internal maps.

However, an implementation risk exists: if a developer decides to expose raw profile data alongside instructions (e.g., adding a method like `(*Fingerprint) ModeProfile(mode Mode) ModeProfile`), they might return a pointer to the internal `ModeProfile` struct. Since Go maps are reference types, the caller would hold a reference to `Laughter map[string]int` that could be mutated by a concurrent `Update()` call after the lock is released.

**Current risk assessment:** The brainstorm's public API does not include a raw profile accessor. The risk is LOW but should be documented as a design invariant.

**Fix:** Add a comment on the `Fingerprint` struct: "Methods must not return references to internal maps or slices. BuildMirroring returns only string values. If a profile accessor is added in the future, it must return a deep copy." Alternatively, make `ModeProfile` fields unexported and provide copy-on-read accessors.

---

## Finding C-2: Mutex on `Fingerprint` is correct granularity — no need for per-mode or per-field locks

**Severity: P3 (informational — validates the brainstorm's design)**
**File:** Brainstorm — Key Decision #2, "Thread-safe via mutex on Fingerprint"

The brainstorm states `Update()` and `BuildMirroring()` acquire a lock on `Fingerprint`. `ComputeObservables()` and `ClassifyMode()` are pure functions. This is the correct design:

1. **Single writer per user:** Even with burst messages, a single user's `Fingerprint` is updated sequentially (messages are ordered by arrival time). The lock prevents data corruption from concurrent goroutines processing the same user's messages, but contention is LOW because updates are fast (a few EMA multiplications and map increments).

2. **Lock scope is small:** `Update()` does ~10 EMA computations and ~5 map increments. Under Go's optimistic mutex (spinning before sleeping), this completes in nanoseconds. No I/O under the lock.

3. **Reader contention:** `BuildMirroring()` reads the profile and generates a string. This is pure computation — no I/O under the lock. Even if `BuildMirroring()` is called concurrently with `Update()`, the lock ensures consistency. The read duration is bounded (iterating ~5 small maps to find max values).

A `sync.RWMutex` would allow concurrent `BuildMirroring()` calls without blocking each other, but the benefit is negligible given the low contention. The simpler `sync.Mutex` is appropriate.

**Recommendation:** Use `sync.Mutex` as proposed. If profiling later shows lock contention (unlikely), upgrade to `sync.RWMutex` with `RLock()` for `BuildMirroring()` and `Lock()` for `Update()`.

---

## Finding C-3: `UpdateCadence` must acquire the same lock as `Update` — brainstorm lists them as separate methods but they share `Fingerprint` state

**Severity: P1**
**File:** `apps/Auraken/src/auraken/style.py:330-341` — `update_cadence`
**Referenced brainstorm:** Public API, "`(*Fingerprint) UpdateCadence(burstSize int)` — thread-safe cadence tracking"

Python's `update_cadence` takes `existing: dict | None` and returns the modified dict. It modifies `existing["cadence"]`. In Go, this becomes a method on `*Fingerprint` that modifies `fp.Cadence`. Both `Update()` and `UpdateCadence()` modify the same `Fingerprint` struct.

If `UpdateCadence` is called from a different goroutine than `Update` (plausible: one goroutine processes the message content, another detects the burst boundary), they must both acquire the same `Fingerprint.mu` lock. The brainstorm's public API listing shows both as `(*Fingerprint)` methods, implying they share the receiver's mutex. But this must be explicit in the implementation — both methods must start with `fp.mu.Lock(); defer fp.mu.Unlock()`.

**Failure scenario:** Developer implements `UpdateCadence` without acquiring the lock because "cadence is a separate sub-struct." But `cadence.avg_burst_size` is a `float64`, and concurrent float64 reads and writes are not atomic on most architectures. A torn read could produce NaN or infinity in the EMA.

**Fix:** Both `Update()` and `UpdateCadence()` must start with `fp.mu.Lock(); defer fp.mu.Unlock()`. Add a test that calls both concurrently (similar to `TestTrackerConcurrent` in `pkg/lens/evolution_test.go`) to verify no data races under `-race`.

---

## Finding C-4: `DetectCurrentMode` is stateless and does not need locking — but callers should not assume thread-safe access to the message slice

**Severity: P2**
**File:** `apps/Auraken/src/auraken/style.py:577-594` — `detect_current_mode`

`DetectCurrentMode(messages []string, window int) Mode` is a pure function (calls `ClassifyMode` on each message, does a majority vote). It does not access `Fingerprint` state and does not need a lock.

However, the input `messages []string` slice could be shared with a goroutine that appends to it. Go slices are not concurrent-safe. If the caller passes a slice that another goroutine is concurrently appending to, the slice header (length, capacity, pointer) could be read inconsistently.

This is a caller-side concern, not a `DetectCurrentMode` concern. But it should be documented: "The messages slice must not be modified concurrently with this call. Pass a copy if the slice is shared."

**Fix:** Document the thread-safety contract in the function's godoc comment. No internal locking needed.
