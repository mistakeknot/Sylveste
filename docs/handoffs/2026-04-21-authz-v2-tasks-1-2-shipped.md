---
artifact_type: handoff
bead: sylveste-qdqr.28
date: 2026-04-21
predecessor: docs/handoffs/2026-04-21-authz-v2-tokens-delegation-handoff.md
status: tasks-1-2-shipped-at-step-5
---

# Session handoff — authz v2 Tasks 1-2 shipped (Step 5 in flight)

## Directive

> Continue `/clavain:sprint sylveste-qdqr.28` from **Step 5, Task 3** onward. Plan at `docs/plans/2026-04-21-auto-proceed-authz-v2.md` (r3, 985 lines). Tasks 1-2 are committed and tests pass. Next concrete move: implement `core/intercore/pkg/authz/token.go` + `token_test.go` per plan Task 3. Wave 3 in the `.exec.yaml` manifest.

## What shipped this session

### Sprint lineage
- `sylveste-qdqr` epic was closed prematurely at the end of v1.5; reopened and child bead `sylveste-qdqr.28` created for the v2 work (feature, P1). Phase now at `executing`.
- Plan drafted (Step 3), reviewed with 5-agent flux-drive (Step 4 r1 — 62 findings), revised (r2), re-reviewed with 3 agents (r2 caught 3 P1 regressions I introduced), revised again (r3). Plan is now substantively ready; Tasks 1-2 implement-and-verify the first wave.

### Task 1 — spec-lock canon docs
**Commits** (monorepo, `main`):
- `e6ef6fb8` docs(authz): v2 plan + exec manifest
- `ed4ffb58` docs(authz): Task 1 — spec-lock v2 token model + canonical payload

**Artifacts**:
- `docs/canon/authz-token-model.md` — 12-section normative spec (lifecycle, scope, delegation with linear-chain lock-in points for v2.x DAG migration, proof-of-possession at delegate + consume, atomic consume contract with 5-step pre-tx checks + transactional UPDATE+INSERT + failure classification priority, cascade revoke root-only + NULL-semantics discipline, same-project scope, relationship to v1.5 audit, threat-model delta, env-var hygiene, marker-deprecation 14-day decision gate).
- `docs/canon/authz-token-payload.md` — canonical byte sequence for `sig_version=2` (12-field list, encoding rules, 3 worked examples: root issue, depth-1 delegation, publish-scoped). Distinct from v1.5's `sig_version=1` payload (`authz-signing-payload.md`).
- `docs/brainstorms/2026-04-19-auto-proceed-authz-design.md` — backlink added after v2 section.
- `docs/handoffs/latest.md` — symlink updated (was pointing at a different handoff).

### Task 2 — migration 034
**Commit** (sibling repo `core/intercore`, `main` at `0edb768`):
- `feat(intercore): Task 2 — migration 034, authz_tokens table + cutover marker`

**Artifacts**:
- `core/intercore/internal/db/migrations/034_authz_tokens.sql` — reference DDL (docs-only per the `≥021` convention).
- `core/intercore/internal/db/db.go` — `currentSchemaVersion` + `maxSchemaVersion` bumped to 34; new `if currentVersion >= 33 && currentVersion < 34 { ... }` migration branch with CREATE TABLE IF NOT EXISTS + 4 indexes + INSERT OR IGNORE cutover marker.
- `core/intercore/internal/db/schema.sql` — authz_tokens + indexes + marker for fresh-DB path.
- `core/intercore/internal/db/db_test.go` — `TestMigration034AuthzTokens` verifies 16 columns, 4 indexes, CHECK constraints (depth in [0,3], agent_id non-empty), default sig_version=2, cutover marker idempotent across re-runs (fixed id `'migration-034-tokens-enabled'`), SchemaVersion()==34.

**Test status**: `go test ./internal/db/ -run TestMigration -v` → 032/033/034 all PASS. No regressions.

## Next concrete task — Task 3: `pkg/authz/token.go`

### Files to create
- `core/intercore/pkg/authz/token.go`
- `core/intercore/pkg/authz/token_test.go`

