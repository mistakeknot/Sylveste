---
track: distant
agents: [fd-oral-tradition-memory, fd-monastic-scriptoria, fd-cartographic-wayfinding, fd-fermentation-culture]
target: docs/brainstorms/2026-03-30-session-intelligence-compounding-brainstorm.md
---

# Flux-Drive Review: Session Intelligence Compounding
## Track C — Distant Domain Analysis

Reviewed against four knowledge domains with structural isomorphisms to the brainstorm's architecture. Each section names the specific mechanism, not just the metaphor, then maps it to the brainstorm.

---

## Domain 1: West African Griot Oral Tradition

The griot is not merely a storyteller — they are a living knowledge index with retrieval protocols built into their social role. Several mechanisms in the oral tradition predate and parallel what the brainstorm is trying to build.

### Mechanism 1.1 — Genealogical Disambiguation

When two griots possess conflicting accounts of the same event, the tradition does not average them — it tags the account with its lineage (which griot family transmitted it, from which village, in which performance context). The lineage IS the provenance. Consumers of the knowledge can then apply their own weighting.

**Map to brainstorm:** The brainstorm's insight capture (Opportunity 1a) writes insights to a store and trusts cass to surface them later. It has no lineage model. An insight extracted from a session that spent 3 hours on a failed approach carries different epistemic weight than one from a session that produced a shipped change. The current design conflates them. The griot mechanism suggests tagging every insight with its originating session's outcome state (landed/abandoned/in-progress) and the file's subsequent change history. Future retrieval should display this lineage — "this insight comes from a session that was reverted 2 weeks later."

### Mechanism 1.2 — Call-and-Response Priming

Before a griot performs, they receive a social cue (a patron, a ceremony type, an audience composition) that primes which subset of the corpus is relevant. The full corpus is never activated — the cue filters it. This is not search; it is activation gating by context.

**Map to brainstorm:** Opportunity 2b (Warm Start Primer) and Opportunity 3a (Context Warmth in Routing) both attempt a version of this, but they treat context injection as retrieval from a store. The griot mechanism reveals a different model: the signal that matters is not "what was recently discussed" but "what performance mode is this session entering." A session starting with /route has a different activation gate than one starting with a file read or a bug report. The warm-start primer should key off the session's entry point (which command, which file, which bead type) not just recency. Recency is a weak proxy for relevance; entry-mode is a stronger one.

### Mechanism 1.3 — Purposeful Omission as Signal

Griots maintain a parallel corpus of what is NOT said in public performance — suppressed versions, contested accounts, dangerous knowledge. This omission corpus is as carefully curated as the main one. Knowing what was silenced tells you as much as knowing what was said.

**Map to brainstorm:** Dead End Capture (Opportunity 1b) tries to record failed approaches, but the brainstorm frames it symmetrically with insight capture — same store format, same retrieval path. The griot tradition suggests that dead ends need a distinct epistemic status, not just a category tag. An approach that was omitted because it was actively dangerous (e.g., a data migration pattern that caused corruption) is categorically different from one that was merely suboptimal. The store should distinguish: (a) approaches tried and abandoned for performance reasons, (b) approaches ruled out on principle before execution, (c) approaches that caused harm and were reverted. Only category (c) warrants a PreToolUse warning. Categories (a) and (b) are lower-urgency context. The current design collapses all three.

### Mechanism 1.4 — The Nyamakala Specialization

Griots belong to a caste (nyamakala) that specializes in knowledge transmission. Other castes do not perform this function, even if they have relevant knowledge. The specialization is structural, not just skill-based — it creates a clear authority boundary and prevents diffuse responsibility.

**Map to brainstorm:** The brainstorm distributes insight/dead-end capture across multiple hooks (PostToolUse, Stop, /reflect, /handoff). This diffuses responsibility — any system that might capture knowledge, will sometimes capture it, and no system owns the corpus. The griot mechanism suggests designating a single specialized subsystem as the knowledge transmission layer. All other systems (cass, interstat, interspect) route knowledge signals to it; none of them store insights themselves. This is an architectural recommendation: define a canonical knowledge substrate (the brainstorm gestures at `~/.interseed/insights.db`) and make all capture hooks write there exclusively, rather than letting each tool accumulate its own partial record.

---

## Domain 2: Medieval Benedictine Scriptoria

Benedictine scriptoria operated under a centuries-long preservation mandate. They developed mechanisms for copying, verifying, and transmitting knowledge across time horizons that no single person would live through. Their constraints — error propagation, scribal mortality, storage limits — are structurally similar to the constraints in the brainstorm.

