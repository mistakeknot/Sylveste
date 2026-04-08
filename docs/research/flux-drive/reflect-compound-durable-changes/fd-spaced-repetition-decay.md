---
agent: fd-spaced-repetition-decay
track: adjacent
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P0] CLAUDE.md has no capacity limit or consolidation trigger

**Issue:** The brainstorm (line 78) acknowledges "CLAUDE.md could bloat if every sprint appends" and lists it as an open question (line 112), but none of the five options specify a concrete capacity threshold or consolidation mechanism. Option E (the recommended hybrid) inherits this gap. Every sprint that routes even one learning to CLAUDE.md grows the file permanently. At current sprint cadence (~3-5/week), CLAUDE.md could accumulate 50+ append-only entries within 3 months.

**Failure scenario:** CLAUDE.md exceeds the effective attention window (roughly 150-200 substantive lines based on observed agent behavior). Agents begin skimming or truncating. Recently-appended learnings at the bottom of the file have P(retrieval|need) approaching zero because they compete with the established structure at the top. The learning router produces writes that are never read — the same "dead file" problem it was designed to solve, just in a higher-stakes location.

**Fix:** Add a capacity discipline to Option E: define a hard line budget per CLAUDE.md section (e.g., max 10 entries in "Universal Gotchas"), and require that any append beyond the cap triggers a consolidation pass that merges, promotes to hooks, or archives entries with the lowest retrieval value. The router classification step should include a "capacity check" before writing.

### [P1] Routing treats all targets as equivalent without weighting by retrieval guarantee

**Issue:** The classification taxonomy in Option A (line 72) lists six targets as peer categories: `claude-md | agents-md | memory | code | hook | philosophy`. The brainstorm does not rank these by P(retrieval|need). Hooks fire automatically at trigger points — they are the only target where P(retrieval|need) approaches 1.0. Code comments are encountered exactly when the relevant code is read. CLAUDE.md is loaded once at session start but competes for attention. Memory files are loaded but rarely re-read mid-session.

**Failure scenario:** A critical behavioral rule like "never use `which` in Claude Code" (which must fire every time someone writes a detection check) is routed to a memory file instead of a hook because the agent classifies it topically rather than by retrieval urgency. The rule is loaded at session start, forgotten by mid-session, and the mistake recurs. Meanwhile, a low-stakes preference like "prefer uv over pip" correctly lands in CLAUDE.md where it does work — the system is accidentally effective for low-severity items and ineffective for high-severity ones.

**Fix:** Add a retrieval-priority ranking to the classification step. After topical classification, apply a severity filter: if the learning describes a behavior that must never/always happen, escalate the target to `hook` regardless of topical fit. The router prompt should explicitly ask: "Would passive reminder suffice, or does this need active enforcement?"

### [P1] No re-encounter strategy for high-value learnings beyond initial load

**Issue:** The brainstorm identifies `recent-reflect-learnings` as "informational, not behavioral" (line 11) and proposes replacing it with durable targets. But this eliminates the only re-encounter mechanism without replacing it. CLAUDE.md entries are read once at session start and never re-surfaced during the session. A learning placed in CLAUDE.md has exactly one retrieval opportunity per session — the moment the agent processes the system prompt.

**Failure scenario:** A learning like "close child beads when parent ships" is added to CLAUDE.md. The agent reads it at session start, begins working on an unrelated task, and 45 minutes later ships a parent bead without closing children. The learning was encountered at the wrong time — it needed to fire at ship-time, not session-start.

**Fix:** For learnings that are context-triggered (need to fire at a specific workflow moment, not at session start), the router should prefer hooks or code-level enforcement over CLAUDE.md. Add a "trigger context" field to the classification: if the learning has a specific trigger condition, it should not route to a passive-load target.

### [P2] Encoding specificity lost in classification step

**Issue:** The evidence table (lines 37-44) shows that effective learnings are context-rich: "regex `[,.\-]` splits compound words at hyphens" with a specific file reference. The classification step in Option A (line 72) reduces learnings to a category label and a one-liner. The brainstorm does not specify what metadata the router preserves when writing to the target.

**Failure scenario:** A learning about DISPATCH_CAP=1 mutation is classified as `code` and written as "# Warning: DISPATCH_CAP=1 mutates global state" in lib-dispatch.sh. Six months later, a developer encounters the comment but it lacks the failure scenario (rest of session affected) and the specific conditions that trigger the bug. The abstract warning fails to trigger recall because encoding specificity is too low.

**Fix:** Require the router to preserve three components in every write: the trigger condition (when), the consequence (what breaks), and the source (which sprint/session). The brainstorm's existing evidence table format — learning + "where it should live" — is a good template. Codify it as the minimum schema for any routed entry.

### [P3] Desirable difficulty eliminated for all learnings

**Issue:** The brainstorm frames all reflection files as "dead files" (line 28), but some friction in retrieval can be beneficial. A developer who has to search for a learning processes it more deeply than one who passively reads it in CLAUDE.md. The proposal moves all learnings to zero-friction passive loading, which may reduce deep processing.

**Failure scenario:** Over time, CLAUDE.md becomes a wall of rules that agents process mechanically without engaging with the underlying reasoning. Rules are followed literally but not understood, leading to brittle compliance that breaks in edge cases.

**Fix:** This is a design consideration, not a bug. Note in the open questions that some learnings (design principles, architectural decisions) may benefit from being in PHILOSOPHY.md or AGENTS.md where they require active search, while operational rules (gotchas, safety constraints) benefit from passive loading or hook enforcement.
