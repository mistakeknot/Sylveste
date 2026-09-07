# fd-decisions — Auto-proceed authz framework

## Findings Index
- [P1] Sunk cost risk in Axis 1 (parallel `.publish-approved`) — lock-in on maintenance debt
- [P1] Q1 & Q5 conflate transient session ID with stable agent identity — identity instability flows through v1
- [P1] Q2 (requires precedence) underspecifies the "stricter-wins" semantics — risk of silent scope creep when projects add conditions
- [P2] Q3 (`.publish-approved` migration) is marked as "future" but creates a merge conflict if v1 reaches production scale
- [P2] Single-use tokens (v2) solve cross-session delegation but the problem statement doesn't confirm that's the hard requirement
- [P2] "No token lifecycle" (v1) may underestimate human cost of re-issuing tokens per bead if policy rules tighten

## Verdict
**SHIP-WITH-CHANGES**

The decision framework is sound: the 2.5 → 3 trajectory is justified (Option 3 does require Option 2 as fallback), and the v1 spec is implementable. However, three mid-scope reversals risk lock-in:

1. Axis 1's parallel `.publish-approved` (Q3) should commit to a unify migration window NOW, not defer to "when the system is running" — otherwise it becomes zombie infrastructure.
2. Agent identity (Q5) must be resolved before v1 ships, not left to v2 — session-ID-based audit records are unusable for cross-session delegation chains (the stated reason for v2).
3. Policy inheritance (Q2) needs a formal spec with examples for how projects add conditions while global rules remain binding.

These are not blocking (all ship-level code is sound), but deferring them guarantees rework in v1.5 when v2 tries to layer on tokens. Minor risk of false-positive auto-proceeds if vetting staleness (Q6) checks are not airtight.

## Summary
The brainstorm demonstrates clear understand of the exploration/exploitation tradeoff (minimal v1 to validate friction reduction, staged tokens for delegation) and appropriate stagewise commitment. The threat model is explicit and honest. Open questions are well-scoped but three contain implicit deferral of architectural decisions that should be made now: the `.publish-approved` deprecation path, agent identity stability, and policy inheritance semantics. The frame is "implement v1, then iterate," which is sound for an ADHD-context user managing friction; the risk is that ad-hoc answers to Q2, Q3, Q5 at implementation time create divergent interpretations across the monorepo.

---

## Open Questions Disposition

### Q1 — Token DAG vs hop chain — delegate_to field scope
**Verdict: Requires early clarification, but not blocking v1.**

The question asks: `delegate_to` single-agent or DAG? The answer affects token schema directly (v2, not v1).

Reasoning: Claude → codex → skaffen is mentioned as a motivating case. However, the brainstorm doesn't specify *how often* this happens or *whether* it's optional. If delegation chains are rare or optional (each agent can consume tokens directly), then single-hop with optional `parent_token` chain pointer is simpler and reversible. If they're mandatory or frequent, the schema needs to support arbitrary depth.

Evidence to resolve:
- How many fleet agents exist in the foreseeable future (12 months)?
- For each pair (agent A issuing, agent B consuming), can B re-delegate to C, or does re-delegation happen only at the user/Claude level?
- Does `parent_token` (already in the v2 schema) suffice to track chains, or do you need `delegate_to` as a forward pointer?

This is properly in v2 scope (tokens are v2), so no blocking issue for v1 ship. Recommend a brief spike on Demarch-side delegation patterns before v2 planning.

### Q2 — Policy inheritance precedence: requires merge semantics
**Verdict: P1 decision blocker for v1 ship (must be explicit before implementation).**

The question asks: how do `requires` conditions merge across global + per-project layers? Tighten-only (add), or replace? The brainstorm says "tighten-only with explicit `replace` keyword."

The risk: "tighten-only" is intuitive (global rule says "auto-proceed bead-close if tests_passed: true"; project says "also require vetted_within_minutes: 60") but the phrase "strict-wins rule" on line 210 for conflict resolution is asymmetric:
- If global rule A conflicts with project rule A (both op: bead-close, different modes), project wins (stricter).
- But if project *loosens* (force_auto: true), it overrides stricter global. This is not "stricter-wins," it's "explicit-override wins."

The spec needs a worked example. What happens if:
1. Global: `op: bead-close, mode: auto, requires: {tests_passed: true}`
2. Project: `op: bead-close, mode: confirm`

Does the project rule *replace* the global rule (bead-close always confirms), or *tighten* (bead-close confirms in addition to the global auto check)? The current language suggests replace. But replacing also means a careless project override could weaken safety.

