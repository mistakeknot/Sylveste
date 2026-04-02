---
artifact_type: reflection
bead: sylveste-18a.7
stage: done
---

# Reflect: Deep Research Pass — Claude Code Patterns for Skaffen

## What Worked

- **Parallel research agents** covered 8 investigation areas in 3 concurrent agents, each producing detailed findings with specific file paths, function names, and thresholds. Total research time ~2 minutes wall clock for 376K tokens of source analysis.

- **The research surfaced concrete implementation details, not just architecture descriptions.** Knowing that auto-compact triggers at `effectiveWindow - 13,000` tokens with a circuit breaker at 3 consecutive failures is actionable. Knowing that the bash classifier uses 64 max_tokens for Stage 1 with `</block>` as a stop sequence is implementable.

- **Prioritization was straightforward** once the patterns were laid out. Auto-compact is clearly P1 (prevents session crashes), while skill fork execution is P3 (nice to have).

## What We'd Do Differently

- **The initial research pass (sylveste-18a creation session) already identified the top 6 patterns.** This deep pass added 5 more (.8-.12), but the highest-impact ones (auto-compact, post-compact restoration) could have been spotted in the first pass with more time on QueryEngine.ts. The first pass focused too narrowly on the tool system.

- **Should have read QueryEngine.ts in the first session.** The 1,295-line file contains the turn lifecycle, compaction triggers, and budget tracking — all foundational for an agent runtime. We read toolOrchestration.ts and forkSubagent.ts but skipped the core loop.

## Key Lessons

1. **Context window management is the most critical missing feature in Skaffen.** Without auto-compact, long sessions silently hit the 200K token limit and fail. Claude Code's layered approach (snip → microcompact → full compact) with a circuit breaker is battle-tested.

2. **The two-stage classifier is cheaper than expected.** Stage 1 at 64 max_tokens with a stop sequence is ~50ms and costs almost nothing. Only blocks escalate to the expensive Stage 2. This makes LLM-as-judge feasible for every bash call, not just high-risk ones.

3. **Memory systems bootstrap from simple file formats.** YAML frontmatter + MEMORY.md index + keyword recall is the starting point. LLM-based semantic recall is the upgrade, not the requirement. Skaffen can ship memory with grep-based recall and add Sonnet-based filtering later.

4. **MCP transport abstraction pays off at scale.** 7 transport types seems like overengineering until you realize each unlocks a different deployment model (subprocess, remote server, in-process, IDE extension). Skaffen should add HTTP next — it unlocks team-shared tools.

5. **Research beads are lightweight sprints.** The standard 10-step sprint is too heavy for pure research. Steps 2-7 (strategy, plan, plan-review, execute, test, quality-gates) don't apply. A research-specific sprint template would save overhead.
