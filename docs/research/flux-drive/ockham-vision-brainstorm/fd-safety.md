# Safety Review — Ockham Vision Brainstorm (Rev 3)

**Document:** `docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md`
**Bead:** sylveste-8em
**Reviewer:** fd-safety (Flux-Drive Safety Reviewer)
**Date:** 2026-04-02
**Prior review:** rev 2 (3 prior findings: S-01, S-02, S-03)

---

## Threat Model

**Deployment context:** Headless CLI tool (`ockham`) running as the local developer's user account. Writes to `~/.config/ockham/` (intent.yaml, signals.db) and `~/.clavain/factory-paused.json`. Reads from `bd` (beads state), interspect (evidence DB), interstat (cycle metrics), and CASS (session data). No network exposure in Waves 1-3. The CLI is invoked by agents and by the principal.

**Trust boundary:** Agents call `ockham authority promote` and `ockham intent` as shell commands. Beads state (lane labels, autonomy_tier state keys) is written by agents before Ockham reads it. Interspect evidence is produced by agent execution pipelines that Ockham reads for promotion/demotion decisions. The intent YAML is written by the principal; Ockham reads it on every CLI invocation.

**Untrusted inputs:**
- `--actor` flag value on `ockham authority promote` (agent-supplied)
- `bd list --json` output (agent-influenced via lane labels and bead granularity choices)
- interspect `agent_reliability()` results (derived from agent-executed gate results)
- `intent.yaml` content (principal-written, but file is on the filesystem where agents also run)
- `signals.db` state (written by previous Ockham invocations, persisted across sessions)

**Credentials:** None generated or stored. No tokens in scope.

**Deployment path:** CLI binary, Wave 1-3. No daemon. State persisted in SQLite and YAML files. Rollback requires deleting/restoring those files.

**Risk classification: High** — authority tier promotions, factory halt, and dispatch weight manipulation are all sensitive governance operations. Several are partially irreversible (autonomy demotion requires a confirmation window to reverse). Policy immutability during halt is a new invariant with its own failure modes.

---

## Prior Finding Verification

### S-01: No self-promotion enforcement point

**Status: Partially fixed — residual gap remains.**

Rev 3 adds: "`ockham authority promote` requires `--actor` flag that is validated against the current session's agent ID. An agent calling `ockham` cannot pass its own ID as the granting actor."

The fix addresses the enforcement point correctly at the CLI boundary. However, two residual issues are unresolved:

1. **Session identity source is unspecified.** The text says the `--actor` flag is "validated against the current session's agent ID" but does not identify where the current session's agent ID comes from. Claude Code sessions expose `$CLAUDE_SESSION_ID`. If Ockham reads this from an environment variable, an agent that controls its own shell environment can potentially set `$CLAUDE_SESSION_ID` to a different value before calling `ockham`. The fix is structurally sound only if the session ID is sourced from a non-agent-writable location (e.g., a token minted by Clavain's dispatch machinery at session start, stored outside the agent's writable paths).

2. **Delegation ceiling (invariant 2) has no enforcement point.** "An agent cannot grant authority exceeding its own level" is stated as an invariant but has no specified enforcement mechanism. If enforcement is also at the CLI boundary, the same session-identity question applies: Ockham must know the invoking agent's current tier to check the ceiling, which requires reading the agent's own authority record from interspect — a read that must happen before the write, within the same transaction or with appropriate staleness limits. This interaction is not specified.

### S-02: Agent-influenced evidence noted as Wave 3 open question

**Status: Fixed as specified.**

Open Question 2 explicitly names the evidence gaming vector: "Agents influence their own first_attempt_pass_rate through bead granularity choices. Use gate results at review time as canonical evidence, not bead closure events? (Resolve during authority package design, Wave 3.)"

This correctly defers the question to the right wave. The fix is appropriate for a brainstorm document.

### S-03: Tier 3 bypass suppressible via dedup — should use distinct_root_causes >= 2

**Status: Fixed as specified.**

Section 5 now reads: "`distinct_root_causes >= 2` fire simultaneously while operating at reduced oversight (not just signal count — prevents cascade false triggers per C-05)."