### Mechanism 2.1 — The Exemplar and the Copy

Every manuscript copy was made from a designated exemplar — an authoritative source document. Copies were not made from other copies if the exemplar was available. When the exemplar was unavailable, copies were flagged as "derived" and carried reduced authority. This preserved error traceability: if a corruption appeared, you could reconstruct which copy generation introduced it.

**Map to brainstorm:** Opportunity 2a (Session Context Cache) proposes injecting cached summaries from prior sessions in place of file reads. This is copying from a copy. The brainstorm notes the risk of "stale summaries" but treats it as a cache invalidation problem. The scriptorium mechanism reveals it as a provenance problem — the summary is a derived copy, and its authority degrades with each generation of derivation. A session that summarizes a file produces a first-order copy. A session that reads that summary and generates its own understanding produces a second-order copy. By the third session, the injected context may bear little relation to the actual file. The mechanism suggests: never inject a cached summary without surfacing its derivation depth and the number of file changes since the summary was written. Authority of the cached summary should decay explicitly, not implicitly through mtime checks alone.

### Mechanism 2.2 — Marginal Glosses

Scribes added glosses — commentary, corrections, cross-references — in the margins of manuscripts. These were structurally separate from the main text and carried different epistemic weight. A gloss was not the text; it was a reader's annotation on the text. Over centuries, some glosses became incorporated into the main text (gloss creep), corrupting the original.

**Map to brainstorm:** The insight capture mechanism (Opportunity 1a) extracts `★ Insight` blocks from session output and writes them to a shared store. If future sessions inject these insights as context before reading files, the insights will eventually be treated as equivalent to the file contents themselves — gloss creep. A session will read an insight that says "this function uses lazy evaluation for performance" and not read the function itself, even if the function was refactored 3 weeks ago to be eager. The mechanism suggests maintaining a hard structural separation between primary sources (file contents, git history) and derived annotations (insights, summaries, dead ends). The retrieval interface should always present them in separate layers, never merged.

### Mechanism 2.3 — The Chapter Reading Protocol

Benedictine rule required daily reading of specific texts at specific hours. The schedule was not ad hoc — each text had a canonical time and context for reading. This created predictable activation cycles that kept the corpus alive without requiring agents to hold it in working memory continuously.

**Map to brainstorm:** Opportunity 1c (Compound on Close) triggers at session end. This is the right moment for some signals (session digests) but wrong for others. Design rationale insights are most useful at the moment a related file is next touched, not at session start when the new session doesn't yet know what it's going to do. The chapter reading protocol suggests that different insight types should have different activation schedules keyed to context transitions, not session lifecycle events. An insight about a specific file should surface when that file enters scope (at Read time), not at SessionStart. An insight about a test failure pattern should surface when a similar test is about to run. The brainstorm conflates "when to capture" with "when to surface" — these should be designed separately.

### Mechanism 2.4 — The Quire Signature

Large manuscripts were assembled from quires — folded gatherings of pages. Each quire was signed (numbered) so the binder could assemble them in order even if the quire came apart. The signature was metadata that made the document self-describing at the structural level.

**Map to brainstorm:** The session digest format proposed in Opportunity 1c (files read >3 times, tools retried, insights generated) captures events but not structure. The brainstorm assumes cass will make these digests searchable, but cass indexes text — it doesn't understand the structural relationships between events in a session. The quire signature mechanism suggests: session digests should include a structural signature that captures the session's arc (what was the entry problem, what was the resolution path, what changed between start and end state). This is not a summary; it is a navigation key. A future session should be able to read the signature and decide whether the full digest is worth loading, without reading the digest at all.

---

## Domain 3: Polynesian Wayfinding

Polynesian navigators crossed thousands of miles of open ocean without instruments, using environmental signals (star paths, swell patterns, bird behavior, phosphorescence) to maintain orientation. They did not navigate by storing a map — they navigated by reading continuous environmental feedback and maintaining a mental model of the vessel's position relative to a moving reference frame.

### Mechanism 3.1 — Dead Reckoning via Accumulated Signals

Polynesian navigators tracked their position not by a single fix but by integrating many low-signal observations over time. No individual signal was sufficient; their combination was. The navigator maintained a running model that weighted recent signals more heavily while preserving older signals as context for anomaly detection.

**Map to brainstorm:** Opportunity 3b (Agent Success Patterns) proposes combining interspect evidence with interstat cost to build agent profiles. The brainstorm treats this as a join across two databases. The wayfinder mechanism suggests a different architecture: agent profiles should be maintained as running models, not computed on demand from raw tables. Each new piece of evidence (a correction, a success, a cost data point) updates the model incrementally. The model is never "recalculated from scratch" — it is continuously maintained. This matters because it changes the failure mode: a model that accumulates state will drift gradually when evidence changes, giving operators time to detect the drift. A model recomputed from raw tables can flip discontinuously when the underlying data changes.

