# fd-correctness — Auto-proceed authz framework

## Findings Index

- [P0] Token expiry not checked at consume time — authz_tokens table, v2 spec
- [P0] Token double-consume window not closed by spec — authz_tokens.consumed_at UPDATE, v2 spec
- [P0] Cross-project authz 2PC gap — no atomic writes across N intercore.db files
- [P1] `mode` column has no CHECK constraint — authorizations table DDL
- [P1] Gate wrapper TOCTOU: policy rule mutates between check and record
- [P1] `agent_id` has no well-formedness constraint — empty/whitespace accepted
- [P1] Vetting SHA staleness check bound to wrong HEAD — single-repo assumption
- [P1] `parent_token` has no FOREIGN KEY — child tokens survive parent revocation
- [P1] Missing index on `agent_id` — `policy audit --agent=<id>` causes full scan
- [P2] `vetting` JSON TEXT column — malformed JSON silently accepted; query patterns break
- [P2] Policy rule matching semantics not specified — first-match vs. all-match ambiguous
- [P2] `vetted_within_minutes` clock-skew risk — NTP drift / container clock divergence
- [P2] `mode_override: force_auto` is a silent weakening knob with insufficient audit trail
- [P2] Beads Dolt mid-recover read returns stale state — policy evaluates on bad vetting signal
- [P2] v1.5 signature covers undefined field set — schema evolution breaks all prior signatures
- [P2] No duplicate logical authorization guard — same (op_type, target, agent_id, bead_id) can repeat


## Verdict

SHIP-WITH-CHANGES

The v1 design (policy + audit log) is sound in intent and the underlying intercore.db infrastructure — WAL mode, `SetMaxOpenConns(1)`, transaction-scoped migration locking — already handles the single-writer serialization that makes the atomic consume pattern safe. However, two P0 issues must be resolved before v2 tokens ship: the token expiry check is absent from the consume path, and the cross-project write protocol has no recovery path after a partial failure, leaving the audit log in a state that claims more authority than was actually granted. The P1 TOCTOU on the gate wrapper matters for v1 as well and should be addressed before production use.


## Summary

The brainstorm correctly identifies the core risk (agents claiming vetted without vetting) and proposes a layered mitigation. The v1 pull-model design is implementable on existing infrastructure with minor schema hardening. The v2 token layer introduces two correctness holes that the spec text leaves as implicit assumptions rather than explicit invariants: the consume path must check expiry atomically with the consumed_at CAS, and cross-project writes need an explicit partial-failure recovery protocol, or the audit log will silently lie about whether all project records were written.


## Race Conditions Identified

- **Token double-consume (v2):** Two agents receive the same token ID and call `authz consume` within the same SQLite WAL checkpoint window. Each reads `consumed_at IS NULL`, both issue `UPDATE ... SET consumed_at = ? WHERE consumed_at IS NULL AND id = ?`. Under SQLite WAL with `SetMaxOpenConns(1)`, the single Go connection serializes writes — the second UPDATE sees 0 rows affected. This is safe IF the caller checks affected-row count and treats 0 as "already consumed, abort." The brainstorm says "consumption is atomic" but does not say the caller MUST check rows-affected. Any implementation that ignores the return count creates a silent authorization bypass.

- **Expired-then-consumed (v2):** Agent A holds a token that expires at T+60. At T+59, A calls `authz consume`. The implementation checks `consumed_at IS NULL` only; `expires_at` is not part of the WHERE clause. Between the read of `expires_at` (at T+59, valid) and the actual UPDATE (at T+61 after a slow network/process pause), the token is now expired but the UPDATE still succeeds because `expires_at` was not in the WHERE predicate. Result: a revoked-by-expiry token authorizes an op.

- **Vetting-signal stale read during Dolt recovery:** The beads-troubleshooting.md entry confirms Dolt server can be mid-recover when `bd state` is called. `policy check` calls `bd state $CLAVAIN_BEAD_ID vetted_at`; if Dolt is recovering, `bd state` may return the empty string or a cached-stale value. The policy gate reads "" as "not vetted" and correctly blocks — but only if the implementation treats an empty/error return as a gate failure. The brainstorm does not specify this behavior, leaving an implementation free to default-open on `bd state` error.

