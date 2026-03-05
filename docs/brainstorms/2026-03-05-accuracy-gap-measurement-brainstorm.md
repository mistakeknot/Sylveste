# Brainstorm: Measure Accuracy Gap With and Without Composition Layer

**Bead:** iv-u74sq
**Date:** 2026-03-05
**Context:** The shallow composition layer (iv-3kpfu) shipped — `tool-composition.yaml` with domain groups, curation groups, and sequencing hints, injected via SessionStart hook. The dialectic (R3 sublation) decomposed the 18-point accuracy gap into three bands: discovery, sequencing, and scale. This bead measures which bands the composition layer actually closes.

---

## Problem Statement

Tool Search accuracy with 49 plugins is ~74%. Native tool selection (5-7 tools) is ~92%. The 18-point gap needs decomposition to determine:
1. How much does the shallow composition layer close?
2. Is the remaining gap in sequencing (moderate composition needed) or scale (irreducible)?
3. Should we invest in moderate-depth composition or wait for model improvements?

This measurement gates `iv-mtf12` — "Let data determine plugin boundary decisions."

## Blocker: No Telemetry Data

**Critical discovery:** The `tool_selection_events` table has 0 rows. The instrumentation hooks (`post-tool-all.sh`, `post-tool-failure.sh`) exist in the interstat source repo but were **never published** to the plugin cache.

Root cause: The source `hooks/hooks.json` includes `PostToolUse:*` and `PostToolUseFailure` entries, but the **installed** version at `~/.claude/plugins/cache/interagency-marketplace/interstat/0.2.14/hooks/hooks.json` only has `SessionStart`, `PostToolUse:Task`, and `SessionEnd`. The hook files themselves (`post-tool-all.sh`, `post-tool-failure.sh`) are also missing from the installed cache.

This means iv-rttr5 ("Instrument agent sessions for tool selection failure classification") was closed prematurely — the code was written but never deployed.

## Approach Options

### Option A: Fix Instrumentation First, Then Measure (Data-Driven)

1. Publish interstat with the missing hooks (add `post-tool-all.sh` + `post-tool-failure.sh` to the publish manifest, ensure hooks.json includes the `*` matcher and `PostToolUseFailure` entries)
2. Run normal work sessions for N days to collect baseline data
3. Toggle composition layer off (remove/skip the hook injection)
4. Run comparable sessions without composition
5. Compare failure categories (discovery/sequencing/scale) between the two groups

**Pros:** Empirical, addresses R3's call for "the composition paradox is an empirical question." Per-session data with failure classification.
**Cons:** Slow — requires days of data collection for statistical significance. Two measurement periods (with/without) doubles the calendar time. May not get enough comparable tasks.

### Option B: Synthetic Benchmark (Controlled Experiment)

1. Design a fixed set of 20-30 tool selection tasks spanning the three gap categories:
   - Discovery tasks: "find and use the right plugin for X" (e.g., semantic code search, drift detection)
   - Sequencing tasks: "resolve paths then reserve files" (interpath -> interlock)
   - Scale tasks: "pick the right tool from 49 options for an ambiguous prompt"
2. Run each task twice: once with composition context injected, once without
3. Score: did the agent select the right tool(s) in the right order?

**Pros:** Fast, controlled, repeatable. Can run in a single session. Directly tests the composition layer's effect.
**Cons:** Synthetic tasks may not reflect real-world failure modes. "Teaching to the test" risk — the composition layer was designed around known plugin relationships, so synthetic tasks using those same relationships will show improvement by construction.

### Option C: Hybrid — Fix Instrumentation + Quick Synthetic Validation

1. Fix and publish the missing hooks (small, bounded task)
2. Run a quick synthetic benchmark (10-15 tasks) to get an immediate directional signal
3. Let instrumentation collect real data over subsequent sessions
4. Revisit with real data in 1-2 weeks for a definitive measurement

