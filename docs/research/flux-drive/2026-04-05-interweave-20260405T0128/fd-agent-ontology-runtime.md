### Findings Index
- P1 | AOR-1 | "Features (general)" | No concrete capability delta over existing tools — PRD does not prove agents need interweave
- P1 | AOR-2 | "F5: Named Query Templates" | Bootstrap problem: agents must know entity types to query, but the ontology IS the type knowledge
- P2 | AOR-3 | "F5: Named Query Templates" | 6 MCP tools impose discovery overhead on agents — may exceed the cost of direct subsystem queries
- P1 | AOR-4 | "F7: Gravity-Well Safeguards" | Finding-aid test is necessary but insufficient — behavioral dependency matters more than data dependency
- P2 | AOR-5 | "F6: Query-Context Salience" | Context detection via explicit parameter requires agents to self-classify their task, which they do poorly
Verdict: needs-changes

## Summary

The PRD correctly identifies a real problem: agents cannot ask "show me everything connected to this function" because entity relationships are siloed. The solution — named query templates via MCP tools — is the right architectural shape for agent consumption. However, the PRD fails to demonstrate that the proposed capability is materially better than what agents can already do with existing tools (cass search + bd list + grep). The "~800 tokens for manual multi-tool queries" claim needs substantiation. If the cost delta is <200 tokens, agents won't prefer interweave over familiar tools, and the entire system becomes shelfware. The bootstrap problem (agents must understand the ontology to use it) is real and unaddressed.

## Issues Found

### 1. [P1] No concrete capability delta over existing tools (AOR-1)

**File**: `docs/prds/2026-04-05-interweave.md`, Problem statement, lines 9-11

"Cross-system context requires manual multi-tool queries that cost ~800 tokens and still miss relationships."

This is the central value proposition, but the PRD does not demonstrate it with a concrete example. What specific workflow is impossible or significantly worse without interweave? The PRD should include at least 2-3 "before/after" scenarios:

**Example that should be in the PRD:**
- **Before**: Agent debugging a test failure in `src/auth.py::validate_token`. Runs `cass search "validate_token"` (200 tokens), `bd list | grep auth` (150 tokens), `grep -r validate_token` (300 tokens). Gets 3 partial views. Misses that a flux-drive review from 2 weeks ago flagged this exact function for a race condition (would have required `ls docs/research/flux-drive/*/fd-*.md | xargs grep validate_token`, which the agent doesn't know to do).
- **After**: Agent runs `related-work validate_token` + `review-findings validate_token`. Gets the bead, the review finding, and the recent sessions in 2 queries / ~400 tokens. The race condition warning surfaces.

Without this kind of scenario, the PRD is an abstract architecture document, not a product requirements document.

**Recommendation**: Add a "Scenarios" section between Problem and Solution with 3 concrete before/after examples, including token counts and the specific information gap that interweave closes.

### 2. [P1] Bootstrap problem unaddressed (AOR-2)

**File**: `docs/prds/2026-04-05-interweave.md`, F5, lines 78-88

To use `related-work <entity>`, an agent must know:
- That interweave exists (tool discovery)
- What entity identifier format to use (file path? bead ID? canonical ID?)
- What results to expect (entities from which subsystems, in what format)

Tool discovery is handled by MCP — agents see the tool list. But knowing WHEN to use interweave vs. a direct subsystem query requires understanding the ontology's value proposition. This is the bootstrap problem: the ontology is most useful when the agent already understands the cross-system relationships, but understanding those relationships is exactly what the ontology provides.

In practice, agents with access to 10+ MCP tools tend to use the 3-4 they have the most experience with (cass search, grep, Read). Adding 6 more tools does not guarantee adoption — it fragments the agent's decision space.

**Failure scenario**: Agents are given access to 6 interweave MCP tools. In 80% of cases, agents continue using `cass search` and `grep` because those tools are simpler, more predictable, and already well-represented in training data. Interweave tools are invoked occasionally but never become the default pathway. The maintenance cost of the ontology is paid; the query benefit is not realized.

**Recommendation**: Address bootstrap with a routing hint strategy. Rather than exposing 6 generic tools, expose 1 tool (`interweave-context <entity>`) that returns the most relevant cross-system context based on the entity type and agent context. This is effectively F6's salience feature baked into the primary tool. Agents learn one tool, not six. Alternatively, add to F5: "MCP tool descriptions include concrete examples of when to use this tool vs. direct subsystem queries." Tool descriptions are the agent's only guide — they must be precise about the capability delta.

### 3. [P2] 6 MCP tools impose discovery overhead (AOR-3)

**File**: `docs/prds/2026-04-05-interweave.md`, F5, lines 78-84

Each MCP tool occupies ~50-100 tokens in the agent's tool description context. 6 tools = 300-600 tokens of permanent context overhead in every session where interweave is loaded. If the average session issues 0.5 interweave queries, the break-even is only reached when the query saves >600 tokens compared to the manual approach.

Sylveste already has a large MCP tool surface (interlens, interrank, intercache, intersearch, etc.). Each new tool set adds to the context pressure that interpulse tracks.

**Recommendation**: Consider consolidating the 6 tools into 2-3: `interweave-context <entity>` (combines related-work + recent-sessions + review-findings based on salience), `interweave-chain <entity>` (causal-chain), and `interweave-evidence <entity>` (evidence-for + who-touched). This reduces context overhead by 50% while preserving the full capability.

### 4. [P1] Finding-aid test is necessary but insufficient (AOR-4)

**File**: `docs/prds/2026-04-05-interweave.md`, F7, lines 106-109

"Finding-aid audit script: `interweave audit` deletes the entire index, verifies all subsystems still function, and rebuilds."

This tests data dependency: can subsystems function without interweave's data? Good. But it does not test behavioral dependency: do agents still function effectively without interweave's tools?

If agents are trained/prompted to use `related-work` instead of direct `cass search + bd list` queries, and interweave becomes unavailable, the agent doesn't fall back — it either retries the failed tool or gives up. The "direct access documentation" criterion (line 109) addresses this in theory, but in practice, agent prompts rarely include "if tool X is unavailable, do Y instead" fallback logic.

**Failure scenario**: Interweave MCP server crashes mid-session. Agent has already been using `related-work` successfully. Next query fails. Agent retries 3 times, burns 1500 tokens on retries, then reports "I couldn't find related work." The agent doesn't know to fall back to `cass search + bd list + grep`.

**Recommendation**: Add to F7 acceptance criteria: "Graceful degradation test: disable the interweave MCP server. Verify that agent skill files and CLAUDE.md include explicit fallback instructions ('if interweave is unavailable, use: cass search X, bd list --filter Y, grep Z'). Test that agents successfully complete cross-system queries using fallback paths." This aligns with PHILOSOPHY.md's "standalone plugins fail-open" principle.

### 5. [P2] Context detection requires agent self-classification (AOR-5)

**File**: `docs/prds/2026-04-05-interweave.md`, F6, lines 95-99

"Context detection: explicit parameter (`--context=debugging`) as primary method."

This requires the agent to correctly classify its own task as "debugging", "planning", or "reviewing" and pass the appropriate parameter. In practice:
- Agents often don't have clear task boundaries — a session might start as debugging, shift to planning, and end with reviewing.
- The agent must know that the `--context` parameter exists and what each mode does — more bootstrap knowledge.
- If the agent doesn't pass `--context`, it gets "general" (balanced), which may be the worst option for specialized tasks.

**Recommendation**: Consider ambient context detection: if the agent recently invoked `cass search` or `grep` with error-related terms, infer `debugging`. If the agent recently used `bd create` or `bd list`, infer `planning`. If the agent invoked `interflux:flux-drive`, infer `reviewing`. This can be a soft signal (overridable by explicit `--context`) that provides better defaults without requiring agent self-classification. Add this as a "future iteration" note in F6 or as an open question.

## Improvements

1. **Add a "tool adoption metric" to F7 health.** Track how often each interweave MCP tool is invoked vs. direct subsystem queries across sessions. If `related-work` is used <10% as often as `cass search` for the same entities, the tool isn't providing sufficient value over the existing approach. This is the closed-loop measurement that PHILOSOPHY.md demands.

2. **Include a token budget comparison in F5.** For each of the 6 named queries, specify: (a) what the equivalent manual query sequence looks like, (b) how many tokens the manual approach costs, (c) how many tokens the interweave approach costs. This makes the value proposition testable and quantifiable.

3. **Consider a "suggested next query" feature.** After returning results for `related-work <entity>`, include a 1-line suggestion: "For causal context, try: causal-chain <entity>". This addresses the discovery/bootstrap problem by guiding agents through the tool surface incrementally.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 3, P2: 2)
SUMMARY: The PRD does not demonstrate a concrete capability delta over existing tools — agents need proof that interweave queries are materially better than cass+beads+grep, and the bootstrap problem (6 new MCP tools to learn) is unaddressed.
---
<!-- flux-drive:complete -->