**What evidence would resolve this:** Write a formal merge algorithm (pseudocode, not prose) that shows:
- How `requires` conditions combine (list of conditions? AND? OR?)
- How `mode` conflicts resolve (global/project/env precedence order)
- How `force_auto: true` interacts with a stricter global rule
- At least 5 worked examples (tighten, replace, conflict, force, env override)

**Why this matters for v1:** The gate wrapper (line 154) calls `policy check` once; if the merge semantics are unclear, two implementations could disagree on the same policy files, causing audit records to diverge across the fleet.

### Q3 — .publish-approved migration path and timing
**Verdict: P1 decision deferred but should be front-loaded (not blocking v1 ship, but blocking v1 production scale).**

The question asks: when unify happens in v1.5 or v2, how do existing `.publish-approved` markers migrate?

Current answer: "ic publish keeps accepting markers but logs them as synthetic authz. Deprecation window."

The risk: The brainstorm chooses Axis 1 (parallel) for v1 to avoid coordinating with `ic publish` ("not worth blocking v1 ergonomics"). This is reasonable for ship velocity. However, once v1 is deployed at scale (e.g., multiple plugins per sprint, 10+ agents running publish), the parallel system becomes zombie infrastructure. The "deprecation window" is undefined, and teams diverge: some plugins use markers, some use policy rules.

By v1.5, the cost of unifying is higher (retraining on new UX, migrations for existing records), and the motivation is weaker (the author has already adapted to parallel). This is classic sunk cost framing.

**What evidence would resolve this:**
- Before v1 ships, decide: is unify a v1.5 MUST or a v2 NICE-TO-HAVE?
- If v1.5 MUST, estimate the ic-publish PR size and coordination cost now, and commit to it in the roadmap.
- If v2 NICE-TO-HAVE, explicitly state the maintenance cost of running parallel systems until then (e.g., "audit log has two mechanisms; policy-lint must check both; onboarding docs must explain both").

This is not blocking v1 because the marker system is already shipped and proven. But if you reach v1.5 and discover the parallel system has calcified (plugins have `.publish-approved` in CI/CD scripts), the unify work explodes. Front-load the decision now.

### Q4 — Cross-project ops and multi-project bead closes
**Verdict: Well-scoped, implementable without v1 changes.**

The question asks: if a `bd close` touches 3 repos, which project's DB gets the authz record?

Proposed answer: "all three (one record per project, linked by a `cross_project_id`)."

This is sound. The per-project audit log design (Axis 2) anticipates this. A single `cross_project_id` foreign key is sufficient. Aggregation (`clavain-cli audit aggregate`) can join on that key.

No decision risk here. The schema supports it. Implementation can defer cross-project aggregation to v1.5 if the first v1 release is single-project-scoped.

### Q5 — Agent identity stability across sessions
**Verdict: P1 decision blocker for v1 schema (identity must be stable before you ship audit records).**

The question asks: session ID is ephemeral; for cross-session continuity (Claude session 1 issues token, Claude session 2 consumes), need stable agent identity. Proposed: derive from `~/.clavain/keys/agent-<type>.key` per fleet-agent-type.

The risk: This is deferred to v2 in the brainstorm ("Probably derived..."), but Q5 is actually a v1 *audit record* problem, not a v2 *token* problem.

Look at the v1 schema (line 79): `agent_id TEXT NOT NULL`. Today you're filling this with session ID. If you ship v1 with session IDs and then switch to stable agent identity in v2, you have two problems:
1. Existing audit records are keyed on ephemeral session IDs; they're no longer useful for answering "what did agent type X do?"
2. The migration is not transparent: queries that worked in v1 (SELECT * FROM authorizations WHERE agent_id = <session>) break when agents change identity format.

**What evidence would resolve this:**
- Before v1 ships, implement stable agent-type identity in clavain-cli and use it in v1 audit records from day one.
- Session ID should be a separate column (for correlation with Claude Code logs) but not the primary agent identity.
- This adds ~2 hours to v1 (new key generation + CLI refactor) but saves rework when v2 tries to layer tokens.

### Q6 — Vetting signal staleness: SHA check
**Verdict: P2 risk, implementable but requires care.**

The question asks: what if tests passed 60 minutes ago but code has been edited since? Need a SHA check.

Proposed spec in the open questions (line 208): `vetted_sha == HEAD` in requires block.

