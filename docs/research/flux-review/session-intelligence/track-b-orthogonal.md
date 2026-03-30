---
track: orthogonal
agents: [fd-clinical-case-reasoning, fd-broadcast-engineering, fd-intelligence-analysis, fd-newsroom-workflow]
target: docs/brainstorms/2026-03-30-session-intelligence-compounding-brainstorm.md
---

# Track B: Orthogonal Disciplines Review
## Session Intelligence Compounding

Reviewed: 2026-03-28

---

## Discipline 1: Clinical Medicine — Institutional Memory

### Frame

Clinical medicine has 150+ years of hard-won practice managing exactly what the brainstorm describes: high-stakes decisions made under time pressure by rotating practitioners who cannot rely on verbal handoffs. The chart, the differential, and the case conference exist precisely because insight evaporates between shifts. Modern EHR systems (Epic, Cerner) have solved — and repeatedly broken — this problem at scale.

### Pattern Matches

**Problem-Oriented Medical Record (POMR).** Since Lawrence Weed's 1960s work, medicine structures notes as SOAP (Subjective / Objective / Assessment / Plan). The brainstorm's Insight Capture Hook (1a) and Dead End Capture (1b) are reinventing SOAP for software sessions. The key lesson: SOAP works because it separates *signal* (Assessment) from *chronology* (Subjective/Objective). The brainstorm conflates these — it proposes capturing insights *with* session metadata but hasn't specified a schema that separates "why this was decided" from "what the session did." Without that separation, search degrades into full-text retrieval and the signal drowns in narrative.

**Sign-out culture and shift handoffs.** The I-PASS handoff protocol (Illness severity, Patient summary, Action list, Situation awareness, Synthesis by receiver) maps precisely to the Warm Start Primer (2b). I-PASS research shows that structured handoffs reduce medical errors 30%. The brainstorm proposes injecting "here's what the last agent knew" — but the clinical evidence says the *structure* of that handoff matters as much as its presence. A handoff_latest.md prose blob fails the same way unstructured verbal handoffs fail: the receiver can't efficiently extract what they need to act on.

**Allergy and contraindication flags.** The brainstorm's Failure Pattern Avoidance (3d) is analogous to drug-allergy alerts: a PreToolUse hook that surfaces "this approach was tried and failed." Clinically, these alerts suffer from *alert fatigue* — when every action triggers a warning, practitioners click through without reading. The brainstorm doesn't address how to gate warning frequency. If every file read on a large codebase surfaces a dead-end warning, the signal will be ignored within a week.

### Blind Spots

**P0 — No provenance model.** Medicine requires every chart entry to be signed, timestamped, and attributable to a specific practitioner. The brainstorm's insight store has no equivalent: if an insight is wrong (the "dead end" was actually correct, or the agent that captured it was miscalibrated), there's no way to trace it, weight it, or retract it. A single bad insight, confidently stored, will be injected into future sessions as ground truth. The insight store needs a confidence field, a source agent identifier, and a retraction mechanism from day one — not as a future enhancement.

**P1 — No differential for contradictory signals.** Medicine trains practitioners to hold multiple diagnoses simultaneously and update on new evidence (Bayesian differential). The brainstorm assumes session signals are additive — you accumulate insights and they compound. But what happens when two sessions reach opposite conclusions about the same architectural pattern? cass has no conflict-detection. The system will silently inject contradictory context and leave the agent to resolve it without knowing a conflict exists.

**P2 — No "resolved" state for dead ends.** A drug contraindication that was added in 2018 should be reviewed if the patient's condition changes. Dead ends in code are similar — a pattern that failed in one context may succeed when the underlying library upgrades. The brainstorm treats dead ends as permanent signals. There's no expiry, no review trigger, no "this dead end was tried again and succeeded" state.

**P3 — Observer effect on insight quality.** Clinicians write differently when they know their notes are being reviewed by administrators for billing. Agents that know their Insight blocks are being extracted and stored will start optimizing for extraction legibility rather than actual insight quality. This is Goodhart's Law applied to knowledge capture.

---

## Discipline 2: Broadcast Engineering — Real-Time Signal Management

### Frame

Broadcast engineering manages continuous signal pipelines where latency, buffer management, and graceful degradation under load are non-negotiable. A broadcast chain that fails silently is worse than one that fails loudly. The discipline has strong opinions about buffering, codec selection, and what happens when the pipeline gets congested.

