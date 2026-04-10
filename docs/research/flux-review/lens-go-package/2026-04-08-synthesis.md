---
artifact_type: review-synthesis
method: flux-review
target: "docs/brainstorms/2026-04-08-lens-go-package-brainstorm.md"
target_description: "Go port of Auraken lens library — graph, selection, evolution, stacks"
tracks: 4
track_a_agents: [fd-graph-algorithm-determinism, fd-embed-data-integrity, fd-llm-provider-interface, fd-evolution-tracking-semantics, fd-stack-orchestration-state-machine]
track_b_agents: [fd-railway-interlocking-state-machine, fd-pharmaceutical-stability-kinetics, fd-ecological-survey-community-structure, fd-air-traffic-flow-management]
track_c_agents: [fd-persian-qanat-network-topology, fd-japanese-urushi-lacquer-sequential-curing, fd-tibetan-thangka-iconometric-specification, fd-asante-kente-pattern-encoding-community]
track_d_agents: [fd-moche-fineline-narrative-sequencing, fd-heian-kodo-incense-discrimination, fd-hopi-kiva-mural-ceremonial-layering]
date: 2026-04-08
---

# Lens Go Package: Flux Review Synthesis

4-track multi-agent review of the Go port brainstorm for Auraken's 291-lens conceptual framework library. 16 agents produced 62 raw findings. After deduplication, 28 distinct findings remain, grouped below by root cause.

## 1. Critical Findings (P0/P1)

### P0: Must fix before implementation begins

**P0-DETERM: Go map iteration makes graph algorithms non-deterministic**
Root cause: Go's `map` type randomizes iteration order. Every function that iterates over the adjacency list (`map[string][]TypedEdge`) produces different results per run. Louvain community detection and Brandes betweenness centrality are both affected. Setting `seed=42` on the PRNG is necessary but insufficient --- the node visitation order must also be deterministic.
Discovered independently by: Track A (GAD-1, GAD-2), Track B (P0-1), Track C (Qanat+Thangka convergent), Track D (P0-A).
**Convergence: 4/4 tracks.** Highest-confidence finding in the entire review.
Fix: Extract sorted key slices (`sort.Strings(keys)`) before every map iteration in `louvain.go` and `betweenness.go`. Enforce this via a linter rule or wrapper type that only exposes ordered iteration.

**P0-GOLDEN: No behavioral baseline means correctness is unverifiable**
Root cause: The brainstorm acknowledges that Task 0.1 (capture golden fixtures from Python) and Task 0.2 (write invariant spec) have not been done. Without golden community assignments, bridge sets, and EMA trajectories captured from the Python implementation, there is no way to verify the Go port produces equivalent results.
Discovered independently by: Track A (cross-cutting theme), Track C (Thangka P1), Track D (P0-A, P1-A).
**Convergence: 3/4 tracks.**
Fix: Elevate Tasks 0.1 and 0.2 from open questions to hard prerequisites. Run the Python implementation against a fixed input, capture community assignments, bridge lens IDs, betweenness rankings, EMA trajectories, and selector outputs as JSON golden fixtures. The Go implementation's acceptance tests compare against these fixtures.

**P0-SYNCONCE: `sync.Once` permanently caches initialization errors**
Root cause: If `Load()` fails (corrupt JSON, missing embed, partial parse), `sync.Once` guarantees the error callback never retries. All subsequent callers get zero-value data with no indication of failure.
Discovered by: Track A (EDI-1).
Fix: Replace `sync.Once` with a load state machine (`unloaded` / `loading` / `loaded` / `failed`) protected by `sync.Mutex`. On failure, remain in `failed` state but allow retry on next call. Return the stored error to every caller until a retry succeeds.

**P0-STREAM: Provider.Stream() is streaming-only; HaikuSelector needs collected text**
Root cause: Skaffen's `provider.Provider` interface exposes `Stream()` which returns a stream of tokens. The selector needs the full response body to parse JSON. Without a `CollectText()` helper (or equivalent), every selector implementation must reinvent stream-to-string collection with error handling.
Discovered by: Track A (LPI-1).
Fix: Add a `CollectText(ctx, stream) (string, error)` helper in the provider package, or add a non-streaming `Complete()` method. The selector should use this, not raw stream iteration.

