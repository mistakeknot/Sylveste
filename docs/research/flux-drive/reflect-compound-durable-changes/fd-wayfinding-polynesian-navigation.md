---
agent: fd-wayfinding-polynesian-navigation
track: distant
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] Debugging heuristics classified as CLAUDE.md entries instead of activity-triggered hooks — knowledge separated from its practice context

**Issue:** The evidence table in the brainstorm includes the learning "Triage should check git history for open beads" — a procedural heuristic that only has meaning during triage. This learning is proposed to route to CLAUDE.md. But CLAUDE.md is loaded at session start, before any activity context is established. An agent running a triage sprint will encounter this line as general background text. An agent not running triage will also encounter it, as noise. The learning's meaning is inseparable from the triage activity itself — it is only actionable when `bd triage` or equivalent is being run.

**Structural isomorphism:** A Polynesian navigator who wrote "when you see the frigatebird flying low, you are near a lee shore" in a shore-side manual was not preserving the knowledge — the knowledge is only meaningful when you are at sea and can see the frigatebird. Writing it in CLAUDE.md is like writing it on a placard in the harbor: technically preserved, practically inert at the moment of use.

**Fix:** The learning router prompt (Option A, step 2) must include a classification question before picking a target: "Is this learning only meaningful during a specific activity or command? If yes, target a hook triggered by that command, or an inline comment at the relevant function." "Triage should check git history" should route to a hook on `bd triage` that injects the reminder into context, not to CLAUDE.md. The classification `hook` in Option A step 2 should be split into `hook:always` and `hook:triggered-by:<command>`.

---

### [P1] The routing taxonomy (Option A step 2) lists only documentary targets plus hooks — does not distinguish reference knowledge from activity-triggered knowledge

**Issue:** Option A's classification step lists six target types: `claude-md | agents-md | memory | code | hook | philosophy`. Of these, four are documentary (read before activity begins) and two have potential for activity-triggering (`hook`, `code`). But the brainstorm does not define what conditions make `hook` the correct choice versus `claude-md`. The implicit assumption is that `hook` is for behavioral enforcement (blocking mistakes) and `claude-md` is for informational guidance. This misses the entire category of context-injection hooks — hooks that fire not to block an action but to provide relevant knowledge at the moment of relevant action.

**Structural isomorphism:** Polynesian wayfinding distinguishes between knowledge that can be pre-loaded (star positions relative to home island at different seasons) and knowledge that must be encountered in context (the specific feel of the Carolinian swell pattern versus the trade-wind swell pattern, which cannot be described but can be recognized when present). The navigator carries both types, but they function differently. The brainstorm's taxonomy only supports the first type well.

**Fix:** Extend the target taxonomy to include `hook:context-inject` as a distinct target type, separate from `hook:enforce`. A `hook:enforce` target fires and can block or alter behavior. A `hook:context-inject` target fires and appends relevant knowledge to session context only when the relevant command or activity is active. This is implementable via Clavain's hooks system using `SessionStart` hooks filtered by the current sprint's bead type or active commands. The router prompt should define: "if the learning is only relevant during X, classify as `hook:context-inject` for X."

---

### [P2] Practice-embedded knowledge (hooks, inline comments) has no documentary index — invisible during plugin migration or audit

**Issue:** Option E proposes that compound's auto-trigger mode (fired from hooks) may still write to `solutions/` as an archive in that specific mode. But for knowledge routed to hooks and code comments by the learning router, there is no proposed cross-reference mechanism. If a hook contains a learning ("when `DISPATCH_CAP=1` is set, this mutates global state for the session"), that knowledge exists only inside the hook file. An agent auditing the codebase, migrating the plugin, or debugging an unfamiliar failure has no way to discover what learnings are encoded in hooks without reading all hook files.

**Structural isomorphism:** Polynesian navigation knowledge encoded in the practice of sailing was nearly lost when the practice was interrupted in the 20th century — not because anyone destroyed it, but because it was invisible as knowledge when not being practiced. The navigators who preserved it did so by creating a documentary shadow (the Micronesian Area Research Center collections, Lewis's fieldwork) that could bootstrap re-learning when the practice was interrupted.

**Fix:** When the router writes to a hook or code comment, it should also append a one-line cross-reference to a lightweight `docs/learnings-index.log` (format: `[date] hook:<file>:<line> — summary`). This log is not a duplicate of the knowledge — it is an index. It enables `grep` and audit without requiring hook-by-hook inspection. This is a three-line addition to the router's write step, not a new system.

---

### [P2] Context-dependent learnings are routed to context-free targets — the etak problem

**Issue:** Some learnings in the brainstorm are only meaningful relative to a current position in the workflow. "Review detection is the weak point" is actionable if you are designing a review gate, but noise if you are running a triage sprint. "Plan review catches stale beads" is actionable at the plan-review stage but irrelevant at the deploy stage. The learning router routes these to CLAUDE.md or AGENTS.md — context-free locations that load the same content regardless of what the agent is currently doing.

**Structural isomorphism:** Etak navigation — the Carolinian technique of conceptualizing navigation as the reference island moving past a fixed canoe rather than the canoe moving toward a destination — is a frame shift that is only useful when you understand where you are in the voyage. Giving an apprentice the etak reframe at the beginning of their first voyage produces confusion; giving it when they are mid-passage and struggling with position uncertainty produces insight. Same knowledge, radically different utility depending on current context.

**Fix:** The router should support a `scope` field (as noted by the Venetian agent, but the mechanism here is specifically about workflow position, not skill level). Learnings tagged with a workflow scope (e.g., `scope: plan-review`, `scope: dispatch-sprint`) should be routed to context-inject hooks filtered by that scope, not to CLAUDE.md. A sprint-start hook could inspect the active bead type and inject scoped entries from a `docs/scoped-learnings.yaml` index rather than loading them unconditionally.

---

### [P3] Survival of practice-embedded knowledge through plugin migration is not addressed

**Issue:** Option E notes that compound's auto-trigger mode operates from hooks. If the Clavain plugin is migrated, refactored, or split (as has happened historically — see MEMORY.md on extracted companion plugins), hooks that carry encoded learnings will move or change without any migration check ensuring the encoded knowledge travels with them. The brainstorm does not address what happens to knowledge embedded in hooks when the hook infrastructure changes.

**Structural isomorphism:** Polynesian navigation knowledge survived in the Caroline Islands specifically because the practice of inter-island voyaging was maintained despite colonial disruption — when the practice finally stopped in some island groups, the knowledge stopped with it. Plugin migrations in Clavain are the equivalent of colonial interruption of the voyaging practice: structurally imposed changes that break the context in which embedded knowledge is activated.

**Fix:** Add a migration check to the plugin publish step (`ic publish`): before publishing a plugin version that removes or renames a hook, check `docs/learnings-index.log` for entries referencing that hook file. If any exist, the publish step should warn: "N learnings are encoded in hooks being modified — verify knowledge is preserved." This is a pre-publish hook on the Clavain plugin, referencing the index established in Finding 3.
