# fd-architecture — Auto-proceed authz framework

## Findings Index

- [P0] Policy system name collision with existing `policy-check` / `policy-show` commands in `clavain-cli` — Module Boundaries
- [P0] `sprint_or_work_flow` condition has no write path: `/clavain:work` Phase 3 and `/clavain:sprint` Steps 6-7 contain no `vetted_at` or `vetted_with` writes today — Vetting Signal
- [P1] Gate wrapper pattern has no registry or discovery mechanism; unwrapped ops are silent bypasses — Gate Wrapper Pattern
- [P1] Naming collision: brainstorm proposes `clavain-cli policy check/explain/audit/set/list/lint` as subcommand hierarchy, but `clavain-cli` uses flat verb tokens (`policy-check`, `policy-show`); structural mismatch — CLI Surface
- [P1] `vetting TEXT` column as opaque JSON breaks `policy check` evaluation purity: gate must parse JSON at runtime, preventing schema-level constraint or index use — Schema Design
- [P1] Two parallel write paths for authorization persist through v1: `.publish-approved` marker and `authorizations` table. The bridging note creates a synthetic record that can be replayed or omitted silently — Code Reuse / Duplication
- [P1] `policy check` exit-code contract (0/1/2/3) is undefined relative to the existing `policy-check` exit behavior (`Allowed: bool` JSON to stdout, always exit 0) — API Stability
- [P2] `delegate_to TEXT` in `authz_tokens` is a single hop; Claude → codex → skaffen chains require a linked list, not a scalar — Schema Design (v2)
- [P2] No `vetted_sha` column in `authorizations` or in `requires` conditions: vetting freshness check without content-address is gameable — Schema Design
- [P2] Global vs per-project merge semantics for `requires` conditions are underspecified: "tighten-only" needs a formal operator, not prose description — Layering
- [P2] `policy set <op> <mode>` is session-scoped but written nowhere durable; collides with `CLAVAIN_POLICY_FILE` env override; three override sources with undefined precedence — CLI Surface
- [P2] `mode` column has no CHECK constraint; `agent_id TEXT` has no format enforcement — Schema Design

---

## Verdict

SHIP-WITH-CHANGES

The authz framework's core problem statement is sound and the v1 design carries most of the value. Two P0 issues must be resolved before implementation begins: the `policy-check` naming collision inside an already-shipped Go binary, and the missing vetting-signal write path in `/work` and `/sprint` (without which `sprint_or_work_flow: true` and `vetted_within_minutes` conditions can never fire). The P1 issues around gate-wrapper discovery and the parallel `.publish-approved` write path are structural debt that will solidify quickly if shipped as-is; they should be resolved in v1 rather than deferred to v1.5. None of the issues require architectural rethink — each has a small, targeted fix.

---

## Summary

The brainstorm correctly identifies that enforcement must live in infrastructure, not agent memory, and the pull-model v1 design is the right minimal viable shape. The deepest structural risk is that the proposed `policy check` command and the existing `policy-check` command in `clavain-cli` are the same binary speaking different languages: one outputs JSON with `Allowed: bool`, the other is supposed to return exit codes 0/1/2/3 and drive shell control flow — these must be unified or separated cleanly before any gate wrapper is written. The vetting-signal write path is the other load-bearing gap: `/clavain:work` Phase 3 currently contains no `bd set-state` call for `vetted_at`, meaning the most important policy conditions are always unevaluable at gate time.

---

## Module Boundaries Diagram (text)

