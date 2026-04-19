# fd-systems — Auto-proceed authz framework

## Findings Index

- [P1] Vetting signal staleness—stale `vetted_at` when beads reopen
- [P1] Tight-coupling feedback loop: vetting signal → gate → audit log (unidirectional, no damping)
- [P2] Cross-project audit consistency model underdetermined
- [P2] Delegation chain TTL/revocation propagation unspecified
- [P2] Audit log unbounded growth vs retention strategy
- [P3] Policy inheritance tighten-only rule misses inheritance by composition
- [P3] Pace-layer friction: fast policy checks vs slow policy.yaml edits

---

## Verdict

**SHIP-WITH-CHANGES**

The framework is sound in its core loop (policy-driven pull-model with signed audit records) and correctly defers the higher-complexity token layer to v2. The brainstorm anticipates most major risks (cobra effect, stale signals, cross-project coordination). However, three feedback-loop and consistency issues must be addressed before v1 ships: (1) staleness detection in the vetting signal must include a SHA check and auto-invalidation on bead reopen, (2) the audit log must document its consistency model for cross-project ops (eventual vs two-phase), and (3) delegation chain semantics (TTL inheritance, revocation scope) must be specified before coding v2. Audit growth and policy inheritance are addressable in follow-up work without blocking v1 MVP.

---

## Summary

The framework applies effective constraints (policy as YAML, audit as unforgeable records, vetting signals from upstream flows) but rides on three tight coupling points where feedback could amplify: the vetting signal is both input and (implicitly) output of the gate decision, the audit log is the single source of truth for cross-project ops without a documented consistency model, and the delegation chain in v2 must handle TTL and revocation without creating revocation-orphans. The system is over-adapted to the current single-user, single-host constraint; when Sylveste scales to multi-host or multi-project factories, the audit consistency and delegation semantics will need careful review.

---

## Feedback Loops Identified

### Loop 1: Vetting-Signal-as-Gate-Input
**Inputs:** `/work` or `/sprint` writes `vetted_at=<ts>` (upstream vetting complete) → **Gate reads it** → **Gate emits authorization record** (downstream vetting cached) → **Signal feeds back into next bead reopen?**

**Structure:** Balancing loop (intended damping: `vetted_within_minutes: 60` age check). But the loop has no exit condition for bead modifications.

**Pace:** Fast (sub-second checks at op time) vs Medium (vetting happens once per bead per session, ~minutes).

**Runaway Risk:** If a bead is re-opened after vetting (user edits code post-vetting), the stale `vetted_at` still exists. The policy gate sees it and auto-proceeds the second time, even though tests haven't re-run. The 60-minute age check only bounds the time window, not the event-sequence: `vetting → op1 (auto) → code change → op2 (still auto, because vetted_at didn't reset)`.

**Damping Mechanism:** Insufficient. Need: `vetted_sha == current HEAD` in the `requires` block (mentioned in Q6 but not in v1 spec). Without it, the loop oscillates between false confidence (auto-proceed on unchanged code after stale vetting) and friction (user must re-vet every code change).

---

### Loop 2: Audit-Log-as-Trustworthiness-Signal
**Inputs:** Operator requests gate check → **Audit records the decision** → **User queries audit for "did I screw up?"** → **User tightens policy rules** → **Gate becomes stricter** → **Fewer auto-proceeds** → **Less audit data** → **User loses confidence in the policy**

**Structure:** Reinforcing loop with a twist: success feedback starves data.

**Pace:** Fast (gate decisions, sub-second) vs Slow (user reviews audit, adjusts policy, hours/sessions).

**Effectiveness Trap:** The brainstorm assumes the audit log alone provides feedback on correctness ("the user can inspect"). But there's no built-in telemetry: "How often did auto-proceed pick the right thing?" Once the user sees one false positive in the audit log, they have no way to know if it's 1 in 100 (safe) or 1 in 3 (broken). Without a confidence metric (e.g., `false_positive_rate_7d: 0.02`), the user's tightening of policy is based on salience, not calibration. A single high-visibility error triggers tightening that hurts throughput.

**Damping Mechanism:** None specified. Recommendation: add a `policy explain --audit-mode` that shows "over the last 7 days: N auto-proceeds, M false positives (user overrides), confidence score 0.98."

---

### Loop 3: Delegation-Token-Reissuance (v2)
**Inputs:** Claude issues token to codex (single-use) → **Codex consumes it** → **Audit records consumption** → **Claude sees token consumed** → **Claude reissues token for follow-up ops?**

**Structure:** Reinforcing loop (positive feedback: more tokens enable more agent autonomy).

**Pace:** Medium (token lifecycle is operation-scoped, minutes) vs Slow (agent permissions reviewed after session, hours).

**Runaway Risk:** If Claude has a policy rule "auto-issue new delegation tokens for ops on the same bead," it could create a cascade: token1 consumed → token2 issued → token2 consumed → token3 issued. Combined with a buggy codex that keeps retrying the same op, the token-issuance loop creates unbounded token growth in the audit log. The revocation point (revoke all tokens issued since time T) works, but only if Claude detects the loop and acts—no automatic circuit breaker.

**Damping Mechanism:** Per-bead token-reissuance limit (e.g., max 3 delegation tokens per bead per session). Not mentioned. Must be added in v2 spec.

---

## Issues Found

### [P1] Vetting signal staleness — code changed after vetting, bead reopened — section "Vetting signal" + Q6
**Problem:** The `vetted_at` signal is a scalar timestamp. It captures "vetting happened at T" but not "vetting covered the code at SHA X." If the user modifies code post-vetting (rare but possible in a buggy flow), the timestamp is still fresh, and the gate auto-proceeds a stale vetting.

**Symptom:** User runs `/work`, tests pass, bead state updated `vetted_at=1713607200`. User notices a typo in the code, edits and commits (HEAD changes). Later, `ic publish` reads policy, sees `vetted_at` is 2 minutes old (well within 60m), and auto-proceeds. The vetting covered the old code, not the new code.

**Systems lens:** Feedback loop #1 has no exit condition for "code changed." The gate reads a scalar timestamp, not a binding commitment to "this exact code passed tests."

**Fix:** Extend `requires` block to include optional SHA constraint:
```yaml
requires:
  vetted_within_minutes: 60
  vetted_sha: current_head  # Must match vetting evidence's commit SHA
  tests_passed: true
