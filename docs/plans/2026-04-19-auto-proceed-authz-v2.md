---
artifact_type: plan
bead: sylveste-qdqr
stage: design
scope: v2 — authorization tokens + delegation chains (push-model authorization)
source_brainstorm: docs/brainstorms/2026-04-19-auto-proceed-authz-design.md
source_synthesis: docs/research/flux-drive/2026-04-19-auto-proceed-authz-design-20260419T0239/SYNTHESIS.md
prerequisite: docs/plans/2026-04-19-auto-proceed-authz-v1.5.md
---

# Auto-proceed authorization framework — v2 implementation plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-qdqr (reopen if closed)
**Goal:** Add a push-model authorization token layer on top of v1's pull-model policy engine so (a) user-issued tokens let specific ops auto-proceed without re-deriving approval from policy at op time, and (b) multi-agent delegation (Claude → codex → …) carries authority through a signed chain with atomic single-use semantics and cascading revocation. Pull-model remains the fallback when no token is presented.

**Architecture:** New `authz_tokens` table (migration 034) holds signed tokens with TTL, parent/root pointers, and a `consumed_at` column. A token carries the same signed payload semantics as v1.5 authorization rows. At op time, gates check for a presented token (via `--authz=<id>` or `CLAVAIN_AUTHZ_TOKEN` env): if present and consumable, gate runs the op, atomically consumes the token, and writes a linked audit row. If no token or consume fails, gate falls back to `policy check` (v1 pull-model). Delegation requires proof-of-possession: the caller's `agent_id` must match the parent token's `agent_id`. Linear chain, depth ≤ 3; runtime is chain-only (schema is DAG-ready via `root_token` if evidence shifts later).

**Trust boundary:** Tokens inherit the v1.5 tamper-evident-post-write claim for the `authz_tokens` table. An attacker with write access to `intercore.db` and the signing key can forge tokens; without the key, direct SQL mutations are detected by `authz token verify`. Stolen (but not revoked) tokens remain a real risk until their TTL expires — short TTLs (default 15 min, max 1 day) + cascade revoke are the primary mitigations. Documented in `docs/canon/authz-token-trust-model.md`.

**Tech Stack:** Go (intercore + clavain-cli), `crypto/ed25519`, SQLite (migration 034), oklog/ulid for token IDs (sortable, 128-bit collision-resistant), Bash (gate wrapper extension).

**Prior Learnings:**
- v1.5 landed Ed25519 signing + key management in `pkg/authz`. Reuse — tokens sign with the same project key.
- v1.5 defined canonical payload encoding in `docs/canon/authz-signing-payload.md`. Extend that spec; don't invent a parallel one for tokens.
- `policy record` in v1 writes to `authorizations` table; tokens write a *linked* audit row there via a new `token_id` column (migration 034 adds this column alongside the new table).
- ULIDs are sortable-by-time — use them over UUIDv4 so `ORDER BY id` is meaningful for audit pagination.
- Codex shells out via `core/intercore/internal/codex/` adapters. Token plumbing to sub-agents has two surface options: file-at-known-path (simple, discoverable) vs env var (transient, harder to accidentally commit). Plan pins the env-var path with a documented file fallback for agents that cannot inherit env.

---

## Must-Haves

**Truths:**
- `clavain-cli policy token issue --op=bead-close --target=sylveste-xyz --agent=codex-<id> --ttl=15m` prints a ULID to stdout and writes a signed row to `authz_tokens`.
- A gate wrapper invoked with `CLAVAIN_AUTHZ_TOKEN=<id>` consumes the token (atomic) and proceeds — exit 0 — without consulting policy.
- A second invocation with the same token exits 2 (`already-consumed`), not 0.
- An expired token exits 3 (`expired`); an unknown token exits 4 (`not-found`).
- `policy token delegate --from=<parent> --to=<agent-id>` by an agent whose own identity does NOT match `parent.agent_id` fails with a proof-of-possession error; a matching caller succeeds and produces a child token with `parent_token=<parent>` and `root_token` inherited.
- `policy token revoke --token=<root> --cascade` marks every descendant consumed-with-reason-revoked in one UPDATE via the `root_token` index.
- `policy audit --since=1d --include-tokens` shows both consumed-token audit rows AND policy-only rows, with `token_id` populated where applicable.
- `policy token compact --older-than=90d` moves expired-and-consumed tokens to a summary row; verification of live tokens remains intact.