The fix is correct and directly addresses the dedup-suppression attack. One follow-on question is deferred to the new findings below.

---

## New Findings

### Finding 1 — P1: Self-promotion enforcement relies on agent-writable session identity

**Section:** Key Decision 7, Safety Invariant 1 (S-01)

The `--actor` flag validation depends on knowing the invoking agent's session ID. The brainstorm states the flag is "validated against the current session's agent ID" but does not specify how Ockham obtains the canonical session ID. The only ambient session identity in Claude Code's agent execution environment is `$CLAUDE_SESSION_ID`, which agents control as part of their shell environment. An agent constructing a shell command can prepend `CLAUDE_SESSION_ID=<peer_id> ockham authority promote --actor <peer_id> <target>`, presenting a peer's ID as both the environment identity and the flag value, passing the equality check while actually performing self-promotion under a borrowed identity.

**Concrete attack path:** Agent A wants to promote itself in domain D. Agent A knows Agent B's session ID (visible in dispatch logs, beads state, or interspect evidence). Agent A calls `CLAUDE_SESSION_ID=$AGENT_B_ID ockham authority promote --actor $AGENT_B_ID $AGENT_A_ID D`. If Ockham reads session ID only from the environment variable, it sees actor == session_id == B's ID and accepts the call.

**Mitigation:** Ockham must obtain the canonical session identity from a principal-controlled source that agents cannot overwrite. Options: (a) Require a signed dispatch token minted by Clavain's lib-dispatch.sh at session start and stored in a path outside agent home directories; (b) derive session identity from an OS-level attribute (process group, audit log PID) rather than an environment variable; (c) require the `--actor` flag to be a beads-verified session ID that matches the interspect record for who holds the current dispatch claim on the bead in question. Option (c) ties promotion authority to the dispatch claim, which is already an integrity checkpoint.

---

### Finding 2 — P1: Weight neutrality floor is stated backwards

**Section:** Key Decision 7, Safety Invariant 6 (S-08, Weight neutrality floor)

Invariant 6 reads: "No bead's offset can exceed `-24` (effectively blocked requires an explicit freeze constraint, not an organic weight)."

The bound is stated using "exceed" but the intended constraint is a lower bound (floor), not an upper bound (ceiling). A value of `-24` is the most negative organic offset allowed. "Exceed" in standard English means to go higher, so the clause "cannot exceed -24" would mean the offset cannot go above -24, which would prevent any positive or small-negative offset — the opposite of the intended safety property.

The likely intended statement is: "No bead's offset can be lower than `-24` through organic weight computation. Values below `-24` require an explicit freeze constraint." The implementation risk is that a developer reading the invariant literally could implement an upper-bound check (`offset > -24`) rather than a lower-bound check (`offset < -24`), which would invert the floor: positive offsets would be blocked, large negative offsets would pass unchecked.

**Mitigation:** Restate as: "The minimum organic ockham_offset is `-24`. An offset more negative than `-24` requires an explicit freeze constraint to be active; the weight subsystem must clamp organic offsets to `[-24, +12]`."

Additionally, note that the ±12 claim (additive offsets "bounded within one priority tier gap") needs verification. The lib-dispatch.sh scoring and intercore/scoring.go use different score representations — `scoring.go` uses float64 bonuses in the 0.1–0.5 range, while lib-dispatch.sh uses integer scores from `bd list --json` with 0–5 random perturbation. The brainstorm asserts the "priority gap between adjacent tiers is ~24 points" but this value does not appear in either scoring implementation in the codebase. If the actual tier gap is different from 24, the ±12 bound either provides too little isolation (if gap is 18) or is unnecessarily restrictive (if gap is 36). The tier gap must be verified against the live scoring before the bound is committed.

---

### Finding 3 — P1: Policy immutability during halt has no integrity mechanism

**Section:** Key Decision 7, Safety Invariant 8 (S-08, Policy immutability during halt)

