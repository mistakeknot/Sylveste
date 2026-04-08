---
agent: fd-tibetan-terma-concealment
track: esoteric
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] No kha byang catalog — code-comment placements are undiscoverable

**Issue:** Option A / Hybrid E routes a learning to a code comment at its "point of use" (e.g., a regex in `generate-agents.py`, a variable in `lib-dispatch.sh`). Once placed, there is no catalog entry recording that the knowledge exists there. The only way to rediscover it is to re-encounter that exact file. The brainstorm acknowledges that `docs/reflections/` has "no consumer, no search, no loading" — but the proposed fix replaces that dead-file store with equally undiscoverable inline comments, just at different locations. A learning placed in `lib-dispatch.sh` about `DISPATCH_CAP=1` is still lost if a future agent is debugging the same class of problem in a different file.

**Structural isomorphism:** In the terma tradition, physical earth-treasures (sa gter) could only be found because the master encoded a prophetic catalog (kha byang) listing each treasure's location and the conditions under which it should be revealed. Without the kha byang, the treasure might as well not exist — practitioners wandering Himalayan valleys without a map would die before finding it. The brainstorm proposes routing learnings to sa gter locations (code files) while discarding the kha byang (the audit log / lightweight log). The "append a one-liner to a lightweight log for audit trail" in Option E is close to a kha byang, but the brainstorm treats it as optional ("Optionally append..."), and the log format is unspecified — no retrieval conditions, no pointer to the target file/line.

**Fix:** In the learning router prompt, require that every sa gter placement (code comment, config change) appends a structured entry to a fixed-location catalog file — e.g., `docs/learnings-index.jsonl` — with fields: `{date, learning_summary, target_file, target_symbol, retrieval_condition}`. The audit log in Option E should not be optional; it is the kha byang. One-line addition to the reflect prompt: `After placing any code-level learning, append a catalog entry to docs/learnings-index.jsonl with target_file and retrieval_condition.`

---

### [P1] All documentation-level knowledge routed to dgongs gter only — CLAUDE.md becomes the single substrate

**Issue:** The brainstorm's target taxonomy lists `CLAUDE.md/AGENTS.md`, `auto-memory`, `hooks`, `code comments`, and `PHILOSOPHY.md`. In practice, the worked examples in the "Evidence" section show that 80% of learnings are "1-2 sentence items" assigned to CLAUDE.md/code-comment targets, with CLAUDE.md being the dominant documentary target. Open question #1 explicitly worries about CLAUDE.md bloat. The brainstorm proposes no counter-taxonomy for learnings that should remain in external, location-anchored targets rather than being loaded into every session context. The risk: over time, CLAUDE.md becomes the universal sink for all dgongs gter knowledge, activating indiscriminately regardless of relevance — the equivalent of a tradition that abandoned earth-treasures entirely and encodes everything in the mindstream, requiring practitioners to carry the entire canon mentally at all times.

**Structural isomorphism:** Dgongs gter (mind-treasure) knowledge is activated by internal context — the right mental state calls it forth. Sa gter (earth-treasure) knowledge is activated by location — you encounter it when you physically arrive at the relevant site. A healthy terma tradition uses both: stable, universal principles go in dgongs gter; location-specific knowledge stays sa gter. Routing `"regex [,.\-—] splits compound words at hyphens"` to CLAUDE.md (dgongs gter) is wrong — that knowledge is only relevant at the exact site of the regex, so it belongs in a code comment (sa gter). The brainstorm conflates the two modalities because the router taxonomy lacks an explicit sa gter vs dgongs gter classification step.

**Fix:** Add an explicit classification question to the learning router: *"Is this knowledge relevant everywhere, or only at a specific code location?"* If location-specific → sa gter (code comment, config change) + kha byang entry. If universal principle → dgongs gter (CLAUDE.md, AGENTS.md, PHILOSOPHY.md). This single gate prevents CLAUDE.md bloat and is implementable as one sentence in the reflect prompt.

---

### [P2] No terma authentication — fabricated or misdiagnosed learnings are placed as validated knowledge

