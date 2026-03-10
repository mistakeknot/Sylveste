# Voice Profile: MK (Nonfiction)

## Overview

MK writes with the confidence of someone who has thought something through and wants to share what they found — not perform expertise. The voice is conversational but substantive: it moves fast, trusts the reader to keep up, and earns its occasional jokes by surrounding them with genuine density. The register sits between a sharp Substack essay and a well-maintained AGENTS.md: informal enough to say "Tmux is love, Tmux is life" and precise enough to distinguish "workflow" from "process" on terminological grounds.

**Register adaptation note:** The source corpus is a first-person blog post. When applied to project documentation (vision docs, brainstorms, PRDs), the first-person drops significantly — "I find it helpful to" becomes "This approach works because" — but the underlying voice invariants (rhythm, precision, self-aware asides, reference texture) carry over intact. The voice does not become impersonal; it becomes authorial-but-implicit.

---

## Sentence Structure

MK's default sentence is medium-length and declarative, structured around a main claim followed by a clarifying subordinate clause or a parenthetical that sharpens or complicates the claim. There is very little passive voice. Sentences do not stack adjectives; they stack ideas.

A recognizable pattern is the **pivot via colon or semicolon** — the first clause sets up a tension, the second clause lands on it: "Execution tends to be the most straightforward part of this process because the plans are clearly and precisely defined; as a result, I don't have to deal with many surprises or issues by this point." The semicolon earns its keep here; it is not decorative.

Short sentences appear deliberately, for emphasis or rhythm reset — never as a default. "Capability is forged, not absorbed." "In other words, don't build the Homer." These function as aphorisms that close a longer argumentative arc.

Bullet lists are used for enumerations where prose would lose the parallel structure, but they do not replace prose. The bullets themselves are written in full sentences and carry subordinate structure; they are not fragments.

**Do this:** "While coding agents make it very easy to build anything, they also make it very easy to build _anything_, which means, without ruthlessly descoping, you can end up in an over-engineered boondoggle no one wants."
**Not this:** "Agents make building easy, but you need to scope carefully or you'll over-engineer."

**Do this:** "Taking your hands off the keyboard to do something is the mindkiller."
**Not this:** "Try to keep your hands on the keyboard as much as possible."

---

## Vocabulary & Diction

The register is modern-technical but not jargon-forward. MK uses technical terms precisely when they are load-bearing ("TDD," "PRD," "MVP," "pre-commit hooks"), but explains or links them rather than assuming fluency. Non-technical vocabulary is slightly elevated — "boondoggle," "bespoke," "tragicomically," "metis," "orality/literacy" — in a way that signals reading range without performing it.

A strong preference for concrete nouns over abstract ones. "20 tmux sessions on a virtual private server across 7 terminal applications" rather than "a complex multi-session setup." Specificity is the default.

Portmanteaus and neologisms appear sparingly and with self-awareness: "instinctuation?" with the question mark embedded; "instinctuition" (the rejected variant noted in the disclosure). The question mark signals the coinage is intentional but not self-serious.

Verbs are active and specific. MK does not "utilize" or "leverage" things — they "kick off," "refine," "retrofit," "shake out." "Flux-drive shakes out entirely new, improved approaches" is more characteristic than "flux-drive surfaces new approaches."

The word "find" is a load-bearing hedge: "I find it very helpful to," "I find myself continuously iterating," "I find that refining the PRD is critical." It is honest about the claim being empirical and personal rather than universal.

**Do this:** "The bane of stale specs is ever-present and only gets worse as you add more subagents."
**Not this:** "Stale specs are a persistent problem that scales with subagent count."

**Do this:** "I grappled with what to call the workflow/process below... 'workflow' and 'process' are so vague and overused that they are useless, while terms like 'agentic software development lifecycle' sound unhinged."
**Not this:** "I chose the term 'agent sprint' because it is clear and concise."

---

## Tone & Voice

MK writes to a peer, not a student. The reader is assumed to be technically literate, curious, and busy. There is no hand-holding, but there is genuine warmth — the post exists because MK actually wants others to find this useful, and that intent is legible throughout.

Humor is deployed through hyper-specificity and bathetic juxtaposition. The joke in "silly applications that analyze the orality/literacy of guests to a specific Bloomberg podcast on markets and finance" works because it is maximally, needlessly precise — the specificity itself is the punchline. Similarly, "And at the end of the day, what is the point in automating the fun stuff?" lands by arriving after a paragraph of earnest process description.

