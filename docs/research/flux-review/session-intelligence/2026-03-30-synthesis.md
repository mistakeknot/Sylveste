---
artifact_type: review-synthesis
method: flux-review
target: "docs/brainstorms/2026-03-30-session-intelligence-compounding-brainstorm.md"
target_description: "Session intelligence compounding — cass, interstat, interspect, interject integration for token savings, quality, and learning"
tracks: 4
track_a_agents: [fd-session-memory-architecture, fd-token-economics, fd-feedback-loop-integrity, fd-dispatch-intelligence, fd-integration-surface]
track_b_agents: [fd-clinical-case-reasoning, fd-broadcast-engineering, fd-intelligence-analysis, fd-newsroom-workflow]
track_c_agents: [fd-oral-tradition-memory, fd-monastic-scriptoria, fd-cartographic-wayfinding, fd-fermentation-culture]
track_d_agents: [fd-raga-melodic-grammar, fd-tibetan-memory-palace, fd-tidal-resonance]
date: 2026-03-30
---

# Synthesis: Session Intelligence Compounding

4 tracks, 16 agents, ~55 findings. This synthesis extracts the highest-signal patterns, with cross-track convergence ranked first.

## Cross-Track Convergence (found independently in 2+ tracks)

### 1. No confidence/provenance model — the #1 structural gap (4/4 tracks)

Every track independently flagged this. The brainstorm stores insights without reliability grading, provenance chains, or retraction mechanisms.

- **Track A** (fd-session-memory-architecture): "No schema for insight records" — missing `source_agent`, `session_id`, `confidence`
- **Track B** (fd-clinical, fd-intelligence, fd-newsroom): "Ungraded multi-source data produces worse decisions than no data" — NATO source reliability codes (A-F), clinical evidence grading, newsroom byline accountability all exist precisely because this failure was catastrophic in those fields
- **Track C** (fd-oral-tradition, fd-monastic-scriptoria): "Provenance decay is structural, not incidental" — griot lineage tags, scriptorium exemplar chains — authority degrades with derivation depth
- **Track D** (fd-raga): Distinguishes vadi (load-bearing) from samvadi (contextualizing) from gamaka (named exceptions) — structural roles, not just quality grades

**Convergence score: 4/4 — highest confidence finding.**

Minimum viable schema for any stored insight artifact:
```
id, session_id, source_agent, confidence (low/medium/high),
insight_role (vadi/samvadi/gamaka), domain (file paths),
inquiry_direction (ascending/descending/ornamental),
expires_at (or is_evergreen: true), superseded_by (nullable)
```

### 2. Missing maintenance layer — the system has no immune system (3/4 tracks)

- **Track B** (fd-broadcast): "No pipeline health monitoring" — hooks can fail silently with no detection
- **Track C** (fd-fermentation): "Passaging is not error recovery; it is the mechanism by which the culture remains viable" — periodic pruning of low-value insights is normal operation
- **Track C** (fd-fermentation): "pH as leading indicator" — no early-warning signals for store quality degradation; only lagging metrics (cost, completion rate)
- **Track D** (fd-tibetan-mandala): Mandala destruction as final teaching — value is in cognitive apparatus, not the persistent artifact

**Convergence score: 3/4.** The brainstorm has capture and retrieval but no maintenance. Leading indicators needed: insight-used/insight-skipped ratio, dead-end re-encounter rate, session digest growth rate.

### 3. Activation gating > retrieval (3/4 tracks)

- **Track C** (fd-oral-tradition): Call-and-response priming — "the signal that matters is not recency but entry mode"
- **Track C** (fd-monastic-scriptoria): Chapter reading protocol — "different insight types should have different activation schedules keyed to context transitions"
- **Track D** (fd-tidal): 5-tool-call cycle classifier — "detect which constituent is active and inject context appropriate to that phase"

**Convergence score: 3/4.** The brainstorm is retrieval-based (search the store, inject results). Three domains say: gate first, retrieve second. Determine session type from entry signals before deciding what to surface.

### 4. Reject Opportunity 2a (full context cache) — cost-benefit inverted (2/4 tracks)

- **Track A** (fd-token-economics): "Hook overhead on every Read call likely exceeds savings"
- **Track B** (fd-broadcast): "Buffer overrun (stale cache injection) more costly than underrun (cold read)"
- **Track C** (fd-monastic-scriptoria): "Summary is a derived copy; authority degrades with each generation"

**Convergence score: 2/4 explicit, 1 supporting.** Kill 2a. The warm-start primer (2b) achieves 80% of value at 5% complexity.

### 5. Data flows too long — keep signals independent, combine linearly (2/4 tracks)

- **Track D** (all three agents): "Multi-hop flows compound fitting error. Raga grammar is compact. Mandala encodes invisibly. Tidal prediction decomposes into non-interacting constituents."
- **Track B** (fd-intelligence): "Correlated source collapse: interspect + interstat + reflect from the same session = n=1, not n=3"

**Convergence score: 2/4.** Architect the system as independent signal layers that combine at the output, not as a pipeline where each stage feeds the next.

## Critical Findings (P0/P1)

