# intermonk — Hegelian Dialectic Plugin Brainstorm

**Date:** 2026-03-01
**Status:** Draft
**Source:** [hegelian-dialectic-skill](https://github.com/KyleAMathews/hegelian-dialectic-skill) by Kyle Mathews (MIT license)
**Bead:** iv-x7rlv

## What We're Building

**intermonk** — a new Interverse plugin that provides structured dialectical reasoning through "Electric Monks" — subagents that fully commit to opposing positions so the user can analyze contradictions from a belief-free position. Adopted from Kyle Mathews' 1100-line SKILL.md, adapted for Claude Code's Agent tool architecture.

### Core Concept

Two subagent sessions (the Electric Monks) *believe* fully committed positions on the user's behalf. A third (the orchestrator skill) performs structural contradiction analysis and generates a synthesis (Aufhebung) that transforms the question itself. The user operates from a belief-free position — freed from cognitive load of holding either position.

**Why this works:** The bottleneck in human reasoning isn't intelligence — it's *belief.* Once you believe a position, you can't simultaneously hold its negation at full strength. The monks carry the belief load at full conviction, freeing the user for structural analysis. (Rao's "artificial belief system" framework, Boyd's fast transients analogy.)

### User Experience

1. User invokes `/intermonk:dialectic "topic or tension"`
2. Orchestrator conducts Socratic interview to surface hidden assumptions, identify deepest contradiction
3. Orchestrator writes context briefing, spawns two Electric Monk subagents in parallel
4. Monks write fully committed essays (1500-2000 words each, no hedging)
5. Orchestrator performs determinate negation + Boydian decomposition
6. Synthesis (Aufhebung) — cancels, preserves, elevates — not compromise
7. Monks validate (elevated or defeated?), hostile auditor attacks
8. Recursion: synthesis generates new contradictions, repeat with deeper contradictions
9. All artifacts saved to `dialectics/[topic-name]/` directory

## Why This Approach

### Adopt (Not Build From Scratch)

- The original SKILL.md is remarkably well-crafted — 1100 lines of dense orchestration with theoretical foundations from Hegel, Boyd, Rao, Peirce, Pollock, and Galinsky
- MIT licensed, clean to adopt
- It already has an "Environment Mapping" section (L870-887) that maps `claude -p` to Task/Agent tool patterns
- Building from scratch would reproduce the same structure with less intellectual rigor

### Separate Plugin (Not Extending interflux)

- **interflux** is code/document review — it dispatches specialized reviewer agents
- **intermonk** is dialectical reasoning — it dispatches belief-committed arguers
- Fundamentally different agent patterns: reviewers analyze objectively; monks believe subjectively
- No shared infrastructure beyond the Agent tool itself
- Clean separation follows Interverse philosophy: one plugin, one job

### Minimal Plugin (Skill Only)

- No MCP server needed — the orchestration is pure skill logic + Agent tool subagents
- No hooks — no events to intercept
- No commands beyond the skill invocation itself
- Single skill (`dialectic`) is the entire plugin — keeps it focused and maintainable
- Low dependency surface: just Claude Code's Agent tool and file system

## Source Material Analysis

### What to Keep (Whole-Cloth)

1. **The 7-phase process** — interview → calibrate → spawn → negate → sublate → validate → recurse. This is the intellectual core and it's well-designed.
2. **Anti-hedging instructions** — "You are an Electric Monk. Your ONE JOB is to believe this position fully." This is functionally critical, not just stylistic.
3. **Decorrelation check** (Phase 3) — verify monks diverged in *framework*, not just conclusion. Catches the most common failure mode.
4. **Hostile auditor** (Phase 6) — separate agent with no position, sole job is finding structural flaws.
5. **Boydian decomposition** (Phase 4.5) — shatter → scatter → cross-domain connect. This is where creative synthesis actually comes from.
6. **Sublation criteria** — explicit tests that distinguish genuine Aufhebung from compromise.
7. **Recursive queue** — `dialectic_queue.md` tracks explored/queued/deferred contradictions across sessions.
8. **Domain adaptation table** — different "truth" vocabularies for empirical, normative, personal, creative, risk domains.

### What to Adapt

1. **Spawn mechanics:** `claude -p` → Agent tool with `subagent_type="general-purpose"`. The skill already maps this (L870-887).
2. **File I/O pattern:** In `claude -p`, agents write directly via shell redirect. In Agent tool, agents return text and orchestrator writes files. Add explicit file-writing steps after each agent returns.
3. **Model selection:** `--model` flag → `model` parameter on Agent tool. Original recommends heterogeneous models; we can offer this via Agent tool's model parameter.
4. **Session resumption:** `claude -p` session resume → Agent tool's `resume` parameter. Original notes persona may need reinforcement — include fallback summary.
5. **Parallel execution:** Shell background jobs → multiple Agent tool calls in single message with `run_in_background: true`.

### What to Trim or Restructure

1. **Belief-burden typology** (L130-165) — MBTI-adjacent pattern catalog (Convergent Visionary, Empathic Integrator, etc.). Interesting but adds ~35 lines of material that most users won't directly encounter. Keep it but move to a `references/belief-burdens.md` companion file.
2. **Worked examples** (L1045-1110) — valuable but adds ~65 lines to the skill. Move to `references/worked-examples.md`.
3. **Theoretical foundations** (L912-1043) — 130 lines of Rao, Hegel, Boyd, Socrates, Adams, Aquinas, DeLong, Peirce, Pollock, Galinsky, Klein, Fauconnier & Turner, ensemble diversity, SICP, Dixon, Alexander. The orchestrator doesn't need all of this in-context every invocation. Keep core concepts (Rao, Hegel, Boyd) inline; move the rest to `references/theory.md`.
4. **Token budget tables** (L837-868) — useful reference but not operational instructions. Move to AGENTS.md or a companion file.

### What to Add (Interverse Integration)

1. **Output directory convention:** `dialectics/[topic-name]/` at project root (or configurable via argument)
2. **Interflux integration:** After dialectic completes, offer to run `/interflux:flux-drive` on the synthesis for review
3. **Beads integration:** If beads are available, link dialectic artifacts to the active bead
4. **Progress display:** Use inline status messages between phases so user sees where they are in the 7-phase process

## Architecture

```
interverse/intermonk/
├── .claude-plugin/
│   └── plugin.json                   # name: intermonk, 1 skill
├── skills/
│   └── dialectic/
│       ├── SKILL.md                  # Main orchestrator (~600-700 lines)
│       └── references/
│           ├── belief-burdens.md     # MBTI-adjacent belief-burden typology
│           ├── theory.md             # Full theoretical foundations
│           ├── worked-examples.md    # Example dialectics from source
│           └── auditor-prompt.md     # Hostile auditor prompt template
├── README.md
├── CLAUDE.md
├── AGENTS.md
├── PHILOSOPHY.md
├── LICENSE                           # MIT (matching source)
├── .gitignore
├── scripts/
│   └── bump-version.sh
└── tests/
    ├── pyproject.toml
    ├── uv.lock
    └── structural/
        ├── conftest.py
        ├── helpers.py
        ├── test_structure.py
        └── test_skills.py
```

## Key Design Decisions

### 1. Keep Full Intellectual Depth

The original skill's power comes from its specificity — the anti-hedging instructions, the determinate negation process, the Boydian decomposition, the hostile auditor. Trimming these for brevity would gut the skill. Keep the orchestrator instructions dense and specific; move reference material to companion files.

### 2. Orchestrator Does Everything

The orchestrator (SKILL.md) handles: interview, prompt generation, agent spawning, structural analysis, synthesis, validation orchestration, recursion management, file output. Monks and auditor are spawned as stateless subagents. This matches the original's design — the orchestrator maintains continuity across phases.

### 3. File-Based State

All artifacts written to disk: `context_briefing.md`, `monk_a_output.md`, `monk_b_output.md`, `determinate_negation.md`, `sublation.md`, `dialectic_queue.md`. This enables session recovery and provides a navigable dialectical trace.

### 4. User as Co-Pilot

The skill's design mandates user checkpoints at Phase 1f (confirm framing), Phase 3 (monk output review), Phase 5 (synthesis review), and Phase 7 (recursion direction). These are not optional — user corrections are consistently the highest-leverage inputs.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Monks hedge despite instructions | Core value destroyed | Explicit anti-hedging in prompts + decorrelation check + restart-not-nudge policy |
| Skill too long for context window | Phases get cut from context on later turns | XML-tagged phases + selective re-reading instructions already in the source |
| Token cost per dialectic (~300-400K) | Expensive for casual use | Document cost expectations upfront; personal domains are cheaper (~100-200K) |
| Synthesis quality varies by model | Weaker models produce compromise, not sublation | Document model requirements; recommend strongest available + extended thinking |
| Agent tool doesn't support `claude -p` session resume | Validation loses conviction context | Fallback: include summary of monk's original argument in validation prompt |

## Open Questions

1. **Output directory:** Should dialectics go in `dialectics/` at project root, or in a configurable location? (Lean: project root, user can override via argument.)
2. **Heterogeneous models:** The original recommends different model families for each monk. Should we prompt the user about this, or just default to same model? (Lean: default same, mention in AGENTS.md.)
3. **Interflux integration:** Should we auto-suggest flux-drive review after synthesis, or leave that to the user? (Lean: suggest but don't auto-invoke.)
4. **Recursion default:** Original says "recurse at least once." Should we make this the default, or let user opt in? (Lean: suggest recursion, don't force it.)

## What Success Looks Like

- User invokes `/intermonk:dialectic "should we use microservices or a monolith for the new platform?"`
- Socratic interview surfaces the real tension (team autonomy vs. system coherence, not just architectural preference)
- Two monks produce genuinely divergent, fully committed essays grounded in the user's specific context
- Structural analysis identifies shared assumptions both sides missed
- Synthesis produces an Aufhebung the user couldn't have reached alone — irreversible cognitive gain
- Recursive round deepens into territory the first round couldn't see
- All artifacts preserved in `dialectics/microservices-vs-monolith/` for future reference
