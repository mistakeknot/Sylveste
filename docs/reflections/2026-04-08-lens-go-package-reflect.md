---
artifact_type: reflection
bead: sylveste-benl.1
sprint_steps: [brainstorm, strategy, plan, plan-review, execute, test, quality-gates, resolve, reflect]
---

# Reflection: Lens Go Package (sylveste-benl.1)

## What Worked

- **Golden fixtures as prerequisite** was the right call (3/4 flux-review convergence). Having Python behavioral baselines before writing Go enabled parity tests for EMA trajectories and stack transitions. Louvain/betweenness parity was not achievable (different PRNG), but the fixture infrastructure caught the normalization bug in betweenness immediately.

- **Wave-based parallel execution** cut implementation time significantly. Tasks 4 (graph), 8 (evolution), 9 (stacks) ran simultaneously because they share only `types.go`. Three agents completed in the time of one.

- **Flux-review brainstorm findings → plan integration** prevented rework. The sync.Once trap (P0-SYNCONCE) was designed around from the start (mutex + state machine), not discovered mid-implementation.

- **92.6% test coverage** for a 3,502-LOC package with 63 tests. The TDD approach (golden fixtures → types → loader → graph → algorithms → integration) kept each task small and testable.

## What Didn't Work

- **Louvain exact parity impossible.** Python's `random.seed(42)` and Go's `rand.NewSource(42)` produce different sequences. The Louvain optimization path diverges, producing 6 communities instead of 7. Both are valid modularity optima. Tests were relaxed to verify structural properties (determinism, reasonable count, all lenses assigned) rather than exact community membership.

- **Betweenness normalization was wrong initially.** The test expectations were incorrect (not the implementation). Verifying against actual networkx output caught this. Lesson: always verify golden fixture expectations against the source tool, not manual calculation.

- **Tasks 5+6 agent hit API error** after 10 minutes. The files were created but tests hadn't been debugged. Required manual intervention to fix normalization and test expectations. Lesson: complex algorithm tasks (Louvain, Brandes) should be split into separate agents rather than combined.

## Decisions Made

1. **Flat package with interfaces** — confirmed as correct. 18 files, clear naming convention (`NewGraph`, `NewTracker`, `NewOrchestrator`, `NewLLMSelector`), no circular imports.
2. **LensRef as cross-package currency** — lightweight `{ID, Name}` struct. Downstream packages (fingerprint, extraction) can reference lenses without importing the full graph.
3. **Provider.Collect() already existed** — the flux-review P0-STREAM was a false alarm. StreamResponse.Collect() was already implemented.
4. **MemoryStore for testing** — in-memory Store implementation enables full pipeline testing without database.

## Follow-up Work

- Implement `pkg/fingerprint` (sylveste-benl.2) — next P0 child of the epic
- Port OODARC prompt builder (sylveste-benl.3)
- Wire LLMSelector to Skaffen's agent loop (Orient phase)
- Add filesystem override for lens data (deferred from v1)
