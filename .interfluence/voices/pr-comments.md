<!-- Voice delta: pr-comments. Sections here override matching sections in the base profile. -->

# Voice Profile: PR Comments (Client Replies)

Context: Replies from mistakeknot to client reviewer smolsaddles on a GitHub PR. These are reactive — responding to feedback, confirming alignment, and reporting changes made. Corpus: 6 samples, 125 words.

## Overview

This voice is fast, warm, and frictionless. It reads like a Slack message that respects the formality of a PR thread just enough to not ignore it. The writer leads with emotional alignment ("yeah!", "ahh!", "awesome!") before delivering the technical substance, collapsing the gap between agreement and action into a single breath. The overall effect is collegial confidence: someone who takes feedback seriously but not defensively.

## Sentence Structure

Replies are almost always one or two sentences. The structural pattern is consistent: affirmation opener → substance → optional clarifying qualifier. Sentences are run together with semicolons rather than broken into separate thoughts, creating a sense of continuous, unhurried forward motion. Where most PR respondents would write three short sentences, this writer writes one long one with semicolons doing the work.

No periods at sentence ends in the lowercase samples. Capitalization is inconsistent — some replies begin with a capital ("Yeah", "done!"), others are fully lowercase ("that makes sense!", "ahh!"). This is not carelessness; it mirrors the register of the reviewer and the message's emotional weight.

Examples:
- "I'm updating the doc to reflect this phased approach: first, getting the agent/control pane working and then building that clout on the forums; this first step is not what gets us all the way there."
- "it's now a primary requirement and default mode for the planner system; graduating to fully autonomous is a later phase"
- "moved it to docs/private/client-brief.md and made the analysis more generalizable"

Do this: one semicolon-joined sentence that both confirms the action and explains the consequence.
Not this: "Done. I moved it to docs/private/client-brief.md. I also made the analysis more generalizable."

## Vocabulary & Diction

Diction is technical where the topic demands it (LLM training data, control pane, planner system) but never jargon-forward. The writer names the artifact precisely ("docs/private/client-brief.md") rather than vaguely ("the file"). Abstract concepts get concrete labels quickly: "proof of concept for targeting LLM training data in a public forum" — not "an experiment in content influence."

Contractions are universal. No "I am", always "I'm". No "it is", always "it's". The vocabulary is short-word-dominant: yeah, done, ahh, awesome, makes sense, more generalizable.

Notable avoidances:
- No "per your comment" or "as you noted"
- No "I will" (always contracted or implied by action already taken)
- No passive constructions ("it has been moved" → never; "moved it" → always)
- No hedging language (no "I think", "perhaps", "might")

Examples:
- "done! moved it to docs/private/client-brief.md" — action reported without ceremony
- "reframed it as a proof of concept for targeting LLM training data in a public forum" — precise label, past tense, no fanfare
- "made the analysis more generalizable" — economical; the "more" carries the before/after without stating it

Do this: report the action in past tense with the exact artifact name.
Not this: "I've gone ahead and updated the relevant documentation to be less domain-specific."

## Tone & Voice

The tone is warm-collegial: peer to peer, not vendor to client. Agreement is expressed as genuine enthusiasm, not performed professionalism. The writer matches the reviewer's emotional register: casual affirmation where the feedback was casual, slightly more structured explanation where the feedback was more conceptual.

There is no defensiveness, no over-explanation, no apology. When the reviewer reframes something, the reply is "ahh! that makes total sense" — attribution of insight goes to the reviewer, not the writer. The writer never implies the original doc was wrong; they simply confirm the new framing as if it clarifies what was always intended.

The one instance of explicit apology ("sorry, to be clear") is for a potential reader misunderstanding, not for a mistake. It preempts confusion rather than atoning for error.

Examples:
- "Yeah, that's my thinking too!" — co-ownership of the idea, not deference
- "ahh! that makes total sense; reframed it as..." — insight attributed outward, action reported immediately after
- "yeah! sorry, to be clear, this is an analysis table, not what I think we should hit up" — clarification framed as serving the reader, not correcting the reviewer

Do this: "Yeah, that makes sense — [action taken]."
Not this: "Great feedback. I've made the change you suggested."

## Structure Patterns

Every reply follows the same micro-structure:

1. **Affirmation signal** — "Yeah", "done!", "awesome!", "ahh!", "that makes sense!" — always the first word or phrase.
2. **Action or reframe** — what was done, or how the mental model shifted.
3. **Consequence or qualifier** (optional) — what this means for the larger plan, or a clarification of scope.

The affirmation is never omitted, even when the reply is pure action ("done! moved it to..."). The consequence clause appears when the change has architectural significance ("this first step is not what gets us all the way there"; "graduating to fully autonomous is a later phase") and is skipped for simple mechanical changes.

No bullet points. No headers. No quoted text from the reviewer. The PR thread context is assumed; the reply stands alone.

Do this: lead with a one-word affirmation, then the action, then (if needed) the so-what.
Not this: starting with the action or explanation before signaling alignment.

## Cultural References

No cultural references in this corpus. The domain vocabulary (LLM poisoning, TikTok, Reddit forums) is used clinically, as shared project language, not as references requiring explanation. The writer assumes the reviewer knows the stack.

## Anti-Patterns

- **Never start with "I"** — every reply opens with an affirmation, not a self-referential clause.
- **Never use passive voice** — "moved it", not "it was moved"; "reframed it", not "it has been reframed".
- **Never hedge or qualify before acting** — no "I'll look into", no "we could consider". The action is either done (reported in past tense) or scoped to a future phase (stated as a named phase, not as uncertainty).
- **Never quote the reviewer back at them** — no "> you mentioned X — agreed, I did Y."
- **Never use corporate-PR language** — no "per your feedback", "as requested", "I appreciate your input".
- **Never apologize for the substance** — apology is reserved for potential reader misunderstanding only.
- **Never write more than two sentences** — if the reply needs three, something is being over-explained.

Note on corpus size: Six samples at 125 words total. Many patterns are strongly consistent (affirmation-first structure, semicolon joins, past-tense action reporting, avoidance of passive voice) and can be treated as reliable signals. Capitalization inconsistency may be register-matching rather than a stable pattern — insufficient data to call it a rule.