This is sound design, but the implementation has a footgun: the policy gate (line 154) runs at operation time; it reads `vetted_sha` from bead state, compares to HEAD, and proceeds or asks for confirmation. But between the policy check and the actual operation (e.g., `bd close`), the user could edit HEAD. The check is only good for that microsecond.

**What evidence would resolve this:**
- The gate wrapper should record the SHA that passed the check, then re-verify it immediately before the irreversible op.
- Or, the op-side machinery (bd, ic, git) should refuse to proceed if HEAD has changed since the policy check.
- A false-positive auto-proceed here is high-cost: you auto-close a bead whose code was edited after tests.

This is not P0 (you have a chance to catch it in v1 testing), but it's worth a test case: edit code *after* tests pass, immediately call `bd close`, verify it asks for confirmation.

### Q7 — Interactive fallback in non-TTY environments
**Verdict: Well-scoped, low risk.**

The question asks: if `policy check` returns "confirm needed" and we're in a non-interactive env (CI, background agent), what happens?

Proposed: "mode: block in non-tty by default, configurable."

This is sensible. The spec is clear. No decision risk here. Implementation-level detail: the gate wrapper (line 154) already handles this (`if [[ -t 0 ]]`), so the pattern is proven.

### Q8 — Global vs per-project conflict: stricter-wins, except force_auto
**Verdict: P1 decision underspecified (see Q2).**

The question asks: if global says "auto-proceed bead-close" and project says "always confirm bead-close," project wins. But what if project says "auto-proceed everything"?

Proposed: "stricter-wins is global, but projects can explicitly loosen via `force_auto: true` on a rule, which leaves a louder audit trail."

The risk: This is the same ambiguity as Q2. What does "stricter-wins is global" mean?

Example:
1. Global: `op: "*", mode: confirm` (default: confirm all ops)
2. Project: `op: bead-close, mode: auto` (loosen bead-close only)

Does the project rule *replace* the global catchall or *narrow* it? If replace, the project can selectively loosen. If narrow, the project's rule is a special case of the global rule. The language "stricter-wins" suggests the former (replace, with the twist that projects can only loosen via explicit force_auto).

But "stricter-wins is global" means: if the project tries to loosen a global rule without `force_auto: true`, the policy check fails or ignores the project rule. This is correct for safety but needs a worked example in the spec.

**Recommendation:** Same as Q2 — write a merge algorithm pseudocode before v1 implementation.

---

## Issues Found

### [P1] Agent identity stability is a v1 audit risk, not a v2 token problem — Q5 decision needs frontload
**Section:** Open questions, Q5; v1 schema (line 79)

The brainstorm defers agent identity to v2 ("Probably derived..."). However, the v1 audit schema uses `agent_id` as a primary key. If you ship v1 with session IDs and migrate to stable agent-type identity in v2, you've locked yourself into a schema migration at v2 time.

**What could go wrong:**
- Audit records from v1 are keyed on ephemeral session IDs; they're unqueryable by agent type once v2 ships.
- Dashboards and analysis tools built on v1 records (agent_id = session ID) will break when agent identity changes.
- Migration work explodes if you have 1000s of audit records to backfill.

**Fix:** Implement stable agent-type identity now (one key-generation ceremony per agent type, stored in `~/.clavain/keys/agent-<type>.key`), use it in v1 audit records from day one. Session ID stays in a separate column for correlation.

Cost: ~2 hours. Payoff: v2 tokens work seamlessly with existing audit records.

---

### [P1] Policy inheritance semantics (Q2) are unclear — risk of silent override in multi-project setups
**Section:** "Axis 2 — Scope," line 54–62; Open questions Q2

The brainstorm says "tighten-only with explicit `replace` keyword" for how project rules merge with global rules. But the language is ambiguous:
- Does a project rule *replace* the global rule for that op, or *add conditions* (AND)?
- If a project rule loosens the global rule, does `force_auto: true` make it stick, or does the gate still ask for confirmation?

The worked example in the brainstorm is missing.

**Why this matters:** Two implementations could disagree on the same policy files. One might interpret "project rules replace global rules" (simpler), another might interpret "project rules add conditions to global rules" (stricter by default).

**What could go wrong:**
- An agent runs policy check and auto-proceeds; the user runs the same check on the CLI and gets a different result.
- The audit trail shows conflicting decisions for the same op in different sessions.
- Onboarding new agents requires understanding the merge semantics; ambiguity breeds cargo-cult policy files.