- **Cross-project partial write:** Sprint touches three repos. `policy record` writes to project-A's `intercore.db`, succeeds. Network hiccup; write to project-B's `intercore.db` fails. Write to project-C's `intercore.db` succeeds. `clavain-cli audit aggregate` now shows A and C with `mode=auto` and a `cross_project_id`, but B has no record. The audit appears to say "A and C authorized, B was not part of this op" — the inverse of the truth. No recovery procedure is specified.

- **Policy-file mutation between check and record (TOCTOU):** Agent calls `policy check bead-close`; rule `bead-close → auto` matches; agent proceeds; rule is tightened to `bead-close → confirm` (another session edits the yaml); agent calls `policy record --policy_match="bead-close"`. The recorded `policy_match` names a rule that no longer matches the current policy. Audit claims "rule bead-close authorized this op" but the rule has changed. v1.5 signatures sign the record fields but not the policy content at check time, so the signature does not detect this.


## Issues Found

### [P0] Token expiry not checked atomically at consume time — authz_tokens, v2

**Bug type:** atomicity
**Reproduction sketch:** Token issued with `expires_at = now + 60s`. Agent sleeps 61 seconds (or is paused by scheduler). Calls `authz consume`. Implementation executes `UPDATE authz_tokens SET consumed_at = ? WHERE consumed_at IS NULL AND id = ?` — no `AND expires_at > unixepoch()` predicate. UPDATE succeeds (1 row affected). Gate proceeds. Token was expired.
**Recommendation:** The WHERE clause in the consume UPDATE must be `WHERE consumed_at IS NULL AND expires_at > unixepoch() AND id = ?`. Check rows-affected == 1; if 0, disambiguate: query for `consumed_at IS NOT NULL` (already consumed) vs. `expires_at <= unixepoch()` (expired) and return distinct error codes. The brainstorm spec must state this as a normative requirement, not leave it to implementors.

### [P0] Token double-consume: rows-affected check not specified — authz_tokens, v2

**Bug type:** race
**Reproduction sketch:** Claude and codex both receive token `T` for `bead-close bead-X`. Both call `authz consume T` within the same second. SQLite WAL serializes the two UPDATEs. Second UPDATE affects 0 rows. If the caller treats 0 rows-affected as success (e.g., shell `if [[ $? -eq 0 ]]` checking command exit code rather than rows affected), both agents proceed with "auto." The op fires twice.
**Reproduction context:** Shell scripts cannot introspect SQL rows-affected directly; they rely on `clavain-cli authz consume` exit codes. The CLI must return exit 1 (not 0) when rows-affected == 0, and the spec must state this.
**Recommendation:** Specify that `clavain-cli authz consume` exits 0 only when exactly 1 row was modified. Exit 2 for "already consumed," exit 3 for "expired." All gate wrappers must treat any non-0 exit as authorization denied.

### [P0] Cross-project authz: no 2PC, no partial-failure recovery — Open question 4

**Bug type:** atomicity
**Reproduction sketch:** Op touches projects A, B, C. `policy record` writes A (success), B (SQLITE_BUSY timeout after 5s, returns error), C (success). Caller logs the B error to stderr and exits 0 (fail-open pattern used everywhere else in auto-push.sh). Audit aggregate reports A and C as authorized; B has no record. Human reviews audit and concludes "B was not covered" — wrong inference.
**Spec gap:** The brainstorm says "one record per project, linked by cross_project_id" but specifies no protocol for what happens when writes are partial.
**Recommendation:** Define an explicit partial-failure protocol. Options: (a) write to all N DBs in a best-effort loop, then write a `cross_project_summary` record to the primary project DB listing which secondaries succeeded and which failed — audit aggregate uses this as ground truth; (b) require all N writes to succeed before the op proceeds (strict mode, suitable for `bd-push-dolt` and `ic-publish-patch`); (c) treat partial write as "audit gap, not authorization gap" — document this in the audit schema and surface it in `policy audit --verify`. Pick one and make it normative.

### [P1] `mode` column lacks CHECK constraint — authorizations DDL

**Bug type:** constraint
**Reproduction sketch:** A shell script calls `clavain-cli policy record --mode=aut` (typo). The INSERT succeeds; `mode = 'aut'` is stored. `policy audit` shows a record with an unrecognized mode. Logic that branches on `mode = 'auto'` silently skips it.
**Recommendation:** Add `CHECK(mode IN ('auto', 'confirmed', 'blocked'))` to the `authorizations` DDL. The existing schema in `intercore.db` already uses CHECK constraints on `coordination_locks.type` — follow the same pattern.

