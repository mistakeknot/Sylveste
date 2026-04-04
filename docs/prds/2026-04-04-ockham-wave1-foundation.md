---
artifact_type: prd
bead: sylveste-8em
stage: design
revision: 2
review: docs/research/flux-drive/ockham-wave1-foundation/synthesis.md
---

# PRD: Ockham Wave 1 — Foundation

## Problem

The principal is the dispatch bottleneck. The backlog is prioritized, the toolchain exists, but every work assignment requires a human to say "go." Ockham removes this bottleneck by translating strategic intent into dispatch weights that Clavain's existing machinery consumes.

## Solution

Build the Ockham CLI and Go packages for Wave 1: intent directives, weight scoring, dispatch wiring, temporal signal evaluation, pleasure signals, and the autonomy ratchet. The factory can then self-dispatch from a prioritized backlog shaped by the principal's theme budgets.

## Prerequisites (from PRD review)

These interface gaps must be resolved before or during implementation:

1. **`ic state list` has no value output.** `ic state list <key>` returns scope_ids only. F3 bulk pre-fetch requires either: (a) iterate scope_ids + `ic state get` per bead, or (b) add `ic state list-values <key> --json` to intercore. Decision: (a) for Wave 1 (known O(N) cost, N≈50 beads), (b) as a follow-up optimization.
2. **Lane stored as label, not top-level field.** `bd list --json` has no `lane` field. Lane is in the `labels` array as `lane:<name>`, visible via `bd show <id> --json`. F2 must use per-bead `bd show` or parse labels from list output.
3. **`agent_reliability(agent, domain)` does not exist.** Interspect's calibration outputs per-agent hit rates in `.clavain/interspect/confidence.json` without a domain dimension. Wave 1 F6 cold-start uses the existing per-agent confidence (domain=`*` wildcard). Domain-scoped reliability is a Wave 3 prerequisite.
4. **Dispatch token contract.** Clavain must mint a dispatch token at claim time, written to a path the agent cannot modify (e.g., `.clavain/dispatch-tokens/<session_id>.json`). Ockham reads this token for INV-1 enforcement. Token format and minting logic are F0 prerequisites (tracked as a separate sub-task).
5. **Interspect halt record.** `_interspect_insert_halt_record()` and `_interspect_get_halt_record()` must be added to `lib-interspect.sh` with hook_id `interspect-reaction` (or new `interspect-halt`). Required by F7 double-sentinel.

## Features

### F1: Intent CLI + YAML schema

**What:** `ockham intent` command that reads/writes `~/.config/ockham/intent.yaml` with theme budgets, priorities, and constraints.

**Acceptance criteria:**
- [ ] `ockham intent --theme auth --budget 0.4 --priority high` creates/updates intent.yaml
- [ ] `ockham intent show` displays current intent as formatted table
- [ ] `ockham intent validate` checks: budgets sum to 1.0, no budget < 0 or > 1.0, freeze/focus entries match declared themes (misspelled → error, not silent no-op)
- [ ] Invalid YAML produces CLI error, factory continues with last-known-good (atomic replacement)
- [ ] Missing/corrupt intent.yaml falls back to hardcoded default (all themes 1/N, priority normal)
- [ ] `ockham intent --freeze auth` calls `ic lane update auth --metadata='{"paused":true}'` (uses existing lane-pause mechanism, NOT offset manipulation)
- [ ] Priority maps to offset magnitude: high=+6, normal=0, low=-3 (asymmetric — low is half-step, not full)
- [ ] `ockham intent` returns error when halt sentinel is active (INV-8: policy immutability during halt)

### F2: Scoring package + governor assembly

**What:** Go packages `internal/intent`, `internal/scoring`, and `internal/governor` that compute per-bead weight offsets from intent directives.

