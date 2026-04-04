---
artifact_type: fd-correctness
bead: sylveste-8em
reviewer: julik
date: 2026-04-04
sources:
  - docs/prds/2026-04-04-ockham-wave1-foundation.md
  - docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
  - os/Ockham/docs/vision.md
  - os/Clavain/hooks/lib-dispatch.sh
  - interverse/interphase/hooks/lib-discovery.sh
---

# Correctness Review: Ockham Wave 1 Foundation PRD

## Invariants Under Review

Before finding gaps, these are the invariants the brainstorm (rev 4) establishes as non-negotiable. I use these as the test bed against which every PRD acceptance criterion is measured.

| ID | Invariant | Source |
|----|-----------|--------|
| INV-01 | Offset bound `[-6, +6]`, double-clamped (Ockham write + dispatch read) | Brainstorm §3 |
| INV-02 | Priority magnitudes: `high=+6`, `normal=0`, `low=-3` | Brainstorm §3 |
| INV-03 | Eval order: CONSTRAIN check → ockham_offset → perturbation → floor guard | Brainstorm §3 |
| INV-04 | shadow→supervised guard: `hit_rate >= 0.80 AND sessions >= 10 AND confidence >= 0.7` | Brainstorm §6 |
| INV-05 | supervised→autonomous guard: `hit_rate >= 0.90 AND sessions >= 25 AND confidence >= 0.85` | Brainstorm §6 |
| INV-06 | No promotion skipping; CONSTRAIN drops one level; BYPASS drops to shadow from any level | Brainstorm §6 |
| INV-07 | Fresh evidence after demotion: `>= 10 sessions` timestamped after demotion event | Brainstorm §6 (OBR-04) |
| INV-08 | Cold start: evidence meeting autonomous guard still starts at supervised | Brainstorm §6 (D-05/SYS-05/R-06) |
| INV-09 | Cross-domain: `effective_tier = min(tier_per_domain)`; any frozen domain → ineligible | Brainstorm §6 (ET-01) |
| INV-10 | Double-sentinel: `factory-paused.json` AND interspect halt record; write-before-notify | Brainstorm §5 (OCKHAM-03) |
| INV-11 | `ockham check` reconstructs `factory-paused.json` from interspect halt record if file deleted | Brainstorm §5 |
| INV-12 | `ockham resume` resets all domains to supervised for one confirmation window | Brainstorm §5 (R-04 step 4) |
| INV-13 | Policy immutability during halt: all writes blocked except `ockham resume` | Brainstorm §7 (S-08) |
| INV-14 | `ockham resume --constrained` allows intent changes while factory paused | Brainstorm §7 (N-03) |
| INV-15 | Tier 3 trigger: `distinct_root_causes >= 2` AND operating at reduced oversight | Brainstorm §5 (C-05) |
| INV-16 | Tier 2: short (1h) AND long (24h) windows must both breach simultaneously | Brainstorm §5 |
| INV-17 | Weight-drift: >20% degradation, 7-day rolling window, minimum 10 completed beads per theme | Brainstorm §10 |
| INV-18 | Feedback loop interaction: suppress weight_drift during ratchet demotion (one confirmation window) | Brainstorm §10 (SYS-NEW-01) |
| INV-19 | 30-day re-confirmation, staggered by promotion timestamp (not synchronized) | Brainstorm §6 (SYS-01) |
| INV-20 | Starvation floor: theme receiving zero dispatches over configurable cadence → Tier 1 INFORM | Vision.md §Starvation Prevention |

---

## Findings

### FIND-01 (High): low=-3 magnitude is absent from ACs; only high=+6 is specified

**Severity:** High. An unspecified low-offset magnitude is a correctness ambiguity that will be resolved independently by different implementers. If low becomes `-6` (symmetric with high), it crosses the brainstorm's intent of asymmetric penalties; if it becomes `0`, it is indistinguishable from normal.

**Gap:** F1's AC "Priority maps to offset magnitude: high=+6, normal=0, low=-3" correctly states all three values. F2's AC says only "Scoring clamps all offsets to [-6, +6]" — the scoring package AC does not restate the per-priority magnitudes. These are not the same thing. The clamp bound and the priority magnitude are separate invariants. A scoring package could clamp to [-6, +6] while producing `low=-6` and still pass the F2 AC, but violate INV-02.

