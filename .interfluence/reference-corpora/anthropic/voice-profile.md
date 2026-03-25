# Voice Profile: Anthropic Blog (Reference Corpus)

Corpus source: Anthropic posts captured from `https://www.anthropic.com/sitemap.xml`, filtered to `/news/` and `/engineering/`, stored under this directory. This is a reference profile for tone and structure, not a user voice profile.

## Overview

Anthropic's blog voice is institutional, measured, and explicit about what it is trying to explain. It does not posture. It names the claim early, supplies enough context for a technically literate reader to follow, and then proceeds by unpacking the mechanics, tradeoffs, or implications in an orderly way.

The engineering posts are the clearest signal. They favor plain nouns, moderate sentence length, and a calm confidence that comes from describing concrete systems rather than gesturing at abstractions. Even the product and company posts stay relatively restrained compared to typical startup writing: they announce, define, and enumerate.

Representative lines:
- "Consistently, the most successful implementations weren't using complex frameworks or specialized libraries. Instead, they were building with simple, composable patterns."
- "When building applications with LLMs, we recommend finding the simplest solution possible, and only increasing complexity when needed."
- "Between August and early September, three infrastructure bugs intermittently degraded Claude's response quality. We've now resolved these issues and want to explain what happened."

## Sentence Structure

The default sentence is medium-length, declarative, and front-loaded with the main point. It rarely withholds the subject. Sentences often follow a practical sequence: claim, explanation, consequence. Coordination is common, but the prose usually avoids overt rhetorical flourish.

A characteristic move is to open a section with a plain statement of scope and then immediately narrow it: "Evaluating technical candidates becomes harder as AI capabilities improve." "Sandboxing creates pre-defined boundaries within which Claude can work more freely, instead of asking for permission for each action." The sentence says exactly what the section is about, then the rest of the section elaborates.

Lists are heavily used, but they are functional rather than ornamental. They appear when the material is naturally decomposable: design goals, workflow variants, resolution steps, or product capabilities.

Do this: "The archive should explain what changed, why it matters, and where the tradeoffs are."
Not this: "The archive should serve as a vibrant space for rigorous, thoughtful, and forward-looking analysis."

## Vocabulary & Diction

The diction is formal but not inflated. The writing uses domain terms directly when they are load-bearing: "routing logic", "context window", "sandboxing", "load balancing change", "toolsets", "guardrails". It prefers ordinary verbs to dressed-up synonyms: "fixed", "deployed", "introduced", "recommend", "use", "affect".

Anthropic's writing is comfortable with precise quantitative detail. Percentages, dates, model names, and explicit conditions appear naturally in the prose because they tighten the claim rather than decorate it.

There is a strong avoidance of empty intensifiers. The voice does not need to call something "groundbreaking" to present it as important. It trusts the facts to carry the weight.

Do this: "The change affected 0.8% of requests and was fixed on September 4."
Not this: "The issue had a profound impact and underscores the importance of robust infrastructure."

## Tone & Voice

The tone is professional, explanatory, and institution-first. Even when a post is authored by an individual engineer, the reader is being addressed on behalf of a team or company. The voice is not intimate. It is also not cold: it acknowledges user expectations, operational mistakes, and uncertainty without drifting into performative humility.

The confidence level is high, but the register stays sober. A sentence like "To state it plainly: We never reduce model quality due to demand, time of day, or server load" is assertive because it resolves ambiguity, not because it is trying to sound forceful.

Humor is almost absent. When it appears, it comes from a concrete example or a lightly self-aware framing, not from jokes or cultural references.

Do this: "The piece should explain the system clearly and avoid overstating what the evidence shows."
Not this: "The piece should sound sharp, bold, and impossibly dialed in."

## Structure Patterns

Anthropic posts generally follow a stable structure:

1. Lead with the announcement, finding, or problem.
2. Explain why it matters.
3. Break the subject into named sections.
4. Use lists or examples where decomposition helps.
5. End with practical next steps, acknowledgements, or links.

Section headers are functional and descriptive. They are often questions or plain labels: "What are agents?", "How we serve Claude at scale", "Getting started". This keeps the piece skimmable and reduces the need for rhetorical transitions.

The tone of the opening matters. The first paragraph usually tells the reader what this post is going to do. It does not spend two paragraphs constructing an aura first.

Do this: open with the claim and the scope of the post.
Not this: open with a slogan, then spend a paragraph describing the mood of the site.

## Cultural References

Almost none. Anthropic's blog avoids literary or pop-cultural reference as a matter of house style. The writing wants the authority to come from the operational detail, not from resonance borrowed from elsewhere.

When examples appear, they are usually product, infrastructure, or workflow examples. Even the illustrative examples are in-domain.

## Anti-Patterns

- Do not write in a manifesto register.
- Do not use slogans where a factual sentence would do.
- Do not rely on aesthetic nouns like "atelier", "studio", "practice", or "craft" to create seriousness.
- Do not open with branding language and only later explain the actual subject.
- Do not use puffery verbs such as "underscores", "showcases", "exemplifies", or "reflects" when "is", "shows", or "means" would suffice.
- Do not use rule-of-three marketing phrasing unless the list items are genuinely distinct and necessary.
- Do not use second-person familiarity as a crutch. The voice is helpful, but it is not chatty.