**Pros:** Unblocks iv-mtf12 quickly with a directional signal while building toward definitive data. Fixes a real bug (missing hooks) regardless of measurement approach.
**Cons:** The quick signal may be misleading if synthetic tasks are poorly designed. Two-phase approach means the bead stays open longer.

## Recommendation: Option C (Hybrid)

The hybrid approach is best because:
- Fixing the missing hooks is valuable independent of this bead — that's a deployment bug
- A synthetic benchmark gives us a directional answer in hours, not weeks
- Real instrumentation data will either confirm or override the synthetic signal
- We can close this bead with the synthetic results + hook fix, and create a follow-up bead for the definitive measurement once real data accumulates

## Benchmark Design Sketch

### Task Categories

**Discovery (tests shallow composition — domain groups + curation groups):**
1. "Search this codebase semantically for functions related to authentication" — should use intersearch or tldr-swinton (discovery domain)
2. "Check if any documentation is out of date" — should use interwatch (doc-lifecycle curation group)
3. "Show me what other agents are editing right now" — should use intermux (coordination domain)
4. "Track how many tokens this session has used" — should use interstat (analytics domain)
5. "Create a visual diagram of the module dependencies" — should use interchart (design domain)

**Sequencing (tests moderate composition — sequencing hints):**
6. "Reserve these files for editing after resolving their paths" — interpath first, then interlock
7. "Review the plan then run the sprint" — interflux first, then clavain
8. "Set up token tracking before starting sprint work" — interstat first, then clavain
9. "Check which files are reserved, then review the code in them" — interlock status, then interflux
10. "Generate a roadmap from beads, then check for doc drift" — interpath first, then interwatch

**Scale (tests irreducible gap — ambiguous prompts with many valid tools):**
11. "Help me understand this codebase" — could be tldr-swinton, intermap, serena, or intersearch
12. "Make sure everything is good before I ship" — could be interflux, intercheck, intertest, clavain:verify
13. "Find where this function is used" — could be serena, tldr-swinton, intermap, or grep
14. "Document what I just did" — could be interdoc, interpath, interkasten, or clavain:compound
15. "Coordinate with the other agent" — could be interlock, intermux, or intercom

### Scoring

For each task, score on 3 dimensions:
- **Tool selection:** Did the agent pick the right tool(s)? (0/1)
- **Tool ordering:** If multiple tools, were they called in the right order? (0/1, N/A for single-tool tasks)
- **Composition awareness:** Did the agent reference domain/group context in its reasoning? (0/1)

Run each task with and without composition context. The delta per category tells us:
- Discovery delta = composition layer value for shallow metadata
- Sequencing delta = composition layer value for ordering hints
- Scale delta = (should be ~0 — if composition helps here, the tasks were poorly designed)

### Execution Method

Use a subagent for each task with a controlled system prompt. Two variants:
- **With composition:** Include the tool-surface output in the prompt
- **Without composition:** Omit it, use only default tool descriptions

Record which tools the agent actually calls (via the Task tool's output) and compare to expected.

## Hook Fix Scope

Minimal changes to unblock data collection:
1. Copy `post-tool-all.sh` and `post-tool-failure.sh` into the publish manifest
2. Update the installed `hooks.json` to include the `PostToolUse:*` and `PostToolUseFailure` entries
3. Bump interstat version and publish
4. Verify by running a session and checking `SELECT COUNT(*) FROM tool_selection_events`

## Open Questions

1. **Sample size for synthetic benchmark:** Is 15 tasks enough for a directional signal? The dialectic's R3 identified three categories — 5 tasks per category may be too few for statistical confidence but enough to show whether the effect exists at all.
2. **Baseline definition:** What counts as "correct" tool selection for ambiguous prompts (scale category)? Need a rubric that allows multiple valid answers.
3. **Composition context format:** The `clavain-cli tool-surface` command output is what gets injected. Should we test the formatted output specifically, or test the raw YAML content?
4. **Agent model:** Test with Opus 4.6 only, or also with Sonnet/Haiku to see if composition value varies by model capability?