**Concrete failure path:** Developer implements `internal/scoring` and sees F2's AC "clamp [-6, +6]" but does not read F1's magnitude mapping. Chooses `low=-6` for symmetry. The score for a `low` theme bead shifts from `-3` to `-6`. A bead sitting 4 points above a tier boundary is now pushed 3 points further below it than the brainstorm intended. Not caught by the 80% coverage AC unless the test explicitly encodes the exact magnitude.

**Required fix:** Add to F2 AC: "Priority-to-offset mapping is: high=+6, normal=0, low=-3. The Scoring package enforces these values (not just the clamp)."

**Brainstorm reference:** Brainstorm §3 states "high = +6, normal = 0, low = -3" explicitly. INV-02.

---

### FIND-02 (High): Floor-guard position in CONSTRAIN path is ambiguous in F3

**Severity:** High. This is the class of bug that wakes someone up at 3 AM: a frozen theme's beads are supposed to score 0 and be skipped, but if the floor guard fires before or instead of the CONSTRAIN gate, those beads end up scoring 1 and get dispatched.

**Gap:** F3's AC specifies the evaluation order as: "(1) CONSTRAIN check — frozen theme → score=0, skip; (2) apply ockham_offset; (3) perturbation; (4) floor guard." This matches INV-03 exactly. However, the existing `dispatch_rescore()` in `os/Clavain/hooks/lib-dispatch.sh` applies the lane-pause check (via `ic lane status`) inside the scoring loop but does NOT set `score=0` — it calls `continue`, skipping the bead entirely. The PRD AC says "set score=0, skip" which is subtly different from "continue (exclude from result)".

Setting score=0 and then applying the floor guard would raise it back to 1 (since the floor guard is at step 4). The brainstorm's CONSTRAIN gate must exclude the bead from the candidate set, not set its score to a minimum. The AC's "score=0, skip" phrasing conflates a score assignment with an exclusion: the semicoloned "skip" is load-bearing but could be read as an implementation note rather than a correctness requirement.

**Concrete failure path:** Developer reads "CONSTRAIN check → score=0, skip remaining steps" and implements it as: set `adjusted_score=0`, then allow the floor guard (step 4) to clamp it back to 1. The bead remains in the candidate set with score=1 and gets dispatched. A frozen theme is not actually frozen.

The existing `lib-dispatch.sh` code gets this right (it uses `continue` to exclude the bead). But the PRD AC's language could lead an implementer to set score=0 and fall through.

**Required fix:** Change the AC phrasing to: "(1) CONSTRAIN check — if bead's theme is frozen, exclude from candidate set entirely (do not add to result; skip all remaining steps including floor guard)." The word "score=0" must be removed since the floor guard would negate it.

**Brainstorm reference:** Brainstorm §3 and vision.md §Gate-Before-Arithmetic both specify that CONSTRAIN is a dispatch eligibility gate, not an extreme weight. INV-03.

---

### FIND-03 (High): Fresh evidence requirement AC is incomplete — the timer resets on demotion, but the AC does not specify which demotion events reset it

**Severity:** High. The fresh evidence requirement (INV-07) is the primary defense against snap-back promotion after a CONSTRAIN event. If the AC is ambiguous about which demotions reset the counter, the implementation may only reset on BYPASS demotions (which are salient) and silently skip CONSTRAIN-triggered demotions (which are more frequent).

**Gap:** F6's AC states: "after demotion, re-promotion requires >= 10 sessions timestamped after demotion event." This is correct as far as it goes. But the transition table in F6 shows two demotion paths from automatic CONSTRAIN: `autonomous→supervised` and `supervised→shadow`. The AC does not explicitly state that each demotion — including the autonomous→supervised CONSTRAIN path — resets the fresh-evidence counter. There is a reasonable reading where "demotion" only applies to BYPASS (the explicit "drops to shadow") since that is the dramatic case, and the CONSTRAIN demotions are treated as "tier adjustments" that don't require fresh evidence before re-promotion.

**Concrete failure path:** Domain A is at `supervised`. CONSTRAIN fires, drops it to `shadow`. The supervisor evaluates the domain and notes it had 30 historical sessions meeting the supervised guard. An implementer who doesn't reset the counter on CONSTRAIN-demotion re-promotes the domain to supervised immediately (counter not reset, existing evidence satisfies the guard). This violates OBR-04: "stale pre-demotion evidence cannot re-promote."

**Required fix:** Add to F6 AC: "The fresh evidence counter resets on ALL demotion events, including automatic CONSTRAIN demotions, not only BYPASS demotions. Sessions predating the demotion event timestamp are excluded from guard evaluation regardless of their values."

