---
date: 2026-04-19
session: 44ed0f82
bead: sylveste-qdqr
input: docs/brainstorms/2026-04-19-auto-proceed-authz-design.md
agents: fd-safety, fd-decisions, fd-systems, fd-architecture, fd-correctness
---

# Synthesis — Auto-proceed authz framework review

## Verdict consensus

| Agent | Verdict |
|---|---|
| fd-safety | SHIP-WITH-CHANGES |
| fd-decisions | SHIP-WITH-CHANGES |
| fd-systems | SHIP-WITH-CHANGES |
| fd-architecture | SHIP-WITH-CHANGES |
| fd-correctness | SHIP-WITH-CHANGES |

**Unanimous: SHIP-WITH-CHANGES.** No agent recommends BLOCK. v1 (unsigned pull policy) is safe to ship as-is or with minor schema hardening. v1.5 and v2 carry the load-bearing concerns.

## Cross-cutting convergences (≥3 agents)

### C1. Vetted SHA must be first-class, not buried in `vetting` JSON
**Agents:** fd-safety (P2), fd-architecture (P2), fd-correctness (P1), fd-systems (P1), fd-decisions (P2 via Q6).
**Convergence:** Q6 is misframed as a v1.5+ concern. The `vetted_within_minutes: 60` rule has no value without a SHA bind — code can be edited inside the freshness window and the gate still auto-proceeds. Promote `vetted_sha` to a column in v1; add `vetted_sha_matches_head: true` as a `requires` key. For multi-repo beads, store `{"shas": {"<repo>": "<sha>"}}` and verify each.

### C2. The vetting-signal write path does not exist yet
**Agents:** fd-architecture (P0), fd-decisions (implied via Q5 freshness), fd-systems (loop input is empty).
**Convergence:** `/clavain:work` Phase 3 and `/sprint` Steps 6-7 contain no `bd set-state vetted_at=…` writes today. Without them, `vetted_within_minutes`, `tests_passed`, and `sprint_or_work_flow` policy conditions can never evaluate to true. **The most important policy rules are unevaluable until the upstream commands are extended.** This is a precondition, not a follow-up.

### C3. Gate wrapper TOCTOU + missing wrapper coverage
**Agents:** fd-correctness (P1), fd-architecture (P1), fd-safety (implied).
**Convergence:** Two related risks: (a) policy can mutate between `check` and `record`, so the recorded `policy_match` becomes a lie even under v1.5 signing; (b) there is no registry that proves all irreversible ops are actually wrapped — convention silently bypasses. Fix: hash the merged effective policy at check time and pin it through to record; introduce `.clavain/gates/` registration directory with `policy lint` coverage check.

### C4. Cross-project ops have no defined consistency model (Q4)
**Agents:** fd-correctness (P0), fd-systems (P2), fd-safety (P1 improvement), fd-decisions (deferral risk).
**Convergence:** "One record per touched project, linked by `cross_project_id`" leaves partial-failure undefined. Three agents independently surfaced this. Pick one of: (a) all-or-nothing strict mode for `ic-publish-patch`; (b) primary-project summary record listing successes/failures; (c) explicit "audit gap ≠ authz gap" with `policy audit --verify` surfacing it. **Must be normative before write-plan.**

### C5. Policy inheritance + merge semantics are prose, not algorithm (Q2)
**Agents:** fd-decisions (P1), fd-architecture (P2), fd-correctness (P2), fd-systems (P3).
**Convergence:** "Tighten-only with explicit `replace`" is not implementable without a formal merge rule with worked examples. Specifically needed: per-key merge rule (numeric=min, boolean=AND), `force_auto`'s distinct mode value (not just a knob, an audit-visible record class), and rule order semantics (first-match vs all-match). The `op: "*"` catchall must be a **non-removable global floor**, not a policy convention.

### C6. Agent identity is self-reported through v1.5 (Q5)
**Agents:** fd-safety (P1), fd-decisions (P1), fd-architecture (P2).
**Convergence:** Until v1.5 ties signatures to per-agent keys, `agent_id` is advisory. Two ways to resolve:
- **fd-decisions:** ship stable identity (`<agent-type>:<key-fingerprint>`) in v1 to avoid v2 schema migration
- **fd-safety:** accept the advisory limitation explicitly in v1 docs and address only when signing layer lands