### Pattern Matches

**Signal-to-noise engineering.** Every broadcast chain has an explicit SNR budget. Engineers design filters at each stage to prevent noise from compounding — a noisy input that passes through three amplifiers becomes unusably noisy output. The brainstorm proposes extracting insights from session output and passing them forward into future sessions. There is no SNR analysis. A session that was confused and produced low-quality reasoning will also produce low-quality insight blocks. Those blocks will be indexed, retrieved, and injected into future sessions with the same authority as high-quality insights. The pipeline has no noise gate.

**Time-code and synchronization.** In broadcast, every frame is stamped with a timecode and every downstream component knows the relationship between its current time and the source time. Cache invalidation (Opportunity 2a) depends on "file unchanged since last session" — but the brainstorm checks mtime, not content hash. mtime is a rough proxy that breaks on network filesystems, git operations that preserve timestamps, and tools that write files atomically via temp-and-rename. A broadcast engineer would never use a wall-clock timestamp as a sync reference; they'd use a frame counter (equivalent: content hash or git SHA).

**Buffer underrun vs. overrun tradeoffs.** The Session Context Cache (2a) optimizes for buffer hit rate (inject cached summary, skip read). Broadcast engineers know that buffer management requires planning for both underrun (cache miss, must re-read — this is the "cold start" the brainstorm is already solving) and overrun (cache hit on stale data — this is the risk the brainstorm acknowledges but doesn't fully address). The current proposal optimizes only for underrun. Overrun (serving a stale summary that leads the agent to the wrong mental model) is likely more costly than underrun because the agent may not know to distrust its context.

**Graceful degradation.** Broadcast chains are designed to degrade gracefully: if the uplink drops, the station cuts to a backup feed rather than emitting silence. The brainstorm has no graceful degradation spec. If cass is unavailable (index corruption, migration, heavy load), what do hooks do? If the insight store is locked, does the PostToolUse hook block or skip? The brainstorm assumes the plumbing works. In a production system, hooks that block on external processes will cause latency spikes visible to the user.

### Blind Spots

**P0 — No pipeline health monitoring.** The brainstorm adds four new data flows (insight capture, dead end capture, session digest, warm start injection) with no observability plan. A broadcast engineer would immediately ask: what's the monitoring? How do you know insights are being written? How do you detect when the injection pipeline is silently dropping data? The system can fail in non-obvious ways — hook runs but cass write fails silently, warm start injection fires but injects an empty file — and there's no detection mechanism proposed.

**P1 — Codec selection: structured vs. prose.** The brainstorm debates SQLite vs. markdown for the insight store (Open Questions) but treats this as a storage preference. A broadcast engineer would see it as a codec selection: markdown is a lossy codec for structured data (markdown insight blocks are human-readable but require a parser to extract fields reliably), while SQLite is lossless but requires a schema. The key question isn't which to pick — it's whether the extraction step (hook reads conversation output, parses insight blocks) can produce consistent structured output from free-form agent prose. If the parser is fragile, all downstream consumers are unreliable.

**P2 — Latency budget unspecified.** The PostToolUse hook fires after every tool call. If insight extraction adds 500ms to every tool call, a session with 200 tool calls adds 100 seconds of latency. The brainstorm doesn't specify a latency budget or propose async extraction (write to queue, process out-of-band). Broadcast engineers always specify latency budgets before adding pipeline stages.

**P3 — No concept of channel capacity.** cass context injection at session start is unbounded in the current proposal. If 50 sessions have touched a file, the warm start primer could inject thousands of tokens of prior context. There's no channel capacity model — no maximum injection size, no priority ranking for which prior context is most relevant, no pruning strategy.

---

## Discipline 3: Intelligence Analysis — Multi-Source Fusion

### Frame

Intelligence analysis (SIGINT, HUMINT, OSINT fusion) has developed rigorous tradecraft for exactly the problem the brainstorm describes: synthesizing signals from multiple sources of varying reliability into actionable assessments. The IC (Intelligence Community) developed source grading, analytic confidence levels, and structured analytic techniques (SATs) after catastrophic failures from unvetted source fusion.

### Pattern Matches

**Source grading and reliability codes.** NATO and IC use structured source reliability codes (A-F for source reliability, 1-6 for information credibility). The brainstorm treats all session insights as equivalent signals. An insight from a session where the agent was confused, retried the same tool five times, and ultimately failed the task should be rated F-6 (unreliable source, unconfirmed information). An insight from a session that shipped a working bead with no retries should be rated A-1. Without source grading, multi-source fusion produces analytical noise, not intelligence.

**Analysis of Competing Hypotheses (ACH).** ACH is a structured technique for evaluating multiple hypotheses against the same evidence set, specifically designed to counter confirmation bias. The brainstorm's Agent Success Patterns (3b) will build profiles of which agents succeed on which task types. Without ACH-style controls, this risks confirmation bias: an agent that has historically succeeded on database code gets routed to database tasks, succeeds (because it's the best fit), and the profile reinforces itself — but the system never tests whether a different agent would have done equally well. This is the IC's "echo chamber" failure mode.