**Issue:** The brainstorm describes the failure mode "learnings are too generic — vague 'we learned to plan better' instead of specific actionable changes" but its fix is purely about specificity (be more specific, route to point-of-use). It does not address the orthogonal failure mode: a learning that is specific but wrong. Example: a session diagnoses `DISPATCH_CAP=1` as a bug and routes "DISPATCH_CAP must always be reset to its default after use" to `lib-dispatch.sh` as a code comment — but the diagnosis was incorrect, and now every future reader of that file has a wrong mental model encoded authoritatively in the codebase. The brainstorm has no quality gate that distinguishes provisional observations from validated learnings before placement.

**Structural isomorphism:** The terma tradition developed elaborate authentication protocols (tertön lineage verification, second-opinion councils, retrospective validation over decades) precisely because "false terma" — teachings encoded by deluded rather than enlightened masters — posed a real contamination risk. A fabricated terma accepted as genuine corrupts the tradition. The equivalent here is a misdiagnosed root cause placed as authoritative knowledge in a code comment or CLAUDE.md entry. Once placed in a persistent target that is "loaded every session," incorrect knowledge is harder to dislodge than it was to place.

**Fix:** The learning router step should include a confidence classification: `{validated | provisional | hypothesis}`. Learnings marked `validated` (reproducing the fix confirmed the learning) route to CLAUDE.md or code comments. Learnings marked `provisional` route to a memory file with an explicit "unverified" prefix, or to a `docs/learnings-provisional.md` staging area. The escape hatch in Option B ("no actionable learnings" is valid) should also permit "provisional — not yet verified" as an honest response that places in staging rather than a persistent target.

---

### [P2] Concealment decay unaddressed — no expiration or relevance conditions on placed knowledge

**Issue:** The brainstorm's "durable output targets" list is framed as permanent: CLAUDE.md lines are intended to persist indefinitely, auto-memory accumulates without pruning (the open question about CLAUDE.md bloat acknowledges this), and there is no mechanism for a placed learning to declare when it stops being relevant. A learning placed today about `DISPATCH_CAP=1` in `lib-dispatch.sh` may become incorrect after that dispatch mechanism is rewritten in three months. The entry in CLAUDE.md or the code comment will persist, actively misleading future agents.

**Structural isomorphism:** Some terma were sealed with time-bound retrieval conditions: "reveal this teaching when the political situation in [region] allows" or "this treasure expires if not revealed within N generations." These conditions prevented stale knowledge from being retrieved after its context had dissolved. The brainstorm builds a system for knowledge placement without any mechanism for knowledge retirement, creating the equivalent of a terma tradition where nothing ever expires.

**Fix:** For every placement in CLAUDE.md or a memory file, the learning router should optionally append a `# review-after: <date or condition>` inline comment. This is a soft mechanism — not enforced — but it creates a searchable marker. Add: `When a learning references a specific implementation detail (a function name, a config variable, a file path), include a # review-after comment with the condition that would invalidate it.` The `bd doctor --deep` or `/doctor` check could scan CLAUDE.md for `review-after` entries and surface any whose date has passed.

---

### [P3] Gter ston readiness not modeled — knowledge is placed without considering retrieving agent's context

**Issue:** The brainstorm treats all learning targets as equivalent consumption surfaces: "loaded into every conversation context" (CLAUDE.md) or "at the point of use" (code comments). It does not ask whether the agent retrieving a learning at a future session will have sufficient context to apply it correctly. A learning about `bd doctor --deep` false positives on epic completeness (currently in MEMORY.md) is only useful to an agent that knows what `bd doctor`, epics, and `.N` suffix children are. If that entry is encountered by an agent doing unrelated work on the same project, the entry is noise at best and confusing at worst.

**Structural isomorphism:** Terma tradition held that certain treasures could only be safely revealed by practitioners who had reached a specific level of realization (gter ston readiness). A treasure revealed to an unprepared practitioner would be misapplied or corrupted in transmission. The brainstorm's routing taxonomy has no concept of "retrieval context" — the conditions under which a placed learning is relevant. It places knowledge and assumes the right agent will find it at the right time, which is the equivalent of hiding terma with no retrieval conditions.

**Fix:** Add a `when:` field to the learning router's output format: `when: <conditions under which this learning is relevant>`. For CLAUDE.md entries, this becomes inline context: `# Only relevant when working with bd/Dolt` or `# Only relevant during sprint-end reflect phase`. For memory entries, it enriches the MEMORY.md topic file headers. This is a P3 because the system still works without it — knowledge is found — but false-positive retrieval (loading irrelevant rules) degrades quality over time.