These are compatible if the v1 column accepts both shapes (session-id today, fingerprint when keys exist) and the schema enforces non-empty + format.

## Divergences worth flagging

### D1. v2 token DAG vs single-hop (Q1)
- **fd-safety:** linear chain with depth cap of 3 — auditable; open DAG isn't. Resolve before v2 begins.
- **fd-decisions:** properly scoped as v2 decision, can defer.
- **fd-architecture:** add `depth INTEGER` and `root_token TEXT` columns to support either; cap chosen later.
- **fd-systems:** semantics matter for revocation propagation and TTL inheritance; can't punt without picking defaults.

**Disposition:** add columns now (fd-architecture's compromise) but do not implement DAG semantics until use case proves needed.

### D2. .publish-approved migration timing (Q3)
- **fd-decisions:** decide *now* whether v1.5 unify is MUST-SHIP or v2 NICE-TO-HAVE — once parallel system reaches scale, calcification cost grows.
- **fd-safety:** parallel is fine in v1; signing landing in v1.5 is the natural unify trigger.
- **fd-architecture:** do not bridge in v1; gate `ic-publish-patch` through new authz **alongside** the marker (no shim shenanigans). Modify `RequiresApproval()` in v1.5.

**Disposition:** fd-architecture's "additive guard, not bridge" pattern is cleanest. Lock in v1.5 unification timing.

### D3. Audit log signing model (v1.5)
- **fd-safety P0:** signing process and gate write path cohabit the same DB and same key file → forgery at write time is undetectable. Either separate the writer (gate writes plaintext, auditor signs on flush) or reduce the v1.5 claim from "tamper-proof" to "tamper-evident-post-write".
- **fd-correctness P2:** signature payload field set must be enumerated; `sig_version INTEGER` from day one so v2 schema additions don't break verification.

**Disposition:** Both fixes are needed and orthogonal. fd-safety's separation-of-duties point is a v1.5 blocker; fd-correctness's `sig_version` is a 5-minute spec addition.

## P0 Combined Ranking (do before write-plan)

1. **[fd-architecture] Add vetting-signal write path** to `/clavain:work` Phase 3 and `/sprint` Steps 6-7. Without this, v1 policy rules are unevaluable. Two-line addition.
2. **[fd-safety + fd-correctness] Specify v1.5 signing trust boundary.** Either separate writer/signer process OR explicitly weaken the claim. Cohabitation = forgeable-at-write.
3. **[fd-correctness] Cross-project consistency model.** Pick (a)/(b)/(c) above and make normative.
4. **[fd-architecture] Resolve `policy` namespace collision** with the existing `policy-check` / `policy-show` scenario commands in `/os/Clavain/cmd/clavain-cli/policy.go`. Rename existing to `scenario-policy-check`, claim `policy` for authz.
5. **[fd-correctness] Token consume must check `expires_at` atomically** in WHERE clause + CLI must exit non-zero on 0 rows-affected. Without this, expired tokens consume successfully and double-consume races silently succeed.
6. **[fd-safety] `parent_token` proof-of-possession** before issuing child token in v2. Without this, any agent that knows a token ID can delegate as if they held it.

## P1 Disposition Summary

| Theme | Action | Owner |
|---|---|---|
| First-class `vetted_sha` column | Add to v1 schema | spec |
| Gate registry `.clavain/gates/` | Design before v1 | architecture |
| `mode` CHECK constraint | DDL fix | spec |
| `agent_id` non-empty + format check | DDL fix | spec |
| `parent_token` FOREIGN KEY + cascade revoke | Add to v2 spec | spec |
| `agent_id` index for `policy audit --agent` | DDL fix | spec |
| Stable agent identity in v1 (not v2) | Add `<type>:<fingerprint>` shape now | spec |
| Audit log retention/compaction | Add to v1 design | systems |
| Effectiveness telemetry (false-pos rate) | v1.5 addition | systems |
| Drop `policy set` session override | Use env var only | architecture |
| Policy hash pinned through check→record | Schema + CLI | correctness |
| Single-host identity reality | Document explicitly | safety |

## 8 Open Questions — Recommended Dispositions

| Q | Topic | Disposition |
|---|---|---|
| Q1 | Token DAG vs hop chain | Linear chain, depth cap 3, but add `root_token`+`depth` columns now to keep DAG migration cheap. Defer DAG until evidence demands it. |
| Q2 | Policy inheritance precedence | Tighten-only via per-key merge (numeric=min, boolean=AND). `op:"*"` catchall is global floor, project cannot drop. `force_auto` is a distinct `mode` value, not a knob — audit-visible. Spec needs 5+ worked examples. |
| Q3 | `.publish-approved` migration | Additive guard in v1 (gate alongside marker, no bridge). Unify in v1.5 by modifying `RequiresApproval()` to consult `authorizations` records. Deprecate marker in v2. |
| Q4 | Cross-project ops | Write to all touched projects with `cross_project_id`. **Pick consistency model**: strict-all-or-nothing for ic-publish-patch; best-effort + `policy audit --verify` for non-publish ops. Make normative. |
| Q5 | Agent identity | Use `<agent-type>:<fingerprint>` shape in v1 column; populate from session ID until keys exist. Single-host = single-trust-domain documented explicitly. |
| Q6 | Vetting staleness | First-class `vetted_sha` column from v1, multi-repo via `{"shas": {...}}`. `vetted_sha_matches_head: true` as `requires` key. Re-verify SHA at op time, not just check time. |
| Q7 | Non-tty fallback | `mode: block` default, configurable per-rule. Global `op: "*"` catchall must be non-removable floor. Per-project cannot weaken below global non-tty floor. |
| Q8 | Stricter-wins vs force_auto | Stricter-wins via per-key merge (mechanical). `force_auto` is distinct `mode` value with WARNING log + separate audit class — not a silent override. |

## Recommended write-plan decomposition

Suggested child beads under `sylveste-qdqr`:

1. **sylveste-qdqr.v1.spec** — Lock spec gaps before code: vetting write path, `vetted_sha` column, `policy` namespace rename, cross-project consistency model, schema CHECK constraints, gate registry design. (1-2 days, decisions only.)
2. **sylveste-qdqr.v1.schema** — `authorizations` table + indexes + constraints. (~0.5 day)
3. **sylveste-qdqr.v1.policy-engine** — yaml loader, merge algorithm, condition evaluator, exit-code contract. (~1 day)
4. **sylveste-qdqr.v1.cli** — `clavain-cli policy {check,explain,audit,list,lint,record}`. (~0.5 day)
5. **sylveste-qdqr.v1.gate-wrappers** — bd-close, git-push-main, bd-push-dolt, ic-publish-patch + `.clavain/gates/` registry. (~1 day)
6. **sylveste-qdqr.v1.vetting-writes** — extend `/clavain:work` and `/sprint` to set vetting state. (~0.5 day, but blocks v1 evaluability)
7. **sylveste-qdqr.v1.5.signing** — separate writer/signer trust boundary, `sig_version`, signed payload spec, key lifecycle. (~1.5 days)
8. **sylveste-qdqr.v2.tokens** — `authz_tokens` schema, atomic consume with expiry, `parent_token` FK + cascade, proof-of-possession on delegate. (~1 week)
9. **sylveste-qdqr.v1.5.publish-unify** — `RequiresApproval()` consults authz; deprecate marker. (~0.5 day)

Total v1: ~3.5 days. v1.5: ~2 days. v2: ~1 week. Matches the brainstorm's estimates.

## What this review didn't cover

- **fd-resilience** was on Stage 2 standby; skipped because phasing/migration was already triangulated by other agents. Re-run with `--mode=research` and resilience focus if antifragility-specific signal is wanted.
- **Cross-AI** (Oracle) was not in roster. For a second-opinion check on the 8 open questions, see `/interpeer:interpeer`.
- **Threat model boundary** was accepted as written (out-of-band attacker out of scope). If cross-host deployment lands, re-review.

<!-- flux-drive:complete -->
