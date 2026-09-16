# Reclaim the session opening

**Date:** 2026-09-16
**Project:** Sylveste
**Complexity:** C3
**Status:** charter drafted, awaiting ratification

## Why (leverage)

Every session on this rig pays its fixed context before anyone types anything. Measured on session `d44605f2` (Clavain, Opus 5, interactive), that opening cost **81,295 tokens**, split as:

| component | tokens | note |
|---|---|---|
| built-in tool schemas | 31,282 | `Artifact` alone is 16,733 |
| skill listings | 7,499 | 190 entries; 11 advertised twice |
| agent listing | 4,391 | 68 agents, 21 of them generated `fd-*` lenses |
| MEMORY.md | 5,277 | 139 lines against a 120-line budget |
| ~/.claude/CLAUDE.md | 3,822 | |
| MCP instructions + tool names | 6,293 | probe-confirmed at 5,883 |
| SessionStart hook output | 1,947 | |
| base system prompt blocks | 2,694 | includes a 1,026-token browser block |

Across ~76 sessions/day this is the single largest recurring cost in the estate, and it is paid at the 1h cache-write rate on the main thread. The existing `advertisement-budget` check has sat in its warn band for 34 days on zklw and 3 on Clavain (29,214 chars against a 30,000 ceiling) — but that check only sees plugin advertisement text, which is under a tenth of the opening. The rig has been optimizing the part it can see.

## The instrument problem (why this is not just a trimming pass)

A headless probe is the obvious meter and it is **wrong on the biggest item**. Measured this session:

| probe | opening context |
|---|---|
| A — default config | 44,632 |
| B — MCP servers off | 38,749 |
| C — `enableArtifact`/`enableWorkflows`/`includeGitInstructions` off | 41,377 |
| D — both | 35,511 |

Probe C saves 3,255 tokens where the `Artifact` schema alone is 16,733, because `claude -p` print mode never loads interactive-only tools. An interactive session opened at 81,295 against probe A's 44,632. Any inventory built on the probe alone would rank the wrong targets — the failure mode recorded in `feedback_prove_target_before_optimizing`. So the goal delivers **two** instruments that must reconcile: a transcript decomposer (interactive truth, reads the prompt snapshot) and the probe (fast A/B).

## Waste versus capability

Two different transactions, deliberately separated:

- **Waste** returns nothing for its cost: 11 duplicated skill advertisements (the personal `~/.claude/skills/cloudflare*` copies are byte-identical to the enabled `cloudflare` plugin's), 215 never-used generated lens agents in the Sylveste registry, MCP servers with no recorded use, memory lines over budget. Reclaiming these removes no capability.
- **Capability** trades a feature for tokens: `enableArtifact: false` is the largest single lever on the board and it removes artifact publishing outright. Verified present in build 2.1.273 (`enableArtifact`, `enableWorkflows`, `includeGitInstructions`, and `skillOverrides`, which the settings already use for `argus`/`context-init`/`flux-council`).

Waste lands on evidence. Capability stops for a ruling.

## Quality gate

`claude plugin eval` (CLI 2.1.272+) runs cases with `--ablation with-without` and reports a per-case delta between the with-plugin and without-plugin arms; `tool_used: Skill` graders act as plugin-fired indicators. Zero of the 71 interverse plugins ship a single case today (bead `Sylveste-qdrz`). Per-run token usage is **not** exposed by the runner, which is why tokens come from the instruments and quality comes from the evals — neither substitutes for the other.

## Scope

**In:** the meter, the eval suite, waste reclaim on both machines, a written-up ruling packet for each capability lever, re-measurement on a fresh interactive session, and closing or re-scoping the beads this supersedes (`mk-etfy`, `mk-z8pn`, `Sylveste-qdrz`, `sylveste-3xgz`).

**Out:** applying any capability lever before the ruling; winning bytes by deleting trigger words from skill descriptions; client-facing or Notion configuration; creating a second task system.

## Completion condition

The literal string handed to `/goal` lives in `2026-09-16-session-opening-reclaim-condition.md`.

## Successor obligations

Whatever lands, the next goal inherits: the ruling packet for the capability levers, and the question of whether the `advertisement-budget` ceiling should be replaced by a whole-opening budget now that the opening can be measured end to end.
