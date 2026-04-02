---
date: 2026-04-02
session: d4d31fd6
topic: Claude Code source analysis for Skaffen
beads: [sylveste-18a, sylveste-18a.1, sylveste-18a.7, sylveste-18a.8, sylveste-18a.9, sylveste-18a.10, sylveste-18a.11, sylveste-18a.12]
---

## Session Handoff — 2026-04-02 Claude Code source analysis for Skaffen

### Directive
> Your job is to continue porting Claude Code production patterns to Skaffen. Start by sprinting `sylveste-18a.8` (auto-compact context management) — it's the most critical missing feature. Verify with `cd os/Skaffen && go test ./... -count=1 -race`.

- Epic: `sylveste-18a` — 12 children, 2 shipped (.1 tool concurrency, .7 deep research), 10 open
- Next priority: `.8` auto-compact (P1, unblocked, blocks `.9` post-compact restoration)
- Alternative: `.6` dangerous pattern deny list (P1, smaller scope, unblocks `.5` bubble mode)
- The masaq `ScrollTo` fix was committed and pushed — Skaffen build is green (25/25 -race)

### Dead Ends
- **Approach A (extend core Tool interface) for concurrency** — rejected by 3 independent review agents. Optional interface (Approach B) is correct for Go. The user initially chose A; brainstorm review caught it before any code was written.
- **Direct slice writes in executeBatchParallel** — Go race detector flags concurrent writes to distinct slice indices. Switched to channel-based collection (`chan indexedResult`).
- **`find` in safeCommands** — `find -delete` and `find -exec rm {} +` bypass metachar guard. Removed from safe list.
- **`sed`/`awk` in safeCommands** — both can write (`sed -i`, `awk print-to-file`). Removed.
- **StreamToolStart in executeBatchSerial** — double-emitted because `collectWithCallbacks` already emits it during streaming. Removed from execution phase.
- **flux-gen agents as subagent_types** — generated agents in `.claude/agents/` require session restart to become available as subagent_types. Used core fd-* agents instead.

### Context
- `research/claude-code-source/` contains the full Claude Code CLI source (512K LOC TypeScript, leaked .map file extract). Gitignored. Key files for future research: `src/coordinator/coordinatorMode.ts` (370-line coordinator prompt), `src/services/compact/autoCompact.ts` (compaction thresholds), `src/utils/permissions/yoloClassifier.ts` (two-stage bash classifier), `src/memdir/` (persistent memory)
- masaq subrepo at `/home/mk/projects/Sylveste/masaq/` had its working tree wiped (all files showed as `deleted` in git status but never committed). `git restore .` fixed it. Root cause unknown — possibly mutagen sync or a bulk operation.
- 5 flux-gen agents were generated at `.claude/agents/fd-{go-concurrency-safety,interface-contract-integrity,tui-event-loop-isolation,oodarc-phase-ordering,observability-and-failure-modes}.md` — these are Skaffen-specific review agents, usable in future flux-drive reviews after session restart.
- The `executeOne` pattern (named return + deferred recover, single channel send) is the canonical way to handle goroutine panics with channel-based collection in Skaffen. The dual-send deadlock was caught by quality gates.
- `GatedRegistry` in `agent/gated_registry.go` was confirmed dead code and deleted. If anyone asks, it was an adapter layer NOT used by `Agent.Run()`.
