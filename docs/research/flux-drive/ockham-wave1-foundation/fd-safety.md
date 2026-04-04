# Safety Review — Ockham Wave 1 Foundation PRD

**Document:** `docs/prds/2026-04-04-ockham-wave1-foundation.md`
**Bead:** sylveste-8em
**Reviewer:** fd-safety (Flux-Drive Safety Reviewer)
**Date:** 2026-04-04
**Prior review:** `docs/research/flux-drive/ockham-vision-brainstorm/fd-safety.md` (7 findings: OCKHAM-01 through OCKHAM-07)

---

## Threat Model

**Deployment context:** Headless CLI binary (`ockham`) running on the developer's local machine as a single user account. No network exposure. State persists in `~/.config/ockham/signals.db` (SQLite) and `~/.config/ockham/intent.yaml`. The factory halt sentinel is `~/.clavain/factory-paused.json`. Agents and the principal share the same user-level filesystem permissions.

**Trust boundary:** Agents invoke `ockham` subcommands as shell commands. Beads state (lane labels, autonomy_tier entries) is agent-writable. The SessionStart hook fires `ockham check` on every agent session. The interspect evidence store is the only data path that agents cannot directly overwrite — it is the architectural trust anchor.

**Untrusted inputs:** `bd list --json` output (agent-influenced via lane labels), `ockham_offset` state read back from ic state (written by Ockham, but the read path is shared), `signals.db` contents (persisted across sessions in an agent-accessible path), and any argument supplied to an `ockham` subcommand invoked by an agent.

**Credentials:** None in scope.

**Risk classification: High** — authority tier transitions, factory halt/resume, and dispatch weight manipulation are governance operations with delayed or irreversible consequences. Several ACs in F6 and F7 directly implement the safety invariants from the brainstorm. Defects here cannot be detected by unit tests alone; they require adversarial scenario simulation.

---

## Safety Invariant Coverage Audit

The brainstorm (Section 7, rev 4) defines 8 safety invariants. This section maps each to the ACs in the PRD and flags gaps.

### INV-1 — No self-promotion

**Brainstorm text:** "`ockham authority promote` requires `--actor` flag validated against a Clavain-minted dispatch token (not `$CLAUDE_SESSION_ID`, which agents can spoof)."

**PRD coverage: NOT PRESENT.**

The PRD has no AC for `ockham authority promote`. The authority package is correctly deferred to Wave 3 as a non-goal, but the wave-3 deferral does not exempt Wave 1 from establishing the token contract. The dispatch token is the integrity anchor for INV-1 — it must be minted by Clavain and stored at a non-agent-writable path before `ockham authority promote` is wired. If Wave 1 ships without specifying where the token is written and how `ockham` reads it, Wave 3 implementors will encounter the same session-identity ambiguity documented in OCKHAM-01 and will either implement the check incorrectly or defer it again.

**What is needed:** An AC in F4 (SessionStart hook) specifying that Clavain mints a dispatch token at session start and writes it to a path outside agent home directories. The path and format do not need to be final in Wave 1, but the contract must exist so `ockham authority promote` can reference it.

### INV-2 — Delegation ceiling

**Brainstorm text:** "An agent cannot grant authority exceeding its own level."

**PRD coverage: NOT PRESENT.**

The authority package is a Wave 3 non-goal. The delegation ceiling enforcement depends on that package. This is an acceptable deferral, but the PRD should note the deferral explicitly so the Wave 3 PRD inherits the obligation. Currently the PRD's non-goals section does not mention delegation ceiling; it only says "Authority package — requires evidence accumulation from Wave 1 operation (Wave 3)." An implementor reading only the Wave 1 PRD would not know the ceiling invariant exists.

**What is needed:** One sentence in the non-goals section: "Delegation ceiling enforcement (INV-2) deferred to Wave 3 authority package."

### INV-3 — Action-time validation with degradation contract

**Brainstorm text:** "Authority checked at execution time. If interspect is unavailable, use last-known authority snapshot persisted to signals.db. Max staleness: 5 minutes. Beyond 5 minutes stale, fail-closed (deny)."

**PRD coverage: Partial.**

F4 AC states: "Authority snapshot persisted to signals.db after each successful interspect read (R-02-b)." This covers the persistence half of INV-3. However, the 5-minute staleness bound and the fail-closed behavior on stale snapshots have no AC. There is no testable criterion for "what does `ockham check` do when signals.db contains an authority snapshot that is 10 minutes old and interspect is unreachable?"