Invariant 8 states: "When factory-paused.json exists, all Ockham subsystems are read-only. No weight updates, no authority changes, no signal evaluation. Only `ockham resume` (principal action) re-enables writes."

The invariant is stated correctly for the happy path. The integrity gap is that `factory-paused.json` is checked by Ockham, and Ockham is a CLI tool invoked in the agent execution environment. An agent can call `rm ~/.clavain/factory-paused.json` before invoking `ockham authority promote`, bypassing the immutability check. The sentinel file is described in the brainstorm as "filesystem-only — no agent can suppress it through evidence manipulation" (Invariant 7), but that claim addresses evidence manipulation, not direct filesystem deletion.

This is distinct from Invariant 7's claim. Invariant 7 says an agent cannot suppress the Tier 3 trigger through evidence channels. Invariant 8 says the factory halt state enforces read-only behavior. Both claims are simultaneously true, yet a file-delete attack bypasses both: it does not manipulate evidence (sidestepping Invariant 7's protection) and it removes the condition that Invariant 8 checks.

**Concrete attack path:** Agent receives BYPASS signal, factory-paused.json written. Agent deletes `~/.clavain/factory-paused.json`. Next Ockham invocation sees no sentinel, treats factory as running, resumes weight writes and authority changes. Principal sees no halt notification if the delete occurs before notification delivery (write-before-notify ordering ensures the file exists at write time, but not throughout the halt period).

**Mitigation options:** (a) Write factory-paused.json to a directory where agents do not have write permissions (requires OS-level access control, which may not be feasible in the single-user model); (b) additionally record the halt state in interspect (agent-unwritable path) as a double-sentinel — Ockham checks both, refuses to resume unless both are cleared, and only `ockham resume` clears the interspect record; (c) detect file deletion on the next Ockham invocation by storing a hash of the pause file in signals.db (also agent-writable, but a second deletion is required and leaves a gap in the audit trail). Option (b) aligns with the existing interspect durable-receipt pattern and provides the best audit trail.

---

### Finding 4 — P2: Cross-domain min-tier composition is computed at weight synthesis, invisible to the dispatcher

**Section:** Key Decision 6, cross-domain beads (ET-01/HADZA-01)

The brainstorm states: "Ockham computes this during weight synthesis; lib-dispatch.sh receives the final weight without needing to understand domain resolution."

The architectural separation is clean, but it creates an observability gap. When lib-dispatch.sh dispatches a bead and it fails mid-execution because the executing agent lacks authority for one of the crossed domains, the dispatcher has no record that the bead was min-tier constrained. The only artifact is the `ockham_offset` value in ic state, which does not distinguish "low offset because theme has low priority" from "low offset because a crossed domain is shadow-tier."

**Impact:** The weight-outcome feedback loop (Section 10) compares actual-vs-predicted cycle time by theme. A bead that was shadow-constrained due to cross-domain min-tier will have artificially inflated cycle time (agent cannot proceed autonomously, requires principal intervention). The feedback loop will attribute this to theme performance degradation and may lower the theme's weight further, compounding the problem without surfacing the real cause (cross-domain authority restriction).

**Mitigation:** Ockham should write a companion state entry alongside `ockham_offset`: `ockham_constraint_reason` with values like `none`, `theme_priority`, `domain_shadow`, `domain_freeze`. The feedback loop reads this field to filter out authority-constrained beads from the performance baseline computation. This does not require lib-dispatch.sh to understand domain resolution — the weight is still synthesized by Ockham — but it makes the constraint cause auditable for calibration.

---

### Finding 5 — P2: Intent YAML validation does not verify that freeze and focus lists name real themes

**Section:** Key Decision 4, Intent YAML schema

The validation spec states: "`ockham intent validate` checks: budgets sum to 1.0, no unknown theme names, no budget < 0 or > 1.0."

The constraints block has `freeze: []` and `focus: []` fields containing theme names. The validation description says it checks for "no unknown theme names" but this check is described only in the context of the `themes:` map entries, not the `constraints:` lists. If `freeze: [auth, typo_theme]` is written and `typo_theme` does not exist in the themes map, the spec does not explicitly state whether validation rejects this.

