---
artifact_type: plan
bead: sylveste-qdqr.28
stage: design
scope: v2 — unforgeable token protocol + delegation chain
source_brainstorm: docs/brainstorms/2026-04-19-auto-proceed-authz-design.md
source_handoff: docs/handoffs/2026-04-21-authz-v2-tokens-delegation-handoff.md
source_synthesis: docs/research/flux-drive/2026-04-19-auto-proceed-authz-design-20260419T0239/SYNTHESIS.md
prerequisite: docs/plans/2026-04-19-auto-proceed-authz-v1.5.md
revisions:
  - 2026-04-21 r1 — initial draft
  - 2026-04-21 r2 — apply flux-drive findings (2 P0 + 10 convergent P1); see docs/research/flux-drive/2026-04-21-auto-proceed-authz-v2-20260421T0350/
  - 2026-04-21 r3 — apply re-review findings (3 P1 regressions introduced by r2 + 3 P2 hygiene); see docs/research/flux-drive/2026-04-21-auto-proceed-authz-v2-r2-20260421T0710/
---

# Auto-proceed authorization framework — v2 implementation plan

> **Revision note (r2, 2026-04-21).** Applied review findings from 5-agent flux-drive pass. Material changes:
> - **P0 · cascade revoke NULL fix** — predicate changed to `WHERE id = ? OR root_token = ?` with explicit `target.id` passed (NULL-NULL comparison in SQL never matches, breaking revoke from any root token). Affects Architecture, Must-Haves, Task 1 canon doc, Task 3 `RevokeToken` + new test, Task 8 scenarios.
> - **P0 · transactional consume** — token-state UPDATE + audit-row INSERT now wrap in one `BEGIN...COMMIT`. Affects Architecture, Task 3 `ConsumeToken` body, new forced-abort test.
> - **P1 · `ConsumeToken` enforces caller identity** — new required `callerAgentID` parameter; verified against `token.AgentID`. Bearer-token-by-string-alone is rejected.
> - **P1 · gate wrapper hard-fails on auth-class exit codes** — `gate_token_consume` no longer falls through on revoked/POP/scope failures.
> - **P1 · exit code collapse** — 9 codes → 5 codes (0/1/2/3/4) by semantic class; wrappers log reason to stderr from CLI rather than discriminating on numeric code.
> - **P1 · `RequiresApproval` signature threaded** — no `os.Getenv` inside intercore kernel; no second `sql.Open`. Caller passes `tokenStr` + `db *sql.DB`.
> - **P1 · `DelegateToken` uses `DelegateSpec` struct** — positional string args replaced.
> - **P1 · env var unset after consume** — both bash wrapper and Go `RequiresApproval` unset `CLAVAIN_AUTHZ_TOKEN` after a successful consume.
> - **P1 · `--expect-op` / `--expect-target` flags pinned** — previously called by wrapper spec but missing from handler spec; now defined on `policy token consume`.
> - **P1 · 95% marker-removal threshold instrumented** — telemetry measurement window + baseline collection specified as a Task 6 subtask, not a deferred assumption.
> - **P1 · linear-chain runtime lock-in documented explicitly** — Task 1 canon doc pins which code interfaces are chain-specific so v2.x DAG migration knows where to look.
>
> **r3 additions (fixing r2 regressions):**
> - **P1 · `--cascade` restricted to root tokens** — r2's `WHERE id=? OR root_token=?` predicate correctly handled root revokes but silently missed descendants for mid-chain cascade because descendants' `root_token` denormalizes to the *chain root*, not the mid-chain target. r3 restricts `--cascade` to root tokens only; non-root-with-cascade returns `ErrCascadeOnNonRoot`. Mid-chain revoke-all-descendants is a v2.x concern (recursive CTE over `parent_token`).
> - **P1 · revoked is auth-failure class, not token-state** — r2 internally contradicted itself: Prior Learnings classed revoked as auth-failure (hard-fail) while `ExitCode()` mapped `ErrRevoked` to exit 2 (token-state fall-through). r3 reclassifies revoked to exit 4 (auth-failure); gate wrapper hard-fails on a revoked token. Rationale: revocation is an explicit operator intent; falling through to legacy would let legacy policy silently override the revoke.
> - **P1 · migration 034 cutover marker idempotent** — r2 used `randomblob(16)` for the marker ID, so re-running migration on a already-migrated DB would insert a second marker. r3 uses a fixed ID (`'migration-034-tokens-enabled'`) with `INSERT OR IGNORE`, mirroring the v1.5 migration-033 pattern.
> - **P2 · empty-expect passthrough removed** — r2 made `--expect-op` / `--expect-target` optional with "backward-compat" rationale. But this is a new protocol; no backward-compat exists. r3 makes both required when consuming from the CLI (wrapper always passes them); the Go function still accepts empty strings but callers that pass empty get a `warn: scope check skipped` stderr line for observability.
> - **P2 · README uses one-shot form, not `export`** — Task 7 README example uses `CLAVAIN_AUTHZ_TOKEN=<tok> ic publish --patch` one-shot rather than `export CLAVAIN_AUTHZ_TOKEN=...` to prevent shell-history leakage.
> - **P2 · `eval` path emits sentinel-prefixed unset** — the CLI prints `# authz-unset-begin\nunset CLAVAIN_AUTHZ_TOKEN\n# authz-unset-end` so callers can verify integrity of stdout before eval.
---


> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-qdqr.28 (child of epic sylveste-qdqr; v1 and v1.5 closed, epic reopened for v2)
**Goal:** Add an unforgeable token protocol on top of v1.5's signed audit so that delegated ops (Claude → codex today, fleet agents tomorrow) carry a traceable chain of custody. After v2, `policy audit` can answer *"who actually did this?"* for every delegated op, double-consumption is atomically impossible, expired tokens fail closed, and revoking a root token invalidates every descendant before its consume lands.

**Architecture:** A new `authz_tokens` table holds the token lifecycle (issued → [delegated → …] → consumed | revoked | expired). Tokens are ULIDs signed under the v1.5 project key using a v2 canonical payload (12 token-shaped fields, distinct from the v1.5 authorizations payload → new `sig_version=2`). The opaque token string carried between agents is `<ulid>.<sighex>` — the DB row is authoritative for scope and lifecycle; the string is proof of possession. **Consume wraps two writes in one transaction**: (1) atomic `UPDATE authz_tokens SET consumed_at=? WHERE id=? AND consumed_at IS NULL AND revoked_at IS NULL AND expires_at > ? AND agent_id=?` with `RowsAffected()` discrimination (modernc.org/sqlite constraint: no CTE-wrapped RETURNING; use direct UPDATE + row counting), and (2) `INSERT INTO authorizations (...)` for the consume-audit row. A partial-failure between (1) and (2) must not leave a consumed token with no audit record — commit-or-rollback is non-negotiable. Consume additionally requires the caller's `agent_id` to match the token's `agent_id` (passed as explicit parameter — not bearer-by-string). Delegation is linear chain, max depth 3 (CHECK constraint + CLI enforcement + concurrency-safe recheck inside the insert transaction). `root_token` is denormalized so cascade revoke is `UPDATE authz_tokens SET revoked_at=? WHERE id=? OR root_token=?` passing `target.id` for both bindings (the disjunction covers both root revokes, where `root_token IS NULL` on descendants would otherwise fail to match via NULL semantics, and non-root revokes — a single index scan against `tokens_by_root` covers both). Same-project-only in v2; cross-project delegation deferred to v2.1. Linear-chain runtime lock-in is documented explicitly in Task 1's canon doc — v2.x DAG migration will require signature changes in `DelegateToken` + `Token.ParentToken` type widening.

**Trust claim:** v2 ships as **proof-of-possession tokens with atomic single-use**, sitting on top of v1.5's tamper-evident-post-write audit. A token holder can consume exactly once for exactly the op/target scope it was issued for. An agent that never received a token cannot forge one (no signing key). A delegated agent cannot widen scope (scope-narrowing check in `Delegate`). The signer-key-holder can still forge tokens — that's the same threat envelope as v1.5; tightening requires the v1.6 out-of-band signer deferred in v1.5. This is documented in `docs/canon/authz-token-model.md`.

**Tech Stack:** Go (intercore `pkg/authz` + clavain-cli), `crypto/ed25519` (reuse v1.5), ULID (`github.com/oklog/ulid/v2` — stdlib-adjacent, tiny), SQLite (migration 034), Bash (gate wrapper extension).

