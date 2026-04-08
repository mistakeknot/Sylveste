---
agent: fd-liturgical-calendar-ritual-memory
track: distant
status: NEEDS_ATTENTION
finding_count: 4
---

## Findings

### [P1] No periodic re-encounter mechanism for compound-written entries — knowledge decays into background noise

**Issue:** The brainstorm replaces dead reflection files with durable targets (CLAUDE.md, memory files, hooks, code comments). Once written, those entries are never mentioned again in the design. CLAUDE.md is loaded every session, but loading is not re-encounter — an agent context that contains 40 CLAUDE.md lines treats them as background context, not as actively processed instructions. There is no mechanism in the brainstorm to surface existing entries for review, consolidation, or retirement. The open questions section asks "How to handle CLAUDE.md bloat over time?" but offers no answer and leaves it unresolved.

**Structural isomorphism:** A lectionary that reads a passage once and never returns to it is not a liturgical calendar — it is an archive. The liturgical calendar's power is precisely that the same text is re-encountered at regular intervals in varying life contexts, which is why a monk who has heard the same Gospel pericope forty times can still be surprised by it. CLAUDE.md entries written at sprint 3 and never revisited by sprint 30 are liturgical texts that have become inaudible — present in the service but not heard.

**Fix:** Add a periodic review step to the sprint workflow. At sprint start, `recent-reflect-learnings` (the Go code in clavain-cli that already reads from reflection files) should be extended to surface a rotating subset of CLAUDE.md entries added by prior reflect steps — not all of them, a rotating sample of 3-5. The agent reads them actively rather than absorbing them as background. This requires adding a `# Added by reflect [date]` comment tag when the router appends to CLAUDE.md, so the review step can select entries by age and surface oldest-unreviewed first.

---

### [P2] No review cadence tied to existing rhythm — any future review mechanism risks being arbitrary or too frequent

**Issue:** The brainstorm proposes sprint boundaries as natural workflow checkpoints (the gate fires at ship time, reflect fires at sprint end). But for reviewing existing CLAUDE.md entries, no cadence is specified. Without anchoring review to an existing rhythm, any future addition will either be too frequent (every sprint = fatigue, rubber-stamping) or too infrequent (monthly = entries go stale without notice). The lectionary calendar's strength is that its cadence is non-negotiable and structurally embedded in the church year — it doesn't require anyone to remember to do it.

**Structural isomorphism:** Liturgical calendars that gave congregations discretion over which texts to re-read and when consistently degraded into reading only familiar or comfortable texts, avoiding challenging ones. The mandatory structure of the cycle was not bureaucracy — it was the mechanism that ensured hard texts were encountered even when inconvenient.

**Fix:** Tie the review step structurally to the existing sprint lifecycle rather than proposing a separate review command. Specifically: every Nth sprint (suggest N=5 or N=10 configurable in CLAUDE.md), the reflect phase includes a mandatory "review oldest 5 CLAUDE.md router entries" step before writing new ones. This is a single conditional in the reflect prompt: "If sprint count is a multiple of 5, begin with a review pass before extracting new learnings." Sprint count is already tracked in beads.

---

### [P2] Review, when it eventually exists, will confirm presence not relevance — obsolete entries will survive

**Issue:** The brainstorm names the archive decision as "keep both — route to durable target AND keep archive" and describes the archive as providing an audit trail. But neither the proposed router nor the gate includes any mechanism to ask: is this entry still accurate? A CLAUDE.md entry from sprint 3 about a regex bug that was subsequently fixed in generate-agents.py will remain in CLAUDE.md indefinitely, loading correct-seeming but now-wrong guidance into every session context.

**Structural isomorphism:** Liturgical reform cycles (Vatican II's revision of the Roman Rite being the most extensive modern example) exist precisely because readings accumulated over centuries included texts that had become misleading in their new cultural context, or that elevated peripheral matters to prominence they no longer deserved. The reform was not about adding new texts — it was about removing texts that had outlived their instructive function.

**Fix:** When the periodic review step surfaces an entry (per the fix in Finding 1), the review prompt must explicitly ask: "(1) Is this still accurate? (2) Has the underlying issue been resolved in code? (3) Should this be promoted to a hook or demoted to archive?" An entry answered "resolved in code" should be removed from CLAUDE.md with a one-line archive entry. The router should support a `deprecate` action that moves an entry from CLAUDE.md to a lightweight `docs/learnings-retired.log` with a date and reason.

---

### [P3] Escape hatch for "no actionable learnings" risks becoming the default — the calendar needs its ordinary time

**Issue:** Option E includes an escape hatch: "'no actionable learnings' is valid if explicitly stated." This is necessary but creates a perverse incentive: the escape hatch is much lower-friction than a genuine routing and writing step. Over time, agents may default to "no actionable learnings" to satisfy the gate quickly, especially for sprints where the work felt smooth. Liturgical calendars do not have an "ordinary time opt-out" — the readings for unremarkable weeks are structurally required.

**Structural isomorphism:** The liturgical distinction between "ordinary time" and feast days is instructive: ordinary time is not empty time — it is when foundational texts are re-encountered in their most concentrated form, without the distraction of special occasions. A sprint with no dramatic failures is not a sprint with no learnings — it may be the sprint where existing rules were confirmed effective, which is itself a learning worth recording (positive confirmation rather than only failure capture).

**Fix:** Rename the escape hatch to require a positive assertion rather than a negative one. Instead of "no actionable learnings," the router should require: "the following existing CLAUDE.md entries were confirmed accurate this sprint: [list at least 1]." This turns zero-learning sprints into positive confirmation passes rather than exits, preserving the habit without fabricating learnings.
