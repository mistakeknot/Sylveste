---
artifact_type: canon
bead: sylveste-qdqr.28
supersedes: (none)
superseded_by: (none)
---

# Authz token model — v2

This document is the normative specification for the v2 authorization token protocol. It covers token lifecycle, scope semantics, delegation rules, proof-of-possession, atomic consume contract, cascade revoke, scope of the same-project guarantee, relationship to v1.5 audit rows, threat model delta, and env-var hygiene.

v2 adds an unforgeable token protocol on top of v1.5's signed audit records. A token is a single-use, scoped, time-limited authorization that can be delegated in a linear chain (max depth 3), revoked (with cascade on root tokens), and atomically consumed. The opaque token string carried between agents is `<ulid>.<sighex>` and is transported via the `CLAVAIN_AUTHZ_TOKEN` environment variable.

Implementations MUST match. Any deviation is a bug.

---

## 1. Lifecycle

A token moves through the following states:

```
  issued ──(delegate)──> issued (child)
     │                      │
     ├──(consume)───────────┤
     ↓                      ↓
  consumed              consumed
     │                      │
     (or)                  (or)
     ↓                      ↓
  revoked               revoked
     │                      │
     (or)                  (or)
     ↓                      ↓
  expired               expired
```

Three terminal states, exclusive:

- **consumed** — the single-use atomic UPDATE landed. `consumed_at` is set. A second consume returns `ErrAlreadyConsumed`.
- **revoked** — an operator invoked `clavain-cli policy token revoke`. `revoked_at` is set. A consume attempt returns `ErrRevoked` (v2 auth-failure class, exit 4).
- **expired** — the DB column `expires_at` is a unix-second timestamp. When `now > expires_at` and the token is not yet consumed or revoked, any consume attempt returns `ErrExpired` (token-state class, exit 2).

State predicates (used by the consume UPDATE predicate):

- `consumed_at IS NULL AND revoked_at IS NULL AND expires_at > now` → consumable.
- Any other state is terminal for consume purposes, though revocation can still land on a consumed or expired token for audit-intent (the `revoked_at` column gets set, but the token was already terminal; the revoke is informational).

No re-issue. A token has exactly one `id` (ULID) generated at issue time. Re-running `policy token issue` with identical `--op --target --for --ttl` produces a *new* token with a *new* ULID.

## 2. Scope

A token's scope is the union of four fields:

- `op_type` — the operation class (e.g., `bead-close`, `git-push-main`, `bd-push-dolt`, `ic-publish-patch`). Must match exactly; no wildcards at consume time.
- `target` — the resource the op acts on. For `bead-close` it is the bead id; for `ic-publish-patch` it is the plugin slug; for `git-push-main` it is the remote refname. Must match exactly.
- `agent_id` — the agent identity allowed to *present* this token. At consume time, the caller's `CLAVAIN_AGENT_ID` (passed as `callerAgentID` parameter to `authz.ConsumeToken`) MUST equal this field. Bearer-by-string is explicitly rejected.
- `bead_id` — optional. When set, the op MUST be for this bead. When unset (NULL), the token is not bead-scoped.

Scope narrowing in delegation (see §3): a child token's `op_type` and `target` MUST equal its parent's. A child's TTL is clamped to `min(requested, parent_remaining)`. No scope-widening API exists; adding one in a future version would require a conscious design change, not a flag flip.

### 2.1. Expect flags

The `consume` CLI accepts `--expect-op=<o>` and `--expect-target=<t>`. When non-empty, both MUST match the token's scope exactly; mismatch returns `ErrExpectMismatch` (auth-failure class, exit 4). Gate wrappers always pass both.

Empty-string expect values are accepted by the Go function (`authz.ConsumeToken`) for programmatic flexibility but the CLI logs `warn: scope check skipped` to stderr for observability. New Go callers SHOULD pass non-empty expects.

## 3. Delegation

Delegation is a *linear chain*, max depth 3. Each node has exactly one parent (or is a root).

**Runtime lock-in is deliberate.** The schema carries `parent_token`, `root_token`, and `depth` (CHECK depth ≤ 3); the runtime code commits to chain semantics via:

