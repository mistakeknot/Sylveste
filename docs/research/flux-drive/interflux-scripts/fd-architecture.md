<!-- flux-drive:complete -->

## Findings Index

- P1 | ARC-01 | "fluxbench-*.sh" | Registry-write pattern duplicated 5x with drift risk
- P1 | ARC-02 | "fluxbench-challenger.sh / fluxbench-qualify.sh" | yaml-roundtrip python3 -c heredoc reinvented in 4 files
- P2 | ARC-03 | "discover-merge.sh / fluxbench-challenger.sh" | MODEL_REGISTRY/REGISTRY_FILE variable naming inconsistency across scripts
- P2 | ARC-04 | "generate-agents.py / flux-agent.py" | `_infer_domains` implemented twice, drifts
- P2 | ARC-05 | "fluxbench-score.sh" | 200-line inline Python (Hungarian + scoring) inside shell heredoc — unit-testable logic trapped in bash
- P2 | ARC-06 | "findings-helper.sh / fluxbench-score.sh / fluxbench-qualify.sh" | flock fd 200 overloaded for two different lock domains (findings vs results JSONL)
- P3 | ARC-07 | "validate-*.sh" | 5 validators with similar scan+compare shape — no shared helper

## Verdict

**MINOR-ISSUES — coupling is fine at the public contract layer, but 4-5 near-identical patterns have been hand-copied across 8+ shell scripts. Extraction into a single `lib-registry.sh` and `lib-yaml-io.py` would eliminate ~300 LOC of boilerplate and close the drift gap between variations of the same operation.**

## Summary

The scripts/ directory is a mature mix of plugin lifecycle tooling (`generate-agents`, `flux-agent`), benchmark orchestration (`fluxbench-*`), and launchers. Module boundaries are generally good — each script has a clear job — but the **same three operations** keep being re-implemented inline:

1. "read YAML → mutate one nested field → dump YAML → atomic rename" (seen in fluxbench-challenger.sh `_set_model_status`, `_promote_model`; fluxbench-qualify.sh `_update_registry`; discover-merge.sh inline; fluxbench-drift.sh `yq -i` variant).
2. "flock registry → python3 -c heredoc → validate → mv" (same 5 files).
3. "extract agent_type / model_slug → env-var-export → python3 -c → capture stdout" (calibrate.sh, qualify.sh, challenger.sh, score.sh, drift.sh, drift-sample.sh — this pattern appears ~20 times).

The copy-pasta hasn't caused a visible defect **yet**, but each copy has slightly different error handling (drift.sh uses `yq -i` with `.tmp` intermediate; qualify.sh uses `python3` heredoc; challenger.sh uses python3 heredoc **inside** a flock subshell with a separate `trap RETURN` that behaves differently from the trap-EXIT used in qualify.sh). The pattern is already diverging.

## Issues Found

### P1 | ARC-01 | Registry-write pattern copy-pasted 5x with subtle divergence

**Files**:
- `fluxbench-challenger.sh` lines 42–82 (`_set_model_status`) and 87–130 (`_promote_model`) — two functions doing the same shape of write
- `fluxbench-qualify.sh` lines 141–208 (`_update_registry`) — trap RETURN variant
- `fluxbench-drift.sh` lines 156–166 — inline `yq -i` variant
- `discover-merge.sh` lines 24–96 — inline python heredoc variant

**Problem**: Each implementation does the same 5 steps (flock → cp to tmp → mutate tmp → yaml.safe_load validate → mv tmp → original), but they disagree on:

- **Trap lifetime**: qualify.sh:144 uses `trap 'rm -f "$tmp_reg"' RETURN` — which fires when the **function** returns, but the `cp` on line 148 and the yaml dump in the heredoc run **under a `flock -x 201` subshell** started by the caller at qualify.sh:494. If the caller subshell exits on error before `_update_registry` returns, the trap still fires, but if the caller's subshell is killed mid-python, the temp file is leaked. Challenger.sh uses `trap 'rm -f "$_tmp_reg"' EXIT` inside the flock subshell, which is the more defensive pattern.
- **Validation**: `fluxbench-challenger.sh:80` and `:127` runs `python3 -c "yaml.safe_load(open(...))"` before mv. `fluxbench-qualify.sh:206` does the same. `discover-merge.sh:90` does **not** validate — it just writes and hopes.
- **Lock naming**: All use `${MODEL_REGISTRY}.lock` **except** discover-merge.sh which uses `${REGISTRY_FILE}.lock`. When `MODEL_REGISTRY` and `REGISTRY_FILE` are set to the same path by default, the locks are the same file — but if a caller overrides only one of them (e.g., tests), the lock is on a different file and serialization silently breaks.