**Need-to-know vs. need-to-share tension.** Intelligence failures (9/11 Commission findings, WMD assessments) often stem from over-compartmentalization: relevant intelligence exists but wasn't shared with the analyst who needed it. The brainstorm's system is the inverse problem — it makes everything available (cass indexes everything, warm start injects everything relevant). The IC learned that both extremes fail. The solution is structured dissemination: intelligence is tagged by relevance criteria, and recipients get what they need to act, not everything that exists.

**Tradecraft standard: alternative analysis.** IC analysts are trained to produce "red team" assessments — what would the evidence look like if our hypothesis is wrong? The brainstorm has no equivalent. Dead ends are captured as "approach X failed" without capturing "what would success have looked like?" or "what evidence would tell us to retry this approach?" This makes dead ends permanent in a way that IC tradecraft would reject.

### Blind Spots

**P0 — No confidence calibration mechanism.** The brainstorm has no equivalent to IC analytic confidence levels (Low / Moderate / High confidence). When the warm start primer injects "last session concluded that X," the receiving agent has no basis for calibrating how much to trust that conclusion. IC analysts who ignore confidence levels have contributed to intelligence failures of historic magnitude. The session intelligence system will produce lower-stakes but structurally identical failures: agents confidently acting on miscalibrated prior intelligence.

**P1 — Collection vs. production conflation.** IC tradecraft strictly separates collection (gathering raw signals) from production (synthesizing into finished intelligence). The brainstorm conflates these: /reflect produces prose (collection artifact) and the proposal is to extract structured data from it (production step) in the same pipeline. This conflation makes quality control impossible — you can't audit collection without corrupting the production signal, and you can't improve production without re-running collection. The insight pipeline needs explicit collection/production boundary.

**P1 — No deception detection.** Intelligence analysis explicitly models the possibility that sources are compromised or adversarial. In the context of session intelligence, the relevant failure mode is: what happens when a session was led astray by a hallucination, injected bad insights into the store, and now those bad insights are surfaced to future sessions as context? This is "agent deception" in a non-adversarial sense — the source wasn't lying but its output was wrong. The brainstorm has no mechanism for detecting when injected context is systematically leading agents astray.

**P2 — Warning intelligence vs. current intelligence.** IC distinguishes warning intelligence (advance notice of threats) from current intelligence (situational awareness). The brainstorm's Failure Pattern Avoidance (3d) is warning intelligence — "before you proceed, here's what's failed before." But the system doesn't distinguish this from current intelligence (what's happening right now in the codebase). A warning from 6 months ago about a dead end may be current intelligence today if the underlying code hasn't changed, or it may be stale warning if it has. No staleness model exists.

**P3 — No finished intelligence dissemination standard.** IC produces finished intelligence products with standardized formats (NIE, DIA assessments). The brainstorm's output artifacts (insight blocks, session digests, dead end entries) have no standard schema. When a future agent receives injected context, it has no metadata telling it what kind of artifact it's reading, who produced it, or what confidence level it carries. This is equivalent to receiving raw intercepts with no finished intelligence wrapper.

---

## Discipline 4: Newsroom Workflow — Knowledge Management Under Time Pressure

### Frame

Newsrooms have operated under the session intelligence problem for a century: reporters and editors work on rotating deadlines, institutional knowledge must transfer between shifts, prior reporting must be findable under time pressure, and errors must be correctable without retracting the entire archive. The wire service model (AP, Reuters) solved multi-source fusion under deadline pressure. The morgue (clippings archive) was the original cass. Modern newsrooms (NYT, WaPo) have built sophisticated knowledge management systems under operational constraints that directly parallel Sylveste's.

### Pattern Matches

**The morgue and clip research.** Before digital archives, reporters consulted the morgue — physical clippings organized by topic, person, and event. The key practice was *pre-filing clips before writing*: before starting a new story, a reporter would spend 20 minutes in the morgue to understand what had already been established. The brainstorm's cass system is the digital morgue. The gap the brainstorm identifies (clips exist but reporters don't consult them) is exactly the historical problem that killed the clip-research discipline in the transition to digital: when clips became full-text searchable, reporters stopped doing structured pre-research because "I can search anytime." Retrieval became reactive rather than proactive, and stories started missing institutional context. The warm start primer (2b) is the digital equivalent of mandatory clip research — good instinct, but the newsroom lesson is that mandatory pre-research only works if it's frictionless and the output is scannable in under 2 minutes.

