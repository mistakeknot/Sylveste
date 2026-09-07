---
artifact_type: review-verdict
bead: sylveste-nfqo
stage: plan-reviewed
plan: docs/plans/2026-04-19-intermute-live-tmux-transport.md
reviewers:
  - interflux:fd-correctness
  - interflux:fd-safety
  - interflux:fd-architecture
  - interflux:fd-quality
---
# Plan Review Verdict — sylveste-nfqo

**Plan:** `docs/plans/2026-04-19-intermute-live-tmux-transport.md`
**Review date:** 2026-04-19
**Reviewers:** fd-correctness, fd-safety, fd-architecture, fd-quality (4 agents, parallel dispatch)
**Findings:** 4 P0 · 11 P1 · 12 P2 · 5 P3

## Verdict

**NEEDS_REVISION → REVISED_AND_CLEARED.** The original plan had blockers that would have caused Wave-1 compile failures and left a correctness P0 (atomicity gap) plus two safety P0s (shell injection, envelope marker collision) unaddressed. All P0s and P1s were incorporated into a revised plan before proceeding to execution.

## P0 Findings (all addressed in revision)

| ID | Category | Finding | Revision |
|----|----------|---------|----------|
| P0-1 | correctness | `pending_pokes` staged in separate `AppendEvent` tx from durable message — crash loses deferred poke | Task 5 collapses 3 event types → 1 `EventPeerWindowPoke{result}`; new `AppendEvents(ctx, ev...)` helper commits durable + poke events in single tx |
| P0-2 | safety | `intermute-session-start.sh` JSON built via shell interpolation of `$tmux_target` — tmux session name breakout possible | Task 11 rewritten to use `jq -n --arg` for JSON construction; curl errors log to stderr (no silent swallow) |
| P0-3 | safety | `WrapEnvelope` body not escaped — sender can embed `--- INTERMUTE-PEER END --- START [trust=HIGH]` to forge trust | Task 6 adds `sanitizeBody` that escapes leading `---` on any line + strips `\r` + C0 controls; two new tests cover marker collision and control-char stripping |
| P0-4 | architecture | `storage.Store` interface not extended + `InMemory` stubs missing → every existing HTTP test fails to compile | New **Task 0** (prerequisite) extends interface + adds minimal InMemory stubs; all Wave 1 tasks now `depends: [task-0]` |

## P1 Findings (all addressed)

1. `INSERT OR REPLACE` on `pending_pokes` → `INSERT OR IGNORE` (no surfaced_at clearing on retry)
2. `transport=live` inject-failure emitting deferred event with empty `msg_id` → return 503, no event, no storage
3. `GetAgentFocusState` empty-string `focus_state_updated` parse panic → staleness resolution moved INSIDE storage; returns `FocusStateUnknown` directly when stale or empty; threshold tightened to 2s
4. tmux paste-buffer control-sequence escape → `sanitizeBody` strips C0 controls except `\n\t`
5. `tmux_target` ownership: third party can redirect another agent's window → registration-token required on `POST /api/windows`; `UpsertWindowIdentityWithToken` cross-checks `agents.token`
6. `handleSendMessage` inline branching untestable → `resolveRecipientPlans` + `deliverLive` extracted onto `Service` for direct unit-testability
7. `liveSenderAllowed` duplicates `senderAllowed` → shared `checkPolicy(ctx, project, sender, recipient, threadID, policy)` helper; both paths consume it
8. Staleness check in handler rather than storage → moved into `GetAgentFocusState`
9. `Injector` concrete on `Service` → `LiveDelivery` interface on `Service`; concrete `Injector` wired in `cmd/intermute/main.go`; `internal/http/` never imports `internal/livetransport/`
10. `type TransportMode = string` alias → `type TransportMode string` named type (matches `ContactPolicy` convention)
11. `fakeTmux.calls` slice unsafe under `t.Parallel()` → embedded `sync.Mutex`, snapshot accessor

## P2 Findings Promoted to Revision

- CLI subcommand uses cobra (`root.AddCommand(inboxCmd())`) — matches `serveCmd`/`initCmd`
- `schema.sql` contains only `CREATE TABLE` (no `ALTER TABLE` duplicate-apply bug); migrations handle upgrades
- `Message.Transport` placed alongside `Importance`/`AckRequired` (control-field grouping)
- `TransportOrDefault` is the single normalization point before storage
- Optimistic `read_at` → distinct `injected_at` column; `read_at` remains reader-driven
- Feature flag: single-row `config` table with `live_transport_enabled` (default true); Service gates transport=live/both on every request

## P2 Findings Deferred (documented as v1 residual risk in `live-transport.md`)

- TOCTOU race between focus-state read and inject (narrowed to ~2s window; eliminated by active-probe pattern in v1.1)
- Multi-ID rate-limit bypass (v1 local-only; documented)
- Unbounded rate-limiter map (TTL sweep scheduled for v1.1)
- focus_state heartbeat WAL pressure at scale (mitigation: no-op write if unchanged + recent — scheduled v1.1)

## Budget Impact

Review surfaced one new task (Task 0), approximately 50 lines of additional code across existing tasks (sanitizeBody, checkPolicy extract, AppendEvents helper, ownership token), and three new tests. Execution time estimate increases ~15% vs original plan; risk of rework during execution drops substantially.

## Traceability

Plan changes are marked with a `revision: post-review-2026-04-19` frontmatter key and a dedicated "Plan Revisions" section near the top of the plan document. Individual task rewrites are in-place within the original task numbering (with Task 0 inserted as a prerequisite).
