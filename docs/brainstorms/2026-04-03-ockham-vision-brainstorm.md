---
artifact_type: brainstorm
bead: sylveste-8em
stage: discover
revision: 4
review: docs/research/flux-drive/ockham-vision-brainstorm/synthesis.md
---

# Ockham Vision — L2 Factory Governor

**Date:** 2026-04-04 (rev 4 — 8 fixes from round-2 re-review, 7 agents × 4 tracks × 2 rounds)
**Research:** [Algedonic signal design](../research/flux-research/ockham-algedonic-signal-design/synthesis.md), [Authority tiers](../research/flux-research/authority-tiers/synthesis.md), [Phase 1 self-dispatch](../research/flux-research/phase1-self-dispatch/synthesis.md), [AI factory brainstorm](2026-03-19-ai-factory-orchestration-brainstorm.md)

## What We're Building

A vision document for Ockham — the headless L2 factory governor that mediates between the principal's strategic intent and the factory's execution. Named after Ockham Saneer (Ada Palmer, *Terra Ignota*), who ran the Humanist transportation network by routing resources through competing hive interests without commanding any vehicle directly.

Ockham is the Cyberstride in Sylveste's Cybersyn architecture. It computes; Clavain, Zaka, and Alwe act.

## Why This Approach

### Policy engine, not orchestrator (Phase 1-3 constraint, re-evaluate at Phase 4)

Ockham never dispatches agents, never claims beads, never touches tmux sessions. It shapes what others do by producing three outputs: dispatch weight offsets, authority grants/revocations, and algedonic signals. This separation exists because:

1. **Clavain already dispatches.** lib-dispatch.sh has scoring, backpressure, circuit breakers. Replacing it creates a migration nightmare. Adding bounded offsets to its scores injects intent without disrupting existing machinery.
2. **Interspect already observes.** The evidence pipeline, canary monitoring, and calibration are battle-tested. Ockham reads interspect's outputs as facts and defines what they mean for governance.
3. **Single-responsibility compounds.** A policy engine that only computes weights is testable in isolation, auditable (every weight has a derivation chain), and replaceable (swap the policy without changing dispatch).

This is a **phased constraint**, not a permanent identity. At Phase 4 (post-Wave 3), re-evaluate whether Ockham should gain dispatch authority for mid-sprint corrections. The constraint forces clean interfaces now; relaxing it later is additive, not disruptive.

### Split evidence/policy ownership

Interspect owns evidence: hit rates, session counts, confidence bands, canary alerts. Ockham owns policy: what those numbers mean for autonomy levels, authority grants, and dispatch priority. The boundary is the fact/value distinction — interspect says what happened, Ockham says what it means.

Interface: `interspect exposes agent_reliability(agent, domain) -> {hit_rate, sessions, confidence, last_active}`. Ockham consumes this to make promotion/demotion decisions.

### CLI-first with persisted signal state

Intent arrives via `ockham intent --theme auth --budget 40%`, stored in `intent.yaml`. Meadowsyn reads and writes the same file when it exists. Day-1 path is a CLI that a principal can use from a terminal.

**Temporal model:** No daemon. Signal timestamps and confirmation windows are persisted to `~/.config/ockham/signals.db` (SQLite). Each CLI invocation reads current state, evaluates signals, writes updated state. The anomaly subsystem's multi-window confirmation works on stored timestamps, not in-memory timers.

## Key Decisions

### 1. Four subsystems (renamed: Scoring, not Dispatch)

| Subsystem | Input | Output | Wave | Allowed deps |
|-----------|-------|--------|------|-------------|
| **Intent** | Principal theme budgets, constraints | Per-bead weight offsets | Wave 1 | beads (read) |
| **Authority** | Interspect evidence, principal overrides | Domain grants, tier promotions/demotions | Wave 3 | interspect (read), intent (read) |
| **Anomaly** | Beads state, interspect, interstat, CASS | Tiered algedonic signals | Wave 2 | all (read), Alwe (read) |
| **Scoring** | Intent offsets + authority + anomaly state | Unified weight vector for lib-dispatch.sh | Wave 1 | intent, authority, anomaly (read) |