**Wire service beat reporting.** AP reporters on a beat maintain running files — structured notes on ongoing stories, open threads, and pending follow-ups. The brainstorm's session digest (1c) is this practice automated. Wire services found that beat files only remain useful if they're updated at the end of every session (not periodically, not on-demand). The Stop hook proposal is correct in mechanism. The risk is that it captures session activity, not beat-level context — the digest will be full of "read file X, grepped for Y" rather than "the standing question on this feature is Z."

**Editor-reporter workflow.** In newsrooms, the editor's job is not to do the reporter's work but to surface the right context ("did you talk to the building inspector?" / "the last story on this mentioned a lawsuit"). This is exactly what the smart routing proposals (3a, 3b) are trying to automate. The newsroom lesson: this only works when the editor has enough context to ask the right question. An editor who hasn't read the prior stories will ask generic questions. cass context injection is only as useful as the quality of prior session summaries.

**Corrections and errata.** Newsrooms have a mandatory corrections process: when a published story contains an error, a correction is published in the same outlet and tagged to the original. The brainstorm's dead end store has no corrections mechanism. If an insight is wrong, future sessions will continue receiving it until someone manually removes it. There's no "correction issued" state, no equivalent to the corrections column.

### Blind Spots

**P0 — No editorial judgment layer.** Newsrooms have editors whose job is to apply judgment about what context is relevant, what's background, and what's noise. The brainstorm's system has no editorial layer — everything that gets extracted from sessions is treated as equally worth injecting into future sessions. This is the equivalent of a newsroom that files every reporter's notebook verbatim into the morgue alongside finished stories. The signal-to-noise ratio degrades immediately. Something must make judgments about what's insight-worthy vs. routine — and the brainstorm's implicit answer (the agent's own Insight blocks) means agents are self-editing their contributions to institutional memory. This is a significant conflict of interest in journalistic terms.

**P1 — No evergreen vs. breaking news distinction.** Newsrooms distinguish evergreen content (always relevant background) from breaking news (time-sensitive, perishable). The brainstorm's insight store has no TTL (time-to-live) model. An insight about "prefer async patterns in this module" may be evergreen. An insight about "the tests were broken as of session X" is breaking news — it expires when the tests are fixed. Without TTL, the store accumulates stale breaking-news insights alongside evergreen ones, and agents can't tell the difference.

**P1 — No byline accountability.** Newsrooms require bylines because attribution drives accountability. If a story is wrong, the reporter is accountable; if a pattern emerges (a reporter frequently gets X wrong), editors adjust. The brainstorm's insight store has no equivalent: insights have no clear agent attribution, and there's no feedback loop from "insight was wrong" back to "which agent/session produced it and under what conditions." Without attribution, there's no systematic way to improve insight quality over time.

**P2 — Deadline pressure and the good-enough problem.** Newsrooms work under deadline, which means reporters routinely ship stories that are good enough rather than perfect. The brainstorm's compound-on-close (1c) and dead end capture (1b) are both post-session processes. Under the operational pressure of autonomous development (sessions closing because context windows fill, not because work is complete), the Stop hook will frequently fire in incomplete states. The digest will capture an in-progress state as a finished-session summary. Newsrooms solve this with the "30-second brief" — a mandatory structured fragment even under deadline. The brainstorm needs an equivalent: a minimum-viable session record that can be written even when the Stop hook fires on a partial session.

**P3 — Scoop competition and knowledge hoarding.** In competitive newsrooms, reporters hoard scoops — they don't file their best leads in the morgue because that information would benefit competitors. In multi-agent systems, this failure mode is less obvious but structurally present: if the insight store becomes noisy or unreliable, agents (i.e., future sessions) will learn to distrust it and stop consulting it, which means well-intentioned insights never compound. The brainstorm assumes agents will reliably use injected context. The reality is that agents already have strong priors (from training) and injected session context will be discounted if it conflicts with those priors. There's no mechanism to detect when the compounding system is being systematically ignored.

---

## Cross-Discipline Synthesis

Four disciplines, four independent paths to the same three structural omissions:

**1. No confidence/reliability model (P0 across all four disciplines).**
Clinical medicine, IC tradecraft, and newsrooms all have explicit reliability grading because they discovered the hard way that ungraded multi-source data produces worse decisions than no data at all. The brainstorm's insight and dead-end stores will produce the same failure at smaller scale. Every artifact written to the insight store needs a minimum schema: `source_agent`, `session_id`, `confidence` (low/medium/high), `domain` (file paths, feature area), and `expires_at` (or `is_evergreen: true`).

**2. No correction/retraction mechanism (P1 across clinical and newsroom disciplines).**
Stored intelligence that cannot be retracted will be wrong and will remain wrong. Dead ends that are later resolved, insights that encode incorrect assumptions, and warm-start primers that describe a codebase state that no longer exists are all forms of stale intelligence. The store needs a `superseded_by` field from day one.

**3. No observability / no feedback loop from consumption to production (P0 in broadcast, P1 in IC).**
The brainstorm asks "how do we measure compounding?" in Open Questions. The answer from IC tradecraft and broadcast engineering is the same: instrument consumption, not just production. Track when an injected insight led to a decision (consumption), not just when it was stored (production). Without consumption metrics, you cannot distinguish a compounding system from a write-only archive.

---

## Severity Index

| Finding | Discipline | Severity | Description |
|---------|-----------|----------|-------------|
| No confidence/reliability model on stored insights | Clinical, IC, Newsroom | P0 | Bad insights injected with the same authority as good ones |
| No pipeline health monitoring | Broadcast | P0 | Silent failures in hook pipeline undetectable |
| No consumption feedback loop | IC, Broadcast | P0 | Cannot distinguish compounding from write-only archive |
| No provenance/attribution model | Clinical, Newsroom | P1 | Cannot trace, weight, or retract bad insights |
| mtime vs. content hash for cache invalidation | Broadcast | P1 | Cache invalidation breaks on git ops and atomic writes |
| No correction/retraction mechanism | Clinical, Newsroom | P1 | Stale intelligence permanently injected into future sessions |
| No conflict detection for contradictory signals | Clinical, IC | P1 | System silently injects contradictory context without flagging |
| Latency budget unspecified for hooks | Broadcast | P1 | PostToolUse insight extraction could add 100s of latency |
| No editorial judgment layer | Newsroom | P1 | Self-editing conflict; no filter between routine and insight-worthy |
| No evergreen vs. TTL distinction | Newsroom | P1 | Breaking-news insights expire; store doesn't know this |
| Collection/production conflation in /reflect | IC | P1 | Cannot audit or improve quality without separating phases |
| Confirmation bias in agent success profiling | IC | P2 | Best-fit routing reinforces itself without adversarial testing |
| No graceful degradation spec for hooks | Broadcast | P2 | Hook blocks if cass unavailable; latency spikes under load |
| Channel capacity for injection unspecified | Broadcast | P2 | Unbounded warm-start injection can flood context window |
| No "resolved" state for dead ends | Clinical | P2 | Dead ends from 2024 codebase injected in 2026 without review |
| No minimum viable session record | Newsroom | P2 | Stop hook on partial session writes in-progress state as finished |
| Observer effect on insight quality | Clinical | P3 | Agents optimize insight blocks for extraction, not accuracy |
| No alternative analysis / red-team discipline | IC | P3 | Dead ends stored without "what would retry success look like?" |
| No "scoop hoarding" detection | Newsroom | P3 | System cannot detect when injected context is systematically ignored |
