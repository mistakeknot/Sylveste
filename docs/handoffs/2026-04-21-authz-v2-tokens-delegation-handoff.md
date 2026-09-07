---
artifact_type: handoff
bead: sylveste-qdqr
date: 2026-04-21
predecessor: docs/handoffs/2026-04-20-authz-v15-shipped.md
status: ready-for-plan
---

# Session handoff — authz v2 tokens + delegation (open the plan)

## Directive

> Your job is to draft `docs/plans/2026-04-21-auto-proceed-authz-v2.md` — the v2 token + delegation protocol — then execute it. Start from the v1.5 shipped state, re-read the v1.5 plan for continuity (`docs/plans/2026-04-19-auto-proceed-authz-v1.5.md`), re-read the brainstorm's v2 section (`docs/brainstorms/2026-04-19-auto-proceed-authz-design.md`), then write the v2 plan following the same shape as v1 / v1.5. Finish the plan, get it signed off, then execute task-by-task via `/clavain:executing-plans`.

## Why now

- v1.5 shipped Ed25519 signing end-to-end; `pkg/authz.SignRow` + `authz.Sign/Verify` + `authz.KeyPair` + canonical payload spec are all in place.
- Claude → codex delegation is already live in sprints (ships every session) but has NO authz representation — a delegated op currently runs under the parent agent's identity with no traceable chain of custody.
- Each additional session without v2 adds more rows to a table that cannot reason about delegation, so `policy audit` can't answer "who actually did this?" for any parallel-agent work.
- Context is warm: all of the signing primitives were in hand ~24 hours ago.

## What v2 needs (from the brainstorm)

Design doc: `docs/brainstorms/2026-04-19-auto-proceed-authz-design.md` → grep for "v2" / "token" / "delegation". Key shape:

- **`authz_tokens` table**: issued-by agent, issued-for agent, op scope, expiry, `root_token` (the session-level originating token), `depth` (delegation depth), consumed-at, revoked-at. Signed by the issuing agent's key per the v1.5 payload spec.
- **Token issue**: `clavain-cli policy token issue --for=<agent> --op=<op> --scope=<target> --ttl=<duration>` → emits the token (stdout or file), inserts the row, signs it.
- **Token consume**: atomic SQL — `UPDATE ... WHERE consumed_at IS NULL ... RETURNING` — ensures a token is used exactly once. If consume fails (already used, expired, revoked), op fails.
- **Proof of possession**: delegated agent presents the token at op time; gate wrapper verifies signature under the issuing agent's pubkey + calls consume + records the audit row with `root_token` and `depth` preserved.
- **Cascade revoke**: revoking a `root_token` invalidates every descendant. Tree walk is on read-time verify, not write-time propagation (schema stays append-only).
- **CLI surface**: `policy token issue / consume / revoke / list / show / verify`.

## What's in place from v1.5 to reuse

- `core/intercore/pkg/authz/sign.go` — `SignRow`, `CanonicalPayload`, `Sign`, `Verify`. The token rows use the same payload shape with two new fields (`root_token`, `depth`) → new `sig_version=2`.
- `core/intercore/pkg/authz/keys.go` — `KeyPair`, `GenerateKey`, `WriteKeyPair`, `LoadPrivKey`, `LoadPubKey`, `KeyFingerprint`, `RotateKey`.
- `core/intercore/internal/db/db.go` — migration framework with `currentVersion >= N && currentVersion < M` branches. Next migration is 034.
- `os/Clavain/cmd/clavain-cli/authz.go` + `authz_sign.go` — dispatch + subcommand patterns to mirror for `policy token ...`.
- `os/Clavain/scripts/gates/_common.sh` — `gate_check`, `gate_record`, `gate_sign` pattern. Token path likely needs `gate_token_consume` before `gate_record`.
- `os/Clavain/scripts/authz-init.sh` — bootstrap that v2 can extend with token-scope init if needed.

## Design decisions worth pinning up front

- **Token shape**: recommend a ULID + signature bundle so tokens are opaque strings passable via env var (`CLAVAIN_AUTHZ_TOKEN=<ulid>.<sig-hex>`) to child processes without requiring FS access.
- **Delegation chain representation**: DAG vs chain. Brainstorm has an open question on this; chain is simpler (one parent per token) and matches how sessions actually delegate today. DAG is general but adds complexity for consume semantics. Recommend **chain** unless evidence of multi-parent need surfaces.
- **Token-at-rest vs token-by-reference**: tokens live in the `authz_tokens` table; the opaque string carries only `id + signature`. Consume is a table UPDATE. Revoke is a separate column update, never deletion.
- **Scope semantics**: `op` is required, `target` is optional (wildcard = any target). Scope narrowing across delegations: a child token cannot widen scope beyond its parent's scope.
- **Freshness**: default TTL 60 min (matches publish approval window); overridable per-issue.
- **Identity resolution**: `CLAVAIN_AGENT_ID` is already the convention; v2 uses it unchanged. Agent pubkey lookup: same `.clavain/keys/authz-project.pub` today (single project-wide keypair) — multi-agent-per-project is a v2.1 concern.