The "Scoring" package synthesizes the weight vector. It receives typed input structs (`IntentVector`, `AuthorityState`, `AnomalyState`) — it does not import the upstream packages directly. This prevents it from becoming a god-module.

**Orchestration:** `internal/governor` is the thin assembly layer. It imports all four packages, wires stores, and exposes a single entry point: `Evaluate(ctx, stores) → WeightVector`. The CLI commands delegate to `governor.Evaluate()`. This is the only package allowed to import all four subsystems.

Dependency direction: Intent → (no deps) | Authority → interspect | Anomaly → all read-only | Scoring → receives structs, imports nothing | **Governor → imports all four, assembles structs, calls Scoring**.

### 2. Bead-to-theme mapping via lane labels (resolved)

Beads already have lane assignments via `bd set-state lane=<name>`. Lanes ARE themes. The terminology collision is resolved:

- **Lane** = intercore kernel entity (the data model: `ic lane create`, `ic lane list`)
- **Theme** = Ockham's governance concept (the policy label: "auth", "performance", "open")
- **Mapping**: `theme = bead.lane`. If a bead has no lane, it falls into the `open` theme (default).

Ockham reads lane assignments from beads: `bd list --json | jq '.[] | {id, lane}'`. No new data model needed.

### 3. Dispatch integration via additive weight offsets (revised from multipliers)

Multiplicative weights cause priority inversion (C-02). Additive offsets bounded within half a priority tier gap preserve ordering while expressing intent preference.

```
final_score = raw_score + ockham_offset
```

Where `ockham_offset` is bounded to `[-6, +6]`. The actual inter-tier gap is 12 points (P0=60, P1=48, P2=36, P3=24 in `score_bead()`). With perturbation adding 0-5, the effective swing is -6 to +11 — which never crosses a full tier boundary. Intent nudges ties and close races but cannot cause a P3 bead to outrank a P1 bead.

Ockham writes offsets via `ic state set "ockham_offset" <bead_id>`. lib-dispatch.sh reads them in `dispatch_rescore()` with this evaluation order:
1. Check CONSTRAIN state — if bead's theme is frozen (lane paused), set score=0 and skip remaining steps
2. Apply `ockham_offset` (clamped to [-6, +6])
3. Apply perturbation (0-5)
4. Apply floor guard (score < 1 → 1)

Bulk pre-fetch: `ic state list "ockham_offset" --json` once per dispatch cycle, not per-bead.

**Logging:** lib-dispatch.sh records `raw_score`, `ockham_offset`, and `final_score` so calibration can reconstruct counterfactuals and attribute drift to intent vs organic scoring (D-06).

**Scheduled evaluation:** `ockham check` runs signal evaluation, re-confirmation timers, and weight-drift detection. Wired into Clavain's SessionStart hook so it fires on every agent session start. This is the no-daemon scheduler — the factory's own activity drives Ockham's temporal evaluation (OBR-02).

### 4. Intent YAML schema (resolved)

```yaml
# ~/.config/ockham/intent.yaml
version: 1
themes:
  auth:
    budget: 0.40        # fraction of dispatch capacity
    priority: high       # high|normal|low — maps to offset magnitude
    # high = +6, normal = 0, low = -3
  performance:
    budget: 0.30
    priority: normal
  open:
    budget: 0.30
    priority: normal     # "open" is the default for unlaned beads

constraints:
  freeze: []             # list of theme names — enforced via ic lane update --metadata="paused:true"
  focus: []              # list of theme names — all others get priority: low
  # freeze uses the existing lane-pause mechanism (NOT offset manipulation).
  # A frozen theme's beads are ineligible for dispatch at the lane level,
  # before offset arithmetic runs. This avoids the floor-guard conflict
  # (lib-dispatch.sh raises scores < 1 back to 1).
  # freeze and focus compose: freeze takes precedence over focus.
```