**Artifacts:**
- `core/intercore/internal/db/migrations/034_authz_tokens.sql` — `authz_tokens` table + `authorizations.token_id` column + indexes.
- `core/intercore/pkg/authz/tokens.go` — `Issue`, `Consume`, `Delegate`, `Revoke`, `Verify`, token-payload canonical encoding.
- `core/intercore/pkg/authz/tokens_test.go` — covers atomic-consume races, proof-of-possession, cascade revoke, clock-skew tolerance.
- `os/Clavain/cmd/clavain-cli/authz.go` — `policy token {issue,delegate,consume,revoke,show,list,verify,compact}` handlers.
- `os/Clavain/scripts/gates/_common.sh` — `gate_consume_token` helper; wrappers accept `CLAVAIN_AUTHZ_TOKEN` with priority over policy-check fallback.
- `docs/canon/authz-token-trust-model.md` — tamper-evident claim, TTL rationale, stolen-token scenarios.
- `docs/canon/authz-token-payload.md` — canonical signed payload for tokens (extends signing-payload.md).
- `docs/canon/authz-delegation-semantics.md` — proof-of-possession, chain depth, cascade revoke, what DAG means if/when enabled.

**Key Links:**
- Gate flow: `CLAVAIN_AUTHZ_TOKEN` set? → `gate_consume_token` → op on success, else `policy check` fallback.
- Audit: `policy record` gains an optional `--token-id=<ulid>` flag (populates the new column); `policy audit` joins tokens on that column when `--include-tokens`.
- Sub-agent plumbing: Claude-originated codex invocations export `CLAVAIN_AUTHZ_TOKEN` into the child process env via the existing codex adapter. No filesystem drop by default.

---

## Task 1: Spec-lock round — token trust model + payload + delegation semantics (no code)

**Files:**
- Create: `docs/canon/authz-token-trust-model.md`
- Create: `docs/canon/authz-token-payload.md`
- Create: `docs/canon/authz-delegation-semantics.md`
- Modify: `docs/brainstorms/2026-04-19-auto-proceed-authz-design.md:~230` (backlink)

**Step 1: `authz-token-trust-model.md`** pins:
(a) tamper-evident inheritance from v1.5 (same key, same verify semantics),
(b) stolen-token window bounded by TTL (default 15m, max 1d, configurable per rule),
(c) cascade-revoke as the lever when a root agent is compromised,
(d) explicit non-goals: does not prevent direct-DB token insertion by a holder of the signing key; does not survive a host compromise.

**Step 2: `authz-token-payload.md`** extends `authz-signing-payload.md` with the token-specific field set: `id|op_type|target|agent_id|bead_id|delegate_to|expires_at|issued_by|parent_token|root_token|depth|sig_version|created_at`. NULLs as empty string, LF-delimited, NFC, signed with Ed25519. Include ≥3 worked examples: (i) root token issued by user, (ii) child token delegated from a parent, (iii) depth-3 terminal token.

**Step 3: `authz-delegation-semantics.md`** pins:
- Linear chain, max depth 3 (CHECK constraint + runtime reject).
- Proof-of-possession at delegate time: caller's `agent_id` == parent's `agent_id`.
- `root_token` denormalized from the root's own id (root.root_token = root.id).
- Cascade revoke is ONE UPDATE keyed by `root_token`; atomic against concurrent consume.
- DAG runtime explicitly out of scope; schema stays DAG-ready if evidence shifts.

**Step 4: Commit**
```bash
git add docs/canon/authz-token-trust-model.md docs/canon/authz-token-payload.md docs/canon/authz-delegation-semantics.md docs/brainstorms/2026-04-19-auto-proceed-authz-design.md
git commit -m "docs(authz): spec-lock v2 token trust model + payload + delegation (sylveste-qdqr)"
```

<verify>
- run: `grep -c '^### Example' docs/canon/authz-token-payload.md`
  expect: contains "3"
- run: `test -f docs/canon/authz-token-trust-model.md && test -f docs/canon/authz-delegation-semantics.md`
  expect: exit 0
</verify>

---

## Task 2: Migration 034 — `authz_tokens` table + `authorizations.token_id` link column

**Files:**
- Create: `core/intercore/internal/db/migrations/034_authz_tokens.sql`
- Modify: `core/intercore/internal/db/db_test.go`

