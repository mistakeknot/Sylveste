---
date: 2026-04-20
session: b8c3c8ae
topic: intermute live tmux transport shipped
beads: [sylveste-nfqo, sylveste-mb3i, sylveste-aglf, sylveste-4cny, sylveste-nxfq, sylveste-hvmc, sylveste-zfsj]
---

## Session Handoff — 2026-04-20 intermute live tmux transport shipped

### Directive
> Your job is to pick the next `bd ready` item. Run `/clavain:route` with no args — it auto-discovers. Skip sylveste-nfqo (closed) and its 6 follow-ups (P2-P4) unless prioritizing them: sylveste-mb3i + sylveste-aglf are the highest-value (P2) and would improve every future Codex-dispatched sprint.
- **Closed**: sylveste-nfqo shipped at commits `core/intermute:7618bc8` + `Sylveste:b59c02c8`. Everything pushed to origin + beads Dolt remote.
- **Filed as follow-ups** (all open): sylveste-mb3i P2 bug (dispatch.sh 4xx surfacing), sylveste-aglf P2 feature (dispatch.sh build-env preflight), sylveste-4cny P3 task (orchestrate.py PASS/WARN/FAIL), sylveste-nxfq P3 feature (import-graph assertion), sylveste-hvmc P3 feature (live transport v1.5 active-probe), sylveste-zfsj P4 feature (live transport v2 cross-host).
- **Concurrent session warning**: refactory session `8de2734d` (bead sylveste-qdqr, auto-proceed authz) was active and committing to `core/intercore/pkg/authz/` + `os/Clavain/`. Zero file overlap with my work then — check their state before picking anything in those dirs.

### Dead Ends
- First orchestrator run returned "15/15 skipped (task-0 failed)" with no visible error. Root cause: Clavain's `routing.yaml` had `gpt-5.3-codex-xhigh` + `gpt-5.3-codex-spark-xhigh` for deep/fast tiers, and those models return HTTP 400 "not supported when using Codex with a ChatGPT account". Dispatch.sh swallowed the 400 silently (reported 0 tokens, 0 turns, exit 0). Fixed by switching every dispatch tier to `gpt-5.4` in `os/Clavain/config/routing.yaml` (memory `feedback_codex_model_gpt54.md` made permanent). Don't revert.
- Codex sandbox had no `go` on PATH — all 9 "orchestrator WARN" verdicts turned out to be false positives. `go` IS available at `/usr/local/go/bin/go`. Export `PATH="/usr/local/go/bin:$PATH"` before any manual go commands.
- `tmux has-session -t "session:0.0"` fails with "can't find window: 0" because this env has `base-index 1`. `ValidateTarget` now splits on `:` and `has-session` the session name only — don't revert that to the full target spec.
- `INSERT OR REPLACE` on `pending_pokes` clears `surfaced_at` and causes ghost redelivery. Must be `INSERT OR IGNORE`.
- `noopLiveDelivery.Deliver` returning `errors.New("live delivery not configured")` breaks `transport=both` tests; must return `nil`.

### Context
- **Auto-memory working preferences** updated this session: `feedback_codex_model_gpt54.md` (gpt-5.4 default across all Clavain dispatch tiers). Loaded every session from `MEMORY.md`.
- **Plan + review + reflect** all in git:
  - `/home/mk/projects/Sylveste/docs/plans/2026-04-19-intermute-live-tmux-transport.md` (2564 lines post-review)
  - `/home/mk/projects/Sylveste/docs/flux-review/2026-04-19-intermute-live-tmux-transport-plan-review.md`
  - `/home/mk/projects/Sylveste/docs/reflections/2026-04-19-intermute-live-tmux-transport-reflect.md` (34 substantive lines; full sprint lessons)
  - `/home/mk/projects/Sylveste/.clavain/quality-gates/synthesis.md` (QG findings)
- **Architecture boundary locked in**: `core/intermute/internal/http` imports `internal/livetransport` ONLY for the `LiveDelivery` interface (`service.go`, `handlers_domain.go`). `core.WindowTarget` + `core.WrapEnvelope` are the types/funcs shared with handlers. Do NOT add concrete `livetransport.Target` or `livetransport.WrapEnvelope` references in any non-test http file.
- **Feature-flag rollback path**: `UPDATE config SET live_transport_enabled = 0 WHERE id = 1` via SQLite directly, or via a new HTTP endpoint if that gets added. Read-per-request, no restart needed. Documented in `core/intermute/docs/live-transport.md`.
- **Known quality issue in CLI**: `fmt.Println` in `cmd/intermute/main.go:197+` is legitimate keygen output, not debug cruft — don't clean it up in a future pass.
- **tmux integration tests** require `go test -tags tmux_integration` — they spawn real tmux sessions on a scoped socket (`-L` flag). Not run by default `go test ./...`. CI needs to decide whether to run them.
- **Unrelated unresolved state in parent Sylveste repo**: `docs/handoffs/latest.md` had a merge conflict marker (UU) during this session from the refactory session. It's now plain `M` (they resolved it). Don't touch it unless you know what it is.
- **Dolt beads push** via `.beads/push.sh` needs TTY approval; bypass with `/home/mk/.local/bin/dolt push origin main` directly from `.beads/dolt/Sylveste/` (user has auto-proceed on bd push).
