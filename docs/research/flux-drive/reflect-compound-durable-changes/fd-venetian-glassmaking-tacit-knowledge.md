---
agent: fd-venetian-glassmaking-tacit-knowledge
track: distant
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] Learning router defaults to CLAUDE.md for procedural knowledge that should be hooks

**Issue:** The brainstorm's evidence table contains clearly procedural learnings — "Close child beads when parent ships," "Triage should check git history for open beads" — that are proposed to route to CLAUDE.md. These are not reference facts to consult; they are behavioral rules that an agent might violate mid-sprint without ever consulting CLAUDE.md. The router as described (Option A / Option E) classifies into six target types but nowhere specifies that procedural learnings (enforceable via hooks) must be treated differently from declarative learnings (informational, suitable for CLAUDE.md). Without an explicit classification distinction, the path of least resistance is always CLAUDE.md — it requires no code changes, no new hook, just an append.

**Structural isomorphism:** Murano maestri who wrote down temperature limits in a manual rather than encoding them in furnace chamber geometry were producing documentation that depended on apprentices remembering to read it at the right moment. The chamber geometry cannot be ignored; the manual can. Routing "Close child beads when parent ships" to CLAUDE.md is writing the temperature limit in a manual. Routing it to a hook that fires on `bd close` of a parent bead is encoding it in furnace geometry.

**Fix:** In the learning router prompt (Option A step 2), add an explicit classification gate before the target pick: "Is this learning enforceable by code at the moment the mistake would occur? If yes, classify as `hook` or `code` regardless of simplicity. Only classify as `claude-md` if enforcement is not feasible." The classification taxonomy in the router must make `hook` the default for anything phrased as "always do X when Y."

---

### [P1] Durable change gate (Option B) checks file modification, not behavioral constraint

**Issue:** Option B's gate verifies "at least 1 file outside docs/reflections/ was modified by the reflect step." A single appended line to CLAUDE.md satisfies the gate unconditionally. There is no check that the modification actually constrains future behavior at the correct point of action. The gate is satisfied just as easily by adding a vague "be careful with dispatch" line to CLAUDE.md as by adding a `bd close` hook.

**Structural isomorphism:** A Murano guild inspector who verified that the apprentice had written in the ledger "do not overheat" rather than verifying the furnace chamber dimensions had not been widened was checking a formal record, not the constraint itself. The ledger entry could exist while the chamber was structurally compromised.

**Fix:** The gate should require that at least one modification is to a file that is not a documentation target — i.e., at least one of: a hook definition, a code file, a config file, or a memory file. CLAUDE.md and AGENTS.md modifications alone should not satisfy the gate unless explicitly declared as "no hook feasible: [reason]." This escape hatch prevents gaming while allowing the declarative path when enforcement is genuinely impossible.

---

### [P2] CLAUDE.md will bloat into skimmable background noise without a structural distinction between enforcement-level and advisory-level entries

**Issue:** The brainstorm names CLAUDE.md as the "highest-leverage change" and anticipates multiple sprints appending learnings. No mechanism is proposed to differentiate entries by type, frequency of relevance, or enforcement status. Within 20-30 sprint cycles, CLAUDE.md will contain dozens of lines of varying granularity — some high-frequency behavioral rules, some narrow one-off gotchas, some design philosophy. The document will be loaded every session but parsed as undifferentiated text, exactly replicating the dead-file problem at a different address. The brainstorm names this risk ("CLAUDE.md could bloat") in the open questions but proposes no structural fix.

**Structural isomorphism:** Murano workshops that stored all tacit knowledge as written notes (temperature limits, timing cues, color formula steps) rather than organizing knowledge by function (physical constraints, verbal reminders, trainee-only instructions) produced manuals that masters skimmed past rather than internalized. The section structure of the workshop — furnace area, cooling area, color room — encoded organizational knowledge that no manual could replicate.

**Fix:** Establish a CLAUDE.md section structure as part of the router's output format: `## Gotchas` (project-specific, one-time traps), `## Behavioral Rules` (things that should be hooks but aren't yet), and `## Design Doctrine` (architecture-level principles). The router writes to the correct section. Any section exceeding N entries (suggest 8-10) triggers a pruning prompt in the next sprint's reflect phase. This is a small addition to the router prompt, not a new system.

---

### [P2] The classification taxonomy does not distinguish apprentice-stage from master-stage knowledge

**Issue:** The brainstorm lumps all learnings together — regex behavior in generate-agents.py and "review detection is the weak point" are both proposed as CLAUDE.md candidates. A new session handling a simple bead lifecycle needs the regex gotcha as immediately as the architecture insight about review detection. But an agent running complex multi-agent dispatch needs the review detection insight far more urgently. There is no mechanism to stage or qualify which learnings are relevant at which workflow complexity level.

**Structural isomorphism:** Murano apprentices were not given master-level color formula knowledge until they had demonstrated basic gather and gather-and-blow control. Loading all levels of tacit knowledge simultaneously produced confusion rather than competence — the complex knowledge was noise before the simpler knowledge was habituated.

**Fix:** This is a P3 extension to the router. Add an optional `scope` field to the router's output: `scope: always | sprint-context | advanced`. Entries tagged `always` load immediately; entries tagged `sprint-context` load only when their topic area is active (e.g., when the sprint bead is in a dispatch-heavy epic); `advanced` entries are indexed but not loaded by default. The `recent-reflect-learnings` Go code in clavain-cli would need to filter by scope.

---

### [P3] Project-specific encoding (CLAUDE.md, hooks) creates knowledge silos with no portability mechanism

**Issue:** The brainstorm correctly prioritizes CLAUDE.md and hooks as the highest-leverage durable targets. But CLAUDE.md entries are project-specific and hooks are plugin-specific. When a learning generalizes beyond this project — e.g., "DISPATCH_CAP=1 mutates global for rest of session" — there is no mechanism to promote it to the cross-project auto-memory file or to a shared AGENTS.md. The learning that would benefit every future project using the same dispatch pattern stays confined to Sylveste's CLAUDE.md.

**Structural isomorphism:** Murano guild secrecy laws were effective at protecting technique but ensured that when the guild declined, techniques were lost rather than transmitted to other glass-making centers. The extreme durability of knowledge within the island coexisted with complete fragility at the island boundary.

**Fix:** Add a fifth target to the router taxonomy: `cross-project-memory` — maps to `~/.claude/projects/*/memory/MEMORY.md` via the auto-memory convention already established in the project. The router prompt should include: "Does this learning apply only to Sylveste, or would it apply in any project using the same tools/patterns?" A `yes` answer routes to auto-memory rather than CLAUDE.md. This is already a supported target in the existing memory conventions.
