# Sylveste Documentation Truth Audit Inventory

**Date:** 2026-03-14  
**Purpose:** Coverage appendix for the 2026-03-14 truth audit

## Method

- Counted in-scope docs from the Sylveste root, root `docs/`, root `agents/`, top-level context files, and repos under `apps/`, `core/`, `os/`, `sdk/`, and `interverse/`.
- Excluded generated/cache directories such as `.git/`, `.venv/`, `node_modules/`, `dist/`, `target/`, `.pytest_cache/`, and `.tldrs/`.
- Classified canonical docs as `README`, `AGENTS`, `CLAUDE`, `PHILOSOPHY`, and files with `vision`, `roadmap`, `architecture`, `reference`, or `glossary` in the title/path.
- Counted Markdown-link failures directly.
- Counted plain-text path flags heuristically; those are useful for triage but are noisier than Markdown-link failures.

## Scope Totals

- Total scoped docs: **3,626**
- Canonical docs: **678**
- Secondary docs: **2,948**
- Broken Markdown links: **587**
- Plain-text path flags: **6,938**
- Repos in scope: **65**

## Repo Coverage

| Repo | Total Docs | Canonical | Secondary |
|---|---:|---:|---:|
| root | 957 | 86 | 871 |
| apps/Autarch | 411 | 41 | 370 |
| apps/Intercom | 65 | 13 | 52 |
| core/agent-rig | 22 | 8 | 14 |
| core/interband | 6 | 6 | 0 |
| core/interbench | 15 | 8 | 7 |
| core/intercore | 171 | 35 | 136 |
| core/intermute | 29 | 11 | 18 |
| core/marketplace | 12 | 8 | 4 |
| interverse/intercache | 4 | 4 | 0 |
| interverse/interchart | 15 | 6 | 9 |
| interverse/intercheck | 11 | 8 | 3 |
| interverse/intercraft | 24 | 8 | 16 |
| interverse/interdeep | 9 | 4 | 5 |
| interverse/interdev | 53 | 8 | 45 |
| interverse/interdoc | 30 | 8 | 22 |
| interverse/interfluence | 30 | 10 | 20 |
| interverse/interflux | 110 | 15 | 95 |
| interverse/interform | 7 | 6 | 1 |
| interverse/interhelm | 11 | 6 | 5 |
| interverse/interject | 149 | 9 | 140 |
| interverse/interkasten | 68 | 11 | 57 |
| interverse/interknow | 15 | 5 | 10 |
| interverse/interlab | 16 | 6 | 10 |
| interverse/interlearn | 7 | 5 | 2 |
| interverse/interleave | 15 | 8 | 7 |
| interverse/interlens | 67 | 14 | 53 |
| interverse/interline | 11 | 6 | 5 |
| interverse/interlock | 29 | 7 | 22 |
| interverse/intermap | 33 | 14 | 19 |
| interverse/intermem | 35 | 12 | 23 |
| interverse/intermonk | 13 | 4 | 9 |
| interverse/intermux | 9 | 8 | 1 |
| interverse/intername | 6 | 4 | 2 |
| interverse/internext | 7 | 6 | 1 |
| interverse/interpath | 28 | 11 | 17 |
| interverse/interpeer | 15 | 8 | 7 |
| interverse/interphase | 13 | 10 | 3 |
| interverse/interplug | 13 | 4 | 9 |
| interverse/interpub | 8 | 6 | 2 |
| interverse/interpulse | 5 | 4 | 1 |
| interverse/interrank | 4 | 4 | 0 |
| interverse/interscribe | 6 | 4 | 2 |
| interverse/intersearch | 7 | 6 | 1 |
| interverse/intersense | 15 | 4 | 11 |
| interverse/interserve | 13 | 9 | 4 |
| interverse/intership | 6 | 4 | 2 |
| interverse/intersight | 5 | 4 | 1 |
| interverse/interskill | 36 | 5 | 31 |
| interverse/interslack | 8 | 6 | 2 |
| interverse/interspect | 24 | 5 | 19 |
| interverse/interstat | 21 | 10 | 11 |
| interverse/intersynth | 12 | 6 | 6 |
| interverse/intertest | 20 | 6 | 14 |
| interverse/intertrace | 6 | 4 | 2 |
| interverse/intertrack | 8 | 6 | 2 |
| interverse/intertree | 6 | 4 | 2 |
| interverse/intertrust | 5 | 4 | 1 |
| interverse/interwatch | 18 | 6 | 12 |
| interverse/tldr-swinton | 183 | 26 | 157 |
| interverse/tool-time | 27 | 9 | 18 |
| interverse/tuivision | 24 | 7 | 17 |
| os/Clavain | 569 | 67 | 502 |
| os/Skaffen | 34 | 4 | 30 |
| sdk/interbase | 15 | 7 | 8 |

