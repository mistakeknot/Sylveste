---
date: 2026-04-14
session: unknown
topic: Vision v5.0 + Ockham-Alwe bridge
beads: [sylveste-rbii, sylveste-3akj, sylveste-foui, sylveste-1a9t, sylveste-dkx7, sylveste-1py3, sylveste-01cu, sylveste-t6ti, sylveste-xefe, sylveste-tm6g, sylveste-ki2p, sylveste-ycck, sylveste-0ewu, sylveste-a72u]
---

## Session Handoff — 2026-04-14 Vision v5.0 + Ockham-Alwe Bridge

### Directive

> Your job is to execute the Ockham-Alwe observation bridge plan (sylveste-xefe). Start by reading `docs/plans/2026-04-14-ockham-alwe-observation-bridge.md`. Sprint is at Step 5 (Execute) — Steps 1-4 complete with plan review findings already incorporated.

- **Bead:** sylveste-xefe — in_progress, claimed. Sprint phase: plan-reviewed.
- **Plan:** `docs/plans/2026-04-14-ockham-alwe-observation-bridge.md` (14 tasks, 5 features)
- **Start with Task 0:** Move `os/Alwe/internal/observer/` → `os/Alwe/pkg/observer/` (prerequisite for cross-module import). Commit from `os/Alwe/`.
- **Then Task 0b:** Add `replace` directive to `os/Ockham/go.mod` for Alwe dependency.
- **Children:** sylveste-tm6g (F1), sylveste-ki2p (F2), sylveste-ycck (F3), sylveste-0ewu (F4), sylveste-a72u (F5)
- **Verify:** `cd os/Alwe && go test ./... -count=1` after Task 0, `cd os/Ockham && go test ./... -count=1` after each feature.

Fallback: If Alwe's observer API is insufficient (Timeline returns raw JSON, SearchSessions is session-level not event-level), the plan accounts for this — parse raw JSON in Ockham's wrapper, use session-level error ratio as proxy for F1.

### Dead Ends

- None for the bridge work (plan review caught issues before implementation).
- Vision flux-review: brainstorm review found 8 P0s, all structural (no demotion mechanism, aspirational-as-operational, hidden dependency chains). Fixed in the v5.0 text before the second review. The second review confirmed 0 new P0s from 3/4 tracks.

### Context

- **Alwe observer is `internal/`** — Go restricts cross-module imports of `internal/` packages. Task 0 moves it to `pkg/observer/`. This also requires updating Alwe's `internal/mcpserver/` imports.
- **`NewEvaluator` refactor is breaking.** Plan switches from variadic string to functional options. Must update `cmd/ockham/check.go` and all test call sites. Plan review P0-2 caught this.
- **Alwe `Timeline()` returns raw JSON string**, not structured types. `since` param is string `"24h"`, not `time.Duration`. Need `durationToString()` helper in Ockham wrapper.
- **Tool error rate is a proxy.** Exact tool-level error counting requires per-session JSONL parsing (expensive). F1 uses session-level error ratio as proxy. Exact counts deferred.
- **Go version mismatch:** Ockham 1.25, Alwe 1.24. Verify Alwe tests pass under 1.25 after Task 0.
- **Observation metrics are advisory only** — they influence INFORM severity but never independently trigger BYPASS. This is a design decision from the brainstorm.
- **Two other beads created this session:** sylveste-uzpo (interface evidence instrumentation, P2, depends on registry) and sylveste-i8gp (evidence pipeline wiring, P1, blocked on Factory Substrate sylveste-5qv9).
- **Vision v5.0 shipped** as commit 80f6f58e. Promotion Criteria Registry as 9561b249. Six interweave F5 fixes as a4b7272.
