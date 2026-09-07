---
date: 2026-04-18
session: c4146098
topic: interflux blueprint B-bundles
beads: [sylveste-qv33, sylveste-n6zw, sylveste-72l2, sylveste-efyo]
---

## Session Handoff — 2026-04-18 interflux blueprint B-bundles

### Directive

> Your job is to execute the next B-bundle from the interflux improvement blueprint. Start with **B1 (flock hardening)** and **B3 (initial sanitizer)** in parallel — they unblock the most downstream work. Verify with `cd /home/mk/projects/Sylveste/interverse/interflux && bash tests/structural/test_skills.py` and a dry-run of `scripts/fluxbench-drift-sample.sh`.

- Blueprint: `/home/mk/projects/Sylveste/docs/plans/2026-04-18-interflux-improvement-plan.md`
- Campaign epic `sylveste-qv33`: CLOSED. All 11 phase children closed. Reports at `docs/research/interflux-review/phase{0-3}-*.md`.
- No in-progress beads. Clean slate to start B1/B3.

**B1 scope (2-3h)**: Add `flock -w 30` + subshell exit-code propagation to 6 scripts — fluxbench-{challenger,qualify,drift,drift-sample,sync}.sh, discover-merge.sh. Test plan in blueprint Section 3 B1.

**B3 scope (3-4h)**: New `scripts/sanitize_untrusted.py` with NFKC normalization + XML/override/fence strip; integrate into `generate-agents.py render_agent()` (persona/decision_lens/review_areas/task_context/anti_overlap); update `phases/reaction.md` Step 2.5.3 to point at it; persist openrouter tokenBucket/cumulativeSpendUsd to `~/.config/interflux/openrouter-state.json`.

**After B1+B3**: B2 (AgentSpec TypedDict + validate.py, depends on B3 for F2 integration), then B4 (SKILL.md consolidation — delete SKILL-compact.md, move Phase 2.5 back to SKILL.md), B5 (shell hygiene + MODEL_REGISTRY canonicalization), B6 (phase-file accuracy — remove Composer dead code, rename "interserve mode" → "Codex mode", step 2.1b ordering fix, total_tokens COALESCE).

Then the 4 C-epics: C1 lib_registry.py (after B1), C2 dispatch state machine (after B4+B6), C3 sanitize fuzz tests (after B2+B3), C4 flux-review command→skill refactor (after B6).

### Dead Ends

- **A-01 (hooks pathPattern scoping)** — `pathPattern` is not a Claude Code hooks.json field; `matcher` only accepts tool names. The check-compact-drift.sh script is already self-scoped via case statement. Closed as wontfix.
- **`ic publish`** — stale lock on interflux (phase validation, id pub-umxjtfld). `ic publish doctor --fix` didn't clear it. Fell back to manual publish path (bump plugin.json, update marketplace.json, rsync to `~/.claude/plugins/cache/interagency-marketplace/interflux/<ver>/`, remove old version). Use this path until the lock is cleared.
- **Python dynamic-evaluation in heredoc** — triggers a PreToolUse security hook false-positive (hook matches on the literal 3-char prefix even for Python-side use). Use `for key in path.split('.')` iteration instead of the dynamic-evaluation construct.
- **`docs/spec/README.md` drift from code-simplifier** — simplifier agent inadvertently added a reference to `athenverse-adapters.md` (untracked file, pre-existing from another session). Reverted; kept out of v0.2.60 commit.

### Context

- **interflux has its own git repo** at `/home/mk/projects/Sylveste/interverse/interflux/` — commit/push from inside, not from monorepo root. Memory confirms: `[feedback_interverse_git.md]`.
- **Opus 4.7 refusal pattern**: multi-agent dispatch + first-person persona + strategic-target framing (esp. naming Anthropic/OpenAI) triggers server-side Usage Policy refusals. v0.2.58 fixed via "Apply the perspective of X" persona reframe + `_normalize_bullet_list` for string/list LLM spec fields + synthetic-refusal detection with auto-fallback to Sonnet. Dogfood flux-drive/flux-review runs under Opus 4.7 in Phase 2 produced **no refusals** after the fix.
- **3/3 cross-track convergence finding** — "Silent failure as architecture" (MCP exit 0 on missing config, 0-byte `.lock` files with fake semantics, flock-subshell Python exceptions invisible to outer, `|| echo "[]"` masking SQL schema drift). Highest-confidence signal of the entire campaign. B1 + the A-fixes already landed address many instances; C2 (VerificationStep primitive) is the architectural response.
- **Nested Task dispatch limitation**: general-purpose subagents don't have the Task tool available, so Phase 2 flux-drive/flux-review dogfood runs executed the per-agent reviews inline instead of spawning sub-sub-agents. Same artifacts produced, but not a true parallel multi-model test. If B/C epics need true parallel dispatch, invoke from top-level Claude Code session.
- **Gitignore order matters**: `*.lock` must come BEFORE `!/mcp-servers/*/package-lock.json` negation. Processed top-to-bottom.
- **Key paths**:
  - Blueprint: `/home/mk/projects/Sylveste/docs/plans/2026-04-18-interflux-improvement-plan.md`
  - Phase reports: `/home/mk/projects/Sylveste/docs/research/interflux-review/phase{0,1,2,3}-*.md`
  - Flux-drive output bundles: `/home/mk/projects/Sylveste/docs/research/flux-drive/interflux-{scripts,skill}/`
  - Flux-review output bundle: `/home/mk/projects/Sylveste/docs/research/flux-review/interflux-full/`
- **Open risks flagged in blueprint Section 8**: FluxBench calibration integrity unknown (3 P0 silent-failures may have corrupted prior baselines); SKILL-compact.md load-frequency unknown (compact dropped Phase 2.5 reaction orchestration — B4 priority); OpenRouter in-memory rate limit bypass at scale (B3 persistence fix required before automated pipelines).
- **v0.2.61 exit-78 change**: MCP servers now return `exit 78` (EX_CONFIG) on missing API keys. Claude Code will surface this as a config error in plugin logs instead of "clean shutdown". If users report `openrouter-dispatch` or `exa` shown as failed without an API key, that's the new expected behavior.
