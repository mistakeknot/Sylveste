---
agent: fd-typographic-marginalia-annotation
track: distant
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] Code-specific learnings default to CLAUDE.md instead of inline annotation at the relevant code location

**Issue:** The evidence table explicitly identifies "regex `[,.\-—]` splits compound words at hyphens" as a learning that "should live" as a "code comment on the regex in generate-agents.py." Yet this learning is currently in a dead reflection file, and the router as designed would likely route it to CLAUDE.md because that is the highest-listed durable target and the classification prompt does not specify when inline code annotation is preferred over CLAUDE.md. A CLAUDE.md entry reading "regex in generate-agents.py splits compound words at hyphens" requires an agent reading future generate-agents.py to remember to cross-reference CLAUDE.md — precisely the mental cross-reference that marginalia practice eliminates.

**Structural isomorphism:** Medieval scholars who copied a gloss from a manuscript's margin into a separate commentary codex produced a scholarly document that was frequently separated from the primary text during library reorganizations, rendering the commentary unreachable when consulting the original. The marginalia that remained physically attached to the text survived; the extracted commentary was lost or decoupled. Routing the regex learning to CLAUDE.md is extracting the margin gloss into a separate codex.

**Fix:** The router prompt in Option A step 2 must define a `code-comment` target with an explicit preference rule: "If the learning references a specific file, function, or code pattern, classify as `code-comment` (not `claude-md`) and include the target file path and function name in the routing output." The routing step then appends a comment at the relevant code location: in `generate-agents.py`, above or on the regex line: `# NOTE (reflect [date]): this pattern splits on hyphens — compound words like "pre-existing" will split incorrectly.` The CLAUDE.md entry is omitted or replaced with a one-liner cross-reference: `# See comment in generate-agents.py for regex hyphen-split gotcha.`

---

### [P1] The router writes CLAUDE.md entries about specific code without positional anchoring — entries will go stale when code moves

**Issue:** The brainstorm anticipates multiple learnings of the form "X happens in lib-dispatch.sh" or "DISPATCH_CAP=1 behavior in the dispatch system." These would route to CLAUDE.md as entries referencing specific files and functions. When lib-dispatch.sh is refactored, renamed, or split (a common occurrence in a growing plugin ecosystem — see MEMORY.md on extracted companion plugins), the CLAUDE.md entry still names the old file. An agent reading it cannot find the referenced code and cannot verify whether the learning is still relevant.

**Structural isomorphism:** Commentary volumes in medieval libraries were organized by their own classification system, not by the texts they annotated. When a scriptorium was reorganized, the commentary on Matthew might end up on a different shelf from the Gospel of Matthew. A scholar consulting Matthew encountered no indication that relevant commentary existed; a scholar consulting the commentary could not locate the text. Stale file references in CLAUDE.md recreate this decoupling: the entry becomes a reference to a location that no longer exists.

**Fix:** When the router writes to CLAUDE.md about a specific code location, it must include a verification hint inline: `# See: lib-dispatch.sh:dispatch_run() — DISPATCH_CAP=1 mutates global. Verify path if refactored.` The doctor command (`/clavain:doctor`) should include a check that parses CLAUDE.md entries containing file references and verifies the referenced file still exists at the named path. This is a lightweight addition to the doctor health checks — scan CLAUDE.md for patterns like `in <filename>` or `<filename>:<function>` and run `test -f` on each.

---

### [P2] Compound's writes to code comments risk overwriting previous annotations — palimpsest destruction

**Issue:** The brainstorm describes compound as writing code comments in the "code" routing case. If two sprints both produce learnings about the same function — say, `lib-dispatch.sh:dispatch_run()` — the second compound write may target the same comment block and replace the first annotation rather than appending to it. The brainstorm does not specify whether the code comment target is write (replace) or append (additive). If the underlying write operation uses sed-style replacement of a comment block, the first learning is destroyed.

**Structural isomorphism:** Palimpsest manuscripts — parchments scraped and reused — frequently destroyed earlier texts that were later discovered to have been more valuable than the overwriting text. The Abbey of Bobbio's scriptorium palimpsested Cicero's De Re Publica with a biblical commentary; the Cicero was partially recovered in the 19th century but irreparably damaged. A compound write that replaces rather than appends to an existing code comment is a palimpsest — institutionally sanctioned destruction of accumulated annotation.

**Fix:** The router's code-comment write step must always append, never replace. The implementation should: (1) search for an existing `# NOTE (reflect` block at the target location, (2) if found, append a new dated line below the existing block, (3) if not found, insert a new block. A practical format: each annotation line within the block starts with a date: `# NOTE (reflect 2026-03-15): initial observation` / `# NOTE (reflect 2026-03-29): confirmed on second incident.` This preserves the history of re-encounter at the point of annotation.

---

### [P2] No gloss density limit — compound could accumulate annotations until code is obscured by its own commentary

**Issue:** If the router routes code-specific learnings to inline annotations over 30+ sprints, a frequently-visited function could accumulate many comment lines. The brainstorm does not propose any limit on annotation density per code region. Unlike CLAUDE.md bloat (which affects session context loading), annotation bloat affects code readability directly — a function with 15 lines of instructional comments and 8 lines of code has become a commentary on itself.

**Structural isomorphism:** Some heavily glossed medieval manuscripts became literally illegible — the interlinear glosses grew denser than the primary text, and later scribes copying the manuscript could not distinguish text from gloss. The Glossa Ordinaria (the standard medieval Bible commentary) was originally marginal but in some manuscripts consumed more page space than scripture. Useful annotation at low density; obscuring annotation at high density.

**Fix:** Add a density convention to the router prompt: "Code comment blocks added by reflect must not exceed 5 lines per function. If a function already has a reflect comment block with 4 or more lines, consolidate into a single updated note before adding new content, and route the consolidated version to CLAUDE.md as a cross-reference." This enforces progressive consolidation — the code comment stays current and concise; the history lives in CLAUDE.md or the archive log.

---

### [P3] CLAUDE.md entries about specific code regions include no cross-reference back to the code — commentary separated from text

**Issue:** For learnings that cannot be inline-annotated (e.g., "review detection is the weak point" as an architectural observation about the multi-step review system, referencing no single file), CLAUDE.md entries are appropriate. But these entries include no pointer to the specific code they relate to, so an agent reading the code does not encounter the entry, and an agent encountering the entry cannot navigate to the relevant code.

**Structural isomorphism:** The practice of placing cross-references in the manuscript margin ("See also: folio 47v for parallel passage") was standard in well-annotated manuscripts precisely because it enabled readers to navigate the corpus without holding the full bibliography in memory. A CLAUDE.md entry without a code cross-reference is a commentary volume without chapter references — the reader knows a fact but cannot connect it to the text it explains.

**Fix:** When the router writes to CLAUDE.md about an architectural or systemic concern, require it to include a "See also:" field naming the most relevant file(s): `# See also: os/Clavain/lib/review.sh, PHILOSOPHY.md §review-detection`. This is a one-line addition to the router output template. The doctor command should also verify that "See also:" references in CLAUDE.md point to files that still exist.