### [P1] Gate wrapper TOCTOU: policy mutates between check and record

**Bug type:** TOCTOU
**Reproduction sketch:** (1) Agent calls `policy check bead-close` → exit 0, `policy_match=bead-close`. (2) Human edits `.clavain/policy.yaml`, changes `bead-close` rule to `mode: confirm`. (3) Agent calls `bd close`. (4) Agent calls `policy record --op=bead-close --mode=auto --policy_match="bead-close"`. Record claims rule "bead-close" authorized auto-proceed; the rule now says confirm-only. Audit is factually wrong. v1.5 signatures do not protect against this because they sign the record fields, not the policy snapshot.
**Recommendation:** At `policy check` time, compute a content hash of the merged effective policy (global + per-project yaml). Pass this hash as `--policy_hash=<sha256>` to `policy record`. Add a `policy_hash TEXT` column to `authorizations`. `policy audit --verify` can then re-evaluate the recorded rule name against the policy snapshot at the recorded hash. Without the snapshot, downgrade to flagging the mismatch and leaving a warning in the audit output.

### [P1] `agent_id` has no well-formedness constraint — authorizations DDL

**Bug type:** constraint
**Spec gap:** The column is `agent_id TEXT NOT NULL`. An empty string, a whitespace-only string, or an arbitrary 10,000-character string are all accepted.
**Reproduction sketch:** Gate wrapper shell script has `AGENT_ID="${CLAUDE_SESSION_ID:-}"` and the env var is unset; INSERT stores `agent_id = ''`. All audit queries filtering `WHERE agent_id = ?` with a real session ID miss this record; queries without a filter include it silently.
**Recommendation:** Add `CHECK(length(trim(agent_id)) > 0)` to the DDL. Separately, the CLI should validate the `--agent` flag against a pattern (UUID, ULID, or `^[a-zA-Z0-9_-]{8,128}$`) before inserting, and exit non-zero if the value is empty or malformed.

### [P1] Vetting SHA check assumes single-repo bead — Open question 6

**Bug type:** TOCTOU / spec gap
**Context:** The brainstorm's proposed fix for stale vetting is `vetted_sha == HEAD`. For a bead spanning 3 repos (the cross-project case from Q4), there is one HEAD per repo. `vetted_sha` as a single value cannot cover all of them.
**Reproduction sketch:** Bead closes across repos A, B, C. Vetting records SHA of repo A's HEAD. Between vetting and op, repo B gets a `git pull --rebase` that advances its HEAD by 3 commits. `vetted_sha == HEAD` passes for A, but B has changed. The agent proceeds with stale code in B.
**Recommendation:** For multi-repo ops, `vetting` JSON (already a TEXT blob) should store `{"shas": {"repo_A": "abc123", "repo_B": "def456", "repo_C": "ghi789"}}`. The policy engine checks each repo's current HEAD against its recorded SHA. Single-repo is the common case and degrades cleanly to a single-element map.

### [P1] `parent_token` has no FOREIGN KEY — child tokens survive parent revocation

**Bug type:** constraint
**Reproduction sketch:** Claude issues token P to codex. codex delegates to skaffen: `authz_tokens` row with `parent_token = P` is inserted. Claude revokes P via `authz revoke`. The revocation only marks P; there is no cascade because `parent_token` is a plain TEXT column, not `REFERENCES authz_tokens(id) ON DELETE CASCADE`. skaffen still holds a valid (unconsumed) child token and uses it after P is revoked.
**Recommendation:** Add `FOREIGN KEY (parent_token) REFERENCES authz_tokens(id)` to the DDL (foreign keys are enabled in every `db.Open` call via `PRAGMA foreign_keys = ON`). Revocation logic must walk the full delegation chain: revoke P → find all `WHERE parent_token = P` → mark them revoked → recurse. This is a tree walk, not a cascade DELETE, because revocation should leave audit trails intact.

### [P1] Missing index on `(agent_id, created_at)` — authorizations

**Bug type:** other (query performance with correctness implication)
**Context:** `clavain-cli policy audit --agent=<id>` is a first-class CLI verb. With only `authz_by_bead(bead_id, created_at)` and `authz_by_op(op_type, created_at)`, a `--agent` query requires a full table scan. At scale (Claude + codex + skaffen across 20+ beads/day), this is O(N) on the full audit log.
**Correctness implication:** Not a data-loss bug, but an audit command that is too slow to use in the critical path (e.g., during incident response) is effectively absent.
**Recommendation:** Add `CREATE INDEX authz_by_agent ON authorizations(agent_id, created_at DESC)`. The existing intercore schema has per-query indexes for every major filter axis; this one is missing from the brainstorm DDL.

