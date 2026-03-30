---
artifact_type: brainstorm
bead: none
stage: discover
---

# Session Intelligence Compounding

How to use session data (cass, interstat, interspect, interject) to save tokens, improve coding quality/reliability, and compound learnings across sessions.

## The Problem

Sylveste generates enormous session intelligence — every conversation produces insights, dead ends, architectural decisions, tool usage patterns, and cost data. This data is indexed (cass), metrics are tracked (interstat), agent evidence is collected (interspect), and external discoveries are scanned (interject). But almost none of it flows back to change behavior. Sessions are stateless islands connected by git commits and memory files.

**What we lose today:**
- Insight notices (educational content about code choices) die with the conversation
- Dead ends are only captured if someone runs /reflect — and even then, they're prose in a doc, not searchable signals
- Token waste from re-reading files that a session 20 minutes ago already summarized
- Dispatch decisions (which agent, which model) ignore historical success/failure patterns
- No "this file was just changed and tested" signal → next session re-reads and re-tests the same code

## Cluster 1: Insight Compounding

### The Signal: ★ Insight Notices

Every session in explanatory mode produces `★ Insight` blocks — 2-3 educational points about implementation choices. Currently these are styling-only: not persisted, not indexed, not searchable. They vanish when the conversation closes.

### Opportunity 1a: Insight Capture Hook

A PostToolUse or Stop hook that extracts `★ Insight` blocks from the conversation, writes them to a structured store (SQLite or markdown), and tags them with file paths and keywords. When a future session reads the same file, the relevant insights surface as context.

**Data flow:** Session output → hook extracts insight blocks → write to `~/.interseed/insights.db` or `docs/solutions/` → cass indexes → future `cass search` or `cass context <file>` surfaces them.

**Why this matters:** Insights encode *why* code was written a certain way — the design rationale, the tradeoff, the alternative considered. This is exactly what gets lost between sessions and what a new agent needs most.

### Opportunity 1b: Dead End Capture

Similar to insights, but for failed approaches. Today, dead ends are captured only in /reflect output (prose) and /handoff (manual). They could be structured and searchable.

**Data flow:** /reflect already writes learnings → add structured extraction (approach, failure reason, file paths, keywords) → write to `docs/solutions/` with `category: dead-end` → cass indexes → future sessions get "this was tried and didn't work" before attempting the same thing.

### Opportunity 1c: Compound on Close

When a session closes (Stop hook), automatically scan for high-signal patterns: files read >3 times (confusion signal), tools retried (friction signal), insights generated (knowledge signal). Write a structured session digest that downstream systems can consume.

**Data flow:** Stop hook → scan conversation for signals → write session digest to `~/.cass/digests/<session_id>.md` → cass indexes → future `cass context` includes digests.

## Cluster 2: Token Savings via Context Reuse

### The Waste

Every session starts cold. It reads CLAUDE.md, reads files, greps for patterns, builds mental models — even when a session 30 minutes ago did exactly the same work. With 785 sessions at $2.93 per landable change, even 10% token reduction is significant.

### Opportunity 2a: Session Context Cache