**Impact:** A misspelled theme name in the `freeze` list silently fails to freeze the intended theme. The factory continues dispatching beads in a theme the principal believed was frozen. This is an operational safety failure: the principal has acted (running `ockham intent` with a freeze constraint) but the action has no effect and no error is reported.

**Mitigation:** Explicitly state that `ockham intent validate` checks all names in `freeze:` and `focus:` against the keys in the `themes:` map, and returns an error if any name in those lists is not a known theme. This is consistent with the existing "no unknown theme names" check and requires no additional implementation beyond extending the existing loop.

---

### Finding 6 — P2: Weight-outcome feedback loop baseline is undefined for new themes

**Section:** Key Decision 10, Weight-outcome feedback loop

The mechanism states: "compare actual cycle time and quality gate pass rate against the predicted baseline for that theme." The predicted baseline is not defined. The document does not specify how the baseline is established for a new theme (one with fewer than N beads completed), nor what happens when the theme composition changes (beads re-labeled to a different lane).

**Impact:** For a new theme with 3 completed beads, the rolling 7-day window may have no baseline at all, or a baseline derived from too few samples to be statistically meaningful. If Ockham emits a false INFORM signal during the ramp-up period (because variance is high with few samples), it creates noise that degrades principal trust in the signal. Conversely, if the system suppresses signals until a minimum sample size is reached, it has an effective blind spot for new themes during their establishment period.

**Mitigation:** Define a minimum sample size (e.g., 10 completed beads) before the feedback loop activates for a theme. Below the minimum, Ockham does not emit weight_drift signals for that theme but records the bead completions for future baseline computation. Document this threshold alongside the 20% degradation threshold and the 7-day window.

---

### Finding 7 — P3: Tier 3 restart sequence has no timeout for "principal runs ockham resume"

**Section:** Key Decision 5, Tier 3 restart sequence (R-04)

The restart sequence begins: "Principal runs `ockham resume` (or deletes factory-paused.json)." There is no specified timeout or escalation path if the principal is unavailable. Under a 24/7 automated factory model, a Tier 3 halt that occurs while the principal is offline could leave the factory paused indefinitely.

The "or deletes factory-paused.json" alternative is also architecturally inconsistent with Finding 3 above: if file deletion is a valid resume path, then the file-delete attack in Finding 3 is indistinguishable from a legitimate principal resume action. If the goal is to allow emergency resume by file deletion, that needs to be documented as an intentional design tradeoff with the corresponding risk acknowledged.

**Mitigation:** Document maximum expected halt duration and escalation path if principal is unavailable. If automated resume is needed (e.g., after a principal-defined timeout), specify that path explicitly so it is not confused with the file-delete attack vector described in Finding 3.

---

## Deployment and Migration Review

**Risk classification: Medium.** Ockham is net-new with no existing data migration. The sensitive deployment invariants are:

1. **signals.db schema forward compatibility.** The document specifies SQLite at `~/.config/ockham/signals.db` but does not specify a schema version or migration strategy. If the schema changes between Wave 1 and Wave 2, existing signal state will be silently incompatible or must be destroyed. Specify `PRAGMA user_version` and a migration path from day one.

2. **Atomic intent.yaml writes.** The document correctly specifies "file is only replaced atomically after validation" — this is good. Verify the implementation uses `rename()` (write to tmp, then rename), not truncate-then-write, to avoid a torn-read window if Ockham is invoked between file open and write completion.

3. **Cold-start authority state is irreversible within the confirmation window.** The cold-start inference (D-05/SYS-05/R-06) starts all domains at shadow or supervised regardless of prior evidence. If a domain already had autonomous status before Ockham was deployed, the first Ockham activation will demote all domains to at most supervised. This is documented as intentional (conservative), but it creates a one-confirmation-window degradation in factory throughput at activation time. The pre-deploy checklist should include a principal acknowledgment that this demotion will occur.