**What is needed:** An AC in F4: "`ockham check` uses the last-known authority snapshot if interspect is unreachable and the snapshot is < 5 minutes old; if the snapshot is >= 5 minutes old and interspect is unreachable, `ockham check` fails-closed (exits non-zero, logs `authority-staleness-exceeded`)." The 5-minute threshold must also appear as a configurable constant, not a magic number.

### INV-4 — Audit completeness

**Brainstorm text:** "Every authority decision produces a durable receipt in interspect."

**PRD coverage: Partial.**

F6 AC states: "Ratchet decisions logged through intercept for future distillation." This covers ratchet decisions only, not all authority decisions. The promotion guard evaluation, demotion trigger, cross-domain min-tier resolution, and 30-day re-confirmation each constitute authority decisions. There is no AC verifying that each of these paths writes an interspect receipt.

**What is needed:** An AC in F6: "Each ratchet state transition (promotion, demotion, re-confirmation pass, re-confirmation fail) writes a durable event to interspect with fields: agent, domain, prior_tier, new_tier, trigger, timestamp." The existing AC covers intercept logging but not interspect evidence — these are different stores.

### INV-5 — Human halt supremacy (write-before-notify)

**Brainstorm text:** "Write-before-notify ordering. factory-paused.json is the sentinel, not the notification."

**PRD coverage: Present and testable.**

F7 AC states: "Write-before-notify ordering: file sentinel written before any notification." This is a concrete, testable criterion. The AC for the double-sentinel (factory-paused.json AND interspect halt record) is also present. INV-5 is the strongest-covered invariant in the PRD.

**Residual gap:** The AC does not specify what constitutes "any notification." If notification is Meadowsyn (JSON file read by the UI layer), this is easy to verify. If notification includes a future webhook or email, the AC needs to enumerate the notification channels to remain falsifiable after new channels are added.

### INV-6 — Weight neutrality floor

**Brainstorm text:** "No bead's offset can go below `-6` (the clamp bound). Blocking a bead requires an explicit freeze constraint via lane-pause, not an organic weight."

**PRD coverage: Present and testable.**

F2 AC: "Scoring clamps all offsets to [-6, +6]." F3 AC: "Offsets clamped to [-6, +6] at read time (defense in depth — Ockham clamps at write, dispatch clamps at read)." The double-clamp architecture (write-side + read-side) is a sound defense-in-depth pattern and directly satisfies INV-6.

**Note:** The prior brainstorm review (OCKHAM-02) flagged the brainstorm's stated bound as "-24 ± 12" and noted the ±12 tier gap was unverified against live scoring. The PRD has resolved this: the PRD uses ±6 throughout, consistent with "half a priority tier gap" (inter-tier gap is 12 points: P0=60, P1=48). The OCKHAM-02 concern is resolved in the PRD.

### INV-7 — Signal independence (agent-unwritable sentinel)

**Brainstorm text:** "At least one Tier 3 trigger must be agent-unwritable. The interspect halt record is the agent-unwritable sentinel — even if the filesystem sentinel is deleted, `ockham check` reconstructs it."

**PRD coverage: Present, but reconstruction path has a gap.**

F7 AC: "`ockham check` reconstructs factory-paused.json from interspect halt record if file deleted." This AC addresses the reconstruction path, satisfying the letter of INV-7. However, the AC does not specify the interspect query that reconstructs the halt state — there is no AC verifying that `ockham check` reads interspect (not signals.db) as the authoritative source for reconstruction. If an implementor reads signals.db for the halt flag and signals.db is also agent-writable, the reconstruction path provides no additional tamper resistance over the file it is reconstructing.

**What is needed:** An AC explicitly naming interspect (not signals.db) as the reconstruction source: "`ockham check` queries interspect for halt records using `_interspect_query_halt()` (or equivalent); if a halt record exists in interspect and factory-paused.json is absent, `ockham check` rewrites factory-paused.json before proceeding." This ties the reconstruction specifically to the agent-unwritable path.

### INV-8 — Policy immutability during halt

**Brainstorm text:** "When halt sentinel is active, all Ockham subsystems are read-only. Only `ockham resume` clears both sentinels and re-enables writes."