### Shape (from plan §Task 3)
- Types: `Token` struct (16 fields mirroring the DB row), `tokenSignedFields` list (12 fields for canonical payload — distinct from v1.5's 12).
- Primitives: `CanonicalTokenPayload`, `SignToken`, `VerifyToken`, `EncodeTokenString`, `ParseTokenString`.
- Error classes: 11 sentinel errors grouped by exit-code class (2/3/4). `ExitCode(err)` and `ErrClass(err)` mappings.
- Lifecycle: `IssueToken(db, priv, spec IssueSpec, now)`, `DelegateToken(db, priv, spec DelegateSpec, now)`, `ConsumeToken(db, pub, tokenStr, callerAgentID, expectOp, expectTarget, now)`, `RevokeToken(db, id, cascade, now)`.
- Accessors: `GetToken`, `ListTokens`.

### Key contracts from the canon doc
- **Atomic consume**: `BEGIN...COMMIT` wrapping UPDATE + authorizations INSERT. Pre-transaction: parse / load / verify-sig / caller-agent-mismatch / expect-mismatch. In-transaction: UPDATE with 5-AND WHERE (id + consumed_at IS NULL + revoked_at IS NULL + expires_at > now + agent_id match). On RowsAffected=0: re-SELECT to classify (revoked > consumed > expired priority).
- **Cascade revoke root-only**: `RevokeToken(db, id, cascade=true)` first verifies `parent_token IS NULL AND root_token IS NULL`; else `ErrCascadeOnNonRoot`. Then `UPDATE ... WHERE (id=? OR root_token=?) AND revoked_at IS NULL` with `target.id` bound to both positions.
- **Delegate POP**: `spec.CallerAgentID == parent.AgentID` → else `ErrProofOfPossession`. Depth cap re-SELECTed inside the insert transaction (race close).
- **Fault-injection test**: `TestConsumeToken_PartialFailure_Atomic` uses `// +build testfault` hook + `CONSUME_FAULT_INJECT_AFTER_UPDATE=1` to force INSERT failure after UPDATE commits; assert tx.Rollback leaves the token still consumable.

### Dependency to add
- `github.com/oklog/ulid/v2` — needed for ULID generation. Add via:
```bash
cd core/intercore
GOTOOLCHAIN=local go get github.com/oklog/ulid/v2@latest
GOTOOLCHAIN=local go mod tidy
```
**GOTOOLCHAIN=local is mandatory** — a bare `go get` can silently bump the toolchain 1.22 → 1.25+ and break the monorepo (prior session hit this).

### Test list (r3-aligned)
~30 tests; notable ones:
- `TestCanonicalTokenPayload_GoldenFixtures` — matches the 3 canon examples byte-for-byte.
- `TestConsumeToken_Atomic_FirstWins` — N=8 goroutines race; exactly 1 success.
- `TestConsumeToken_PartialFailure_Atomic` — fault-inject; token still consumable after rollback.
- `TestConsumeToken_CallerAgentMismatch` — ErrCallerAgentMismatch → exit 4.
- `TestDelegateToken_DepthCap_ConcurrentRace` — two concurrent delegates against depth=2 parent can't both succeed.
- `TestRevokeToken_CascadeFromRoot_NullRootToken` — the r2 P0 fix; revoke root with NULL root_token still flags all descendants.
- `TestRevokeToken_CascadeOnNonRoot_Refused` — r3 fix; mid-chain cascade refused with ErrCascadeOnNonRoot.
- `TestConsumeToken_RevokedExitsAuthFailure` — r3 fix; consume revoked → ExitCode returns 4, not 2.
- `TestExitCode_Mapping` — table-driven; every Err → expected exit class.

## Sprint state (as of this session close)

- **Bead**: `sylveste-qdqr.28`, status `in_progress`, phase label `phase:executing`, sprint=true.
- **Plan artifact**: `docs/plans/2026-04-21-auto-proceed-authz-v2.md` registered.
- **Progress**:
  - Step 1 Brainstorm ~ satisfied by handoff + brainstorm.
  - Step 2 Strategy ~ satisfied by handoff.
  - Step 3 Write Plan ✓ r1 → r2 → r3 revisions.
  - Step 4 Plan Review ✓ 5-agent r1 + 3-agent r2 re-review.
  - Step 5 Execute ◐ Tasks 1 ✓, 2 ✓; Tasks 3-8 pending.
  - Steps 6-10 pending.

## Gotchas carried forward

- **`core/intercore` is a sibling git repo** (gitignored by monorepo root). Commits land there, not in monorepo. Same pattern as `os/Clavain`.
- **`GOTOOLCHAIN=local` is mandatory** for any `go get` or `go mod tidy`.
- **`SetMaxOpenConns(1)` is the intercore convention** — consume transactions serialize naturally under the single connection.
- **modernc.org/sqlite** does NOT support CTE-wrapped `UPDATE ... RETURNING`. Use direct `UPDATE ... WHERE ...` + `RowsAffected()` (Task 3's consume uses this).
- **Pre-existing WIP in `core/intercore`** from prior sessions: `contracts/cli/gate-check-result.json`, `internal/dispatch/dispatch.go`, `config/metrics.yaml`, `internal/dispatch/retry.go`. Do not touch — user's work.
- **Auth-failure class includes `revoked` and `cascade-on-non-root`** (r3 change). Previously revoked was token-state (exit 2, fall-through); r3 elevated it to exit 4 (hard-fail) because operator revoke intent outweighs legacy policy permission.

## Review findings for context

- `docs/research/flux-drive/2026-04-21-auto-proceed-authz-v2-20260421T0350/` — r1 findings (5 agents, 62 items).
- `docs/research/flux-drive/2026-04-21-auto-proceed-authz-v2-r2-20260421T0710/` — r2 re-review (3 agents; caught the 3 P1 regressions r2 introduced; r3 fixes them).

## Minimum-viable first session from here

If the next session is short, Task 3's highest-leverage subset is:
1. Add the ULID dep + create `token.go` with types + `CanonicalTokenPayload` + `SignToken` + `VerifyToken` + `EncodeTokenString` + `ParseTokenString`.
2. Golden-fixture test matching `authz-token-payload.md` examples byte-for-byte.

That anchors the signing path. Lifecycle functions (`IssueToken`/`DelegateToken`/`ConsumeToken`/`RevokeToken`) can come in the next segment of Task 3. The canon payload is the load-bearing piece; once its bytes are locked in, everything else builds on it.
