---
artifact_type: findings
source_brainstorm: docs/brainstorms/2026-04-08-lens-go-package-brainstorm.md
bead: sylveste-benl.1
generated_at: '2026-04-08'
agents_run:
  track_a:
    - fd-go-package-api-design
    - fd-go-goroutine-isolation
    - fd-go-error-handling-propagation
  track_b:
    - fd-railway-interlocking-state-machine
    - fd-pharmaceutical-stability-kinetics
    - fd-ecological-survey-community-structure
    - fd-air-traffic-flow-management
---

# Flux-Drive Findings: Lens Go Package Brainstorm
## `os/Skaffen/pkg/lens/` — Auraken → Skaffen Migration

---

## Triage Summary

Track B agents triaged as **high-priority Project Agents**. Each maps to one of the four implementation modules:

| Agent | Module | Lens |
|---|---|---|
| fd-railway-interlocking-state-machine | `stacks.go` | Phase type safety, transition atomicity |
| fd-pharmaceutical-stability-kinetics | `evolution.go` | EMA numeric fidelity, Store contract |
| fd-ecological-survey-community-structure | `graph.go`, `louvain.go`, `betweenness.go` | Determinism, parity with networkx |
| fd-air-traffic-flow-management | `selector.go` | LLM/deterministic boundary, failure modes |

---

## P0 Findings

### P0-1 — Go map iteration order breaks Louvain determinism even with seed=42
**Agent:** fd-ecological-survey-community-structure  
**Files:** `pkg/lens/louvain.go` (planned)  
**Trigger:** Any call to `lens.Communities()` after `Load()`

Go randomizes map iteration order per process start by design. If the custom Louvain implementation iterates over the adjacency list (`map[string][]TypedEdge`) during the modularity optimization phase without first sorting node keys, two calls to `Communities()` within the same process will produce different community assignments even with seed=42. The brainstorm specifies that seed=42 must match networkx output — but networkx does not have this problem because Python dict iteration is insertion-order-stable since 3.7 and networkx sorts nodes internally.

**Failure scenario:** Skaffen's style fingerprinting pipeline calls `lens.Communities()` to produce fingerprint vectors. The first call returns lens 47 in community 3. A second call in the same session returns it in community 5. Downstream preference extraction treats community membership as a stable identifier, so it generates contradictory profile vectors for the same conversation. The failure is silent — no error, no log — and only surfaces when A/B analytics reveal profile contradictions.

**Smallest fix:** Before each Louvain modularity optimization pass, collect node keys into a `[]string`, call `sort.Strings()`, and iterate the sorted slice. Add a determinism test: run `Communities()` ten times in the same process with the same embedded JSON and assert all ten outputs are identical.

---

### P0-2 — Context timeout collapses into `([]Lens{}, nil)` — caller cannot distinguish timeout from no-lenses-found
**Agent:** fd-air-traffic-flow-management  
**Files:** `pkg/lens/selector.go` (planned)  
**Trigger:** Haiku p95 latency spike (>15 seconds) under load

The brainstorm specifies "graceful degradation (empty list on error)" as the timeout handling behavior. This conflates two semantically distinct outcomes: (a) the LLM found no relevant lenses and returned an empty selection, and (b) the advisory system failed to respond within the deadline. In ATFM terms, this is equivalent to a weather advisory system returning "no delays recommended" when it actually timed out — the slot allocator cannot tell the difference and proceeds without any degradation signal.

**Failure scenario:** Skaffen's provider experiences a 30-second Haiku latency spike. HaikuSelector's 15-second context fires. If the implementation returns `([]Lens{}, nil)`, the agentloop treats this as "model found no relevant lenses" and proceeds without any lenses applied. The user receives a response with no lens framing and no indication of degraded mode. Neither the user experience nor the application logs signal the failure. Under sustained provider degradation, this continues indefinitely.

**Smallest fix:** Map context timeout specifically to `(nil, ErrSelectorTimeout)`. The `Selector` interface documentation must specify three distinct outcomes:
- `(lenses, nil)` — successful selection, zero or more lenses
- `(nil, ErrNoLensesFound)` — model responded but found no applicable lenses
- `(nil, err)` — advisory system failed (timeout, parse error, provider error)

HaikuSelector must never return `([]Lens{}, nil)` for a timeout.

---

## P1 Findings

### P1-1 — StackOrchestrator.NextPhase requires mutex guard — agentloop may call it concurrently
**Agent:** fd-railway-interlocking-state-machine  
**Files:** `pkg/lens/stacks.go` (planned)  
**Trigger:** Concurrent agentloop calls (timeout retry + normal completion)

