---
date: 2026-04-04
session: 811384ae
topic: Ockham F1+F2 shipped
beads: [sylveste-0zr, sylveste-qd1]
---

## Session Handoff — 2026-04-04 Ockham F1+F2 shipped

### Directive
> Your job is to implement F3 (lib-dispatch.sh offset wiring, sylveste-4lx). Start by reading `os/Clavain/hooks/lib-dispatch.sh:189-207` — the Ockham offset slot goes between the lane-pause check (line 201) and perturbation (line 203). Verify with `cd os/Ockham && go test ./... -count=1`.

- Beads open: sylveste-4lx (F3), sylveste-32p (F4), sylveste-usj (F5), sylveste-q2k (F6), sylveste-fzt (F7)
- F3 is the integration bridge: Ockham writes `ockham_offset` to intercore state, lib-dispatch.sh reads them per dispatch cycle
- PRD acceptance criteria for F3: `docs/prds/2026-04-04-ockham-wave1-foundation.md` lines 66-74
- Prerequisite #1 from PRD: `ic state list` returns scope_ids only, not values — F3 must iterate `ic state get` per bead (O(N), N≈50)
- Fallback: F4 (ockham check + SessionStart hook) or F5 (Tier 1 INFORM signals) if F3 blocked on Clavain changes

### Dead Ends
- None this session — clean implementation run

### Context
- `go` binary not on default PATH in Claude Code Bash — use `export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"` before any go command
- Ockham has its own git repo at `os/Ockham/` — commits go there, not from monorepo root. Monorepo root only for docs/plans/reflections.
- `AuthorityState`/`AnomalyState` stubs live in `internal/authority/` and `internal/anomaly/` (their destination packages), NOT in `scoring/types.go` — this was a P1 caught in plan review to preserve dependency direction for Wave 2-3
- `Governor.New()` takes positional args `(intentStore, haltSentinel)` — will need a config struct when Wave 2-3 adds authority and anomaly stores
- `Validate()` returns `error` (via `errors.Join`), not `[]error` — this is now the project standard for multi-error validation in Go
- `runIntentSet` validates before every save path (both `--freeze` and `--theme`) — a QG correctness review caught the missing validation on the theme path