**P0-TIMEOUT: Context timeout collapses into empty result, indistinguishable from "no match"**
Root cause: When the 15-second timeout fires during LLM selection, the brainstorm specifies "graceful degradation (empty list on error)." This means `Select()` returns `([]Lens{}, nil)` for both "timeout" and "no lenses matched." Callers cannot distinguish transient failure from genuine empty selection.
Discovered by: Track B (P0-2).
Fix: Return typed errors: `ErrSelectionTimeout`, `ErrProviderUnavailable`, etc. Reserve `([]Lens{}, nil)` for the genuine case where the LLM found no applicable lenses.

### P1: Must fix during implementation

**P1-RESET: `Reset()` cannot reinitialize `sync.Once`; stale state bleeds in tests**
Root cause: Go's `sync.Once` has no reset mechanism. The brainstorm's `Reset()` function (matching Python's `reset_library()`) cannot force reinitialization. Tests that call `Reset()` between cases run against the first test's cached data.
Discovered independently by: Track A (EDI-2), Track B (P1-3), Track D (P0-B).
**Convergence: 3/4 tracks.**
Fix: Addressed by the P0-SYNCONCE fix above. The load state machine should expose `Reset()` that transitions back to `unloaded`, clearing all cached communities, bridges, and lens maps.

**P1-EMA: EMA cold-start and floor application order must exactly match Python**
Root cause: The EMA update formula applies a confidence floor (0.1) and an exploration bonus (+0.15 for usage_count < 3). The order of operations matters numerically: `max(floor, ema) + bonus` differs from `max(floor, ema + bonus)`. The brainstorm does not specify the order.
Discovered independently by: Track A (ETS-1), Track B (P1-2).
**Convergence: 2/4 tracks.**
Fix: Read the Python source. Capture the exact order. Write it as a documented invariant. Golden fixtures for EMA trajectories (from P0-GOLDEN) serve as the acceptance test.

**P1-JSONEXPORT: Unexported Go fields silently vanish from JSON serialization**
Root cause: Go's `encoding/json` skips unexported (lowercase) struct fields. If any `Lens`, `Edge`, or `Community` field starts lowercase, serialization/deserialization silently drops it. The brainstorm does not call out this Go-specific pitfall.
Discovered by: Track A (SOS-1).
Fix: All struct fields that participate in JSON round-tripping must be exported. Add a test that round-trips every type through `json.Marshal` / `json.Unmarshal` and asserts field-level equality.

**P1-MUTEX: StackOrchestrator.NextPhase() needs mutex guard**
Root cause: `NextPhase()` reads and writes phase state. If called concurrently (e.g., from multiple goroutines in an agent loop), it races.
Discovered by: Track B (P1-1).
Fix: Add `sync.Mutex` to `StackOrchestrator`. Lock around `NextPhase()` and `CurrentPhase()`.

**P1-EXHAUSTED: NextPhase() clamps silently on exhausted stack**
Root cause: When all phases are consumed, `NextPhase()` returns the last phase again instead of signaling completion. Callers cannot distinguish "still on final phase" from "stack is done."
Discovered by: Track A (SOS-2).
Fix: Return `(Phase, error)` where `ErrStackExhausted` signals completion. Alternatively, add a `Done() bool` method.

**P1-OFFBYONE: 1-indexed LLM lens indices risk off-by-one**
Root cause: The Python implementation presents lenses to the LLM as a 1-indexed list. The Go selector must parse the LLM's 1-indexed response and convert to 0-indexed slice access. This is a classic off-by-one site.
Discovered by: Track A (LPI-2).
Fix: Explicit `index - 1` with bounds checking. Test with boundary values (index 1, index N, index 0, index N+1).

**P1-STORE: Store interface lacks session lifecycle (Load/Flush)**
Root cause: The `Store` interface for evolution tracking defines `RecordEvent` and `Effectiveness` but has no `Load()` or `Flush()` methods. Callers cannot control when state is persisted or when it is loaded from durable storage.
Discovered by: Track A (ETS-2).
Fix: Add `Load(ctx) error` and `Flush(ctx) error` to the `Store` interface. Document the contract: `Load` is called once at startup, `Flush` is called at session end or periodically.

**P1-REFINTEGRITY: Cross-file referential integrity not validated at load time**
Root cause: Edges reference lens IDs, communities reference lens IDs, but `Load()` does not validate that all referenced IDs exist in the lens map. A lens library update that removes a lens while keeping its edges creates silent inconsistency.
Discovered by: Track A (EDI-3), Track C (Thangka P1 on count/checksum validation).
**Convergence: 2/4 tracks.**
Fix: After loading all three JSON files, validate: (a) every edge references existing lens IDs, (b) every community member exists in the lens map, (c) count matches expected 291. Return a typed error listing all violations.

**P1-PHASETRANSITION: NextPhase transitions without validating phase completion**
Root cause: The state machine advances phases on any call to `NextPhase()` regardless of whether the current phase achieved its objective.
Discovered by: Track C (Urushi P1).
Fix: Add a `CompletePhase()` method that must be called before `NextPhase()` succeeds. Or accept a `PhaseResult` argument to `NextPhase()` that carries completion evidence.

**P1-ZOMBIE: EMA floor + exploration bonus creates zombie lens accumulation**
Root cause: The confidence floor (0.1) prevents any lens from reaching zero effectiveness. The exploration bonus (+0.15) keeps rarely-used lenses artificially elevated. Over weeks of operation, lenses that are consistently ignored never get pruned, growing the active candidate set indefinitely.
Discovered by: Track C (Urushi P1).
Fix: Add a decay mechanism or a maximum-age cutoff. Lenses that have been below a threshold for N consecutive sessions get excluded from selection candidates. Document the pruning policy.

**P1-USAGECOUNT: Exploration bonus lifecycle resets on process restart**
Root cause: `usage_count` lives in memory. When the process restarts, all lenses get the exploration bonus again, regardless of how many times they were used in prior sessions.
Discovered by: Track D (P1-C).
Fix: `usage_count` must be part of the persisted `Store` state. `Load()` restores it; `Flush()` saves it.

**P1-LENSREF: Full Lens type bloat forces unnecessary imports**
Root cause: Consumers that only need to reference a lens (by ID and name) must import the full `Lens` struct with all fields. This creates unnecessary coupling.
Discovered by: Track C (Kente P1).
Fix: Define a `LensRef` type (`ID string`, `Name string`) for lightweight cross-package references. The full `Lens` type remains in `pkg/lens/`.

**P1-EDGETYPE: Edge-type semantic weight indistinguishable at runtime**
Root cause: The four edge types (complements, contrasts, sequences, refines) are string labels. The graph algorithms treat them identically for traversal. Betweenness centrality on untyped edges misidentifies semantic bridges --- a "contrasts" edge should not contribute the same weight as a "sequences" edge.
Discovered by: Track C (Qanat P1), Track D (P1-B).
**Convergence: 2/4 tracks.**
Fix: Define edge-type weights as a configurable map. Default weights should match Python behavior. Betweenness and Louvain should use weighted edges.

## 2. Cross-Track Convergence

Findings ranked by number of independent tracks that identified the same root cause.

| Rank | Root Cause | Tracks | Agents | Finding IDs |
|------|-----------|--------|--------|-------------|
| 1 | Map iteration non-determinism breaks graph algorithms | 4/4 | GAD-1, GAD-2, Ecological P0-1, Qanat+Thangka, Moche+Hopi P0-A | P0-DETERM |
| 2 | Golden fixtures absent --- correctness unverifiable | 3/4 | A cross-cutting, Thangka P1, Moche+Hopi P0-A, P1-A | P0-GOLDEN |
| 3 | Reset() cannot clear sync.Once; stale state in tests | 3/4 | EDI-2, Ecological P1-3, Hopi P0-B | P1-RESET |
| 4 | EMA floor/bonus application order divergence | 2/4 | ETS-1, Pharma P1-2 | P1-EMA |
| 5 | Cross-file referential integrity unvalidated | 2/4 | EDI-3, Thangka P1 | P1-REFINTEGRITY |
| 6 | Edge-type semantic weight indistinguishable | 2/4 | Qanat P1, Moche P1-B | P1-EDGETYPE |

The 4/4 convergence on map iteration non-determinism is notable: every track --- from domain experts to Persian qanat engineers to Moche potters --- independently identified the same Go-specific pitfall. This signals a genuine implementation hazard, not a theoretical concern.

The 3/4 convergence on golden fixtures confirms that the brainstorm's Open Questions 1 and 2 are not optional --- they are blocking prerequisites.

## 3. Domain-Expert Insights (Track A)

Track A's five specialists covered the brainstorm's five subsystems with direct technical knowledge. Their highest-value contributions:

**PRNG divergence is unavoidable, not fixable.** GAD-1 identified that even with deterministic map iteration, `random.seed(42)` in Python and `rand.NewSource(42)` in Go produce different pseudorandom sequences. The Louvain algorithm will produce different community assignments. This means golden fixtures must be captured and the Go implementation must match them via deterministic map ordering, not via PRNG equivalence. The acceptance criterion is "same communities," not "same random sequence."

**sync.Once is a trap pattern for fallible initialization.** EDI-1 and EDI-2 together reveal that `sync.Once` is inappropriate when initialization can fail. This is a common Go anti-pattern that the brainstorm walks directly into. The fix (state machine with retry) is well-understood but not obvious to developers coming from Python.

**Provider.Stream() gap.** LPI-1 is a concrete API mismatch that would block implementation. Without `CollectText()`, the selector cannot function. This is a build-order dependency: the provider package must be updated before the selector can be implemented.

**Store interface is underspecified.** ETS-2 identifies that the brainstorm defines the persistence abstraction but omits the lifecycle methods that make it usable. This would surface as a design problem mid-implementation.

## 4. Parallel-Discipline Insights (Track B)

Track B brought operational safety patterns from high-reliability domains.

**Railway interlocking: state machines need exhaustiveness enforcement.** The railway agent (P1-4) argued that `Phase` should be a typed enum with compile-time exhaustiveness checking, not a bare string or int. Go lacks sum types, but a `Phase` type with `iota` constants plus a `//go:generate` stringer gives partial enforcement. This prevents the silent "unknown phase" failure that the Urushi agent also identified from a different angle.

**ATC flow management: typed errors for degradation modes.** The ATC agent (P0-2) made the strongest case for distinguishing timeout from empty-result. In air traffic, "no aircraft detected" and "radar offline" are categorically different states that require different controller responses. The same logic applies to lens selection: downstream code that receives an empty list and treats it as "no lenses apply" when the LLM actually timed out will make incorrect decisions.

**Pharmaceutical stability kinetics: EMA cold-start is a formulation problem.** The pharma agent (P1-2) reframed EMA initialization as analogous to drug stability testing --- the initial measurement conditions determine the entire trajectory. This reinforced the Track A finding (ETS-1) but added the insight that the cold-start formula should be an explicit, documented constant, not an implicit consequence of the code path.

## 5. Structural Insights (Track C)

Track C's distant-domain agents found structural isomorphisms that exposed design gaps.

**Qanat network topology: CommunityOf() point query is missing.** The qanat agent (P2) noted that the `Graph` interface exposes `Communities()` (bulk) but not `CommunityOf(lensID)` (point query). Every consumer that needs one lens's community must iterate all communities. This mirrors qanat master-channel lookup --- you need to answer "which channel feeds this garden?" without enumerating all channels.

**Kente pattern encoding: flat package hides a dependency triangle.** The kente agent identified that `Selector` depends on `Graph` (for community-aware selection), `Tracker` depends on `Selector` (to record which selections were effective), and `Graph` depends on `Tracker` (to weight edges by effectiveness). This circular dependency is hidden by the flat package structure. In a sub-package design, it would be a compile error. In a flat package, it compiles but creates initialization order and testing difficulties. Fix: make the dependencies explicit via interface injection rather than package-level variable access.

**Thangka iconometric specification: post-parse validation is mandatory.** The thangka agent argued that loading 291 lenses from embedded JSON without validating the count, checking for duplicate IDs, or verifying schema conformance is analogous to painting an icon without measuring the proportional grid. This converged with Track A's EDI-3 finding but added the specific recommendation of a post-parse checksum or count assertion.

## 6. Frontier Patterns (Track D)

Track D's esoteric agents produced findings at the highest semantic distance, with several that reframed familiar problems in useful ways.

**Moche fineline narrative sequencing: sequence edges are underspecified.** The Moche agent (P1-B) argued that "sequence" edges imply temporal ordering (lens A should precede lens B), but the graph treats all edges as undirected. If sequence edges are directional, the graph should be a mixed graph (directed for sequence, undirected for complement/contrast). This is a design question the brainstorm does not address. If sequence edges are non-directional, the name is misleading.

**Heian incense discrimination: confidence floor enforcement order is numerically ambiguous.** The Heian agent (P2-A) restated the EMA floor/bonus order problem using an incense-grading analogy but added a subtle point: the "exploration bonus" is semantically a different signal from "effectiveness." Mixing them in one number (the EMA score) makes it impossible to later separate "this lens is effective" from "this lens is unexplored." Recommendation: track exploration and effectiveness as separate dimensions, combine only at selection time.

**Hopi kiva mural layering: community-awareness in stack orchestration is unaddressed.** The Hopi agent (P3-B) noted that the stack orchestrator selects phases (deep_gold, shallow_gold, wax) without considering which communities the selected lenses belong to. A stack that repeatedly selects lenses from the same community will produce a narrow perspective. The orchestrator should accept community diversity as a constraint, or at least expose it as a metric.

**GLM 5.1 naming: HaikuSelector should be LLMSelector.** Track D (P3-D) and the brainstorm itself name the selector "HaikuSelector" while simultaneously describing it as provider-agnostic (supporting Haiku, GLM 5.1, or any provider). The type name contradicts the interface contract. Rename to `LLMSelector`.

## 7. Synthesis Assessment

**Overall brainstorm quality: Strong.** The technical choices are well-reasoned --- flat package, custom graph algorithms, provider abstraction, embedded data. The four open questions are genuine and the brainstorm is honest about what has not been done. The primary gaps are implementation-level details that a brainstorm should not need to specify exhaustively.

**Highest-leverage improvement: Elevate golden fixtures to a hard prerequisite.** This single action (capturing Python behavioral baselines before writing Go code) would make most P0 and P1 findings testable. Without it, the Go port is a reimplementation with unverifiable correctness. With it, every finding in this synthesis becomes a test case.

**Most surprising finding: The hidden dependency triangle.** The kente agent's identification of the `Selector` -> `Graph` -> `Tracker` -> `Selector` cycle was not found by any closer-domain agent. Track A's specialists each examined their own subsystem in isolation. It took a pattern-encoding expert thinking about warp-weft structural dependencies to see the circular coupling that the flat package conceals.

**Semantic distance value: High.** The 4/4 convergence on map non-determinism validates the method --- even the most esoteric agents independently found the highest-priority bug. Track C and D contributed findings (dependency triangle, sequence edge directionality, exploration/effectiveness separation) that no Track A agent identified. The diminishing-returns boundary appears between Track C and Track D: Track C produced 3 novel insights not found elsewhere, Track D produced 2. Both justify their cost.

**Recommended implementation order:**
1. Capture golden fixtures from Python (P0-GOLDEN) --- blocks everything
2. Replace `sync.Once` with retry-capable state machine (P0-SYNCONCE, P1-RESET)
3. Add sorted-key iteration to all map loops (P0-DETERM)
4. Add `CollectText()` to provider package (P0-STREAM)
5. Introduce typed errors for selector failure modes (P0-TIMEOUT)
6. Validate referential integrity at load time (P1-REFINTEGRITY)
7. Document and test EMA floor/bonus order (P1-EMA)
8. Remaining P1 items in dependency order