`NextPhase` reads the current `Phase` and writes the next phase as two operations. Without a mutex covering both, a concurrent caller can observe state between read and write. Skaffen's `internal/agentloop/` processes concurrent goroutines; a timeout retry and a normal completion path may both call `NextPhase` simultaneously, both read Phase N, both compute Phase N+1, and both write it — skipping a phase silently without any error signal.

**Failure scenario:** Two concurrent agentloop iterations both call `NextPhase` simultaneously. Each reads Phase 1 (deep_gold), each computes Phase 2 (shallow_gold), each writes Phase 2. The orchestrator appears to be in Phase 2 but has skipped the Phase 1 → Phase 2 transition logic, causing the wrong transition template to fire for the remainder of the session.

**Smallest fix:** `StackOrchestrator` embeds `sync.Mutex`. All exported methods that read or write phase state call `Lock/Unlock` as their first and last operation, with no nested lock acquisitions inside the critical section.

---

### P1-2 — EMA cold-start initialization value must exactly match Python's behavior
**Agent:** fd-pharmaceutical-stability-kinetics  
**Files:** `pkg/lens/evolution.go` (planned)  
**Trigger:** Any lens with fewer than 3 prior events (the common case for new lenses)

The Python `lens_evolution.py` implementation specifies an initial EMA value before any observation. If Python initializes to `0.0` (cold-start suppression bias) and the Go port initializes to `0.5` (neutral) or any other value, lenses with only 1-2 events will show dramatically different effectiveness scores between Auraken and Skaffen. The brainstorm specifies Open Question 1 (behavioral baseline) as "not done yet" — this means the initialization value is not yet verified.

**Failure scenario:** A user with a short conversation history (2-3 turns) uses Auraken, which suppresses new lenses via cold-start bias toward 0.0, causing the selection system to prefer established lenses. The same user's data migrated to Skaffen has their new lenses starting at 0.5, causing selection to recommend different lenses. The behavioral divergence is invisible until A/B comparison reveals cohort-level lens selection differences. This is a parity requirement, not an implementation quality issue.

**Smallest fix:** Capture Python baseline output (Open Question 1) before writing `evolution.go`. Write a golden-fixture test that runs 50 `RecordEvent` sequences against Python output and asserts bit-level equality on the final EMA value. Treat any divergence as a P0 regression.

---

### P1-3 — `Reset()` must clear all cached state, not just the `sync.Once` trigger
**Agent:** fd-ecological-survey-community-structure  
**Files:** `pkg/lens/loader.go` (planned)  
**Trigger:** Any test sequence that calls `Load()`, `Reset()`, `Load()` with modified data

