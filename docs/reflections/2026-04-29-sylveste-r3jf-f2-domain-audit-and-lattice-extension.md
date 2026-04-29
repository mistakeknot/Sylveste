---
artifact_type: reflection
bead: sylveste-r3jf
date: 2026-04-29
sprint_outcome: shipped
plan: docs/plans/2026-04-28-f2-domain-audit-and-lattice-extension.md
audit_artifact: docs/research/f2-domain-discipline-audit.json
---

# Reflection — F2 Domain/Discipline Audit + Lattice Type Extension

## Outcome

F2 (sylveste-r3jf) shipped: lattice's type system now carries persona/lens entity types and G3/G4/G7 metadata schemas, ready for F3 DDL and F4 connectors to consume. The lexical audit ran on the real corpus (768 fd-agents, 291 Auraken lenses, 258 interlens lenses) and produced a `keep-separate` verdict with sharp signal — only one high-confidence cross-vocabulary pair across 2,938 candidates. 264/264 tests pass; ruff clean on F2 files.

Two repos touched: monorepo (audit JSON + plan + reflect doc) and `interverse/lattice/` (5 commits).

## What worked

**Plan-review caught all three P0s before implementation.** Three fd-* agents converged on `_read_audit_verdict()` import-time filesystem coupling — same root cause, three angles. Architecture flagged it as silent-fallback risk; correctness flagged module-cache fragility for env-var override; quality flagged it as a pattern that contradicts code-time-decision discipline. Replacing it with a `Final[Literal[...]]` constant baked at code time was a clean fix and is now a pattern other plans can crib.

**The bridges/same-as modeling decision was made explicitly.** The plan-review surfaced the divergence from the reconciliation doc (Annotation rule vs Structure rule). The user picked the as-written approach and we documented the rationale in both the plan header and AGENTS.md. Future readers can see the decision and the trade-off; nobody has to reverse-engineer it from the code.

**Verdict-coherence test fired automatically.** `test_baked_verdict_matches_audit_artifact` walks `parents[3]` to the monorepo root, reads the JSON, asserts the constant matches. If anyone in the future updates one without the other, this fails. Cheap canary, high value.

**Audit math produced sharp signal.** A 30% threshold for collapse felt arbitrary at write-time. Once run on real data, the answer was obvious: 3.85% / 0.88% coverage. The threshold was never the load-bearing piece; the corpus answered the question. Worth remembering when a measure feels unjustified — sometimes the data renders the threshold moot.

## What surprised

**Hooks pre-implemented half the plan's tests and impl.** Some session tooling auto-wrote files anticipating the next task. Helpful when the anticipated shape matched the revised plan; friction when it didn't (Task 2 hook used the pre-revision `len(t) > 1` filter, requiring a fix). Net positive, but the TDD red→green ceremony got compressed and I ended up writing tests that were never red. Worth being explicit about: TDD-as-discipline depends on knowing-what-fails; if the impl appears alongside the test, the failing-test step doesn't exercise its diagnostic value.

**Pre-existing test caught a real ship gap.** `test_table_completeness` in `test_diagnostics.py` was already there. It enforced "every registered entity type has a diagnostic property entry" — and caught my missing persona/lens/source entries on first run. This is the kind of cross-cutting invariant test that pays off across many features. Worth noting: invariant tests written by long-gone contributors keep working for years if they're well-named and live alongside the code they protect.

**Two repos, two commits per task** — the lattice/monorepo split made every commit a two-step. The `.gitignore`'d `interverse/` at the monorepo level meant code commits land in lattice while bead-state commits land at monorepo. Mostly harmless once internalized but it's a steady tax; the misleading first commit message ("feat(lattice/f2):" on a commit that contained only `.beads/issues.jsonl`) is exactly the failure mode this layout invites.

## What I'd change

**Don't write a 1681-line plan.** The plan was over-specified — full code blocks for every task, full test code for every assertion. Some of that helped (the test-as-spec discipline forced precise typing). But chunks of it became dead weight when the hooks pre-implemented and the actual code diverged from the plan's literal text. Next time: tasks 1-N as bullet-level specs (file paths, function signatures, key invariants); only inline full code for the genuinely novel pieces.

**Run the audit earlier.** I wrote the audit script, then the lattice extension, then ran the audit. The verdict (`keep-separate`) was needed to bake the constant in Task 11. If the audit had blown up on real data, I'd have had to revisit Workstream B. Better order: write the audit first (Tasks 1-5), run it on the real corpus (Task 6), THEN start the lattice extension (Tasks 7-13) — which is what the plan ordering specifies, but in execution I batched 3-5 together which compressed the feedback loop.

**File the lifecycle-mutation bug pre-emptively.** The `apply_lifecycle_transition` mutation bug in `engine.py` is pre-existing — F2 didn't introduce it. But F2 added entity types that exercise lifecycle (`persona` and `lens` with `edit_creates_new`). The QG agent caught it; the bead is filed (sylveste-lwp7). If I'd done a 5-minute scan of `engine.py` during plan-writing, I'd have surfaced this earlier and could have noted it as a known issue rather than a discovery.

## Patterns to keep

1. **Code-time constants over runtime discovery for schema-shape decisions.** `LATTICE_F2_VERDICT: Final[Literal[...]]` baked from `bd state` at execution time. No filesystem walks, no fallbacks, no silent drift. Verdict change is a one-line code commit. Pattern applies anywhere a downstream artifact depends on a one-time analysis result.

2. **Coherence tests for cross-artifact decisions.** When two artifacts encode the same fact (audit JSON verdict + module constant), write a test that asserts they agree. It runs every CI cycle for free.

3. **Invariant-completeness tests for registries.** `test_table_completeness` enumerates the registry and asserts each entry has a corresponding entry elsewhere. Cheap to write, catches whole classes of "I added a thing but didn't update the other thing" bugs.

## Open follow-ups

- **sylveste-lwp7** (P2): `apply_lifecycle_transition` registry mutation bug
- **sylveste-rm8w** (P3): `function` diagnostic property mismatch between `families.py` and `diagnostics.py`
- F3 (sylveste-dsbl): SQLite migration extending `storage.py` with the new entity types
- F4 (sylveste-t2cs): three Connector implementations (fd_agents, auraken_lenses, interlens)
- F6b (sylveste-g939): flux-drive backend swap targeting a new `select_personae_for_task` template

## Numbers

| Measure | Value |
|---|---|
| Plan tasks | 13 (6 audit + 7 lattice) |
| Lattice commits | 5 (4 feature + 1 quality-gate fix) |
| Monorepo commits | 2 (bead state + audit/plan/reflect docs) |
| New tests | 49 (25 audit + 24 persona/lens) |
| Total tests | 264/264 passing |
| Audit corpus | 768 fd-agents, 291 Auraken, 258 interlens |
| Distinct domains / disciplines | 26 / 113 |
| High-confidence cross-vocabulary pairs | 1 (`economics ↔ economics`) |
| Domain coverage / Discipline coverage | 3.85% / 0.88% |
| Verdict | keep-separate |
