---
agent: fd-knowledge-management-sop
track: orthogonal
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] CLAUDE.md has no content owner and no pruning governance — compound will grow it without bound

**Issue:** The brainstorm identifies CLAUDE.md bloat as an open question but provides no answer. In KM, a document without a named content owner and a documented review/pruning cycle will grow until it becomes unusable — this is the primary cause of SOP compliance failure in regulated industries. The brainstorm's Option E makes CLAUDE.md the primary routing target ("Adding a line here is the highest-leverage change") without addressing the governance model for that document. `~/.claude/CLAUDE.md` and `Sylveste/CLAUDE.md` are already structured documents that exist outside the reflect pipeline's visibility.

**Failure scenario:** Over 6 months of sprint-end reflects under Option E, the Sylveste `CLAUDE.md` grows from its current size (approximately 80 lines) to 240+ lines. No pruning mechanism exists. The document has no section size limits. Multiple contradictory entries accumulate (e.g., two rules about bead lifecycle that were written at different stages of bead system evolution). Future agents load the full document but the signal-to-noise ratio has dropped to the point where the document has the same effective behavior as docs/reflections/: technically loaded, practically ignored.

**Fix:** Add a governance block to the reflect prompt: before appending to CLAUDE.md, check the target section's current line count. If the section already contains more than 8 lines, the reflect step must propose a consolidation pass instead of appending. The consolidation prompt should merge duplicate rules, remove rules superseded by hooks or code changes, and confirm the proposed consolidated version before writing. Define a named content owner per CLAUDE.md section in the document header (e.g., `<!-- owner: reflect-pipeline, review: every 10 sprints -->`).

---

### [P1] Taxonomy gap forces misrouting — novel learning types have no target category

**Issue:** The brainstorm's routing taxonomy (`claude-md | agents-md | memory | code | hook | philosophy`) was derived from analysis of 18 existing reflection files. It covers the learning types observed to date. KM taxonomies must evolve as new knowledge types emerge — and the brainstorm provides no mechanism for the router to identify that a learning doesn't fit any existing category cleanly and propose a taxonomy extension. The taxonomy is treated as fixed. When a learning falls between categories (e.g., a design pattern that is neither a CLAUDE.md gotcha nor a PHILOSOPHY.md principle), the router will force-fit it to the nearest category rather than flagging a gap.

**Failure scenario:** A learning emerges about Clavain's hook registration lifecycle that is more specific than AGENTS.md guidance but more structural than a CLAUDE.md rule — it's a workflow pattern (like `~/.claude/workflow-patterns.md`). The router classifies it as `agents-md` because that's the closest match. It's appended to AGENTS.md in the wrong section. The actual appropriate target — a new section in `workflow-patterns.md` — is never created. The learning is technically routed but practically unfindable at the point of use.

**Fix:** Add a fallback branch to the routing classification: if no existing target is a strong match, the router should output `target: taxonomy-gap` with a description of the new category the learning represents. Taxonomy-gap learnings should be routed to a single `docs/research/flux-drive/taxonomy-gaps.md` accumulation file and surfaced for human review at the next strategy/planning session. This is the KM equivalent of a "pending categorization" queue — don't force-fit, flag and escalate.

---

### [P2] Compound writes are treated as immediate final edits — no draft/review step

**Issue:** The brainstorm's Option A/E describes routing as a direct write operation: classify → write to CLAUDE.md/memory/hook. There is no intermediate draft or review step between classification and final commit to the living document. In KM for regulated industries, governed documents don't accept unreviewed changes — lessons learned become draft changes that require review before becoming authoritative. A wrong or misleading CLAUDE.md rule written by a reflect step becomes an authoritative instruction immediately and is loaded into every future session.

**Failure scenario:** The reflect step extracts a learning from a sprint where the agent made an incorrect diagnosis. The learning is subtly wrong: "always run `bd sync` before closing a bead" — but `bd sync` was actually only needed in a specific scenario involving the per-project Dolt migration (now complete). The router classifies it as `claude-md` and appends it. It becomes authoritative. For the next 20 sprints, agents run an unnecessary `bd sync` before every bead close, occasionally causing Dolt timeouts. No one reviews the CLAUDE.md entry because it was written by the reflect pipeline and looks authoritative.

**Fix:** The reflect step should output its proposed writes as diffs (showing the before/after state of the target document) and display them to the user before committing. For autonomous sprint pipelines where the user is not watching, stage the writes to a `docs/research/flux-drive/pending-reflect-writes.md` holding file and surface them at the next interactive session for review before committing to the target document. This creates a minimal review gate without requiring heavyweight change control.

---

### [P2] Learnings are appended as generic observations, not as specific edits to specific targets

**Issue:** The brainstorm's description of routing ("append to CLAUDE.md") treats CLAUDE.md as an append-only log. In KM, a lesson learned is not complete until it becomes a specific edit to a specific location in a specific SOP — not a new paragraph at the bottom. The distinction matters: an appended-to-bottom rule is less likely to be seen at the relevant decision point than a rule inserted in the section an agent is reading when they face that decision. The brainstorm does not specify that routing to CLAUDE.md means inserting into the relevant section, not appending to the end.

**Failure scenario:** The learning "when shipping a parent bead, check for open children first" is appended to the end of Sylveste's CLAUDE.md under a generic "Beads Workflow" heading. The agent reading the CLAUDE.md in a sprint context reads the top sections (Working Style, Structure) and may not reach the appended entry because the document is long. The relevant section for this rule is the "Work Tracking" section, which already describes bead close procedures. A rule appended to the bottom is not at the point of use.

**Fix:** The reflect routing prompt for `claude-md` and `agents-md` targets should specify not just the file but the target section: "Append to the 'Work Tracking' section" or "Insert after the bead close procedure entry." The reflect step should locate the target section using a pattern search before writing, and insert within the section rather than appending to the file end. This is the KM equivalent of editing the relevant SOP section rather than adding an addendum page.

---

### [P3] No taxonomy versioning — routing decisions made under taxonomy v1 are not reusable under taxonomy v2

**Issue:** The brainstorm proposes replacing the existing docs/reflections/ + docs/solutions/ structure with a new routing taxonomy. When the taxonomy evolves (new categories added, categories merged), previously routed learnings were classified under the old taxonomy. There is no mechanism to re-evaluate or migrate them. Over time, the audit log becomes an archaeology project: learnings from 6 months ago used category names that no longer exist.

**Failure scenario:** The initial taxonomy has `memory` as a category. After implementing Option E, the team decides to split `memory` into `memory:advisory` and `memory:behavioral` (following the aviation finding above). The 40 learnings previously routed to `memory` are now in an ambiguous state — some should be `memory:advisory`, some `memory:behavioral`. The audit log shows `target: memory` for all of them. A future agent trying to audit the routing history cannot determine which sub-category was intended.

**Fix:** Record the taxonomy version used for each routing decision in the audit log (`taxonomy_version: 1.0`). When the taxonomy changes, document the change with a version bump and a migration note. This is a P3 because it doesn't affect current behavior but creates technical debt in the audit trail. A simple taxonomy-version field in the per-learning log record is sufficient.
