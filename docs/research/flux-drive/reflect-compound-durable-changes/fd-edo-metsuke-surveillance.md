---
agent: fd-edo-metsuke-surveillance
track: esoteric
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] CLAUDE.md loading is sankin-kotai without metsuke — presence is required, compliance is voluntary

**Issue:** The brainstorm correctly identifies that CLAUDE.md/AGENTS.md are "loaded into every conversation context" and calls this "highest-leverage." This is the structural enforcement mechanism — the sankin-kotai: agents must pass through Edo (load the file) on every session. But the brainstorm has no corresponding metsuke layer. Once a rule is placed in CLAUDE.md, there is no mechanism to verify that it influenced subsequent agent behavior. The only existing consumer is `recent-reflect-learnings` (a Go display tool in `clavain-cli`), which is purely informational — it surfaces the text, not the compliance. The Option B "durable change gate" checks whether a file outside `docs/reflections/` was modified *during* the reflect step — it verifies placement, not downstream behavioral impact. A rule placed in CLAUDE.md on day 1 that is ignored in sessions 2-50 will never be detected.

**Structural isomorphism:** The Tokugawa sankin-kotai system required daimyo to maintain residences in Edo and alternate attendance, creating a structural chokepoint. But sankin-kotai alone did not guarantee compliance with bakufu policy — it guaranteed physical presence. The metsuke (inspectors) were a separate, independent layer that verified that daimyo were actually following policy rather than merely appearing compliant. The brainstorm's durable change gate is sankin-kotai verification (was the rule placed?), not metsuke verification (is the rule being followed?). These are orthogonal mechanisms.

**Fix:** The smallest viable metsuke mechanism: at the start of `/sprint` or `/reflect`, the router checks whether any CLAUDE.md entry placed in the previous N sessions has a corresponding recent behavior change visible in git history. This is a weak signal but an independent one. Alternatively, when a learning is placed in CLAUDE.md, annotate it with a `# verify-by: <bead-id or sprint-id>` comment that `/doctor` can surface as unverified. The gate in Option B should be extended: pass only if the new CLAUDE.md entry was referenced in the very next session's behavior (observable via session transcript or tool call).

---

### [P1] Single routing logic governs all targets — hooks get the same review standard as memory files

**Issue:** Options A, B, and Hybrid E describe a learning router that classifies each learning into one of six targets: `claude-md | agents-md | memory | code | hook | philosophy`. The brainstorm does not differentiate governance requirements by target type. A hook placement is categorically different from a memory file entry: hooks run automatically and can block operations; a bad hook can halt the entire workflow. A CLAUDE.md entry can be overridden by agent judgment; a hook cannot. Yet the brainstorm treats classification into `hook` with the same lightweight process as classification into `memory`. The "escape hatch for no-learning sprints" is the only governance mechanism mentioned, and it applies uniformly.

**Structural isomorphism:** The Tokugawa bugyo system assigned domain-specific commissioners (bugyo) to distinct administrative areas — temple affairs, municipal finances, foreign trade — because each domain required specialized expertise and different enforcement standards. A single generalist bugyo governing all domains would apply temple-appropriate standards to financial transactions and vice versa. The brainstorm's single router classifies into all targets using identical review standards — no bugyo specialization. A hook-class placement should require higher evidence standards and a rollback procedure; a memory-class placement requires only relevance; a code-class placement requires that the change has been tested.

**Fix:** Add target-specific governance notes to the learning router prompt, differentiated by risk level: `hook` targets require explicit rollback plan and test condition in the placement note; `claude-md` / `agents-md` targets require a `when:` scope clause; `memory` targets require a topic-file assignment; `code` targets require a file and line reference. This is implementable as a few sentences appended to the routing prompt — no architectural change.

---

### [P2] Inspection fatigue risk from Option B gate — heavy verification incentivizes "no actionable learnings" escape hatch abuse

**Issue:** Option B adds a hard gate: the ship step fails if no durable file outside `docs/reflections/` was modified by reflect. The escape hatch is: "no actionable learnings" is valid if explicitly stated. The brainstorm acknowledges this risk but does not model the failure mode: over time, agents learn that declaring "no actionable learnings" reliably passes the gate without the overhead of classification, routing, and placement. This is especially likely for sprints that had learnings but where the learnings were minor (P3-level polish), because the cost of routing a P3 learning through the full system is disproportionate. The escape hatch, intended as a narrow exception, becomes the default path when the gate overhead is perceived as high.