**PRD coverage: Present, but insufficiently testable.**

F7 AC: "Policy immutability: when halt sentinel active, all Ockham write operations are blocked except `ockham resume`." This is the strongest AC in F7 for INV-8. However, "all Ockham write operations" is not enumerated. The testable form requires listing the operations that must be blocked: `ockham intent` (weight writes), `ockham check --write` (signal evaluation writes), `ockham authority` (ratchet transitions), and any ic state write for `ockham_offset`. Without enumeration, an implementor can write a guard for the most obvious path (intent writes) and miss the `ockham_offset` ic state write path, which is not an `ockham` subcommand — it is a side effect of scoring evaluation.

**What is needed:** The AC should enumerate blocked operations: "When factory-paused.json or the interspect halt record is active, the following operations exit non-zero with `FACTORY_HALTED`: (1) any `ockham intent` mutation, (2) any ic state write for `ockham_offset`, (3) any ratchet state transition in `internal/governor`, (4) any signal evaluation write in `ockham check`. Only `ockham resume` and `ockham health` (read-only) are permitted."

---

## Findings

### P1 — High Priority

#### SAFE-W1-001: Dispatch token contract absent — INV-1 enforcement deferred without specification

**Feature:** F4 (SessionStart hook), cross-cutting INV-1

The `ockham authority promote` subcommand is deferred to Wave 3, but the dispatch token that INV-1 depends on must be established in Wave 1. INV-1 requires: "validated against a Clavain-minted dispatch token (not `$CLAUDE_SESSION_ID`, which agents can spoof)." The prior brainstorm review (OCKHAM-01) documented the concrete attack: an agent prefixes `CLAUDE_SESSION_ID=$PEER_ID ockham authority promote --actor $PEER_ID $SELF_ID D` and passes the equality check if Ockham reads session identity from the environment.

The PRD's F4 AC wires `ockham check` into the SessionStart hook but does not specify that Clavain mints a dispatch token at session start. Without that token, Wave 3 authority implementation either rediscovers OCKHAM-01 or silently ships the `$CLAUDE_SESSION_ID` spoofing path.

**Impact:** High — self-promotion under a borrowed session identity is the highest-privilege escalation available to an agent in this architecture. An agent operating at shadow tier can permanently promote itself to autonomous by impersonating any session with a higher tier.

**Mitigation:** Add an AC to F4: "Clavain's SessionStart hook writes a dispatch token (random 32-byte hex, not derived from session ID) to `~/.clavain/dispatch-tokens/<session-epoch>.tok`, readable only by the invoking process. `ockham check` reads the dispatch token from this path and stores a hash in signals.db. Wave 3 `ockham authority promote` validates `--actor` against this stored hash, not `$CLAUDE_SESSION_ID`."

---

#### SAFE-W1-002: signals.db corruption has no recovery path and no schema version

**Feature:** F4 (SessionStart hook), F5, F6

`signals.db` is the temporal state store for Ockham: it holds signal timestamps, confirmation windows, ratchet timers, authority snapshots, and pleasure signal values. The PRD specifies it is a SQLite file at `~/.config/ockham/signals.db`. There are no ACs addressing: (a) schema versioning, (b) what `ockham check` does when the file is corrupt or has an incompatible schema, or (c) how Ockham recovers the ratchet state after signals.db loss.

**Concrete failure path:** An agent process is killed mid-write to signals.db (SQLite journal mode determines whether the transaction is atomic). On the next SessionStart, `ockham check` opens a corrupt database. Without a corruption handler, the Go `database/sql` layer returns an error. If the SessionStart hook is `ockham check 2>/dev/null || true` (as specified in F4 AC), the error is silently swallowed. Ockham appears to run but writes no updated state. The ratchet timers stop advancing. Tier 3 confirmation windows do not close. The autonomy ratchet freezes at its last-committed state. This failure is invisible — `ockham health` will either error silently or return stale data.

**Specific sub-issues:**

1. No `PRAGMA user_version` or equivalent schema-version check. A Wave 1 → Wave 2 schema change (e.g., adding the anomaly package columns) will produce silent query failures against a Wave 1 schema, not a migration prompt.

2. No `ockham check --repair` or `ockham init --reinitialize` path. When signals.db is corrupt, the only documented recovery path in the deployment review of the prior brainstorm review was "delete `~/.config/ockham/` directory" — but that destroys authority snapshots, which are needed to reconstruct ratchet state from interspect.