```
┌─────────────────────────────────────────────────────────────┐
│  L2 OS — Clavain                                            │
│                                                             │
│  Skills / Commands (/work, /sprint)                         │
│    │                                                        │
│    │ writes vetting signal (MISSING TODAY)                  │
│    ▼                                                        │
│  bd set-state vetted_at / vetted_with                       │
│    │                                                        │
│    │ reads bead state at gate time                          │
│    ▼                                                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Policy Engine  (proposed)                           │   │
│  │    yaml loader (global → project → env)              │   │
│  │    rule matcher (op_type × mode)                     │   │
│  │    condition evaluator (vetted_within, tests_passed) │   │
│  │    ── lives in clavain-cli as new subcommand group ─ │   │
│  └───────────┬──────────────────────────────────────────┘   │
│              │ exit 0/1/2/3 + stderr reason                 │
│              ▼                                              │
│  Gate Wrappers (thin bash, one per op)   ◄── NO REGISTRY    │
│    bead-close-gate.sh                                       │
│    git-push-gate.sh                                         │
│    ic-publish-gate.sh                                       │
│    bd-push-gate.sh                                          │
│    │                                                        │
│    │ on auto: execute op                                    │
│    │ on confirm: ask (tty) or block (no-tty)                │
│    ▼                                                        │
│  Audit Log Writer                                           │
│    clavain-cli policy record → authorizations table         │
│    ── seam: must be atomic with op or post-op ──            │
│              │                                              │
│              ▼                                              │
│  intercore.db  (.clavain/intercore.db, per-project)         │
│    authorizations table                                     │
│    authz_tokens table  (v2)                                 │
│                                                             │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│  Parallel (v1 only, to be unified):                         │
│    .publish-approved  ──► ic publish (L1 intercore)         │
│    synthetic record writer (bridging shim)                  │
└─────────────────────────────────────────────────────────────┘

Signing module (v1.5): wraps audit log writer, adds `signature BLOB`
Token issuer / consumer / revocator (v2): wraps policy engine,
  primary path when token present; pull-model fallback when absent
```

Key seams:
- **Policy engine ↔ gate wrapper**: exit code contract (0/1/2/3) is the only interface. Must be stable before v1.5.
- **Gate wrapper ↔ audit log writer**: `policy record` is called after op executes. Gap between check and execute is racy but acceptable for v1 given single-user, single-host assumption.
- **Vetting signal writer ↔ policy engine**: entirely mediated by `bd set-state` / `bd state`. The engine is pure (yaml + bead state in, decision out) only if `bd state` is treated as the canonical source of vetting truth.
- **`.publish-approved` ↔ authorizations table**: two write paths to the same logical decision. Bridging shim is a seam that must be explicitly owned.

---

## Issues Found

### [P0] Policy system name collision with existing `policy-check` and `policy-show` — Module Boundaries

`clavain-cli` already ships `policy-check` and `policy-show` (flat tokens, no subcommand group). The brainstorm proposes `clavain-cli policy check`, `policy explain`, `policy audit`, `policy set`, `policy list`, `policy lint` as a grouped subcommand surface. These are not the same thing.

The existing `policy-check` evaluates path/tool access against phase-based allow/deny lists (holdout scenario gating). It returns `{"allowed": bool, "reason": "..."}` on stdout and always exits 0. The brainstorm's `policy check` is an auto-proceed gate that returns exit codes 0/1/2/3 and drives shell control flow. They share a name, live in the same binary, and serve different concerns.

Shipping the brainstorm's design as `policy check` without resolving this will break existing callers of `policy-check` or silently create two unrelated commands with overlapping names. The smallest fix: rename the existing phase-gating commands to `scenario-policy-check` / `scenario-policy-show` (their actual domain is scenario holdout access, not authz), and claim `policy` as the subcommand group namespace for the new authz surface. This is a one-commit rename with a deprecation alias.

### [P0] `sprint_or_work_flow` and `vetted_within_minutes` conditions have no write path — Vetting Signal

The brainstorm states that `/clavain:work` Phase 3 and `/clavain:sprint` Steps 6-7 "already know when tests passed and verification ran" and should be extended to write `bd set-state "$CLAVAIN_BEAD_ID" vetted_at=<unix_ts>`. Reading `/os/Clavain/commands/work.md` Phase 3 shows no such write exists today. The sprint command also contains no equivalent write. The `sprint_or_work_flow: true` condition in the policy yaml has no evaluable signal to read at gate time.

