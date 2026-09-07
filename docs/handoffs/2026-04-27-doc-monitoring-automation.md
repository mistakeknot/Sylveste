---
date: 2026-04-27
session: 8c5f754c
topic: doc-monitoring automation
beads: [sylveste-4rwh, sylveste-v3ck, sylveste-129h, sylveste-8r5h, sylveste-5lla, sylveste-hfmh]
---

## Session Handoff — 2026-04-27 doc-monitoring automation

### Directive
> Your job is to design how Sylveste should automate document/context updates and monitoring so roadmaps and other docs stay current without per-invocation human prompting. Start by reading `interverse/interpath/`, `interverse/interwatch/`, `interverse/interject/` SKILL.md files and `os/Clavain/skills/status/SKILL.md` — these are the existing building blocks. Verify by running `/interpath:status` and `/clavain:status` to see what's already wired and what drifts silently today.

- **Hard constraint:** do NOT propose a new plugin that pre-bundles a daily/weekly pipeline. That is exactly the shape we just retired (`interscout`, sylveste-hfmh). It violates compose-through-contracts.
- **Soft constraint:** propose composition strategies first (event triggers, drift-driven refresh, on-access regen). Only consider new primitives if no composition closes the loop.
- **Open question to resolve:** is the right trigger model (a) drift-detected by `interwatch` → auto-fire `/interpath:all`, (b) on-access lazy regen when a doc is read after staleness threshold, (c) post-merge git hook, or (d) some hybrid? Each has tradeoffs around latency, cost, and Goodhart pressure on the staleness metric itself.
- **Beads to keep visible:** sylveste-hfmh (retire interscout, P3 — already deprecated, awaiting final removal) ; the 5 leverage beads from yesterday (sylveste-4rwh/v3ck/129h/8r5h/5lla) are scheduled for triage 2026-05-10 via `trig_012g5vyrz8WCznAxaKbGFxaH` — don't conflate.

Fallback: if the design loop bogs down, do a discovery pass on existing drift signals (`bd search drift`, `bd search staleness`, grep `interwatch` for what it currently detects) before committing to an architecture.

### Dead Ends
- Recreating interscout's bundle as `/schedule` routines — same kitchen-sink anti-pattern at a different layer. Don't.
- Dispatching flux skills via `general-purpose` subagents — the subagent context lacks Bash/Write/Agent recursion, so multi-phase pipelines degrade to in-process simulation. Run flux pipelines in main context, or only delegate LLM-only work to subagents.
- `ic publish --patch` for interdoc on 2026-04-26 — stuck on stale lock `pub-8fjjrsmr` at validation phase; `ic publish status` did not show it, `ic publish clean` didn't clear it. Workaround: manual `plugin.json` version bump + commit + push. Fixing the lock-clear path is its own bead-worthy task.

### Context
- **The big finding from yesterday's sweep:** name-collision bug pattern between `commands/<name>.md` and `skills/<name>/SKILL.md`. Skill tool resolves to command body; redirect-style commands shadow real skills. Fix: rename skill frontmatter `name:` to `<name>-engine`. Applied to 12 skills across 6 plugins (interflux, interdoc, Clavain×2, interpeer, interblog×4, interscout×3). Look for other plugins to use the same fix shape if they appear broken.
- **interscout retirement:** README at `/home/mk/projects/Sylveste/interverse/interscout/README.md` documents the migration. Each command body has a deprecation banner. Plugin still installable. **It is the negative example for this next session.** Read it before designing anything.
- **Existing primitives that map to "keep docs fresh":**
  - `/interpath:all` — refreshes High/Certain confidence artifacts based on interwatch drift state
  - `/interpath:{roadmap,prd,vision,cuj,changelog,propagate}` — per-artifact generators
  - `/interwatch` — drift detection (the trigger source already exists)
  - `/interject:scan` — ambient discovery
  - `/clavain:status` — unified status dashboard
  - `/schedule` — CCR cron + run_once_at routines (the scheduling primitive — exists, don't rebuild)
- **Vision context:** the 5 leverage beads filed yesterday came from a multi-pipeline interflux analysis. Strongest finding (3/3 convergent) was substrate-independence — Interspect audits the kernel it runs on. That gap matters for any auto-update architecture too: a doc-monitor that audits state through the same substrate it lives in repeats the same architectural debt. Worth thinking about whether the doc-monitor needs a separate evidence path from the docs themselves.
- **Compose-through-contracts is the load-bearing principle for this design.** PHILOSOPHY.md § Composition. The interflux→interpath→interwatch chain should be reachable from any composition shape; the new design should not require a wrapping plugin to glue them.
- **Synthesis docs to read for ecosystem state:**
  - `/home/mk/projects/Sylveste/docs/research/flux-review/sylveste-vision/2026-04-26-synthesis.md`
  - `/home/mk/projects/Sylveste/docs/research/flux-engine/sylveste-mission-leverage-20260426.md`
  - `/home/mk/projects/Sylveste/docs/brainstorms/2026-04-26-flux-explore-sylveste-flywheel.md`
- **Active plugins shipped this session:** interflux@0.2.65, interdoc@5.2.3, Clavain@0.6.245 (linter bumped to .245 after my .244), interpeer@0.1.1, interblog@0.1.4, interscout@0.1.2 (deprecated). All on `mistakeknot/<name>` GitHub.