3. The F7 reconstruction path (`ockham check` reconstructs factory-paused.json from interspect halt record) depends on signals.db being operational. If signals.db is corrupt when factory-paused.json is deleted by an agent, the reconstruction fails silently (SessionStart hook `|| true`), and the halt sentinel is not restored.

**Impact:** Medium-to-high. Corruption during a Tier 3 halt creates a window where the halt is not enforced and the factory dispatches new work. Corruption of ratchet timers silently prevents demotion re-evaluations from firing, allowing domains to remain at autonomous tier indefinitely past their 30-day re-confirmation deadline.

**Mitigation:**

1. Specify `WAL` journal mode for signals.db to minimize corruption risk from mid-write kills.
2. Add an AC to F4: "`ockham check` opens signals.db with `integrity_check` on first open per session; if corrupt, logs `signals-db-corrupt`, backs up the file, and reinitializes from the last authority snapshot in interspect."
3. Specify `PRAGMA user_version = 1` in the Wave 1 schema, with a migration stub for Wave 2.
4. Add a `ockham check` diagnostic AC: if signals.db is unreadable and factory-paused.json is absent, check interspect for any active halt record before proceeding — do not assume factory is running.

---

#### SAFE-W1-003: INV-8 enumeration gap — ockham_offset ic state writes not guarded during halt

**Feature:** F3 (lib-dispatch.sh offset wiring), F7 (policy immutability)

The F7 AC states: "when halt sentinel active, all Ockham write operations are blocked except `ockham resume`." The gap is that `ockham_offset` writes are not performed by an `ockham` subcommand — they are performed by the `internal/governor` package via `ic state set "ockham_offset" <bead_id>`. The halt-check guard must be implemented in `internal/governor.Evaluate()` before it calls `ic state set`, not just at the CLI subcommand level.

If the guard is implemented only at the CLI entry points (`ockham intent`, `ockham check`), a caller that invokes `governor.Evaluate()` directly (e.g., a future integration layer, or an agent that builds against the Go package) bypasses the halt check. The `ic state set` write succeeds, and new weight offsets are published to the dispatch layer while the factory is supposed to be halted.

**Concrete scenario:** Tier 3 fires. factory-paused.json written. An agent's SessionStart hook fires `ockham check 2>/dev/null || true`. `ockham check` detects the halt sentinel and exits. But a second agent running a custom wrapper that calls `ockham dispatch advise --json` (which executes `governor.Evaluate()`) would publish fresh offsets if the halt guard is only at the CLI layer.

**Impact:** High — this is a direct bypass of INV-8. The policy immutability invariant is only as strong as its lowest enforcement layer.

**Mitigation:** The halt check must be enforced at the `internal/governor.Evaluate()` entry point, before any write to ic state. Add AC to F2 (scoring package): "`internal/governor.Evaluate()` reads halt sentinel state (both factory-paused.json and a signals.db halt flag) before executing any write; returns `ErrFactoryHalted` if either sentinel is active." The CLI layer's guard is a secondary check; the package-level guard is the authoritative one.

---

### P2 — Notable

#### SAFE-W1-004: Double-sentinel reconstruction path does not specify the interspect query contract

**Feature:** F7 (double-sentinel), INV-7

The F7 AC reads: "`ockham check` reconstructs factory-paused.json from interspect halt record if file deleted." This AC is testable for the happy path (halt record exists, file gets written). It is not testable for the query contract: which interspect table, which event type, and which fields identify a halt record vs a stale or superseded halt from a prior session?

Without the query contract, two risks emerge:

1. A developer implementing the reconstruction reads from signals.db (which stores authority snapshots) rather than interspect directly. signals.db is agent-writable. The reconstruction provides no additional tamper resistance.

2. A prior halt record from a previous factory run (correctly cleared by `ockham resume`) gets misidentified as an active halt on reconstruction. The factory locks itself on next startup because a stale interspect record matches the reconstruction query.

**Mitigation:** Add a sub-AC: "`ockham check` queries interspect for halt records using event type `ockham-factory-halt` with `status=active`; resume events written by `ockham resume` set `status=cleared`. Reconstruction only fires on records where `status=active` and `session_epoch` matches the current factory instance."

---