**Brainstorm reference:** Brainstorm §6 (OBR-04). INV-07.

---

### FIND-04 (High): FIND-04 — `ockham resume` reset atomicity not specified in F7 AC

**Severity:** High. The vision.md specifies that `ockham resume` must reset all domains to supervised "atomically (single transaction — if `ockham resume` crashes mid-reset, all domains remain at their pre-halt level, and the next resume attempt retries the full reset)." This atomicity requirement is absent from the F7 AC.

**Gap:** F7's AC for `ockham resume` says: "clears both sentinels, checks Tier 2 state, resets domains to supervised for one confirmation window." No atomicity constraint. Without it, an implementer iterates over domains and resets them one by one. If the process crashes after resetting 3 of 7 domains, the factory resumes with a mixed autonomy state: some domains at supervised, some still at their pre-halt levels (which may be autonomous). The autonomous domains are now operating without the confirmation window the brainstorm requires post-resume.

**Concrete failure path:**
1. Factory halted with 7 domains: 4 at autonomous, 3 at supervised.
2. Principal runs `ockham resume`.
3. Process resets domains 1-3 to supervised, then crashes (OOM, SIGKILL, etc.).
4. Next invocation sees no sentinel file (it was cleared in step 2 before the reset loop).
5. Factory resumes. Domains 4-7 are still at autonomous. Domains 4-7 do not receive a confirmation window.
6. The protection that `ockham resume` was supposed to provide (one supervised confirmation window for all domains) is absent for the autonomous domains.

Note: the sentinel is likely cleared before the domain resets. If it's cleared after, the fail-safe is better — but that ordering is also unspecified.

**Required fix:** Add to F7 AC: "`ockham resume` writes a `resume-in-progress` marker before clearing sentinels and before resetting domain tiers. If the process is interrupted mid-reset, the next invocation detects the marker and completes the full reset before re-enabling dispatch. Only after all domains are at supervised does the marker get removed and dispatch re-enabled."

**Brainstorm reference:** Vision.md §Halt Protocol. INV-12.

---

### FIND-05 (Medium): Cross-domain min-tier AC is present but missing the "any frozen domain → ineligible" rule

**Severity:** Medium. The cross-domain AC in F6 addresses tier resolution correctly but omits the frozen-domain eligibility rule that the brainstorm specifies as a separate condition.

**Gap:** F6's AC states: "Cross-domain beads: authority resolves to min(tier_per_domain)." This correctly implements INV-09's tier resolution. However, brainstorm §6 (ET-01) additionally states: "If any touched domain is frozen (CONSTRAIN), the bead is ineligible for dispatch regardless of other domains' status." This is a distinct rule from min-tier: it applies when the domain is not just at a low tier but is actively CONSTRAIN-frozen. A bead spanning `auth` (frozen) and `performance` (autonomous) has `min(shadow, autonomous) = shadow` — but even shadow-tier dispatch is blocked when auth is frozen. The min-tier rule alone does not capture the frozen-domain ineligibility.

**Concrete failure path:** Domain `auth` is under CONSTRAIN freeze. Domain `performance` is autonomous. A bead touches both. Min-tier gives shadow. Shadow-tier dispatch exists (shadow means "propose, human approves"). The bead is dispatched under shadow rules. But the brainstorm says it should be ineligible for dispatch entirely while `auth` is frozen.

**Required fix:** Add to F6 AC: "If any domain touched by a bead is frozen (CONSTRAIN state), the bead is excluded from the candidate set regardless of its computed min-tier. Frozen-domain ineligibility takes precedence over tier-based dispatch eligibility."

**Brainstorm reference:** Brainstorm §6 (ET-01/HADZA-01): "If any touched domain is frozen (CONSTRAIN), the bead is ineligible for dispatch regardless of other domains' status." INV-09.

---

### FIND-06 (Medium): The Tier 3 trigger AC omits the "at reduced oversight" qualifier

**Severity:** Medium. Without the "operating at reduced oversight" qualifier, the Tier 3 trigger becomes a raw signal count check, which the brainstorm explicitly rejects (C-05: prevents cascade false triggers).

**Gap:** F7's AC states: "Tier 3 BYPASS: when `distinct_root_causes >= 2` and operating at reduced oversight, write factory-paused.json AND interspect halt record (double-sentinel)." The AC includes the qualifier — but it does not define what "operating at reduced oversight" means concretely or how it is evaluated at runtime. Without a testable definition, this qualifier is either ignored (treated as always-true, collapsing to raw count) or implemented inconsistently.