**Validation:** `ockham intent validate` checks: budgets sum to 1.0, no unknown theme names, no budget < 0 or > 1.0, freeze/focus entries must match a declared theme name (misspelled entries are errors, not silent no-ops). Invalid YAML → CLI errors, factory continues with last-known-good intent (file is only replaced atomically after validation).

**Fallback (R-01):** If intent.yaml is missing or corrupt, Ockham uses a hardcoded default: all themes budget 1/N, priority normal. This is the PHILOSOPHY.md stage-4 fallback.

### 5. Algedonic signals: tiered passive/active with bypass

Three response tiers (unchanged from v1, with de-escalation added):

**Tier 1 — INFORM (continuous weight adjustment).** Signal fires, dispatch offsets adjust. Examples: theme drift, cycle time degradation, cost overrun. Recovery is automatic when signal clears. Zero human involvement.

**Tier 2 — CONSTRAIN (freeze + notify).** Signal persists past multi-window confirmation (short 1h AND long 24h must both breach simultaneously). Freeze theme's lane, set autonomy_tier=supervised (not shadow — see ratchet), emit to Meadowsyn. Examples: 3+ quarantines in same domain, circuit breaker trip, stale claims. **In-flight beads:** agents mid-sprint in a frozen theme continue at supervised autonomy (complete current work, but no new claims). This prevents the freeze→failure→more-pain reinforcing loop (SYS-02).

**De-escalation (C-03):** Both windows must simultaneously drop below threshold, then a stability window (equal to the short window, default 1h) must pass with no re-fire before the tier drops. If the signal re-fires within the stability window, the window resets.

**Tier 3 — BYPASS (algedonic, reaches principal directly).** `distinct_root_causes >= 2` fire simultaneously while operating at reduced oversight (not just signal count — prevents cascade false triggers per C-05). **Double-sentinel:** write factory-paused.json AND record halt in interspect evidence (agent-unwritable path). Both must be present for halt to be recognized. An agent can delete factory-paused.json but cannot remove the interspect record — `ockham check` re-creates the file if the interspect halt record exists (OCKHAM-03). Write-before-notify ordering (ARCH). Recovery requires explicit `ockham resume` which clears both sentinels.

**Tier 3 restart sequence (R-04):**
1. Principal runs `ockham resume` (or deletes factory-paused.json)
2. Ockham checks all Tier 2 signals — if any still active, factory resumes in constrained mode (frozen themes stay frozen)
3. If all clear, factory resumes in normal mode
4. All domains reset to supervised for one confirmation window before restoring prior autonomy levels

Six qualifications (unchanged): signal qualification gate, root-cause deduplication by `distinct_root_causes` (not signal count), multi-window confirmation, explicit pleasure signals, observation separation (Alwe observes, Ockham acts), zero cost on healthy path.

### 6. Autonomy ratchet: explicit state machine (revised)

**States:** shadow → supervised → autonomous. **Per-domain, not per-agent.**

**Transition table (C-01):**

| From | To | Trigger | Guard |
|------|----|---------|-------|
| shadow | supervised | pleasure signals persist past confirmation | `hit_rate >= 0.80 AND sessions >= 10 AND confidence >= 0.7` |
| supervised | autonomous | pleasure signals persist past confirmation | `hit_rate >= 0.90 AND sessions >= 25 AND confidence >= 0.85` |
| autonomous | supervised | Tier 2 CONSTRAIN fires | automatic, immediate |
| supervised | shadow | Tier 2 CONSTRAIN fires while already supervised | automatic, immediate |
| any | shadow | Tier 3 BYPASS fires | automatic, immediate |
| shadow | supervised | Tier 2 clears + stability window | requires passing supervised promotion guard |

**Invariant:** `new_tier ∈ {current_tier - 1, current_tier + 1}` except emergency demotion to shadow (allowed from any tier). No state skipping on promotion. Recovery from CONSTRAIN always drops one level, never restores to prior tier directly.