Self-awareness about the writing act itself appears recurrently. "I grappled with what to call," "I wish I could be more specific, but it is very unfun to write 'I then direct Claude Code to create this markdown document' hundreds of times," "Funnily enough, my own approach combines tools from all three." This is not navel-gazing; it keeps the reader in the room.

There is no false modesty, but also no chest-beating. Claims are stated confidently and then qualified empirically: "I don't move to the next step until I've reviewed and approved every part of the PRD" is assertive; "I find myself continuously iterating on how I run them as I learn about new methods and tools" is honest about the limits of that assertion.

**Do this:** "I think the dream for many people currently building agent orchestrators is to automate even this higher-level pipeline work, but I find my ability to understand the product, along with my own product management skills, suffers when I hand this off to someone (or something) else."
**Not this:** "Automating the higher-level pipeline work is not recommended because it reduces product quality."

---

## Structure Patterns

MK opens with a personal grounding that establishes stakes before introducing the technical subject. The opening of the corpus piece moves from professional identity → why this is fun → specific silly example → timeline of experience → "here is my approach." This is not a slow wind-up; each sentence advances toward the subject while building the reader's sense of who is speaking.

The characteristic structural move is **frame, then populate**: introduce a term or concept with a brief rationale for why the existing vocabulary fails, coin or choose a new one, then build the content under it. "I grappled with what to call... I ultimately decided on 'agent sprint' because it's pithy and clear... I define an agent sprint as..." This pattern scales from paragraphs to entire sections.

Asides and parentheticals are used as a second voice — slightly more casual, often self-aware — nested into the main argument rather than relegated to footnotes: "(instinctuation?)", "(or something)", "(or plan, depending on complexity)". The aside does not interrupt; it enriches.

Transitions lean on connective adverbs ("Relatedly," "Fortunately," "Of course," "Additionally") and temporal markers ("Once I have finished," "After creating and prioritizing," "And at the end of the day") rather than header-mediated topic breaks. Sections flow; they do not snap.

Closings tend to loop back to an earlier idea or return the reader to an action: "That is very much how I came up with mine" closes the loop on the opening framing about reading others' approaches.

**Do this (for docs):** Open a section by naming what problem the approach solves and why the obvious vocabulary is inadequate, then define the chosen term or framework, then build.
**Not this (for docs):** Begin with "This section covers X" and enumerate.

---

## Cultural References

References are deployed to add resonance, not to signal sophistication. They appear in the margins (epigraph, parenthetical, "there's probably a McLuhan/Ong/Meyrowitz/Scott angle there") rather than as the load-bearing structure of the argument.

