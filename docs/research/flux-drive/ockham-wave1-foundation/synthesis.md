# Synthesis Report: Ockham Wave 1 Foundation PRD Review

**Date:** 2026-04-04  
**Scope:** Comprehensive PRD review across 5 agents (architecture, correctness, quality, safety, performance)  
**Status:** NEEDS_CHANGES — 3 critical P1 blocking issues; multiple P2 gaps across all layers

---

## Verdict Summary

| Agent | Status | P0 | P1 | P2 | P3 | Key Finding |
|-------|--------|----|----|----|----|-------------|
| Architecture | needs-changes | 0 | 3 | 3 | 3 | Interface assumptions don't match dependencies |
| Correctness | needs-changes | 0 | 4 | 3 | 4 | Floor guard order bug, atomicity gaps, unspecified thresholds |
| Quality | NEEDS_CHANGES | 0 | 3 | 4 | 3 | `ic state list` lacks value output; missing AC test cases |
| Safety | needs-changes | 0 | 3 | 6 | 3 | signals.db corruption, dispatch token contract, halt-guard bypass |
| Performance | needs-changes | 0 | 3 | 4 | 0 | TTL sentinel missing; shell subprocess overhead; scale awareness |

**Converged verdicts:** 5/5 agents: needs-changes

---

## Critical Blockers (P1)

### 1. `ic state list` has no `--json` with values (Arch-01, Quality-01)
**Convergence:** 3 agents independently discovered this.  
**Impact:** F3's bulk pre-fetch architecture cannot be implemented as specified; alternatives are O(N) per-bead calls instead of O(1).  
**Fix:** Either extend `ic state list --json` to return `[{scope_id, value}]` objects (intercore dependency), or accept per-bead `ic state get` and update the AC.

### 2. `agent_reliability(agent, domain)` interface does not exist (Arch-03, Quality-02)
**Convergence:** 2 agents; interspect exposes `confidence.json` (file) not an API boundary.  
**Impact:** F6's cold-start inference and ratchet guard evaluations cannot call the assumed function signature.  
**Fix:** Map the required evidence struct from existing `confidence.json`, or add a thin adapter inside Ockham; mark interspect as "Requires wiring" not "Available."

### 3. signals.db corruption has no recovery path (Safety-002)
**Severity:** High — silent fail-open via `ockham check 2>/dev/null || true`.  
**Impact:** If signals.db is corrupt at halt time, the double-sentinel reconstruction path fails silently; factory resumes despite active halt.  
**Fix:** Add PRAGMA user_version, integrity check on open, backup+reinit on corrupt. Wrap SessionStart invocation with `ockham check --repair` on startup.

### 4. Dispatch token contract absent (Safety-001)
**Severity:** High — self-promotion under spoofed session identity.  
**Impact:** INV-1 (no self-promotion) is deferred to Wave 3, but the token mint specification must exist in Wave 1 or Wave 3 rediscovers OCKHAM-01.  
**Fix:** Add F4 AC specifying Clavain mints dispatch token at SessionStart; store at `~/.clavain/dispatch-tokens/<epoch>.tok`; `ockham check` reads and validates.

### 5. Policy immutability guard missing at `internal/governor.Evaluate()` (Safety-003)
**Severity:** High — INV-8 guard bypassable by direct package callers.  
**Impact:** Factory halt (Tier 3 BYPASS) can be bypassed by any agent calling `governor.Evaluate()` directly, not via CLI.  
**Fix:** INV-8 guard must be in `internal/governor.Evaluate()` before writing offsets, not just CLI entry points.

---

## Correctness Bugs (P1 + P2)

### FIND-02 — Floor guard would re-raise frozen-theme score from 0 to 1 (Correct-02)
**Severity:** P1 — CONSTRAIN bypass without signal.  
**Issue:** F3 AC says "set score=0, skip" but floor guard (step 4) would clamp score 0 back to 1. Frozen beads get dispatched at score=1 instead of excluded.  
**Fix:** Change AC: "if bead's theme is frozen, exclude from candidate set entirely (do not add to result)." Remove "score=0" phrasing.

