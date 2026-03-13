# Interspect — Roadmap

**Companion to:** [interspect-vision.md](./interspect-vision.md)
**Beads:** `bd search "interspect" --status=open`
**Last updated:** 2026-03-13

---

## Phase Status

| Phase | Status | Key Shipped |
|-------|--------|-------------|
| **Phase 1: Evidence** | Shipped | SQLite evidence store, session hooks, `/interspect:correction`, reporting commands |
| **Phase 2: Overlays** | Partially shipped | Routing override chain F1-F5 (pattern detection, propose/approve, apply+canary+commit, status+revert, manual overrides) |
| **Phase 3: Autonomy** | Designed | Counterfactual shadow evaluation, privilege separation, eval corpus, prompt tuning |

---

## Now — Phase 2 Completion

Remaining Phase 2 work after F1-F5 shipped:

- **iv-2o6c** F4: Status display + revert for routing overrides
- **iv-6liz** F5: Manual routing override support
- **iv-88yg** Structured commit message format
- **iv-c2b4** `/interspect:disable` command
- **iv-g0to** `/interspect:reset` command
- **iv-bj0w** Conflict detection
- **iv-m6cd** Session-start summary injection

## Next — Adaptive Routing (iv-5ztam epic)

The primary strategic frontier. Evidence-driven agent selection — the flywheel that makes the system cheaper and better over time.

- **iv-003t** Global modification rate limiter
- **iv-0fi2** Circuit breaker
- **iv-5su3** Autonomous mode flag
- **iv-435u** Counterfactual shadow evaluation
- **iv-drgo** Privilege separation (proposer/applier)
- **iv-rafa** Meta-learning loop
- **iv-t1m4** Prompt tuning (Type 3) overlay-based
- **iv-izth** Eval corpus construction

## Later — Research & Integration

- **iv-x6by** Research: Adaptive profiling and dynamic rule evolution
- **iv-5ubkh** Evolve Interspect outcome data to drive adaptive routing (blocked by iv-5ztam)
- **iv-fl9gg** Research: Anti-Goodhart mechanisms for optimization
- **iv-ynbh** Agent trust and reputation scoring
- **iv-sisi** Interline statusline integration
- **iv-88cp2** Extract Interspect from Clavain into standalone plugin

## Bugs

- **Demarch-k1b** Swept verdicts attributed to sweeping session, not originating session
- **Demarch-cwj** `_interspect_next_seq` TOCTOU race in evidence insertion
- **Demarch-xx4** Bootstrap marker `/tmp/interstat-bootstrap` has no writer
