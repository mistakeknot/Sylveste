# Brainstorm: Interspect Adaptive Routing — Next Phase

**Date:** 2026-03-17
**Bead:** iv-5ztam (epic: Interspect adaptive routing — evidence-driven agent selection)

## Current State Assessment

Interspect is **production-ready** with most originally-planned features shipped:
- Evidence collection: 3 channels (corrections, dispatch, kernel events)
- Pattern detection & classification with counting rules
- Routing override proposals with batch approval + cross-cutting warnings
- Canary monitoring with baseline + sampling + 20% regression threshold
- Autonomous mode with circuit breaker (3 reverts/30d) + rate limiter (5 mods/24h)
- Agent calibration (shadow mode routing scores)
- Delegation calibration (B4 track)
- Full CLI: 14 commands, 3 hooks, 114KB core library

**What's missing** (from the exploration and epic description):

1. **Prompt tuning overlays (Type 3)** — infrastructure in place (directories, schema), but no creation or evaluation workflow
2. **Multi-project calibration** — currently per-project only; patterns that repeat across projects aren't surfaced
3. **Counterfactual shadow evaluation** — mentioned in PHILOSOPHY but not implemented
4. **Eval corpus** — no standardized test set for measuring override quality
5. **Effectiveness metrics** — no way to quantify "was the routing change good?" beyond canary pass/fail
6. **Routing enforcement integration** — calibration is shadow-only; Go fast path skips bash calibration layer

## Gap Analysis: What Would Make the Biggest Difference?

### Gap 1: Effectiveness Measurement (HIGH IMPACT)

**Problem:** Interspect can propose and apply overrides, but can't answer "are our routing decisions making reviews better?" The canary system prevents regression, but doesn't measure improvement.

**Solution:** Add aggregate effectiveness metrics:
- **Before/after override rate** — did the agent's false positive rate actually drop after excluding it?
- **Session cost delta** — are sessions cheaper/faster after routing changes?
- **Finding density change** — are remaining agents producing more relevant findings?
- **Dashboard command** — `/interspect:effectiveness` showing trends

### Gap 2: Cross-Project Pattern Aggregation (MEDIUM IMPACT)

**Problem:** If fd-game-design is consistently wrong across 5 projects, each project must independently accumulate evidence and propose the override. The pattern is obvious from a global view but invisible per-project.

**Solution:** Cross-project evidence aggregation:
- **Global evidence view** — query all project databases, merge patterns
- **Cross-project proposals** — "fd-game-design has been excluded in 4/7 projects, propose for remaining?"
- **Global calibration** — agent scores aggregated across projects for higher confidence

### Gap 3: Prompt Tuning Overlays (MEDIUM IMPACT)

**Problem:** Currently the only action is "exclude agent entirely." Sometimes the agent is useful but needs prompt tuning — e.g., fd-performance gives irrelevant advice for Python projects but is great for Go.

**Solution:** Complete the overlay system:
- **Overlay creation** — `/interspect:tune <agent>` generates a prompt overlay from correction patterns
- **Overlay format** — markdown in `.clavain/interspect/overlays/<agent>/tuning.md`
- **Overlay injection** — Clavain reads overlays and prepends to agent system prompt
- **Overlay canary** — same canary system but for prompt changes, not exclusions

### Gap 4: Go Fast Path Integration (LOW IMPACT, HIGH COMPLEXITY)

**Problem:** `ic route model` (Go binary) skips the bash calibration layer, meaning calibration scores don't affect routing when the Go path is used.

**Solution:** Either port calibration reads to the Go router or add a JSON config that the Go binary reads at startup.

## Recommendation: Scope for This Sprint

Given this is already a mature system, I recommend **Gap 1 (Effectiveness Measurement)** as the primary deliverable:

1. It compounds the value of everything already built
2. It's self-contained (no cross-repo changes needed)
3. It provides data to justify future investments (Gaps 2-4)
4. It's implementable in a single session

Gap 2 (cross-project) is valuable but requires careful design around database access patterns. Gap 3 (overlays) needs design work on how prompts get injected. Both are good follow-up sprints.

## Feature Sketch: Effectiveness Dashboard

### New command: `/interspect:effectiveness`

Shows:
```
Routing Effectiveness — Last 30 days

Active Overrides: 3
  fd-game-design     excluded  14d ago   canary: passed
  fd-resilience      excluded   7d ago   canary: active (12/20 uses)
  fd-perception      excluded  21d ago   canary: passed

Aggregate Impact:
  Override rate:     23% → 15%  (-35% improvement)
  Avg session cost:  $1.47 → $1.22  (-17%)
  Agent dispatches:  8.2/session → 6.1/session  (-26%)
  Unique findings:   4.1/session → 3.8/session  (-7%, expected)

Per-Agent Trends:
  fd-architecture    hit_rate: 0.91  trend: stable
  fd-quality         hit_rate: 0.87  trend: improving (+3%)
  fd-correctness     hit_rate: 0.82  trend: stable
  fd-safety          hit_rate: 0.78  trend: declining (-5%)  ⚠

Recommendations:
  ⚠ fd-safety declining — consider /interspect:evidence fd-safety
```

### Data sources:
- Override rate: existing evidence table (override_reason counts)
- Session cost: interstat token data (if available via cass)
- Agent dispatches: evidence table (agent_dispatch events)
- Hit rates: existing calibration scores
- Trends: time-bucketed queries (7d windows)

### Implementation approach:
- New function `_interspect_effectiveness_report()` in lib-interspect.sh
- SQL queries against existing evidence + sessions tables
- Optional integration with interstat for cost data
- New command file `commands/interspect-effectiveness.md`

## Open Questions

1. Should effectiveness show historical trend graphs (sparklines) or just numbers?
2. Should recommendations auto-surface in `/interspect:status` or require explicit command?
3. Should cross-project aggregation be a flag on effectiveness (`--global`) or separate command?