```
At gate time, retrieve the `vetted_sha` from bead state and compare to current `HEAD`. If mismatch, gate returns "confirm needed," and the user re-vets or manually approves.

**Alternate:** auto-invalidate `vetted_at` on any `git commit` in the bead's project. Simpler but disallows "vetting covers future commits in this PR," which some users may want.

---

### [P1] Vetting-gate-audit coupling is unidirectional with no damping — section "Axis 3" + "Vetting signal"
**Problem:** The vetting signal is both the primary INPUT to the policy gate AND implicitly the OUTPUT (recorded in audit as "why auto-proceed happened"). If the gate makes a decision based on a stale or incorrect signal, the audit records that decision as if it were sound. There's no feedback mechanism for the gate to adjust future decisions based on audit outcomes.

**Symptom:** Buggy `vetted_at` write (e.g., time-zone error, concurrent write corruption in Dolt) → gate sees incorrect timestamp → auto-proceeds → user discovers the bug later in audit. But the gate doesn't learn; it will make the same decision again the next time the timestamp is wrong.

**Systems lens:** Feedback loop #2 is reinforcing: False auto-proceeds increase over time if the signal generation is buggy, because there's no automatic circuit-breaker that says "if the last 3 auto-proceeds were wrong, switch to confirm mode."

**Fix—v1:** Document that `clavain-cli policy check` is stateless and makes no assumptions about signal quality. Responsibility for signal integrity is on `/work` and `/sprint` flows. Add explicit test case: "vetted_at timestamp corruption → audit shows mismatch between recorded time and current time."

**Fix—v2:** Add telemetry to the audit log: `signal_quality: { source_hash, source_version, generation_time }`. At policy explain time, warn if signal generation is older than gate evaluation time (indicates lag or corruption).

---

### [P1] Bead reopen doesn't invalidate vetting state — section "Vetting signal" + Q6
**Problem:** When a bead is reopened (e.g., user closes it, then realizes they need to make a follow-up change), the `vetted_at` persists. The gate will auto-proceed the next op based on "yes, we vetted this bead recently"—but the recent vetting was for the previous version of the code.

**Symptom:** User runs `/work` on bead-abc123. Tests pass. `vetted_at=T1` written. `bd close` auto-proceeds. User reopens bead (realizes a test case was missing). Edits code, tests pass, but `/work` doesn't write a new `vetted_at` (because the user manually edited, not running a full `/work` flow). Later `ic publish` reads the old `vetted_at=T1` and auto-proceeds. Vetting is 10 minutes old but covers different code.

**Systems lens:** The vetting signal is event-driven (flow writes it) but the invalidation is time-driven (60-minute age). When events and times decouple, the gate's reasoning breaks.

**Fix:** On `bd reopen`, scan the bead's vetting metadata. If `vetted_at` is present but the HEAD commit is newer than the commit that was vetting-aware when `vetted_at` was written, set a flag `vetted_stale: true` in the bead state. The gate sees it and requires re-vetting. Or: invalidate `vetted_at` completely on bead reopen, forcing fresh vetting.

---

### [P2] Cross-project ops: consistency model undocumented — section "Open questions Q4"
**Problem:** The brainstorm proposes "one record per project, linked by a `cross_project_id`" for ops touching multiple repos. But the consistency semantics are unclear: if project-A's DB write succeeds and project-B's DB write fails, is the op half-committed? Does the user retry only project-B, or the whole op?

**Symptom:** User runs `bd close` for a bead that touched 3 repos (code change in main, test fixture in test-harness, doc in docs-site). Three authorization records should be written (one per project DB). If the first two writes succeed and the third fails (project-C's Dolt server is down), the authorization audit is incomplete. User retries the op; do they get duplicate audit records? Does `clavain-cli audit` show them a fragmented or unified view?

**Systems lens:** Feedback loop: gate decision depends on "did vetting happen," which depends on audit log. If the audit log is fragmented or inconsistent across projects, the gate's reasoning is unsound.

**Fix:** Explicitly specify:
1. **Consistency model**: "Cross-project ops use eventual consistency. Each project DB writes independently. If one project fails, the caller must retry the full op; on retry, all projects write a new record (deduplication via op-id + timestamp range)."
2. **Query semantics**: `clavain-cli audit aggregate` walks all project DBs and merges results (union semantics). Query may return incomplete results if one project is offline; include a "projects queried" field in output.
3. **Rollback semantics**: If a cross-project op partially commits, how does the user unwind it? Document: "No automatic rollback. User must manually inspect each project DB and decide if a follow-up audit record is needed to document the partial state."

**Alternative (stronger):** Use a two-phase commit pattern (prepare → commit across all projects). More complex, but guarantees atomicity. Deferred to v1.5 or v2, depending on Sylveste's growth trajectory.

---

### [P2] Delegation chain semantics underdetermined — section "Open questions Q1" + v2 schema
**Problem:** The `parent_token` field allows chains (Claude → codex → skaffen). But the schema doesn't specify:
1. Does a token have a single parent or multiple parents (DAG)?
2. What happens to a child token's TTL when the parent token expires?
3. When a parent token is revoked, are all child tokens revoked too, or only consumed ones?

**Symptom:** Claude issues token1 (TTL 1h) to codex. Codex issues token2 (TTL 30m) to skaffen from token1. Skaffen stores token2 and doesn't use it for 20 minutes. Token1 expires (1h TTL). Claude revokes token1 and all descendants. But skaffen has token2 in memory and tries to use it 10 minutes later (still within token2's 30m TTL). Is token2 still valid? The revocation didn't invalidate it (it's not consumed), but the parent expired. The audit record will be confusing: "token2 consumed by skaffen, but token2's parent was revoked before consumption."

**Systems lens:** Delegation chains introduce a pace-layer mismatch: fast token consumption (ops happen in seconds) vs slow revocation propagation (must walk the delegation chain, which could be deep).

**Fix:** Specify:
```
Delegation Chain Semantics (v2):
1. Single-parent chains only (codex can delegate to skaffen, but skaffen cannot re-delegate).
   Reason: DAGs create revocation complexity. Start simple; add DAG support when needed.
