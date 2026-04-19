---
artifact_type: brainstorm
bead: sylveste-b49
stage: discover
---

# Brainstorm: Make Reflect/Compound Produce Durable Changes

## Problem

Reflect writes to `docs/reflections/` and compound writes to `docs/solutions/`. Neither location has automated consumers that change future behavior. The only real consumer is `recent-reflect-learnings` which displays text at sprint start — informational, not behavioral. The engineering-docs 7-step workflow is heavyweight ceremony that produces dead files.

Current flow: learning → standalone markdown file → nobody reads it → same mistake repeats

Desired flow: learning → code/config/CLAUDE.md change → future sessions behave differently

## What Would Actually Work

### Durable output targets (things that are loaded every session)

1. **CLAUDE.md / AGENTS.md** — loaded into every conversation context. Adding a line here is the highest-leverage change.
2. **Auto-memory** (`~/.claude/projects/*/memory/`) — loaded via MEMORY.md index. Good for cross-session context.
3. **Hooks** — enforce behavioral rules via code. Can prevent mistakes rather than just documenting them.
4. **Code comments / config changes** — inline documentation at the point of use. Future readers see it when they need it.
5. **PHILOSOPHY.md** — for design principle learnings.

### What doesn't work (current targets)

- `docs/reflections/` — no consumer, no search, no loading
- `docs/solutions/` — no consumer, no search, no loading
- `docs/sprints/` transcripts — archive only

## Evidence: What Existing Reflections Actually Contain

Analyzed all 18 reflection files in `docs/reflections/` (9-24 substantive lines each, median 12):

| Learning (from actual reflection files) | Where it should live | Where it is |
|---|---|---|
| "regex `[,.\-—]` splits compound words at hyphens" | Code comment on the regex in generate-agents.py | dead file |
| "Close child beads when parent ships" | CLAUDE.md or hook rule | dead file |
| "Triage should check git history for open beads" | bd doctor feature or CLAUDE.md | dead file |
| "DISPATCH_CAP=1 mutates global for rest of session" | Code comment in lib-dispatch.sh | dead file |
| "Review detection is the weak point" | AGENTS.md or PHILOSOPHY.md | dead file |
| "Plan review catches stale beads" (validation, not learning) | Nowhere — not actionable | dead file |

**Pattern:** ~80% of learnings are 1-2 sentence items that belong at a specific point of use. The remaining ~20% are design observations that could go in AGENTS.md or PHILOSOPHY.md. Almost none need a standalone document.

Also analyzed 15+ solution files in `os/Clavain/docs/solutions/`. Same pattern — the useful ones (like heredoc-permission-bloat) were already acted on and added to CLAUDE.md. The standalone file is now redundant.

## Interactive Findings

User confirmed three failure modes (not "busywork" — the phase has value, the output is wrong):
1. **Same mistakes repeat** — learnings don't reach places that are loaded
2. **Learnings are too generic** — vague "we learned to plan better" instead of specific actionable changes
3. **Wrong granularity** — heavyweight process for what's usually a one-liner

All four prevention mechanisms are needed depending on context:
- CLAUDE.md line (project-level gotchas)
- Hook that blocks it (behavioral enforcement)
- Code change (warnings, defaults, assertions)
- Memory file (cross-project user preferences)

**Archive decision:** Keep both — route to durable target AND keep archive. The archive provides "when did we learn X?" audit trail.

**Compound decision:** Still open (interrupted before answering).

## Options and Alternatives

### Option A: Learning Router (route-first, archive-second)

Replace the "write a reflection document" step with a classification + routing step:
1. Extract 1-5 learnings from the sprint
2. Classify each: `claude-md` | `agents-md` | `memory` | `code` | `hook` | `philosophy`
3. Write each to its target (append to CLAUDE.md, add code comment, write memory file, etc.)
4. Optionally append a one-liner to a lightweight log file for audit trail

**Pros:** Learnings immediately affect future behavior. Simple to implement — just change the reflect command prompt. No Go code changes needed.
**Cons:** Classification quality depends on agent judgment. CLAUDE.md could bloat if every sprint appends. No structured search across learnings.

### Option B: Durable Change Gate (enforce behavioral output)

Same as Option A but with a hard gate: the ship step checks that at least 1 file outside docs/reflections/ was modified by the reflect step (CLAUDE.md, code file, memory file, etc.). Reflection files alone don't satisfy the gate.

**Pros:** Enforces the desired behavior. Can't game it with a generic reflection file.
**Cons:** What about sprints where the learning is "everything worked as expected"? Need an escape hatch for no-learning sprints.

### Option C: Knowledge Index (make dead files searchable)

Instead of changing where learnings go, make the existing locations discoverable. Add search/index over docs/reflections/ and docs/solutions/ so future agents can find relevant learnings.

**Pros:** No workflow changes. Preserves existing content. Structured search.
**Cons:** Doesn't solve the core problem — agents still have to actively search rather than passively loading context. More infrastructure to build and maintain.

### Option D: Compound Merge (merge reflect + compound into one phase)

Reflect and compound are doing the same thing from different angles. Merge them: one phase that (1) extracts learnings, (2) routes each to its durable target, (3) optionally writes a solutions/ doc for complex multi-step debugging solutions only.

**Pros:** Simpler workflow (one phase instead of two). Compound is rarely invoked standalone anyway.
**Cons:** Loses the distinction between "sprint-end reflection" and "problem-was-solved documentation." Some compound use cases (auto-triggered by hooks) don't fit neatly in the sprint lifecycle.

### Option E: Hybrid (A + B + partial D)

Recommended combination:
- **Reflect** uses the learning router (Option A) with the durable change gate (Option B)
- **Compound** keeps its identity but also uses the learning router — routes to point-of-use first, solutions/ doc as optional archive
- Gate has an escape hatch: "no actionable learnings" is valid if explicitly stated (not just an empty reflect)
- Archive is an append-only lightweight log, not a full reflection document

## Open Questions

- How to handle CLAUDE.md bloat over time? (Periodic pruning? Section size limits?)
- Should the classification be explicit (agent picks target) or implicit (agent just writes the learning and the system routes it)?
- What about compound's auto-trigger from hooks — does it still write to solutions/ in that mode?
- How does `recent-reflect-learnings` (Go code in clavain-cli) adapt? Does it read from CLAUDE.md git history instead of reflection files?
