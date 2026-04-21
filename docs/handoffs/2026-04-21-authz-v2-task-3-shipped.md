---
artifact_type: handoff
bead: sylveste-qdqr.28
date: 2026-04-21
predecessor: docs/handoffs/2026-04-21-authz-v2-tasks-1-2-shipped.md
status: task-3-shipped-at-step-5
---

# Session handoff — authz v2 Task 3 shipped (Step 5 in flight)

## Directive

> Continue `/clavain:sprint sylveste-qdqr.28` from **Step 5, Task 4** onward. Plan at `docs/plans/2026-04-21-auto-proceed-authz-v2.md` (r3, 985 lines). Tasks 1-3 committed and tests pass under `-race`. Next concrete move: implement the `clavain-cli policy token {issue,consume,delegate,revoke,list,show,verify}` subcommands in `os/Clavain/cmd/clavain-cli/authz_token.go` + tests. Wave 4 of the `.exec.yaml` manifest.

## What shipped this session

### Task 3 — `pkg/authz/token.go` + tests

**Commit** (sibling repo `core/intercore`, `main` at `ff83ab8`):
- `feat(authz): Task 3 — token primitives + lifecycle (sylveste-qdqr.28)`

**Artifacts (all in `core/intercore/`)**:
- `pkg/authz/token.go` — 620 lines. Types (`Token`, `IssueSpec`, `DelegateSpec`, `ListFilter`); 13 error sentinels; `ExitCode` + `ErrClass`; `CanonicalTokenPayload` + `SignToken` + `VerifyToken` (reuses `validateText` / `rejectControlChars` from `sign.go`); opaque `<ulid>.<sighex>` codec; `IssueToken`, `DelegateToken`, `ConsumeToken`, `RevokeToken`, `GetToken`, `ListTokens`.
- `pkg/authz/token_test.go` — 33 test funcs covering all r3-aligned scenarios (see below).
- `pkg/authz/token_faultinject_test.go` — `//go:build testfault` — the partial-failure test with `init()` that wires `consumeFaultHook` to read `CONSUME_FAULT_INJECT_AFTER_UPDATE=1`.
- `go.mod` / `go.sum` — added `github.com/oklog/ulid/v2 v2.1.1`. **Go 1.22 toolchain preserved** via `GOTOOLCHAIN=local` on `go get` + `go mod tidy`.

**Test status**:
- `go test ./pkg/authz/ -race` → PASS in 1.36s (default suite, 33 tests).
- `CONSUME_FAULT_INJECT_AFTER_UPDATE=1 go test -tags=testfault ./pkg/authz/ -run TestConsumeToken_PartialFailure_Atomic` → PASS.
- `go test ./internal/db/ -run TestMigration` → PASS (032/033/034 still green).

**r3 regression guards verified**:
- `TestCanonicalTokenPayload_GoldenFixtures` — byte-exact match against the three worked examples in `docs/canon/authz-token-payload.md`.
- `TestRevokeToken_CascadeFromRoot_NullRootToken` — r2 P0 fix: revoke a root whose `root_token IS NULL` still flags every descendant via the `WHERE id=? OR root_token=?` predicate with `target.id` bound to both positions.
- `TestRevokeToken_CascadeOnNonRoot_Refused` — r3 P1 fix: mid-chain cascade returns `ErrCascadeOnNonRoot` without writing. Confirmed zero rows flagged.
- `TestConsumeToken_RevokedExitsAuthFailure` — r3 P1 fix: `ExitCode(ErrRevoked) == 4` (auth-failure, hard-fail), NOT 2 (token-state fall-through).
- `TestConsumeToken_PartialFailure_Atomic` — fault-inject after UPDATE forces INSERT failure; deferred `tx.Rollback` restores token; zero orphan audit rows.
- `TestConsumeToken_Atomic_FirstWins` — N=8 concurrent consume; exactly 1 success, 7 `ErrAlreadyConsumed`.
- `TestDelegateToken_DepthCap_ConcurrentRace` — N=8 concurrent delegates against depth-3 parent; all fail with `ErrDepthExceeded`.
- `TestVerifyToken_RejectsMutation` — mutates each of 12 signed fields in turn; each mutation breaks verify. Pins the canonical-payload field set.

