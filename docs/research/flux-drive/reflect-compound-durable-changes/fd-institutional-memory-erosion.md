---
agent: fd-institutional-memory-erosion
track: adjacent
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] No expiration conditions or staleness detection on routed entries

**Issue:** The brainstorm proposes routing learnings to durable targets (CLAUDE.md, hooks, code comments) but none of the five options include expiration metadata or review triggers. Learnings are written once and persist indefinitely. The existing MEMORY.md already shows this pattern: entries from months ago reference specific tool versions, beads configurations, and workarounds that may no longer apply.

**Failure scenario:** A learning from 2026-03 says "bd set-state rejects empty values -- use sentinels" (this is already in MEMORY.md). In 2026-09, beads v0.70 adds native empty value support. The stale rule persists in CLAUDE.md, causing agents to use unnecessary sentinel values and confusing newcomers who read the current beads docs and see no such limitation. After 6 months, 30-40% of learned rules reference fixed bugs, removed features, or changed APIs. This matches the P1 calibration: "30 scar-tissue entries accumulate... half referencing bugs that were fixed months ago."

**Fix:** Every routed entry must include a dependency reference — the system state it depends on. Format: `# [date:bead] rule — depends: {tool}@{version} | {file}@{commit}`. When the dependency changes (tool version bump, file modification), flag the entry for review. The brainstorm's open question about CLAUDE.md bloat (line 112) is actually a staleness problem more than a volume problem — stale entries are the primary source of harmful bloat.

### [P1] Learnings embed model-specific behavioral assumptions without versioning

**Issue:** The brainstorm proposes routing learnings to CLAUDE.md, which is consumed by AI agents. Many learnings implicitly assume current model behavior. For example, "CLAUDE.md lines compete for attention" (from the spaced repetition analysis) assumes a specific context window size and attention pattern. The router does not distinguish model-agnostic rules ("use `command -v` not `which`") from model-dependent observations ("agents skim long CLAUDE.md files").

**Failure scenario:** A learning routed to CLAUDE.md says "keep hook output under 3 lines to avoid agent attention drop-off." This was true for Claude 3.5 Sonnet but Claude 4 Opus processes long outputs differently. The stale rule causes agents to truncate valuable hook output. Worse, because the entry looks like a universal principle (no model version tag), no one questions it during model transitions.

**Fix:** Learnings that describe agent behavior (as opposed to tool behavior or project conventions) should be tagged with the model context: `# [date:bead] rule — model-context: opus-4`. During model transitions, entries with `model-context` tags should be flagged for re-evaluation. Purely mechanical rules ("use `command -v`") need no model tag.

### [P1] Newcomer test fails — routed learnings lack self-contained context

**Issue:** The brainstorm's evidence table (lines 37-44) shows learnings that depend on project-specific context: "DISPATCH_CAP=1 mutates global for rest of session" requires knowing what DISPATCH_CAP is, what lib-dispatch.sh does, and why global mutation matters. The router classification (Option A) does not require self-contained encoding. A newcomer agent (fresh session, no prior context) encountering this in CLAUDE.md cannot act on it without additional research.

**Failure scenario:** A new contributor (or a fresh agent session with no prior sprint context) reads CLAUDE.md and encounters: "Close child beads when parent ships." They do not know what constitutes a child bead, what "shipping" means in this workflow, or where to find the ship command. The learning is opaque — it passed the specificity test (it names a specific action) but fails the newcomer test (it requires oral history to interpret).

**Fix:** Each routed learning must include a one-sentence "because" clause that makes it self-contained: "Close child beads when parent ships — otherwise `bd doctor` reports stale in-progress children and the next session wastes time re-triaging them." This is a prompt constraint on the router, not a structural change.

### [P2] Cross-project contamination via user-level memory files

**Issue:** The router taxonomy includes `memory` as a target (line 72), which maps to `~/.claude/projects/*/memory/`. The brainstorm does not address scoping rules for the memory target. User-level memory files (MEMORY.md) are loaded for all sessions in a project, but some learnings are only relevant to specific subprojects or plugins within the Sylveste monorepo.

**Failure scenario:** A learning specific to the Clavain plugin ("lib-routing.sh strips namespace prefixes before matching") is routed to the project-level MEMORY.md. An agent working in the Intercom app loads this memory entry and incorrectly applies the namespace-stripping assumption to Intercom's routing, which does not strip namespaces. The learning was correctly captured but incorrectly scoped.

**Fix:** The router must match learning scope to target scope. Project-level learnings go to project MEMORY.md. Subproject-specific learnings should go to the subproject's CLAUDE.md or a code comment in the relevant module — not to project-level memory. Add a scope-check step: "Is this learning specific to a subproject/plugin? If yes, route to that module's CLAUDE.md, not project-level memory."

### [P2] No survival plan for tool migration

**Issue:** The brainstorm proposes routing to five distinct systems: CLAUDE.md, AGENTS.md, memory files, hooks, and code comments. Each has different loading semantics, different maintenance patterns, and different migration paths. If the hook system changes (new API, different trigger model), all hook-routed learnings may break silently. The brainstorm does not address what happens to routed knowledge when the underlying infrastructure changes.

**Failure scenario:** Claude Code v2 changes the memory file loading path from `~/.claude/projects/*/memory/` to a new location. All memory-routed learnings become invisible. Or: the hook API changes from `hooks.json` to a new declarative format. Hook-encoded behavioral rules stop firing. In both cases, the learnings exist in the old format but are no longer consumed. Unlike `docs/reflections/` (which was always dead), these were active knowledge that silently died.

**Fix:** Add a "knowledge inventory" that lists all router targets and their loading mechanisms. When a tool migration occurs, the inventory enables systematic migration of all routed entries. The lightweight audit log (Option A, line 74) should record not just what was written but where — enabling a bulk search-and-migrate when a target system changes. Make the audit log mandatory, not optional.
