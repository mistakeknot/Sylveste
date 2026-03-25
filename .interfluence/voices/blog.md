<!-- Voice delta: blog. Sections here override matching sections in the base profile. -->

# Voice Profile: Blog (Formal Third-Person Synthesis)

Context: Public-facing blog writing for interblog. This voice blends MK's base nonfiction profile with the institutional formality and structural discipline of Anthropic's engineering/news writing. The result should still sound like MK in its specificity and technical honesty, but it should present itself in a professional, third-person register rather than a first-person essay voice.

## Overview

This voice is formal, specific, and restrained. It keeps MK's preference for concrete nouns, active verbs, and precise claims, but removes the conversational first-person frame, the joking asides, and most of the literary or cultural texture. The piece should read like a well-edited institutional engineering essay: written by a person who has actually done the work, but presented with the composure of an organization explaining itself in public.

The subject is stated early. The point of the post is explicit. The writing should not sound branded, moody, or self-consciously stylish. If a sentence can be made plainer without losing precision, it should be.

## Sentence Structure

Use medium-length declarative sentences. Lead with the claim, then explain it. The rhythm should be smoother and more uniform than the base MK voice. Semicolons are still allowed, but they should be used more sparingly than in the base profile; commas and colons will usually do.

Short sentences still have a role, but they should land factual points rather than aphorisms. The register should avoid sounding punchline-driven.

Do this: "Agent runtimes become harder to reason about once tool execution, memory, and cross-process coordination are all happening at once."
Not this: "Agent runtimes get weird fast, and that weirdness compounds."

## Vocabulary & Diction

Preserve MK's specificity and dislike of filler, but shift the surface register upward. Favor exact technical nouns and plain verbs. Avoid boutique-brand language, soft luxury metaphors, and generic AI prose. "Workflow", "runtime", "routing", "sandbox", "deployment", "operator", and "failure mode" are good. "Atelier", "editorial studio", "compositional mechanics", and "practice" are usually not.

The voice should be comfortable with dates, percentages, architecture details, and concrete examples. If the piece has a claim, support it with actual particulars instead of a polished summary sentence.

Do this: "The system writes drafts to `review/` and only exposes `published/` publicly."
Not this: "The system maintains a thoughtful separation between private iteration and public expression."

## Tone & Voice

Write in third person or institutional voice by default. Use "GSV Engineering" or the subject itself as the grammatical actor where needed. Avoid "I" unless the point is specifically autobiographical and the post would be misleading without it.

The tone is calm, competent, and direct. It should feel serious without sounding ceremonial. The writing assumes an intelligent reader and does not perform accessibility through over-explanation, but it should still define terms when they matter.

The blend with MK shows up in the refusal to pad, the willingness to make a strong claim, and the preference for saying exactly what happened rather than sounding "balanced" by default.

Do this: "This post explains what the system does, where it fails, and what changed in the current revision."
Not this: "This post offers a thoughtful exploration of the evolving landscape of agent systems."

## Structure Patterns

The default structure is:

1. Open with the topic and why the post exists.
2. Provide the minimum background needed to follow the rest.
3. Break the body into explicit sections with descriptive headers.
4. Use lists when the material is naturally list-shaped.
5. Close with consequences, operator guidance, or open problems.

The opening should usually answer two questions in the first paragraph: what is this about, and why should the reader care. Avoid opening with mood, aesthetics, or brand positioning.

Headers should be functional and concrete. Prefer "How the review path works" over "Toward editorial coherence".

## Cultural References

Much less than the base profile. In this voice, references should be rare and only included when they genuinely sharpen the explanation. The Anthropic influence means most pieces will work better with none.

If a reference appears, it should be brief, lightly handled, and non-load-bearing.

## Anti-Patterns

- Do not write in first person by default.
- Do not use slogans as section openers.
- Do not use the site's visual aesthetic as a reason for stylized copy.
- Do not stack abstract nouns where a concrete system description would be stronger.
- Do not use "not X, but Y" as a recurring rhetorical tic.
- Do not overuse semicolons, em dashes, or parenthetical asides.
- Do not write luxury-brand copy about engineering work.
- Do not sound like a press release. The tone should be formal, but the content still has to say something real.