The brainstorm specifies `Reset()` for testing (matches Python's `reset_library()`). If `Reset()` only resets the `sync.Once` trigger but not the underlying community cache variable (the adjacency list, community assignments, centrality scores), a test that calls `Load()`, reads `Communities()`, then calls `Reset()` and `Load()` with a modified adjacency list will receive stale communities from the first load.

**Failure scenario:** CI tests load the full 1,779-edge graph, read a community assignment, call `Reset()`, then load a reduced test graph and expect different community assignments. The test receives the original community assignments because the cache variable was not cleared. Tests pass in isolation (no prior `Load()` call) but fail when run after other tests, producing flaky CI results that are difficult to diagnose.

**Smallest fix:** `Reset()` swaps the package-level state pointer with a fresh zero value, not just the `sync.Once`. Verified by a test that asserts stale community assignments are not returned after `Reset()` + re-`Load()` with a modified graph.

---

### P1-4 — Phase type must be a named typed enum with exhaustiveness enforcement
**Agent:** fd-railway-interlocking-state-machine  
**Files:** `pkg/lens/stacks.go` (planned)  
**Trigger:** Any future addition of a new Phase constant without a corresponding `NextPhase` case

If `Phase` is defined as a `string` or untyped `int`, Go's type system cannot reject unknown phase values and the compiler cannot warn when a new Phase constant is added without a corresponding case in `NextPhase`'s switch statement.

**Failure scenario:** A future contributor adds a fourth transition template and a new `Phase` constant. They add the constant but miss the `NextPhase` switch case. Go compiles without warning. Users whose sessions enter the new phase receive no lens stack progression — the failure is invisible in logs until session analytics reveal a cohort of stalled sessions.

**Smallest fix:** `type Phase int` with an iota constant block. `NextPhase` has an explicit `default` case that returns `ErrUnknownPhase` sentinel, not a zero value, forcing callers to handle all transitions explicitly.

---

## P2 Findings

### P2-1 — Betweenness centrality scope (multigraph vs single graph) must be specified before implementation
**Agent:** fd-ecological-survey-community-structure  
**Files:** `pkg/lens/betweenness.go` (planned)

The 1,779 edges are typed (complements/contrasts/sequences/refines). Betweenness centrality can be computed on: (a) the full multigraph with all edge types collapsed to a single weight, (b) each typed subgraph separately, or (c) a weighted combination. The brainstorm does not specify which scope matches the networkx reference. The two choices produce different centrality scores and different bridge lens sets.

**Risk:** The 15 bridge lenses identified by the Go implementation differ from networkx's 15. Downstream code that uses bridge lenses as anchors for community traversal selects a different spanning set, introducing a systematic behavioral difference that only manifests in multi-lens recommendation scenarios. Manifests over weeks, not immediately.

**Action before implementation:** Inspect `lens_graph.py` to determine what `nx.betweenness_centrality()` was called on (the full graph or a subgraph). Document the scope decision in `betweenness.go`'s package comment.

---

### P2-2 — Exploration bonus application order (before vs after EMA update) changes numeric result
**Agent:** fd-pharmaceutical-stability-kinetics  
**Files:** `pkg/lens/evolution.go` (planned)

The `+0.15` exploration bonus for `usage_count < 3` must be applied either before or after the EMA update — the order changes the numeric result. For lenses with `usage_count` exactly 2, the effectiveness score differs by approximately 0.015 between the two orderings. This is small enough to pass eyeball inspection but large enough to change rank ordering between two closely-scored lenses, causing the selector to prefer a different lens than Auraken would for the same conversation history.

**Action:** Inspect `lens_evolution.py` to determine whether the bonus is applied before or after `ema = alpha * event_score + (1 - alpha) * ema`. Document the order in `evolution.go`'s comments and assert it in a golden-fixture test.

---

### P2-3 — Store interface must specify required numeric precision
**Agent:** fd-pharmaceutical-stability-kinetics  
**Files:** `pkg/lens/evolution.go` (planned)

The `Store` interface returns `float64` EMA values. If a caller-provided persistence implementation serializes to JSON (which truncates to ~15 significant digits) or SQL with a `REAL` column (4-byte float, 7 significant digits instead of 15), the reconstituted EMA will drift on the first `RecordEvent` after restoration.

**Action:** Add a `// Implementors must preserve float64 IEEE 754 precision. SQL: DOUBLE PRECISION. JSON: no truncation.` comment to the `Store` interface. This is an interface contract specification, not an implementation requirement, so it costs one comment and prevents a class of precision bugs in downstream implementations.

---

### P2-4 — JSON parsing layer must produce typed errors for each malformed output case
**Agent:** fd-air-traffic-flow-management  
**Files:** `pkg/lens/selector.go` (planned)

The selector parses a JSON array from LLM output, handling markdown fences and extra text. The brainstorm acknowledges this pattern but does not specify how each failure mode maps to a typed error. Known failure modes: (a) model outputs a JSON object instead of array, (b) array contains string IDs instead of integers, (c) array contains out-of-range indices, (d) array is empty because the model refused the task.

**Action:** Define at minimum four typed parse errors. Map `json.Unmarshal` type mismatch to a `ErrParserTypeMismatch`, out-of-range indices to `ErrInvalidLensID`, and model refusal to `ErrModelRefused`. Do not collapse these into a single `ErrParseFailed` — the caller needs to distinguish model refusal (retry with different prompt) from parse failure (retry with same prompt) from type mismatch (provider contract violation).

---

### P2-5 — Provider-agnostic interface must specify lens ID format contract
**Agent:** fd-air-traffic-flow-management  
**Files:** `pkg/lens/selector.go`, `pkg/lens/types.go` (planned)

The brainstorm supports both Haiku (which uses 1-indexed integers in the prompt) and GLM 5.1. If GLM 5.1 returns lens IDs as name strings while Haiku returns integers, the `Selector` interface contract does not specify which format `[]Lens` contains. A caller that switches providers via `Z_AI_API_KEY` receives a different ID format with no error signal, and the downstream lens lookup silently finds no matching lenses.

**Action:** The `Selector` interface documentation must specify: "Returned `Lens` values are resolved against the embedded lens library. Implementations must normalize provider-specific ID formats (name strings, 1-indexed integers) to the library's canonical ID before returning."

---

### P2-6 — Fallback lens set must be specified — "empty list on error" is not graceful degradation
**Agent:** fd-air-traffic-flow-management  
**Files:** `pkg/lens/selector.go` (planned)

The brainstorm's "graceful degradation (empty list on error)" is a silent failure design, not graceful degradation. An ATFM analogy: a ground delay program that falls back to "no delays" when the weather advisory fails does not degrade gracefully — it propagates the advisory failure into the flight schedule.

**Action:** Specify a fallback lens set (the 15 bridge lenses by default, overridable via constructor option) that callers use when `Select` returns `ErrSelectorTimeout`, `ErrNoLensesFound`, or any parse error. The `Tracker` interface should expose `BridgeLenses()` so the fallback set is always available without importing the graph package.

---

## P3 Findings

### P3-1 — JSON serialization of StackOrchestrator must include all state that affects transition behavior
**Agent:** fd-railway-interlocking-state-machine  
**Files:** `pkg/lens/stacks.go` (planned)

Session persistence requires that all unexported fields affecting transition behavior are either exported and serialized or re-derived deterministically from exported state. Specifically, if a phase history slice is used for loop detection, it must survive JSON round-trip. A round-trip test for every `Phase` value should verify that `json.Marshal` followed by `json.Unmarshal` produces a `StackOrchestrator` where `NextPhase` returns the same sequence as a freshly constructed orchestrator starting from the same phase.

---

### P3-2 — Concurrent RecordEvent on the same lensID without per-key mutex is a data race
**Agent:** fd-pharmaceutical-stability-kinetics  
**Files:** `pkg/lens/evolution.go` (planned)

Two goroutines calling `RecordEvent` with the same `lensID` simultaneously produce a read-modify-write race on the in-memory `Store`'s map. Go's race detector will flag this, but if the race detector is not enabled in production, the EMA for high-frequency lenses silently corrupts.

**Action:** Use `sync.Map` or a map protected by a per-key `RWMutex`. Enable the race detector in all test targets via `-race` in the Makefile / CI configuration.

---

### P3-3 — `Shared types` question (Open Question 4) should be resolved before any dependent package starts
**Agent:** fd-go-package-api-design  
**Files:** `pkg/lens/types.go`, future `pkg/fingerprint/`, `pkg/extraction/` (planned)

Open Question 4 asks whether `Lens`, `Edge`, `Community` types live in `pkg/lens/` or a shared `pkg/types/`. If `pkg/fingerprint/` and `pkg/extraction/` import `Lens` from `pkg/lens/`, they become coupled to the lens package's internal graph implementation — any internal change to `pkg/lens/` forces all consumers to update. Resolving this before `pkg/fingerprint/` is written avoids a future import-cycle refactor.

**Recommendation:** Define `Lens`, `Edge`, `Community` in `pkg/lens/` but export only minimal fields. If fingerprint or extraction needs to reference a `Lens`, accept an interface (e.g., `LensID() string`) rather than the concrete type. Defer `pkg/types/` until a third package creates a genuine circular dependency.

---

## Infrastructure Finding (Not a Code Issue)

### INF-1 — All four Track B agent files have corrupted "What NOT to Flag" sections
**Files:** All four `.claude/agents/fd-railway-interlocking-state-machine.md`, `fd-pharmaceutical-stability-kinetics.md`, `fd-ecological-survey-community-structure.md`, `fd-air-traffic-flow-management.md`

The "What NOT to Flag" prose in each agent file was serialized as character-by-character bullet lists (e.g., `- D`, `- o`, `- e`, `- s`) instead of a single bullet with the full sentence. Each file contains 218–327 such malformed lines. This makes the exclusion scope unreadable and the agents may apply their lens to out-of-scope concerns as a result.

**Counts:** railway: 218 lines, pharmaceutical: 241 lines, ecological: 242 lines, atc: 327 lines.

**Action:** Regenerate the "What NOT to Flag" sections in all four files using `flux-gen` or edit manually to replace the character lists with the intended prose. This is a generator defect, not a content defect — the intended text is recoverable from the character sequence.

---

## Cross-Cutting Observations

**Open Question 1 (behavioral baseline) is load-bearing for P1-2.** The EMA cold-start finding cannot be resolved without the Python baseline. This should be treated as a prerequisite task, not a parallel task.

**Open Question 3 (lens data freshness) is not flagged by any agent** because it is a product decision, not an implementation defect. The compile-time embedding approach is correct for the initial port. Runtime reload from filesystem is a P3 enhancement, not a gap.

**Open Question 2 (invariant spec) should be written alongside the plan**, not deferred. The railway agent's emphasis on type exhaustiveness and the pharmaceutical agent's emphasis on EMA parameter immutability both constitute parts of a relational invariant spec. Capturing them in a spec document (`pkg/lens/INVARIANTS.md` or a testable `invariants_test.go`) before implementation begins is the lowest-cost way to prevent parity regressions.

---

## Findings Count

| Severity | Count |
|---|---|
| P0 | 2 |
| P1 | 4 |
| P2 | 6 |
| P3 | 3 |
| Infrastructure | 1 |
| **Total** | **16** |
