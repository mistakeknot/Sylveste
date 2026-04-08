---
agent: fd-lichen-symbiont-memory
track: esoteric
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] Structural code modification absent from target taxonomy — validation learnings route to overlay, not substrate

**Issue:** The brainstorm's "durable output targets" list (line 19-26) is: CLAUDE.md/AGENTS.md, auto-memory, hooks, code comments, PHILOSOPHY.md. The evidence table at line 39-45 maps `"regex [,.\-—] splits compound words at hyphens"` to "code comment on the regex in generate-agents.py" and `"DISPATCH_CAP=1 mutates global for rest of session"` to "code comment in lib-dispatch.sh." In both cases, the routing target is a *documentary overlay* (a comment describing the problem) rather than a *substrate modification* (changing the regex to use a named group that makes the split behavior explicit, or changing `DISPATCH_CAP` to be a function-local variable that cannot mutate global state). The brainstorm treats code comments as the code-level target — but a code comment is still an overlay: it describes behavior rather than encoding it in the structure.

**Structural isomorphism:** A lichen that produces acids to weather the rock beneath it is doing something categorically different from an epiphyte that sits on the rock surface — the lichen modifies the substrate so that future growth is guided by the modified surface itself, with no need to consult a description of the modification. The bioweathering IS the knowledge. A code comment on `DISPATCH_CAP=1` saying "this mutates global state" is an epiphyte: it sits on top of the code without changing it. A refactored version that makes `DISPATCH_CAP` function-local is substrate modification: the problem cannot recur because the environment has been structurally changed.

**Fix:** Add `structural-code-change` as a first-class target in the routing taxonomy, distinct from `code-comment`. The classification question becomes: *"Can this learning be encoded as a behavioral constraint in the code itself (type, guard clause, function signature, default, refactor) rather than as a comment describing the constraint?"* If yes, route to `structural-code-change`. The reflect prompt should include: `For code-level learnings, prefer structural changes (fix the code so the mistake cannot recur) over code comments (describe why the mistake is possible).` This is a one-line addition to the routing prompt.

---

### [P1] The existing `docs/reflections/` evidence confirms overlay-only historical practice — substrate was never modified

**Issue:** The brainstorm's evidence section (lines 35-48) analyzes 18 reflection files and shows that 100% of learnings were routed to `docs/reflections/` (dead overlay). The proposed fix routes to CLAUDE.md or code comments — still overlays, slightly less dead. But the pattern holds: not a single learning in the 18 analyzed files triggered a structural code change. The learning `"DISPATCH_CAP=1 mutates global for rest of session"` exists as text in a reflection file. The variable `DISPATCH_CAP` in `lib-dispatch.sh` presumably still mutates global state. The brainstorm proposes to move this learning from a dead overlay (`docs/reflections/`) to a live overlay (code comment). Neither is substrate modification.

**Structural isomorphism:** Lichens that merely deposit surface pigments on rock — without the acid bioweathering that modifies the substrate — are doing temporary work: the pigment can be removed without altering the rock. Over billions of years, the lichens that survived are those that modified the substrate itself, because the modification persists through any surface disruption. The brainstorm's "most durable" category (CLAUDE.md, hooks) is still only surface-level compared to structural code changes: hooks can be disabled, CLAUDE.md entries can be deleted, but a function that cannot produce the bug because its inputs are typed correctly is permanent.

**Fix:** In the sprint-end reflect flow, after extracting learnings, add an explicit question: *"For each code-level learning, is the underlying code still in its original (buggy) state?"* If yes, the reflect step should initiate a code fix as part of the sprint ship, not as a CLAUDE.md reminder to fix it later. The durable change gate in Option B should preferentially count structural code changes as higher-value than CLAUDE.md appends — one structural fix should satisfy the gate; three CLAUDE.md entries should require explicit justification for why structural fix was not possible.

---

### [P2] Dormancy resilience unverified — CLAUDE.md entries with session-specific context will degrade after arbitrary gaps

**Issue:** The open question at line 113 asks how `recent-reflect-learnings` (Go code in `clavain-cli`) adapts — suggesting it currently reads from `docs/reflections/`. Under the proposed system, learnings move to CLAUDE.md. But the brainstorm does not address whether CLAUDE.md entries written during a specific sprint will remain coherent after 2-4 weeks of unrelated work. The evidence table shows learnings like `"Triage should check git history for open beads"` — this is meaningful in the context of the sprint where triage was failing due to stale bead state. After a 3-week gap where the triage mechanism was rewritten, the entry in CLAUDE.md is either stale (the fix is already in the code) or still valid (the pattern recurs in a new form). The entry has no mechanism to signal which state it is in.