#### SAFE-W1-005: Pleasure signal values in signals.db are used for ratchet promotion — no freshness check

**Feature:** F5 (pleasure signals), F6 (autonomy ratchet)

F5 AC: "Pleasure signal values written to signals.db for ratchet consumption." F6 AC: promotion guards use `hit_rate >= 0.80, sessions >= 10, confidence >= 0.7`. The ratchet reads pleasure signals from signals.db. There is no AC specifying how old a pleasure signal value can be before it is treated as stale for ratchet promotion decisions.

If `ockham check` has not run for 72 hours (principal was offline, no agent sessions started), the pleasure signals in signals.db are 72 hours stale. On the next invocation, the ratchet may promote a domain to supervised based on values that are three days old and may no longer reflect current factory behavior. This is particularly relevant for the 30-day re-confirmation: if signals are stale at re-confirmation time, the guard evaluates against old data and may incorrectly pass.

**Mitigation:** Add an AC to F5: "Pleasure signal values in signals.db have a `computed_at` timestamp; the ratchet rejects signals older than 48 hours for promotion decisions and logs `signal-staleness-warn`. For re-confirmation, if the most recent pleasure signal is older than 48 hours, re-confirmation is postponed until a fresh evaluation is available."

---

#### SAFE-W1-006: F3 CONSTRAIN evaluation order is listed but not tied to a specific AC with a pass/fail test

**Feature:** F3 (lib-dispatch.sh offset wiring), INV-6

The F3 AC specifies the evaluation order: "(1) CONSTRAIN check — frozen theme → score=0, skip; (2) apply ockham_offset; (3) perturbation; (4) floor guard." This is the correct order from the brainstorm (freeze takes precedence, then offset, then perturbation). However, no AC requires a test that verifies order violations are caught.

Specifically, if perturbation fires before the floor guard, a bead can receive `score = 1 + perturbation(0-5) = 1-6` (since floor guard raises score < 1 to 1, but perturbation has already run). If the CONSTRAIN check is moved after offset application, a frozen theme's bead can receive a non-zero weight from `ockham_offset` that overrides the freeze. Neither of these order violations is caught by the existing ACs.

**Mitigation:** Add an AC: "A unit test verifies evaluation order: a bead in a frozen theme receives score=0 regardless of ockham_offset value (+6 or -6); a bead not in a frozen theme with offset=-6 and raw_score=1 receives final_score=1 (floor guard applied after offset)."

---

#### SAFE-W1-007: Cold-start authority inference has no AC for the conservative cap

**Feature:** F6 (autonomy ratchet), deployment

The brainstorm specifies: "If evidence meets autonomous guard → start at supervised anyway (conservative). No evidence → shadow." F6 AC states: "Cold start: infer from interspect evidence. Meets supervised guard → start supervised. Meets autonomous guard → start supervised (conservative). No evidence → shadow." This matches the brainstorm.

The gap is that there is no AC verifying the conservative cap is actually enforced. An implementor who reads the transition table (shadow→supervised, supervised→autonomous) may implement cold start as "jump to the highest tier the agent qualifies for" rather than "cap at supervised." The conservative cap is a safety property — it prevents a factory from activating Ockham and immediately granting autonomous tier to all agents, bypassing the supervised confirmation window.

**Mitigation:** Add an explicit AC: "Cold-start inference never assigns autonomous tier directly; any agent×domain pair with evidence qualifying for autonomous starts at supervised and must pass a full supervised→autonomous promotion cycle before reaching autonomous."

---

### P3 — Low Priority

#### SAFE-W1-008: Ratchet demotion for cross-domain beads is not covered by an AC

**Feature:** F6 (autonomy ratchet), cross-domain composition

F6 AC covers: "Cross-domain beads: authority resolves to min(tier_per_domain)." But there is no AC for the demotion scenario: if a bead crosses domains A (autonomous) and B (shadow), the bead is dispatched at shadow authority. If execution fails under shadow constraints, does this failure count as evidence against domain A or domain B or both? The prior brainstorm identified that shadow-constrained failures can be misattributed to theme performance by the feedback loop (OCKHAM-04).

This is lower priority in Wave 1 because the feedback loop is advisory-strength (log + suggest) and the authority package is deferred. But the data model decision — which domain gets attributed the failed bead — needs to be captured as a known gap before Wave 3 authority package design.