**Acceptance criteria:**
- [ ] `internal/intent` reads intent.yaml, produces `IntentVector` (theme→budget+priority, where priority encodes: high=+6, normal=0, low=-3)
- [ ] `internal/scoring` receives `IntentVector` + `AuthorityState` + `AnomalyState`, outputs `WeightVector` (bead_id→offset)
- [ ] `internal/governor` assembles stores, calls `Evaluate(ctx, stores) → WeightVector`
- [ ] `governor.Evaluate()` checks halt sentinel FIRST — if active, returns empty WeightVector (INV-8 at package level, not just CLI)
- [ ] Scoring clamps all offsets to [-6, +6] (half the 12-point inter-tier gap, safe even with +5 perturbation)
- [ ] Bead-to-theme mapping: read lane from bead labels via `bd show <id> --json` (lane is NOT a top-level bd list field — it's a `lane:<name>` label). No lane → `open` theme
- [ ] `AuthorityState` and `AnomalyState` are stub structs in Wave 1 (neutral: offset=0, no constraints)
- [ ] Dependency direction enforced: scoring imports nothing; governor imports all four
- [ ] Rename `internal/dispatch/` → `internal/scoring/`, update AGENTS.md
- [ ] `ockham dispatch advise --json` outputs current weight vector (belongs in F2, not F3 — requires scoring package)
- [ ] `go test ./...` passes with ≥80% coverage on scoring logic

### F3: lib-dispatch.sh offset wiring

**What:** Wire Ockham's weight offsets into Clavain's dispatch scoring.

**Acceptance criteria:**
- [ ] lib-dispatch.sh reads offsets: iterate `ic state list "ockham_offset"` scope_ids, then `ic state get "ockham_offset" <id>` per bead (no --json bulk mode available — see Prerequisites #1)
- [ ] Evaluation order in `dispatch_rescore()`: (1) Lane-pause check (existing) — frozen theme → `continue` (skip bead entirely, do NOT set score=0 which floor guard would raise back to 1); (2) apply ockham_offset (clamped [-6, +6]); (3) perturbation; (4) floor guard
- [ ] NOTE: Step 1 uses the EXISTING lane-pause check already at lib-dispatch.sh line 195. No new CONSTRAIN gate is needed in Wave 1 — Tier 2 CONSTRAIN is a Wave 2 non-goal. Ockham's freeze command delegates to `ic lane update --metadata='{"paused":true}'`.
- [ ] Offsets clamped to [-6, +6] at read time (defense in depth — Ockham clamps at write, dispatch clamps at read)
- [ ] Logging: each scored bead logs `raw_score`, `ockham_offset`, `final_score` to dispatch log
- [ ] Missing offset → 0 (no effect, fail-open)
- [ ] **Negative test:** A bead in a frozen theme with `ockham_offset=+6` is still ineligible for dispatch (lane-pause takes precedence)

### F4: `ockham check` + SessionStart hook

**What:** CLI command that evaluates signals, runs re-confirmation timers, and persists temporal state. Wired into Clavain's SessionStart hook with a TTL sentinel.

**Acceptance criteria:**
- [ ] `ockham check` reads signals.db, evaluates all active signals, writes updated state
- [ ] `~/.config/ockham/signals.db` (SQLite) stores: signal timestamps, confirmation window state, ratchet timers, authority snapshots, schema version
- [ ] **signals.db recovery:** On open failure (corrupt WAL, missing file), `ockham check` recreates the DB from scratch with default state and logs a warning. Cold-start inference re-runs. This is fail-safe, not fail-open — the system recovers to a known conservative state (all shadow), not a permissive one.
- [ ] Authority snapshot persisted to signals.db after each successful interspect read (not in-memory only)
- [ ] 30-day autonomous re-confirmation triggers on `ockham check` (staggered by promotion timestamp, not synchronized)
- [ ] **TTL sentinel:** SessionStart hook checks `~/.config/ockham/.check-ttl` mtime. If < 5 minutes old, skip. Otherwise run `ockham check` and touch the sentinel. Pattern matches existing `bd doctor` TTL.
- [ ] SessionStart hook: `[[ -f ~/.config/ockham/.check-ttl ]] && [[ $(( $(date +%s) - $(stat -c %Y ~/.config/ockham/.check-ttl) )) -lt 300 ]] && exit 0; ockham check 2>/dev/null; touch ~/.config/ockham/.check-ttl`
- [ ] `ockham check --dry-run` reports what would change without writing
- [ ] `ockham check` also reconstructs factory-paused.json from interspect halt record if file deleted but record exists (double-sentinel reconstruction — source is interspect, NOT signals.db)

### F5: Tier 1 INFORM signals + pleasure signals

**What:** Weight-drift detection and three pleasure signals that feed the autonomy ratchet.

**Acceptance criteria:**
- [ ] Weight-drift: compares actual cycle time + gate pass rate vs predicted baseline per theme
- [ ] Cycle time computed from beads (`claimed_at`/`closed_at` per lane label via `bd show`), NOT from interstat (interstat has no per-lane mode)
- [ ] Gate pass rates from interspect evidence (existing `review_phase_outcome` events)
- [ ] Cost trend from interstat `cost-query.sh baseline` (project-wide, not per-theme — per-theme cost is a Wave 2 enhancement)
- [ ] Drift detection activates only after ≥10 completed beads per theme (prevents spurious signals from small samples)
- [ ] Drift threshold: >20% degradation over 7-day rolling window → emit `weight_drift` to interspect + Tier 1 INFORM
- [ ] Advisory actuation (Wave 1): underperforming theme priority reduced one step (high→normal, normal→low=-3), logged, principal can override via `ockham intent`
- [ ] **Feedback loop suppression (SYS-NEW-01):** Suppress weight_drift signals for domains currently undergoing ratchet demotion. Suppression lasts one confirmation window (1h) after demotion completes. This prevents the weight-drift + ratchet-demotion compounding spiral.
- [ ] Pleasure signals computed on `ockham check`: first_attempt_pass_rate, cycle_time_p50_trend (14-day rolling), cost_per_landed_change_trend (14-day rolling)
- [ ] Pleasure signal values written to signals.db for ratchet consumption
- [ ] `ockham health --json` includes pleasure signal values and trend directions (F7 is superset — F5 tests the computation, F7 tests the output format)

### F6: Autonomy ratchet state machine

**What:** Per-domain autonomy levels (shadow/supervised/autonomous) with evidence-based promotion and fast demotion.

**Acceptance criteria:**
- [ ] Ratchet state stored per (agent, domain) in signals.db
- [ ] Transition table enforced: shadow→supervised (hit_rate≥0.80, sessions≥10, confidence≥0.7), supervised→autonomous (hit_rate≥0.90, sessions≥25, confidence≥0.85)
- [ ] Invariant: promotion moves one step only (no skipping shadow→autonomous)
- [ ] Demotion: intent-freeze drops one level; BYPASS drops to shadow from any level (Tier 2 CONSTRAIN is Wave 2)
- [ ] **Fresh evidence requirement applies to ALL demotions** (not just BYPASS): after any demotion event, re-promotion requires ≥10 sessions timestamped after the demotion event. Stale pre-demotion evidence cannot re-promote.
- [ ] Cold start: read `.clavain/interspect/confidence.json` for per-agent hit rates (domain=`*` wildcard in Wave 1). Meets supervised guard → start supervised. Meets autonomous → start supervised (conservative). No evidence → shadow.
- [ ] 30-day re-confirmation for autonomous domains (staggered by promotion timestamp, not synchronized — prevents multi-domain demotion cascade)
- [ ] Cross-domain beads: authority resolves to min(tier_per_domain). **Additionally:** if any touched domain is frozen (lane paused), bead is ineligible regardless of other domains' tiers.
- [ ] `ockham authority show --json` displays current ratchet state per domain
- [ ] Ratchet decisions logged through intercept (`intercept decide ratchet-promotion` — requires gate definition in `intercept/gates/ratchet-promotion.yaml`)
- [ ] **"Reduced oversight" defined:** `autonomous` tier AND no principal session active in the last 1h (checked via CASS `cass timeline --since 1h --json` looking for principal sessions). This makes the Tier 3 qualifier testable.

### F7: `ockham health` + Tier 3 double-sentinel

**What:** Health dashboard and the factory halt/resume mechanism with tamper-resistant sentinels.

**Acceptance criteria:**
- [ ] `ockham health` outputs JSON: pain signals (quarantined beads, circuit breaker trips, stale claims), pleasure signals (pass rate, cycle time, cost trends), ratchet state, overall status
- [ ] `ockham health --format=table` outputs human-readable dashboard
- [ ] Tier 3 BYPASS: when `distinct_root_causes >= 2` AND operating at reduced oversight (see F6 definition), write factory-paused.json AND interspect halt record via `_interspect_insert_halt_record()` (double-sentinel)
- [ ] Write-before-notify ordering: file sentinel written before any notification
- [ ] `ockham check` reconstructs factory-paused.json from interspect halt record (source: interspect, NOT signals.db — interspect is the agent-unwritable sentinel)
- [ ] `ockham resume` clears both sentinels, checks Tier 2 state, resets domains to supervised for one confirmation window
- [ ] **Resume atomicity:** `ockham resume` writes a `resume_in_progress` flag to signals.db before starting the domain reset loop. If the process is killed mid-loop, the next `ockham check` detects the incomplete resume and completes it. No domain is left at autonomous without the post-resume confirmation window.
- [ ] `ockham resume --constrained` allows intent changes while keeping factory paused (fix config before re-enabling dispatch)
- [ ] Policy immutability: when halt sentinel active, `governor.Evaluate()` returns empty WeightVector AND CLI commands (except `resume`, `health`, `check`) return error. Both layers enforce INV-8.

## Non-goals

- **Tier 2 CONSTRAIN** — requires anomaly package with multi-window confirmation (Wave 2). Wave 1 freeze uses the existing lane-pause mechanism only.
- **Authority package** — requires evidence accumulation from Wave 1 operation (Wave 3)
- **CUJ health scoring** — requires CUJ infrastructure not yet built (Wave 2)
- **Semantic quality gates** — LLM-as-judge confidence scoring (Wave 3)
- **Rework disposition taxonomy** — requires authority enforcement (Wave 3)
- **Meadowsyn integration** — Ockham writes JSON files; Meadowsyn reads them when it exists
- **Skaffen governance** — outside scope until Wave 4 re-evaluation
- **Intercept distillation** — Wave 1 logs through intercept; actual model training is Wave 2
- **Not a quality arbiter** — quality gates are Clavain's domain; Ockham reads their results but never evaluates code
- **Not an audit log** — interspect owns the evidence trail; Ockham writes to interspect, never maintains its own audit store
- **Per-theme cost tracking** — interstat has no per-lane mode; Wave 1 uses project-wide cost trend only

## Dependencies

| Dependency | Status | Required by | Interface verified |
|-----------|--------|-------------|-------------------|
| beads (`bd` CLI) | Available | F1 (bead-to-theme via lane label), F5 (cycle time via claimed_at/closed_at) | Yes — lane is in labels, not top-level field |
| interspect (`lib-interspect.sh`) | Available, **needs extension** | F5 (gate pass rates), F7 (halt record insert/get) | Partial — halt record functions must be added |
| interstat (`cost-query.sh`) | Available | F5 (cost trend, project-wide only) | Yes — no per-lane mode |
| intercept (`intercept decide`) | Available, **needs gate definition** | F6 (ratchet-promotion gate YAML) | Yes — gate needs to be created |
| intercore (`ic state`) | Available | F3 (offset read/write) | Partial — `ic state list` returns scope_ids only, not values |
| CASS (`cass timeline`) | Available | F6 ("reduced oversight" check) | Yes |
| Clavain SessionStart hook | Requires wiring | F4 | N/A — new hook |
| lib-dispatch.sh | Requires modification | F3 | Yes — lane-pause at line 195, score_bead tier gaps verified |

## Open Questions

1. **Multi-factory:** Single-factory scope for Wave 1. Defer federated model to post-Wave 1.
2. **Evidence gaming (S-02):** Use gate results at review time as canonical evidence source? Resolve during Wave 3 authority package design.