**Concrete failure scenario**: Someone adds a 6th registry mutation in the future, copies the variant from whichever script they're in, and ships it **without the yaml validate-before-mv step**. A transient typo in a yaml dump (e.g., trailing-newline handling on Darwin vs Linux) then corrupts the registry — and because the old scripts validated, they survived the same bug.

**Fix**: Extract to `scripts/lib-registry.sh`:
```bash
# Single-source helper for registry atomic writes
registry_atomic_mutate() {
  local registry="$1" mutator="$2"  # mutator = "python -c heredoc" or "yq expr"
  local fd="${3:-201}"
  (
    flock -x "$fd"
    local tmp=$(mktemp)
    trap "rm -f '$tmp'" EXIT
    cp "$registry" "$tmp"
    # run mutator on tmp
    eval "$mutator"  # or pass as stdin
    python3 -c "import yaml; yaml.safe_load(open('$tmp'))" || return 1
    mv "$tmp" "$registry"
  ) "$fd">"${registry}.lock"
}
```
Then the 5 call sites become 5-line wrappers instead of 40-line blocks.

**Severity**: P1 — not broken today, but drift already observed between implementations, and the "add a sixth call site" failure is load-bearing.

### P1 | ARC-02 | yaml read→mutate→dump python3 heredoc duplicated ~8x

**Files**: `fluxbench-qualify.sh:150–204`, `fluxbench-challenger.sh:53–77` and `:97–124`, `discover-merge.sh:27–93`, `fluxbench-drift-sample.sh:89–97`.

**Problem**: Same 20-line pattern — `python3 -c "import yaml, json, os ; reg = yaml.safe_load(open(os.environ['_FB_TMP_REG']))..."` — appears in 5 files. Each variant reinvents:
- Handling of `reg['models']` being a dict vs list vs None (qualify.sh:168–170 normalizes list→dict, challenger.sh:66–71 handles both as read-only).
- Handling of `model is None` (qualify.sh:172–174 creates empty dict; challenger.sh:73–74 skips silently).
- Handling of missing nested keys (qualify.sh:181–182 creates `fluxbench` dict; drift.sh never does).

**Concrete failure scenario**: If the model-registry.yaml gets edited by a human to have `models: null`, the five different call sites will take four different paths — one creates a models dict, one errors, one silently skips the update. Registry state then depends on which script ran most recently.

**Fix**: `scripts/lib-registry.py` module with `load_registry()`, `get_model(reg, slug)`, `set_model_field(reg, slug, key, value)` — call from every shell script as `python3 -c 'from lib_registry import ...'`. This also makes the logic unit-testable.

**Severity**: P1 — divergence is already real (confirm by diffing the 5 heredocs side by side).

### P2 | ARC-03 | `MODEL_REGISTRY` vs `REGISTRY_FILE` variable naming inconsistency

**Files**:
- `fluxbench-challenger.sh:12` — `export MODEL_REGISTRY="..."`
- `fluxbench-qualify.sh:15` — `MODEL_REGISTRY="${MODEL_REGISTRY:-...}"`
- `fluxbench-drift.sh:22` — `registry="${MODEL_REGISTRY:-...}"` (lowercase local)
- `fluxbench-drift-sample.sh:13` — `MODEL_REGISTRY="${MODEL_REGISTRY:-...}"`
- `discover-merge.sh:8` — `REGISTRY_FILE="${MODEL_REGISTRY:-...}"` ← different name for same thing
- `validate-enforce.sh:7` — `REGISTRY="${SCRIPT_DIR}/.../model-registry.yaml"` (no env override at all!)

**Problem**: Three different names (`MODEL_REGISTRY`, `REGISTRY_FILE`, `REGISTRY`) for one concept, and `validate-enforce.sh` doesn't honor `MODEL_REGISTRY` at all — a test runner that sets `MODEL_REGISTRY=/tmp/test-reg.yaml` would get inconsistent behavior across scripts (some honor the override, some don't, enforce.sh ignores it entirely).

**Fix**: Pick `MODEL_REGISTRY` as the canonical env var name. Document in `scripts/README.md`. Update `validate-enforce.sh:7` to `REGISTRY="${MODEL_REGISTRY:-${SCRIPT_DIR}/...}"`. Alias `REGISTRY_FILE` in discover-merge.sh but read only from `MODEL_REGISTRY`.

### P2 | ARC-04 | `_infer_domains` implemented twice with drifting keyword tables

**Files**:
- `generate-agents.py:150–188` (`_infer_domains_from_spec`)
- `flux-agent.py:194–224` (`_infer_domains`)

**Problem**: Both have a `DOMAIN_KEYWORDS` / `domain_map` dict and an `esoteric_signals` list. They have **different** keys:

- `generate-agents.py` includes `wayfinding` mapping to `navigation` domain, and has a smaller esoteric list (12 entries).
- `flux-agent.py` has a larger `DOMAIN_KEYWORDS` (e.g., includes `latency`, `throughput`, `pricing`, `telemetry`, `tui`, `loop`, `sync`) and a larger esoteric list (19 entries including `perfume`, `weaving`, `pottery`, `brewing`, `typikon`, `iconographic`, `extispicy`, `hepatoscopy`).