This means that in v1 as specified, the most important rule — `bead-close` auto-proceeds when `vetted_within_minutes: 60, tests_passed: true, sprint_or_work_flow: true` — can never fire, because the condition evaluator will find no `vetted_at` in bead state and must either return "blocked" or default-allow. Neither is correct.

The fix requires writing `vetted_at` and `tests_passed` to bead state from within Phase 3 of `/work` and from sprint Steps 6-7 before gate evaluation is possible. This is a required precondition for v1, not an enhancement.

### [P1] Gate wrapper pattern has no discovery or registry mechanism — Gate Wrapper Pattern

The design relies on convention: every irreversible op gets a thin wrapper that calls `policy check` before executing. There is no registry of what ops are irreversible, no test that all known ops are wrapped, and no way for the policy engine to enumerate gates. The `/ship` skill and `landing-a-change` skill both sequence `bd close`, `git push`, `bash .beads/push.sh`, and `ic publish` — none of those call any gate today.

If any of those codepaths is invoked without a wrapper, the policy system is silently bypassed. This is not a theoretical concern: `auto-push.sh` (a hook) and the `/ship` skill both reach `git push` through paths that won't automatically pick up new wrappers.

The smallest fix that doesn't require a full registry: add a `clavain-cli policy gate-list` command that emits the canonical list of wrapped ops. Gate wrappers register themselves in a `.clavain/gates/` directory (one file per op, with the op name and wrapper path). Structural tests can assert that all known irreversible ops have a registration. This is lighter than a full registry and composable with the policy lint command.

Separately: `bash .beads/push.sh` wraps `dolt push`, not `bd push`. Wrapping `.beads/push.sh` is correct because `push.sh` is the single callsite. `bd push` itself should not be wrapped independently.

### [P1] `clavain-cli` subcommand surface is a structural mismatch — CLI Surface

`clavain-cli`'s existing command dispatch (see `/os/Clavain/cmd/clavain-cli/main.go`) uses flat case-matched tokens (`policy-check`, `sprint-init`, `checkpoint-write`, etc.). There is no subcommand group routing. The brainstorm proposes `clavain-cli policy check` which would require `policy` as the first argument and `check` as the second — a two-level dispatch that does not exist in the binary's current switch statement.

This is not a blocking objection to the design; the binary can be extended. But it requires either: (a) adding a new case for `policy` that dispatches a second-level switch, or (b) continuing the flat token pattern as `policy-check-authz`, `policy-explain`, `policy-audit-log`, etc. Option (a) is architecturally cleaner and matches the brainstorm intent; it is the right choice if the intent is to grow this into a proper subcommand surface. Option (b) is less refactoring but produces an incoherent help text alongside the existing `policy-check` flat token.

The `policy audit` verb also conflicts with `evidence-pack` / `evidence-list` territory, which already serve some authz-evidence-adjacent purposes. Audit as a verb is fine; just ensure the help output distinguishes "policy audit" (authz records) from "evidence-list" (sprint quality evidence).

`policy set` as a session-scoped override is the weakest verb. It has no durability (session-scoped means it vanishes on process exit), no defined storage mechanism, and three existing override sources (`~/.clavain/policy.yaml`, `<project>/.clavain/policy.yaml`, `CLAVAIN_POLICY_FILE`) that already provide the same function more durably. Drop `policy set` from v1; it adds state surface without adding capability.

### [P1] Two parallel write paths — Code Reuse / Duplication

The `.publish-approved` marker (consumed by `internal/publish/approval.go` in intercore) and the `authorizations` table are two separate authorization signals for the same class of decision. The bridging note proposes logging `.publish-approved` creation as a synthetic authz record, creating a shim that must fire every time a marker is created.