Before reading a file, check cass for recent sessions that summarized it. If a session <2 hours ago read and analyzed the same file (and the file hasn't changed since), inject the prior session's summary instead of re-reading.

**Data flow:** Agent about to Read file → hook calls `cass context <file> --json --limit 1` → if recent + file unchanged (check mtime) → inject cached summary as context → skip full Read.

**Complexity:** High — requires hooking into the Read tool path and managing cache invalidation. Risk of stale summaries.

### Opportunity 2b: Warm Start Primer

Simpler version of 2a: at session start, if there's a recent handoff or session digest for the current project, inject it as initial context. Not file-level caching, just "here's what the last agent knew."

**Data flow:** SessionStart hook → check `docs/handoffs/latest.md` or `cass timeline --today --json` → if recent session exists → inject summary as additionalContext.

**This partially exists** — the handoff_latest.md auto-memory file we just built does this. But it only captures what /handoff explicitly writes, not the full session context.

### Opportunity 2c: Smart File Reading

Instead of reading entire files, use cass to identify which sections are relevant based on prior session patterns. If 5 sessions all only read lines 100-200 of a 500-line file when working on feature X, suggest reading only that range.

**Data flow:** cass analytics on Read tool usage → aggregate file:line patterns per topic → inject as guidance ("when working on X, focus on lines 100-200 of file Y").

**Complexity:** Medium — requires tool-time to track Read patterns with line ranges, which it currently doesn't.

## Cluster 3: Routing Intelligence

### The Gap

Dispatch decisions (which work to do, which agent to use, which model) are currently based on priority + phase state + recency metadata. They ignore historical outcomes — which agents succeeded on which task types, which models are most cost-effective for which phases, which files are "hot" right now.

### Opportunity 3a: Context Warmth in Routing (already planted as interseed idea)

Wire `cass context <file>` into /route discovery scan so bead prioritization considers which files have warm sessions. Lower switching cost → higher throughput.

### Opportunity 3b: Agent Success Patterns

Interspect collects agent evidence (corrections, successes, overrides). Interstat tracks cost by agent type. Combine these to build agent profiles: "fd-correctness finds 3x more issues on database code than on UI code" or "Codex delegates succeed on isolated tasks but fail on cross-module work."

**Data flow:** interspect evidence + interstat cost → agent profile scores per domain → flux-drive triage uses profiles to weight agent selection → fewer wasted agent dispatches.

**This partially exists** — interspect has correction evidence and routing overrides. The gap is connecting interspect patterns to proactive triage (before dispatch), not just reactive routing (after failures).

### Opportunity 3c: Model Cost Optimization

Interstat tracks cost by model per phase. Some phases (brainstorm, reflect) may not need Opus. Historical data can suggest: "brainstorm phases cost 40% less on Sonnet with no quality difference" → auto-route to cheaper models for known-safe phases.

**Data flow:** interstat cost-by-phase-model data → compute quality-adjusted cost per model per phase → clavain model-routing uses historical data instead of static rules → lower cost without quality regression.

**This partially exists** — `/clavain:model-routing` has economy vs quality modes, but they're manually toggled, not data-driven.

### Opportunity 3d: Failure Pattern Avoidance

When a session encounters a specific error or dead end, tag it in cass. When a future session is about to work on the same file/feature, surface: "Last 3 sessions on this file hit X error — check Y first."

**Data flow:** /reflect dead ends + session error signals → tagged in cass by file/feature → PreToolUse hook checks `cass context <file>` for failure tags → inject warning before agent proceeds.

## Cluster 4: Low-Hanging Fruit (Missing Wiring)

These require no new infrastructure — just connecting existing systems:

### 4a: /route → cass context warmth
Already described. Effort: ~1 hour. Wire `cass context` into route.md discovery scan.

### 4b: /work → cass file context
`/work` Phase 1b uses `cass search` for keywords but not `cass context <file>` for file-level prior sessions. Add one line. Effort: ~30 min.

### 4c: SessionStart → inject recent handoff
The handoff_latest.md auto-memory file exists but SessionStart doesn't explicitly check for it. It's loaded via MEMORY.md already, but a dedicated "last session summary" in additionalContext would be more prominent. Effort: ~30 min.

### 4d: /reflect → structured dead end extraction
/reflect produces prose. Adding a structured JSON sidecar (approach, reason, files) to each reflection would make dead ends machine-searchable. Effort: ~2 hours.

### 4e: tool-time → Read pattern analysis
tool-time tracks tool usage but not file:line patterns. Adding line range tracking to Read tool analytics would enable smart file reading (2c). Effort: ~2 hours.

### 4f: interstat → model routing feedback loop
interstat has cost-by-phase-model data. `/clavain:model-routing` has economy/quality modes. Connecting them so model routing uses historical cost data would close the loop. Effort: ~3 hours.

## Key Decisions

- **Insights are the highest-signal, lowest-effort compounding opportunity.** They encode design rationale that's currently lost. A simple extraction hook + cass indexing makes them searchable forever.
- **Token savings via full context caching (2a) is high-risk.** Cache invalidation is hard. Start with warm-start primer (2b) and smart file reading (2c) instead.
- **Low-hanging wiring (Cluster 4) should ship first.** 4a-4c are 30-60 min each and deliver immediate value. Do these before building new systems.
- **Agent success patterns (3b) are the most strategically valuable** but require interspect + interstat integration work. Medium-term.

## Open Questions

- Should insight capture be a hook (automatic) or a skill (on-demand)? Hook is more complete but adds latency to every tool call.
- Should the insight store be a new SQLite DB, or should insights be written as docs/solutions/ markdown files that cass naturally indexes?
- How do we measure compounding? Track "insight surfaced and useful" vs "insight surfaced but ignored" for calibration.
- Should model routing optimization be fully automated or human-approved? Risk of optimizing for cost at the expense of quality on edge cases.