## Next concrete task — Task 4: `clavain-cli policy token ...`

### Files to create / modify (in `os/Clavain/` sibling repo)
- Create: `os/Clavain/cmd/clavain-cli/authz_token.go`
- Create: `os/Clavain/cmd/clavain-cli/authz_token_test.go`
- Modify: `os/Clavain/cmd/clavain-cli/authz.go` — extend `cmdPolicy` switch with a `case "token": return cmdPolicyToken(args[1:])`.

### Subcommands (per plan Task 4 §Step 3)
- `issue` — flags `--op --target --for --ttl --bead`; loads priv key via `authz.LoadPrivKey`; reads `$CLAVAIN_AGENT_ID` as `issuedBy`; calls `authz.IssueToken`; prints opaque string on stdout; records v1.5 audit row via existing `authz.Record`.
- `consume` — flags `--token` (fallback to `$CLAVAIN_AUTHZ_TOKEN`), `--expect-op`, `--expect-target`; loads pub key; reads `$CLAVAIN_AGENT_ID` as `callerAgentID`; calls `authz.ConsumeToken`; on success emits sentinel-wrapped `unset CLAVAIN_AUTHZ_TOKEN` for `eval`-consumption:
  ```
  # authz-unset-begin
  unset CLAVAIN_AUTHZ_TOKEN
  # authz-unset-end
  ```
- `delegate` — flags `--from --to --ttl`; populates `DelegateSpec{ParentID, CallerAgentID, ToAgentID, RequestedTTL}`.
- `revoke` — flags `--token --cascade --issued-since`.
- `list` — flags `--root --agent --op --status`; JSON or human output.
- `show` — `--token <id>`; full row + sig fingerprint + verify status + subtree.
- `verify` — `--token <opaque>`; exits 0 if sig verifies, 4 otherwise. Does NOT consume.

### Exit code contract
All handlers exit via `authz.ExitCode(err)`. Stderr on error: `ERROR <class>: <reason>` where `<class>` comes from `authz.ErrClass(err)`. Wrappers (Task 5) key off the exit code, never the sentinel string.

### Tests (`authz_token_test.go`)
One table per handler; each row exercises one exit class (0/1/2/3/4). Use a `tmp` intercore DB fixture (same pattern as the existing `authz_test.go` in `cmd/clavain-cli/`). Running the binary from within the test with `os/exec` is acceptable (the existing authz tests do this for the `policy sign` subcommand).

### Verify (from plan)
```bash
cd os/Clavain/cmd/clavain-cli
GOTOOLCHAIN=local go test -run 'TestPolicyToken' -v
~/.local/bin/clavain-cli policy token 2>&1 | head -1  # should print "Usage: policy token"
```

## Sprint state (as of this session close)

- **Bead**: `sylveste-qdqr.28`, status `in_progress`, phase label `phase:executing`, sprint=true.
- **Plan**: `docs/plans/2026-04-21-auto-proceed-authz-v2.md` (r3).
- **Progress**:
  - Step 1 Brainstorm ~ prior session
  - Step 2 Strategy ~ prior session
  - Step 3 Write Plan ✓ r1→r2→r3
  - Step 4 Plan Review ✓ 5-agent r1 + 3-agent r2
  - Step 5 Execute ◐ Tasks 1 ✓, 2 ✓, 3 ✓; Tasks 4-8 pending
  - Steps 6-10 pending

## Dead ends

