---
agent: fd-zettelkasten-link-density
track: adjacent
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] No deduplication mechanism across targets

**Issue:** The learning router in Option A (line 70-78) classifies and writes learnings to targets, but none of the five options describe a deduplication check before writing. The brainstorm's own evidence table shows the pattern already occurring: "Close child beads when parent ships" could independently surface from multiple sprints (parent-close is a recurring workflow step). The same learning routed to CLAUDE.md three times over three months produces three entries.

**Failure scenario:** Sprint 47 learns "always check git history for open beads before triage." Sprint 53 encounters the same problem and learns "triage should check git history for open beads." Sprint 61 discovers it again: "verify no open beads before triage step." CLAUDE.md now has three entries saying the same thing in slightly different words. Cross-target duplication is worse: the same learning exists in CLAUDE.md, a memory file, and a code comment — all slightly different, none authoritative.

**Fix:** Before writing any learning, the router must search existing content in all targets (CLAUDE.md, AGENTS.md, memory files) for semantic overlap. If a match is found, the router should strengthen the existing entry (add context, update date) rather than append a new one. Add a `# Existing knowledge check` step to the router prompt that requires the agent to grep for related content before writing.

### [P1] No atomicity constraint on routed learnings

**Issue:** Option A step 1 says "Extract 1-5 learnings from the sprint" (line 71) but does not define what constitutes a single learning. The evidence table (lines 37-44) shows a mix of granularities: some are atomic ("regex splits at hyphens") while others are compound ("Review detection is the weak point" — which encompasses detection timing, signal quality, and threshold tuning).

**Failure scenario:** A compound learning like "sprint planning needs better scope control" is routed to CLAUDE.md as a single entry. Six months later, half of the insight is obsolete (scope estimation was fixed by a new tool) but the other half is still valuable (the checklist step). The entry cannot be partially deprecated — it rots as a unit, and eventually the whole thing is pruned because it looks stale.

**Fix:** Add an atomicity test to the classification step: each learning must address exactly one specific behavior, in one specific context, with one specific fix. If a learning contains "and" joining two distinct insights, it must be split before routing. The brainstorm's evidence format — one row per learning — naturally enforces this; codify it as a constraint.

### [P1] Write-only graveyard pattern shifts location but persists

**Issue:** The brainstorm correctly diagnoses that `docs/reflections/` is a write-only graveyard (line 29). But the proposed fix — routing to CLAUDE.md and memory files — only changes the graveyard location. Neither Option A nor Option E includes any mechanism to track whether routed learnings are actually retrieved or influence behavior in subsequent sessions. There is no feedback loop that distinguishes effective placements from ineffective ones.

**Failure scenario:** After 6 months, MEMORY.md accumulates 80 entries. A spot check reveals that 60% have never influenced a session decision (they are loaded but never referenced in agent reasoning). The system dutifully routes learnings to "durable" targets, but without retrieval tracking, there is no signal to distinguish valuable entries from noise. Pruning is impossible without manual audit.

**Fix:** Add a lightweight retrieval signal: when an agent references a CLAUDE.md or memory entry in its reasoning (e.g., "per CLAUDE.md rule about X, I will..."), log the entry as "retrieved." Entries with zero retrievals after N sessions become candidates for archival or consolidation. This does not need to be built at brainstorm stage, but it should be listed as a required follow-up in the design.

### [P2] Fixed taxonomy cannot accommodate novel knowledge types

**Issue:** The classification taxonomy (line 72) has six fixed targets: `claude-md | agents-md | memory | code | hook | philosophy`. The brainstorm does not address what happens when a learning does not fit any category. For example, a learning about inter-plugin interaction patterns might belong in a plugin-specific CLAUDE.md, or a learning about CI behavior might belong in a CI config comment — neither is in the taxonomy.

**Failure scenario:** The router forces a CI-specific learning ("GitHub Actions caches expire after 7 days, always pin versions") into the closest category (`code`), where it gets written as a comment in an unrelated source file. The learning is never encountered because the relevant code path is in `.github/workflows/`, not in the file where the comment was placed.

**Fix:** Allow the taxonomy to include a `propose-target` escape hatch: if none of the six categories fit, the router can propose a specific file path and justify why. This preserves the structured taxonomy while allowing adaptation. The brainstorm's open question about explicit vs. implicit classification (line 113) should resolve toward explicit-with-escape.

### [P2] No cross-reference linking between related learnings

**Issue:** None of the five options describe linking related learnings across targets. A learning in CLAUDE.md about "never use `which`" is related to a code comment in a detection function and a hook that validates binary checks — but there is no link between them. Each entry is an island.

**Failure scenario:** A developer updates the hook (because the tool name changed) but does not update the CLAUDE.md entry or the code comment. The three representations of the same knowledge drift apart. Without links, there is no way to discover that updating one requires updating the others.

**Fix:** When routing a learning to multiple targets (or when a learning relates to an existing entry in another target), include a cross-reference comment: `# See also: CLAUDE.md "binary detection" section` or `# Related hook: validate-binary-check`. This is low-cost and prevents drift between related entries.