1. `DelegateToken`'s single-parent signature (`DelegateSpec.ParentID string`, not `[]string`).
2. `Token.ParentToken string` field type.
3. Scope-narrowing compares against one parent row.
4. Cascade revoke predicate assumes one `root_token` per descendant.

A future DAG migration (v2.x) must revisit all four. The canon record is: schema is DAG-ready; runtime is chain-only by design.

### 3.1. Delegation constraints

At `DelegateToken` call time, the following are enforced (each maps to a distinct error class):

- **Proof-of-possession**: `spec.CallerAgentID == parent.AgentID` → else `ErrProofOfPossession` (exit 4).
- **Depth cap**: `parent.Depth + 1 ≤ 3` → else `ErrDepthExceeded` (exit 4). Also enforced by the schema CHECK constraint; CLI re-SELECT inside the insert transaction closes the race on two concurrent delegates.
- **Scope narrowing (API-level)**: `DelegateSpec` has no `ChildOpType` or `ChildTarget` override fields. A future version that adds them would be a conscious design change, not a flag. Child scope is always equal to parent scope.
- **TTL clamp**: `child.ExpiresAt = min(now + spec.RequestedTTL, parent.ExpiresAt)`. A request for a longer TTL than the parent's remaining silently clamps; this is not an error.

### 3.2. Delegation wire format

The child token has:

- `id` — fresh ULID.
- `op_type`, `target` — copied from parent.
- `agent_id` — `spec.ToAgentID` (the recipient agent).
- `bead_id` — copied from parent.
- `delegate_to` — `spec.ToAgentID` (same as `agent_id` on the child row; redundant but retained for audit clarity — a query `WHERE delegate_to IS NOT NULL` returns only delegation events).
- `expires_at` — clamped.
- `issued_by` — `spec.CallerAgentID` (the parent-holder who initiated the delegate).
- `parent_token` — `spec.ParentID`.
- `root_token` — `parent.RootToken if set else parent.ID` (denormalized so cascade revoke on a root is one scan).
- `depth` — `parent.Depth + 1`.
- `sig_version` — 2.
- `signature` — Ed25519 over the canonical payload (see `docs/canon/authz-token-payload.md`).
- `created_at` — `now`.

## 4. Proof-of-possession

Two distinct POP checks:

