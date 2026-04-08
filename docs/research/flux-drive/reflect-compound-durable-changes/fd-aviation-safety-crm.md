---
agent: fd-aviation-safety-crm
track: orthogonal
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P0] No mandatory corrective action — "informational" memory routing creates a passive escape hatch

**Issue:** The brainstorm's classification taxonomy includes `memory` as a routing target (see "All four prevention mechanisms are needed" section). Memory files (`~/.claude/projects/*/memory/`) are loaded as context but impose no behavioral constraint — an agent can read them and ignore them. Routing a learning to memory is the equivalent of aviation "noting" a safety finding without a corrective action. The design explicitly lists memory alongside hooks and CLAUDE.md as equal peers, but they are not equal: memory is advisory, hooks are mandatory.

**Failure scenario:** The learning "close child beads when parent ships" (already documented as a dead-file repeat in the brainstorm's evidence table) gets classified as `memory` because it's cross-project context. It lands in MEMORY.md, is loaded next session, is read by the agent, and is ignored under workload — exactly the pattern that produced the original 18 dead reflection files. The learning repeats for a third session with no escalation.

**Fix:** In the reflect prompt's classification taxonomy, split `memory` into two sub-categories: `memory:advisory` (cross-session context with no enforcement requirement) and flag any learning about a recurring mistake as requiring either `hook` or `claude-md` classification, not `memory`. The escape hatch for "no actionable learnings" in Option E should require explicit justification, not just a declaration.

---

### [P1] No closure verification gate — writes are assumed to succeed

**Issue:** Option A and the recommended Option E describe routing as "append to CLAUDE.md, add code comment, write memory file" with no post-write verification step. The brainstorm's "Durable Change Gate" (Option B) only checks that "at least 1 file outside docs/reflections/ was modified" — it verifies modification metadata, not content. This is the aviation equivalent of signing off a corrective action based on the maintenance log entry rather than inspecting the aircraft.

**Failure scenario:** The reflect step appends a CLAUDE.md rule. A transient write conflict (concurrent session, read-only filesystem on sleeper-service during mutagen sync pause) means the append silently fails or truncates. The gate check passes because it looks for "any file modification outside docs/reflections/" — but if the write failed, no modification occurred and the gate would actually catch this case only if it checks the target file specifically. If the gate is implemented as "did the reflect step produce any git diff?" and the write silently failed, the gate passes with no diff and the learning is lost with no record.

**Fix:** After each write, the reflect step should read back the specific line it wrote and verify it appears in the target. For CLAUDE.md appends, a post-write `grep` for a unique phrase from the appended rule constitutes the inspector sign-off. For hook registrations, the reflect step should verify the hook appears in settings.json. Log verification results to the audit trail alongside the routing record.

---

### [P1] No repeat-finding escalation — the same fix gets re-issued

**Issue:** The brainstorm's evidence table documents that the same categories of learnings ("close child beads", "check build before committing") have appeared in multiple reflection files. Option E's router will route these again the next time they appear. There is no mechanism in any of the five options to detect that a learning was previously routed and the route apparently failed (since the problem recurred). Aviation SMS escalates repeat findings to systemic investigation — the brainstorm has no equivalent.

**Failure scenario:** The learning "close child beads when parent ships" is routed to CLAUDE.md in sprint N. It appears again in sprint N+2. The router classifies it again, appends a second CLAUDE.md line (or overwrites the first), and marks it closed. Sprint N+4, it appears again. After three recurrences there is still no investigation into why the CLAUDE.md rule isn't preventing the behavior. The root cause (possibly: CLAUDE.md is too long to reliably influence behavior at the relevant decision point) is never surfaced.

**Fix:** The reflect routing step should search MEMORY.md and git log of CLAUDE.md for the learning's topic before routing. If a matching entry already exists, the finding is a repeat — the reflect output should flag it as "REPEAT FINDING: previous corrective action did not prevent recurrence" and route it to a bead (via `bd create`) for systemic investigation rather than appending another line to CLAUDE.md.

---

### [P2] No corrective action specificity enforcement — vague learnings pass classification

**Issue:** The brainstorm's evidence table includes vague learnings like "Review detection is the weak point" routed to AGENTS.md or PHILOSOPHY.md. Aviation SMS rejects corrective actions that don't specify a procedural change. "Review detection is the weak point" as a PHILOSOPHY.md entry tells future agents nothing actionable. The classification taxonomy in Option A/E does not include a specificity gate.

**Failure scenario:** The reflect step classifies "we need to be more careful about planning" as a `claude-md` learning and appends "Be more careful about planning" to CLAUDE.md. The durable change gate passes (a file outside docs/reflections/ was modified). The learning is now a CLAUDE.md line that every future agent reads and ignores because it has no specific behavioral instruction. Over 3 months, CLAUDE.md accumulates 15 vague lines of this type.

**Fix:** Add a specificity check to the reflect classification prompt: a valid learning must specify (a) a triggering condition and (b) a concrete action or rule. "When shipping a parent bead, run `bd list --status=in_progress --parent=<id>` before closing" passes. "Be more careful about bead management" fails. The reflect step should reject unspecific learnings and prompt the user for a concrete formulation before routing.

---

### [P2] No checklist-bloat management for CLAUDE.md — the new dead-file problem

**Issue:** The brainstorm identifies CLAUDE.md bloat as an open question ("How to handle CLAUDE.md bloat over time?") but offers no answer. In aviation, checklist fatigue is the primary mechanism by which safety checklists stop working — when checklists grow beyond the cognitive bandwidth of the crew, compliance drops. A CLAUDE.md that accumulates 200 lines of routing targets becomes the new docs/reflections/: technically loaded, practically ignored.

**Failure scenario:** Over 6 months of sprint-end reflects, CLAUDE.md grows from 80 lines to 240 lines. Context window loading remains constant but attention density drops — later rules are processed with less weight. The rule added in month 2 ("never use heredocs in Bash tool calls") remains, but the rule added in month 5 ("always verify hook registration after plugin publish") is in a section the agent scans with low attention. The bloat problem has migrated from docs/reflections/ to CLAUDE.md.

**Fix:** At minimum, add a CLAUDE.md section size limit to the reflect prompt: if the target section already has more than N lines, the reflect step should propose consolidating existing entries rather than appending. At best, add a quarterly review bead type that runs a consolidation pass over CLAUDE.md (merge duplicate rules, remove rules that are now encoded in hooks). This bead type should be created by the reflect step when it detects the section size threshold has been crossed.