### FIND-03 — Fresh evidence counter reset scope (Correct-03)
**Severity:** P1 — snap-back promotion after CONSTRAIN.  
**Issue:** AC does not specify that CONSTRAIN demotions reset the counter (only BYPASS is salient). Implementation may silently skip counter reset on CONSTRAIN→shadow transitions.  
**Fix:** Add AC: "Fresh evidence counter resets on ALL demotion events, including automatic CONSTRAIN demotions."

### FIND-04 — `ockham resume` reset lacks atomicity (Correct-04)
**Severity:** P1 — partial-resume state corruption.  
**Issue:** If `ockham resume` crashes mid-domain-reset, factory resumes with mixed autonomy levels. Some domains skip the confirmation window.  
**Fix:** Add `resume-in-progress` marker; complete full reset before clearing it; add transaction semantics.

### FIND-01 — low=-3 magnitude unspecified in F2 (Correct-01)
**Severity:** P1 — threshold ambiguity; symmetric vs asymmetric penalty.  
**Issue:** F2's scoring AC only specifies clamp [-6, +6], not the per-priority magnitudes. Implementation may choose low=-6 (symmetric) instead of low=-3 (asymmetric).  
**Fix:** Add to F2 AC: "Priority-to-offset mapping: high=+6, normal=0, low=-3. Scoring enforces these values."

### FIND-06 — Tier 3 trigger "operating at reduced oversight" unspecified (Correct-06)
**Severity:** P2 — undefined guard; could collapse to raw count check.  
**Issue:** AC includes qualifier but doesn't define it. "Reduced oversight" could mean different things (≥1 domain autonomous? no recent human review? explicit flag?).  
**Fix:** Define testable: "At least one domain is at supervised or autonomous tier. If all at shadow, Tier 3 does not trigger."

### FIND-07 — Feedback loop suppression SYS-NEW-01 has no AC (Correct-07)
**Severity:** P2 — self-reinforcing degradation spiral unguarded.  
**Issue:** Brainstorm specifies suppress weight_drift during ratchet demotion, but no F5 AC enforces this.  
**Fix:** Add F5 AC: "Suppress weight_drift signals for a domain undergoing ratchet demotion, for one confirmation window after demotion."

### FIND-05 — Frozen-domain ineligibility rule missing (Correct-05)
**Severity:** P2 — multi-domain bead dispatch unsafeguarded.  
**Issue:** F6's cross-domain AC specifies min-tier but omits "if any domain is frozen, ineligible regardless of tier."  
**Fix:** Add F6 AC: "If any domain touched by a bead is frozen (CONSTRAIN), exclude from candidate set entirely."

---

## Interface & Integration Gaps (Architecture)

### A-04 — F3 requires F2's write side before end-to-end
**Severity:** P2  
**Issue:** F3 reads offsets, but F2 (which writes them) must ship first; integration order violation.  
**Fix:** Sequence features F2→F3; mark as prerequisite.

### A-05 — Interspect halt-record write path missing
**Severity:** P2  
**Issue:** Double-sentinel reconstruction depends on `ockham check` writing halt record to interspect; the write path is unimplemented.  
**Fix:** Add AC specifying halt-record write to interspect before reconstruction can work.

### A-06 — `cost-query.sh` has no per-theme query mode
**Severity:** P2  
**Issue:** F5 (drift detection) needs cost/cycle grouped by theme; interstat doesn't expose this.  
**Fix:** Either add per-theme aggregation to interstat, or accept direct SQLite access from Ockham.

### A-02 — Lane is a label, not a field (Arch-02, Quality-02)
**Severity:** P1  
**Issue:** F2 AC says `bd list --json | jq '.[] | {id, lane}'` but lane doesn't exist at top level; it's `labels[]` containing "lane:name".  
**Fix:** Update AC to use `bd show <id> --json | jq '.labels[]? | select(startswith("lane:"))'` pattern.