**Step 1: Migration**
```sql
CREATE TABLE IF NOT EXISTS authz_tokens (
  id            TEXT PRIMARY KEY,            -- ULID, sortable by time
  op_type       TEXT NOT NULL,
  target        TEXT NOT NULL,
  agent_id      TEXT NOT NULL CHECK(length(trim(agent_id)) > 0),
  bead_id       TEXT,
  delegate_to   TEXT,
  expires_at    INTEGER NOT NULL,
  consumed_at   INTEGER,
  consumed_by   TEXT,                        -- op-id or "revoked"
  issued_by     TEXT NOT NULL,               -- agent id or "user"
  parent_token  TEXT REFERENCES authz_tokens(id) ON DELETE RESTRICT,
  root_token    TEXT NOT NULL,               -- self-id for root tokens
  depth         INTEGER NOT NULL DEFAULT 0 CHECK (depth >= 0 AND depth <= 3),
  sig_version   INTEGER NOT NULL DEFAULT 1,
  signature     BLOB NOT NULL,
  created_at    INTEGER NOT NULL
);

CREATE INDEX tokens_by_root     ON authz_tokens(root_token, consumed_at);
CREATE INDEX tokens_by_agent    ON authz_tokens(agent_id, created_at DESC);
CREATE INDEX tokens_by_bead     ON authz_tokens(bead_id, created_at DESC) WHERE bead_id IS NOT NULL;
CREATE INDEX tokens_unconsumed  ON authz_tokens(expires_at) WHERE consumed_at IS NULL;

-- Link column on the audit table so `policy audit --include-tokens` can join.
ALTER TABLE authorizations ADD COLUMN token_id TEXT REFERENCES authz_tokens(id);
CREATE INDEX authz_by_token ON authorizations(token_id) WHERE token_id IS NOT NULL;
```

**Step 2: Tests** — assert table shape (14 columns), 4 indexes, the `CHECK (depth ≤ 3)` constraint rejects `depth=4`, the FK on `parent_token` rejects unknown parent IDs, and the `authorizations.token_id` column is present with the matching index.

**Step 3: Run — expect FAIL. Step 4: Add migration; re-run — expect PASS.**

**Step 5: Commit**
```bash
git add core/intercore/internal/db/migrations/034_authz_tokens.sql core/intercore/internal/db/db_test.go
git commit -m "feat(intercore): add authz_tokens table + authorizations.token_id (migration 034, sylveste-qdqr)"
```

<verify>
- run: `cd core/intercore && go test ./internal/db/ -run TestMigration034 -v`
  expect: exit 0
</verify>

---

## Task 3: Token primitives in `pkg/authz`

**Files:**
- Create: `core/intercore/pkg/authz/tokens.go`
- Create: `core/intercore/pkg/authz/tokens_test.go`

**Step 1: Types**
```go
package authz

type Token struct {
    ID            string
    OpType        string
    Target        string
    AgentID       string
    BeadID        string
    DelegateTo    string
    ExpiresAt     time.Time
    ConsumedAt    *time.Time
    ConsumedBy    string
    IssuedBy      string
    ParentToken   string
    RootToken     string
    Depth         int
    SigVersion    int
    Signature     []byte
    CreatedAt     time.Time
}

type IssueArgs struct {
    OpType, Target, AgentID, BeadID, IssuedBy string
    TTL                                        time.Duration
    Parent                                     *Token // nil for root tokens
}

func Issue(db *sql.DB, priv ed25519.PrivateKey, args IssueArgs) (*Token, error)
func Consume(db *sql.DB, tokenID, consumedBy string, now time.Time) (*Token, error)
func Delegate(db *sql.DB, priv ed25519.PrivateKey, parent *Token, callerAgentID, delegateTo string, ttl time.Duration) (*Token, error)
func Revoke(db *sql.DB, tokenID string, cascade bool) (int, error) // returns rows affected
func LoadToken(db *sql.DB, tokenID string) (*Token, error)
func VerifyToken(pub ed25519.PublicKey, t *Token) bool
```

**Step 2: Atomic consume** — the SQL that matters:
```go
const consumeSQL = `
UPDATE authz_tokens
   SET consumed_at = ?, consumed_by = ?
 WHERE consumed_at IS NULL
   AND expires_at > ?
   AND id = ?`

res, err := db.ExecContext(ctx, consumeSQL, now, consumedBy, now, tokenID)
n, _ := res.RowsAffected()
if n == 0 {
    // Disambiguate: was it expired, already-consumed, or not-found?
    // One follow-up SELECT to classify — acceptable because the hot
    // path (success) is the single UPDATE.
    return nil, classifyConsumeMiss(db, tokenID, now)
}
```
`classifyConsumeMiss` returns one of `ErrTokenAlreadyConsumed`, `ErrTokenExpired`, `ErrTokenNotFound`.

