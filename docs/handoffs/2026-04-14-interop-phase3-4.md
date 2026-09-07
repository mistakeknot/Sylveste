---
date: 2026-04-14
session: 8430ca70
topic: interop Phase 3 shipped, Phase 4 planned
beads: [sylveste-xmav, sylveste-xfsr, sylveste-911m, sylveste-ykta, sylveste-m6hb, sylveste-jd6m, sylveste-irlf, sylveste-2l2x]
---

## Session Handoff — 2026-04-14 interop Phase 3 + Phase 4 sprint

### Directive
> Your job is to execute Phase 4 of interop (GitHub file sync). Start by `/clavain:sprint sylveste-911m --from-step execute`. Verify with `cd /home/mk/projects/Sylveste/interverse/interop && export PATH="/usr/local/go/bin:$PATH" && go test -race ./...`.
- Sprint bead: `sylveste-911m` — Steps 1-4 complete (brainstorm, strategy, plan, plan-review). Step 5 (execute) is next.
- Plan: `docs/plans/2026-04-13-github-file-sync.md` — amended with all P0/P1 findings from 2 rounds of flux-review
- Feature beads (children of 911m): `sylveste-ykta` (F1 entity correlation, P1), `sylveste-2l2x` (F5 ancestor versioning), `sylveste-m6hb` (F2 filesync module), `sylveste-jd6m` (F3 push webhook), `sylveste-irlf` (F4 reconciliation poll)
- Execution order: Phase A (F1 + F5 parallel) → Phase B (F2) → Phase C (F3 + F4 parallel)
- `bd close` from monorepo root only. Feature beads need `--force`.

### Dead Ends
- None this session — clean execution

### Context
- Phase 3 shipped this session: Notion adapter (`internal/adapters/notion/`) and GitHub Issues/PRs adapter (`internal/adapters/github/`). Both pass with race detector. 36 tests total.
- `WebhookRegistrar` interface added to `adapter/adapter.go` — daemon auto-mounts webhook handlers
- Flux-review (10 agents, 2 tracks) surfaced critical P0: EntityKey namespace mismatch (`fs:file:X` vs `github:file:owner/repo:X`) causes infinite ping-pong in CollisionWindow. Entity correlation table (F1) is the prerequisite for everything.
- AncestorStore migration requires table recreation (SQLite can't ALTER PRIMARY KEY). Plan specifies `PRAGMA user_version` guard + CREATE/INSERT/DROP/RENAME in transaction.
- Push webhook handler must pass raw body bytes for re-parsing (current `webhookPayload` struct lacks push fields). Plan amended.
- Reconciler capped at 10 content-fetches per tick with rate-limit budget check (`X-RateLimit-Remaining < 200` defers to next tick).
- interop repo: `/home/mk/projects/Sylveste/interverse/interop/` (no remote)
- Go: `export PATH="/usr/local/go/bin:$PATH"`
