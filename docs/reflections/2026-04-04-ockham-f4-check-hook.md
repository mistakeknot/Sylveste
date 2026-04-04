---
artifact_type: reflection
bead: sylveste-32p
stage: reflect
---

# F4: ockham check + SessionStart hook — Reflection

## What shipped

- `internal/signals/` package — SQLite persistence with error-class-aware recovery (corruption vs transient), schema migration path, conditional writes for concurrent safety
- `cmd/ockham/check.go` — CheckRunner with authority snapshot ingestion, halt sentinel reconstruction (atomic O_EXCL), 30-day re-confirmation with sanity guards, --dry-run
- SessionStart hook in Clavain with 5-minute TTL sentinel
- 11 new tests (signals package), all 35 Ockham tests passing

## What the review caught

The plan review (3 agents) found 2 P0s and 1 P1 before any code was written:
1. **P0: Don't shell out to `ic`** — read interspect JSON files directly. Eliminated a hidden binary dependency and timeout risk.
2. **P0: Delete-on-any-error wipes ratchet state** — distinguished corruption from SQLITE_BUSY. The quality gate caught this was still partially unguarded (ensureSchema path).
3. **P1: Premature Evaluator interface** — deferred to F5 when a second implementation exists.

The quality gate review caught 2 more issues in the implementation:
4. **P2: TOCTOU on halt reconstruction** — concurrent `ockham check` could re-halt after operator resume. Fixed with O_EXCL.
5. **P2: Unconditional reconfirm write** — resetting updated_at every run breaks age-based escalation. Fixed with conditional check.

## Lessons

- **Plan review ROI is highest for persistence code.** Both P0s were about data destruction — the kind of bug that doesn't surface in tests but causes 3 AM pages. The 2-minute review cost prevented hours of debugging.
- **Read files, don't shell out.** When the data source is a local JSON file, reading it directly is always better than invoking a CLI tool. No timeout, no binary dependency, no output format coupling.
- **Atomic file operations matter for multi-session tools.** O_EXCL is one line of code but prevents a class of race conditions where operator actions and automated checks conflict.

## What's next

F5 (sylveste-usj) builds on this: signal evaluators write to signals.db, authority snapshots feed the ratchet. The CheckRunner structure is ready — F5 adds evaluator methods, F6 extracts the Evaluator interface when two implementations exist.