## Open questions the plan has to answer

1. Do we want a separate `authz_tokens` table, or should tokens be rows in `authorizations` with `op_type='policy.token-issue'` and a new `token_payload` column? The separate-table path is cleaner; the authorizations-row path keeps audit query surface uniform.
2. How does consume interact with `policy sign`? Simplest: `policy token consume` signs the consume-event row as part of the consume transaction (atomic).
3. Should `gate_sign` auto-consume a token if one is present in the environment? Leaning yes — keeps the wrapper call site unchanged; the gate just looks up a token by env var and consumes it as part of record/sign.
4. Cross-project tokens — can a token issued under `.clavain/keys/foo` be consumed in `.clavain/keys/bar`? Default: no (same-project only). Cross-project delegation is v2.1+.
5. What's the `.publish-approved` interaction? v2 should fully deprecate it: `ic publish --patch` consumes a publish-scoped token instead of reading the marker file. Aligns with the v1.5 plan's "remove marker after telemetry."

## Suggested task decomposition (mirror v1.5's 8-task shape)

1. **Spec-lock** — `docs/canon/authz-token-model.md` (pin token shape, delegation semantics, consume atomicity, revoke cascade).
2. **Migration 034** — `authz_tokens` table (or column extension if that's the decision), indexes, cutover marker.
3. **`pkg/authz/token.go`** — `Token`, `IssueToken`, `ConsumeToken`, `RevokeToken`, `VerifyToken`, canonical payload v2.
4. **CLI `policy token {issue,consume,revoke,list,show,verify}`** — `os/Clavain/cmd/clavain-cli/authz_token.go`.
5. **Gate wrapper integration** — `gate_token_consume` helper; auto-consume when `$CLAVAIN_AUTHZ_TOKEN` is set.
6. **Publish path** — `ic publish --patch` consumes a publish-scoped token; marker-file path logs a stronger deprecation warning.
7. **Bootstrap + docs** — extend `authz-init.sh` if needed; add token section to README.
8. **E2E test** — `tests/authz-v2-e2e_test.sh`. Scenarios: issue → delegate → consume → audit; revoke-cascade; double-consume rejection; expired-token rejection; cross-session token round-trip.

## Caveats + gotchas picked up this round

- **GOTOOLCHAIN=local** is mandatory for any `go get` — a bare `go get golang.org/x/text@vN` auto-upgraded 1.22 → 1.25 and broke the monorepo. Always pin + local toolchain.
- **`modernc.org/sqlite` doesn't support CTE-wrapped `UPDATE ... RETURNING`** — direct `UPDATE ... RETURNING` with row counting is the substitute. Token consume will need this.
- **`SetMaxOpenConns(1)`** is the intercore convention — serialize consume transactions, don't fan out.
- **Migration inline vs SQL file** — files ≥021 are docs only; real upgrade DDL lives inline in `core/intercore/internal/db/db.go` at the end of the `if currentVersion >= N && currentVersion < M` chain. Don't be fooled by the `migrations/NNN_foo.sql` files.
- **Cutover marker ID convention** — fixed primary-key string, `op_type='migration.XXX-enabled'`. Migration 033 used `'migration-033-cutover-marker'`. Follow same shape for 034.
- **`authz.Record` defaults `sig_version=1`** — if tokens live in `authorizations`, insert must explicitly set `sig_version=2`. Better argument for a separate table.
- **Gate wrapper env vars for non-tty push**: `CLAVAIN_SPRINT_OR_WORK=1 CLAVAIN_AGENT_ID=<id>` required, else gate blocks. Test suites set these explicitly.

## Entry state

- `sylveste-qdqr` bead: CLOSED with "all steps complete" + v1.5 notes. Reopen before starting v2 work: `bd update sylveste-qdqr --status=open`. (Or: create a child bead `sylveste-qdqr-v2` under the same epic — cleaner tracking.)
- `~/.local/bin/{ic,clavain-cli}` at v1.5. Rebuild + reinstall after each v2 feature:
  ```bash
  export PATH=/usr/local/go/bin:$PATH GOTOOLCHAIN=local
  cd core/intercore && go build -o /tmp/ic-new ./cmd/ic && rm -f ~/.local/bin/ic && cp /tmp/ic-new ~/.local/bin/ic
  cd os/Clavain/cmd/clavain-cli && go build -o /tmp/clavain-cli-new ./ && rm -f ~/.local/bin/clavain-cli && cp /tmp/clavain-cli-new ~/.local/bin/clavain-cli
  ```
- Latest handoff symlink: `docs/handoffs/latest.md` → `2026-04-20-authz-v15-shipped.md`. Update to point here after v2 work begins.

## Minimum-viable first session

If the next session is short, the highest-leverage single-session deliverable is **Task 1 (spec-lock doc) + Task 2 (migration 034 with test)** — mirrors how v1.5 opened (canon docs + schema first). Both are reversible, both anchor the rest of the plan.