**Prior Learnings:**
- v1.5 landed `SignRow`, `CanonicalPayload`, `Sign`, `Verify`, `KeyPair`, `GenerateKey`, `WriteKeyPair`, `LoadPrivKey`, `LoadPubKey`, `KeyFingerprint`, `RotateKey`. Reuse the key plumbing verbatim; token payload uses a separate canonical function (distinct field list).
- Payload spec lives at `docs/canon/authz-signing-payload.md`. v2 adds a sibling `docs/canon/authz-token-payload.md` — *not* an extension of the v1.5 spec, a parallel spec. Do NOT reorder or add fields to the v1.5 spec.
- Migration anchor in `core/intercore/internal/db/db.go`: last branch is `if currentVersion >= 32 && currentVersion < 33` (v1.5). Migration 034 appends at the end with `if currentVersion >= 33 && currentVersion < 34 { ... }`. The `migrations/NNN.sql` files are documentation only since ≥021 — the real DDL lives inline.
- `modernc.org/sqlite` does NOT support CTE-wrapped `UPDATE ... RETURNING`. Use `UPDATE ... WHERE ... RETURNING <cols>` directly (supported) or `UPDATE ... WHERE ...` plus `RowsAffected()` check. Atomic consume uses the latter for portability.
- **`NULL = NULL` is never true in SQL.** A WHERE predicate comparing a column to a NULL-valued parameter matches zero rows, not "all NULL rows" and not "the row being revoked". Cascade revoke spec was broken in r1 — revoking a root token whose `root_token IS NULL` matched nothing. r2 uses `WHERE id=? OR root_token=?` with `target.id` bound to both positions.
- `SetMaxOpenConns(1)` is the intercore convention — consume transactions serialize naturally. But *only for the shared `*sql.DB`*. Never call `sql.Open` a second time on the same file from the same process — it creates an independent connection pool that races against the first (`SQLITE_BUSY` territory). `RequiresApproval` takes `db *sql.DB` as a parameter rather than opening its own.
- CLI namespace: existing v1.5 surface is `clavain-cli policy {check,record,audit,list,lint,explain,init-key,sign,verify,rotate-key,quarantine}`. v2 extends with `policy token {issue,consume,delegate,revoke,list,show,verify}` — two-level subcommand under `policy`, not a new top-level `authz` namespace (the brainstorm's original wording is superseded by the handoff's `policy token` convention). Scaling beyond v2 (e.g., per-agent key management) may motivate a `token` or `authz` top-level — called out as a v3 architecture question, not a v2 one.
- Gate wrapper pattern in `os/Clavain/scripts/gates/_common.sh`: `gate_check` → op → `gate_record` → `gate_sign`. v2 adds `gate_token_consume` at the *front* of the chain (before `gate_check`) that runs iff `$CLAVAIN_AUTHZ_TOKEN` is set. On consume-success, short-circuits the op and then `unset CLAVAIN_AUTHZ_TOKEN` to prevent child-process leakage. On auth-class failure (revoked / POP-failure / scope-mismatch / cross-project / sig-verify), fails the gate rather than falling through — the operator's revoke-intent is honored even when a legacy path could have granted approval. On token-state failure (expired / already-consumed) or missing-token: falls through to legacy `gate_check`.
- Exit code policy (r2 9→5 collapse; r3 revoked→auth-failure reclassification): **0** success; **1** unexpected error (I/O, DB, programmer); **2** token-state-passive (already-consumed OR expired — passive drift; wrapper falls through to legacy policy); **3** not-found (malformed string or valid ULID not in DB; wrapper falls through); **4** auth-failure (sig-verify | POP mismatch | scope-widen | cross-project | caller-agent-mismatch | **revoked** | **cascade-on-non-root** | expect-mismatch — explicit refusal; wrapper HARD-FAILS). Wrapper distinguishes success / token-state-fallthrough (2, 3) / hard-failure (1, 4). Fewer codes than r1 (9→5) reduce the shell-wrapper surface and make future error-class additions non-breaking.
- `.publish-approved` marker: v1.5 made `RequiresApproval()` consult authz records first, marker as fallback + deprecation warning. v2 upgrades the warning to a louder stderr banner and *instruments the adoption rate* — Task 6 adds a 30-day rolling measurement (`SELECT count(*) FROM authorizations WHERE op_type='ic-publish-patch' AND created_at > now-30d GROUP BY (vetting JSON 'via' field)` split into `token` vs `marker`). Marker removal deferred to v2.x and gated on a concrete measurement window, not a vague 95%.
- `CLAVAIN_AGENT_ID` convention (v1) is reused for both issuer and consumer identity. Proof-of-possession in delegate: `callerAgentID == parentToken.AgentID` where `callerAgentID` is an explicit parameter (not `os.Getenv` inside library code). CLI reads env var; library function signature is pure. Same applies to consume: `ConsumeToken(db, pub, tokenStr, callerAgentID, now)` — caller identity is passed, not ambient.
- Linear-chain runtime lock-in: `DelegateToken` returns a single token with one `parent_token`, and `depth += 1` is implicit in the spec struct's zero default. DAG migration in v2.x will need: (a) multi-parent representation (`[]string` or many-to-many join table), (b) widened `parent_token` on wire, (c) multi-parent scope-narrowing rules (intersection of parent scopes). Task 1 canon doc pins exactly where chain assumptions live so the v2.x diff is discoverable.

---

## Must-Haves