### Mechanism 3.2 — Etak (Moving Island Reference Frame)

The most distinctive Polynesian navigational concept is etak — the navigator conceptualizes the canoe as stationary and the islands as moving. This inverts the western frame but is computationally equivalent. The advantage is that it makes the navigator's own uncertainty explicit: it's clearer to track "where is the island relative to me" than "where am I relative to the island" when the navigator cannot directly observe themselves.

**Map to brainstorm:** The entire brainstorm frames sessions as moving through a static codebase. Sessions "read files," sessions "encounter errors," sessions "produce insights." But from the codebase's perspective, sessions are the moving reference frame. The codebase accumulates a history of which sessions touched it, in what order, with what outcomes. An etak-style inversion would ask: for each file, what is its current "session pressure" — how many active sessions are working near it, what is their recency, what outcomes have they produced? This is structurally what Opportunity 3a (Context Warmth) gestures at, but the brainstorm only uses this for routing prioritization. The etak frame suggests it should be the primary lens for understanding the codebase's current state — a file's "warmth" is not just a routing hint, it is a real property of the file that affects what a new session needs to know before touching it.

### Mechanism 3.3 — Swells as Out-of-Band Signal

Ocean swells travel thousands of miles and maintain consistent bearing independent of local wind conditions. Navigators used swells to maintain bearing even in overcast conditions when star paths were invisible. Crucially, swells are out-of-band — they carry signal from a distant source that is orthogonal to the local environment.

**Map to brainstorm:** The brainstorm's signal sources are all in-band — they come from the sessions themselves (insights, dead ends, digests, cost data). There are no mechanisms for detecting out-of-band signals: upstream dependency changes, API deprecations detected by interject, test suite drift over time, or changes in the external environment that affect work the codebase is doing. The swell mechanism suggests adding an out-of-band signal layer to the routing intelligence. Before a session begins work on a file, check: have any external signals (interject scans, upstream repo changes) affected this domain since the last session that worked here? An external API change is a swell — it doesn't show up in session history but it changes what the next session will encounter.

### Mechanism 3.4 — The Pwo Certification

Master navigators (pwo) were certified through a formal ceremony that recognized their integration of multiple knowledge domains (star paths, swells, biology). The ceremony was not about demonstrating recall — it was about demonstrating that the navigator could synthesize across domains in real conditions. The certification created a trust boundary: a pwo's judgment could be followed without verification; an uncertified navigator's could not.

**Map to brainstorm:** The model cost optimization proposal (Opportunity 3c) and agent success patterns (3b) assume that the system can automatically route to cheaper or more appropriate models based on historical data. But the brainstorm has no mechanism for certifying when the routing model is trustworthy enough to be used autonomously. The pwo mechanism suggests: routing automation should require demonstrated calibration before taking autonomous action. A model routing system that has been correct >85% of the time on a given phase type (verified against outcomes) can route autonomously. One that hasn't reached that threshold surfaces a suggestion and asks for confirmation. The Open Question in the brainstorm ("fully automated or human-approved?") has a structural answer from this mechanism: calibration-gated automation, not binary choice.

---

## Domain 4: Fermentation Science

Fermentation involves maintaining living microbial cultures over long time horizons. The central challenge is not starting a culture but maintaining it — keeping it viable, preventing contamination, managing the conditions that allow beneficial organisms to outcompete harmful ones.

### Mechanism 4.1 — The Starter Culture and Passaging

Sourdough starters, kombucha SCOBYs, and cheese cultures are maintained by passaging — periodically taking a portion of the culture, feeding it, and discarding the rest. Passaging prevents the culture from becoming exhausted and maintains a population of active organisms. Without passaging, the culture acidifies, beneficial organisms die, and the culture is overtaken by contaminants.

**Map to brainstorm:** The insight store (proposed in Opportunity 1a) will accumulate without a passaging mechanism. Over time, it will contain: insights that are no longer valid (the code they describe was refactored), insights that were wrong from the start, duplicate insights about the same pattern, and insights from abandoned experiments. The brainstorm has no staleness management. A passaging mechanism would periodically evaluate which insights have been surfaced to sessions and found useful vs. surfaced and ignored, and would prune the latter. The brainstorm does ask "how do we measure compounding? Track 'insight surfaced and useful' vs 'insight surfaced but ignored'" — but it frames this as calibration. The fermentation mechanism reveals it as a maintenance requirement. Without active pruning, the insight store will become a burden rather than an asset.

