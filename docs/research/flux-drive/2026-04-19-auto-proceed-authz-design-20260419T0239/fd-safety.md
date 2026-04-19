# fd-safety — Auto-proceed authz framework

**Source doc:** `docs/brainstorms/2026-04-19-auto-proceed-authz-design.md`
**Reviewer:** fd-safety (Flux-drive Safety Reviewer)
**Date:** 2026-04-19

---

## Findings Index

- [P0] v1.5 signing uses same file the gate writes to — no separation of duties (#issue-audit-db-cohabitation)
- [P0] `parent_token` delegation chain is claim-only, not cryptographically authenticated (#issue-parent-token-forgery)
- [P0] v1 → v1.5 retroactive signing is undetectable — unsigned records can be backdated into signed state (#issue-v1-v15-gap)
- [P1] `agent_id` is a session ID — ephemeral, unauthenticated, and trivially claimable by any caller (#issue-agent-id-weak)
- [P1] `.clavain/keys/authz-project.key` has no defined lifecycle, rotation path, or breach protocol (#issue-key-lifecycle)
- [P1] per-fleet-type key at `~/.clavain/keys/agent-<type>.key` collapses all agents of a type to one identity on a shared host (#issue-shared-host-identity-collapse)
- [P1] `mode: confirm` non-tty fallback config knob can be loosened by project policy — config surface is wider than the doc acknowledges (#issue-nontty-fallback-knob)
- [P2] `vetting` JSON blob is not part of the signed payload in v1.5 as currently described (#issue-vetting-not-signed)
- [P2] `clavain-cli policy set <op> <mode>` session-scoped override has no audit record and bypasses the policy engine it sits alongside (#issue-session-override-unaudited)
- [P2] `force_auto: true` project override leaves a "louder audit trail" but the doc does not define what that means concretely (#issue-force-auto-undefined)

---

## Verdict

SHIP-WITH-CHANGES

v1 (unsigned) is safe to ship as an internal friction-reduction tool for the single-user, single-host threat model it targets — it does not worsen the existing `.publish-approved` baseline. However, v1.5 must not ship without resolving the two P0 findings: audit-log cohabitation and the v1-to-v1.5 migration gap make the signing claim hollow before it is ever useful. The P0 delegation-chain finding applies only to v2 but is a full blocker for that phase.

---

## Summary

The design correctly identifies the threat model (fleet-internal trust, single host, single user) and scopes security claims accordingly. The v1 pull-policy engine is coherent and the gate-wrapper pattern is well-structured. The risk surface concentrates in two places: the audit log's lack of write-separation from the gate itself (making signatures useful against casual inspection but not against any agent that already has DB write access), and the v2 delegation chain's reliance on self-reported `parent_token` values that are never cryptographically validated. Both are addressable within the stated design philosophy without requiring architectural overhaul.

---

## Issues Found

### [P0] Audit log cohabitation — same DB, same writer, no separation of duties {#issue-audit-db-cohabitation}

**Risk:** Forgery risk is not eliminated by v1.5 signatures if the signing key and the audit DB reside in the same trust domain as the writing agent. An agent that can execute `clavain-cli policy record` also has write access to `.clavain/intercore.db`. A compromised or buggy agent can INSERT a forged authorization record at the moment it executes the op, then sign it with the project key it can also read. The v1.5 design says "A `clavain-cli policy audit --verify` subcommand walks records and validates signatures; any tampering is detected." Tampering by the record writer itself is not detected.

**Evidence:** "Add a project-scoped signing key in `.clavain/keys/authz-project.key` (or pulled from `intercore.db` config). Each `authorizations` INSERT writes a signature column covering the record fields." — v1.5 section. The gate wrapper pattern shows the same process calling `clavain-cli policy record` immediately after executing the op, with no out-of-band witness.

**Recommendation:** For v1.5 to carry the tamper-evidence claim, the signing key must be readable only by a process that is not the record writer, or the audit log must be append-only and written to a separate sink (e.g., a separate `.clavain/authz-audit.log` with mode 0222/write-only for the gate, 0400 for the auditor key holder). At minimum: document explicitly that v1.5 signs against the record writer, so audit-verify catches out-of-band edits but not self-forged records, and do not state it as "any tampering is detected."

---

### [P0] `parent_token` delegation chain is claim-only {#issue-parent-token-forgery}

**Risk:** In the v2 schema, `parent_token TEXT` is a foreign key reference that any agent can populate when calling `clavain-cli authz delegate`. Nothing in the design authenticates that the presenter of the delegation request actually holds or consumed the parent token. A child agent (e.g., codex or skaffen) can forge a `parent_token` value pointing to any existing token ID and claim the privileges associated with the parent's scope, including `op_type` and `target`.

**Evidence:** "Delegation chains let Claude issue a token to codex for a specific sub-op, codex consumes it, audit records the full chain." — v2 section. The `authz delegate` CLI is `clavain-cli authz delegate --from=<token> --to=<agent>`. There is no mention of the delegating agent proving possession of `<token>` before delegation is granted. The atomic consumption guard (`WHERE consumed_at IS NULL`) applies only to the child token, not to validating the parent link.

**Recommendation:** Before issuing a child token, the gate must verify: (a) the parent token exists and has not expired or been revoked; (b) the requesting agent is the `agent_id` on the parent token (not just a claimant); (c) the child token scope is a strict subset of the parent scope (op_type, target, bead_id must all match or narrow). The `issued_by` field on the child token is not sufficient because it is also self-reported. Proof-of-possession requires either presenting the parent token's signature as a challenge-response or verifying the request is signed with the parent agent's key.

---

### [P0] v1 → v1.5 retroactive signing gap {#issue-v1-v15-gap}

**Risk:** When v1.5 is deployed, existing v1 records have no `signature` column. The migration must add the column and leave old records with NULL signatures. The `audit --verify` command therefore must treat NULL-signature records as either "pre-signing era" (trusted by convention) or "unverified" (flagged). If they are trusted by convention, an attacker who can write to the DB during the migration window can INSERT records with NULL signatures that are indistinguishable from legitimate pre-signing records. If they are flagged, the audit log becomes noisy on day one and operators are trained to ignore flags, defeating the purpose.

**Evidence:** "v1.5 — signed audit records: Add a project-scoped signing key... Each `authorizations` INSERT writes a signature column covering the record fields." — v1.5 section. "v1 = parallel. Keep `.publish-approved` working as-is." — Axis 1. There is no migration plan for existing rows.

**Recommendation:** Define the migration explicitly before shipping v1.5: (a) all pre-v1.5 records get a `signature = "legacy-unsigned"` sentinel value, not NULL; (b) `audit --verify` rejects any record with NULL signature after the migration timestamp; (c) the migration timestamp itself is recorded in a separate, signed metadata row. This makes the trust boundary explicit rather than implicit.

---

### [P1] `agent_id` is a session ID — unauthenticated attribution {#issue-agent-id-weak}

**Risk:** The `agent_id` column is described as "session id" in the v1 schema comment. Session IDs in the Claude Code context are process-ephemeral identifiers set by environment or convention — they are not cryptographically bound to a key and are trivially claimable by any caller that knows the format. Any process on the host that can invoke `clavain-cli policy record` can supply any `agent_id` value, including one belonging to a previous legitimate session. This means the audit log's per-agent attribution is correct only when agents are honest, which is the weaker threat model the design is trying to move away from.

**Evidence:** Schema comment: `agent_id TEXT NOT NULL, -- session id`. Open Question 5 notes: "session ID is per-Claude-Code-session but ephemeral. For cross-session continuity... need a stable agent identity. Probably derived from `~/.clavain/keys/agent-<type>.key` per fleet-agent-type." This is acknowledged as open but it affects v1 attribution correctness now, not just v2 delegation.

**Recommendation:** For v1, document that `agent_id` is advisory/self-reported and the audit log is an accountability tool (honest agents report accurately) not an authentication tool (cannot catch a lying agent). For v1.5 when signing is added, the signature must cover `agent_id` and be validated against a known public key for that agent. Without this, a signed record proves the record was not edited after insertion but does not prove the `agent_id` is correct.

---

### [P1] Key lifecycle undefined for `.clavain/keys/authz-project.key` {#issue-key-lifecycle}

**Risk:** The signing key introduced in v1.5 has no documented: generation procedure, file permission requirement, rotation trigger, rotation procedure, or breach response. A key that lives forever at a fixed path without rotation becomes a higher-value target over time — every signed record from the entire project history is retroactively forgeable if the key is compromised. Additionally, the doc says "or pulled from `intercore.db` config" as an alternative key location, which would mean the signing key is inside the database it signs, a circular trust problem.

**Evidence:** "Add a project-scoped signing key in `.clavain/keys/authz-project.key` (or pulled from `intercore.db` config)." — v1.5 section. No key management section exists in the doc.

**Recommendation:** Before shipping v1.5: (a) drop the `intercore.db` config option for key storage — the key must not live in the artifact it signs; (b) specify file mode (0400, owned by the user running the gate); (c) define a key rotation procedure (new key signs going forward, old key verifies historical records up to rotation timestamp); (d) define breach response (rotation + re-verification pass to identify any records in the window between compromise and rotation that cannot be trusted). Even a one-paragraph subsection closes this gap sufficiently for a brainstorm-to-spec transition.

---

### [P1] Per-fleet-type key collapses agent identity on a shared host {#issue-shared-host-identity-collapse}

**Risk:** Open Question 5 proposes `~/.clavain/keys/agent-<type>.key` per fleet-agent-type (e.g., `agent-claude.key`, `agent-codex.key`). On a single host where both Claude Code and codex run, both processes have the same user identity (arouth1) and therefore both can read each other's keys from `~/.clavain/keys/`. Any local code execution in codex can load `agent-claude.key` and issue tokens or sign records as if it were Claude, and vice versa. The per-type distinction provides no isolation benefit on a shared-user single host.

**Evidence:** "Probably derived from `~/.clavain/keys/agent-<type>.key` per fleet-agent-type." — Open Question 5. "Single user (arouth1), single dev host today (zklw); Claude → codex agent delegation already live" — project context.

**Recommendation:** Accept this as a known limitation of the single-user/single-host model rather than designing around it with per-type keys that give false isolation confidence. The key schema should be per-invocation or per-session (with a short TTL) if isolation between agent types matters, or per-host (one key) with explicit documentation that all agents on the host share an identity boundary. The per-type key design creates the appearance of agent-level isolation without the substance, which is more dangerous than explicit single-identity documentation.

---

### [P1] Non-tty fallback config knob is under-specified {#issue-nontty-fallback-knob}

**Risk:** Open Question 7 answers: "`mode: block` in non-tty by default, configurable." The word "configurable" leaves the question of who can configure it and at what scope. If the per-project `.clavain/policy.yaml` can set `non_tty_mode: auto` (or if the catchall rule `mode: confirm` is simply absent), then a project policy can silently remove the non-tty safety floor. The `force_auto: true` knob described in Open Question 8 compounds this: a project that sets `force_auto: true` on the `"*"` catchall rule effectively disables human oversight for all unvetted ops in that project when running headlessly.

**Evidence:** "`mode: block` in non-tty by default, configurable." — Open Question 7. "projects can explicitly loosen via `force_auto: true` on a rule" — Open Question 8. The policy inheritance section says "project can tighten (add conditions) but the runtime semantics for loosening should be explicit via a `mode_override: force_auto` knob."

**Recommendation:** Define the invariant explicitly: `non_tty_mode` must not be configurable below `block` in per-project policy without a corresponding global policy acknowledgment. The global `~/.clavain/policy.yaml` should own the non-tty floor and per-project policy should not be able to loosen it. This maps to the stricter-wins rule the doc already endorses — apply it explicitly to the non-tty case. Document the `force_auto: true` as requiring presence of a `global_acknowledgment` field in the global policy file, so loosening requires touching both levels simultaneously.

---

### [P2] `vetting` JSON blob is not signed in v1.5 {#issue-vetting-not-signed}

**Risk:** The v1 schema includes a `vetting TEXT` column containing `{tests_passed, verified_with, sha, vetted_at}`. This is the primary evidence field that justifies auto-proceed decisions. If v1.5 signs the record but the signing covers only "record fields" without explicitly listing them, an implementation might sign a hash of a subset of columns and exclude `vetting`. A record with `tests_passed: true` in the vetting blob could be edited to `tests_passed: false` (or vice versa) after insertion if `vetting` is not in the signed payload. Even within an honest implementation, the doc should enumerate which fields are signed.

**Evidence:** "Each `authorizations` INSERT writes a signature column covering the record fields." — v1.5 section. The schema lists `vetting TEXT` as a separate column but the signing scope "record fields" is ambiguous.

**Recommendation:** In the v1.5 spec, explicitly enumerate the canonical field order included in the signed payload. The `vetting` column must be in that list. A hash-then-sign approach over the concatenated canonical form of all columns (including `vetting`) is the correct pattern. This prevents cherry-picked field signing.

---

### [P2] `clavain-cli policy set` session override is unaudited {#issue-session-override-unaudited}

**Risk:** The CLI surface includes `clavain-cli policy set <op> <mode>` described as a "session-scoped override." This command changes the effective policy for the session without going through the `authorizations` table. An agent or user invoking this command to switch an op from `confirm` to `auto` bypasses the audit trail entirely — neither the override itself nor the subsequent auto-proceed it enables will show any policy_match rationale tied to the session-level change.

**Evidence:** `clavain-cli policy set <op> <mode>  # session-scoped override` — CLI surface section.

**Recommendation:** Session-scoped overrides should write a synthetic authorization record with `mode: override`, `policy_match: session-override`, and the overriding agent's session ID. This gives the audit log visibility into when the policy was manually widened, even if the override is legitimate. Alternatively, remove the session-scoped override entirely and require policy changes via the YAML file, which is version-controlled.

---

### [P2] `force_auto: true` audit trail is undefined {#issue-force-auto-undefined}

**Risk:** Open Question 8 states that projects can loosen global policy via `force_auto: true` which "leaves a louder audit trail." No concrete definition of what "louder" means is provided. Without a specification, implementations will differ across callers and over time. "Louder" is not an invariant; it is a hope.

**Evidence:** "projects can explicitly loosen via `force_auto: true` on a rule, which leaves a louder audit trail" — Open Question 8.

**Recommendation:** Define "louder" concretely: e.g., every auto-proceed triggered under a `force_auto: true` rule must emit a WARNING-level log line, write an `authorizations` record with `mode: force_auto`, and be surfaced distinctly in `policy audit` output. The v1.5 signature on such records should be verified first in any audit output. This converts a vague commitment into a checkable invariant.

---

## Improvements

- The `vetting` field should include `vetted_sha` from the start (v1), not only as Open Question 6 implies it might be added later. Without a SHA check, a freshly-passing test suite with stale code can satisfy `vetted_within_minutes` trivially.
- `clavain-cli policy lint` should validate that the catchall `"*"` rule is always present and set to at least `confirm` — a policy file without a catchall defaults to allow in the current `loadPolicy()` implementation (line 74: "No policy file — default allow"), which is the wrong default for a security gate.
- The existing `loadPolicy()` in `policy.go` (line 74) already uses "default allow" when no policy file exists. The new authz system should make this explicit in the design: "if the authz policy file is missing, the gate must fail-closed (block), not open." The current code inverts this for the existing path-based policy and the new authz system should not inherit that inversion.
- The cross-project authz record problem (Open Question 4) should resolve to "record in all touched projects" from v1, not as a future concern. A bead-close that writes to only one project's DB but operates on three repos creates an audit gap that cannot be reconstructed post-hoc.
- The `delegate_to TEXT` field in v2 tokens is described as single-agent. The design should resolve Open Question 1 (DAG vs single-hop) before v2 implementation begins, not during it. A linear chain (`parent_token` walk) with a maximum depth of 3 is simpler to audit than an arbitrary DAG and sufficient for the Claude → codex → skaffen scenario named in the problem statement.
<!-- flux-drive:complete -->