### A-03 — Package naming mismatch (Arch-08, Quality-09)
**Severity:** P3  
**Issue:** PRD names packages `internal/scoring` and `internal/governor`; Ockham directory has `internal/dispatch` (stubs are empty).  
**Fix:** Either rename stubs or clarify the package map.

---

## Performance Critical Path

### HOTSPOT-1 — No TTL sentinel on SessionStart ockham check (Perf-001)
**Severity:** Must fix — every session pays 200-500ms cost unconditionally.  
**Issue:** `ockham check` runs on every SessionStart (including compactions) with no gate. Compaction-heavy sessions trigger 5-10 runs/day.  
**Fix:** Wrap with 5-minute TTL sentinel matching existing `bd doctor` pattern (6 lines).

### HOTSPOT-2 — `ic state list --json` output format unverified (Perf-002, Quality-01)
**Severity:** Must fix — silent no-op if wrong format.  
**Issue:** PRD assumes `ic state list` returns value objects; current implementation returns scope_ids only.  
**Fix:** Verify before implementation; extend ic if needed.

### HOTSPOT-3 — Per-bead `bd show` calls dominate dispatch_rescore (Perf-003)
**Severity:** Must fix separately from Ockham — pre-existing 6+ second cost.  
**Issue:** Not Ockham's responsibility, but F3 should not add to per-bead work.  
**Recommendation:** File separate bead for batch dep/lane API.

---

## Safety Gaps (P2–P3)

### SAFE-W1-004 — Interspect halt-record query contract unspecified (Safety-004)
**Severity:** P2  
**Fix:** Define: event type `ockham-factory-halt`, `status=active` (or `cleared` on resume), `session_epoch` matching current factory instance.

### SAFE-W1-005 — Pleasure signal staleness no freshness bound (Safety-005)
**Severity:** P2  
**Fix:** Add timestamp to pleasure signals in signals.db; reject signals >48h old for promotion decisions; postpone re-confirmation until fresh.

### SAFE-W1-006 — Evaluation order (INV-03) specified in prose, no falsifiable test AC
**Severity:** P2  
**Fix:** Add AC with testable order-violation detection (e.g., frozen-theme bead with +6 offset logs score=0, not score=1).

### SAFE-W1-007 — Cold-start autonomous cap has no testable AC
**Severity:** P2 — INV-08 (start supervised, not autonomous) unguarded.  
**Fix:** Add AC verifying supervised-only on cold start even if evidence qualifies for autonomous.

### SAFE-W1-008 — Cross-domain failure attribution data model gap (Safety-008)
**Severity:** P3 — pre-Wave 3 concern.  
**Fix:** Note in non-goals that ratchet evidence attribution to correct domain requires evidence schema enhancement (Wave 2/3).

### SAFE-W1-009 — `ockham resume --constrained` write scope unspecified (Safety-009)
**Severity:** P3 — unfreeze-during-halt could cause dispatch burst.  
**Fix:** Enumerate permitted writes under `--constrained` (intent changes only? ratchet writes? offset writes?).

---

## Missing AC Test Cases (Quality)

### Q-3 — CONSTRAIN check self-contradictory with Wave 2 non-goal (Quality-03)
**Severity:** P1  
**Issue:** F3 AC references CONSTRAIN (frozen themes), but anomaly subsystem (which produces CONSTRAIN) is deferred to Wave 2. The AC will fail on day 1.  
**Fix:** Either move CONSTRAIN detection to Wave 1, or clarify that F3's CONSTRAIN path is a no-op stub pending Wave 2.

### Q-7 — No negative test AC for frozen-theme non-selectability (Quality-07)
**Severity:** P2  
**Issue:** ACs test positive cases (offset applied) but not negative (frozen theme remains ineligible despite offset).  
**Fix:** Add AC: "Bead with theme frozen and ockham_offset=+6 is NOT selectable; logs reason=CONSTRAIN_FROZEN."