The brainstorm (§5) defines the qualifier as "not just signal count — prevents cascade false triggers per C-05" but does not give a machine-readable definition in either the brainstorm or PRD. "Reduced oversight" could mean: at least one domain is autonomous, the last human review was >N hours ago, the principal has set a low-oversight flag, or some combination.

**Concrete failure path:** A cascading infrastructure failure (e.g., Dolt restart) fires 3 signals with different symptom names but the same root cause (Dolt unavailability). The root-cause deduplication works for that case. But two genuinely distinct root causes fire during a session where all domains are at shadow (maximum oversight). The factory halts unnecessarily, waking the principal.

**Required fix:** Add to F7 AC a testable definition: "Operating at reduced oversight" is defined as: at least one domain is currently at supervised or autonomous tier. If all domains are at shadow (maximum oversight), Tier 3 does not trigger regardless of distinct root cause count. Encode this as an `operating_tier` enum in signals.db alongside the halt condition.

**Brainstorm reference:** Brainstorm §5 (C-05). INV-15.

---

### FIND-07 (Medium): Feedback loop suppression during ratchet demotion has no AC

**Severity:** Medium. The SYS-NEW-01 feedback loop interaction rule (INV-18) is entirely absent from the PRD ACs. This is a silent correctness gap: the brainstorm identifies the "self-reinforcing degradation spiral" as a known failure mode, then specifies the suppression rule, but no AC enforces it.

**Gap:** F5 has ACs for weight-drift detection, threshold, advisory actuation, and drift-detection disabling for <10 beads. It does not have any AC for: "suppress weight_drift signals for a domain that is currently undergoing ratchet demotion, until the ratchet stabilizes (one confirmation window after demotion)."

**Concrete failure path:**
1. Domain `auth` experiences degraded pass rates.
2. The ratchet fires a CONSTRAIN demotion (autonomous → supervised).
3. In the same `ockham check` cycle, the weight-drift signal also fires for `auth` because the degraded pass rate exceeds the 20% threshold.
4. Without suppression: the theme's priority drops one step (advisory actuation from weight-drift) on top of the demotion. Fewer `auth` beads are dispatched. Even fewer pass. The cycle repeats.
5. With suppression: weight_drift is suppressed for one confirmation window. The ratchet stabilizes first, then drift is re-evaluated with fresh data.

This is the spiral the brainstorm names as SYS-NEW-01. It has no AC.

**Required fix:** Add to F5 AC: "If a domain is currently undergoing ratchet demotion (demotion event timestamp within the last confirmation window), weight_drift signals for that domain are suppressed and not emitted to interspect. The suppression lasts one confirmation window, measured from the demotion event timestamp. This condition is evaluated before advisory actuation."

**Brainstorm reference:** Brainstorm §10 (SYS-NEW-01). INV-18.

---

### FIND-08 (Medium): Cold start AC mixes two distinct cases in a way that obscures the conservative guarantee

**Severity:** Medium. The cold start AC in F6 is correct in its final outcome but the phrasing creates an implementation ambiguity that could produce a non-conservative result for a specific edge case.

**Gap:** F6's AC states: "Meets supervised guard → start supervised. Meets autonomous guard → start supervised (conservative). No evidence → shadow." This is correct for the enumerated cases. However, the transition table (F6) shows that supervised→autonomous requires `hit_rate >= 0.90 AND sessions >= 25 AND confidence >= 0.85`. What happens at cold start when evidence meets the supervised guard but NOT the autonomous guard? The AC correctly says "start supervised." But what happens when evidence meets BOTH guards simultaneously (the "meets autonomous guard" case)? The AC says "start supervised (conservative)" — also correct.

The missing case is: what happens when evidence exists but meets NEITHER guard? For example: `hit_rate = 0.75` (below the 0.80 supervised threshold). The AC only enumerates "meets supervised," "meets autonomous," and "no evidence." An implementation that reads the AC literally would default to shadow for this case (since it falls through to "no evidence"), but that is correct. However, the AC should state this explicitly to prevent a "partial evidence → shadow with a note" vs "partial evidence → shadow silently" ambiguity.