An agent generated by `generate-agents.py` gets domains `["uncategorized"]` for names like `fd-latency-budget` because generate's map doesn't include `latency`. `flux-agent.py` then re-indexes the same file and assigns it `["performance"]`. The registry and the generated file disagree on what domain the agent covers — so triage scoring uses one answer and spec-to-agent overlap detection uses another.

**Fix**: Extract to `scripts/_domain_inference.py` (shared module). Both scripts import from it. Until consolidated, at minimum duplicate the longer list (flux-agent.py's) into generate-agents.py verbatim.

**Severity**: P2 — real divergence, but `_infer_domains` output is consumed mostly for cosmetic indexing. Promote to P1 only if triage scores are noticeably wrong.

### P2 | ARC-05 | 180-line Python scoring algorithm trapped inside shell heredoc

**File**: `fluxbench-score.sh:64–300` — entire Hungarian algorithm + severity weighting + gate evaluation in a `python3 -c "<huge heredoc>"`.

**Problem**: The most algorithmically complex code in the plugin (bipartite matching, severity ±1 accuracy, P0 auto-fail cascade) is inside a shell string. Consequences:
- **No unit test coverage is feasible** — you'd have to shell out and diff outputs.
- **No type-check pass** (mypy/pyright can't see into `python3 -c`).
- **No IDE navigation** — grep is the only way to find the algorithm.
- Escaping is fragile: the heredoc mixes `\"\"\"`, `\"`, and `f'...'` strings. A future edit that adds an unescaped backtick or `$` will break.

**Fix**: Extract to `scripts/_fluxbench_score.py` as a proper module with `if __name__ == "__main__"` CLI. The shell then becomes `python3 "$SCRIPT_DIR/_fluxbench_score.py" --qual "$qual_output" --baseline "$baseline" --output "$result_output"`. Enables pytest, type-check, and readable diffs.

### P2 | ARC-06 | flock fd 200 overloaded for two different locks

**Files**:
- `findings-helper.sh:37` — `flock -x 200` on `${findings_file}.lock`
- `fluxbench-score.sh:382` — `flock -x 200` on `${results_jsonl}.lock`
- `fluxbench-qualify.sh:138` — `flock -x 200` on `${results_jsonl}.lock`

**Problem**: fd 200 is overloaded for two unrelated lock domains (findings vs results JSONL). In isolation this is fine — each subshell opens a fresh fd 200. But if any call site ever gets nested (e.g., fluxbench-score.sh calls findings-helper.sh inside its own `(flock -x 200)` subshell), the inner flock would block forever waiting on the outer fd.

Current scripts don't nest. But the pattern is a footgun for the next reviewer.

**Fix**: Assign stable fd numbers per lock domain:
- 200 = `${results_jsonl}.lock`
- 201 = `${registry}.lock` (already consistent)
- 202 = `${sync_state_file}.lock` (already)
- **203 = `${findings_file}.lock`** (move findings-helper.sh off 200)

Document in a header comment at top of each script.

### P3 | ARC-07 | validate-*.sh scripts share 70% structural overlap

**Files**: `validate-manifest.sh`, `validate-roster.sh`, `validate-enforce.sh`, `validate-gitleaks-waivers.sh`.

All four follow the shape: find files on disk → compare to declared list → count errors → print summary → exit 0/1. Three of them use `comm -23 <(echo "$A") <(echo "$B")` for diff. There's no shared `_compare_sets()` helper.

**Fix**: Low priority — extract `scripts/lib-validate.sh` with `compare_sets()`, `report_missing_extra()`. Would shrink the four files by ~30% each. Not urgent.

## Improvements

1. **Extract `scripts/lib-registry.sh` + `scripts/lib_registry.py`** to deduplicate the 5 registry-write variants and the 8 yaml-roundtrip heredocs. Highest-leverage refactor in the plugin.
2. **Extract `scripts/_fluxbench_score.py`** as a proper module to unlock unit tests on the most complex algorithm in the codebase.
3. **Move `_infer_domains` to a shared module** to eliminate the domain-classification drift between `generate-agents.py` and `flux-agent.py`.
4. **Add a `scripts/README.md`** documenting the canonical env var names (`MODEL_REGISTRY`, `FLUXBENCH_RESULTS_JSONL`, `AGMODB_REPO_PATH`, `DRIFT_SAMPLE_COUNTER`), fd-numbering convention for flocks, and the "atomic mutate" pattern.
5. **Inline-Python heredoc audit**: 20+ sites in these scripts. Set a convention — anything >10 lines goes into a `scripts/_<name>.py` module; only tiny one-liners stay inline.