2. Child token TTL must not exceed parent token TTL. At creation time, enforce: child_ttl <= parent_ttl.
3. Revocation is transitive: if parent is revoked, all unconsumed children are revoked.
   Audit record includes "revoked_by_parent: true" for orphaned child tokens.
4. Consumption is atomic: a token can only be consumed if its parent is not revoked and parent_ttl > now().
   Gate check includes parent revocation status.
```

---

### [P2] Audit log unbounded growth — implicit in "Cross-project ops" + "Delegation chains"
**Problem:** Each op writes one authorization record. Each delegation writes token records. In v2, with agent-to-agent workflows running autonomously, the audit log could grow very quickly (hundreds or thousands of ops per session across multiple agents). The schema has no retention policy or compaction strategy.

**Symptom:** After 3 months of autonomous agent flows, the project's `intercore.db` contains 50K authorization records and 100K token records. Queries become slow. The user wants to archive old records but has no tool to do it. The audit trail is also a liability: proof of every decision made, including potentially embarrassing false positives.

**Systems lens:** Reinforcing loop #2 (audit log growth): more agent autonomy → more ops → more audit records → slower queries → user tempted to delete old records → audit trail integrity at risk.

**Fix—v1:** Document audit log retention expectations: "Retention policy TBD. Expected growth rate for a single-agent flow: ~100 records/session. For multi-agent flows (v2): ~10x growth. Recommend: archive audit logs quarterly to `.beads/archive/`, keep hot logs for 6 months."

**Fix—v2:** Implement `clavain-cli audit archive --before=<date>` that exports records to gzipped JSON and prunes the DB. Verify signatures before archiving (v1.5 feature).

---

### [P3] Policy inheritance tighten-only rule misses inheritance by composition — section "Axis 2" + "Policy file shape"
**Problem:** The design specifies "per-project yaml overrides individual rule keys" and "projects can tighten but loosening should be explicit." This assumes projects inherit rules from global and selectively override. But the YAML merge semantics aren't specified for complex cases.

**Symptom:** Global policy says `- op: bead-close, mode: auto`. Project-A adds `- op: bead-close, mode: confirm, requires: { vetted_within_minutes: 30 }` (tightening). When `clavain-cli policy list` merges them, does it: (a) replace the global rule with the project rule, or (b) merge the requires blocks such that both the global version and project version apply?

If (a), the global `vetted_within_minutes: 60` is lost and only the project's `30` applies—but that might not be tightening in all cases (what if global had other requires conditions not in project rule?). If (b), composition could create unexpected behavior (two require blocks both must pass, but the exact precedence is unclear).

**Systems lens:** The "tighten-only" rule is a balancing mechanism to prevent accidental privilege escalation. But the merge semantics are underspecified, making it possible to accidentally loosen while intending to tighten.

**Fix:** Specify YAML merge semantics:
```yaml
# Global:
rules:
  - op: bead-close
    mode: auto
    requires:
      vetted_within_minutes: 60
      tests_passed: true