The risk is that the shim is called inconsistently: `.publish-approved` is created by agents (who write a file), by humans (who `touch .publish-approved`), and potentially by `ic publish --auto` itself. A bridging shim that only covers one of those callsites will produce an audit trail with gaps that look like policy bypasses.

For v1, do not bridge. Instead, document explicitly that `.publish-approved` is outside the authz framework scope until v1.5 unification. The `authorizations` table covers `bead-close`, `git-push-main`, `bd-push-dolt`. The `ic-publish-patch` op is gated by the new authz system in addition to `.publish-approved`, not instead of it. Two gates on the same op is redundant but not incorrect; it eliminates the bridging shim and its inconsistency risk. Unify at v1.5 by adding authz record lookup to `RequiresApproval()` in `internal/publish/approval.go`.

### [P1] `policy check` exit-code contract is undefined relative to existing behavior — API Stability

Agents and shell scripts that script against the policy system will lock onto the exit-code and JSON shape early. The existing `policy-check` always exits 0 and emits JSON. The brainstorm's `policy check` exits 0/1/2/3 with reasons on stderr. These must be documented as a stable contract before v1 ships, not after.

Specifically: what does exit 2 ("blocked") mean in a non-tty CI environment where the agent cannot ask for confirmation? The brainstorm lists this as Open Question 7 ("block by default, configurable") but the answer must be encoded in the exit-code table, not left to configuration drift. Recommend: exit 2 always means "this op is administratively blocked regardless of tty". Exit 1 means "confirmation required; caller decides how to handle". This separation lets non-tty agents distinguish "ask the user" from "this is policy-prohibited".

The JSON output on stdout (for `policy explain`) should be versioned from day one with a `schema` field, since agents will script against it across v1/v1.5/v2 as the token layer adds fields.

### [P2] `delegate_to TEXT` is a single hop — Schema Design (v2)

The v2 `authz_tokens` table includes `delegate_to TEXT` and `parent_token TEXT`. `delegate_to` is a single agent ID. A Claude → codex → skaffen chain requires the table to support chains longer than two hops. `parent_token TEXT` handles the reverse pointer (child knows its parent), but a consumer verifying the chain must walk the table recursively. This is queryable but expensive and fragile if a chain member's record is missing.

The smallest fix: add a `depth INTEGER NOT NULL DEFAULT 0` column and a `root_token TEXT` column (always pointing to the original user-issued token). Chain depth is then a single read rather than a recursive walk, and revocation of the root propagates to all descendants via `root_token`.

### [P2] No `vetted_sha` in schema or conditions — Schema Design

The brainstorm identifies in Open Question 6 that `vetted_sha == HEAD` is needed to prevent stale vetting from authorizing post-edit code. The `vetting TEXT` JSON blob is documented as `{tests_passed, verified_with, sha, vetted_at}` but `sha` is not a first-class column in `authorizations`, and `vetted_sha` is not in the `requires` block of any policy rule.

This means the policy engine cannot evaluate "was the vetting on the current HEAD" without parsing the JSON blob. Promote `vetted_sha TEXT` to a first-class column in `authorizations`, add `vetted_sha` as an optional key to `requires`, and add a `vetted_sha_matches_head: true` condition evaluator that reads `git rev-parse HEAD` at check time. This is the highest-value single addition to the schema for the stated threat model ("buggy agent claims vetted without vetting").

### [P2] `requires` merge semantics across global and per-project policy are underspecified — Layering

The brainstorm states "project can tighten (add conditions)" with a note about `mode_override: force_auto` for loosening. This is prose, not a rule. The actual merge question is: if global policy has `requires: {vetted_within_minutes: 60, tests_passed: true}` and project policy has `requires: {vetted_within_minutes: 30}`, is the result `{vetted_within_minutes: 30, tests_passed: true}` (tighten: shorter window, keep other) or `{vetted_within_minutes: 30}` (replace: project replaces global requires entirely)?