The subtler issue is that "no evidence → shadow" is ambiguous about whether partial evidence (exists but below threshold) maps to shadow or to the nearest qualifying tier. A developer could reason: "they have hit_rate 0.75, that's close to supervised, let's start them at supervised and let the ratchet confirm." This is wrong but the AC does not prevent it.

**Required fix:** Add to F6 AC: "Cold start maps evidence to the LOWEST tier whose guard is fully satisfied. Evidence existing but below the supervised guard threshold (hit_rate < 0.80 OR sessions < 10 OR confidence < 0.7) starts at shadow, identical to the no-evidence case. Partial evidence does not grant partial trust."

**Brainstorm reference:** Brainstorm §6 (D-05/SYS-05/R-06). INV-08.

---

### FIND-09 (Low): 30-day re-confirmation staggering rule has no AC

**Severity:** Low. The re-confirmation cadence AC in F6 covers the 30-day evaluation trigger but does not enforce the staggering-by-promotion-timestamp invariant (INV-19). Without staggering, a factory with N autonomous domains promoted in the same month will experience N simultaneous re-confirmations at day 30, which the brainstorm explicitly identifies as a failure mode ("multi-domain demotion cascades at T=30 days").

**Gap:** F6's AC states: "30-day re-confirmation for autonomous domains (staggered by promotion timestamp)." The parenthetical "(staggered by promotion timestamp)" is present but has no enforcement mechanism in any AC. There is no AC that says: "re-confirmation dates are computed as `(promotion_timestamp + 30 days)` and stored in signals.db; they are never synchronized to a shared tick or calendar boundary." A developer could implement a 30-day cron that re-evaluates all autonomous domains simultaneously, which is technically "30-day re-confirmation" but violates the stagger invariant.

**Required fix:** Add to F4 AC (signals.db schema): "Each autonomous domain stores `reconfirmation_due_at = promotion_timestamp + 30 days` in signals.db. `ockham check` evaluates only domains where `reconfirmation_due_at <= now()`. Re-confirmation timestamps are never rounded to calendar boundaries or synchronized across domains. After re-confirmation (pass or demotion), the next `reconfirmation_due_at` is set to `confirmed_at + 30 days`."

**Brainstorm reference:** Brainstorm §6 (SYS-01). INV-19.

---

### FIND-10 (Low): Starvation detection AC is absent entirely

**Severity:** Low. Vision.md §Starvation Prevention specifies that a theme receiving zero dispatches over a configurable cadence triggers a Tier 1 INFORM signal. This is INV-20 and has no corresponding AC in any F-section of the PRD.

**Gap:** F5 covers weight-drift (underperformance signal) but not starvation (zero-dispatch signal). These are distinct: weight-drift fires when a theme dispatches but underperforms; starvation fires when a theme dispatches nothing. The vision.md also specifies "when a high-budget theme exhausts its queue, idle capacity is released to the `open` pool rather than sitting unused" — this capacity-release behavior also has no AC.

**Concrete failure path:** The `auth` theme has `budget: 0.40`. All auth beads are completed. The backlog is exhausted. The `open` pool continues to receive 0% of dispatch despite the high-budget theme being empty. Dispatch efficiency degrades. The principal has no signal that auth capacity is sitting idle. This is precisely the failure the vision.md starvation prevention is designed to detect.

**Note:** Starvation detection may be intentionally deferred to Wave 2 (along with Anomaly subsystem), but if so, it must be explicitly listed in Non-Goals. Currently it appears neither in ACs nor in Non-Goals, which creates ambiguity about scope.

**Required fix:** Either add to F5 AC: "When a theme receives zero dispatches over a configurable cadence (default: 7 days), emit a Tier 1 INFORM `theme_starved` signal. When a high-budget theme exhausts its queue, Ockham adjusts offsets to release that capacity to the `open` pool." Or add to Non-Goals: "Starvation detection and idle-capacity release (Wave 2 with Anomaly subsystem)."

**Brainstorm reference:** Vision.md §Starvation Prevention. INV-20.

---

### FIND-11 (Low): `ockham health --json` schema for ratchet state is underspecified

**Severity:** Low. F7's AC for `ockham health --json` says "ratchet state" as a field but does not specify the structure. This is a testability gap: the AC "outputs JSON: ... ratchet state ..." cannot be deterministically tested without knowing the expected schema.

**Gap:** The AC lists the JSON fields at a category level (pain signals, pleasure signals, ratchet state, overall status) but does not specify the schema for ratchet state. For the 80% coverage requirement in F2 to extend to the health output, the schema must be testable. The F6 AC for `ockham authority show --json` separately covers per-domain state but is a different command from `ockham health`.

