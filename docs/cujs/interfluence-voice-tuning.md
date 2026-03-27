---
artifact_type: cuj
journey: interfluence-voice-tuning
actor: regular user (developer or writer who wants AI output in their voice)
criticality: p3
bead: Sylveste-2c7
---

# Interfluence Voice Tuning

## Why This Journey Matters

AI-generated text that sounds generic is worse than no assistance — it creates a jarring tonal shift in documentation, commit messages, PR descriptions, and any prose the developer publishes. The reader notices immediately: "This paragraph doesn't sound like the rest." Interfluence solves this by learning the developer's writing style and adapting AI output to match.

The value compounds over time. A well-tuned voice profile means every piece of AI-assisted writing sounds natural from the start — no manual editing to fix tone, no "make this sound less robotic" follow-up prompts. For developers who write public-facing documentation, blog posts, or technical articles, this is the difference between AI as a draft generator and AI as a genuine writing partner.

## The Journey

The developer installs Interfluence and runs `/interfluence:ingest` with a few writing samples — blog posts, documentation they've written, even well-crafted commit messages. Interfluence normalizes the samples, stores them in `.interfluence/corpus/`, and builds a corpus index.

Next: `/interfluence:analyze`. Interfluence dispatches the voice-analyzer agent (Opus-powered deep literary analysis) to read the corpus and extract style invariants — sentence rhythm, vocabulary preferences, structural habits, tone register, rhetorical patterns. The result is a prose voice profile stored at `.interfluence/voice-profile.md`. Not numeric scores — natural language descriptions that Claude can follow: "Favors short declarative sentences. Uses em-dashes liberally. Opens paragraphs with the conclusion, then supports it. Technical terms without hedging."

The developer reviews the profile: `/interfluence:refine`. This is an interactive dialogue — Interfluence asks "Does this capture your style?" and the developer adjusts. "I don't actually use semicolons that much" or "You missed that I always use active voice." Refinements update the profile.

In use: `/interfluence:apply <file>` rewrites a file in the developer's voice. For ongoing use, the developer can configure per-context voices — one for docs, one for blog posts, one for commit messages. Voice routing uses glob patterns: `docs/**/*.md → docs-voice`, `*.md → blog-voice`.

The learn-from-edits hook silently logs edit diffs to `learnings-raw.log`. When the developer runs `/interfluence:refine` again, these accumulated observations refine the profile further — the voice gets more accurate with use.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Voice profile generated from 3+ writing samples | measurable | Profile file exists after analyze with ≥3 corpus entries |
| Applied text passes the "sounds like me" test | qualitative | Developer accepts ≥80% of applied text without tone edits |
| Per-context voices produce distinct styles | measurable | Docs voice and blog voice profiles differ materially |
| Edit-learning hook captures style corrections | measurable | learnings-raw.log grows with Edit tool usage |
| Refinement dialogue updates the profile | measurable | voice-profile.md modified after refine session |
| `/interfluence:compare` detects voice drift | measurable | Comparison output scores voice match |

## Known Friction Points

- **Corpus bootstrapping** — needs 3+ substantial writing samples. Developers with little published writing may struggle to provide enough.
- **Manual mode by default** — the developer must explicitly run `/apply`. Auto-mode (apply voice to all AI output) is opt-in and can be surprising.
- **Voice analysis is expensive** — the Opus analyzer uses significant tokens. Should be batched, not run on every refinement.
- **No multi-author support** — one voice profile per project. Team projects with multiple writers need separate contexts.