**Fresh evidence requirement (OBR-04):** After a demotion event, re-promotion requires `sessions >= 10` of NEW evidence (timestamped after the demotion event). Stale pre-demotion evidence cannot re-promote — prevents snap-back within one stability window.

**Cold start (resolved, D-05/SYS-05/R-06):** Infer initial positions from existing interspect evidence. Run `agent_reliability(agent, domain)` for each known agent×domain pair. If evidence meets the supervised guard, start at supervised. If it meets autonomous, start at supervised anyway (conservative — promotion from supervised to autonomous happens in the first confirmation window if evidence holds). If no evidence, start at shadow. This prevents the activation regression (turning on Ockham shouldn't increase principal load).

**Cross-domain beads (ET-01/HADZA-01):** When a bead touches multiple domains (e.g., `interverse/**` + `core/**`), authority resolves to `min(tier_per_domain)` — the most restrictive domain governs. If any touched domain is frozen (CONSTRAIN), the bead is ineligible for dispatch regardless of other domains' status. This is the capability-ceiling model from the authority-tiers research applied at the bead level: a bead that crosses a shadow domain boundary must be executed under shadow rules. Ockham computes this during weight synthesis; lib-dispatch.sh receives the final weight without needing to understand domain resolution.

**Ratchet runaway prevention (SYS-01):** Autonomous domains require periodic re-confirmation. Every 30 days (configurable), autonomous domains are re-evaluated against the promotion guard. If evidence has degraded below threshold, the domain demotes to supervised. Re-confirmation windows are staggered by promotion timestamp (not synchronized) to prevent multi-domain demotion cascades at T=30 days. This is a balancing loop that prevents the all-autonomous steady state.

**Pleasure signals (minimum viable, SYS-07):** Ship alongside Wave 1 Tier 1 INFORM, not deferred to Wave 3.
- `first_attempt_pass_rate` — fraction of beads passing quality gates on first attempt
- `cycle_time_p50_trend` — improving (decreasing) over rolling 14-day window
- `cost_per_landed_change_trend` — stable or improving over rolling 14-day window

### 7. Safety invariants (extended, S-01/S-03/S-08)

Five original + three new:

1. **No self-promotion.** Enforced at the Ockham CLI boundary: `ockham authority promote` requires `--actor` flag validated against a Clavain-minted dispatch token (not `$CLAUDE_SESSION_ID`, which agents can spoof). The dispatch token is written by Clavain at claim time to a path the agent cannot modify. An agent calling `ockham` cannot forge the token. (S-01, OCKHAM-01)
2. **Delegation ceiling.** An agent cannot grant authority exceeding its own level.
3. **Action-time validation.** Authority checked at execution time. **Degradation contract (S-05/R-02):** if interspect is unavailable, action-time validation uses the last-known authority snapshot persisted to `signals.db` after each successful interspect read (R-02-b). Max staleness: 5 minutes. Beyond 5 minutes stale, fail-closed (deny).
4. **Audit completeness.** Every authority decision produces a durable receipt in interspect.
5. **Human halt supremacy.** Write-before-notify ordering. factory-paused.json is the sentinel, not the notification.
6. **Weight neutrality floor (S-08).** No bead's offset can go below `-6` (the clamp bound). Blocking a bead requires an explicit freeze constraint via lane-pause, not an organic weight. Prevents beads from being silently blackholed.
7. **Signal independence (S-08).** At least one Tier 3 trigger must be agent-unwritable. The interspect halt record is the agent-unwritable sentinel — even if the filesystem sentinel is deleted, `ockham check` reconstructs it from the interspect record.
8. **Policy immutability during halt (S-08).** When the halt sentinel is active (factory-paused.json OR interspect halt record), all Ockham subsystems are read-only. No weight updates, no authority changes, no signal evaluation. Only `ockham resume` (principal action) clears both sentinels and re-enables writes. **Recovery ordering (N-03):** `ockham resume --constrained` allows intent changes while keeping the factory paused, so the principal can fix misconfigured weights before re-enabling dispatch.

### 8. What Ockham Is NOT (Q-04)

- **Not a scheduler.** Ockham produces weights; Clavain decides dispatch timing and agent selection.
- **Not an audit log.** Interspect owns the evidence trail. Ockham writes to interspect, never maintains its own audit store.
- **Not a UI.** Meadowsyn renders Ockham's health output. Ockham is headless.
- **Not a Clavain replacement.** Clavain owns sprint execution, quality gates, and the agent dispatch loop. Ockham shapes the inputs to that loop.
- **Not a quality arbiter.** Quality gates are Clavain's domain. Ockham never evaluates code quality or review correctness.
- **Not a Skaffen governor.** Skaffen-dispatched work (direct tmux agent sessions) is outside Ockham's scope until Wave 4 re-evaluation.

### 9. What already works (zero code changes)

- `~/.clavain/factory-paused.json` → Tier 3 halt
- `~/.clavain/paused-agents/<id>.json` → Tier 2 agent demotion
- `ic lane update --metadata="paused:true"` → Tier 2 theme freeze
- `_interspect_apply_routing_override()` → Tier 2 agent exclusion
- `bd set-state autonomy_tier=3` → Tier 2 ratchet demotion

### 10. Weight-outcome feedback loop (SUBAK-01)

Ockham's weights must be outcome-derived, not just enforcement-derived. Without a feedback loop, misconfigured intent degrades the factory indefinitely with no detection.

**Mechanism:** After each bead completion, compare actual cycle time and quality gate pass rate against the predicted baseline for that theme. If a theme's actual-vs-predicted ratio degrades >20% over a 7-day rolling window, Ockham emits a Tier 1 INFORM signal and logs a `weight_drift` event to interspect.

**Minimum sample size:** The feedback loop activates only after a theme has >= 10 completed beads. Below that, variance is too high for meaningful drift detection. New themes run in monitoring-only mode (log but don't signal) until they cross the threshold.

**Actuation (D-06):** When weight_drift fires, Ockham's response depends on the drift direction:
- Theme underperforming → reduce the theme's priority by one step (high→normal, normal→low). Log the change.
- Theme outperforming → no automatic change (pleasure signals handle promotion). Log for analysis.
- The principal can override any automatic adjustment via `ockham intent`. Automatic adjustments are advisory-strength in Wave 1 (log + suggest), enforcement-strength in Wave 2+.

**Feedback loop interaction rule (SYS-NEW-01):** When SUBAK-01 weight-drift and the autonomy ratchet both fire on the same domain simultaneously, apply the more restrictive signal only — do not compound. The ratchet demotion already reduces throughput; adding weight suppression on top creates a self-reinforcing degradation spiral. Specifically: if a domain is being demoted by the ratchet, suppress weight_drift signals for that domain until the ratchet stabilizes (one confirmation window after demotion).

**Implementation:** The feedback loop reads from interstat (cycle time, cost) and interspect (gate pass rates), grouped by theme. Ships in Wave 1 alongside Tier 1 INFORM — without it, Ockham is a governor that can't tell when its own policies are harmful.

**Intercept integration:** The weight-drift detection threshold (20%) starts hardcoded, logs every evaluation through intercept. Distillation is Wave 2 (needs 50+ evaluations that won't exist in Wave 1's first weeks). Wave 1 deliverable is detection + logging + advisory actuation.

**Wave 1 wiring needed:** `ockham_offset` read in lib-dispatch.sh (with CONSTRAIN-first evaluation order) + bulk pre-fetch + raw/offset/final score logging + `ockham check` in SessionStart hook + weight-drift detection (logging + advisory actuation) + signals.db for temporal state + authority snapshot persistence.

## Open Questions (reduced from 5 to 2)

1. **Multi-factory:** If multiple Sylveste instances share a beads tracker, does each get its own Ockham? (Defer to post-Wave 1 — single-factory for now.)
2. **Evidence gaming vectors (S-02):** Agents influence their own first_attempt_pass_rate through bead granularity choices. Use gate results at review time as canonical evidence, not bead closure events? (Resolve during authority package design, Wave 3.)