- **`oklog/ulid/v2` is permissive about characters.** `Parse` only validates length (26 chars), NOT per-char Crockford alphabet membership. A 26-char string with non-base32 chars (`@`, `!`, `?`, space, reserved `U`) parses without error. This is fine for a token system because integrity is bound by signature verification — an "invalid-char ULID" will either not exist in the DB (→ `ErrNotFound`) or not have a valid signature (→ `ErrSigVerify`). But do not rely on `ulid.Parse` to reject malformed IDs; it only rejects wrong length. The `TestParseTokenString_ErrorClasses` subtests use `bad_ulid_short` / `bad_ulid_long` for length-based negatives.
- **`go get` without `GOTOOLCHAIN=local`** silently bumps the Go toolchain (1.22 → 1.25) and breaks the monorepo. Always set the env var for both `go get` AND `go mod tidy`. Confirmed during this session: the initial `go get github.com/oklog/ulid/v2@latest` succeeded but `go mod tidy` removed the dep (nothing imported it yet); after writing `token.go` the tidy re-added it. No toolchain drift.
- **Pre-staged plan files in the monorepo index.** This session found `A  docs/plans/2026-04-21-sylveste-ynh7-skill-listing-compact.{exec.yaml,md}` staged from a parallel session. Avoid `git commit` without explicit paths or you'll sweep another session's WIP into your handoff commit. Use `git commit <path>` for partial commits.

## Context gotchas carried forward

- **`core/intercore` is a sibling git repo** (gitignored at monorepo root). Commits for `pkg/authz/*` go inside `core/intercore/`, not the monorepo.
- **Pre-existing WIP in `core/intercore`** from parallel sessions: `contracts/cli/gate-check-result.json`, `internal/dispatch/dispatch.go`, `config/metrics.yaml`, `internal/dispatch/retry.go`, `internal/dispatch/retry_test.go`, and the `.DS_Store` / `cmd/ic/ic` artifacts. Do not touch.
- **`SetMaxOpenConns(1)`** is the intercore convention. Token consume and delegate transactions serialize naturally; the concurrent-race tests rely on this.
- **modernc.org/sqlite** does not support CTE-wrapped `UPDATE ... RETURNING`. Task 3 uses direct UPDATE + `RowsAffected()` + conditional re-SELECT. Task 4 handlers should follow the same pattern.
- **Auth-failure class includes `revoked` and `cascade-on-non-root`** (r3). When the CLI wrapper reads exit code 4, it hard-fails; it does NOT fall through to legacy policy. Tasks 4 + 5 must wire this consistently — a token-state-class sentinel accidentally entered into the exit-4 branch (or vice versa) breaks the operator-intent contract.

## Minimum-viable first session from here

Task 4's highest-leverage subset if short on time:
1. `cmdPolicyTokenIssue` + `cmdPolicyTokenConsume` handlers — these two are what Task 5's wrappers actually call at runtime; `delegate`/`revoke`/`list`/`show`/`verify` can follow.
2. One table-test per handler. Table rows: happy path, empty-spec validation, wrong-agent, wrong-expect, expired, revoked. Each row asserts both the returned error class AND the printed exit code.

That keeps the Task 5 wrapper integration unblocked. `delegate` + `revoke` + accessor commands are useful but not on the gate-wrapper critical path.

## Review findings for context

- `docs/research/flux-drive/2026-04-21-auto-proceed-authz-v2-20260421T0350/` — r1 findings (5 agents, 62 items).
- `docs/research/flux-drive/2026-04-21-auto-proceed-authz-v2-r2-20260421T0710/` — r2 re-review (3 agents; r3 addressed).

## Provenance

- Session: `07fdf48d-7ede-48c5-ac02-3ae0768f4b33`
- Predecessor handoff: `docs/handoffs/2026-04-21-authz-v2-tasks-1-2-shipped.md` (session `f8c560dc`)
- Tasks-1-2 canon docs shipped in monorepo commits `e6ef6fb8` + `ed4ffb58`.
- Task 2 shipped in `core/intercore` commit `0edb768`.
- Task 3 shipped in `core/intercore` commit `ff83ab8` (this session).