**Fix:** Before v1 implementation, write a formal merge algorithm (pseudocode) with 5+ worked examples:
1. Global tightens, project does nothing → global wins.
2. Global auto, project loosens to confirm → `force_auto: true` required.
3. Global auto with `requires: {tests_passed: true, vetted_within_minutes: 60}`, project adds `requires: {vetted_sha: HEAD}` → does the project condition merge (AND) or replace?
4. Global auto, project tries to loosen without `force_auto` → audit trail shows what?
5. Env var override with both global and project rules → precedence order?

Cost: ~3 hours (decision + pseudocode). Payoff: single source of truth; no runtime surprises.

---

### [P1] Axis 1 (parallel .publish-approved) creates sunk-cost risk if v1 reaches production scale
**Section:** "Design axes," Axis 1 (line 44–51); Open questions Q3

The brainstorm chooses to keep `.publish-approved` working as-is in v1, adding the new policy/audit system in parallel for other ops. The reason: "unify requires coordinated changes to `ic publish`; not worth blocking v1 ergonomics on it."

This is correct for v1 ship velocity. But once v1 lands and becomes the way agents work (e.g., multiple plugins publish per sprint, 10+ agents running in parallel), the parallel system becomes zombie infrastructure.

**What could go wrong:**
- By v1.5, `.publish-approved` is embedded in plugin CI/CD scripts, documentation, and team workflows. Unifying has calcified into a much bigger lift.
- The audit log has two separate mechanisms for the same kind of decision (one filesystem-based, one DB-based). Policy-lint must understand both. Dashboards must aggregate from both.
- New agents learn the policy system first, then ask "why is ic publish different?" — training and maintenance burden.
- The "deprecation window" is undefined. By v2, you're either stuck with parallel forever or you've burned time on unification that should have been front-loaded.

This is a sunk-cost framing. The brainstorm is aware of it ("when the system is already running and the user trusts it"), which is good discipline. But "trust" is built in weeks/months, and calcification happens even faster.

**Fix:** Before v1 ships, decide: is Axis 1 unification a v1.5 MUST-SHIP or a v2 NICE-TO-HAVE?
- If MUST-SHIP: estimate the ic-publish PR (probably ~200 lines: read authz table instead of checking filesystem marker, log synthetic record for old markers). Add to v1.5 roadmap NOW.
- If NICE-TO-HAVE: document the maintenance cost explicitly in the RFC: "v1 and v1.5 run parallel `.publish-approved` and policy rules. Unification in v2 requires migration of 200+ existing markers."

Cost: 30 minutes (decision call + roadmap update). Payoff: no surprise rework in v1.5; clear path to unification.

---

### [P2] Question phrasing may anchor respondents toward "yes, ship v1" without exploring smaller MVP
**Section:** "Open questions," preamble (line 201)

The brainstorm scopes Q1–Q8 as refinements to the three-phase plan (v1 → v1.5 → v2). This is appropriate framing for an RFC. However, no question asks: "Is v1 (policy engine + audit log) the right MVP, or is there something smaller?"

For example: a simple allowlist in `~/.clavain/auto-proceed.allowlist` (one bead ID per line) gated on `CLAVAIN_BEAD_ID` env var would be a ~1-hour MVP. It would validate the basic friction reduction without DB schema, SQL migrations, or policy YAML. Ship that, gather signal on false-positives, then build v1 on solid ground.

**Why this matters:** The brainstorm is well-reasoned, but the decision is anchored to "full v1" without exploring whether a smaller commitment would learn faster. For an ADHD-context user with many parallel projects, the friction-reduction signal is urgent, but that doesn't mean v1's complexity is justified.

**What evidence would resolve this:** Run a 1-week spike with the allowlist MVP, measure false-positive rate (where auto-proceed would have been wrong), then decide: is that error rate acceptable, or do you need full policy rules?

This is P2 because the full v1 is justified (the threat model is real, and policy rules do reduce false-positives). But the decision would be *stronger* if it included the MVP comparison.

---

### [P2] Cross-session delegation (v2 motivation) may be overstated if single-session token issue is sufficient
**Section:** "Decision traversed" (line 24–40); v2 spec (line 172–199)

The brainstorm lists four reasons Option 3 earns its complexity:
1. Agent-to-agent delegation (real: Claude → codex already running)
2. Single-use consumption (real: prevents token reuse)
3. Unforgeable audit chain-of-custody (real: v1.5 signed records already provide this for policies)
4. Revocation-before-consumption (speculative: no use case mentioned)

