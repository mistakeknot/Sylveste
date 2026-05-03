---
date: 2026-05-02
session: unknown
topic: microrouter Track B6 — start .19.8 design revision
beads: [sylveste-s3z6.19, sylveste-s3z6.19.1, sylveste-s3z6.19.2, sylveste-s3z6.19.3, sylveste-s3z6.19.4, sylveste-s3z6.19.5, sylveste-s3z6.19.6, sylveste-s3z6.19.7, sylveste-s3z6.19.8, Sylveste-jm4, Sylveste-emv, Sylveste-a5u, Sylveste-906, Sylveste-7pq, Sylveste-b1e, Sylveste-v3b, Sylveste-2lh, Sylveste-j6t, Sylveste-w6j, Sylveste-96p, Sylveste-gxl, Sylveste-t0g, Sylveste-d3r]
---

## Session Handoff — 2026-05-02 microrouter Track B6 / start .19.8

### Directive
> Your job is to start `sylveste-s3z6.19.8` — the design revision that hard-blocks `.19.1` (design doc). Read `bd show sylveste-s3z6.19.8` and the synthesis at `/Users/sma/projects/Sylveste/docs/research/flux-review/microrouter-track-b6/2026-05-01-synthesis.md`. The bead defines four problems but defers the resolution of two design forks to this session.
- Beads ready (P0): `sylveste-s3z6.19.8` (start here), plus 4 P0 finding beads under the epic (`Sylveste-jm4`, `Sylveste-emv`, `Sylveste-a5u`, `Sylveste-906`)
- Forks to resolve via AskUserQuestion (one at a time per global preference):
  1. **Architecture α vs. β** — α: judge family ≠ baseline anchor (Gemini/Qwen judge, Opus calibration as anchor). β: replace baseline anchor entirely with observed downstream pass@1. β is stronger but only viable if the production-pass@1 data exists. Check whether interspect verdicts contain enough actual-pass-fail outcomes (not judge recommendations) — `bd show Sylveste-emv` has the framing.
  2. **Calibration freeze mechanics** — snapshot `routing-calibration.json` at the holdout cut date. Decide: SHA hash check enforced where (training pipeline entry only? Or also at every read?). Decide: held-out-agents workload — which 2-3 agents to exclude (must be high-volume so holdout has signal; must NOT be fd-safety/fd-correctness because those have safety floors that bypass routing entirely).
- Verify the design lands by: (1) writing `docs/brainstorms/2026-MM-DD-microrouter-track-b6-design-revision.md`, (2) editing `.19.2`, `.19.3`, `.19.4` bead bodies to reference the revision, (3) `bd export -o .beads/issues.jsonl && git commit && git push`
- Dependency chain: `.19.8` (P0, ready) → blocks `.19.1` → blocks `.19.2`, `.19.5` → diamond into `.19.3` → `.19.4` → `.19.7`; `.19.5` → `.19.6`

### Dead Ends
- **Track D flux-review (esoteric agents)** — timed out at 600s watchdog, never produced findings. The 3 agents (`fd-khipukamayuq-paired-audit`, `fd-fulani-garso-shadow-soak`, `fd-curare-titration-feedback`) were designed and have agent files in `.claude/agents/` but their reviews never ran. Don't re-run — Tracks A/B/C already converge 3/3 on the most important findings (safety-floor bypass).
- **`bd backup sync` to refresh JSONL** — does NOT update `.beads/issues.jsonl`. That command pushes Dolt off-machine (e.g., DoltHub). Use `bd export -o .beads/issues.jsonl` to refresh the tracked JSONL backup. The session-start protocol's wording is misleading.
- **`bd dep add A B` for re-parenting** — wrong primitive. That creates "A blocked by B" dep, not parent-child. Correct primitive is `bd update <id> --parent <epic>`. Wasted ~30s undoing 14 wrong deps before realizing.
- **Subagent-claimed bead IDs** — flux-review synthesis subagent reported "14 beads created" with specific IDs but its summary alternately said "did not create" and "created and recommend triaging." Beads DO exist (`Sylveste-jm4` etc., capital S). Always verify subagent claims about state mutations with `bd show`.
- **`git stash push -u --` with scoped paths** — chokes when the scoped path tree contains gitignored files. Plain `git stash push` (tracked-only, no `-u`) was the right move when stashing alongside untracked-but-ignored review output.

### Context
- **Routing.yaml resolver order is critical**: microrouter MUST sit BELOW `overrides[agent]` in the chain, not above. Above means a learned router can override fd-safety/fd-correctness Sonnet floors. `.19.5` body has the corrected chain spec.
- **Three factual errors in original `.19.5`** (now fixed in body): port 8421 collides with B5 interfer (`interverse/interfer/server/__main__.py:22`), so use 8422; `routing-overrides.schema.json` is the interspect-overrides schema NOT a routing.yaml validator; the resolver is `scripts/lib-routing.sh` (Bash, ~1475 lines), NOT Go.
- **The deepest finding is P0-B (gongfu-cha)**: GPT-5.5/Opus is BOTH the augmentation judge in `.19.3` AND the implicit anchor for the ≥90% holdout-agreement criterion. Router learns to imitate evaluator. This is what `.19.8` Architecture α/β fork addresses. It was the single most important finding from the entire 4-track review.
- **14 review-finding beads were auto-created by Track B/C subagents** — re-parented under epic, not closed. They overlap heavily with `.19.5`/`.19.8` content but are kept as discoverable findings. Future work-in-area should close them as the relevant child completes; do not pre-emptively close.
- **Flux-review output dirs are gitignored**: `.gitignore:79` excludes `docs/research/*/` so `INPUT.md`, `2026-05-01-synthesis.md`, and per-agent finding files at `docs/research/flux-drive/INPUT/` and `INPUT-20260501T2239/` are durable on disk only. If you want the synthesis in git, edit `.gitignore:79` to allow `docs/research/flux-review/`.
- **Working tree has unrelated mods**: `interverse/interfer/server/flashmoe_worker.py` and its test are modified by another session (parallel tmux flash-MoE focus per session-start framing). Do not stage. Stash with plain `git stash push` (no `-u`) before any rebase.
- **Post-rebase**: today's commit landed at `ff59fead` after rebasing past `849afcbe..ff59fead`. The remote has GitHub branch protection that emits "Changes must be made through a pull request" — informational only, push went through.
- **Synthesis file path** (durable, gitignored): `/Users/sma/projects/Sylveste/docs/research/flux-review/microrouter-track-b6/2026-05-01-synthesis.md` (329 lines, ~5K words). Per-agent findings split between `docs/research/flux-drive/INPUT/` (5 Track A files) and `INPUT-20260501T2239/` (8 Track B+C files + structured findings.json).
- **`.19.5` body absorbed**: P0-A (resolver below overrides), P0-F (port 8422), P0-G (no schema validator), P0-H (Bash not Go), P0-I (no silent auto-degrade — explicit fall-through table with structured logging). `.19.8` body absorbs: P0-B, P0-C, P0-D, P0-E. Other P0s (P0-J audit-trail unconformity, P0-L privacy fail-mode) are NOT absorbed yet — they belong in `.19.5`/`.19.6` follow-up edits but are tracked in finding beads `Sylveste-a5u` and `Sylveste-906`.