### Q-8 — `ockham health --json` output duplicated across F5 and F7 (Quality-08)
**Severity:** P2 — ownership unclear.  
**Fix:** Consolidate to single feature (F7 preferred, since health is read-only); F5 references pleasure-signal writing only.

### Q-6 — Non-goals section missing brainstorm items (Quality-06)
**Severity:** P2 — "Not a quality arbiter" and "Not an audit log" absent.  
**Fix:** Add to non-goals; clarify scope.

### Q-10 — Baseline prediction bootstrapping unspecified (Quality-10)
**Severity:** P2 — drift detection for new themes.  
**Fix:** Define cold-start baseline (e.g., assume median across all themes, or neutral forecast).

---

## Cross-Agent Convergence

| Issue | Agents | Convergence | Severity |
|-------|--------|-------------|----------|
| `ic state list` value output missing | Arch-01, Quality-01, Perf-002 | 3/5 | P1 |
| `agent_reliability()` does not exist | Arch-03, Quality-02 | 2/5 | P1 |
| Lane field in `bd list` | Arch-02, Quality-02 | 2/5 | P1 |
| CONSTRAIN floor-guard order | Correct-02 | 1/5 (architectural) | P1 |
| Atomicity gaps (resume, state writes) | Correct-04, Safety-003 | 2/5 | P1 |
| signals.db corruption silent fail | Safety-002 | 1/5 (specialized) | P1 |
| Dispatch token contract missing | Safety-001 | 1/5 (specialized) | P1 |
| TTL sentinel missing | Perf-001 | 1/5 (specialized) | P1 |

**Total unique findings: 47** (9 Arch + 12 Correct + 10 Quality + 9 Safety + 7 Perf)

---

## Categorized by Feature

### F1 — Intent (baseline config)
- A-07 (P3): `ic lane status` SQL error in CONSTRAIN path
- Correct-01 (P1): low=-3 unspecified in F2 AC (propagates to F1 mapping)

### F2 — Scoring package
- A-02 (P1): Lane field location
- A-08 (P3): Package name mismatch (internal/dispatch vs internal/scoring)
- Correct-01 (P1): low=-3 magnitude
- Quality-09 (P3): Package naming
- Perf-006 (P3): Stale ockham_offset accumulation (TTL cleanup)

### F3 — Dispatch integration
- A-01 (P1): `ic state list --json` lacks value output
- A-04 (P2): F3 before F2 sequencing
- A-07 (P3): SQL error in dispatch_rescore CONSTRAIN path
- Correct-02 (P1): Floor guard would re-raise frozen score
- Correct-03 (P1): Fresh evidence counter reset scope
- Quality-01 (P1): `ic state list` bulk fetch missing
- Quality-03 (P1): CONSTRAIN self-contradictory with Wave 2
- Quality-07 (P2): No negative test AC for frozen theme
- Perf-002 (P1): `ic state list` output schema unverified
- Perf-003 (P2): Per-bead bd calls dominate (pre-existing)
- Perf-006 (P3): Stale offset accumulation (needs TTL)
- Safety-003 (P1): Governor package guard missing
- Safety-006 (P2): Evaluation order test AC

### F4 — SessionStart hook
- A-01 (P1): Bulk state-fetch syntax
- Correct-01 (P1): low=-3 propagates here
- Perf-001 (P1): No TTL sentinel
- Quality-04 (P2): Duplicate 30-day re-confirmation AC
- Safety-001 (P1): Dispatch token contract
- Safety-002 (P1): signals.db corruption recovery