### Mechanism 4.2 — pH as Continuous Health Signal

Fermenters monitor pH continuously because it is a leading indicator of culture health, not a lagging one. A pH drop tells you that acid-producing organisms are active before you can taste the result. Waiting for an observable outcome (off flavor, failed batch) means you've already lost the culture.

**Map to brainstorm:** The brainstorm's measurement approach is entirely lagging — it tracks outcomes (sessions that landed, cost saved, tokens reduced). There are no leading indicators of system health. If the insight store is accumulating low-quality insights faster than high-quality ones, you won't detect this until sessions start being misled. The pH mechanism suggests: define leading indicators for the intelligence system. Candidate signals: ratio of insights surfaced-and-used to insights surfaced-and-skipped (declining ratio = store quality degrading), rate of new dead ends discovered vs. old dead ends re-encountered (low rate = system is working; high rate = sessions not reading history), distribution of session digest sizes over time (growing digests = sessions are confused and re-exploring). These should be monitored continuously, not reported post-hoc.

### Mechanism 4.3 — Contamination and Competitive Exclusion

The primary defense against contamination in fermentation is competitive exclusion — maintaining a robust population of the desired organisms such that contaminants cannot gain a foothold. The culture protects itself by being vigorous, not by being sterile. Attempting to make fermentation sterile destroys the culture.

**Map to brainstorm:** The brainstorm's risk model for context caching (Opportunity 2a) is contamination by stale data — a cached summary that no longer reflects the file. The proposed solution (check mtime, cache invalidation) is a sterility approach. The competitive exclusion mechanism suggests a different defense: maintain a high density of fresh, high-confidence signals so that stale signals are crowded out. If a file has been touched by 5 recent sessions, the weight of their combined context will naturally dominate a single stale summary without needing explicit invalidation. The design implication: context retrieval should aggregate multiple signals and surface the distribution, not return a single cached answer. A reader who sees "5 recent sessions describe this function as X, 1 older session describes it as Y" can make their own judgment. A reader who receives a single cached answer cannot detect the contamination at all.

### Mechanism 4.4 — Terroir as Uncodifiable Context

Wine fermentation is famous for terroir — the specific combination of soil, climate, microbiome, and viticulture that makes a wine's character irreproducible outside its origin. Terroir is not a defect of imprecise measurement; it is the mechanism by which the local environment becomes encoded in the product. Attempts to standardize it destroy the signal.

**Map to brainstorm:** The brainstorm seeks to make session intelligence portable and general — insights should surface across sessions, agent profiles should generalize across domains, model routing should apply project-wide. But much of the highest-signal intelligence is specific to a particular combination of developer, codebase region, and moment. An insight that "lazy evaluation in this module causes GC pressure under high load" is not portable to other modules or other projects. If forced through a general store and retrieval system, it will be surfaced inappropriately and erode trust in the intelligence system. The terroir mechanism suggests: some intelligence should be deliberately scoped and not generalized. The store should support explicit locality bounds on insights — "valid for: this file," "valid for: this module," "valid for: this project, this bead type." Retrieval that crosses a locality bound should surface a warning, not a transparent match.

---

## Cross-Domain Patterns

Three structural patterns appear across all four domains:

**1. Provenance decay is structural, not incidental.** Every domain has mechanisms for tracking how derived a piece of knowledge is from its source. Griot lineage, scriptorium exemplar chains, wayfinder signal integration, fermentation culture passaging — all treat authority as time-and-derivation-indexed. The brainstorm treats knowledge provenance as a nice-to-have (cass tagging). It should be a first-class structural property of every record in every store.

**2. Activation gating is more efficient than retrieval.** Griots use performance context to gate which corpus activates. Wayfinders use vessel orientation to determine which signals are relevant. Fermenters use pH to decide which intervention to apply. None of these systems search a store — they apply a context-sensitive filter before any retrieval happens. The brainstorm is almost entirely retrieval-based. The missing architectural primitive is a gating layer that determines what kind of session this is before deciding what to retrieve.

**3. Maintenance is not cleanup — it is continuous operation.** All four domains treat maintenance as normal operation, not exception handling. Passaging is not error recovery; it is the mechanism by which the culture remains viable. The chapter reading protocol is not remediation; it is how the corpus stays alive. The brainstorm has no continuous maintenance model — it has capture mechanisms and retrieval mechanisms, but no mechanism for keeping the intelligence corpus healthy over time. This is the most significant structural gap.