**Structural isomorphism:** Lichens are poikilohydric — they can survive complete desiccation for years and rehydrate without loss because their knowledge is structural, not metabolic. A lichen that stored its growth instructions in a volatile membrane that degrades when dry would not survive. The equivalent of volatile membrane storage is CLAUDE.md entries that reference session-specific state ("during the sprint, we found that...") rather than encoding the underlying principle structurally. The learning survives a 2-week session gap as text, but its applicability does not survive the gap if the code context it references has changed.

**Fix:** The learning router should prohibit session-specific phrasing in CLAUDE.md entries. Entries must be written in present tense, imperative mood, and must not reference bead IDs, sprint dates, or in-progress work. Prohibited: `"During sylveste-b49, we found that triage misses open beads."` Required: `"Triage: always check git log --all -- for bead IDs before declaring no open work."` This is a formatting constraint on the router output, enforceable by the reflect prompt.

---

### [P2] Shallow-overlay accumulation — all placement targets are removable without affecting codebase behavior

**Issue:** The brainstorm's Hybrid E recommendation produces a system where all knowledge placements are in removable layers: CLAUDE.md (a text file), auto-memory (a text file), hooks (a JSON config), code comments (strippable). If someone ran `grep -r "# learning:" . | xargs sed -i 's/.*//g'` across the repo, all compound-placed knowledge would be gone with no effect on how the code runs. This is the defining characteristic of shallow overlay: the knowledge is separate from the behavior. The brainstorm does not model what fraction of learnings could be encoded as structural changes versus must remain documentary — and without that model, the default is to route everything documentary because it is always possible to add text.

**Structural isomorphism:** A lichen colony that grew for 100 years on bare granite produces a substrate that is physically different from bare granite — the bioweathering is irreversible and visible to geologists. An epiphytic community that grew for 100 years on the same rock and then died leaves no trace. The brainstorm is designing a system that, after 100 sprints, leaves a modified set of text files. It is not designing a system that, after 100 sprints, leaves a structurally different codebase where the classes of mistakes that were made are architecturally prevented.

**Fix:** At sprint-end, the reflect step should explicitly ask: *"Of the code-level learnings this sprint, how many have been fixed in the code vs documented in CLAUDE.md?"* If the answer is "0 fixed, N documented," this should be flagged as an undesirable pattern — not blocked (some learnings genuinely require documentation, not code change), but surfaced as a quality signal. The sprint retrospective could track a "substrate modification ratio": code-fixed learnings / total code learnings. This does not require architectural changes — it is a metric question in the reflect prompt.

---

### [P3] Growth guidance absent — compound does not consider whether code structure modifications would guide future agent behavior without documentation

**Issue:** The brainstorm focuses on where to place knowledge (CLAUDE.md, code comments, memory files). It does not ask whether a code modification could encode the learning in a way that guides correct behavior without any documentation. Example: `"regex [,.\-—] splits compound words at hyphens"` — one fix is a code comment; a better fix is replacing the inline regex with a named constant `WORD_BOUNDARY_PATTERN` with a docstring explaining the hyphen edge case. An agent encountering the named constant in a future session gets the knowledge without reading any documentation. The code structure itself guides correct behavior.

**Structural isomorphism:** A lichen modifies its substrate such that future lichen growth follows the modified topography — the knowledge IS the environment. There is no separate documentation saying "grow here, not there." The modified surface guides growth. The named constant with docstring is the software equivalent: the name and docstring modify the "surface" of the codebase so that future agents encounter the knowledge at the point of use, without needing to search CLAUDE.md. This is a stronger form of the code-comment target the brainstorm proposes, not a different category.

**Fix:** Add to the learning router's code-level routing guidance: *"When routing a learning to a code target, prefer named constants, explicit type constraints, or renamed functions over inline comments. The goal is for a future agent reading the code to encounter the learning through the code structure itself, not through a comment on top of otherwise-unchanged code."* This is P3 because the system functions without it — code comments work — but over time this preference produces a codebase that is self-documenting rather than comment-annotated.