**Step 3: Proof-of-possession in Delegate**
```go
if parent.AgentID != callerAgentID {
    return nil, fmt.Errorf("proof-of-possession failed: caller %q != parent.agent_id %q", callerAgentID, parent.AgentID)
}
if parent.Depth+1 > 3 {
    return nil, fmt.Errorf("delegation chain would exceed max depth 3")
}
// Signature on parent must verify, or refuse to delegate.
if !VerifyToken(pub, parent) { ... }
```

**Step 4: Cascade revoke**
```go
const revokeCascadeSQL = `
UPDATE authz_tokens
   SET consumed_at = ?, consumed_by = 'revoked'
 WHERE consumed_at IS NULL
   AND root_token = (SELECT root_token FROM authz_tokens WHERE id = ?)`
```
Single UPDATE; returns `rows_affected`.

**Step 5: Tests** — table-driven, including:
```go
TestIssue_RootTokenHasSelfRoot
TestIssue_ExpiresAtInFutureOnly
TestConsume_Atomic_SingleUseWinsExactlyOnce
TestConsume_RejectsExpired
TestConsume_RejectsAlreadyConsumed
TestConsume_RejectsNotFound
TestDelegate_RequiresProofOfPossession
TestDelegate_RejectsDepth4
TestDelegate_InheritsRootTokenFromParent
TestDelegate_RejectsConsumedParent      // can't delegate from a consumed token
TestRevoke_CascadesByRootToken
TestRevoke_SkipsAlreadyConsumed
TestVerifyToken_DetectsMutation
TestConsume_ClockSkewTolerance_5min     // matches v1 evaluator tolerance
```

Parallelism test for atomic consume:
```go
func TestConsume_RaceSingleWinner(t *testing.T) {
    tok := issueTestToken(t, db, ttl=10*time.Minute)
    var wg sync.WaitGroup
    winners := atomic.Int32{}
    for i := 0; i < 50; i++ {
        wg.Add(1)
        go func() { defer wg.Done()
            if _, err := Consume(db, tok.ID, "race", time.Now()); err == nil {
                winners.Add(1)
            }
        }()
    }
    wg.Wait()
    require.Equal(t, int32(1), winners.Load())
}
```

**Step 6: Commit**
```bash
git add core/intercore/pkg/authz/tokens.go core/intercore/pkg/authz/tokens_test.go
git commit -m "feat(authz): token primitives — issue, consume, delegate, revoke, verify (sylveste-qdqr)"
```

<verify>
- run: `cd core/intercore && go test ./pkg/authz/ -run 'TestIssue|TestConsume|TestDelegate|TestRevoke|TestVerifyToken' -v`
  expect: exit 0
- run: `cd core/intercore && go test -race ./pkg/authz/ -run TestConsume_RaceSingleWinner`
  expect: exit 0
</verify>

---

## Task 4: `clavain-cli policy token` subcommand group

**Files:**
- Modify: `os/Clavain/cmd/clavain-cli/authz.go` (add `cmdPolicyToken` + 8 sub-handlers)
- Modify: `os/Clavain/cmd/clavain-cli/authz_test.go`

**Step 1: Handlers + exit-code contract**
```go
func cmdPolicyTokenIssue(args []string) error    // prints ULID to stdout
func cmdPolicyTokenDelegate(args []string) error
func cmdPolicyTokenConsume(args []string) error  // exit 0 ok, 2 consumed, 3 expired, 4 not-found
func cmdPolicyTokenRevoke(args []string) error   // --cascade cascades via root_token
func cmdPolicyTokenShow(args []string) error     // human-readable
func cmdPolicyTokenList(args []string) error     // --agent, --bead, --unconsumed
func cmdPolicyTokenVerify(args []string) error   // signature + chain walk
func cmdPolicyTokenCompact(args []string) error  // --older-than=90d archive
```
Dispatcher gets a new `case "token": return cmdPolicyToken(rest)` inside the existing `cmdPolicy` switch.