### F5 — Pleasure signals & drift detection
- A-06 (P2): `cost-query.sh` lacks per-theme mode
- Correct-07 (P2): Feedback loop suppression unguarded
- Quality-05 (P2): Cycle time per theme unavailable
- Quality-10 (P2): Baseline bootstrapping unspecified
- Quality-08 (P2): Health output duplication with F7
- Perf-004 (P2): 7-day window query shape
- Perf-005 (P2): Shell subprocess overhead
- Safety-005 (P2): Pleasure signal freshness bound

### F6 — Autonomy ratchet
- A-03 (P1): `agent_reliability()` missing
- A-09 (P3): `intercept decide` interface mismatch
- Correct-03 (P1): Fresh evidence counter reset all demotions
- Correct-05 (P2): Frozen-domain ineligibility rule
- Correct-08 (P2): Cold-start partial-evidence case
- Quality-02 (P1): `agent_reliability()` missing
- Quality-04 (P2): Duplicate 30-day re-confirmation AC
- Quality-11 (P3): Unspecified schema for ratchet_state in health output
- Safety-005 (P2): Pleasure signal freshness
- Safety-007 (P2): Cold-start autonomous cap test AC
- Safety-008 (P3): Cross-domain failure attribution

### F7 — Halt/resume & diagnostics
- A-05 (P2): Interspect halt-record write path missing
- Correct-04 (P1): `ockham resume` atomicity
- Correct-06 (P2): Tier 3 "reduced oversight" definition
- Quality-08 (P2): Health output duplication with F5
- Quality-11 (P3): Unspecified ratchet_state schema
- Safety-001 (P1): Dispatch token (INV-1)
- Safety-002 (P1): signals.db corruption
- Safety-004 (P2): Halt-record query contract
- Safety-009 (P3): `--constrained` write scope

### Cross-cutting
- Correct-09 (P2): 30-day re-confirmation staggering enforcement
- Correct-12 (P1): Dispatch log schema migration (raw_score, final_score fields)
- Quality-06 (P2): Non-goals section incomplete
- Correct-10 (P1): Starvation detection absent from ACs/non-goals
- Perf-007 (P3): Re-confirmation O(domains) — informational

---

## Non-Goals Clarifications Needed

Per Quality-06:
- Add: "Starvation detection (INV-20) — deferred to Wave 2 with Anomaly subsystem"
- Add: "Not a quality arbiter (explicit Ockham non-goal)"
- Add: "Not an audit log (explicit Ockham non-goal)"
- Add: "Delegation ceiling enforcement (INV-2) — deferred to Wave 3 authority package"

---

## Implementation Sequencing

**Blocked on P1 fixes before coding starts:**
1. Verify `ic state list --json` output format (Perf-002)
2. Map `agent_reliability()` from confidence.json (Quality-02)
3. Add dispatch token contract AC to F4 (Safety-001)
4. Clarify lane field query pattern (Arch-02)
5. Specify CONSTRAIN as exclude-not-zero (Correct-02)

**Can proceed with ACs updated (P2+):**
- All other feature ACs can be implemented with precision once P1 interfaces are verified

**Critical deployment additions:**
- `ockham check` TTL sentinel (Perf-001) — 5 minutes, before F4 wiring
- signals.db integrity check + repair path (Safety-002) — before SessionStart
- Dispatch token mint in SessionStart (Safety-001) — before F4 wiring

---

## Files Referenced

- `/home/mk/projects/Sylveste/docs/prds/2026-04-04-ockham-wave1-foundation.md` — PRD reviewed
- `/home/mk/projects/Sylveste/docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md` — Brainstorm (ground truth)
- `/home/mk/projects/Sylveste/os/Ockham/docs/vision.md` — Vision invariants
- `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-dispatch.sh` — Dispatch implementation
- `/home/mk/projects/Sylveste/interverse/interspect/hooks/lib-interspect.sh` — Interspect interface
- `/home/mk/projects/Sylveste/interverse/interstat/scripts/cost-query.sh` — Cost querying
- `/home/mk/projects/Sylveste/interverse/intercept/bin/intercept` — Intercept gate interface

---

**End of Synthesis Report**
