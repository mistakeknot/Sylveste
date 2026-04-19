---
date: 2026-04-19
session: 4059d2e5
topic: Agent auto-proceed authorization framework (policy + audit + tokens)
related_memory: feedback_auto_proceed_vetted_flow.md
related_beads: [sylveste-qdqr]
phase: brainstorm-reviewed
review:
  date: 2026-04-19
  agents: [fd-safety, fd-decisions, fd-systems, fd-architecture, fd-correctness]
  verdict: SHIP-WITH-CHANGES (unanimous)
  synthesis: docs/research/flux-drive/2026-04-19-auto-proceed-authz-design-20260419T0239/SYNTHESIS.md
---

# Auto-proceed authorization framework — brainstorm

> **2026-04-19 review note:** Flux-drive reviewed by 5 agents (verdict: unanimous SHIP-WITH-CHANGES). Open questions now have recommended dispositions inline (see §Open questions). P0 spec gaps are folded into v1 schema + CLI sections below. Full findings: `docs/research/flux-drive/2026-04-19-auto-proceed-authz-design-20260419T0239/SYNTHESIS.md`.

## Problem

Agents running `/clavain:route` → `/clavain:work` / `/clavain:sprint` flows hit multiple irreversible ops at session close: `bd close`, `git push`, `bash .beads/push.sh`, `ic publish --patch`. Today each one requires human confirmation. Re-confirming every op when the upstream flow already vetted the change (tests passed, measure/verify evidence, user explicitly kicked off the flow) is pointless friction.

Simultaneously: re-confirming is the only thing preventing a buggy agent from running the checklist without having actually vetted anything. The naive "auto-proceed on everything" fix is strictly worse than the friction.

**Goal:** a durable mechanism that lets vetted agent flows proceed without re-confirming, but prevents unvetted flows from auto-proceeding, and produces an audit trail the user can inspect.

## Why this needs infrastructure, not memory