### [P2] `vetting` TEXT column accepts invalid JSON without detection

**Bug type:** constraint
**Reproduction sketch:** Shell script writes `vetting='{"tests_passed":true, "sha":"'$(git rev-parse HEAD)'"'` (missing closing brace). INSERT succeeds. `policy check` attempts `json_extract(vetting, '$.tests_passed')` in SQLite — returns NULL. NULL evaluates as falsy for `tests_passed: true` requires-check. Policy gate blocks the op even though tests passed. No error is surfaced.
**Recommendation:** Either (a) add a `CHECK(json_valid(vetting) OR vetting IS NULL)` constraint to the DDL; or (b) validate JSON in the CLI before INSERT and exit non-zero on malformed input. SQLite 3.38+ supports `json_valid()` as a CHECK expression. The modernc.org/sqlite driver version in use should be verified for this support.

### [P2] Policy rule matching semantics unspecified — first-match vs. all-match

**Bug type:** spec gap
**Context:** The brainstorm shows a rules list with a `op: "*"` catchall at the bottom. This implies first-match semantics (like iptables). But the text does not say so. If two rules match `bead-close` (a specific one and a wildcard), first-match returns the specific rule; all-match would aggregate requires conditions. These produce different authorization decisions.
**Reproduction sketch:** Global policy has `op: bead-close, mode: auto, requires: {tests_passed: true}`. Per-project policy has `op: bead-close, mode: auto, requires: {vetted_within_minutes: 60}`. Under first-match, which rule fires depends on merge order. Under all-match with tighten-only, both conditions apply.
**Recommendation:** The spec must state: "first rule wins; the catchall `op: '*'` must be last." Or: "all matching rules are evaluated; the most restrictive requires-block wins." Either is correct but must be normative. The implementation should have a test that exercises both a specific rule and a wildcard simultaneously and asserts the expected winner.

### [P2] `vetted_within_minutes` subject to clock skew — requires block

**Bug type:** clock-skew
**Context:** `vetted_at` is a Unix timestamp written by one agent; `policy check` is called by a different agent (or a different process on the same host). If the agent that wrote `vetted_at` ran in a container or via a remote dispatch with clock drift, the age calculation `now - vetted_at` may be wrong by minutes.
**Reproduction sketch:** codex agent (container, clock 3min ahead) writes `vetted_at = 1000`. Main Claude session (host clock) calls `policy check` 58 minutes later at host time `1000 + 58*60 = 4480`. It computes age = `4480 - 1000 = 3480s = 58min` — within 60min, passes. But the actual elapsed time was 61 real minutes. Or vice versa: clock behind causes a valid vetting to appear stale.
**Recommendation:** Accept ±5-minute clock skew in the comparison. Document the tolerance in the schema comment. Alternatively, use monotonic wall-clock from the policy-check host only (do not trust timestamps from remote agents without a verified source), but this requires `vetted_at` to be re-written at check time, which defeats its purpose.

### [P2] `force_auto` knob weakens global safety without loud audit trail

**Bug type:** spec gap
**Context:** The brainstorm says projects can loosen global policy via `force_auto: true` on a rule, which "leaves a louder audit trail." But the spec does not define what "louder" means, and the audit trail for a `force_auto` record in `authorizations` looks identical to a normal `mode=auto` record unless `policy_match` includes the override reason.
**Recommendation:** When `force_auto: true` is active, the `mode` field in `authorizations` should be `"force_auto"` (not `"auto"`), and the CHECK constraint should permit this value. `policy audit` output should distinguish it visually and flag it in `--verify`. The v1.5 signature should also cover the `mode` field value so tampering with `force_auto → auto` is detectable.

### [P2] Beads Dolt recovery default not specified for policy gate reads

