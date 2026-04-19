# Flux-drive synthesis — interflux/scripts/

**Date**: 2026-04-17
**Input**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/` (25 scripts, ~5500 LOC)
**Agents launched**: 5 (fd-architecture, fd-safety, fd-correctness, fd-quality, fd-performance)
**Agents skipped**: 7 (fd-user-product, fd-game-design, fd-systems, fd-decisions, fd-people, fd-resilience, fd-perception — all correctly filtered by Step 1.2a for code targets)
**Challenger**: deepseek/deepseek-chat-v3 (shadow only, see `challenger-deepseek.md`)

## Verdict

**MATERIAL-ISSUES (4 P0-ish, 15 P1) — concentrated in fluxbench-* scripts around flock lifecycle, Python heredoc-in-shell duplication, and the 5x-copied registry-write pattern. The scripts/ layer is broadly hygienic (set -euo pipefail everywhere, jq --arg consistently, atomic writes) but has accumulated architectural debt in the form of 8+ copies of "read yaml → mutate → dump" and 5 copies of "atomic registry mutate under flock."**

The review target is dogfooding (interflux reviewing its own scripts via its own skill). No review agent refused under Opus 4.7 — the v0.2.59 sanitization fixes held. Cognitive agents correctly skipped per the code-not-docs rule.

## Convergence table

Findings where ≥2 agents independently landed on the same issue (+1 confidence each):

| Issue | Agents | Dedup | New? |
|---|---|---|---|
| Python-in-flock-subshell pattern duplicated across 4+ scripts | fd-architecture ARC-01, ARC-02; fd-correctness COR-01 | Also in Phase 1 silent-failure finding | **Converged — already known, confidence++** |
| `_parse_frontmatter` duplicated in generate-agents.py vs flux-agent.py | fd-architecture ARC-04, fd-quality QUA-01 | Not in Phase 0/1 | **NEW** |
| `_count_usage_from_synthesis` double-walk (flux-agent.py) | fd-quality QUA-07, fd-performance PER-02 | Not in Phase 0/1 | **NEW** |
| `config_path` interpolation in discourse-health.sh:39 | fd-safety SAF-01 | Not in Phase 0/1 | **NEW P1 safety** |
| fd 201 flock nested-lock deadlock class | fd-correctness COR-02 | Not in Phase 0/1 | **NEW P0 correctness** |
| Inconsistent MODEL_REGISTRY / REGISTRY_FILE / REGISTRY naming | fd-architecture ARC-03 | Not in Phase 0/1 | **NEW** |

## New findings (not in Phase 0/1)

### P0 (concurrency)

1. **COR-02 — fluxbench-drift-sample.sh:142 loop calls fluxbench-drift.sh:64 which takes the same `${registry}.lock`.** No `flock -w` timeout anywhere in scripts/. A stuck holder (e.g., a concurrent `fluxbench-qualify.sh` that hangs on a long python3 heredoc) will deadlock the drift loop, cascading into the session-start hook.
   - **Fix**: Add `flock -w 30 -x 201` to all 6 call sites. Log and skip on timeout. Drift sampling is advisory.

2. **COR-01 — `trap RETURN` in fluxbench-qualify.sh:_update_registry does not fire on SIGINT.** Temp files leak in `/tmp` on user Ctrl-C during long runs.
   - **Fix**: Move tmp-file cleanup to an `EXIT` trap on the outer flock subshell (qualify.sh:491), not the function. Same pattern already used correctly in fluxbench-challenger.sh.

### P1 (architecture + safety + correctness)

3. **ARC-01 — Registry-write pattern copy-pasted 5x with subtle divergence** (fluxbench-challenger.sh, fluxbench-qualify.sh, fluxbench-drift.sh, discover-merge.sh). Disagreements on trap lifetime, validation, and lock-path variable naming. **Extract `scripts/lib-registry.sh` — highest-leverage refactor in the plugin.**

4. **ARC-02 — YAML read→mutate→dump python3 heredoc duplicated ~8x.** Five scripts independently normalize `reg['models']` dict-vs-list confusion, with different fall-throughs. If someone edits model-registry.yaml by hand to `models: null`, the five call sites produce four different behaviors.

5. **ARC-04 / QUA-01 — `_parse_frontmatter` and `_infer_domains` duplicated across generate-agents.py and flux-agent.py** with diverging keyword maps and error handling. generate-agents returns `None` silently on missing pyyaml; flux-agent raises. Same parse, different contract.

6. **SAF-01 — `discourse-health.sh:39` interpolates `$config_path` into a python3 -c heredoc.** Shell-injection exploitable if a user passes an attacker-controlled config path (e.g., from a cloned repo). The env-var-for-heredoc pattern is already the house style — this one site just missed the migration.

7. **SAF-02 — `estimate-costs.sh:51` uses grep with an unescaped `agent_type` as the regex pattern.** Safe today (hardcoded values), activates the moment `classify_agent` returns a derived value. Trivial awk fix.

8. **COR-03 — fluxbench-sync.sh two-phase pending→committed has a crash gap.** Kill between phase 2 (AgMoDB writes) and phase 3 (commit marks) causes re-sync to overwrite partial files, time-traveling `last_sync` timestamps.

9. **COR-04 — fluxbench-score.sh P0 auto-fail loop doesn't normalize severity strings.** LLM output with trailing spaces (`"P0 "`) fails equality check, marking correct P0 identifications as downgrades.

10. **COR-05 — findings-helper.sh:49 `grep '^{'` mis-filters.** Drops valid non-object JSON lines AND keeps malformed lines that start with `{`. A mid-write crash breaks the entire findings file parse.

11. **QUA-02 — token-count.py:78 `sys.exit(1)` on fallback contradicts docstring.** Callers using `|| echo '{}'` throw away the estimate.

12. **PER-01 — fluxbench-qualify.sh --score mode: 5 jq forks per fixture × 5-10 fixtures.** At 30-50 fixture scale, adds 500ms-1s to qualification runs.

13. **PER-03 — detect-domains.sh: 80+ yq forks per invocation.** Already close to the documented 5s budget on cold cache.

### P2 (quality)

14. **ARC-03 — Three names for the same registry env var** (MODEL_REGISTRY / REGISTRY_FILE / REGISTRY). Test runners that override one of them get inconsistent behavior across scripts.

15. **ARC-06 — flock fd 200 overloaded for two unrelated domains** (findings file vs results JSONL). Footgun for future nested call sites.

16. **COR-08 — awk convergence regex `[Pp][0-2]` has false-positive on prose.** "p2p network" substring matches as severity P2.

17. **QUA-03 — `2>&1 $(...)` at fluxbench-challenger.sh:208** captures stderr into the value. Python DeprecationWarnings break downstream jq parse, causing silent "no candidate."

18. **PER-06 — fluxbench-drift-sample.sh re-parses results JSONL per model**, O(M × N). Fine at 30 models × 500 entries; breaks at 2000.

## Convergence with Phase 0/1 findings (confidence++)

- **Python-in-flock-subshell pattern**: Phase 1 silent-failure analyst already called this out across 4 scripts. Three review agents (fd-architecture, fd-correctness) independently flagged the same pattern. +1 confidence — the refactor to `lib-registry.sh` / `lib_registry.py` is now supported by 4 independent reviewers.

- **LLM spec validation (name regex, persona sanitization)**: Phase 1 security and type-design both called this out. fd-safety in this review **did not restate** these (correctly deduplicated) and called out only the additional untrusted-content pathways (discourse-health config_path, estimate-costs grep pattern).

- **Silent-failure in estimate-costs.sh:85-96**: Known from Phase 1. This review adds SAF-02 on line 51 (a **different** silent-failure path in the same file).

## Top 5 actionable improvements (scripts-layer-specific)

Ordered by leverage × ease:

1. **Add `flock -w 30` timeouts** to all 6 `flock -x 201` call sites (fluxbench-{challenger,qualify,drift,drift-sample,sync}.sh, discover-merge.sh). Low effort, high operational value — eliminates entire class of deadlock bugs.

2. **Extract `scripts/lib_registry.py`** as a single Python module with `load_registry`, `get_model`, `set_model_field`, `validate_and_dump`. Delete 5 heredocs. ~200 LOC reduction, unit-testable, eliminates dict-vs-list normalization drift.

3. **Extract `scripts/_frontmatter.py`** and `scripts/_domain_inference.py` from generate-agents.py + flux-agent.py. Eliminates 2 sources of drift, adds type safety, enables mypy.

4. **Migrate discourse-health.sh:39 and estimate-costs.sh:51 to the env-var-for-heredoc pattern.** Each is a 5-line mechanical change. Closes the two remaining shell-injection vectors.

5. **Run `shellcheck -s bash scripts/*.sh` in CI.** Would catch the `2>&1 $(...)` anti-pattern (QUA-03), the `|| true` posture inconsistencies, and unquoted interpolations automatically. Also catches ~half of the findings in fd-correctness without human review.

## Cost estimate (self-review)

Agent token spend: ~35K tokens across 5 fd-* review outputs (5 × ~7K). Challenger: 1.5K. Approx 37K total at ~$0.03/1K = **~$1.10 in API equivalents**. Compare to baseline flux-drive $2.93/landable change (per CLAUDE.md memory) — within budget for a tight-scoped dogfood.
