---
track: adjacent
agents: [fd-session-memory-architecture, fd-token-economics, fd-feedback-loop-integrity, fd-dispatch-intelligence, fd-integration-surface]
target: docs/brainstorms/2026-03-30-session-intelligence-compounding-brainstorm.md
date: 2026-03-28
---

# Flux Review: Session Intelligence Compounding (Track A — Adjacent)

Five domain-expert agents reviewed the brainstorm through adjacent lenses. Findings ordered by severity within each agent.

---

## Agent 1: fd-session-memory-architecture

Focus: data model, storage topology, lifecycle, invalidation, schema evolution.

### F1.1 — Insight store location conflict (P1)

The brainstorm proposes `~/.interseed/insights.db` as one option for insight storage. But `interseed` is already a shipped plugin with a different purpose (idea garden: capture, refine, graduate). Reusing the name/namespace creates a collision. The brainstorm's "insight capture" is functionally distinct from interseed's "idea refinement."

**Recommendation:** Use a dedicated store under the plugin that owns insights. Either extend cass (it already indexes markdown and can add structured fields) or create a purpose-built `~/.cass/insights/` directory with indexed markdown files. Avoid new SQLite databases — cass already handles the index/search contract and a second DB creates a consistency boundary.

### F1.2 — No schema for insight records (P2)

The brainstorm describes data flows but never defines what an insight record contains. Without a schema, the extraction hook and the search surface will drift. At minimum: `{id, session_id, timestamp, files: [], keywords: [], content, category: insight|dead-end|pattern}`.

**Recommendation:** Define the schema in the brainstorm before planning. Include the cass indexing contract — which fields become searchable, which are metadata-only.

### F1.3 — Session digest lifecycle undefined (P2)

Opportunity 1c writes digests to `~/.cass/digests/<session_id>.md`. No TTL, no pruning, no size cap. At 785+ sessions and growing, this becomes unbounded storage that cass must index.

**Recommendation:** Define a retention policy. 30-day rolling window for digests, permanent for insights. Alternatively, store digests inline in cass's existing session records rather than as sidecar files.

### F1.4 — Duplicate capture with durable reflect (P1)

The recently-planned "Durable Reflect & Compound" work (sylveste-b49, `docs/plans/2026-03-29-reflect-compound-durable-changes.md`) already implements a "learning router" that routes learnings to CLAUDE.md, AGENTS.md, auto-memory, code comments, hooks, and PHILOSOPHY.md. The brainstorm's Cluster 1 (insight capture, dead end capture, compound on close) overlaps significantly. Both propose extracting structured learnings from sessions — the plan does it at reflect-time, the brainstorm at hook-time.

**Recommendation:** Treat the durable reflect plan as the canonical learning capture path. The brainstorm's insight capture should be scoped to *non-reflect signals only* — the ephemeral "insight notices" that appear during normal conversation but would never trigger a /reflect. Clearly delineate the boundary: `/reflect` owns deliberate learnings, the insight hook owns incidental educational content.

---

## Agent 2: fd-token-economics

Focus: cost reduction claims, ROI modeling, measurement feasibility.

### F2.1 — 10% token reduction claim is ungrounded (P2)

The brainstorm states "even 10% token reduction is significant" but provides no basis for the estimate. The actual token breakdown by activity type (file reading, tool retries, context building) is available in interstat and tool-time but not referenced. Without knowing what percentage of tokens go to re-reading files vs. original reasoning, the savings target is arbitrary.

**Recommendation:** Before planning, run `cass analytics tokens --json` and tool-time analysis to decompose where tokens actually go. If file re-reading is 5% of total tokens, a context cache saves at most 5% — not 10%. If it's 30%, the investment is clearly worthwhile. Let data set the target.

### F2.2 — Context cache (2a) cost-benefit is inverted (P1)

The brainstorm correctly flags 2a as "high complexity, risk of stale summaries." But it underestimates the cost side: the hook that checks cass before every Read adds latency and tokens to *every* file read, even when there's no cache hit. At ~$2.93 per landable change, adding overhead to the most common tool call could *increase* costs.

**Recommendation:** Kill 2a entirely. The brainstorm already recommends warm-start primer (2b) instead. Make this explicit: 2a is not "defer" but "reject." The warm-start primer achieves 80% of the value at 5% of the complexity.