**Mitigation:** Add a non-goal note: "Cross-domain failure attribution (which domain's ratchet evidence is updated on a min-tier constrained failure) is deferred to Wave 3 authority package. Wave 1 does not write ratchet evidence for cross-domain beads where min-tier constrained the outcome; log `cross-domain-constrained` flag on the interspect record for Wave 3 attribution."

---

#### SAFE-W1-009: `ockham resume --constrained` intent-change scope is unspecified

**Feature:** F7 (resume path), INV-8

F7 AC: "`ockham resume --constrained` allows intent changes while keeping factory paused." INV-8 states that when the halt sentinel is active, all Ockham write operations are blocked except `ockham resume`. The `--constrained` flag creates an exception: some writes are permitted (intent changes) while the halt remains.

The scope of "intent changes" is not defined. Can `ockham resume --constrained` change theme weights and budgets? Add new themes? Change the freeze list? Unfreeze a theme that was frozen before the halt? Unfreezing a theme while the factory is paused and then releasing it may lead to an unintended burst of dispatching in the newly unfrozen theme immediately on resume.

**Mitigation:** Enumerate the permitted writes under `--constrained`: "Permitted: `ockham intent --theme X --budget Y`, `ockham intent --priority`. Not permitted: `ockham intent --unfreeze`, `ockham intent --unfocus`. Removing freeze/focus constraints during a halt must wait for `ockham resume` (full resume), not `--constrained`."

---

## Deployment and Migration Review

**Risk classification: High** for signals.db management; Medium for the remaining deployment steps.

### Pre-deploy checks (measurable pass/fail)

1. `sqlite3 ~/.config/ockham/signals.db "PRAGMA integrity_check;"` exits 0 and returns `ok` — verify schema is intact before activation.
2. `ls ~/.clavain/factory-paused.json 2>/dev/null` exits 1 — no stale halt sentinel from a prior test run.
3. `ockham intent validate` exits 0 on a known-good intent.yaml.
4. `ockham check --dry-run` exits 0 — signal evaluation path reachable without writing state.
5. `ockham authority show --json` exits 0 and returns a valid JSON structure — ratchet store initialized.
6. `bd list --json | jq 'length > 0'` exits 0 — beads reachable (primary Ockham input).

### Rollback feasibility

Wave 1 ships no data migration for existing systems. Rollback requires:

1. Remove `ockham check 2>/dev/null || true` from Clavain's SessionStart hook.
2. Clear `ockham_offset` entries from ic state: `ic state list ockham_offset --json | jq -r '.[].bead_id' | xargs -I{} ic state delete {} ockham_offset` — this is operationally fiddly under incident pressure and requires a `ockham deactivate --purge` shortcut (per OCKHAM prior review recommendation, still unaddressed in the PRD).
3. Delete `~/.config/ockham/` — destroys signals.db and intent.yaml.
4. Revert lib-dispatch.sh changes (git checkout the pre-Wave-1 version of the file).

Steps 2 and 4 require coordinated timing: if lib-dispatch.sh is reverted while ockham_offset entries still exist in ic state, dispatch will read stale offset values through the old code path (if any offset-reading code remains) or ignore them (if reverted clean). The PRD does not specify which order is safe.

**Rollback sequencing recommendation:** (1) revert lib-dispatch.sh first, (2) then clear ic state ockham_offset entries, (3) then remove SessionStart hook wiring. This order ensures dispatch never reads Ockham offsets after lib-dispatch.sh is reverted.

### Irreversible steps

**Ratchet cold-start inference** is the one step that changes observable factory behavior at activation time. All domains demote to at most supervised on first `ockham check`. This is the activation regression risk noted in the brainstorm and the prior review. The pre-deploy checklist must include a principal acknowledgment that this demotion will occur and that the first confirmation window will require manual observation before domains restore to prior autonomy levels.

### signals.db as deployment dependency

The SessionStart hook AC is `ockham check 2>/dev/null || true` — fail-open. If signals.db does not exist on first run, `ockham check` must initialize it (not crash silently). If the initialization writes a corrupt schema due to disk pressure or a killed process, subsequent invocations fail silently via the `|| true`. There is no monitoring signal that Ockham is failing on every session start. Add an AC: "`ockham check` writes a health file to `~/.config/ockham/last-check-ok` on successful completion; Clavain's `doctor` check flags if this file is absent or older than 2 sessions."