The ambiguity matters for the policy engine implementation. Recommend: per-key merge with tighten-only semantics for numeric thresholds (min wins), additive for boolean flags (AND semantics — if global requires `tests_passed: true`, project cannot drop it without explicit `allow_override: [tests_passed]` declaration). Document this as the merge algorithm in the policy yaml schema comment, not as prose in the brainstorm.

### [P2] `mode` has no CHECK constraint; `agent_id` has no shape enforcement — Schema Design

The `authorizations` table defines `mode TEXT NOT NULL` with documented values `auto | confirmed | blocked` but no `CHECK (mode IN ('auto', 'confirmed', 'blocked'))` constraint. A bug in a gate wrapper writing `mode = "AUTO"` or `mode = "skipped"` will silently create an invalid record that audit queries miscount.

`agent_id TEXT NOT NULL` is documented as "session id" but session IDs have a format (the intercore/Clavain convention appears to be the CLAUDE_SESSION_ID env var, which is a hex string). Without a CHECK or a format comment, cross-session continuity (Open Question 5) will be implemented inconsistently across fleet agents.

Both are one-line DDL fixes. Add them before the table ships in production.

---

## Improvements

- Rename the existing phase-gating commands from `policy-check` / `policy-show` to `scenario-policy-check` / `scenario-policy-show` before adding the new authz `policy` subcommand group. Retain a deprecation alias for one release cycle.

- Add `bd set-state "$CLAVAIN_BEAD_ID" vetted_at=$(date +%s)` and `bd set-state "$CLAVAIN_BEAD_ID" tests_passed=true` to `/clavain:work` Phase 3 (after tests pass) and to `/clavain:sprint` Steps 6-7. This is the mandatory precondition for any policy condition to be evaluable.

- Drop `policy set` from the v1 CLI surface. The three-layer yaml override already covers session-scoped policy changes via `CLAVAIN_POLICY_FILE`. Adding a fourth ephemeral override source creates confusion for agents scripting the policy.

- Add `vetted_sha TEXT` as a first-class column in `authorizations`. Add `vetted_sha_matches_head: true` as an optional `requires` key. Write the sha at vetting time (`git rev-parse HEAD`) alongside `vetted_at`.

- Add `CHECK (mode IN ('auto', 'confirmed', 'blocked'))` to the `authorizations` DDL. Add an inline schema comment naming `agent_id` as "CLAUDE_SESSION_ID or <agent-type>:<stable-key-fingerprint>".

- Define the `requires` merge algorithm formally in the policy yaml schema: per-key merge, numeric thresholds use min(), boolean flags use AND. Per-project overrides cannot drop global boolean requirements without an explicit `allow_override` key.

- For v2 `authz_tokens`: add `depth INTEGER NOT NULL DEFAULT 0` and `root_token TEXT` columns. Revocation by root covers the full delegation chain in one UPDATE.

- Do not bridge `.publish-approved` to the `authorizations` table in v1. Gate `ic-publish-patch` through the new authz system as an additional gate alongside the marker. Unify at v1.5 by modifying `RequiresApproval()` in `/home/mk/projects/Sylveste/core/intercore/internal/publish/approval.go` to consult `authorizations` records when the marker is absent.

- Add a `.clavain/gates/` registration directory. Each gate wrapper drops a one-line file (`bead-close: hooks/bead-close-gate.sh`). `clavain-cli policy lint` validates that all registered ops have a working wrapper. Structural tests assert the gate list is non-empty.

- Specify the exit-code contract in the schema before v1 ships: exit 0 = auto-proceed, exit 1 = confirmation required (caller handles tty/non-tty), exit 2 = administratively blocked (no tty path), exit 3 = policy error (yaml parse fail or bead state unavailable). Add a `schema` field to all JSON stdout output from the policy subcommand group.

<!-- flux-drive:complete -->