# Project override (tighten):
rules:
  - op: bead-close
    mode: auto
    requires:
      vetted_within_minutes: 30  # Tighter
      # tests_passed inherited from global? Or must be re-specified?

# After merge (SPECIFY THIS):
# Option A (inheritance): both vetted_within_minutes apply (30 is stricter, so use 30)
# Option B (replacement): only project rule applies; global rule is completely replaced
# Option C (union): both conditions must be satisfied
# Recommend: Option A with explicit note: "per-key override; omitted keys inherit from global"
```

Document with examples: "Tightening: specify a narrower value for an existing key, or add a new key. Loosening (discouraged): use `mode_override: force_auto` on a rule to explicitly loosen—creates audit flag `loosened_from_global`."

---

### [P3] Pace-layer friction: fast gate checks vs slow policy edits — implicit in v1 design
**Problem:** The gate runs `policy check` at op time (sub-second). If the user edits `policy.yaml` and the change is slow to distribute (git pull lag, env var cache in shell), the gate might operate on stale policy for several seconds or minutes.

**Symptom:** User realizes the policy is too strict, edits `.clavain/policy.yaml`, commits and pushes. User opens a new shell and runs `ic publish --patch`. The new shell's environment includes `CLAVAIN_POLICY_FILE` from the user's `.bashrc`, but if the environment variable isn't re-sourced or the git pull hasn't happened yet, the gate checks against the old policy and blocks the publish. User is confused: "I just changed the policy, why is it still blocking?"

**Systems lens:** Pace mismatch: policy updates (minutes, distributed via git) vs gate decision execution (seconds, local check). The system assumes gate always sees the latest policy, but doesn't enforce it.

**Fix—v1:** Document: "Policy changes take effect on the next `clavain-cli` invocation. If you edit policy.yaml, run `clavain-cli policy lint` to verify, then run a new shell to clear environment caches."

**Fix—v2:** Add a policy-version field to the schema. Each `policy.yaml` includes `version: <hash>`. The gate logs the policy version it used. If the user edits the policy, they can query the audit log to see "last 3 ops used old policy v123; new ops used v456." This provides visibility into the lag.

---

## Improvements

1. **Add SHA-based vetting validation:** Extend the vetting signal to include the commit SHA that was tested. Gate checks `vetted_sha == current HEAD` in addition to timestamp check. Prevents false auto-proceeds when code changes post-vetting.

2. **Implement audit telemetry dashboard:** Add `clavain-cli policy audit-summary --window=7d` that shows false-positive rate, override rate, and confidence scores. Allows user to calibrate policy rules based on data, not salience.

3. **Specify cross-project consistency model:** Document whether ops are atomic across projects (two-phase commit) or eventual (best-effort, with rollback responsibility on user). Choose based on Sylveste's deployment maturity (v1: eventual OK; v2+: consider two-phase if multi-host).

4. **Define delegation chain semantics before v2 implementation:** Lock in single-parent-chain-only, TTL inheritance rules, and transitive revocation semantics. Add test cases for revocation-after-consumption, revoked-parent scenarios.

5. **Plan audit log retention:** Document expected growth rates per agent type and session duration. Implement `clavain-cli audit archive` subcommand before audit logs become unwieldy.

6. **Clarify YAML merge semantics:** Document which keys are per-rule (replaced on override) vs global (inherited unless explicitly overridden). Provide examples: tightening, loosening with explicit flag, and common mistakes.

7. **Add policy version tracking:** Include policy hash in audit records and gate output. Enables user to detect policy drift and understand which policy version was active during each op.

---

<!-- flux-drive:complete -->