---

## Summary Table

| ID | Severity | Feature | Issue |
|----|----------|---------|-------|
| SAFE-W1-001 | P1 | F4 / INV-1 | Dispatch token contract absent — INV-1 enforcement deferred without specifying the token mechanism |
| SAFE-W1-002 | P1 | F4, F5, F6 | signals.db corruption: no schema version, no recovery path, silent fail-open via SessionStart hook |
| SAFE-W1-003 | P1 | F3, F7 / INV-8 | Policy immutability guard missing at `internal/governor.Evaluate()` — CLI-layer guard is bypassable |
| SAFE-W1-004 | P2 | F7 / INV-7 | Double-sentinel reconstruction path does not specify the interspect query contract |
| SAFE-W1-005 | P2 | F5, F6 | Pleasure signals in signals.db have no freshness bound — stale values can drive ratchet promotion |
| SAFE-W1-006 | P2 | F3 / INV-6 | Evaluation order specified but no AC with a pass/fail test for order violations |
| SAFE-W1-007 | P2 | F6 | Cold-start conservative cap (no direct autonomous assignment) has no AC verifying it is enforced |
| SAFE-W1-008 | P3 | F6 | Cross-domain failure attribution not specified — data model gap before Wave 3 authority package |
| SAFE-W1-009 | P3 | F7 | `ockham resume --constrained` permitted write scope unspecified — unfreeze during halt may cause dispatch burst |

---

### Findings Index

- P1 | SAFE-W1-001 | "F4 (SessionStart hook)" | Dispatch token contract absent — INV-1 self-promotion defense has no Wave 1 AC establishing the token mechanism
- P1 | SAFE-W1-002 | "F4, F5, F6 (signals.db)" | signals.db corruption produces silent fail-open via `|| true` hook; no schema version, no recovery path, halt reconstruction fails silently
- P1 | SAFE-W1-003 | "F3, F7 (governor.Evaluate / policy immutability)" | INV-8 halt guard missing at package layer — CLI-layer guard bypassable by direct `governor.Evaluate()` callers
- P2 | SAFE-W1-004 | "F7 (double-sentinel reconstruction)" | Interspect query contract for halt record reconstruction unspecified — implementation may read agent-writable signals.db instead
- P2 | SAFE-W1-005 | "F5, F6 (pleasure signal freshness)" | No staleness bound on signals.db pleasure values used for ratchet promotion — stale signals can drive incorrect tier transitions
- P2 | SAFE-W1-006 | "F3 (evaluation order)" | Evaluation order specified in prose but no AC with a falsifiable test for order violations — freeze bypass and floor-guard inversion are undetected by existing ACs
- P2 | SAFE-W1-007 | "F6 (cold-start cap)" | Conservative autonomous cap has no testable AC — implementor may assign autonomous tier directly if evidence qualifies
- P3 | SAFE-W1-008 | "F6 (cross-domain attribution)" | Cross-domain failure attribution data model not captured as known gap before Wave 3 — ratchet evidence may be written to the wrong domain
- P3 | SAFE-W1-009 | "F7 (resume --constrained)" | Permitted writes under `--constrained` unspecified — unfreeze during halt and subsequent dispatch burst is an unguarded path

Verdict: needs-changes

### Summary

The PRD covers the safety surface significantly better than the brainstorm did. INV-5 (write-before-notify), INV-6 (weight clamp double-enforcement), and the double-sentinel mechanism are well-specified and testable. Three P1 gaps remain. First, the dispatch token contract (INV-1) is absent: the authority package is correctly deferred to Wave 3, but the token mint spec must exist in Wave 1 or the Wave 3 implementor rediscovers the OCKHAM-01 peer-ID spoofing attack. Second, signals.db corruption is a silent failure: the `ockham check 2>/dev/null || true` SessionStart hook suppresses all errors including schema corruption, and a corrupt signals.db at halt time prevents the double-sentinel reconstruction path from working. Third, the INV-8 policy immutability guard belongs in `internal/governor.Evaluate()` — the CLI-layer guard is bypassable by any caller that uses the Go package directly rather than the CLI. The P2 gaps (interspect query contract for reconstruction, pleasure signal freshness, evaluation order test, cold-start cap AC) are straightforward to add as ACs before implementation begins.

<!-- flux-drive:complete -->
