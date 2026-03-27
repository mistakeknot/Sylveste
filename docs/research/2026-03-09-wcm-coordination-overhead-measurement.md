# WCM Phase 2: Coordination Overhead & Idle Time Measurement

**Bead:** iv-6bwm7
**Date:** 2026-03-09
**Purpose:** Measure agent idle time, interface-wait delays, and coordination overhead to gate P2→P1 promotion for WCM patterns 3 (commitments) and 4 (idle dispatch)

---

## Data Sources

- **interstat metrics.db**: 1,174 agent runs across 113 sessions, 12.6M classified tokens
- **beads events.jsonl**: 3,722 events, 11 claimed beads, 2,883 closed issues
- **beads issues.jsonl**: 1,178 closed tasks/bugs/features with lead time data

## Metric 1: Coordination Overhead

**Question:** How much of total token spend goes to coordination (review, synthesis, research, planning) vs actual work?

| Category | Tokens | % of Total | Runs |
|----------|--------|-----------|------|
| Main session | 7,303,401 | 63.2% | 313 |
| Work subagents (general-purpose, Explore) | 3,226,961 | 27.9% | 572 |
| Coordination subagents | 1,026,058 | 8.9% | 164 |

**Coordination as % of subagent work: 24.1%**
**Coordination as % of all work: 8.9%**

Top coordination consumers:
- Review agents (fd-architecture, fd-correctness, fd-quality, fd-safety, fd-user-product): 534,220 tokens (52% of coordination)
- Synthesis agents (synthesize-review, synthesize-research): 128,238 tokens (12.5%)
- Research/learnings: 193,089 tokens (18.8%)
- Plan agents: 128,989 tokens (12.6%)

**Interpretation:** Coordination overhead is moderate at ~9% total. The review pipeline is the largest coordination cost. This is healthy — reviews produce evidence for the trust ladder. No intervention needed.

## Metric 2: Session Concurrency (Interface-Wait Proxy)

**Question:** How often do multiple sessions run concurrently, creating potential for interface-wait delays?

| Concurrent Sessions | Frequency | % |
|---------------------|-----------|---|
| 1 | 20 | 8.8% |
| 2-3 | 58 | 25.7% |
| 4-6 | 83 | 36.7% |
| 7-9 | 52 | 23.0% |
| 10-11 | 6 | 2.7% |

**Max concurrent sessions: 11**
**Sessions > 1hr: 66/113 (58%)**

**Interpretation:** High concurrency is common — 62% of the time there are 4+ concurrent sessions. This creates real potential for interface-wait delays, but the current Interlock reservation system handles file conflicts. The question is whether agents are *blocked* waiting for another agent's output (interface-wait) vs simply working on independent tasks.

**Key limitation:** We cannot distinguish between "multiple sessions working on independent beads" and "multiple sessions blocked on each other's outputs" from this data. The interstat DB doesn't record blocking events.

## Metric 3: Inter-Dispatch Idle Time

**Question:** How much time do sessions spend idle between subagent dispatches?

| Gap Duration | Count | % |
|-------------|-------|---|
| < 5min (active work) | 445 | 60.8% |
| 5-30min (possible idle) | 135 | 18.4% |
| > 30min (session break) | 152 | 20.8% |

**Within-session idle time: 30.6h out of 41.0h total gap time (74.5%)**

**Critical caveat:** This metric measures gaps between *subagent dispatches*, not true idle time. During a 10-minute gap, the main session is typically:
- Reading files (Read tool)
- Editing code (Edit tool)
- Running tests (Bash)
- Thinking/planning

The main session consumes 7.3M tokens during these gaps — it is not idle. The metric captures **subagent underutilization**, not agent idleness.

**Refined interpretation:** The high gap ratio (74.5%) means there is substantial time between subagent dispatches where *additional parallel subagents could be dispatched* if appropriate work existed. This is the addressable opportunity for Pattern 4 (idle-time work suggestion).

## Lead Time Analysis

| Percentile | Lead Time |
|-----------|-----------|
| P10 | 6 min |
| P25 | 19 min |
| P50 (median) | 1.8 hours |
| P75 | 9.2 hours |
| P90 | 47.5 hours |
| Max | 760 hours |

- Same-session completion (< 2h): 54% of all closed beads
- Multi-session (>= 2h): 46%

## Bead Claim Analysis

Only 11 beads have claim metadata (claims were introduced recently). Claim-to-close times:
- iv-hvoyx: 0.25h (same session)
- iv-wie5i.2: 0.39h (same session)
- Sylveste-dcy: 0.45h (same session)
- iv-057uu: 0.47h (same session)
- iv-zfvdf: 1.85h (same session)
- iv-g36hy: 4.16h (multi-session)

Too few data points for statistical analysis. Claim system is too new.

## Decision Gate: Pattern Promotion

### Pattern 3 (Verifiable Work Commitments): P2 → P1?

**Verdict: NO — remain P2**

Rationale: Coordination overhead is only 8.9% of total tokens. The existing review pipeline (fd-* agents) already provides post-hoc verification. Adding pre-hoc commitments would increase coordination overhead for uncertain benefit. The Goodhart resistance design (from WCM brainstorm flux-drive review) is still unresolved.

### Pattern 4 (Proactive Idle-Time Work): P2 → P1?

**Verdict: CONDITIONAL — promote to P1 with scope constraints**

Rationale: The 74.5% subagent-gap ratio reveals a genuine opportunity. However:

1. **The opportunity is subagent parallelism**, not whole-agent idle time. Main sessions are working during gaps.
2. **The intervention is micro-task dispatch**: during long gaps (5-30min), dispatch additional parallel subagents for complementary work (tests, docs, static analysis).
3. **Budget constraint required**: The idle-artifact spiral risk (from WCM brainstorm review) is real. Budget-cap micro-task dispatch at 15% of sprint token budget.

**Recommended scope:** Implement idle detection + micro-task dispatch only within the existing sprint pipeline, gated by `ic run budget-remaining`. Do NOT create a standalone idle-work daemon.

## Measurement Gaps

1. **No wall_clock_ms data**: interstat records timestamps but not wall clock duration. Cannot compute true session duration or utilization ratio.
2. **No blocking events**: No record of when agents are blocked waiting for another agent's output. Cannot directly measure interface-wait delays.
3. **No multi-agent sprint data**: Only 1 completed sprint in ic run history. Cannot analyze coordination patterns across sprint phases.
4. **Claim system too new**: 11 claims total. Need 50+ for meaningful claim-conflict analysis.

## Recommendations

1. **Instrument wall_clock_ms** in interstat's PostToolUse hook to enable true utilization measurement
2. **Record blocking events** when `bd update --claim` fails or when coordination lock contention occurs
3. **Re-run this analysis** after 30 days of claim data accumulation (target: 50+ claimed beads)
4. **Promote Pattern 4** to P1 with budget-capped micro-task dispatch scope
5. **Keep Pattern 3** at P2 until Goodhart-resistant commitment scoring is designed