**Step 2: Sentinel errors** (mirror v1):
```go
var (
    ErrTokenAlreadyConsumed = errors.New("token: already consumed")
    ErrTokenExpired         = errors.New("token: expired")
    ErrTokenNotFound        = errors.New("token: not found")
)
```
Main-dispatch translates these to exit 2/3/4 respectively.

**Step 3: Tests**
```go
TestPolicyTokenIssue_PrintsULIDOnStdout
TestPolicyTokenConsume_ExitCodes
TestPolicyTokenDelegate_ProofOfPossession
TestPolicyTokenRevoke_Cascade
TestPolicyTokenList_UnconsumedFilter
TestPolicyTokenCompact_ArchivesOldConsumed
```

**Step 4: Commit**
```bash
git add os/Clavain/cmd/clavain-cli/authz.go os/Clavain/cmd/clavain-cli/authz_test.go
git commit -m "feat(clavain-cli): policy token {issue,delegate,consume,revoke,...} (sylveste-qdqr)"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && go test -run 'TestPolicyToken' -v`
  expect: exit 0
</verify>

---

## Task 5: Gate wrapper integration — `CLAVAIN_AUTHZ_TOKEN` priority path

**Files:**
- Modify: `os/Clavain/scripts/gates/_common.sh` (add `gate_consume_token`)
- Modify: `os/Clavain/scripts/gates/{bead-close,git-push-main,bd-push-dolt,ic-publish-patch}.sh`
- Modify: `os/Clavain/scripts/gates/gates-smoke_test.sh` (token path smoke)

**Step 1: `_common.sh` helper**
```bash
# gate_consume_token <op> <target>
# If CLAVAIN_AUTHZ_TOKEN is set, try to consume it. On success, sets
# GATE_MODE=auto + GATE_POLICY_MATCH=token:<id> and returns 0 so the
# caller proceeds with the op without calling policy check. On any
# failure, returns non-zero so the caller falls back to pull-model.
gate_consume_token() {
  local op="$1" target="$2"
  [[ -z "${CLAVAIN_AUTHZ_TOKEN:-}" ]] && return 1
  local token="$CLAVAIN_AUTHZ_TOKEN"
  local rc=0
  clavain-cli policy token consume \
    --token="$token" \
    --op="$op" \
    --target="$target" \
    --consumer="$(gate_resolve_agent)" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) GATE_MODE=auto; GATE_POLICY_MATCH="token:${token}"; export GATE_MODE GATE_POLICY_MATCH; return 0 ;;
    2) echo "policy: token already consumed" >&2; return 2 ;;
    3) echo "policy: token expired" >&2; return 3 ;;
    4) echo "policy: token not found" >&2; return 4 ;;
    *) echo "policy: token consume failed (rc=${rc})" >&2; return "$rc" ;;
  esac
}
```

**Step 2: Wrapper update** — at top of each wrapper, before `gate_check`:
```bash
if gate_consume_token <op> <target>; then
  # token path: proceed with op immediately
  :  # GATE_MODE already set
else
  # fall back to pull-model policy check
  rc=0
  gate_check <op> "${check_flags[@]}" >/dev/null || rc=$?
  gate_decide_mode "$rc" <op>
fi
```
`gate_record` then writes an audit row with `--token-id="${CLAVAIN_AUTHZ_TOKEN:-}"` so `policy audit --include-tokens` can reconstruct the chain.

**Step 3: Smoke test extension** — exercise both paths:
1. With `CLAVAIN_AUTHZ_TOKEN` set to a freshly-issued token → wrapper consumes, op runs, audit row has `token_id` populated.
2. Same token again → exit non-zero (already-consumed); wrapper either falls back to pull-model or aborts.
3. Expired token → wrapper falls back, not fails outright.

**Step 4: Commit**
```bash
git add os/Clavain/scripts/gates/
git commit -m "feat(authz): gates prefer CLAVAIN_AUTHZ_TOKEN, fall back to policy check (sylveste-qdqr)"
```

<verify>
- run: `bash os/Clavain/scripts/gates/gates-smoke_test.sh`
  expect: contains "PASS: token-path" and "PASS: fallback"
</verify>

---

## Task 6: Sub-agent token plumbing (Claude → codex export path)

**Files:**
- Modify: `core/intercore/internal/codex/` (adapter — confirm exact path during task)
- Create: `core/intercore/pkg/authz/child_env.go` (small helper: `TokenEnvVar`, `WithTokenEnv`)
- Modify: `os/Clavain/skills/executing-plans/SKILL.md` (Step 2A codex dispatch: export token when present)
- Modify: `docs/canon/authz-delegation-semantics.md` (env-var handoff spec)