**Required fix:** Add to F7 AC a minimal schema: "`ratchet_state` is an array of objects with fields: `domain` (string), `tier` (enum: shadow|supervised|autonomous), `sessions_since_demotion` (int, null if no demotion), `reconfirmation_due_at` (ISO 8601, null if not autonomous)." This makes the health output mechanically testable.

**Brainstorm reference:** General testability requirement. INV-04, INV-05.

---

### FIND-12 (Low): Logging AC for dispatch does not include the three required fields

**Severity:** Low but load-bearing for calibration. F3's AC states: "each scored bead logs `raw_score`, `ockham_offset`, `final_score` to dispatch log." This matches INV-03. However, the existing `dispatch_log()` function in `lib-dispatch.sh` logs: `ts`, `session`, `bead`, `score`, `outcome`. It does not currently have `raw_score`, `ockham_offset`, or `final_score` as separate fields — only a single `score` field. The AC is correct about what should be logged, but the implementation will require a schema change to the dispatch log, and that schema change is not called out as a migration concern.

**Gap:** The JSONL dispatch log at `~/.clavain/dispatch-log.jsonl` currently has schema: `{ts, session, bead, score, outcome}`. Adding `raw_score`, `ockham_offset`, `final_score` means downstream consumers of this log (calibration tooling, interstat) need to handle both old and new entries. No AC in F3 addresses backward compatibility of the dispatch log format.

**Required fix:** Add to F3 AC: "The dispatch log schema is extended to `{ts, session, bead, raw_score, ockham_offset, final_score, outcome}`. Existing entries without `ockham_offset` are interpreted as having `ockham_offset=0`. The `score` field is deprecated in favor of `final_score`; both are written during the transition period."

**Source reference:** `os/Clavain/hooks/lib-dispatch.sh` line 96-103 (current log schema). INV-03.

---

## Summary Table

| ID | Feature | Severity | Category |
|----|---------|----------|----------|
| FIND-01 | low=-3 magnitude absent from F2 scoring AC | High | Threshold gap |
| FIND-02 | Floor guard would re-raise frozen-theme score from 0 to 1 | High | CONSTRAIN eval order |
| FIND-03 | Fresh evidence counter reset scope not specified for CONSTRAIN demotions | High | Transition guard |
| FIND-04 | `ockham resume` domain reset lacks atomicity requirement | High | Halt/resume safety |
| FIND-05 | Cross-domain: frozen-domain ineligibility rule missing from AC | Medium | Transition guard |
| FIND-06 | Tier 3 trigger: "at reduced oversight" has no testable definition | Medium | Signal correctness |
| FIND-07 | Feedback loop suppression (SYS-NEW-01) has no AC | Medium | Signal correctness |
| FIND-08 | Cold start: partial-evidence-below-threshold case not specified | Medium | Transition guard |
| FIND-09 | 30-day re-confirmation staggering has no enforcement AC | Low | Concurrency safety |
| FIND-10 | Starvation detection absent from ACs and Non-Goals | Low | Scope ambiguity |
| FIND-11 | `ockham health --json` ratchet_state schema unspecified | Low | Testability |
| FIND-12 | Dispatch log schema migration for new fields not specified | Low | Data compatibility |

**4 High, 3 Medium, 4 Low** findings across 7 features (F1–F7).

All High findings have concrete failure paths that could cause incorrect dispatch behavior in production. FIND-02 (floor guard on frozen themes) is the most dangerous because it silently negates the CONSTRAIN mechanism without any error signal: frozen beads would be dispatched at score=1 rather than excluded.

---

## Relevant File Paths

- `/home/mk/projects/Sylveste/docs/prds/2026-04-04-ockham-wave1-foundation.md` — PRD reviewed
- `/home/mk/projects/Sylveste/docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md` — Brainstorm (ground truth, rev 4)
- `/home/mk/projects/Sylveste/os/Ockham/docs/vision.md` — Vision document (additional invariant sources)
- `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-dispatch.sh` — Current dispatch implementation; existing log schema (lines 96-103); existing lane-pause check (lines 189-199)
- `/home/mk/projects/Sylveste/interverse/interphase/hooks/lib-discovery.sh` — `score_bead()` function and priority tier gaps (lines 27-86; P0=60, P1=48, P2=36, P3=24, P4=12 — 12-point inter-tier gap)