| Finding | Track | Agent(s) | Recommendation |
|---------|-------|----------|----------------|
| No confidence/provenance on stored insights | B | clinical, IC, newsroom | Add schema fields from day one |
| No pipeline health monitoring | B | broadcast | Instrument hook execution: success/failure/latency per hook |
| No consumption feedback loop | B | IC, broadcast | Track behavioral divergence (per mandala), not retrieval hits |
| Overlap with durable-reflect work (sylveste-b49) | A | session-memory | Delineate: /reflect owns deliberate learnings, hooks own incidental signals |
| Opportunity 2a cost-benefit inverted | A | token-economics | Reject 2a explicitly, not defer |
| Insight extraction from prose is fragile | A | feedback-loop | Use deliberate structured output, not post-hoc regex |
| Hook latency budget undefined | A, B | integration, broadcast | SessionStart <2s, Stop <5s, Pre/PostToolUse <100ms or async |
| cass is single-point dependency with no abstraction | A | integration | Wrap in thin abstraction; degrade gracefully on unavailability |
| Model routing needs canary gating | A | dispatch | Measure phase-specific quality before auto-routing to cheaper models |
| interseed namespace collision | A | session-memory, integration | Use separate namespace for insight storage, not interseed |

## Domain-Expert Insights (Track A)

- **Token economics**: Run `cass analytics tokens` to decompose where tokens actually go before setting savings targets. The "10% reduction" claim is ungrounded without this baseline.
- **Dispatch intelligence**: Context warmth must be a tiebreaker, not a primary signal. Priority inversion (warm P2 over cold P0) is the main risk. And agent success profiles need precision-rate normalization (issues-confirmed-valid / total-issues), not raw volume.
- **Feedback loops**: Dead-end signals need expiration based on code changes since capture, not just time. And the "learned helplessness" risk (agents over-avoiding files with past failures) needs resolution status in failure warnings.

## Parallel-Discipline Insights (Track B)

- **Clinical medicine**: I-PASS structured handoff protocol reduces medical errors 30%. The handoff_latest.md prose blob will fail the same way unstructured verbal handoffs fail. Structure matters as much as presence.
- **Intelligence analysis**: Collection vs. production must be separated — /reflect produces collection artifacts; insight extraction is a production step. Conflating them prevents quality auditing. Also: Analysis of Competing Hypotheses (ACH) should apply to agent success profiles to counter confirmation bias.
- **Broadcast engineering**: Use content hash or git SHA for cache invalidation, never mtime. And define channel capacity for context injection — unbounded warm-start can flood the context window.
- **Newsroom workflow**: The morgue (cass) only works if pre-research is mandatory and scannable in <2 minutes. Corrections must propagate — a `superseded_by` field is non-negotiable.

## Structural Insights (Track C)

- **Griot oral tradition**: Dead ends need 3 subtypes with different retrieval urgency: (a) abandoned for performance, (b) ruled out on principle, (c) caused harm and was reverted. Only (c) warrants a PreToolUse warning.
- **Monastic scriptoria**: Hard structural separation between primary sources (files, git) and derived annotations (insights, summaries). Never merge them in retrieval. Gloss creep is the specific failure mode.
- **Polynesian wayfinding**: Agent profiles should be running models (incrementally updated), not on-demand computations from raw tables. And swells — out-of-band signals from interject/upstream changes — are missing from the signal layer entirely.
- **Fermentation science**: Terroir (locality bounds) — some intelligence is deliberately scoped to specific files/modules. Retrieval that crosses a locality bound should surface a warning, not a transparent match.

## Frontier Patterns (Track D)

- **Raga grammar**: Unify Opportunities 1a/1b/1c into one grammar-aware schema with `insight_role` (vadi/samvadi/gamaka) and `inquiry_direction` (ascending/descending/ornamental). This collapses three separate stores into one structurally-aware schema. Dead ends are gamaka — named exceptions within the grammar, not a separate category.

- **Tibetan mandala**: Measure behavioral divergence, not retrieval hits. Compare cost-to-landable-change with vs. without warm context. Implement warm-context as silent pre-flight enrichment. Add `builder_affinity` to bead state — the agent that did deep constructive work on files should be routed back to those files.

- **Tidal harmonics**: Implement a 5-tool-call cycle classifier at session start to detect implementation/debugging/architecture/refactoring mode. Same file + different cycle = different context injection. And enforce a Rayleigh criterion of n=15 minimum observations per agent-type × task-domain cell before using for routing.

## Synthesis Assessment

**Overall quality of the brainstorm:** The opportunity clusters are well-identified and the 4-cluster structure is sound. The brainstorm correctly identifies the core problem (sessions are stateless islands) and proposes reasonable solutions. The main weaknesses are: (1) no data model, (2) no maintenance architecture, (3) overlap with existing durable-reflect work, and (4) effort underestimates.

**Highest-leverage improvement:** Define the insight schema (with provenance, roles, directions, expiry) before building anything. Every other feature depends on what an insight record looks like. The raga-derived schema is the most elegant proposal: `insight_role` + `inquiry_direction` unifies three stores into one.

**Surprising finding:** The mandala's reframing of the measurement problem. "Track behavioral divergence, not retrieval hits" is a fundamentally different measurement approach that no single adjacent-domain track would surface. It converts an open question ("how do we measure compounding?") into a testable hypothesis ("does warm context injection lower cost-to-landable-change?") using infrastructure that already exists (interstat).

**Semantic distance value:** The outer tracks (C/D) contributed qualitatively different insights. Track A identified *what's missing* (schema, measurement, overlap). Tracks C/D identified *what kind of thing to build* (grammar not store, maintenance not cleanup, classifier not aggregator). The convergence between C and D on "keep signals independent, combine linearly" was the strongest structural recommendation and would not have emerged from adjacent review alone.