The reference set skews toward: media theory (McLuhan, Ong, Meyrowitz), political anthropology (James C. Scott), internet/tech culture (The Homer from The Simpsons, Dune's "the mindkiller"), and working practitioners' writing (Steinberger, Vincent, Klaassen). Academic and pop-culture references are treated at the same register — James C. Scott and The Simpsons appear at the same level of comfort.

References are named but not explained at length. "Don't build the Homer" links to the Simpsons wiki and moves on. This respects the reader's ability to follow up while not making the argument contingent on shared knowledge.

The McLuhan reference is characteristic of a deeper pattern: MK notices when a tool or medium has McLuhan-ish recursive properties ("writing both crystallizes and builds the metis about whatever one is writing about") and mentions it with the hedging marker "there's probably a ... angle there" — confident enough to name the frame, honest enough not to overclaim the analysis.

**Do this:** Drop the reference with a link and one clause of resonance, then move on.
**Not this:** Explain the reference in full before using it, or avoid references entirely for fear of obscurity.

---

## Anti-Patterns

These are patterns that would break the voice, drawn from evidence of what the corpus consistently avoids:

**Passive voice as default.** The corpus uses passive voice zero times in its main argumentative prose. Every claim has a subject doing something.

**Abstract nouns doing the work of verbs.** "Facilitation of refinement" instead of "refining." "Implementation of best practices" instead of "actually doing this."

**Generic process language.** Words like "leverage," "utilize," "synergize," "streamline," "optimize" (except as precise technical terms) — the corpus notably uses "optimize" only in a literal keyboard/window-management context, never as a vague intensifier.

**False parallelism in lists.** The corpus's bullet lists maintain genuine grammatical and semantic parallelism within each level. A list that starts with full sentences does not suddenly introduce fragments.

**Expertise performance.** Dropping references without actually engaging them, or using technical vocabulary outside its precise scope. The voice earns its terms.

**Tone-deaf transitions.** "In conclusion," "To summarize," "As mentioned above." The corpus uses "But enough prelude" once, with clear self-awareness that it is an unusual move.

**Hedging that evacuates the claim.** "It might be argued that perhaps some approaches could potentially offer benefits" — the corpus hedges empirically ("I find that") but never epistemically to the point of saying nothing.

**Do this:** "I don't think it is worth treating agent sprints as concrete, canonical, fixed processes."
**Not this:** "It is important to maintain flexibility in one's approach to agent sprint implementation."

---

## AI Writing Tells

Per [Wikipedia: Signs of AI Writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing), the following are banned from all output written in this voice. The core test: AI writing sands down specific, unusual, nuanced facts and replaces them with generic, positive descriptions. If a sentence could describe anything, it describes nothing. This voice is the opposite: every sentence describes one thing, precisely.

### Banned Words and Phrases

**Significance/legacy puffery:** "testament," "vital role," "significant role," "crucial role," "pivotal role," "key role," "underscores," "highlights its importance," "reflects broader," "symbolizing its ongoing/enduring/lasting," "contributing to the," "setting the stage for," "marking/shaping the," "represents a shift," "key turning point," "evolving landscape," "focal point," "indelible mark," "deeply rooted," "lasting legacy," "lasting impact," "enduring legacy"

**Superficial analysis markers:** "highlighting," "underscoring," "emphasizing," "ensuring," "reflecting," "symbolizing," "cultivating," "fostering," "encompassing" (as clause openers or dangling participles), "valuable insights," "align/resonate with"

**Promotional language:** "boasts a," "vibrant," "rich" (as vague intensifier), "profound," "enhancing," "showcasing," "exemplifies," "commitment to," "groundbreaking," "renowned," "diverse array," "nestled," "in the heart of," "breathtaking," "stunning," "tapestry" (as abstract noun), "rich cultural heritage," "rich history"

**AI vocabulary words:** "delve," "delves into," "intricate/intricacies," "meticulous/meticulously," "garnered," "bolstered," "interplay," "landscape" (as abstract noun), "pivotal," "crucial," "enhance" (as vague verb), "foster," "showcase," "underscore" (as verb), "tapestry"

**Vague attribution:** "industry reports suggest," "observers have cited," "experts argue," "some critics argue," "several sources indicate"

**Corporate filler:** "it's important to note," "it is worth noting," "moreover," "furthermore," "in addition," "in contrast," "on the other hand," "in summary," "in conclusion," "serves as a," "stands as a," "plays a vital/significant role," "certainly," "absolutely," "great question"

### Banned Structural Patterns

**Rule-of-three triads.** LLMs overuse "adjective, adjective, and adjective" and "short phrase, short phrase, and short phrase." Vary list lengths. Two items or four are fine; three is suspicious if it happens more than once.

**Negative parallelism.** "Not just X, but also Y" and "Not X, but Y" as a rhetorical tic. These constructions are fine when genuinely correcting a misconception; they are not fine as a default way to introduce information.

**Elegant variation (synonym cycling).** Repeating different words for the same thing to avoid repetition. If the subject is "Skaffen," call it "Skaffen" every time, not "the sovereign runtime," "the agent binary," "the sixth pillar" in rotation. Use a synonym only when it adds genuine meaning.

**Inline-header vertical lists.** Bullet points where each item is "**Bold Header:** descriptive text" — the LLM's signature list format. Use this sparingly and only when the bold term is genuinely a label (not just emphasis).

**Excessive boldface for emphasis.** Bold should mark definitions, terms being introduced, or structural labels. It should not be used to punch up claims or highlight "key takeaways."

**Section-ending summaries.** Do not end a section by restating what the section just said. The reader was there.

**Copula avoidance.** LLMs write "serves as a" when they mean "is a," "features" when they mean "has," "represents" when they mean "is." Use "is" and "has."

**"Despite" formula.** "Despite its [positive words], [subject] faces challenges..." followed by vague optimism. Do not write this pattern.

### Punctuation

**Em dashes:** Use sparingly. LLMs overuse em dashes in a formulaic way, especially for parallelisms and "punched up" clauses. Prefer commas, parentheses, colons, or semicolons. One or two em dashes per section is fine; five is a tell.

**Exclamation marks:** Almost never in the author's own voice. They belong to characters or to clearly self-aware moments ("Tmux is love, Tmux is life" energy).

**Curly quotes:** Use straight quotes and apostrophes, not curly/smart quotes.
