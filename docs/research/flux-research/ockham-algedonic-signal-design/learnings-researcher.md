---
artifact_type: research
date: 2026-04-02
topic: algedonic-adjacent signal patterns in Sylveste
---

# Learnings Researcher: Algedonic-Adjacent Patterns in Sylveste

## Search Context

- **Task**: Surface existing signal/response patterns before designing Ockham's algedonic signal layer
- **Keywords**: circuit breaker, backpressure, canary, threshold, degradation, discourse health, budget pressure, closed-loop, OODARC, review queue, dispatch scoring
- **Files Scanned**: 18 source files / 30+ docs
- **Relevant**: 8 primary sources, 6 supporting docs

---

## Critical Patterns

From `docs/solutions/patterns/critical-patterns.md`: No patterns directly about signal design. Relevant adjacent pattern: the **activation gap** (docs/solutions/patterns/activation-sprint-last-mile-gap-20260307.md) — fail-safe design makes "not installed" and "installed but degraded" produce identical observable behavior. Any algedonic channel that fails silently will look exactly like a healthy channel.

---

## Relevant Learnings

### 1. Dispatch Backpressure — Review Queue as WIP Signal

**File**: `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-dispatch.sh`

**Relevance**: The most direct algedonic-adjacent pattern in the codebase. Review queue depth is a factory health signal that changes dispatch behavior in two graduated steps.

**How it works**:
- Signal source: `bd list --status=open --label=needs-review` + beads in shipping/quality phase
- Threshold: `DISPATCH_REVIEW_PRESSURE_THRESHOLD` (default 3 pending reviews)
- Response 1 (proportional, passive): when `review_depth > threshold`, subtract `(depth - threshold) * 5` points from all candidate scores. More reviews pending = steeper score penalty. Dispatch still happens, but candidates are deprioritized.
- Response 2 (active, behavioral): when `review_depth > threshold * 2` (double — deeply in the weeds), `DISPATCH_CAP` is forced to 1 for the session. From brainstorm: "reduce parallelism to recover, don't pile on more work." (rsj.1.3, autonomous-epic-execution-brainstorm.md)

**Active or passive**: Active at the 2x threshold (changes behavior). Passive/scoring at the 1x threshold (informs scoring).

**What went wrong**: The brainstorm `2026-03-28-autonomous-epic-execution-brainstorm.md` identified this as a gap: "Self-dispatch keeps producing when review queue is full — no backpressure." The feature existed in code but the lean production analysis found the signal was insufficient (no WIP limit, hidden WIP in decomposition). The P0 fix was to wire review-queue-depth as a negative factor in dispatch scoring — which is what rsj.1.3 implemented. The lesson: backpressure needs to be wired to the actual production signal, not inferred from status labels.

**Known bug**: `DISPATCH_CAP=1` mutates a global variable for the rest of the session (documented in `docs/brainstorms/2026-03-29-reflect-compound-durable-changes.md` as an example of a learning that should be a code comment in lib-dispatch.sh, not a dead reflection file).

---

### 2. Interspect Canary Monitoring — Routing Override Quality Signal

**File**: `/home/mk/projects/Sylveste/interverse/interspect/hooks/lib-interspect.sh`

**Relevance**: Post-hoc quality signal with graduated escalation. Closest existing pattern to a proper algedonic channel: detects degradation in a subsystem (agent routing quality), emits warning signals (SessionStart context injection), and can escalate to behavior change (autonomy disable).

**How it works**:
- Signal source: SQLite evidence table. Metrics per routing override: `override_rate` (agent findings overridden by user), `fp_rate` (false positive rate), `finding_density` (findings per session).
- Canary window: 20 uses over 14 days after an override is applied.
- Noise floor: 0.1 (changes smaller than this are ignored — prevents alert on statistical noise).
- Alert threshold: 20% relative change from baseline (configurable, `canary_alert_pct`).
- Degradation detection: `override_rate` increase or `fp_rate` increase = degradation; `finding_density` decrease = degradation.
- Response: `_interspect_evaluate_canary()` returns `verdict: "alert"` when any metric crosses its threshold. SessionStart hook injects warning context (`additionalContext`) when active alerts exist.