**Structural isomorphism:** The metsuke system in the Tokugawa period experienced documented decay: when inspectors became too aggressive or required extensive compliance documentation, domain administrators developed sophisticated workarounds — bribery, parallel record-keeping, information hiding — that formally satisfied inspection requirements while neutralizing their intent. The "no actionable learnings" escape hatch is the bakufu-approved form of metsuke-bypass. If the gate triggers for every sprint, and the escape hatch is low-cost, the gate will be systematically circumvented without anyone explicitly deciding to do so.

**Fix:** Calibrate the gate to the cost of compliance: for a sprint that produced only P3 learnings, a one-line memory append should satisfy the gate. The gate should require "at least one placement at appropriate depth" rather than "at least one modification outside docs/reflections/." The escape hatch should require a learning-type declaration ("no P0/P1/P2 learnings this sprint — 2 P3 polish items noted in memory") rather than a blanket "no actionable learnings." This makes the escape hatch narrower and creates a searchable record of why placement was skipped.

---

### [P2] Directive ambiguity — compound-written CLAUDE.md rules are open to interpretation that varies by session context

**Issue:** The brainstorm's evidence table shows learnings like `"Close child beads when parent ships"` and `"Triage should check git history for open beads"` as candidates for CLAUDE.md. These are behavioral directives, but they are ambiguous: "close child beads" — all children, or only completed children? "when parent ships" — when the bead is closed, or when the PR merges? An agent in a sprint-end context will interpret these differently from an agent in a mid-sprint triage context. The brainstorm's routing step produces the learning as written; it does not require that CLAUDE.md entries meet a precision standard that enables consistent enforcement across different session contexts.

**Structural isomorphism:** Tokugawa bakufu directives (hatto) that were ambiguous caused inconsistent enforcement: different daimyo interpreted the same directive differently, producing compliance theater rather than behavioral alignment. The bakufu learned over time to specify directives with explicit scope, exceptions, and enforcement conditions. CLAUDE.md functions as the project's hatto — the authoritative behavioral directive document. Entries that are vague enough to be interpreted contextually are the equivalent of ambiguous hatto: each session complies according to its own reading.

**Fix:** The learning router should apply a specificity test before CLAUDE.md placement: can this directive be followed consistently by an agent with no memory of the sprint that produced it? If not, the directive must be rewritten with explicit scope and condition. The reflect prompt should include: `CLAUDE.md entries must specify: (1) who this applies to, (2) under what condition, (3) what the exception is. Example: "Close child beads before closing parent — always, unless child has no work started (status=triage)"` — not just `"Close child beads when parent ships."`

---

### [P3] Compound's auto-trigger mode (from hooks) has no governance model — operates outside the inspection hierarchy

**Issue:** Open question #3 asks: "What about compound's auto-trigger from hooks — does it still write to solutions/ in that mode?" The brainstorm leaves this open. In the current architecture, compound can be invoked automatically by a hook (not by a human sprint-end decision). When compound is triggered automatically, the metsuke model is further degraded: there is no human-initiated review step, the triggering condition may not be well-documented, and the placed knowledge reflects a machine judgment about a machine-generated event. The governance model in Options A/B/Hybrid E is designed around human-driven sprint-end reflect, not automated hook-triggered compound.

**Structural isomorphism:** The metsuke inspection hierarchy functioned because inspections were initiated by the bakufu (top-down authority), not by the daimyo being inspected. A system where the inspected party can trigger its own compliance documentation at will — and where those self-triggered documents carry the same authority as bakufu-initiated inspections — degrades the inspection hierarchy. Compound auto-triggered by hooks is the equivalent of daimyo-initiated self-inspection: the actor generating the knowledge is also the actor being governed by it.

**Fix:** Resolve open question #3 explicitly in the plan: auto-triggered compound should write to `docs/solutions/` (the existing archive) only, not to CLAUDE.md or hooks. Promotion from `docs/solutions/` to a persistent target requires a human-in-the-loop reflect step. This maintains the metsuke separation of concerns: automated compound generates candidates; human reflect promotes validated learnings to governing targets. One sentence in the plan document closes this gap.