## Broken Markdown Link Hotspots

| File | Broken Markdown Links |
|---|---:|
| docs/solutions/INDEX.md | 72 |
| interverse/interdev/skills/working-with-claude-code/references/settings.md | 37 |
| interverse/interdev/skills/working-with-claude-code/references/plugins.md | 25 |
| interverse/interskill/skills/skill/references/anthropic-best-practices.md | 23 |
| docs/plans/2026-02-23-first-stranger-experience.md | 17 |
| interverse/interdev/skills/working-with-claude-code/references/slash-commands.md | 16 |
| interverse/interdev/skills/working-with-claude-code/references/cli-reference.md | 14 |
| interverse/interdev/skills/working-with-claude-code/references/plugins-reference.md | 13 |
| interverse/interdev/skills/working-with-claude-code/references/iam.md | 11 |
| interverse/interpeer/skills/interpeer/references/oracle-docs/upstream-readme.md | 11 |
| interverse/interskill/skills/skill/references/best-practices.md | 11 |
| interverse/interdev/skills/working-with-claude-code/references/security.md | 10 |
| interverse/interdev/skills/working-with-claude-code/references/sub-agents.md | 10 |
| interverse/interdev/skills/working-with-claude-code/references/common-workflows.md | 9 |
| interverse/interdev/skills/working-with-claude-code/references/skills.md | 9 |
| interverse/interdev/skills/working-with-claude-code/references/third-party-integrations.md | 9 |
| interverse/interdev/skills/working-with-claude-code/references/model-config.md | 8 |
| interverse/interdev/skills/working-with-claude-code/references/overview.md | 8 |
| interverse/interphase/skills/beads-workflow/references/CLI_REFERENCE.md | 8 |
| os/Clavain/docs/research/review-cross-references.md | 8 |

## Plain-Text Path Hotspots

| File | Plain-Text Path Flags |
|---|---:|
| docs/plans/2026-02-25-clavain-cli-go-migration.md | 70 |
| docs/plans/2026-02-20-intercore-e5-discovery-pipeline.md | 67 |
| core/intercore/docs/plans/2026-02-19-intercore-e1-kernel-primitives.md | 61 |
| docs/plans/2026-02-20-sprint-handover-kernel-driven.md | 56 |
| docs/solutions/INDEX.md | 55 |
| docs/plans/2026-02-20-intercore-rollback-recovery.md | 53 |
| docs/plans/2026-03-05-factory-substrate.md | 53 |
| os/Clavain/docs/research/review-cross-references.md | 52 |
| docs/plans/2026-02-20-reflect-phase-sprint-integration.md | 51 |
| os/Skaffen/docs/sprints/Sylveste-6i0.11-transcript.md | 51 |
| docs/plans/2026-02-19-intercore-e3-hook-cutover.md | 48 |
| docs/plans/2026-03-10-skaffen-v01-fork.md | 48 |
| core/intercore/docs/plans/2026-02-18-intercore-event-bus.md | 47 |
| docs/plans/2026-03-03-c3-composer.md | 44 |
| docs/plans/2026-03-10-conversation-resumption.md | 44 |
| docs/plans/2026-02-28-intercom-h2-last-mile.md | 43 |
| docs/plans/2026-03-04-c5-self-building-loop.md | 41 |
| docs/sprints/Sylveste-j2f-transcript.md | 40 |
| os/Clavain/docs/research/correctness-review-of-m2-plan.md | 40 |
| apps/Autarch/AGENTS.md | 39 |

## Root-Scope Structural Signals

- Root roadmap table is missing real first-level repos `interverse/interhelm`, `interverse/interlab`, and `sdk/interbase`.
- Root roadmap and vision still contain lower-case `os/clavain` and `apps/autarch` references even though the real repo paths are `os/Clavain` and `apps/Autarch`.
- Root module inventory is 64 first-level repos in the audited pillars, while the root docs still rely on unevaluated shell commands or stale prose counts.

## Follow-Up Targets

1. Regenerate or rewrite `docs/solutions/INDEX.md`.
2. Sweep imported reference packs under `interverse/interdev` and `interverse/interskill`.
3. Fix root and pillar canonical path casing before attempting a broader secondary-doc link repair.
4. Re-run the inventory scan after canonical fixes; many downstream broken references are likely to collapse once root path conventions are corrected.