- **At delegate time**: caller must hold the parent token. Enforced by `spec.CallerAgentID == parent.AgentID`. Without this, any agent that has seen a token ID (e.g., from an audit log or leaked stdout) could delegate as if they held it.
- **At consume time**: caller must be the intended consumer. Enforced by `callerAgentID == token.AgentID` (inside the atomic UPDATE's WHERE clause). Without this, the opaque token string alone would be sufficient to consume — making it a bearer token. v2 rejects bearer semantics.

Both checks read from `callerAgentID` as an explicit parameter to the library functions. The CLI reads `$CLAVAIN_AGENT_ID` and threads it in. Library code does not call `os.Getenv` — this makes the library testable without environment setup and pins the trust boundary at the composition root (`cmd/clavain-cli/authz_token.go`, `cmd/ic/publish.go`).

**Threat caveat**: `$CLAVAIN_AGENT_ID` is settable by whoever runs the CLI. A user who possesses a token for `agent=claude` and sets `CLAVAIN_AGENT_ID=claude` can consume the token. This is the intended threat envelope in v2 — tokens bind to agent *name*, and agent-name trust is the responsibility of the process that sets `$CLAVAIN_AGENT_ID`. Per-agent key binding (where tokens verify against a claude-specific pubkey rather than the project-wide key) is a v2.x concern.

## 5. Atomic consume contract

`authz.ConsumeToken` wraps two writes in one transaction:

### 5.1. Pre-transaction checks

Before opening the transaction:

1. Parse the opaque string into `(id, sig)`. Malformed → `ErrBadTokenString` (exit 3).
2. Load the row by `id`. Not found → `ErrNotFound` (exit 3).
3. Verify the signature against the project pubkey over `CanonicalTokenPayload(row)`. Invalid → `ErrSigVerify` (exit 4).
4. Check `callerAgentID == row.AgentID`. Mismatch → `ErrCallerAgentMismatch` (exit 4).
5. If `expectOp != ""`: check `expectOp == row.OpType`. Mismatch → `ErrExpectMismatch` (exit 4).
6. If `expectTarget != ""`: check `expectTarget == row.Target`. Mismatch → `ErrExpectMismatch` (exit 4).

Pre-transaction because these checks don't need atomic DB state — signature verification only requires the canonical payload which is built from signed fields that never mutate after insert (only `consumed_at` and `revoked_at` mutate, neither is in the signed field list).

### 5.2. Transactional writes

```go
tx, err := db.BeginTx(ctx, nil)
// ... defer rollback ...
res, err := tx.ExecContext(ctx, `
    UPDATE authz_tokens
       SET consumed_at = ?
     WHERE id = ?
       AND consumed_at IS NULL
       AND revoked_at IS NULL
       AND expires_at > ?
       AND agent_id = ?
`, now, id, now, callerAgentID)
if err != nil { return err }

n, _ := res.RowsAffected()
if n != 1 {
    // Re-SELECT within the tx to classify the failure.
    // Possible outcomes: revoked (ErrRevoked, exit 4), expired (ErrExpired, exit 2),
    // already-consumed (ErrAlreadyConsumed, exit 2). Agent-mismatch was caught pre-tx.
    // Priority when multiple conditions hold: revoked > consumed > expired.
    return classifyConsumeFailure(tx, id, now)
}

// Write the consume-audit row as a v1.5-shaped authz row with sig_version=1.
// Includes vetting JSON: {"via": "token", "token_id": "<id>", "root_token": "<root|null>"}.
_, err = tx.ExecContext(ctx, `INSERT INTO authorizations (...) VALUES (...)`, ...)
if err != nil { return err }  // tx.Rollback in deferred cleanup

return tx.Commit()
```

### 5.3. Partial-failure invariant

If the process is killed after the UPDATE commits but before the INSERT commits, the transaction rolls back on next DB open (modernc.org/sqlite's WAL-mode recovery). Therefore neither the token-consume nor the audit row lands; the token remains consumable on a future retry. Tested via `TestConsumeToken_PartialFailure_Atomic` using a build-tagged fault injection hook (`// +build testfault`) triggered by `CONSUME_FAULT_INJECT_AFTER_UPDATE=1`.

### 5.4. Failure classification priority

When the atomic UPDATE returns 0 rows, the re-SELECT classifies:

1. `revoked_at IS NOT NULL` → `ErrRevoked`
2. `consumed_at IS NOT NULL` → `ErrAlreadyConsumed`
3. `expires_at <= now` → `ErrExpired`
4. Row exists and none of the above → unexpected (caller-mismatch was caught pre-tx; a 0-rows UPDATE here means concurrent revoke/consume landed between our pre-tx checks and our UPDATE). Return `ErrAlreadyConsumed` as the conservative classification.

Priority is `revoked > consumed > expired` because a row can be in multiple terminal states simultaneously (e.g., consumed-then-revoked for audit-intent). We report the *stronger* operator-intent signal first.

## 6. Cascade revoke

Revoke has two modes: single-target and cascade.

### 6.1. Single-target revoke

```
UPDATE authz_tokens SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL
```

Works for any token (root or non-root). Only the target row is flagged. Idempotent via the `revoked_at IS NULL` predicate.

### 6.2. Cascade revoke — root-only

```
UPDATE authz_tokens SET revoked_at = ?
 WHERE (id = ? OR root_token = ?) AND revoked_at IS NULL
```

Both parameter slots bind to `target.id`. The `id = ?` branch catches the root itself; the `root_token = ?` branch catches every descendant (descendants denormalize `root_token` to the root's ID).

**Restriction — root-only in v2**: `RevokeToken(db, id, cascade=true, now)` first verifies the target is a root (`parent_token IS NULL AND root_token IS NULL`). If not, returns `ErrCascadeOnNonRoot` (exit 4) without writing.

**Why not mid-chain cascade**: descendants denormalize `root_token` to the *chain root*, not to immediate ancestors. A predicate `WHERE root_token = <mid-chain-target.id>` matches zero rows. Correct mid-chain cascade requires either:

- A recursive CTE traversing `parent_token` upward from each row.
- A schema change that denormalizes additional ancestors (e.g., `ancestors TEXT[]`).

Both are v2.x concerns. v2 refuses mid-chain cascade rather than silently half-revoke.

### 6.3. NULL-semantics discipline

SQL `NULL = NULL` is never true. An earlier draft used `WHERE root_token = target.root_token`; for a root target with `target.root_token IS NULL`, this evaluated to `WHERE root_token = NULL` and matched zero rows. The corrected predicate binds `target.id` to both positions. Any future cascade-column additions must revisit this.

### 6.4. Race with concurrent consume

Under `SetMaxOpenConns(1)`, cascade UPDATE and concurrent `ConsumeToken` UPDATE serialize against each other. If cascade lands first, the consume's WHERE (`revoked_at IS NULL`) sees non-NULL and affects 0 rows → returns `ErrRevoked`. If consume lands first, it succeeds; a subsequent cascade sets `revoked_at` on the already-consumed row, which is harmless for audit (the consume was final). Tested via `TestRevokeVsConsume_Race`.

## 7. Same-project scope

v2 refuses cross-project consumption.

**Mechanism**: `consume` looks up the token by `id` in the local project's `.clavain/intercore.db`. If the row is not present, returns `ErrNotFound` (exit 3). A caller cannot cross project boundaries by passing a token issued elsewhere — the row simply does not exist in the local DB.

**Not a cross-project guarantee by signature verification** (which would be a v2.1 upgrade path — see §9). v2's guarantee is topological: each project's DB is isolated.

**v2.1 upgrade path**: add a `cross_project_id TEXT` column to `authz_tokens`, plus a multi-project pubkey registry (`~/.clavain/trusted-projects.yaml`). Consume flow becomes: look up row; if not local, resolve `cross_project_id` via registry; load remote pubkey; verify; consume against the local DB with a cross-project-audit row.

## 8. Relationship to v1.5 audit

Token issue, consume, delegate, and revoke events each land as a v1.5-shaped `authorizations` audit row (sig_version=1, signed with the project key per `docs/canon/authz-signing-payload.md`).

The *token itself* uses sig_version=2 (signed over `docs/canon/authz-token-payload.md`'s field list, which is a different 12 fields). Distinct `sig_version` values prevent cross-payload replay attacks.

The consume-audit row's `vetting` JSON carries:

```json
{
  "via": "token",
  "token_id": "<id>",
  "root_token": "<id or null>",
  "depth": <int>
}
```

This makes `policy audit --tokens` possible: join `authorizations` (consume events) with `authz_tokens` (lifecycle state) via the embedded `token_id`, and render the delegation tree rooted at each `root_token`.

The `vetting.via` key also drives the marker-deprecation telemetry: counts of `via="token"` vs `via="authz-record"` vs `via="marker"` over 14-day windows feed the decision gate in §10.

## 9. Threat model delta from v1.5

v1.5's trust claim is **tamper-evident-post-write** — an attacker with gate-CLI privilege can forge new rows, but cannot rewrite history already signed. Detection covers direct-SQL mutations.

v2 adds:

- **Atomic single-use** — a token cannot be consumed twice; the UPDATE's `consumed_at IS NULL` predicate is racesafe under MaxOpenConns=1.
- **Delegation traceability** — every consume references `root_token` and (via the token row) the full parent chain. `policy audit --tokens` renders the tree.
- **Cascade revoke** — an operator can invalidate a root + all descendants in one scan. Revocation is an auth-failure class at the gate, not a token-state fall-through.
- **Caller-identity binding** — the opaque string alone does not authorize; the caller's `agent_id` must match the token's `agent_id`. Bearer semantics explicitly rejected.
- **Scope narrowing in delegation** — child scope cannot widen beyond parent; enforced by API-level absence of override fields.

v2 does NOT add:

- **Tamper-proof at rest** — signer-key-holder can still forge tokens and audit rows. Inherited limitation from v1.5. Fix in v1.6 (out-of-band signer daemon).
- **Per-agent key binding** — tokens verify against the project-wide key, not per-agent. An attacker who compromises the project key can impersonate any agent. v2.x concern.
- **Cross-project trust** — tokens do not traverse projects. v2.1 concern.
- **DAG delegation** — multi-parent delegations are schema-ready but runtime-refused. v2.x concern.

## 10. Env-var hygiene

`CLAVAIN_AUTHZ_TOKEN` is the transport mechanism for tokens between processes. It is:

- **Inherited by child processes**. Delegation to a sub-agent (e.g., Claude → codex) works by spawning the child with the env var set. Once the child consumes the token, it unsets the var in-process so *its* children don't inherit.
- **Unset after successful consume**. Both the bash wrapper (`gate_token_consume` in `_common.sh`) and the Go `RequiresApproval` unset the var after consume. This is belt-and-suspenders: the wrapper's `unset` covers spawned children of the wrapper; the Go `os.Unsetenv` covers spawned children of the `ic` process.
- **Not to be `export`ed in interactive shells**. The README uses one-shot form `CLAVAIN_AUTHZ_TOKEN=<tok> ic publish --patch` for exactly one invocation. `export CLAVAIN_AUTHZ_TOKEN=...` persists the value in shell state (and history with some shell configs) — an attack surface.

The CLI `consume` emits a sentinel-wrapped `unset` on success for eval-consumption in interactive shells:

```
# authz-unset-begin
unset CLAVAIN_AUTHZ_TOKEN
# authz-unset-end
```

`eval "$(clavain-cli policy token consume ...)"` clears the var. A paranoid caller can grep the region between sentinels to verify no injection happened before eval-ing.

## 11. Marker-deprecation decision gate

v1.5 shipped a louder deprecation warning for `.publish-approved`. v2 adds telemetry + an explicit removal gate (not a vague "95%"):

**Measurement**: every `ic-publish-patch` authz row carries `vetting.via` ∈ {`token`, `authz-record`, `marker`}. The baseline is collected during Task 6 of v2 implementation (expected: 100% marker pre-v2).

**14-day rolling query**:
```sql
SELECT json_extract(vetting, '$.via') AS via, count(*) AS n
FROM authorizations
WHERE op_type = 'ic-publish-patch'
  AND created_at > strftime('%s','now','-14 days')
GROUP BY via;
```

**Decision gate (normative)**:

- *token + authz-record ≥ 90% AND marker ≤ 10%* of the 14-day window → open a bead to remove the marker-file path in the next release.
- *marker between 10-20%* → keep the deprecation warning; re-measure in 14 days.
- *marker ≥ 20%* → investigate why adoption stalled (missing tooling, insufficient docs, legitimate use cases); do not remove.

This gate replaces the r1 plan's vague "95% telemetry" and gives a concrete operator decision procedure.

## 12. Reserved for v2.x

- **DAG delegation** — schema is DAG-ready; runtime single-parent. Migration requires widening `DelegateToken` + `Token.ParentToken` type + scope-narrowing code + cascade-revoke predicate. See §3 for lock-in points.
- **Cross-project delegation** — requires `cross_project_id` column + multi-project pubkey registry. See §7 for upgrade path.
- **Per-agent key binding** — tokens verify against project-wide key today. Per-agent keys would reduce blast radius of a single-key compromise.
- **Marker-file full removal** — gated on §11's decision procedure.
- **Mid-chain cascade revoke** — gated on a schema or CTE design. v2 refuses rather than half-revoke.
- **Out-of-band signer daemon** (v1.6 carry-forward) — decouples signing key from gate-CLI process. Tightens trust claim from "tamper-evident-post-write" to "tamper-proof-at-rest".

## References

- `docs/canon/authz-token-payload.md` — canonical byte sequence for sig_version=2.
- `docs/canon/authz-signing-payload.md` — v1.5 canonical payload (sig_version=1).
- `docs/canon/authz-signing-trust-model.md` — v1.5 trust claim.
- `docs/brainstorms/2026-04-19-auto-proceed-authz-design.md` — design rationale (v1 + v1.5 + v2).
- `docs/plans/2026-04-21-auto-proceed-authz-v2.md` — implementation plan (this is its canon counterpart).