**Active or passive**: Passive (informs, doesn't block). The alert surfaces in session context but doesn't prevent dispatch or routing. The revert action is a separate human-triggered command (`/interspect:revert`).

**Circuit breaker escalation**: Per-agent circuit breaker trips at 3+ reverts in 30 days → blocks autonomous modifications for that agent. System-level breaker trips when >= 50% of agents with evidence have tripped → calls `_interspect_set_autonomy("false")`. This is the escalation path from "passive alert" to "active behavioral change."

**What went right**: The two-level architecture (per-agent + system) prevents a single bad agent from disabling everything while ensuring systemic problems force human attention. The 60-second TTL cache on system breaker avoids repeated full scans.

**What went wrong**: The canary pattern exists but evidence collection is sparse in practice — `expired_unused` (no sessions during monitoring window) is a common outcome. The signal only fires when usage is high enough. Low-traffic agents have effectively no monitoring.

---

### 3. Discourse Fixative — Pre-Synthesis Health-to-Behavior Loop

**Files**: 
- `/home/mk/projects/Sylveste/interverse/interflux/config/flux-drive/discourse-fixative.yaml`
- `/home/mk/projects/Sylveste/interverse/interflux/config/flux-drive/discourse-sawyer.yaml`
- `/home/mk/projects/Sylveste/docs/brainstorms/2026-03-31-discourse-fixative-brainstorm.md`

**Relevance**: The only pattern where a health signal directly modifies the content of future agent prompts (not just metadata or scores). Signal → behavior at low latency within a single run.

**How it works**:
- Sawyer (health monitor, rsj.7): post-hoc measurement after Phase 2 synthesis. Three metrics: `participation_gini` (imbalance), `novelty_rate` (uniqueness of findings), `response_relevance` (evidence anchoring). States: healthy / degraded / unhealthy.
- Fixative (corrective injection, rsj.9): runs before Phase 2.5 (reaction round). Computes approximate pre-synthesis Gini + novelty estimate from raw agent outputs. Three trigger conditions: `participation_gini_above: 0.3`, `novelty_estimate_below: 0.1`, `collapse_threshold: 2` (both fired simultaneously).
- Response: appends injection text to reaction prompts. Each trigger maps to a specific injection: imbalance → "prioritize expressing your divergent perspective"; convergence → "focus on what's MISSING"; drift → "anchor to file:line references"; collapse → "challenge at least one peer finding."
- `drift_unconditional: true` — the drift injection fires on every reaction round regardless of health, because evidence anchoring is always beneficial and can't be estimated pre-synthesis.

**Active or passive**: Active (changes prompts). Zero cost when healthy (no-op). ~50-100 tokens overhead when triggered.

**Key design principle** (from brainstorm): "The fixative should be invisible when the discourse is healthy — the sandalwood principle." This is a concrete implementation principle: the signal channel should have zero cost and zero noise on the healthy path.

**What went right**: The decision to use Option A (prompt injection) over Option B (separate agent) or Option C (post-synthesis re-run) was driven by cost: zero additional dispatches. The no-op path is genuinely zero-cost, not just "low cost."

**Open gap**: Fixative thresholds are static. The brainstorm explicitly asks: "Should the fixative thresholds evolve based on Interspect feedback?" This is deferred to Phase 2. The pattern exists but the calibration loop is not closed.

---

### 4. Quality Gates — Pass/Fail with Phase Advancement Block

**File**: `/home/mk/projects/Sylveste/os/Clavain/commands/quality-gates.md`

**Relevance**: Hard gate pattern. P1+ findings prevent phase advancement — the most forceful response in the system.

**How it works**:
- Signal source: flux-drive synthesis (scored findings from multi-agent review).
- Decision: `clavain-cli enforce-gate "$BEAD_ID" "shipping"` — gate passes or blocks.
- Response on PASS: `clavain-cli advance-phase` (phase advances to shipping).
- Response on FAIL: no phase advance. "Do NOT set phase on FAIL — work needs fixing first."
- Evidence side-channel: per-agent verdict files written to `.clavain/verdicts/*.json`, fed to Interspect via `_interspect_record_verdict()`.

**Active or passive**: Active (blocks phase advancement). The Interspect side-channel is passive (records for future calibration).

**Small change shortcut**: If `DIFF_LINES < 20` and `CHANGED_FILES == 1`, runs only `fd-quality` directly (skips full flux-drive). Differential cost signal: small changes get lighter review.

**What went right**: Interspect evidence recording is fail-open (`|| true`). Gate enforcement never fails due to evidence recording errors. Evidence collection is a side effect, not a dependency.

---

### 5. Budget Controls — Token Pressure on Agent Dispatch

**Files**: 
- `/home/mk/projects/Sylveste/interverse/interflux/config/flux-drive/budget.yaml`
- `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-sprint.sh`

**Relevance**: Cost pressure as a signal that reshapes the agent set dispatched, not just a hard stop. Two distinct budget systems at different scopes.

**Flux-drive budget (per-run)**:
- Signal: total estimated tokens for selected agents vs. budget ceiling (type-dependent: diff-small=60K, diff-large=200K, repo=300K).
- `enforcement: soft` — warn + offer override, don't hard-block.
- AgentDropout (step 2.2a.5): when budget pressure exists, prune Stage 2 agents whose domains are already covered. `threshold: 0.6` redundancy score. Exempt agents: `fd-safety`, `fd-correctness` (never dropped regardless of budget).
- Incremental expansion (step 2.2a.6): `max_speculative: 2` — launch up to 2 Stage 2 agents early when Stage 1 findings justify it.

**Sprint budget (per-sprint)**:
- Signal: `sprint_budget_remaining()` = `token_budget - tokens_spent`.
- Per-stage allocation: 5 stages (discover/design/build/ship/reflect) each get a percentage share.
- Response: `sprint_budget_stage_check()` emits `"budget_exceeded|$stage|stage budget depleted"` to stderr and returns 1. This is informational — the sprint orchestrator must interpret it.
- No behavioral enforcement: budget depletion warns but doesn't block (complements the soft enforcement in flux-drive).

**Active or passive**: Mixed. AgentDropout is active (changes which agents run). Budget stage check is passive (warns, caller decides).

**Key lesson from budget.yaml**: "Validated 2026-03-26 (26+ runs): 0% P0/P1 recall loss — dropout candidates never produce P0/P1." The AgentDropout threshold was lowered from 0.7 to 0.6 based on evidence. This is the closed-loop pattern (collect actuals → calibrate threshold) operating on the budget system itself.

---

### 6. Reflect/Compound — The OODARC Closed-Loop Pattern

**Files**:
- `/home/mk/projects/Sylveste/PHILOSOPHY.md`
- `/home/mk/projects/Sylveste/docs/brainstorms/2026-03-29-reflect-compound-durable-changes.md`
- `/home/mk/projects/Sylveste/docs/brainstorms/2026-02-19-reflect-phase-learning-loop-brainstorm.md`

**Relevance**: The architectural frame for all signal-to-behavior loops in the system. The OODARC lens describes how every signal channel should be structured.

**OODARC structure** (from PHILOSOPHY.md):
- **Observe**: collect evidence (agent findings, override rates, token costs, gate pass/fail)
- **Orient**: classify the signal (Interspect pattern analysis, discourse health scoring, budget math)
- **Decide**: routing proposal, injection trigger, dispatch cap adjustment
- **Act**: apply override, inject fixative, reduce cap, block phase
- **Reflect**: extract lesson from outcome (per-sprint at reflect phase)
- **Compound**: persist in a form that changes future behavior (calibration files, routing overrides, CLAUDE.md additions)

**The Closed-Loop Pattern** (from PHILOSOPHY.md "Closed-loop by default"):
Four required stages: (1) hardcoded defaults, (2) collect actuals, (3) calibrate from history, (4) defaults become fallback. "Shipping fewer than all four is incomplete work."

**What went wrong** (from `2026-03-29-reflect-compound-durable-changes.md`):
Reflect and Compound produce documents that have no automated consumers. "Current flow: learning → standalone markdown file → nobody reads it → same mistake repeats." The learning loop is architecturally present (phase exists) but the output is not wired to behavior change. Only `CLAUDE.md` additions, code comments, hooks, and auto-memory entries actually change future behavior. The 80/20 finding: ~80% of learnings should be one-liners at point of use; ~20% go in AGENTS.md or PHILOSOPHY.md.

**Key insight**: The reflect/compound pattern is the meta-loop that closes ALL other loops. Interspect's canary monitoring is only useful if the override thresholds themselves are calibrated. That calibration happens through the reflect/compound cycle. A signal channel without a calibration loop is "a constant masquerading as intelligence."

---

### 7. Dispatch Circuit Breaker — Infrastructure Health vs. Claim Race Discrimination

**File**: `/home/mk/projects/Sylveste/os/Clavain/hooks/lib-dispatch.sh`

**Relevance**: Teaches an important lesson about signal discrimination — not all "failures" are the same signal.

**How it works**:
- Circuit trips at `DISPATCH_CIRCUIT_THRESHOLD=3` consecutive infrastructure failures.
- Infrastructure failure: bd unavailable, discovery scan returns `DISCOVERY_UNAVAILABLE|DISCOVERY_ERROR`.
- Claim race: another agent claimed the bead first. Logged as `race_lost` but NOT counted toward circuit breaker.
- Reset: successful claim resets failure count to 0.

**Why discrimination matters**: Claim races are expected and healthy under multi-agent load. If they counted as failures, the circuit breaker would trip during normal high-traffic operation, suppressing dispatch when the factory is actually running well. Infrastructure failures are the only genuine "pain signal" — they indicate the environment is broken.

**From solutions doc** (`2026-03-20-self-dispatch-stop-hook-integration.md`):
> "Circuit breaker must distinguish race losses from infra failures — Claim races are expected under multi-agent load. Counting them as failures trips the circuit breaker during normal operation."

---

### 8. Autonomous Epic Execution Brainstorm — What Was Missing

**File**: `/home/mk/projects/Sylveste/docs/brainstorms/2026-03-28-autonomous-epic-execution-brainstorm.md`

**Relevance**: 32-agent cross-domain analysis identified the gaps in the existing signal infrastructure. The P0 items from this brainstorm are the stated deficiencies as of 2026-03-28.

**Identified gaps**:
1. No global WIP limit (lean production finding). Hidden WIP in decomposition (theme spawning 15 beads = committed future work invisible to any signal channel).
2. No "post-merge canary gate" — silent failure detection after a bead ships, before the next sprint starts.
3. Review queue backpressure was insufficient (addressed by rsj.1.3 but identified as needing more).
4. Interspect evidence quarantine: bad sprints contaminate the learning baseline (48h quarantine proposed).
5. No Operational Design Domains (SAE robotics finding) — "Human attentiveness assumed, never verified."
6. No formal escalation path from autonomy signals to the human operator when ODD conditions fail.

---

## Recommendations

1. **Use graduated response architecture**: All existing patterns use proportional-then-binary response (dispatch scoring penalty → DISPATCH_CAP reduction). Ockham's algedonic channel should follow this: informational signal at low severity, behavioral constraint at medium, hard block or human escalation at high.

2. **Discriminate signal types before routing**: The circuit breaker lesson is critical. Claim races, infrastructure failures, and quality degradation are three distinct signal classes that require different responses. Don't aggregate them into a single "health score."

3. **Zero-cost on healthy path is a hard requirement**: The fixative's "sandalwood principle" is validated — the system runs thousands of sessions. Any signal channel that adds overhead on every run, even when healthy, will generate optimization pressure to disable it.

4. **Wire the loop or it doesn't exist**: The reflect/compound gap is the canonical failure mode. If Ockham's algedonic signals write to a log that nothing reads, the loop is not closed. The acceptance criteria for any new signal channel must include: (a) where it is called from, (b) what evidence it emits, and (c) what calibration reads that evidence to adjust future thresholds.

5. **Fail-open on signal collection, fail-closed on behavioral gates**: Quality gates record Interspect evidence fail-open (`|| true`) but enforce phase advancement fail-closed. Algedonic signals should follow this: never let signal collection failures block work, but let verified signals block risky actions.

6. **The activation gap is the most likely first failure**: The solution pattern `activation-sprint-last-mile-gap-20260307.md` documents that fail-safe design makes "not installed" and "degraded" look identical. Any new algedonic channel needs a health-check path that can distinguish "channel healthy" from "channel absent."

7. **Thresholds need calibration loops**: The AgentDropout threshold (0.7 → 0.6 based on 26 runs of evidence) and canary alert_pct (configurable, not hardcoded) demonstrate that hardcoded thresholds are always provisional. Build the collection + calibration path from the start.

---

## Confidence

**High confidence**: Patterns 1-7 are read directly from source. Architecture, thresholds, and failure modes are documented in code and brainstorms.

**Medium confidence**: Assessment of what "went wrong" is inferred from brainstorm problem statements and the reflect/compound analysis. Not all failures have been confirmed closed.

**Low confidence**: Gap analysis (what Ockham still needs vs. what exists) is interpretive. The autonomous-epic-execution brainstorm identified gaps as of 2026-03-28; some P0 items may have been addressed since.

---

## Gaps

- **No existing factory-level health aggregator**: All patterns above are subsystem-local (discourse quality for a single run, routing quality for a single agent, budget for a single sprint). No system-level signal that aggregates across subsystems. Ockham's algedonic channel may be the first cross-subsystem signal.
- **Post-merge canary is described but not implemented**: The P0 item from autonomous-epic-execution-brainstorm.md. After a bead ships, no signal monitors whether the change caused downstream regressions.
- **No signal for human attentiveness**: The SAE robotics finding — "Human attentiveness assumed, never verified (monitoring paradox)." No ODD-style condition monitoring.
- **DISPATCH_CAP=1 mutation bug**: Documented as a code comment that should be added to lib-dispatch.sh but may not have been addressed.
