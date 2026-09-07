---
date: 2026-04-21
session: db68505b
topic: Autosync kill + interfer cleanup + 2ss resume
beads: [Sylveste-ql9, Sylveste-2d9, Sylveste-t0o, Sylveste-b7j, Sylveste-2ss]
---

## Session Handoff — 2026-04-21 Autosync kill + 2ss resume

### Directive

> Your job is to resume **Sylveste-2ss** (Flash-MoE holistic benchmarking) by landing **Sylveste-b7j** — wire SWE-bench Lite + LiveCodeBench v6 into the holistic benchmark harness in `/Users/sma/projects/Sylveste/interverse/interfer`. Start by reading `bd show Sylveste-b7j` for scope, then scaffold `benchmarks/code_correctness.py` next to the existing holistic runner. Verify with `uv run python -m benchmarks.code_correctness --model=local:qwen3.5-122b --suite=swe-bench-lite --dry-run` and confirm pass@1 emits without requiring real MLX inference.

- Beads in flight: `Sylveste-b7j` — open, P1, blocks on `Sylveste-2ss` (in_progress). `Sylveste-2ss` is the parent epic.
- Fallback work: **Mutation 3** (wire LMCache Prometheus endpoint as a vLLM-backed baseline) or **Mutation 1** (per-token expert-overlap telemetry — only useful if someone publishes a credible MoE draft scheme worth checking).

### Dead Ends

- **Speculative decoding on routed MoE** — confirmed dead end as of April 2026. LayerSkip got 0% acceptance on Qwen3.5 (Sylveste-qbv); llama.cpp PR #19493 (merged 2026-04-19) enabled classic draft-speculative for Qwen3.5/3.6 MoE and the community reproduction on RTX 3090 + Qwen3.6-35B-A3B got zero speedup across 19 configs (3–12% slowdown). Root cause: draft tokens route to new experts, wrecking bandwidth. Don't revisit until someone solves expert-path-consistency for drafting.
- **Parallel `git reset --hard`** — failed mid-session (stale index.lock); serial was required. Only relevant while autosync existed — now moot.
- **Custom expert caching on Apple Silicon** — Flash-MoE's public numbers show OS page cache beats custom caching.

### Context

- **Every git op in this repo must prefix `env -u GIT_INDEX_FILE`** or unset the var at shell start. Claude Code sets `GIT_INDEX_FILE=<umbrella>/.git/index-<session-uuid>` on every shell. Without clearing, git ops read/write a per-session phantom index instead of real ones. This is what contaminated 110 child repos last session.
- **Autosync is gone, not just disabled.** `~/.claude/hooks/git-autosync{,-pull}.sh` deleted, both hook entries removed from `~/.claude/settings.json`, both `.git-autosync` markers (umbrella + `~/.local/share/Sylveste/`) removed. If autosync "needs" to come back, rebuild from scratch with explicit `unset GIT_INDEX_FILE` and recursion guards — do not restore from backup.
- **Prior handoff's "genuinely corrupt" claim was wrong.** `interverse/interfer` and `research/pi_agent_rust` are both healthy (`fsck --full` clean). The handoff mistook modified-tracked-files state and dangling commits for object-store corruption.
- **`.beads/push.sh` is now Mac/Linux portable** — derives paths from `BASH_SOURCE`, auto-detects dolt via `command -v`, honors `BEADS_DOLT_DB` / `BEADS_DOLT_BIN` overrides.
- **Pre-existing test flake (not yours):** `tests/test_turbo_quant.py::test_polar_transform_range` in interfer fails on main. Already tracked at **Sylveste-wfz**. Deselect with `--deselect tests/test_turbo_quant.py::test_polar_transform_range` when running the interfer suite.
- **Key research artifacts (from flux-research 2026-04-21, in transcript only — not written to disk):**
  - SWE-bench Verified leaderboard: 86 models evaluated; Qwen3 32B at ~3.4% resolve rate (baseline for our local-MoE numbers)
  - LiveCodeBench v6 is contamination-free with time-segmented cutoffs — preferred over SWE-bench Verified for first pass
  - MLX mixed-bit quantization (`mixed_2_6`, `mixed_3_4`, `mixed_3_6`, `mixed_4_6`) shipped in mlx-lm 0.31+ — enables hand-tuned expert-vs-attention bit allocation; worth a separate mutation later
  - LMCache (April 2026) claims 13× TTFT improvement via MP mode, Prometheus endpoint available — only applies to vLLM-backed baselines
  - **Green field:** per-expert routing-stability telemetry (which experts fire on which tokens, variance across runs). Nobody's published this for MoE observability. Candidate for a future 2ss mutation.
- **Interfer commits landed this session:** admission gate extract + shared `conftest.py` fixtures + removed deprecated `kv_quantization` yaml stanza (Sylveste-t0o). 222 tests pass (1 pre-existing flake deselected).
- **Mac repo inventory tools** (in /tmp, may not survive reboots):
  - `/tmp/inventory_contam_v2.sh` — correctly clears `GIT_INDEX_FILE`
  - `/tmp/repair_mac_repo_v2.sh` — correctly clears `GIT_INDEX_FILE`
