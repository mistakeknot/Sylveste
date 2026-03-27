<!-- Voice delta: docs. Sections here override matching sections in the base profile. -->

# Voice Profile: Docs (Project Documentation)

Context: Vision docs, brainstorms, PRDs, and project documentation within the Sylveste ecosystem. These are persistent artifacts read by both humans and agents across sessions. Corpus: base profile (Substack post), adapted for structural documentation conventions.

## Overview

The base voice carries over intact — frame-then-populate, semicolons doing real work, self-aware hedges, humor through specificity, active verbs, no passive default. The delta adds structural affordances that make docs navigable by agents and skimmable by humans: headers, tables, reading context blocks, numbered lists for ordered sequences. These are tools, not compromises; the voice stays conversational within them.

## Structure Patterns

**Reading context blocks** open every doc that cross-references other parts of the monorepo. Format: `> **Reading context.** [one sentence explaining where you are and how links resolve]`. This is agent memory, not decoration.

**Headers** are used for major sections. The base profile's "frame, then populate" pattern still drives the prose under each header, but the headers themselves provide scan structure. Use `##` for top-level sections, `###` for subsections. Do not use `####` or deeper; if nesting goes that far, the section wants splitting.

**Tables** are used when comparing structured data (component relationships, decision matrices, feature comparisons). A table replaces three paragraphs of "X does this, Y does that, Z does the other thing." The table cells themselves should be written in the base voice — not clipped fragments.

**Numbered lists** are used for ordered sequences (milestones, priority-ordered items, step-by-step processes) and for lists where the count itself is meaningful ("five faces," "four things"). Unordered bullets for everything else.

**Section flow** still leans on connective prose between structural elements rather than headers alone. A table or list is introduced with a sentence that frames what it contains and why; it does not appear without context.

**Do this:** Frame a table with "Skaffen shares L1 infrastructure with Clavain and the rest of Sylveste:" then the table.
**Not this:** `## Companion Ecosystem` followed immediately by a table with no introductory sentence.

**Do this:** "The ceiling has five faces:" followed by a numbered list with bold lead-ins and prose.
**Not this:** Five `###` subsections each containing one paragraph.

## Tone & Voice

The base profile's peer-to-peer register stays. The shift from first-person blog to docs is: "I find it helpful" becomes "this approach works because" or simply stating the thing without attribution. The voice does not become impersonal; it becomes authorial-but-implicit. The author is present in the rhythm and choices, not in pronouns.

Self-aware asides still appear but less frequently than in the blog register. In a vision doc, one aside per major section is about right. In a PRD, asides are rare — the format is more transactional.

## Anti-Patterns

All base anti-patterns carry over, plus:

**Never use headers as the only structural device.** A doc that is nothing but `## Header` / paragraph / `## Header` / paragraph reads like a slide deck, not a document. Headers frame; prose connects.

**Never write table cells as fragments.** "L1 kernel" in a table cell is fine as a label column, but the description column should be a full clause: "Skaffen integrates as a first-class consumer/producer: dispatch events, run state, session registry."

**Never omit the reading context block** on docs that reference other parts of the monorepo or external repos. Agents load these docs cold; the context block orients them.

**Never use `####` headers.** If the nesting is that deep, the section is too big or the hierarchy is wrong.