**Bug type:** other (reliability with correctness implication)
**Context:** `policy check` reads `bd state $CLAVAIN_BEAD_ID vetted_at`. If the Dolt server is mid-recover (per beads-troubleshooting.md: crash-recovery can take 10–30 seconds), `bd state` exits non-zero or returns empty. The brainstorm does not specify the policy gate's default in this case.
**Reproduction sketch:** Sprint is at Step 6. Dolt crashes (known failure mode). Agent calls `policy check bead-close`. `bd state vetted_at` returns "". Policy engine evaluates `vetted_within_minutes: 60` against an empty timestamp: (a) if it treats "" as "never vetted" → blocks correctly; (b) if it treats "" as "read error, default open" → auto-proceeds without vetting signal.
**Recommendation:** The spec must state: "if `bd state` returns an error or empty string for any required condition field, `policy check` exits 3 (policy error), not 0 (auto)." Gate wrappers must treat exit 3 as "require confirmation" in interactive mode or "block" in non-interactive mode. This is the conservative safe default.

### [P2] v1.5 signature covers undefined field set — migration breaks all prior signatures

**Bug type:** other (audit integrity)
**Context:** "Each `authorizations` INSERT writes a signature column covering the record fields." The spec does not enumerate which fields are covered or in which serialization order. When v2 adds columns to `authorizations` (e.g., `policy_hash`, `cross_project_id`), the signature computed over the v1.5 field set will not match a v2 verification that includes the new fields.
**Reproduction sketch:** v1.5 record: signature covers `(id, op_type, target, agent_id, bead_id, mode, policy_match, vetting, created_at)`. v2 migration adds `policy_hash`. Verification tool hashes all columns including `policy_hash = NULL` for old records → signature mismatch → every pre-v2 record fails `--verify`, flooding the audit with false positives.
**Recommendation:** The signature spec must enumerate the exact fields and serialization format (e.g., canonical JSON, sorted keys, UTF-8). New columns must either be explicitly excluded from the signature or require a signature version field. Use `sig_version INTEGER NOT NULL DEFAULT 1` so the verifier knows which field set to hash.

### [P2] No uniqueness guard on logical (op_type, target, agent_id, bead_id) tuple

**Bug type:** constraint
**Reproduction sketch:** Gate wrapper is invoked twice for the same op (e.g., retry after transient error). Two `authorizations` rows are inserted with different ULIDs but identical `(op_type='bead-close', target='sylveste-abc', agent_id='sess-123', bead_id='sylveste-abc', mode='auto')`. Audit shows 2 auto-authorizations for the same bead-close. This is not wrong per se, but it inflates the audit record and makes idempotent retries look like duplicate ops.
**Recommendation:** Either (a) add a UNIQUE constraint on `(op_type, target, agent_id, bead_id)` with `ON CONFLICT IGNORE`; or (b) add an `idempotency_key TEXT` column (populated by the gate wrapper from a hash of the op context) with a UNIQUE constraint. Pattern (b) already exists in `intent_events(idempotency_key)` in the current schema — reuse the precedent.


## Improvements

- The `authorizations` DDL should mirror `coordination_locks`: add a `CHECK` on every enum column (`mode`, `op_type` if enumerable). The existing intercore schema consistently enforces this — be consistent.
- Add a `cross_project_id TEXT` column to the v1 DDL now, even if cross-project support ships in v2. Backfilling a column later triggers a migration that all 10+ existing intercore.db files must run; adding it as a nullable column up front is free.
- The gate wrapper pattern in the brainstorm calls `bd close "$id" --reason="$reason"` between `policy check` and `policy record`. If `bd close` fails (Dolt not available), `policy record` is never called. The record should be written before the op executes (as intent) and updated after (as result), not only on success — otherwise partial failures leave no audit trace. The `intent_events` table already models this "write-intent, then write-result" pattern.
- `clavain-cli policy set <op> <mode>` (session-scoped override) should write to the `authorizations` table with `mode='force_auto'` and a `policy_match='session_override'` so the override is auditable, not just ephemeral env state.
- The `authz_tokens.delegate_to` column as a single `TEXT` value cannot represent a DAG delegation (Claude → codex → skaffen). Open question 1 notes this. The fix is a separate `authz_token_delegates` join table: `(parent_token_id, child_token_id)`, which also enables walking the full chain for revocation.
- Consider adding `PRAGMA synchronous = NORMAL` to the `db.Open` call for `authorizations` writes. The current intercore setup uses WAL (which already reduces sync overhead), but `synchronous = FULL` (the SQLite default) means each `policy record` INSERT requires an fsync. For a gate that runs on every `bd close`, this adds latency on spinning-disk servers. NORMAL + WAL is safe: only a power failure between the WAL write and the checkpoint risks data loss, and even then only the last record is lost, not the DB.

<!-- flux-drive:complete -->