Memory files work inside Claude Code but not across the fleet. arouth1 is already running Claude → codex delegation in sprints; skaffen and other fleet agents are coming. Memory is advisory (I read it, I try to obey it); infrastructure is enforcement (the gate returns 1 or it doesn't, regardless of which agent is calling). The `.publish-approved` marker already proved the shape — a file-system gate that `ic publish` checks regardless of caller.

## Decision traversed: why 2.5 → 3, not 2.5 OR 3

Three options were considered:

| Option | Mechanism | Complexity |
|---|---|---|
| **2** — Policy engine | Pull-model. `clavain-cli policy check <op>` returns 0/1 based on yaml + bead state. | ~1 day |
| **2.5** — Policy + signed audit | Policy engine as in (2) plus each `authorizations` record signed with a project-scoped key. Unforgeable audit. | ~1.5 days |
| **3** — Full token protocol | Push-model. User issues signed tokens per-op per-bead. Agents present tokens to gates. TTL, single-use, revocable, delegable. | ~1 week |

**Option 3 recurses into Option 2.** If the user has to issue a token for every auto-proceed, friction increases, not decreases. The only way Option 3 reduces friction is via a meta-authorization ("auto-issue tokens for any bead I vetted via /work") — which is Option 2 with a token wrapper. So Option 3 earns its complexity only if you need:
1. Agent-to-agent delegation (parent authz delegates to child agent)
2. Single-use consumption
3. Unforgeable audit chain-of-custody
4. Revocation-before-consumption

**arouth1 is already running Claude → codex delegation**, so (1) is real, not speculative. Trajectory is 2.5 → 3, not 2.5 OR 3. Ship 2.5 as MVP (carries most of the value), layer tokens on top when the basics land.

## Design axes

### Axis 1 — Unify vs parallel for `.publish-approved`

**v1 = parallel.** Keep `.publish-approved` working as-is. Add the new policy/audit system for `bd close`, `git push`, `bash .beads/push.sh`, and any future op. Bridge the audit-log gap with a one-liner that logs `.publish-approved` creation as a synthetic authz record.

**v1.5 or v2 = unify.** `ic publish` reads authz records instead of filesystem markers. Deprecate `.publish-approved` with a migration path.

**Reason:** unify requires coordinated changes to `ic publish` code and currently-working marker semantics. Not worth blocking v1 ergonomics on it. Unify when the system is already running and the user trusts it.

### Axis 2 — Scope (global vs per-project)

**Policy file: global default + per-project override.** Layering follows git's model:

1. `~/.clavain/policy.yaml` — global default
2. `<project>/.clavain/policy.yaml` — override-or-inherit per-key
3. `CLAVAIN_POLICY_FILE` env var — one-off for a session

**Audit log: per-project** in each `.clavain/intercore.db`. Projects own their history; cross-project queries are a `clavain-cli audit aggregate` operation that walks project DBs.

**Reason:** higher-stakes projects need stricter defaults. Cross-project ops need a policy fallback. Git's layering is familiar and proven.

### Axis 3 — Pull vs push (Option 2 vs Option 3 from above)

**v1 = pull.** Every gate calls `policy check` at op time. Stateless. No token lifecycle.

**v2 = push-on-top-of-pull.** Token layer with single-use semantics and delegation. Pull-model stays as the fallback; tokens are the primary authorization when present.

## v1 concrete spec (Option 2.5 minus signing)

### Schema — per-project `intercore.db`

```sql
CREATE TABLE authorizations (
  id             TEXT PRIMARY KEY,       -- ulid
  op_type        TEXT NOT NULL,
  target         TEXT NOT NULL,
  agent_id       TEXT NOT NULL           -- shape: "<type>:<fingerprint>" (falls back to session id pre-v1.5)
                 CHECK(length(trim(agent_id)) > 0),
  bead_id        TEXT,                   -- CLAVAIN_BEAD_ID at time of op
  mode           TEXT NOT NULL
                 CHECK(mode IN ('auto', 'confirmed', 'blocked', 'force_auto')),
  policy_match   TEXT,                   -- rule name (NULL if manually confirmed)
  policy_hash    TEXT,                   -- hash of merged effective policy at check time (TOCTOU pin)
  vetted_sha     TEXT,                   -- first-class; for multi-repo beads see vetting blob
  vetting        TEXT                    -- JSON: {tests_passed, verified_with, shas:{repo→sha}, vetted_at}
                 CHECK(vetting IS NULL OR json_valid(vetting)),
  cross_project_id TEXT,                 -- NULL unless op spans repos
  created_at     INTEGER NOT NULL
);

CREATE INDEX authz_by_bead  ON authorizations(bead_id,  created_at DESC);
CREATE INDEX authz_by_op    ON authorizations(op_type,  created_at DESC);
CREATE INDEX authz_by_agent ON authorizations(agent_id, created_at DESC);
```

**Post-review additions vs original draft:** `agent_id` CHECK + stable-identity shape (resolves Q5), `mode` CHECK incl. distinct `force_auto` (resolves Q8), `policy_hash` (closes check→record TOCTOU), `vetted_sha` first-class (resolves Q6), `vetting` JSON validity CHECK, `cross_project_id` first-class, `authz_by_agent` index for `policy audit --agent=…`.

### Policy file shape

```yaml
version: 1
rules:
  - op: bead-close
    mode: auto
    requires:
      vetted_within_minutes: 60
      tests_passed: true
      sprint_or_work_flow: true

  - op: git-push-main
    mode: auto
    requires:
      committed_by_this_session: true

  - op: ic-publish-patch
    mode: auto
    requires:
      vetted_within_minutes: 60
      tests_passed: true

  - op: bd-push-dolt
    mode: auto
    requires:
      sprint_or_work_flow: true

  - op: "*"        # catchall
    mode: confirm
```

**Inheritance (resolved post-review):** per-key merge on `requires`. Numeric thresholds → `min()`. Boolean flags → `AND`. Per-project cannot drop a boolean requirement without an explicit `allow_override: true` on that key in the global rule. `op: "*"` catchall is a **non-removable global floor** — per-project files cannot delete it. Loosening is only possible via `mode: force_auto` which is a distinct audit class (separate `mode` value, WARNING log line, flagged by `policy audit`) — not a silent knob. Spec must ship with ≥5 worked examples in `docs/canon/policy-merge.md`.

### Vetting signal — where it comes from

**⚠ Precondition: this write path does not exist yet and must be added before v1 policy rules are evaluable.** Without the vetting writes, `vetted_within_minutes`, `tests_passed`, and `sprint_or_work_flow` conditions have no data and either always-block or default-allow — neither is correct.

Extend `/clavain:work` Phase 3 (Quality Check) and `/clavain:sprint` Steps 6-7 to write:

```bash
bd set-state "$CLAVAIN_BEAD_ID" vetted_at="$(date +%s)"
bd set-state "$CLAVAIN_BEAD_ID" tests_passed=true
bd set-state "$CLAVAIN_BEAD_ID" vetted_with="tests:26/26,measure:664ms"
bd set-state "$CLAVAIN_BEAD_ID" vetted_sha="$(git rev-parse HEAD)"
# For multi-repo beads (cross_project_id != NULL):
bd set-state "$CLAVAIN_BEAD_ID" vetted_shas='{"path/to/repo":"abc123...","other/repo":"def456..."}'
```

Policy gate reads those states at op time. SHA check must re-verify at op time, not just at `policy check` time (close the edit-between-check-and-op window).

### CLI surface

**⚠ Namespace collision to resolve:** The existing `clavain-cli policy-check` / `policy-show` commands in `cmd/clavain-cli/policy.go` govern scenario holdout access (return `{allowed: bool}` JSON, always exit 0). They share the `policy` prefix with this design's gate commands. Rename the existing scenario commands to `scenario-policy-check` / `scenario-policy-show` (keep deprecation aliases), then claim `policy` as the authz subcommand namespace.

```
clavain-cli policy check <op> [--target=<x>] [--bead=<id>]
    → exit 0 if auto, 1 if confirm needed, 2 if blocked, 3 if policy error
    → emits JSON {policy_match, reason, policy_hash, schema: 1} to stdout

clavain-cli policy record --op=<x> --target=<y> --mode=<m> --bead=<id> \
                          [--policy-hash=<h>] [--cross-project-id=<id>]
    → writes authorizations row; exits non-zero on constraint failure

clavain-cli policy explain <op> [--target=<x>] [--bead=<id>]
    → human-readable reasoning

clavain-cli policy audit [--since=1d] [--op=<type>] [--agent=<id>] [--verify]
    → recent records, JSON or table. --verify walks signatures (v1.5+)
    → --verify flags cross_project_id groups with missing per-project rows

clavain-cli policy list                  # effective merged policy
clavain-cli policy lint                  # validate yaml, check invariants:
                                         #   - "*" catchall present
                                         #   - no project drops global boolean requires without allow_override
                                         #   - all registered ops in .clavain/gates/ have rules
```

**Dropped vs original draft:** `policy set` (session-scoped override). Redundant with `CLAVAIN_POLICY_FILE` env var; one more ephemeral override source adds complexity without benefit.

### Gate registry

`.clavain/gates/` directory. Each wrapper drops a one-line registration at install time (`bead-close.gate`, `git-push-main.gate`, etc.). `policy lint` asserts that every registered gate has a corresponding rule in the effective policy; `policy audit --verify` can assert every gate-wrapped op left a record. Lighter than a runtime registry; makes coverage testable.

### Gate wrapper pattern

Each gate op gets a thin wrapper that calls `policy check` before executing. Examples:

```bash
# bd close wrapper (or bd itself, if upstream accepts the PR)
if clavain-cli policy check bead-close --target="$id" --bead="$id" ; then
    mode="auto"
else
    if [[ -t 0 ]]; then confirm_interactive; mode="confirmed"
    else echo "policy: bead-close requires confirmation; no tty" >&2; exit 1; fi
fi
bd close "$id" --reason="$reason"
clavain-cli policy record --op=bead-close --target="$id" --mode="$mode" --bead="$id"
```

For agents: the agent checks `policy check` first; if mode=auto, proceeds and announces. If mode=confirm, stops and asks.

## v1.5 — signed audit records

Add a project-scoped signing key. **Trust boundary decision (resolved post-review):** key must NOT live in `intercore.db` — circular trust (the artifact being signed hosts its own key). Key lives at `.clavain/keys/authz-project.key`, mode 0400.

**Separation of duties:** the gate process writes plaintext `authorizations` rows; a separate `clavain-cli authz-signer` process (optionally a systemd/launchd job, or an on-demand call at op close) reads unsigned rows and signs. This prevents the "agent that writes records can also forge records at write time" attack. The weaker alternative is to document v1.5 as **tamper-evident-post-write**, not **tamper-proof** — decide and document explicitly.

**Signature payload spec:**
- `sig_version INTEGER NOT NULL DEFAULT 1` column from day one (so v2 schema additions don't break verification).
- Signed field set (v1): canonical concatenation of `id|op_type|target|agent_id|bead_id|mode|policy_match|policy_hash|vetted_sha|vetting|cross_project_id|created_at`, NULLs as empty string, LF-delimited, signed with Ed25519.
- `signature BLOB NOT NULL` column.

**Key lifecycle:**
- Rotation: manual (`clavain-cli authz rotate-key`), old records keep old-key verification via `sig_version`.
- Breach: new key + `clavain-cli authz quarantine --before-key=<fingerprint>` flags all pre-breach records as "pre-breach vintage" during audit.

**v1 → v1.5 migration:** pre-v1.5 records have NULL signature. A synthetic signed metadata row (`op_type='migration.signing-enabled'`) marks the changeover timestamp; records before it are audited as "pre-signing vintage" (trusted advisory, not cryptographically verified). This prevents ambiguity about whether a NULL signature = migration-era or = tampering.

**Also in v1.5:** unify `.publish-approved` by modifying `RequiresApproval()` in `core/intercore/internal/publish/approval.go` to consult `authorizations` records. Marker file stays as fallback during a deprecation window (v1.5 → v2). See Q3 disposition.

**No tokens yet**, no single-use, no delegation. Just "what happened was provably what happened, by this key."

## v2 — tokens + delegation

Adds a `authz_tokens` table:

```sql
CREATE TABLE authz_tokens (
  id            TEXT PRIMARY KEY,       -- ulid
  op_type       TEXT NOT NULL,
  target        TEXT NOT NULL,
  agent_id      TEXT NOT NULL,          -- who may present this
  bead_id       TEXT,
  delegate_to   TEXT,                   -- NULL or a child agent id
  expires_at    INTEGER NOT NULL,
  consumed_at   INTEGER,                -- NULL until used
  issued_by     TEXT NOT NULL,          -- agent id or "user"
  parent_token  TEXT REFERENCES authz_tokens(id) ON DELETE RESTRICT,
  root_token    TEXT,                   -- first ancestor (denormalized for O(1) revoke cascade)
  depth         INTEGER NOT NULL DEFAULT 0 CHECK (depth <= 3),
  sig_version   INTEGER NOT NULL DEFAULT 1,
  signature     BLOB NOT NULL,
  created_at    INTEGER NOT NULL
);

CREATE INDEX tokens_by_root ON authz_tokens(root_token, consumed_at);
```

**Delegation semantics (resolved post-review — Q1):** linear chain, max depth 3. `root_token` denormalized so revocation of the root cascades in one UPDATE. DAG semantics deferred until evidence demands them (schema is DAG-ready via `root_token`, runtime is chain-only).

**Proof-of-possession on delegate:** `authz delegate --from=<token>` requires the caller's `agent_id` to match the parent token's `agent_id`. Without this check, any agent that knows a token ID can impersonate its scope. This is a v2 ship-blocker.

**Atomic consume (closes race + expiry gaps):**
```sql
UPDATE authz_tokens
   SET consumed_at = ?
 WHERE consumed_at IS NULL
   AND expires_at > ?       -- unix now; rejects expired atomically
   AND id = ?;
```
`clavain-cli authz consume` must exit 0 only when `rows_affected == 1`. Distinct exit codes: 2 = already-consumed, 3 = expired, 4 = not-found. Without this, expired tokens consume successfully and double-consume races silently win.

CLI:
- `clavain-cli authz issue --op=<x> --target=<y> --agent=<z> --ttl=1h`
- `clavain-cli authz delegate --from=<token> --to=<agent>` → issues child token (proof-of-possession gated)
- `clavain-cli authz consume --token=<id>` → atomic consume with expiry check
- `clavain-cli authz revoke --token=<id> [--cascade]` → cascade walks `root_token` index
- `clavain-cli authz revoke --issued-since=<ts>` → bulk revoke before consumption
- Gates accept `--authz <token>` in addition to policy match

**Delegation chains** let Claude issue a token to codex for a specific sub-op, codex consumes it, audit records the full chain via `root_token` + `parent_token`. Revocation of Claude's root token invalidates all descendants before their consume lands.

## Open questions — resolved post-review (2026-04-19)

Full per-agent reasoning in `docs/research/flux-drive/2026-04-19-auto-proceed-authz-design-20260419T0239/SYNTHESIS.md`. Dispositions folded into the specs above; the question + resolution summary stays here for history.

1. **Q1 — DAG vs hop chain.** Linear chain, depth cap 3. Schema carries `root_token` + `depth` so DAG migration is cheap if/when evidence demands it. Runtime is chain-only.
2. **Q2 — Policy inheritance precedence.** Per-key merge: numeric → `min()`, boolean → `AND`. `op:"*"` catchall is non-removable global floor. Loosening only via `mode: force_auto` (distinct audit class). Ship ≥5 worked examples in `docs/canon/policy-merge.md`.
3. **Q3 — `.publish-approved` migration.** v1: additive guard (gate alongside marker, no bridge). v1.5: unify via `RequiresApproval()` reading `authorizations`. Marker deprecation in v2. Not a permanent parallel system.
4. **Q4 — Cross-project ops.** Write to all touched projects with shared `cross_project_id`. **Consistency model:** strict-all-or-nothing for `ic-publish-patch`; best-effort + `policy audit --verify` surfacing gaps for non-publish ops. Normative before write-plan.
5. **Q5 — Agent identity.** v1 column accepts `<agent-type>:<fingerprint>` shape from day one, falls back to session ID pre-v1.5. Single-host = single-trust-domain documented explicitly (per-type keys on shared host provide false isolation).
6. **Q6 — Vetting staleness.** First-class `vetted_sha` column from v1. Multi-repo via `{"shas": {repo: sha}}` in `vetting` blob. Re-verify SHA at op time, not only at `check` time.
7. **Q7 — Non-tty fallback.** `mode: block` default, configurable per-rule — but the `op:"*"` global floor is non-removable. Per-project cannot weaken below global non-tty floor.
8. **Q8 — Stricter-wins vs force_auto.** Stricter-wins is the per-key merge mechanic (Q2). `force_auto` is a distinct `mode` value (not a knob) with WARNING log + separate audit class. No silent overrides.

## P0 items done before write-plan

See SYNTHESIS.md §P0 Combined Ranking. Summary:

1. Add vetting-signal write path to `/clavain:work` Phase 3 + `/clavain:sprint` Steps 6-7 (precondition — without it, v1 policy is unevaluable).
2. Resolve v1.5 signing trust boundary (separate writer/signer OR document weaker "tamper-evident-post-write" claim).
3. Lock cross-project consistency model (strict for publish, best-effort elsewhere) as normative.
4. Rename existing scenario `policy-check` / `policy-show` → `scenario-policy-*`; claim `policy` namespace for authz.
5. v2 atomic consume with `expires_at` in WHERE + non-zero exit on 0 rows-affected.
6. v2 `authz delegate` proof-of-possession check (caller's `agent_id` == parent's `agent_id`).

## Threat model recap (what this prevents, what it doesn't)

| Threat | Addressed by |
|---|---|
| Buggy agent claims vetted without vetting | `requires` conditions (tests_passed, vetted_within_minutes, vetted_sha) |
| User regret after auto-proceed | Audit log + `policy explain` + ability to tighten rules forward |
| Compromised agent rewrites audit | v1.5 signed records |
| Cross-agent delegation ambiguity | v2 token chain |
| Authority held by a departed agent | v2 token TTL + revocation |
| Out-of-band attacker (shell on host) | **Not addressed.** Anyone with write access to `intercore.db` can forge records. Signatures defeat retroactive edits but not initial forging. This is fleet-internal trust; out-of-band attackers are a host-security problem, not a policy-framework problem. |
| **Write-time forgery by gate process itself** (post-review addition) | Mitigated in v1.5 via separation of duties (gate writes plaintext, separate auditor signs on flush). If separation is not shipped, v1.5's claim weakens to **tamper-evident-post-write**, not tamper-proof. Pick one and document. |
| **`parent_token` impersonation in delegation** (post-review addition) | v2 `authz delegate` requires proof-of-possession: caller's `agent_id` must match parent token's `agent_id`. Without this check, any agent that knows a token ID can delegate as if they held it. Ship-blocker for v2. |
| **Clock skew across agents** (post-review addition) | `vetted_within_minutes` and `expires_at` both depend on wall clock. Policy engine accepts ±5 min tolerance documented explicitly. Containerized agents with drifted clocks are the realistic scenario. |
| **Audit-log unbounded growth** (post-review addition) | Multi-agent flows can write hundreds of records per session. v1 must define retention/compaction strategy (e.g., monthly rollup to summary rows, raw records retained 90 days) or the audit DB becomes unwieldy. |

## Not in scope (v1 through v3)

- **Multi-user**. arouth1 is the sole principal. If Sylveste grows past that, the framework will need per-user identity, but today everything else — beads, memory, plugins — assumes one user.
- **Cross-host federation**. One dev machine, one deploy machine (zklw). If agents run on multiple hosts with shared state, we'd need remote authz protocol. Not today.
- **Production deploy gates**. Nothing in this framework stops `kubectl apply` or any non-Clavain tool. If production ops need gating, add hooks into deploy tooling separately.

## References

- `docs/research/mcp-cold-start-breakdown-2026-04-18.md` — context for the sprint/work flow that surfaced this need
- `docs/solutions/integration-issues/graceful-mcp-launcher-external-deps-interflux-20260224.md` — the `.publish-approved`-adjacent pattern
- Memory: `feedback_auto_proceed_vetted_flow.md` — session-scoped version of the same idea
- Memory: `user_adhd_many_projects.md` — why infrastructure beats memory for this user