### F2.3 — Smart file reading (2c) requires tool-time changes that aren't costed (P2)

Opportunity 2c depends on tool-time tracking Read patterns with line ranges, which it currently doesn't do. The brainstorm estimates "~2 hours" for adding this to tool-time. But tool-time's `summarize.py` parses JSONL conversation logs — adding line-range extraction requires parsing Read tool arguments from conversation history, aggregating across sessions, and exposing a query API. This is closer to 1-2 days.

**Recommendation:** Re-estimate 4e at 1-2 days. Consider whether the payoff (marginally smaller file reads) justifies the tool-time complexity. File reads are already cheap — the expensive part is the LLM processing the content, which doesn't change if you read 400 lines instead of 500.

### F2.4 — No measurement plan for compounding ROI (P1)

The brainstorm asks "how do we measure compounding?" as an open question but doesn't propose an answer. Without measurement, there's no way to know if any of this works. The system could surface insights that are always ignored, or save tokens that are dwarfed by the overhead.

**Recommendation:** Define the measurement plan now, not later. Minimum viable metrics: (1) insight-surfaced count per session, (2) insight-acted-on rate (did the agent's behavior change after seeing the insight?), (3) session cold-start token cost before vs. after warm-start primer. Wire these into interstat from day one.

---

## Agent 3: fd-feedback-loop-integrity

Focus: signal fidelity, feedback delay, loop closure, degradation modes.

### F3.1 — Insight extraction from conversation text is fragile (P1)

The brainstorm assumes a hook can reliably extract `insight blocks` from conversation output. But insight notices are styling conventions — there's no structured format, no delimiter, no guaranteed pattern. The extraction regex/heuristic will either miss insights (low recall) or capture non-insights (low precision). Either failure mode undermines trust in the system.

**Recommendation:** Instead of post-hoc extraction, make insight generation explicit. Define a structured output format that the agent writes *intentionally* (e.g., a tool call to `record_insight(files, keywords, content)` or a markdown block with a machine-parseable delimiter like `<!-- insight: ... -->`). This moves from "extract signal from noise" to "emit signal deliberately."

### F3.2 — Dead end capture via /reflect is a single point of failure (P2)

Dead ends are only captured if someone runs `/reflect`. The brainstorm acknowledges this but doesn't address the fundamental issue: most sessions don't run /reflect. The "compound on close" (1c) partially addresses this with a Stop hook, but it's detecting confusion signals (files read >3 times) rather than explicit dead ends.

**Recommendation:** Add a lightweight dead-end signal to the Stop hook: if a session made >2 attempts at the same file edit, or if a tool call was retried with the same arguments, tag those files as "friction points" in cass. This captures dead ends passively without requiring /reflect.

### F3.3 — Feedback loop for insight quality is missing (P2)

The brainstorm captures insights and surfaces them, but has no mechanism for feedback on whether surfaced insights were *useful*. Without this, the system accumulates low-quality insights that clutter context without helping. The open question about "insight surfaced and useful vs. surfaced but ignored" is critical but deferred.

**Recommendation:** Start with a simple implicit signal: if an insight is surfaced via `cass context` and the agent subsequently reads the same file (suggesting it needed more than the insight provided), mark the insight as "insufficient." If the agent proceeds without reading the file, mark it as "sufficient." This is coarse but automatable.

### F3.4 — No degradation mode for stale context (P2)

Warm-start primer (2b) and context warmth in routing (3a) both depend on cass being fresh. But cass health shows `stale: true` right now — the index is 67 minutes behind. If cass is stale, warm-start injects outdated context, which is worse than no context. No degradation mode is specified.

**Recommendation:** All cass-dependent features must check `cass health --json` and fall back to cold-start if `stale: true` and `age_seconds > threshold`. The threshold should be configurable but default to the session gap (if the last index is older than the last session start, the data is stale).

---

## Agent 4: fd-dispatch-intelligence

Focus: routing quality, agent selection, model optimization, dispatch feedback.

### F4.1 — Agent success patterns (3b) conflates correlation with causation (P2)

The brainstorm proposes: "fd-correctness finds 3x more issues on database code than on UI code." But finding more issues could mean (a) the agent is better at database code, or (b) database code has more bugs. Using this signal to weight agent selection would route fd-correctness *toward* buggy code domains, not toward domains where it's most *effective*.

**Recommendation:** Normalize by ground truth. The metric should be "issues found that were confirmed valid / total issues found" per domain, not raw issue count. Interspect's correction evidence already distinguishes valid findings from false positives — use the precision rate, not the volume.

### F4.2 — Model routing feedback loop (3c/4f) needs quality regression detection (P1)

Auto-routing brainstorm phases to Sonnet based on historical cost data is high-risk. The brainstorm says "no quality difference" but provides no measurement mechanism. Quality regression on brainstorm output would propagate downstream: a weaker brainstorm produces a weaker strategy produces a weaker plan. The damage compounds silently.

**Recommendation:** Model routing changes must be canary-gated, similar to interspect's existing canary system for agent routing overrides. Define quality metrics per phase (brainstorm: idea count and novelty score, review: finding precision, reflect: learning count). Run N sessions with the cheaper model and compare. Only promote after canary passes.

### F4.3 — Context warmth in routing (3a/4a) has a cold-start paradox (P2)

Prioritizing beads whose files have warm sessions biases toward recently-touched work. New beads with no session history will always lose priority to in-progress work. This creates a starvation pattern: new work never gets picked because old work always has warmer context.

**Recommendation:** Context warmth should be a *tiebreaker*, not a primary signal. Priority + phase state should remain the primary routing criteria. Warmth only matters when two beads have equal priority — then prefer the one with warm context to minimize switching cost.

### F4.4 — Failure pattern avoidance (3d) has a "learned helplessness" risk (P3)

If the system aggressively surfaces past failures ("last 3 sessions hit X error"), agents may avoid the file entirely or adopt overly cautious approaches. The signal "this failed before" doesn't mean "this will fail again" — the previous sessions may have fixed the underlying issue.

**Recommendation:** Failure warnings should include recency and resolution status. "This file had 3 failures in the last 24 hours, 2 of which were resolved" is actionable. "This file has failures" is not.

---

## Agent 5: fd-integration-surface

Focus: plugin boundaries, API contracts, dependency chains, implementation feasibility.

### F5.1 — Hook latency budget not defined (P1)

Opportunities 1a, 1c, 2a, 2b, and 3d all propose hooks (PostToolUse, Stop, PreToolUse, SessionStart). Claude Code hooks add latency to every matching event. The brainstorm doesn't specify an acceptable latency budget. A PostToolUse hook that calls `cass context` adds network + disk I/O to every tool call — potentially 100-500ms per call across hundreds of calls per session.

**Recommendation:** Define a latency budget: SessionStart hooks may take up to 2 seconds (one-time cost). Stop hooks may take up to 5 seconds (session is ending). PreToolUse and PostToolUse hooks must complete in <100ms or run asynchronously. Any hook exceeding budget must use background processing with async write-back.

### F5.2 — cass is the implicit dependency for everything, but it's a v0.2.0 external binary (P1)

Every cluster depends on cass (search, context, timeline, health, analytics). But cass is an external binary at v0.2.0 — not a Sylveste-controlled dependency. If cass changes its CLI interface, output format, or behavior, multiple systems break simultaneously. The brainstorm has no fallback for cass unavailability.

**Recommendation:** Define a cass abstraction layer — a thin wrapper (shell function or script) that all Sylveste integrations call instead of `cass` directly. This wrapper handles version checking, output format normalization, and fallback behavior (e.g., return empty results if cass is unavailable rather than failing). The intersearch plugin may already serve this role — if so, make it explicit.

### F5.3 — Plugin ownership boundaries are blurred (P2)

The brainstorm touches interseed (storage), cass (search), interstat (cost), interspect (evidence), tool-time (usage patterns), Clavain (routing, reflect, compound). But it doesn't assign ownership of each opportunity to a specific plugin. Who owns insight capture — interseed? A new plugin? Clavain?

**Recommendation:** Assign plugin ownership in the brainstorm:
- Insight capture (1a, 1b, 1c) → **interseed** (expand scope from "idea garden" to "intelligence garden") or a new `interinsight` plugin
- Token savings (2a, 2b, 2c) → **Clavain** SessionStart hook (2b) + **tool-time** (2c)
- Routing intelligence (3a-3d) → **Clavain** route.md (3a) + **interspect** (3b, 3d) + **Clavain** model-routing.md (3c)
- Low-hanging wiring (4a-4f) → assigned per-item to the owning plugin

### F5.4 — Cluster 4 effort estimates are optimistic (P2)

The brainstorm estimates 30 minutes for "add one line" changes (4a, 4b, 4c). In practice, each requires: (1) reading the current command/hook, (2) understanding the cass output format, (3) writing the integration, (4) testing, (5) handling the error case where cass is unavailable. The real effort is 1-2 hours per item, not 30 minutes.

**Recommendation:** Double the estimates for Cluster 4 items. 4a: 2 hours (route.md is complex, warmth scoring needs design). 4b: 1 hour. 4c: 1 hour. 4d: 3 hours (structured extraction is parsing work). 4e: 1-2 days (per F2.3). 4f: 4 hours (model routing canary needed per F4.2).

### F5.5 — No mention of interseed's actual current state (P2)

The brainstorm references `~/.interseed/insights.db` but interseed already exists as a shipped plugin with SQLite storage at a different path, a different schema, and a different purpose (idea lifecycle, not insight storage). The brainstorm appears unaware of interseed's current implementation.

**Recommendation:** Read interseed's CLAUDE.md and AGENTS.md before planning. Either (a) expand interseed's scope to include insight storage alongside idea storage, or (b) use a different namespace entirely. Option (b) is cleaner — insight capture is a different domain from idea refinement.

---

## Cross-Agent Convergence

Three findings appeared independently from multiple agents:

1. **Durable reflect overlap** (F1.4, F3.2): The brainstorm's Cluster 1 overlaps with the already-planned durable reflect work. Both agents flagged this. Resolution: clearly separate the capture boundaries — /reflect for deliberate learnings, hooks for incidental signals.

2. **Measurement gap** (F2.4, F3.3): Both token economics and feedback loop agents flagged the absence of quality/ROI measurement. Without measurement, the system cannot self-correct. Resolution: define metrics before implementation, wire into interstat.

3. **cass dependency risk** (F3.4, F5.2): Both feedback loop and integration surface agents flagged cass fragility. Resolution: abstraction layer with degradation mode.

---

## Priority Summary

| ID | Severity | Finding | Owner |
|----|----------|---------|-------|
| F1.4 | P1 | Duplicate capture with durable reflect | brainstorm scoping |
| F2.2 | P1 | Context cache (2a) cost-benefit inverted | brainstorm — reject 2a |
| F2.4 | P1 | No measurement plan for compounding ROI | interstat |
| F3.1 | P1 | Insight extraction from text is fragile | brainstorm design |
| F4.2 | P1 | Model routing needs quality regression detection | interspect canary |
| F5.1 | P1 | Hook latency budget undefined | brainstorm design |
| F5.2 | P1 | cass single-point dependency, no abstraction | intersearch |
| F1.1 | P1 | Insight store namespace collision with interseed | brainstorm scoping |
| F1.2 | P2 | No schema for insight records | brainstorm design |
| F1.3 | P2 | Session digest lifecycle undefined | brainstorm design |
| F2.1 | P2 | 10% token reduction claim ungrounded | pre-planning analysis |
| F2.3 | P2 | Smart file reading effort underestimated | tool-time |
| F3.2 | P2 | Dead end capture via /reflect is SPOF | Clavain Stop hook |
| F3.3 | P2 | No feedback loop for insight quality | measurement design |
| F3.4 | P2 | No degradation mode for stale cass data | integration design |
| F4.1 | P2 | Agent success patterns conflate correlation/causation | interspect |
| F4.3 | P2 | Context warmth cold-start paradox | Clavain route.md |
| F5.3 | P2 | Plugin ownership boundaries blurred | brainstorm scoping |
| F5.4 | P2 | Cluster 4 effort estimates optimistic | planning |
| F5.5 | P2 | interseed current state not referenced | brainstorm awareness |
| F4.4 | P3 | Failure pattern "learned helplessness" risk | interspect |

**Verdict:** The brainstorm identifies real problems and the opportunity clusters are well-structured. The main gaps are: (1) overlap with existing durable-reflect work that needs explicit delineation, (2) missing measurement infrastructure that should be designed alongside the features, (3) underestimated complexity especially around hook latency and cass dependency, and (4) the interseed namespace collision. Recommend addressing all P1 findings before moving to /strategy.