**Pre-deploy checks:**
1. `ockham intent validate` exits 0 on a known-good intent.yaml — verifies validation path is reachable.
2. `ls ~/.clavain/factory-paused.json` exits 1 — verify no stale halt sentinel before activation.
3. `ockham status --json | jq '.subsystems | length == 4'` exits 0 — all four subsystems initialized.
4. `bd list --json | jq 'length > 0'` exits 0 — beads are reachable (Ockham's primary input).

**Rollback:** Fully reversible for authority state (delete `~/.config/ockham/` directory, autonomy_tier state keys revert to whatever interspect last set). Weight offsets in ic state (`ockham_offset`) must also be cleared: `ic state list ockham_offset --json | jq -r '.[].key' | xargs -I{} ic state delete {}`. This is operationally fiddly under incident pressure; a `ockham deactivate --purge` command that clears all Ockham-written state should be specified for Wave 1.

---

## Summary Table

| ID | Severity | Area | Issue |
|----|----------|------|-------|
| S-01 | Partial fix | Safety Invariant 1 | Session identity source unspecified; peer-ID spoofing attack remains possible |
| Finding 1 | P1 | Safety Invariant 1 | Self-promotion enforcement relies on agent-writable `$CLAUDE_SESSION_ID` |
| Finding 2 | P1 | Safety Invariant 6 | Weight neutrality floor stated backwards ("exceed -24" vs "floor at -24"); ±12 tier gap unverified in code |
| Finding 3 | P1 | Safety Invariant 8 | Policy immutability during halt: `factory-paused.json` can be deleted by agents |
| Finding 4 | P2 | Cross-domain resolution | Min-tier constraint reason not recorded; feedback loop attributes shadow-constrained delays to theme perf |
| Finding 5 | P2 | Intent YAML validation | freeze/focus lists not validated against known theme names |
| Finding 6 | P2 | Weight-outcome feedback | No baseline definition or minimum sample size for new themes |
| Finding 7 | P3 | Tier 3 restart | No timeout or escalation if principal unavailable; file-delete resume conflicts with attack surface in Finding 3 |

---

### Findings Index

- P1 | OCKHAM-01 | "Key Decision 7, Safety Invariant 1" | Self-promotion enforcement relies on agent-writable session identity — peer-ID spoofing bypasses the --actor check
- P1 | OCKHAM-02 | "Key Decision 7, Safety Invariant 6" | Weight neutrality floor stated backwards; ±12 tier gap unverified against actual scoring implementation
- P1 | OCKHAM-03 | "Key Decision 7, Safety Invariant 8" | Policy immutability during halt: factory-paused.json is deletable by agents in the execution environment
- P2 | OCKHAM-04 | "Key Decision 6, cross-domain beads" | Min-tier constraint reason not propagated; weight-outcome feedback loop misattributes shadow-constrained delays
- P2 | OCKHAM-05 | "Key Decision 4, Intent YAML schema" | freeze and focus constraint lists not validated against known theme names — silent no-op on typo
- P2 | OCKHAM-06 | "Key Decision 10, weight-outcome feedback loop" | No baseline definition or minimum sample size for new themes — false signals during ramp-up
- P3 | OCKHAM-07 | "Key Decision 5, Tier 3 restart sequence" | No timeout or escalation if principal unavailable; file-delete resume path ambiguous with attack surface

Verdict: needs-changes

### Summary

Rev 3 addresses all three prior findings. S-02 (evidence gaming deferred to Wave 3) and S-03 (distinct_root_causes >= 2) are fully resolved. S-01 (self-promotion enforcement) is partially resolved — the enforcement point exists at the CLI boundary, but the session identity source is unspecified, leaving a peer-ID spoofing path open. Three new P1 issues require attention: the session identity attack vector (OCKHAM-01), a backwards floor statement that will likely produce an inverted implementation (OCKHAM-02), and the factory-paused.json file-delete bypass of the policy immutability invariant (OCKHAM-03). The cross-domain resolution and feedback loop gaps (OCKHAM-04, OCKHAM-06) are P2 and relevant to Wave 1 wiring. The intent YAML validation gap (OCKHAM-05) is a one-line fix.

---

<!-- flux-drive:complete -->