**Step 1: Helper**
```go
// Package authz
const TokenEnvVar = "CLAVAIN_AUTHZ_TOKEN"

// WithTokenEnv returns a copy of env with CLAVAIN_AUTHZ_TOKEN set to token.
// Strips any prior CLAVAIN_AUTHZ_TOKEN value to avoid inheriting stale state.
func WithTokenEnv(env []string, token string) []string
```

**Step 2: Codex dispatcher integration** — when Claude dispatches a task to codex and the flow holds an issued token (`policy token issue --agent=<codex-id>` output), the adapter sets `CLAVAIN_AUTHZ_TOKEN` in the child process env. This is the ONLY supported transfer path in v2; documented to forbid filesystem drops (no `.clavain/pending-token`), which would be a security footgun (world-readable by default).

**Step 3: `/clavain:interserve` + `executing-plans` Step 2A** — Claude issues a per-sub-op token (via `clavain-cli policy token issue`) with `agent=<codex-id>` and `ttl=5m`, then exports it before dispatch. Documented in SKILL.md.

**Step 4: Delegation-semantics canon** gains an explicit "env-var handoff" section pinning CLAVAIN_AUTHZ_TOKEN as the only transfer channel and naming what isn't supported (stdin, files, args).

**Step 5: Commit**
```bash
git add core/intercore/pkg/authz/child_env.go core/intercore/internal/codex/ os/Clavain/skills/executing-plans/SKILL.md docs/canon/authz-delegation-semantics.md
git commit -m "feat(authz): CLAVAIN_AUTHZ_TOKEN env plumbing for Claude→codex dispatch (sylveste-qdqr)"
```

<verify>
- run: `cd core/intercore && go test ./pkg/authz/ -run TestWithTokenEnv -v`
  expect: exit 0
- run: `grep -c CLAVAIN_AUTHZ_TOKEN os/Clavain/skills/executing-plans/SKILL.md`
  expect: contains at least "1"
</verify>

---

## Task 7: Audit retention — `policy token compact` + scheduled sweep

**Files:**
- Modify: `os/Clavain/cmd/clavain-cli/authz.go` (full `policy token compact` impl)
- Create: `os/Clavain/hooks/authz-compact.sh` (weekly SessionEnd hook)
- Modify: `os/Clavain/.claude-plugin/plugin.json` (register hook if matches convention)
- Create: `docs/canon/authz-retention.md`

**Step 1: `compact` semantics**
- Raw tokens consumed > `--older-than` (default 90d) AND their audit rows are moved to a `authz_rollup` summary table (month-keyed, counts by op_type + consumer).
- Live (unconsumed, unexpired) tokens never touched.
- `policy audit --include-rollup` joins the rollup table for aggregate queries.
- Cascade revokes don't count as "consumed for compaction purposes" — revoked tokens retained full-fidelity for 1 year (breach-forensics window), documented.

