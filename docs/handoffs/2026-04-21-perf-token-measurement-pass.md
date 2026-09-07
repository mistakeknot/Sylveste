---
date: 2026-04-21
session: 31bf39f9
topic: perf + token measurement pass
beads: [sylveste-1tbk, sylveste-8lsf, sylveste-49kl, sylveste-ynh7]
---

## Session Handoff — 2026-04-21 Sylveste perf + token-efficiency measurement pass

### Directive
> Your job is to execute bead **sylveste-8lsf** — the measurement pass for the Sylveste perf + token-efficiency refactor epic. Produce `docs/research/2026-04-21-sylveste-cost-breakdown.md` factoring the last 50–100 sessions' per-session cost into concrete categories. **No code changes this session.** Start by running `interstat report --json` and `cass analytics tokens --json --since=30d`; verify the baseline with `bash interverse/interstat/scripts/cost-query.sh`.
- Beads:
  - `sylveste-1tbk` — epic, P1, open (parent)
  - `sylveste-8lsf` — **this session's work**, P1, open, ready (no blockers)
  - `sylveste-49kl` — P1, open, blocked by sylveste-8lsf (prompt cache audit)
  - `sylveste-ynh7` — P2, open, blocked by sylveste-8lsf (deferred-tool + skill-compact)
- Claim first: `bd update sylveste-8lsf --status=in_progress`
- Output contract: findings doc MUST name top 3 optimization targets with estimated $ / % savings each, and each follow-on bead needs a linked target metric so it can claim measured savings later.

### Categories to factor (acceptance requires all six)
- prompt preamble (CLAUDE.md + MEMORY.md + skill list + deferred-tool list)
- tool schemas (eagerly loaded MCP tool JSONSchemas)
- subagent fan-out (per-subagent startup cost × frequency)
- repeated file reads (same file Read by 3+ subagents in one session — grep cass)
- skill loading (which skills carry no SKILL-compact.md and get loaded full)
- hook output (SessionStart + bd prime + intermem + intership dumps)

### Dead Ends (do NOT repeat)
- Running `go get golang.org/x/text@latest` without `GOTOOLCHAIN=local` silently upgrades Go 1.22 → 1.25 and breaks the monorepo. Always pin + local toolchain for any dep bump.
- Asking "proceed with commit?" for routine local work — user explicitly declined; see `feedback_commit_without_asking.md` in auto-memory. Still ask for push / publish / close / destructive ops.
- Trying to defer a tool that a hook auto-invokes — breaks the hook. Cross-check `.claude/hooks/` before proposing deferrals in sylveste-ynh7.

### Context
- **Cost baseline (stale):** $2.93 / landable change from 2026-03-18, 785 sessions. Re-derive fresh baseline as first step.
- **Pricing source of truth:** `core/intercore/config/costs.yaml`. `cost-query.sh` reads it dynamically (v0.2.27+). Don't hardcode.
- **CASS binary:** `~/.local/bin/cass` v0.2.0. Search with `cass search "<q>" --robot --limit N --mode hybrid`; analytics via `cass analytics {tokens,tools,models} --json`. SessionStart hook auto-indexes when stale >1hr.
- **interstat scope (post-v0.2.1):** only bead-correlated token metrics. Session search moved to intersearch. Use `interstat report` for cost/tokens, `cass` for session intelligence.
- **Prior-art check is mandatory per `/clavain:strategy` Phase 0** — grep `docs/research/assess-*.md` for any tool before reimplementing. Memory note [2026-03-08] covers why.
- **Suspected biggest line items (hypothesis only — verify with data):**
  - MEMORY.md at 128/120 lines, auto-growing; cache miss every session it changes
  - 18 `interlens_*` lens tools loaded eagerly, most unused per session
  - `intermap_*` and `intercache_*` MCPs rarely hit in day-to-day work
  - Deferred-tool MCP disconnects mid-session invalidate schemas, trigger re-discovery
  - agent-rig postInstall message was just added (d63e139) — may reshape first-session preamble cache
- **Absolute paths (WIP):**
  - Measurement findings target: `/home/mk/projects/Sylveste/docs/research/2026-04-21-sylveste-cost-breakdown.md`
  - Baseline query: `/home/mk/projects/Sylveste/interverse/interstat/scripts/cost-query.sh`
  - Pricing: `/home/mk/projects/Sylveste/core/intercore/config/costs.yaml`
  - Assessment docs: `/home/mk/projects/Sylveste/docs/research/assess-*.md`
- **Previous handoff just shipped authz v1.5 + polish + v2 handoff.** All three repos pushed, beads synced. Clean entry state — no WIP code to reconcile.

### Minimum-viable first session
If short on time, ship the three highest-impact factored numbers + a baseline and mark sylveste-8lsf partially complete; full 6-category factoring can span two sessions. The blocked children need even rough numbers to start.