Point 1 is solid. But points 3–4 are less clear:
- **Point 3:** v1.5 already has signed audit records. Do tokens need *additional* unforgeable signatures, or does the policy-check audit record (signed in v1.5) suffice?
- **Point 4:** "Authority held by a departed agent" — in a single-user monorepo (arouth1), when is revocation needed? If an agent goes rogue, it's revoked at the host level (kill the process). If the concern is a lingering token from an old session, TTL handles it. Revocation-before-consumption only matters if the token is in flight and you discover it's compromised mid-use.

**Why this matters:** v2 is 1 week of work. The decision is sound (layer tokens on top of policy), but the motivation could be stronger. The "real" driver is agent-to-agent delegation (Claude issues token to codex), and that's well-articulated. The other justifications smell like completeness rather than necessity.

**What evidence would resolve this:** In the v2 design phase, explicitly answer:
- Does a delegated token (Claude → codex → skaffen) need additional per-hop signatures, or is the audit chain (signed in v1.5) sufficient for forensics?
- What's the concrete revocation scenario? Is it common enough to warrant a schema table?
- Can you ship v2 with single-use + delegation chains but defer revocation to v2.5?

This is P2 because the decision is not *wrong*, just *over-motivated*. Ship v2 when you have a real delegation scenario (multiple agents coordinating on a complex task). Don't over-engineer the schema for threats that don't exist yet.

---

### [P2] False-positive auto-proceed on stale vetting (Q6) requires two-phase gate check to mitigate risk
**Section:** Open questions Q6 (line 208); gate wrapper pattern (line 154)

The brainstorm proposes `vetted_sha == HEAD` to catch code edits after tests pass. But the implementation (line 154) is a single check:

```bash
if clavain-cli policy check bead-close --target="$id" --bead="$id" ; then
    mode="auto"
```

Between the policy check (which validates SHA) and the operation (bd close), the user could edit code, and the gate doesn't re-verify.

**What could go wrong:**
1. Tests pass, vetting SHA is recorded.
2. Policy check runs, sees vetting_sha == HEAD, returns mode=auto.
3. User edits a file (refactor, comment, etc.).
4. Immediately calls `bd close` before thinking.
5. The gate auto-proceeds, closing a bead whose code is not actually tested.

The risk is low (user would see the diff when closing), but the audit record is now wrong.

**Fix:** Either:
- **Option A (safer):** Record the vetting SHA at policy-check time, then re-verify immediately before the operation.
- **Option B (lighter):** Tighten the staleness window (vetted_within_minutes: 5 instead of 60) and document that edits after testing require re-testing.

Cost: ~1 hour (test case + documentation). Payoff: audit records are always correct; no erroneous auto-proceeds.

---

## Improvements

1. **Write a formal policy-inheritance merge algorithm (pseudocode) before v1 implementation.** The language "tighten-only" and "stricter-wins" is ambiguous. Clarify with 5+ worked examples: what does the gate do for each combination of global/project/env rules?

2. **Commit to a v1.5 unification timeline for `.publish-approved` NOW, or document it as v2 NICE-TO-HAVE.** Deferring decisions about zombie infrastructure guarantees rework later. Either budget 200 lines for ic-publish refactor in v1.5, or accept the parallel-system maintenance cost.

3. **Implement stable agent-type identity before v1 ships, not in v2.** Session IDs are ephemeral; audit records keyed on them are useless for cross-session analysis. Derive stable identity from `~/.clavain/keys/agent-<type>.key`, store both session ID and agent-type ID in v1 audit records.

4. **Spike a simple allowlist MVP (1 hour).** Before committing to v1's full policy engine, validate the friction-reduction signal with a `~/.clavain/auto-proceed.allowlist` text file. Measure false-positive rate; if acceptable, you can defer v1 to v1.5 and unblock agents immediately.

5. **Add a test case for staleness detection (Q6).** Edit code after tests pass, immediately run `bd close`, verify it asks for confirmation. This catches the false-positive auto-proceed gap.

6. **Defer Q1 (DAG vs hop) and Q7 (interactive fallback) to v2 planning.** These are properly scoped as v2 decisions and don't block v1 ship. Include them in the v2 RFC, not the v1 implementation.

7. **Clarify v2 motivation around revocation and per-hop signatures (point 3–4 in the "Decision traversed" section).** The agent-to-agent delegation use case is solid. The other justifications should either be justified with concrete scenarios or deferred as v2.5.

<!-- flux-drive:complete -->