**Truths:**
- `clavain-cli policy token issue --op=<o> --target=<t> --for=<agent> --ttl=60m` emits `<ulid>.<sighex>` on stdout, inserts a signed row into `authz_tokens`, and is idempotent only in the sense that re-running with the same args produces a *new* token (never the same ULID).
- `clavain-cli policy token consume --token=<str> --expect-op=<o> --expect-target=<t>` exits 0 on success; the CLI reads `$CLAVAIN_AGENT_ID` and passes it to `authz.ConsumeToken` so the caller's identity is verified against the token's `agent_id`. Supplying `--token` OR reading `$CLAVAIN_AUTHZ_TOKEN` from env are both supported (explicit flag wins). On success the CLI prints `unset CLAVAIN_AUTHZ_TOKEN` to stdout (evaluable in shell via `eval $(clavain-cli policy token consume ...)`) and the bash wrapper additionally unsets the env var in-process.
- Consume exit codes (r3): **0** success; **1** unexpected error (DB, I/O); **2** token-state-invalid (already-consumed | expired — CLI logs which via `ERROR token-invalid: <class>` to stderr); **3** not-found (malformed opaque string or valid ULID not in DB); **4** auth-failure (sig-verify | `--expect-op/--expect-target` mismatch | caller-agent-mismatch | cross-project | **revoked** | **cascade-on-non-root**). Revoked maps to 4, not 2 — an explicit operator revoke intent is stronger than token-state drift; wrappers hard-fail rather than fall-through.
- A consume attempt against a token whose `agent_id` differs from `$CLAVAIN_AGENT_ID` exits 4, even if the signature verifies and the token is unconsumed. Bearer-by-string is explicitly rejected.
- Consume wraps the token UPDATE and the authorizations INSERT in one `BEGIN...COMMIT`. A forced process kill after the UPDATE but before the INSERT rolls back both — the token remains consumable, the audit log has no orphaned record. Test `TestConsumeToken_PartialFailure_Atomic` forces this via a `CONSUME_FAULT_INJECT_AFTER_UPDATE=1` hook gated behind a `// +build testfault` tag.
- A second `policy token consume` on the same token exits 2, and the audit log (`authorizations`) contains exactly one `op=<o>,target=<t>` entry for the consume pair.
- `clavain-cli policy token delegate --from=<parent> --to=<child-agent> --ttl=<d>` exits 0 only when `$CLAVAIN_AGENT_ID` matches the parent's `agent_id`; otherwise exit 4 (POP failure, logged as `ERROR auth-failure: pop-mismatch`). The child token has `parent_token=<parent.id>`, `root_token=<parent.root_token if set else parent.id>`, `depth=parent.depth+1`. `depth > 3` is refused at CLI layer, database layer (CHECK constraint), AND inside the insert transaction (re-SELECT parent.depth under serialized MaxOpenConns=1 to close TOCTOU on concurrent delegates).
- A child token's scope cannot widen: `op` and `target` must match the parent exactly; `ttl` must be ≤ parent's remaining lifetime. `DelegateToken` takes a `DelegateSpec` struct; no positional string args for `parentID/callerAgentID/toAgentID`.
- `clavain-cli policy token revoke --token=<id>` without `--cascade` sets `revoked_at=now` via `UPDATE authz_tokens SET revoked_at=? WHERE id=? AND revoked_at IS NULL` on the target row only.
- `clavain-cli policy token revoke --token=<id> --cascade` requires the target to be a *root* token (parent_token IS NULL AND root_token IS NULL). It uses `UPDATE authz_tokens SET revoked_at=? WHERE (id=? OR root_token=?) AND revoked_at IS NULL` binding `target.id` to both positions — this correctly revokes the root + every descendant in one scan against `tokens_by_root`. A `--cascade` call on a non-root token exits 4 with class=cascade-on-non-root (descendants' `root_token` denormalizes to the chain root, so a mid-chain cascade predicate would miss them — we refuse rather than silently half-revoke). Mid-chain cascade is a v2.x concern requiring a recursive CTE over `parent_token`.
- A consume attempt on any revoked row exits 4 (auth-failure, class=revoked). The gate wrapper hard-fails; legacy fall-through would let the operator's revoke intent be silently overridden by a legacy policy rule.
- `ic publish --patch` on an agent-authored commit with `CLAVAIN_AUTHZ_TOKEN=<publish-scoped-token>` in env succeeds without reading `.publish-approved`, and the publish approval audit row references `root_token`. The env var is unset after consume (both in the `ic` process and propagated-up such that child commits don't inherit).
- Running `ic publish --patch` with the same token twice rejects the second call (exit 2, already-consumed) and writes a stderr message pointing at the audit row.
- `policy audit --tokens` shows the full delegation tree per root token (indent by `depth`), consumed/revoked/expired state per row, and fingerprints for issuer signatures.
- Pre-v2 rows in `authorizations` continue to verify under v1.5's `sig_version=1` path. A v2 consume-audit row lands as `sig_version=1` authorizations (it's a v1.5-shaped row — the *token* is sig_version=2, but the consume event's audit record is a plain authz row).
- Cross-project tokens are refused: `policy token consume` from a project whose `.clavain/intercore.db` does not contain the token row exits 4 (auth-failure, class=cross-project) with a stderr message pointing at `docs/canon/authz-token-model.md §v2.1` for the roadmap.
- `RequiresApproval(pluginRoot, tokenStr, db)` takes its dependencies explicitly. It does NOT call `os.Getenv` and does NOT call `sql.Open`. The `ic publish` command handler reads env vars and the already-open `db` handle once at the top, passing them in. Testing does not require env setup.
- Task 6 installs a 30-day rolling measurement of `ic publish --patch` approvals by path (`token` vs `marker` vs `authz-record`). The baseline is collected during Task 6 implementation (current state: 100% marker). Marker-full-removal is gated on this telemetry — not a vague "95%". The decision gate is: *if token+authz-record share ≥90% over a 14-day window AND marker < 10% of window, open removal bead. If between 10-20% marker, keep deprecation warning for another 14-day window. If ≥20%, investigate why adoption stalled.*

**Artifacts:**
- `docs/canon/authz-token-model.md` (new) — normative: token lifecycle, delegation semantics, consume atomicity, revoke cascade, same-project-only scope, `sig_version=2` rationale, v2.1 roadmap.
- `docs/canon/authz-token-payload.md` (new) — canonical byte sequence for `sig_version=2` token rows. Same encoding rules as v1.5 payload, different field list. ≥3 worked examples: (a) root issue, (b) depth-1 delegation, (c) publish-scoped.
- `core/intercore/internal/db/migrations/034_authz_tokens.sql` (new, docs-only) — reference DDL.
- `core/intercore/internal/db/db.go` (modify) — inline DDL in the `if currentVersion >= 33 && currentVersion < 34 { ... }` branch, matching the SQL file.
- `core/intercore/pkg/authz/token.go` (new) — `Token`, `TokenSignRow`, `CanonicalTokenPayload`, `SignToken`, `VerifyToken`, `IssueToken`, `DelegateToken`, `ConsumeToken`, `RevokeToken`, `ListTokens`, `GetToken`. Distinct errors: `ErrAlreadyConsumed`, `ErrExpired`, `ErrNotFound`, `ErrSigVerify`, `ErrProofOfPossession`, `ErrRevoked`, `ErrCrossProject`, `ErrDepthExceeded`, `ErrScopeWidening`.
- `core/intercore/pkg/authz/token_test.go` (new) — golden-fixture canonical payload + round-trip sign/verify + all error classes.
- `os/Clavain/cmd/clavain-cli/authz_token.go` (new) — handlers for `policy token {issue,consume,delegate,revoke,list,show,verify}` + opaque-string parse (`<ulid>.<sighex>` → `(id, sig)`).
- `os/Clavain/cmd/clavain-cli/authz_token_test.go` (new) — one table-driven test per subcommand.
- `os/Clavain/cmd/clavain-cli/authz.go` (modify) — extend `cmdPolicy` switch with `case "token": return cmdPolicyToken(args[1:])`.
- `os/Clavain/scripts/gates/_common.sh` (modify) — `gate_token_consume` helper; wrappers short-circuit when env var set and consume succeeds.
- `os/Clavain/scripts/gates/{bead-close,git-push-main,bd-push-dolt,ic-publish-patch}.sh` (modify) — call `gate_token_consume` before `gate_check`.
- `core/intercore/internal/publish/approval.go` (modify) — `RequiresApproval()` also checks `$CLAVAIN_AUTHZ_TOKEN` via intercore; token path exits before marker-file fallback.
- `core/intercore/cmd/ic/publish.go` (modify if needed) — pass token env var through to `RequiresApproval`.
- `os/Clavain/scripts/authz-init.sh` (modify) — optional `--with-token-demo` flag that issues a sample token to validate end-to-end.
- `os/Clavain/README.md` (modify) — v2 section under *Auto-proceed authorization* with CLI cheat-sheet and the token-env-var pattern.
- `os/Clavain/tests/authz-v2-e2e_test.sh` (new) — full matrix: issue → delegate → consume → audit; revoke-cascade; double-consume; expired-token; cross-session round-trip; cross-project rejection.
- `docs/handoffs/latest.md` (symlink update) — point at this plan after Task 1 lands.

**Key Links:**
- Gate wrapper flow (token path): `gate_token_consume` → op → `gate_record` (records the op as an `authorizations` row referencing `root_token`) → `gate_sign`. The token *consume* is logged separately via `policy token consume`'s internal `authz.Record` call.
- Publish flow: `ic publish --patch` → `RequiresApproval(pluginRoot)` → if `$CLAVAIN_AUTHZ_TOKEN` set, attempt consume under scope=publish → on success, skip marker-file check AND skip v1.5 authz-record lookup (token path is authoritative).
- Verify walk: `policy audit --tokens` → for each root token, recursively list children via `WHERE parent_token=?` (up to depth 3) → render tree.
- Sig verification order: pre-parse opaque string into `(id, sig_bytes)` → load row by `id` → recompute `CanonicalTokenPayload(row)` → `ed25519.Verify(projectPub, payload, sig_bytes)`.

---

## Task 1: Spec-lock round — token model + token payload (no code)

**Files:**
- Create: `docs/canon/authz-token-model.md`
- Create: `docs/canon/authz-token-payload.md`
- Modify: `docs/brainstorms/2026-04-19-auto-proceed-authz-design.md:~230` (backlink to both canon docs)
- Modify: `docs/handoffs/latest.md` (symlink update)

**Step 1: Write `docs/canon/authz-token-model.md`** — normative. Cover:
(a) Lifecycle: issued → (delegated → )* → consumed | revoked | expired. No re-issue; revoked ≠ expired ≠ consumed (three terminal states with distinct audit semantics).
(b) Scope: `op` + `target` + `agent_id` (who may present — enforced at consume time, not bearer-by-string) + optional `bead_id`. Scope narrowing only — `op` and `target` must match parent exactly in delegate; `ttl` must be ≤ remaining parent lifetime.
(c) Delegation: linear chain, max depth 3 (schema CHECK + CLI enforcement + in-transaction re-SELECT). `root_token` denormalized. DAG explicitly deferred; document the locations that hard-assume chain: (i) `DelegateToken`'s single-parent signature, (ii) `Token.ParentToken string` field, (iii) scope-narrowing compares against one parent row, (iv) cascade revoke predicate assumes single `root_token`. v2.x DAG migration must revisit all four.
(d) Proof-of-possession: `callerAgentID == parent.AgentID` at delegate time AND `callerAgentID == token.AgentID` at consume time. Ship-blocker rationale reproduced. The CLI reads `$CLAVAIN_AGENT_ID`; library functions take `callerAgentID` as parameter (no ambient env reads in library code).
(e) Atomic consume contract: single transaction wrapping (1) `UPDATE ... WHERE id=? AND consumed_at IS NULL AND revoked_at IS NULL AND expires_at > ? AND agent_id=?` with `RowsAffected()` discrimination and (2) `INSERT INTO authorizations` for the consume-audit row. Partial-failure between (1) and (2) must roll back (1). Exit-code table (0/1/2/3/4; 5 codes total, down from r1's 9) — error-class discrimination via stderr classifier line, not numeric code.
(f) Cascade revoke: one UPDATE `WHERE id=? OR root_token=?` with `target.id` bound to both positions. This correctly revokes the target row + all descendants (for root revokes where `target.root_token IS NULL`, the `id=?` disjunct covers the target and the `root_token=?` disjunct covers descendants since descendants' `root_token` equals the root's `id`). Why this matters: r1 had `WHERE root_token = target.root_token`; for a root target with NULL root_token, SQL NULL semantics would match zero rows, silently breaking cascade. Write-time revoke is primary; read-time verify is an additional guard.
(g) Same-project scope: v2 refuses cross-project consumption. Document the v2.1 upgrade path (cross-project-id column + multi-project pubkey registry + registry-lookup in consume path).
(h) Relationship to v1.5 audit: token issue/consume/revoke events also land as `authorizations` rows (sig_version=1). The token itself is sig_version=2.
(i) Threat model delta from v1.5: what tokens add (atomic single-use, delegation traceability, cascade revoke, caller-identity binding), what they don't (signer-key-holder forgery — still the v1.6 out-of-band signer problem, inherited from v1.5).
(j) Env var hygiene: `CLAVAIN_AUTHZ_TOKEN` is unset by the consuming process after a successful consume. Child processes spawned *before* consume inherit the token (that's the delegation mechanism); processes spawned *after* do not. README must avoid `export CLAVAIN_AUTHZ_TOKEN=...` forms that bake it into shell history; prefer `CLAVAIN_AUTHZ_TOKEN=<tok> ic publish --patch` one-shot form.

**Step 2: Write `docs/canon/authz-token-payload.md`** — pin the exact byte sequence for `sig_version=2`. Field order:
```
id
op_type
target
agent_id
bead_id
delegate_to
expires_at
issued_by
parent_token
root_token
depth
created_at
```
12 fields. Encoding rules identical to v1.5 (NFC, LF separator, no trailing LF, UTF-8, no CR, empty-string for NULL, decimal integers). Three worked examples:
(i) Root issue: parent_token="", root_token="", depth=0, delegate_to="".
(ii) Depth-1 delegate: parent_token=<ulid>, root_token=<same ulid as parent>, depth=1, delegate_to=<child agent>.
(iii) Publish-scoped: op="ic-publish-patch", target=<plugin-slug>, bead_id=<bead>, depth=0.
Each example shows the exact byte sequence going into Ed25519 (LF expanded to literal `\n` for reader clarity, note that real bytes are raw LF).

**Step 3: Add brainstorm backlink + update handoff symlink**
```bash
# Append a one-line pointer at the end of the v2 section of the brainstorm
# Update docs/handoffs/latest.md to point to the v2 plan once Task 1 lands
```

**Step 4: Commit**
```bash
git add docs/canon/authz-token-model.md docs/canon/authz-token-payload.md docs/brainstorms/2026-04-19-auto-proceed-authz-design.md docs/handoffs/latest.md
git commit -m "docs(authz): spec-lock v2 token model + canonical payload (sylveste-qdqr.28)"
```

<verify>
- run: `test -f docs/canon/authz-token-model.md && test -f docs/canon/authz-token-payload.md && grep -c '^### Example' docs/canon/authz-token-payload.md`
  expect: contains "3"
- run: `grep -c 'sig_version=2\|sig_version = 2' docs/canon/authz-token-payload.md`
  expect: contains "1"
</verify>

---

## Task 2: Migration 034 — `authz_tokens` table + cutover marker

**Files:**
- Create: `core/intercore/internal/db/migrations/034_authz_tokens.sql` (docs-only reference)
- Modify: `core/intercore/internal/db/db.go` (inline DDL branch at end of chain)
- Modify: `core/intercore/internal/db/db_test.go` (add `TestMigration034_*`)

**Step 1: Write migration SQL (documentation)**
```sql
-- migration 034 — authz_tokens: unforgeable token protocol with delegation chain.
-- See docs/canon/authz-token-model.md for semantics.
-- Real DDL lives inline in db.go under "if currentVersion >= 33 && currentVersion < 34".

CREATE TABLE authz_tokens (
    id            TEXT PRIMARY KEY,                 -- ULID (Crockford base32)
    op_type       TEXT NOT NULL,
    target        TEXT NOT NULL,
    agent_id      TEXT NOT NULL,                    -- who may present this token
    bead_id       TEXT,                             -- optional scope to a bead
    delegate_to   TEXT,                             -- NULL (root) or child agent id
    expires_at    INTEGER NOT NULL,                 -- unix seconds
    consumed_at   INTEGER,                          -- NULL until atomic consume lands
    revoked_at    INTEGER,                          -- NULL unless revoked
    issued_by     TEXT NOT NULL,                    -- agent id or "user"
    parent_token  TEXT REFERENCES authz_tokens(id) ON DELETE RESTRICT,
    root_token    TEXT,                             -- first ancestor; NULL for roots
    depth         INTEGER NOT NULL DEFAULT 0 CHECK (depth <= 3),
    sig_version   INTEGER NOT NULL DEFAULT 2,
    signature     BLOB NOT NULL,
    created_at    INTEGER NOT NULL
);

CREATE INDEX tokens_by_root      ON authz_tokens(root_token, consumed_at, revoked_at);
CREATE INDEX tokens_by_parent    ON authz_tokens(parent_token);
CREATE INDEX tokens_by_expiry    ON authz_tokens(expires_at) WHERE consumed_at IS NULL AND revoked_at IS NULL;

-- Cutover marker: a synthetic authz row that marks migration-034 cutover.
-- Lives in `authorizations` (not `authz_tokens`), sig_version=1 (v1.5-shaped).
-- Purpose: audit tools can distinguish a pre-v2 DB (no marker) from a v2 DB
-- with zero tokens issued yet (marker present, authz_tokens empty).
--
-- Idempotent: fixed primary key + INSERT OR IGNORE. Re-running the migration
-- (e.g., test harness that calls Migrate() twice) produces no duplicate row.
-- Mirrors the v1.5 migration-033 marker pattern.
INSERT OR IGNORE INTO authorizations (
    id, op_type, target, agent_id, mode, created_at, sig_version
) VALUES (
    'migration-034-tokens-enabled',
    'migration.tokens-enabled',
    'authz_tokens',
    'system:migration-034',
    'auto',
    strftime('%s','now'),
    1
);
```

**Step 2: Add inline branch to `db.go`** — match the SQL file verbatim. Immediately after the `if currentVersion >= 32 && currentVersion < 33 { ... }` block that landed in v1.5:
```go
if currentVersion >= 33 && currentVersion < 34 {
    stmts := []string{
        `CREATE TABLE authz_tokens ( ... )`,
        `CREATE INDEX tokens_by_root ...`,
        `CREATE INDEX tokens_by_parent ...`,
        `CREATE INDEX tokens_by_expiry ...`,
        `INSERT INTO authorizations (...) VALUES (...)`,
    }
    for _, s := range stmts {
        if _, err := tx.ExecContext(ctx, s); err != nil {
            return fmt.Errorf("migration 034: %w", err)
        }
    }
    if _, err := tx.ExecContext(ctx, `PRAGMA user_version = 34`); err != nil {
        return err
    }
}
```

**Step 3: Bump `currentSchemaVersion` to 34.**

**Step 4: Write failing test** (`db_test.go`):
```go
func TestMigration034_TableExists(t *testing.T) { /* authz_tokens columns present */ }
func TestMigration034_DepthCheckConstraint(t *testing.T) { /* INSERT depth=4 fails */ }
func TestMigration034_IndexesExist(t *testing.T) { /* all three indexes present */ }
func TestMigration034_CutoverMarker(t *testing.T) { /* op_type='migration.tokens-enabled' row exists */ }
func TestMigration034_FreshDBSkipsCutover(t *testing.T) { /* fresh DB at v34 still has the marker (path through migration) */ }
```

**Step 5: Run — expect FAIL.** Add DDL. **Run — expect PASS.**

**Step 6: Commit**
```bash
git add core/intercore/internal/db/migrations/034_authz_tokens.sql core/intercore/internal/db/db.go core/intercore/internal/db/db_test.go
git commit -m "feat(intercore): authz_tokens table + cutover marker (migration 034, sylveste-qdqr.28)"
```

<verify>
- run: `cd core/intercore && go test ./internal/db/ -run TestMigration034 -v`
  expect: exit 0
</verify>

---

## Task 3: `pkg/authz/token.go` — token primitives + lifecycle functions

**Files:**
- Create: `core/intercore/pkg/authz/token.go`
- Create: `core/intercore/pkg/authz/token_test.go`

**Step 1: Types + canonical payload**
```go
package authz

import (
    "crypto/ed25519"
    "database/sql"
    "errors"
    "fmt"
    "strconv"
    "strings"
    "time"

    "github.com/oklog/ulid/v2"
    "golang.org/x/text/unicode/norm"
)

// Token mirrors one authz_tokens row; all nullable DB fields are empty-string
// or zero for canonical-payload consistency.
type Token struct {
    ID           string // ULID
    OpType       string
    Target       string
    AgentID      string
    BeadID       string // empty if NULL
    DelegateTo   string // empty if NULL
    ExpiresAt    int64
    ConsumedAt   int64 // 0 if NULL; not part of signed payload
    RevokedAt    int64 // 0 if NULL; not part of signed payload
    IssuedBy     string
    ParentToken  string // empty if NULL (root)
    RootToken    string // empty if NULL (root)
    Depth        int    // 0 for root
    SigVersion   int    // always 2 for v2
    Signature    []byte
    CreatedAt    int64
}

// tokenSignedFields: 12 fields, v2 sig_version. Order and set are frozen;
// changes require sig_version=3 and a parallel path. Keep aligned with
// docs/canon/authz-token-payload.md.
var tokenSignedFields = []string{
    "id", "op_type", "target", "agent_id", "bead_id",
    "delegate_to", "expires_at", "issued_by", "parent_token",
    "root_token", "depth", "created_at",
}

func CanonicalTokenPayload(t Token) ([]byte, error) { /* NFC + LF join; reject control chars per v1.5 rules */ }
func SignToken(priv ed25519.PrivateKey, t Token) ([]byte, error) { /* CanonicalTokenPayload + ed25519.Sign */ }
func VerifyToken(pub ed25519.PublicKey, t Token, sig []byte) bool { /* length gate + CanonicalTokenPayload + ed25519.Verify */ }
```

**Step 2: Opaque string codec**
```go
// TokenString encodes/decodes the <ulid>.<sighex> form carried in env vars.
// Exactly one "." separator. ULID is 26 chars base32 Crockford (ulid pkg
// validates). Signature hex is 128 chars (64 bytes × 2).
func EncodeTokenString(id string, sig []byte) string
func ParseTokenString(s string) (id string, sig []byte, err error) // distinct errors for bad-format, bad-ulid, bad-hex, wrong-siglen
```

**Step 3: Error classes**
```go
var (
    // token-state class (CLI exit 2 — wrapper falls through to legacy check)
    ErrAlreadyConsumed    = errors.New("authz-token: already consumed")
    ErrExpired            = errors.New("authz-token: expired")

    // not-found class (CLI exit 3 — wrapper falls through to legacy check)
    ErrNotFound           = errors.New("authz-token: not found")
    ErrBadTokenString     = errors.New("authz-token: malformed token string")

    // auth-failure class (CLI exit 4 — wrapper HARD-FAILS, no legacy fall-through)
    ErrSigVerify             = errors.New("authz-token: signature verification failed")
    ErrProofOfPossession     = errors.New("authz-token: caller agent_id does not match parent token agent_id (delegate)")
    ErrCallerAgentMismatch   = errors.New("authz-token: caller agent_id does not match token agent_id (consume)")
    ErrCrossProject          = errors.New("authz-token: cross-project consumption not permitted in v2")
    ErrScopeWidening         = errors.New("authz-token: child scope must not widen parent scope")
    ErrDepthExceeded         = errors.New("authz-token: delegation depth cap (3) exceeded")
    ErrExpectMismatch        = errors.New("authz-token: --expect-op/--expect-target did not match token scope")
    ErrRevoked               = errors.New("authz-token: revoked — operator explicitly invalidated this token")  // r3: auth-failure, not token-state
    ErrCascadeOnNonRoot      = errors.New("authz-token: --cascade only allowed on root tokens in v2")           // r3 new
)

// ExitCode classifies library errors into the 5-class CLI exit space.
// 0 = nil error; 1 = unexpected (unwrapped/IO); 2 = token-state; 3 = not-found;
// 4 = auth-failure. Wrappers discriminate on this, never on sentinel identity.
//
// r3 change: ErrRevoked moved from token-state (exit 2) to auth-failure (exit 4).
// An operator-issued revoke is a stronger intent signal than "expired naturally";
// falling through to legacy policy would silently override the revoke.
func ExitCode(err error) int {
    switch {
    case err == nil:
        return 0
    case errors.Is(err, ErrAlreadyConsumed),
         errors.Is(err, ErrExpired):
        return 2
    case errors.Is(err, ErrNotFound),
         errors.Is(err, ErrBadTokenString):
        return 3
    case errors.Is(err, ErrSigVerify),
         errors.Is(err, ErrProofOfPossession),
         errors.Is(err, ErrCallerAgentMismatch),
         errors.Is(err, ErrCrossProject),
         errors.Is(err, ErrScopeWidening),
         errors.Is(err, ErrDepthExceeded),
         errors.Is(err, ErrExpectMismatch),
         errors.Is(err, ErrRevoked),              // r3: now auth-failure
         errors.Is(err, ErrCascadeOnNonRoot):     // r3 new
        return 4
    default:
        return 1
    }
}

// ErrClass returns the stderr classifier string (`ERROR <class>: <reason>`)
// used by the CLI for wrapper consumption. Library callers never rely on the
// string form.
func ErrClass(err error) string { /* ... */ }
```
Rationale: 11 library errors for test expressivity; 5 exit codes for wrapper simplicity. `ExitCode()` is the single mapping point — tests assert both the library error and the exit code to catch drift.

**Step 4: Lifecycle functions** — all take `db *sql.DB` (intercore convention) and honor `SetMaxOpenConns(1)`. No `os.Getenv` inside library code — all identity and time values are explicit parameters.

```go
// IssueToken generates a ULID, signs, inserts. Returns the Token + opaque string.
func IssueToken(db *sql.DB, priv ed25519.PrivateKey, spec IssueSpec, now int64) (Token, string, error)

type IssueSpec struct {
    OpType, Target, AgentID, BeadID, IssuedBy string
    TTL                                       time.Duration
}

// DelegateToken enforces:
//   - POP: spec.CallerAgentID == parent.AgentID (else ErrProofOfPossession)
//   - Scope: spec.ChildOpType == parent.OpType, spec.ChildTarget == parent.Target (else ErrScopeWidening;
//           note: caller-API deliberately does not accept op/target overrides — if a future version needs
//           them, add explicit fields; do not silently allow).
//   - Depth: parent.Depth + 1 <= 3 (else ErrDepthExceeded); also re-SELECT parent.Depth inside the
//           insert transaction to defeat concurrent-delegate races under MaxOpenConns=1.
//   - TTL clamp: child.ExpiresAt = min(now + spec.RequestedTTL, parent.ExpiresAt)
func DelegateToken(db *sql.DB, priv ed25519.PrivateKey, spec DelegateSpec, now int64) (Token, string, error)

type DelegateSpec struct {
    ParentID       string        // ULID of parent token
    CallerAgentID  string        // from $CLAVAIN_AGENT_ID at CLI layer
    ToAgentID      string        // recipient (child) agent
    RequestedTTL   time.Duration // clamped against parent remaining
}

// ConsumeToken wraps two writes in ONE transaction:
//   (1) UPDATE authz_tokens SET consumed_at=?
//         WHERE id=?
//           AND consumed_at IS NULL
//           AND revoked_at IS NULL
//           AND expires_at > ?
//           AND agent_id = ?                -- caller-identity binding
//   (2) INSERT INTO authorizations (...) VALUES (...)
//         -- v1.5-shaped audit row; sig_version=1; signature via authz.Sign
// If (1) affects 0 rows, tx.Rollback; re-SELECT the row by id to classify the
// failure (not-found / already-consumed / revoked / expired / agent-mismatch)
// and return the matching ErrXxx. The signature-verify check happens BEFORE
// the transaction opens — verify failure returns ErrSigVerify with no DB write.
// expectOp / expectTarget may be empty strings; when non-empty, must match
// token scope exactly (else ErrExpectMismatch, pre-transaction).
func ConsumeToken(db *sql.DB, pub ed25519.PublicKey, tokenStr, callerAgentID, expectOp, expectTarget string, now int64) (Token, error)

// RevokeToken sets revoked_at.
//
// Non-cascade (cascade=false):
//   UPDATE authz_tokens SET revoked_at=? WHERE id=? AND revoked_at IS NULL
// Works for any token (root or non-root). Only the target row is flagged.
//
// Cascade (cascade=true):
//   FIRST verify target.parent_token IS NULL AND target.root_token IS NULL.
//   If the target is NOT a root, return ErrCascadeOnNonRoot without writing.
//   Otherwise:
//     UPDATE authz_tokens SET revoked_at=? WHERE (id=? OR root_token=?) AND revoked_at IS NULL
//   binding target.id to both positions. This correctly flags the root +
//   every descendant (descendants' root_token = root.id).
//
// Why no mid-chain cascade: descendants denormalize root_token to the chain
// root, not immediate ancestors. A mid-chain cascade would need either (a) a
// recursive CTE traversing parent_token, or (b) a re-denormalization on
// delegate. Both are v2.x concerns; v2 refuses rather than half-revoke.
//
// Returns rows_affected. Double-revoke is idempotent via "AND revoked_at IS NULL".
func RevokeToken(db *sql.DB, tokenID string, cascade bool, now int64) (revokedCount int, err error)

// Accessors (read-only)
func GetToken(db *sql.DB, tokenID string) (Token, error)
func ListTokens(db *sql.DB, filter ListFilter) ([]Token, error)
```

**TOCTOU notes:**
- Signature verification happens BEFORE the transaction. Signed fields are immutable by schema intent (only `consumed_at` and `revoked_at` mutate); the pre-tx verify is therefore safe against a concurrent UPDATE that only touches those fields.
- Depth-cap race: two concurrent `DelegateToken(parent=P)` both see `P.depth=2` → both try to INSERT `depth=3`. Under MaxOpenConns=1 transactions serialize, but the CHECK constraint alone would allow both. The in-transaction re-SELECT of `parent.depth` is belt-and-suspenders; strict correctness already falls out of MaxOpenConns=1 + transactional INSERT, but the re-SELECT documents intent and survives future pool-size changes.
- Cascade-revoke vs consume race: under MaxOpenConns=1, the cascade UPDATE and a concurrent ConsumeToken's UPDATE serialize against each other. If cascade lands first, consume's WHERE clause sees `revoked_at IS NOT NULL` and affects 0 rows → returns ErrRevoked. If consume lands first, it succeeds; the subsequent cascade still sets revoked_at on the already-consumed row (harmless for audit; the consume is final). Tested explicitly.

**Step 5: Tests (`token_test.go`)** — golden-fixture coverage for every error class and happy path:
```go
TestCanonicalTokenPayload_GoldenFixtures      // matches the 3 examples in docs/canon/authz-token-payload.md byte-for-byte
TestSignToken_RoundTrip
TestVerifyToken_RejectsMutation               // mutate each of 12 fields; each causes verify=false
TestVerifyToken_RejectsWrongSigLen
TestTokenString_RoundTrip
TestParseTokenString_ErrorClasses             // bad-format, bad-ulid, bad-hex, wrong-siglen
TestIssueToken_WritesRow                      // row present, sig verifies under loaded pub
TestDelegateToken_POPEnforced                 // caller != parent.AgentID → ErrProofOfPossession
TestDelegateToken_DepthCap                    // depth=3 delegate → ErrDepthExceeded
TestDelegateToken_DepthCap_ConcurrentRace     // two concurrent delegates against depth=2 parent → both cannot exceed cap
TestDelegateToken_ScopeNarrowing              // spec has no op/target override fields; API-level guarantee
TestDelegateToken_TTLClamp                    // requested TTL > remaining → child.expires_at == parent.expires_at
TestDelegateToken_UsesSpecStruct              // compile-time: signature is DelegateSpec, not positional strings
TestConsumeToken_Atomic_FirstWins             // N=8 goroutines → exactly 1 success, 7 ErrAlreadyConsumed
TestConsumeToken_PartialFailure_Atomic        // fault-injected INSERT failure → UPDATE rolled back; token still consumable
TestConsumeToken_CallerAgentMismatch          // token.AgentID=A, callerAgentID=B → ErrCallerAgentMismatch (exit 4)
TestConsumeToken_ExpectOpMismatch             // expectOp != token.OpType → ErrExpectMismatch
TestConsumeToken_ExpectTargetMismatch         // expectTarget != token.Target → ErrExpectMismatch
TestConsumeToken_EmptyExpectSkipsCheck        // expectOp="" and expectTarget="" → passes (backward-compat)
TestConsumeToken_Expired                      // expires_at in past → ErrExpired
TestConsumeToken_Revoked                      // revoked_at set → ErrRevoked
TestConsumeToken_NotFound                     // random ULID → ErrNotFound
TestConsumeToken_BadSig                       // signature bytes mutated → ErrSigVerify
TestConsumeToken_AuditRowWritten              // after success, authorizations has the consume row, sig_version=1
TestConsumeToken_NoAuditRowOnRollback         // after PartialFailure test, authorizations has no orphan
TestRevokeToken_CascadeFromRoot_NullRootToken // CRITICAL: revoke root (root_token IS NULL) → target + all descendants flagged; catches r1 NULL bug
TestRevokeToken_CascadeOnNonRoot_Refused      // r3: revoke --cascade on mid-chain returns ErrCascadeOnNonRoot, no rows flagged
TestRevokeToken_NonCascade                    // --no-cascade revoke any node → only that row
TestRevokeToken_Idempotent                    // revoke twice → revoked_at unchanged (AND revoked_at IS NULL predicate)
TestConsumeToken_RevokedExitsAuthFailure      // r3: consume revoked → ErrRevoked → ExitCode returns 4, not 2
TestRevokeVsConsume_Race                      // revoke + consume in parallel against same token → exactly one semantically wins; both leave consistent state
TestListTokens_FilterByRoot
TestExitCode_Mapping                          // table-driven: each ErrXxx → expected exit code (0/1/2/3/4)
```
Concurrency tests use `t.Parallel()` + `sync.WaitGroup`. The fault-injection for partial-failure uses a build-tagged testfault hook (`// +build testfault`) that returns an error from the INSERT path when `CONSUME_FAULT_INJECT_AFTER_UPDATE=1`.

**Step 6: Commit**
```bash
git add core/intercore/pkg/authz/token.go core/intercore/pkg/authz/token_test.go
git commit -m "feat(authz): token primitives — issue/delegate/consume/revoke with POP + atomic single-use (sylveste-qdqr.28)"
```

<verify>
- run: `cd core/intercore && GOTOOLCHAIN=local go test ./pkg/authz/ -run 'TestCanonicalToken|TestSignToken|TestVerifyToken|TestTokenString|TestParseTokenString|TestIssueToken|TestDelegateToken|TestConsumeToken|TestRevokeToken|TestListTokens' -v -race`
  expect: exit 0
</verify>

---

## Task 4: `clavain-cli policy token {issue,consume,delegate,revoke,list,show,verify}`

**Files:**
- Create: `os/Clavain/cmd/clavain-cli/authz_token.go`
- Create: `os/Clavain/cmd/clavain-cli/authz_token_test.go`
- Modify: `os/Clavain/cmd/clavain-cli/authz.go` (extend `cmdPolicy` switch)

**Step 1: Extend `cmdPolicy` dispatcher in `authz.go`**
```go
// in cmdPolicy:
case "token":
    return cmdPolicyToken(args[1:])
```

**Step 2: `cmdPolicyToken` dispatcher**
```go
func cmdPolicyToken(args []string) error {
    if len(args) == 0 { return usagePolicyToken() }
    switch args[0] {
    case "issue":    return cmdPolicyTokenIssue(args[1:])
    case "consume":  return cmdPolicyTokenConsume(args[1:])
    case "delegate": return cmdPolicyTokenDelegate(args[1:])
    case "revoke":   return cmdPolicyTokenRevoke(args[1:])
    case "list":     return cmdPolicyTokenList(args[1:])
    case "show":     return cmdPolicyTokenShow(args[1:])
    case "verify":   return cmdPolicyTokenVerify(args[1:])
    default:         return usagePolicyToken()
    }
}
```

**Step 3: Handler spec (each uses flag.NewFlagSet; exit codes 0/1/2/3/4 via `authz.ExitCode`)**
- `cmdPolicyTokenIssue(args)` → flags `--op --target --for --ttl --bead`; loads priv key; reads `$CLAVAIN_AGENT_ID` as `issuedBy`; calls `authz.IssueToken(db, priv, spec, time.Now().Unix())`; prints opaque string on stdout; records audit row via existing `authz.Record` (sig_version=1).
- `cmdPolicyTokenConsume(args)` → flags `--token` (else reads `$CLAVAIN_AUTHZ_TOKEN`) `--expect-op` `--expect-target` (both optional but recommended; wrappers always pass). Loads pub key; reads `$CLAVAIN_AGENT_ID` as `callerAgentID`; calls `authz.ConsumeToken(db, pub, tokenStr, callerAgentID, expectOp, expectTarget, time.Now().Unix())`. On success, prints `unset CLAVAIN_AUTHZ_TOKEN` to stdout (evaluable) and exits 0. On error, prints `ERROR <class>: <reason>` to stderr and exits via `authz.ExitCode(err)`. The consume-audit row is written INSIDE `ConsumeToken`'s transaction (not by this handler).
- `cmdPolicyTokenDelegate(args)` → flags `--from --to --ttl`; reads `$CLAVAIN_AGENT_ID` as `callerAgentID`; populates `DelegateSpec{ParentID, CallerAgentID, ToAgentID, RequestedTTL}`; calls `authz.DelegateToken`; exit codes 0 (success, prints new opaque string) / 4 (POP | scope-widen | depth-exceeded, via `ExitCode`).
- `cmdPolicyTokenRevoke(args)` → flags `--token --cascade --issued-since`. `--issued-since` variant bulk-revokes all not-yet-consumed tokens since a timestamp.
- `cmdPolicyTokenList(args)` → flags `--root --agent --op --status`; JSON or human output.
- `cmdPolicyTokenShow(args)` → `--token <id>`; shows full row + signature fingerprint + verification status + delegation tree rooted here.
- `cmdPolicyTokenVerify(args)` → `--token <opaque>`; exits 0 if sig verifies, 4 otherwise (auth-failure). Does NOT consume.

**Env var unset on success (sentinel-wrapped for r3 safety)**: the consume handler prints to stdout (in this exact order, no other output unless `-v/--json`):
```
# authz-unset-begin
unset CLAVAIN_AUTHZ_TOKEN
# authz-unset-end
```
Interactive callers use `eval "$(clavain-cli policy token consume ...)"` to clear the var. The sentinel lines let a paranoid caller grep the output and reject if the region contains anything beyond the single `unset` line. Reduces the `eval` attack surface if the CLI binary is ever compromised and emits extra stdout. Bash wrappers (Task 5) do NOT use `eval` — they `unset` directly in-process because they already know the outcome from the exit code.

**Step 4: Tests (`authz_token_test.go`)** — one table per handler, exercising each exit code path. Use `tmp` intercore DB fixture (same pattern as `authz_test.go`).

**Step 5: Commit**
```bash
git add os/Clavain/cmd/clavain-cli/authz_token.go os/Clavain/cmd/clavain-cli/authz_token_test.go os/Clavain/cmd/clavain-cli/authz.go
git commit -m "feat(clavain-cli): policy token {issue,consume,delegate,revoke,list,show,verify} (sylveste-qdqr.28)"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && GOTOOLCHAIN=local go test -run 'TestPolicyToken' -v`
  expect: exit 0
- run: `~/.local/bin/clavain-cli policy token 2>&1 | head -1`
  expect: contains "Usage: policy token"
</verify>

---

## Task 5: Gate wrapper `gate_token_consume` + short-circuit integration

**Files:**
- Modify: `os/Clavain/scripts/gates/_common.sh`
- Modify: `os/Clavain/scripts/gates/bead-close.sh`
- Modify: `os/Clavain/scripts/gates/git-push-main.sh`
- Modify: `os/Clavain/scripts/gates/bd-push-dolt.sh`
- Modify: `os/Clavain/scripts/gates/ic-publish-patch.sh`
- Modify: `os/Clavain/scripts/gates/gates-smoke_test.sh` (token-path assertions)

**Step 1: `gate_token_consume` in `_common.sh`**
```bash
# gate_token_consume: if $CLAVAIN_AUTHZ_TOKEN is set, attempt to consume it
# under the given scope. Exit codes (from authz.ExitCode mapping):
#   0 → success: short-circuit (GATE_CONSUMED=1), unset token in this process.
#   2 → token-state (consumed/expired/revoked): fall through to legacy check.
#         Revoked is indistinguishable from consumed/expired here because the
#         CLI stderr line carries the class; wrappers log it but all three
#         mean "token can't authorize, try legacy". This is safe: a revoked
#         token defeats token-path auth, and the legacy policy still enforces
#         its own rules. A NON-revocable auth failure (class 4) WOULD be
#         dangerous to fall through, so we don't.
#   3 → not-found (bad string / stale ULID): fall through to legacy check.
#   4 → auth-failure (sig-verify / POP / scope-widen / caller-mismatch /
#         cross-project / expect-mismatch): HARD FAIL. The operator's auth
#         intent was malformed or the token is unusable for the op. Falling
#         through would let a mismatched token's presence silently not matter.
#   1 → unexpected (DB/IO): HARD FAIL with explicit error.
#
# GATE_CONSUMED=1 on success, 0 on fall-through. Hard failures return 1 from
# this function (caller exits).
gate_token_consume() {
    local op="$1" target="$2"
    GATE_CONSUMED=0
    [[ -z "${CLAVAIN_AUTHZ_TOKEN:-}" ]] && return 0

    local rc out
    out=$(clavain-cli policy token consume \
        --token="$CLAVAIN_AUTHZ_TOKEN" \
        --expect-op="$op" \
        --expect-target="$target" 2>&1)
    rc=$?

    case "$rc" in
        0)
            GATE_CONSUMED=1
            # Unset in this process (belt; CLI stdout may also emit
            # 'unset CLAVAIN_AUTHZ_TOKEN' for eval in interactive shells).
            unset CLAVAIN_AUTHZ_TOKEN
            echo "authz: token consumed for ${op} ${target}" >&2
            return 0
            ;;
        2)
            # Token-state fall-through: already-consumed OR expired ONLY.
            # Revoked is NOT in this class (r3) — revoked maps to exit 4.
            echo "authz: token unusable (state — consumed or expired): ${out}" >&2
            echo "authz: falling back to policy check" >&2
            return 0
            ;;
        3)
            echo "authz: token unusable (not-found or malformed): ${out}" >&2
            echo "authz: falling back to policy check" >&2
            return 0
            ;;
        4)
            echo "authz: AUTH FAILURE — token rejected for this op: ${out}" >&2
            echo "authz: gate hard-fails; resolve the mismatch and retry" >&2
            return 1
            ;;
        1|*)
            echo "authz: unexpected token consume error (${rc}): ${out}" >&2
            echo "authz: gate hard-fails; this is a bug — check intercore DB" >&2
            return 1
            ;;
    esac
}
```
The key change across r2/r3: auth-failure (exit 4) is a hard gate failure, not a fall-through. r3 moved `revoked` from exit 2 to exit 4 because an operator revoke is an explicit invalidation, not a passive state drift — falling through to legacy policy would let a legacy-policy rule silently override the revoke intent. The remaining exit-2 classes (already-consumed, expired) ARE passive state drifts where fall-through to legacy is safe: the operator hasn't said "do not allow"; the token simply couldn't authorize on this path, and legacy policy's own gates still apply. Auth-failure classes (revoked | cascade-on-non-root | sig-verify | POP | scope-widen | caller-mismatch | cross-project | expect-mismatch) all hard-fail at the wrapper. Wrapper callers check `gate_token_consume` return code before `$GATE_CONSUMED`.

**Step 2: Wrapper modification pattern** (each of bead-close.sh, git-push-main.sh, bd-push-dolt.sh, ic-publish-patch.sh)
```bash
# At top of the wrapper, after sourcing _common.sh:
if ! gate_token_consume "<op-name>" "<target>"; then
    # Hard failure from token consume (auth-failure class or unexpected DB error).
    # Do NOT fall through; do NOT run the op.
    exit 1
fi

if [[ "$GATE_CONSUMED" == "1" ]]; then
    # Skip gate_check; op is authorized via token.
    # Still record the op as an authorizations row + sign (for audit parity).
    exec_op_then_record_and_sign "$@"
    exit $?
fi

# Legacy path (fall-through from gate_token_consume returning 0 + GATE_CONSUMED=0):
gate_check "<op>" "<target>"
exec_op_then_record_and_sign "$@"
```
Shape: three branches — (a) token hard-fail → exit immediately, (b) token success → short-circuit past `gate_check`, (c) token absent or state-invalid → legacy `gate_check` runs. The order is fixed: check token-consume return before `$GATE_CONSUMED` before legacy.

**Step 3: Smoke test extension** — new cases in `gates-smoke_test.sh`:
- Set a valid token, run wrapper, assert op succeeds, assert `GATE_CONSUMED=1`, assert token row has `consumed_at` set, assert `CLAVAIN_AUTHZ_TOKEN` is unset in a spawned child process (verify with `sh -c 'echo ${CLAVAIN_AUTHZ_TOKEN:-CLEAR}'`).
- Set an expired token, run wrapper, assert fall-through to `gate_check` (which also succeeds in the smoke env), assert stderr mentions "token unusable (state)".
- Set a revoked token, run wrapper, assert **hard fail** (exit 1 from wrapper), assert legacy `gate_check` did NOT run, assert stderr mentions "AUTH FAILURE" and "revoked". (r3: revoked is auth-failure class, not token-state; the operator's revoke intent is honored by refusing rather than by falling back to legacy policy that might allow.)
- Set a token with `--expect-op` mismatch (e.g., bead-close token against a git-push wrapper), run wrapper, assert **hard fail** (exit 1), assert legacy `gate_check` did NOT run (grep stderr for absence of legacy gate output), assert stderr mentions "AUTH FAILURE".
- Set a token signed with a foreign key, run wrapper, assert hard fail with "sig-verify".
- Set a token for agent=A while `CLAVAIN_AGENT_ID=B`, run wrapper, assert hard fail with "caller-mismatch".
- Leave env unset, run wrapper, assert legacy path unchanged.

**Step 4: Commit**
```bash
git add os/Clavain/scripts/gates/
git commit -m "feat(authz): gate wrappers short-circuit on valid token; legacy fall-through preserved (sylveste-qdqr.28)"
```

<verify>
- run: `bash os/Clavain/scripts/gates/gates-smoke_test.sh 2>&1 | tail -20`
  expect: contains "PASS"
- run: `bash os/Clavain/scripts/gates/gates-smoke_test.sh --focus=token 2>&1 | grep -c 'GATE_CONSUMED=1'`
  expect: contains "1"
</verify>

---

## Task 6: `ic publish --patch` consumes publish-scoped token; marker logs hard deprecation

**Files:**
- Modify: `core/intercore/internal/publish/approval.go`
- Modify: `core/intercore/internal/publish/approval_test.go`
- Modify: `core/intercore/cmd/ic/publish.go` (only if env var plumbing needs a tweak)

**Step 1: Extend `RequiresApproval` — dependencies threaded in, not pulled from env/global state.**
```go
// RequiresApproval order of precedence (first hit wins):
//   1. tokenStr (if non-empty) + scope matches op=ic-publish-patch target=<plugin-slug>
//      AND caller agent_id matches token.agent_id → returns false
//   2. Fresh signed authz record for this plugin (v1.5 behavior) → returns false
//   3. .publish-approved marker file (legacy, WARN-LOUD deprecation) → returns false
//   4. None → approval required (return true)
//
// Dependencies are explicit parameters; the function does NOT call os.Getenv,
// does NOT call sql.Open, does NOT read ambient state. cmd/ic/publish.go is
// the composition root that reads env vars + opens the DB + calls this.
func RequiresApproval(
    pluginRoot string,
    tokenStr string,          // from $CLAVAIN_AUTHZ_TOKEN at caller layer
    callerAgentID string,     // from $CLAVAIN_AGENT_ID at caller layer
    db *sql.DB,                // already-open intercore DB
    pub ed25519.PublicKey,     // already-loaded project pubkey
    now int64,                 // time.Now().Unix() at caller layer
) (needsApproval bool, viaPath string) {
    // returns (false, "token"|"authz-record"|"marker") on approval-granted,
    // (true, "none") on approval-needed.
    // The viaPath string is used by the telemetry subtask below.
}
```
The `cmd/ic/publish.go` handler threads all these: env vars → `RequiresApproval(... os.Getenv("CLAVAIN_AUTHZ_TOKEN"), os.Getenv("CLAVAIN_AGENT_ID"), db, pub, time.Now().Unix())`. After a successful token approval, the handler `os.Unsetenv("CLAVAIN_AUTHZ_TOKEN")` so spawned post-approval processes don't inherit it.

**Step 2: Token-path implementation (inside `RequiresApproval`)**
```go
if tokenStr != "" {
    tok, err := authz.ConsumeToken(db, pub, tokenStr, callerAgentID, "ic-publish-patch", pluginSlug(pluginRoot), now)
    if err == nil {
        return false, "token"  // approved via token; consume-audit row already written by ConsumeToken
    }
    // Auth-failure class (sig-verify, POP, cross-project, scope-mismatch, caller-mismatch): DO NOT fall through.
    // Returning "approval needed" here is the safe default; the caller can surface the specific class.
    if authz.ExitCode(err) == 4 {
        log.Printf("publish: token auth-failure — not falling back to legacy paths: %v", err)
        return true, "none"
    }
    // Token-state failure (consumed/expired/revoked) or not-found: fall through to v1.5 path.
    log.Printf("publish: token unusable (%v); trying authz-record + marker paths", err)
}
```
Mirrors the gate-wrapper hard-fail discipline: auth-failure blocks, token-state falls through.

**Step 3: Louder marker-file deprecation + adoption telemetry**
```go
if markerApproved(pluginRoot) {
    log.Printf(`DEPRECATION: .publish-approved marker used for %s.
  Migration target: clavain-cli policy token issue --op=ic-publish-patch --target=%s
  Marker removal is gated on 14-day rolling adoption telemetry; see docs/canon/authz-token-model.md §deprecation-gate.`, pluginRoot, pluginSlug(pluginRoot))
    return false, "marker"
}
```
Adoption telemetry is written as structured metadata on every `ic-publish-patch` authz row. The `vetting` JSON column gains a `via` key: `{"via": "token" | "authz-record" | "marker", "plugin": "<slug>"}`. Downstream query for adoption gate:
```sql
-- Last 14 days, by path:
SELECT json_extract(vetting, '$.via') AS via, count(*)
FROM authorizations
WHERE op_type='ic-publish-patch'
  AND created_at > strftime('%s','now','-14 days')
GROUP BY via;
```
Baseline collection: Task 6 captures the *current* state (expected: 100% marker) into `docs/canon/authz-token-model.md §deprecation-gate` as the starting point. Decision gate (captured normatively in Task 1 canon doc):
- *token + authz-record ≥ 90% of 14-day window AND marker ≤ 10%* → open a bead to remove the marker path in the next release.
- *marker 10-20%* → keep the deprecation warning another 14-day window; re-measure.
- *marker ≥ 20%* → investigate why adoption stalled; do not remove yet.

**Step 4: Tests** — extend table to include token cases:
```go
{name: "token-valid",                         token: validFreshToken,    record: nil,           marker: false, wantApproval: false, wantVia: "token"},
{name: "token-already-consumed",              token: consumedToken,      record: freshRecord,   marker: false, wantApproval: false, wantVia: "authz-record"},
{name: "token-expired-marker-present",        token: expiredToken,       record: nil,           marker: true,  wantApproval: false, wantVia: "marker"},
{name: "token-auth-failure-scope-mismatch",   token: otherPluginToken,   record: freshRecord,   marker: true,  wantApproval: true,  wantVia: "none"}, // CRITICAL: do NOT fall through on auth-failure
{name: "token-auth-failure-sig-invalid",      token: forgedToken,        record: nil,           marker: true,  wantApproval: true,  wantVia: "none"},
{name: "token-not-set-record-valid",          token: "",                 record: freshRecord,   marker: false, wantApproval: false, wantVia: "authz-record"},
{name: "no-token-no-record-no-marker",        token: "",                 record: nil,           marker: false, wantApproval: true,  wantVia: "none"},
{name: "via-telemetry-written",               token: validFreshToken,    record: nil,           marker: false, wantApproval: false, wantVia: "token", assertVettingVia: "token"},
```

**Step 5: Commit**
```bash
git add core/intercore/internal/publish/approval.go core/intercore/internal/publish/approval_test.go core/intercore/cmd/ic/publish.go
git commit -m "feat(publish): RequiresApproval takes explicit deps; token consume + adoption telemetry (sylveste-qdqr.28)"
```

<verify>
- run: `cd core/intercore && GOTOOLCHAIN=local go test ./internal/publish/ -v`
  expect: exit 0
</verify>

---

## Task 7: Bootstrap + docs

**Files:**
- Modify: `os/Clavain/scripts/authz-init.sh` (optional `--with-token-demo`)
- Modify: `os/Clavain/README.md` (v2 quickstart section)
- Modify: `os/Clavain/config/policy.yaml.example` (comment explaining tokens layer on top)

**Step 1: `authz-init.sh` extension**
```bash
# --with-token-demo: issue a sample bead-close token to validate end-to-end.
if [[ "${1:-}" == "--with-token-demo" ]]; then
    TOKEN=$(clavain-cli policy token issue \
        --op=bead-close \
        --target=demo-$(date +%s) \
        --for="${CLAVAIN_AGENT_ID:-demo-agent}" \
        --ttl=5m)
    echo "Demo token issued: $TOKEN"
    echo "Use with (one-shot, preferred):"
    echo "  CLAVAIN_AUTHZ_TOKEN=$TOKEN bead-close some-bead-id"
    echo "Verify (no consume):"
    echo "  clavain-cli policy token verify --token=$TOKEN"
    echo "(Do NOT 'export' the token — keep it scoped to one command.)"
fi
```

**Step 2: README v2 section** — one subsection under *Auto-proceed authorization*:
- **When to use a token**: delegation (Claude → codex), scoped one-shot grants (`ic publish --patch` for a bead), cross-session hand-off.
- **Issue**: `clavain-cli policy token issue --op=<op> --target=<t> --for=<agent> --ttl=60m`
- **Present (one-shot, preferred — no shell history leakage)**:
  ```bash
  CLAVAIN_AUTHZ_TOKEN=$(clavain-cli policy token issue --op=ic-publish-patch --target=my-plugin --for=claude --ttl=60m) \
    ic publish --patch
  ```
  The env var lives only for this one command. Do NOT `export` it.
- **Present (interactive, with eval-clear)**: if the token genuinely needs to persist across several commands, use:
  ```bash
  CLAVAIN_AUTHZ_TOKEN=<string>
  # ... do the work ...
  eval $(clavain-cli policy token consume --token="$CLAVAIN_AUTHZ_TOKEN" --expect-op=... --expect-target=...)
  ```
  Output is sentinel-wrapped: `# authz-unset-begin\nunset CLAVAIN_AUTHZ_TOKEN\n# authz-unset-end`. Verify the sentinels before eval-ing output from an untrusted binary.
- **Delegate**: `clavain-cli policy token delegate --from=<parent> --to=<child-agent> --ttl=<d>` — proof-of-possession required (`CLAVAIN_AGENT_ID` must equal parent's `agent_id`).
- **Revoke**: `clavain-cli policy token revoke --token=<id>` revokes one; `--cascade` revokes a root + all descendants (refused on non-root — see `docs/canon/authz-token-model.md` for rationale).
- **Audit**: `clavain-cli policy audit --tokens` — shows the delegation tree per root.
- Pointer to `docs/canon/authz-token-model.md` for full semantics.

**Step 3: `policy.yaml.example` addendum** — add a comment block near the top:
```yaml
# v2 note: tokens layer on top of policy. When CLAVAIN_AUTHZ_TOKEN is set
# and matches the op+target, the token consume short-circuits the policy
# check entirely. Policy still governs token-less ops. Issue tokens via
# `clavain-cli policy token issue`; see docs/canon/authz-token-model.md.
```

**Step 4: Commit**
```bash
git add os/Clavain/scripts/authz-init.sh os/Clavain/README.md os/Clavain/config/policy.yaml.example
git commit -m "docs(authz): README v2 quickstart + authz-init token demo (sylveste-qdqr.28)"
```

<verify>
- run: `bash os/Clavain/scripts/authz-init.sh --with-token-demo 2>&1 | grep -c 'Demo token issued'`
  expect: contains "1"
- run: `grep -c '^## .*[Tt]oken' os/Clavain/README.md`
  expect: contains "1"
</verify>

---

## Task 8: End-to-end integration test + full matrix

**Files:**
- Create: `os/Clavain/tests/authz-v2-e2e_test.sh`
- Modify: `os/Clavain/tests/authz-v15-e2e_test.sh` (sanity-assert v1.5 behavior unchanged when no token present)

**Step 1: E2E script covers (exit codes follow r2's 5-class mapping: 0/1/2/3/4):**
1. **Fresh sandbox bootstrap**: `ic init`, `policy init-key`, project policy installed, authz-init run.
2. **Root issue + consume**: issue a bead-close token for agent=claude → set `CLAVAIN_AGENT_ID=claude` + `CLAVAIN_AUTHZ_TOKEN=<tok>` → run `bead-close.sh` → assert `GATE_CONSUMED=1`, row's `consumed_at` populated, audit log has a row referencing `root_token`, **assert `CLAVAIN_AUTHZ_TOKEN` unset in process env after wrapper** (spawn child shell and check).
3. **Delegation chain**: issue root (agent=claude) → `CLAVAIN_AGENT_ID=claude` → delegate to codex → simulate codex session by setting `CLAVAIN_AGENT_ID=codex` + the child token → consume → assert `depth=1`, `parent_token` + `root_token` populated, audit tree renders both rows.
4. **Proof-of-possession rejection (delegate)**: issue root for agent=claude → attempt delegate from `CLAVAIN_AGENT_ID=eve` → assert exit 4 (auth-failure, class=pop-mismatch on stderr), no child row written.
5. **Caller-agent mismatch on consume (NEW)**: issue root for agent=claude → set `CLAVAIN_AGENT_ID=mallory` + the token → consume → assert exit 4 (auth-failure, class=caller-mismatch), no consumed_at set, no audit row written.
6. **Scope narrowing enforced (API-level)**: attempt `policy token delegate --from=<bead-close-token> --op=git-push-main` → assert the `--op` flag is rejected ("unknown flag"); API-level guarantee, not runtime check.
7. **Depth cap**: 3-deep chain → 4th delegate → assert exit 4 (auth-failure, class=depth-exceeded).
8. **Double-consume rejection**: consume once (exit 0) → consume again → exit 2 (token-state, class=already-consumed), audit log has exactly one consume event.
9. **Expired token rejection**: issue with `--ttl=1s` → sleep 2 → consume → exit 2 (token-state, class=expired).
10. **Revoke-cascade from root (CRITICAL r2/r3 fix)**: issue root (root_token IS NULL) → delegate depth-1 → delegate depth-2 → `revoke --cascade <root.id>` → consume each of the three (root, d1, d2) → assert all three exit **4** (class=revoked, r3 — was exit 2 in r2). Assert legacy fall-through did NOT happen for any of the three. If any succeed, the NULL-semantics bug from r1 has regressed; if any exit 2, the r3 revoked-classification regression has appeared.
11. **Cascade-on-non-root rejected (r3)**: issue root → d1 → d2 → d3 → attempt `revoke --cascade <d1.id>` → assert exit 4, class=cascade-on-non-root, no rows revoked (d1's revoked_at still NULL). Document that mid-chain cascade is a v2.x concern.
12. **Non-cascade revoke on mid-chain**: issue root → delegate child → `revoke <child.id>` (no --cascade) → consume child → exit 4 (class=revoked); consume root → exit 0 (root not revoked).
12a. **Non-cascade revoke on root**: issue root (no children) → `revoke <root.id>` → consume root → exit 4.
13. **Transactional consume (CRITICAL r2 fix)**: build intercore binary with `-tags testfault`, set `CONSUME_FAULT_INJECT_AFTER_UPDATE=1`, attempt consume → assert exit 1 (unexpected error) → assert `consumed_at IS NULL` in DB → assert no authorizations row for this consume → retry consume without fault → exit 0.
14. **`ic publish --patch` via token**: agent-authored commit sandbox → issue publish-scoped token → `ic publish --patch` → succeeds without `.publish-approved`, audit row has `vetting.via="token"`.
15. **Publish token wrong target rejection**: token for plugin A → attempt `ic publish --patch` in plugin B → exit 4 at `RequiresApproval` (scope-mismatch → no fall-through).
16. **Publish token wrong agent rejection (NEW)**: token for agent=claude with `CLAVAIN_AGENT_ID=codex` → `ic publish --patch` → exit 4 (caller-mismatch).
17. **Cross-project rejection**: issue token in project X's DB → attempt consume in project Y → exit 4 (auth-failure, class=cross-project).
18. **Adoption telemetry (NEW)**: after tests 14-17 run, query `SELECT json_extract(vetting, '$.via'), count(*) FROM authorizations WHERE op_type='ic-publish-patch' GROUP BY 1` → assert both `token` and `marker` counts are nonzero and distinct (proves the telemetry write path).
19. **Gate hard-fail on auth-failure (NEW)**: set a sig-forged `CLAVAIN_AUTHZ_TOKEN` → run `bead-close.sh` → assert wrapper exits 1, legacy `gate_check` did NOT run (grep stderr for absence of legacy indicator).
20. **v1.5 path unchanged when no token present**: unset `CLAVAIN_AUTHZ_TOKEN` → run bead-close → legacy `gate_check` fires → op succeeds. Same for `ic publish --patch` with `.publish-approved` marker alone → exits 0 with the loud deprecation warning on stderr.

**Step 2: Run full matrix locally + in CI**
```bash
cd core/intercore && GOTOOLCHAIN=local go test ./... -v -race
cd os/Clavain && GOTOOLCHAIN=local go test ./... -v -race
bash os/Clavain/scripts/gates/gates-smoke_test.sh
bash os/Clavain/tests/vetting-writes_test.sh
bash os/Clavain/tests/authz-e2e_test.sh          # v1
bash os/Clavain/tests/authz-v15-e2e_test.sh      # v1.5 (asserts no regression)
bash os/Clavain/tests/authz-v2-e2e_test.sh       # v2 (new)
```

**Step 3: Commit**
```bash
git add os/Clavain/tests/authz-v2-e2e_test.sh os/Clavain/tests/authz-v15-e2e_test.sh
git commit -m "test(authz): v2 e2e — 13 scenarios incl. delegate/cascade/double-consume/cross-project (sylveste-qdqr.28)"
```

<verify>
- run: `bash os/Clavain/tests/authz-v2-e2e_test.sh 2>&1 | tail -5`
  expect: contains "PASS"
- run: `bash os/Clavain/tests/authz-v15-e2e_test.sh 2>&1 | tail -5`
  expect: contains "PASS"
</verify>

---

## Deferred to v2.1 and beyond

- **v2.1 cross-project delegation.** Add `cross_project_id` + multi-project pubkey registry so a token issued in project X can be consumed in project Y against Y's signing key. Current v2 refuses this outright. Est. 2 days.
- **v2.x marker-file removal.** Once telemetry shows ≥95% of `ic publish --patch` approvals flowing via tokens, remove `.publish-approved` path entirely. Est. 2 hours.
- **v2.x DAG delegation.** Allow a token to have multiple parents (e.g., joint-authorization scenarios). Schema is DAG-ready (`root_token` denormalized); runtime is chain-only today. Est. 1 day if demand materializes.
- **v1.6 out-of-band signer daemon.** Carried forward from v1.5 — moves the signing key out of the gate-wrapper process. Tightens trust claim from "tamper-evident-post-write" to "tamper-proof-at-rest". Est. 1 day.
- **Multi-agent-per-project keys.** Today `.clavain/keys/authz-project.{key,pub}` is project-wide. A per-agent-type key would let delegation target a specific agent's pubkey for verify. Est. 1 day.

---

## Notes on discipline

- **Never reuse the v1.5 canonical payload function for tokens.** `CanonicalTokenPayload` is its own function with its own field list. Crossing them risks "tamper-looks-valid" under the wrong sig_version interpretation.
- **Never skip the proof-of-possession check in Delegate.** Brainstorm §P0.6 flagged this as ship-blocker. A caller whose `CLAVAIN_AGENT_ID` differs from the parent's `agent_id` must not be able to delegate.
- **Never trust `$CLAVAIN_AUTHZ_TOKEN` without a consume.** The opaque string is proof of possession AT consume time. Reading the env var is never itself authorization — only a successful `ConsumeToken` is.
- **Always enforce caller identity on consume (r2 new rule).** `ConsumeToken` takes `callerAgentID` and rejects mismatch with `ErrCallerAgentMismatch`. Bearer-by-string is explicitly not how this protocol works.
- **Never widen scope in delegate.** `op` and `target` must match parent. The `DelegateSpec` struct deliberately has no op/target override fields; adding them in a future version requires a parallel code path so a scope-widen is a conscious act, not a flag flip.
- **Never cascade-revoke without `--cascade`.** Single-token revoke is a different audit class from a cascade. The two are distinct operator intents — don't collapse them.
- **Never compare a nullable column to a possibly-NULL parameter (r2 new rule).** `WHERE root_token = ?` with `?=NULL` matches zero rows. The cascade-revoke predicate uses `WHERE id=? OR root_token=?` binding `target.id` to both positions. A future schema change that introduces another nullable-revoke dimension must revisit this.
- **Always wrap consume (UPDATE + audit INSERT) in one transaction (r2 new rule).** A partial-failure that consumes the token without writing the audit row is unrecoverable. Test `TestConsumeToken_PartialFailure_Atomic` enforces this via fault injection.
- **Never let auth-failure fall through to legacy paths (r2 new rule).** Token-state failures (consumed/expired/revoked) fall through because the operator's revoke-intent is still honored by the legacy policy check refusing. Auth failures (sig-verify, POP, scope-mismatch, cross-project, caller-mismatch) MUST hard-fail — a legacy success after a malformed token would silently ignore the operator's intent.
- **Don't read env vars or open DBs inside library code (r2 new rule).** `RequiresApproval`, `ConsumeToken`, `DelegateToken` all take their dependencies explicitly. `cmd/ic/publish.go` and `cmd/clavain-cli/authz_token.go` are the composition roots where env reads and `sql.Open` happen — exactly once each.
- **Unset `CLAVAIN_AUTHZ_TOKEN` after consume (r2 new rule).** Both the bash wrapper and Go `RequiresApproval` unset it. Child processes spawned before consume inherit (delegation vector); after consume they don't. README does not use `export CLAVAIN_AUTHZ_TOKEN=...`.
- **Don't read the signing key from `ConsumeToken`.** Consume only needs the pubkey (verify). `IssueToken` and `DelegateToken` are the only functions that load the private key. Mirror v1.5's minimal-read-path discipline.
- **Exit codes are a semantic class, not an error inventory (r2 new rule).** 0/1/2/3/4 cover success/unexpected/token-state/not-found/auth-failure. Wrappers discriminate on class; reason class is a stderr classifier line. Adding a new library error does NOT add a new exit code — it maps into an existing class.
- **Always record the consume as an `authorizations` row.** The token lives in `authz_tokens`; the *consume event* is a v1.5-shaped audit row. `policy audit` joins the two when rendering the tree.
- **Always record `vetting.via` (r2 new rule).** Each `ic-publish-patch` authorizations row has a `via` key in its vetting JSON: `"token" | "authz-record" | "marker"`. Without this, the marker-removal decision gate has no signal.
- **Linear-chain runtime is deliberate (r2 new rule).** Schema is DAG-ready; `DelegateToken`'s single-parent signature is not. v2.x DAG migration will require widening — Task 1's canon doc pins the exact touch points so the migration is discoverable.
- **modernc.org/sqlite quirks.** No CTE-wrapped `UPDATE ... RETURNING`. Use direct `UPDATE ... WHERE ...` + `RowsAffected()`. Single-row atomic semantics are preserved via the composite WHERE clause.
- **`GOTOOLCHAIN=local` is mandatory.** Prior session showed `go get golang.org/x/text@vN` silently bumping 1.22→1.25 and breaking the monorepo. Pin toolchain, add `github.com/oklog/ulid/v2` via explicit version, run `go mod tidy` with toolchain=local.
- **Session-end discipline.** After a session that issues or consumes tokens, `bd backup && bash .beads/push.sh` before exit so the delegation chain isn't lost on Dolt crash.