**Step 2: Hook** — SessionEnd cron-like hook runs compact weekly (checks `last_compact_at` timestamp in the DB's `config` singleton; skips if < 7d ago). Idempotent, safe to over-run.

**Step 3: Retention canon** — document the 90d default, 1y for revoked, rollup shape, and how to restore detail from git+beads if forensics need more than the rollup.

**Step 4: Tests**
```go
TestCompact_MovesOldConsumed
TestCompact_LeavesUnconsumedUntouched
TestCompact_RetainsRevokedFor1Year
TestAuditWithRollup_JoinsSummary
```

**Step 5: Commit**
```bash
git add os/Clavain/cmd/clavain-cli/authz.go os/Clavain/hooks/authz-compact.sh os/Clavain/.claude-plugin/plugin.json docs/canon/authz-retention.md
git commit -m "feat(authz): retention — compact consumed tokens, 1y revoke window (sylveste-qdqr)"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && go test -run TestCompact -v`
  expect: exit 0
</verify>

---

## Task 8: End-to-end integration test + README v2 quickstart

**Files:**
- Create: `os/Clavain/tests/authz-v2-e2e_test.sh`
- Modify: `os/Clavain/README.md` (v2 Auto-proceed subsection — delegation + tokens)

**Step 1: E2E script**
1. Fresh sandbox, `ic init`, `policy init-key`, project policy installed.
2. User-role issues root token for `bead-close` + `sylveste-xyz`, `agent=codex-1`, ttl=5m. Assert ULID printed to stdout.
3. Codex-role consumes the token via the bead-close wrapper (with `CLAVAIN_AUTHZ_TOKEN` set). Assert bd-close stub called + audit row has `token_id` set.
4. Second consume same token → wrapper exits non-zero, bd-close stub NOT called a second time.
5. Issue a new parent token, delegate to a grandchild agent (depth 2). Verify chain walks correctly from `policy token show --chain`.
6. Issue a token with ttl=1s, sleep 3s, attempt consume → exit 3 (expired).
7. Issue parent + delegate twice (depth 3); attempt depth-4 delegate → error "max depth 3".
8. Root revoke with `--cascade` → every descendant flagged `consumed_by='revoked'` in one step.
9. Proof-of-possession: token issued with `agent=X`; agent `Y` attempts `policy token delegate` from it → fails.
10. `policy token verify --all` returns 0 until we mutate a row via direct SQL, then returns 1 with the row flagged.

**Step 2: README subsection** — title "Delegation + tokens (v2)". Coverage: when to use tokens vs bare policy, issue/consume/delegate lifecycle, cascade-revoke, the TTL default (15m), and the env-var handoff pattern for Claude→codex.

**Step 3: Full matrix**
```bash
cd core/intercore && go test ./... -v
cd os/Clavain && go test ./... -v
bash os/Clavain/scripts/gates/gates-smoke_test.sh
bash os/Clavain/tests/vetting-writes_test.sh
bash os/Clavain/tests/authz-e2e_test.sh       # v1
bash os/Clavain/tests/authz-v15-e2e_test.sh   # v1.5
bash os/Clavain/tests/authz-v2-e2e_test.sh    # v2
```

**Step 4: Commit**
```bash
git add os/Clavain/tests/authz-v2-e2e_test.sh os/Clavain/README.md
git commit -m "test(authz): v2 e2e — tokens, delegation, cascade revoke, expiry (sylveste-qdqr)"
```

<verify>
- run: `bash os/Clavain/tests/authz-v2-e2e_test.sh`
  expect: contains "PASS"
</verify>

---

## Deferred to v2.x / v3

- **v2.x DAG delegation runtime** — schema already supports `root_token` + `parent_token`. Runtime guard only rejects diamond patterns today; if evidence demands fan-in (multiple parents merging authority), add a `parents` junction table and loosen runtime. Est. 2 days.
- **v2.x cross-project delegation** — a token issued in Sylveste and consumed by an op in Clavain needs coordinated audit writes. Reuses the v1 `cross_project_id` discipline; wire the consume path to write to both DBs. Est. 1 day.
- **v3 cross-host federation** — NOT in scope. Requires remote authz protocol; explicitly deferred per brainstorm §"Not in scope".
- **v3 production-deploy gating** — NOT in scope. Separate hooks into deploy tooling.

---

## Notes on discipline

- **TTL defaults bite.** 15-minute default is short enough to make stolen tokens a narrow window but long enough to cover a normal delegated sub-op. Policy per op type can raise it up to 1 day; the `op:"*"` global floor caps max TTL, matching the v1 merge discipline.
- **Proof-of-possession is non-negotiable.** Without it, any agent that sees a token ID in a log can delegate as if they held it. Never log token IDs in stdout that could leak to shared transcripts — log the ULID prefix (first 8 chars) only.
- **Atomic consume is non-negotiable.** The UPDATE with `expires_at > ?` in the WHERE is the whole point. Never add a pre-check SELECT that lets expired tokens slip through on a slow clock.
- **Don't issue long-lived tokens as convenience.** If an op needs repeat authority, either widen policy (pull-model fallback handles it) or issue fresh tokens on demand. Long TTL tokens defeat the stolen-window bound.
- **Env-var handoff only.** Filesystem drops are a leak vector (world-readable by default, shell-history-visible via `env`). If env inheritance is impossible, that agent uses the pull-model fallback.
- **Compaction runs weekly, not per-session.** Per-session compaction would surprise-mutate the DB during active work and cause audit-query flakiness. Weekly via the hook is enough.
- **Revoke cascade is the lever.** When a root agent is compromised, one `policy token revoke --token=<root> --cascade` call blackholes the whole subtree before consume lands. Teach this in the README — it's the v2 equivalent of "kill the session."
