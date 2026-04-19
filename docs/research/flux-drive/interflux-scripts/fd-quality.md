<!-- flux-drive:complete -->

## Findings Index

- P1 | QUA-01 | "generate-agents.py + flux-agent.py" | Two near-identical `_parse_frontmatter` implementations; diverged on error behavior
- P1 | QUA-02 | "token-count.py:78" | `sys.exit(1)` on fallback path — contradicts script contract ("fallback path prints estimate + succeeds")
- P1 | QUA-03 | "All fluxbench-*.sh" | Inconsistent `set -euo pipefail` posture — some allow `|| true` pervasively, some rely on exit trap
- P2 | QUA-04 | "fluxbench-challenger.sh:240-248" | 8 consecutive `echo | jq -r '.field'` when a single `jq -r '.field1, .field2, ...'` would do
- P2 | QUA-05 | "fluxbench-drift-sample.sh:37, flux-agent.py:473" | Shell-style numeric regex validation on data that python already types — belt-and-suspenders w/o value
- P2 | QUA-06 | "generate-agents.py:478-511" | 30-line per-spec loop has 5 mutually-exclusive code paths; hard to test
- P2 | QUA-07 | "flux-agent.py:604 + line 634" | `_count_usage_from_synthesis` iterates `rglob('*.md')` twice (once for rough count, once for dir-count); one pass would suffice
- P3 | QUA-08 | "fluxbench-calibrate.sh + fluxbench-qualify.sh" | `_compute_percentile` and `compute_percentile` live in calibrate only; qualify uses jq; inconsistent statistical implementations

## Verdict

**MINOR-ISSUES — code quality is broadly good (set -euo pipefail, atomic writes, jq --arg throughout, consistent error logging to stderr) but inconsistent in places that matter: two diverging `_parse_frontmatter` implementations, contradictory exit-code contracts in token-count.py, and pervasive local-unit-style logic (e.g., Hungarian algorithm inline in shell) that can't be unit-tested.**

## Summary

Shell hygiene is good overall: every `.sh` script starts with `set -euo pipefail`, all call sites use `jq --arg` for string interpolation into JSON, and atomic tmp+rename is the norm for mutating writes. Python scripts use type hints on public functions and have docstrings. The gaps are:

1. **Duplication of small helpers** (`_parse_frontmatter`, `_atomic_write`, `compute_percentile`) that should live in a shared module.
2. **Exit code contracts** — two scripts have documented contracts that don't match implementation (token-count.py, flux-agent.py exit codes).
3. **Heredoc Python** for logic that deserves unit tests (see fd-architecture ARC-05 for the architectural angle; the quality angle is "no tests == no regression safety").
4. **Inconsistent error attitude** — some `|| true` swallows are correct progressive enhancement; others swallow errors that users need to see (see fd-correctness COR-01 and fd-safety SAF-01 for concrete cases).

## Issues Found

### P1 | QUA-01 | `_parse_frontmatter` duplicated with diverging error handling

**Files**:
- `/home/mk/projects/Sylveste/interverse/interflux/scripts/generate-agents.py:343–369` 
- `/home/mk/projects/Sylveste/interverse/interflux/scripts/flux-agent.py:102–126`

Both implement "parse YAML frontmatter from a markdown file". The bodies are nearly identical, but they diverge on:

- **ImportError handling**:
  - `generate-agents.py:348` — returns `None` silently (falls through to caller treating as "no frontmatter").
  - `flux-agent.py:107` — raises `RuntimeError("pyyaml required: pip install pyyaml")`.
  
  Result: If pyyaml is not installed, `generate-agents.py` quietly treats every agent as "not flux-gen-generated" and proceeds to regenerate everything. `flux-agent.py` fails loudly. Same root cause, two user-visible behaviors.

- **Yaml validation**:
  - `generate-agents.py:364–367` — validates `isinstance(data, dict)`.
  - `flux-agent.py:124` — same check but returns differently shaped (via conditional expression).
  
  Minor; not a bug.

- **Exception handling**:
  - `generate-agents.py:368–369` — bare `except Exception`.
  - `flux-agent.py:125–126` — same.
  
  Both catch too broadly — e.g., a `yaml.YAMLError` from a malformed frontmatter block is indistinguishable from a `FileNotFoundError`.

**Fix**: Extract to `scripts/_frontmatter.py`:
```python
def parse_frontmatter(path: Path, *, strict_yaml: bool = True) -> dict[str, Any] | None:
    """Parse YAML frontmatter. Returns None if missing; raises YAMLError on malformed if strict."""
    ...
```
Both scripts import from `_frontmatter`. Sharpens error semantics and eliminates the drift.

**Severity**: P1 — the ImportError divergence has real user impact (silent vs loud), and the code has already drifted.

### P1 | QUA-02 | `token-count.py:78` fallback path exits 1 despite printing valid output

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/token-count.py`

**Lines 74–82**:
```python
try:
    result = sum_usage(jsonl_path)
    json.dump(result, sys.stdout)
    print()
except (OSError, json.JSONDecodeError, KeyError) as e:
    result = fallback(fallback_file)
    json.dump(result, sys.stdout)
    print()
    sys.exit(1)
```

**Contract mismatch**: The docstring says:
```
Falls back to chars/4 estimate if JSONL unavailable or unparseable.
```

Users reading the docstring expect "fallback == successful alternate path, script exits 0." The implementation exits 1 on fallback. Callers using `result=$(token-count.py ... || echo '{}')` currently get empty JSON because the `||` fires — the **fallback JSON gets thrown away**.

The actual caller in `lib-sprint.sh` (not in scope) uses the output as-is without checking exit code, so it receives the fallback JSON correctly — but any future caller that checks exit code will silently drop the fallback.

**Fix**: Either update the docstring to say "exits 1 on fallback to signal downstream that the estimate is approximate" (existing behavior) OR exit 0 on fallback and include `"estimated": true` in the JSON (already present at line 56) to signal approximation. Latter is cleaner — the `"estimated": true` field is the contract, not the exit code.

**Severity**: P1 — contradicts documented behavior; a future caller WILL get burned.

### P1 | QUA-03 | Inconsistent `set -euo pipefail` posture across scripts

**Files**: all `.sh` in scripts/.

All start with `set -euo pipefail`. Good. But the **posture** varies:

- `fluxbench-sync.sh` — takes `pipefail` seriously, fails closed on every parse.
- `fluxbench-qualify.sh` — mixes strict failure with `|| true` as a catch-all (e.g., line 366, 499). The `|| true` at `500` silently masks registry-write failures **after** the flock is released, so the "if registry write failed" branch doesn't fire the way it reads.
- `discover-models.sh` — uses `|| shift` at line 24 (weird `shift` in an error case — probably typo for `|| { shift; continue; }` or similar).
- `detect-domains.sh:126` — `echo "scale=2; ..." | bc 2>/dev/null || awk ...` — correct fallback pattern.
- `fluxbench-challenger.sh:208` — `2>&1` captures stderr into the value, so any stderr from python3 becomes part of the "result" string. If python3 emits a deprecation warning, `jq -r '.selected // empty'` at line 210 fails because `result` starts with `DeprecationWarning:` instead of JSON. The `// empty` gives up, script proceeds with "no candidate" — **silent wrong output**.

**Fix**: Strip `2>&1` where stderr is not intended to be consumed as part of the value:
```bash
  result=$(python3 -c "..." 2>/tmp/python-stderr-$$) || {
    echo "Error in challenger select: $(cat /tmp/python-stderr-$$)" >&2
    rm -f /tmp/python-stderr-$$
    return 1
  }
  rm -f /tmp/python-stderr-$$
```

More generally: audit each `|| true` and `2>&1 $(...)` — distinguish "progressive enhancement" from "silent wrong output" (see fd-correctness Phase 1 work for the full list).

### P2 | QUA-04 | 8 consecutive `echo | jq -r '.field'` calls where 1 would do

**File**: `fluxbench-challenger.sh:235–248`:
```bash
avg_score=$(echo "$result" | jq -r '.avg_score')
candidates_evaluated=$(echo "$result" | jq -r '.candidates_evaluated')
provider=$(echo "$result" | jq -r '.provider')
prompt_content_policy=$(echo "$result" | jq -r '.prompt_content_policy')
eligible_tiers=$(echo "$result" | jq -c '.eligible_tiers')
```

8 separate jq invocations. Each forks jq, parses the same JSON, extracts one field.

**Fix**:
```bash
{
  read -r avg_score
  read -r candidates_evaluated
  read -r provider
  read -r prompt_content_policy
  read -r eligible_tiers
} < <(echo "$result" | jq -r '.avg_score, .candidates_evaluated, .provider, .prompt_content_policy, (.eligible_tiers | tojson)')
```
One jq invocation. Minor perf win, more importantly: one parse point, no possibility of the JSON changing between reads (not a concern here since `$result` is a string, but for file reads it matters).

Apply the same pattern to fluxbench-qualify.sh:444–464 (5 jq calls in a loop, worst case 5 × N_fixtures invocations).

### P2 | QUA-05 | Shell regex validation on data Python has already typed

**Files**:
- `fluxbench-drift-sample.sh:37` — `if [[ "$val" =~ ^[0-9]+$ ]]` on a counter-file value
- `flux-agent.py:473` — uses `isinstance(lines, list)` on domain data

The drift-sample.sh regex is belt-and-suspenders around a counter that `_write_counter` always writes as an integer. The guard exists for the "user edited the counter file by hand" case. Fine.

But the pattern is duplicated: 4 other sites have `[[ "$x" =~ ^[0-9]+$ ]]` for similar "validate numeric after read" cases. Consolidate into `_read_int_file()` helper.

**Severity**: P2 — style, not behavior.

### P2 | QUA-06 | 30-line per-spec loop has 5 branches (generate-agents.py:478–511)

**File**: `generate-agents.py:478–511`:

```python
for spec in specs:
    name = spec.get("name", "")
    if not name.startswith("fd-"):
        report["errors"].append(...); continue
    if name in CORE_AGENTS:
        report["errors"].append(...); continue
    if name in existing:
        if mode == "skip-existing":
            report["skipped"].append(name); continue
        elif mode == "regenerate-stale":
            existing_version = existing[name].get("flux_gen_version", 0)
            if isinstance(existing_version, int) and existing_version >= FLUX_GEN_VERSION:
                report["skipped"].append(name); continue
    spec_domains = _infer_domains_from_spec(spec)
    overlapping = set()
    for d in spec_domains:
        if d != "uncategorized":
            overlapping.update(_domain_agents.get(d, []))
    if overlapping:
        ...
    content = render_agent(spec, source_spec_file=specs_file_name)
    if not dry_run:
        target = agents_dir / f"{name}.md"
        _atomic_write(target, content)
    report["generated"].append(name)
```

**Problem**: Five branches (invalid-prefix, core-collision, skip-existing, regenerate-stale, happy path) in one loop. Adding a sixth (e.g., "force" mode) requires editing in the middle of a long block.

**Fix**: Early-return pattern — extract decision logic:
```python
def classify_spec(spec, existing, mode) -> tuple[str, str | None]:
    """Returns (decision, reason) where decision in {'skip', 'error', 'generate'}."""
    name = spec.get("name", "")
    if not name.startswith("fd-"):
        return ("error", f"name must start with 'fd-': {name!r}")
    if name in CORE_AGENTS:
        return ("error", f"conflicts with core agent")
    if name in existing:
        if mode == "skip-existing":
            return ("skip", "already exists")
        if mode == "regenerate-stale":
            existing_version = existing[name].get("flux_gen_version", 0)
            if isinstance(existing_version, int) and existing_version >= FLUX_GEN_VERSION:
                return ("skip", "already at current version")
    return ("generate", None)

for spec in specs:
    decision, reason = classify_spec(spec, existing, mode)
    if decision == "error":
        report["errors"].append(f"Skipping: {reason}"); continue
    if decision == "skip":
        report["skipped"].append(spec["name"]); continue
    # generate
    ...
```

Unit-testable classifier. Easier to add force mode.

### P2 | QUA-07 | `_count_usage_from_synthesis` double-walks the flux-drive directory

**File**: `flux-agent.py:634–662`:
```python
def _count_usage_from_synthesis(project: Path) -> dict[str, int]:
    flux_dir = project / "docs" / "research" / "flux-drive"
    counts: dict[str, int] = Counter()
    if not flux_dir.is_dir():
        return counts
    for md in flux_dir.rglob("*.md"):       # <-- first walk
        ...
        for match in re.findall(r"\bfd-[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\b", text):
            counts[match] += 1
    # Normalize: count unique synthesis dirs, not raw mention count
    dir_counts: dict[str, set[str]] = defaultdict(set)
    for md in flux_dir.rglob("*.md"):       # <-- second walk
        ...
```

**Problem**: Walks `flux-drive/**/*.md` **twice** and uses the first result's `counts` dict for **nothing** (it's overwritten by dir_counts-derived result at line 662). Dead computation.

**Fix**: Delete lines 640–648 entirely. Keep only the dir-count walk.

### P3 | QUA-08 | Statistical computation inconsistent: Python in one script, jq in another

**Files**:
- `fluxbench-calibrate.sh:50–72` (`compute_percentile`) — Python interpolation-based percentile (p25, p75).
- `fluxbench-qualify.sh:_compute_avg_metrics:86–104` — Python average.
- `fluxbench-score.sh:118–187` — Python Hungarian algorithm.
- `discourse-health.sh:44–87` — jq's built-in sort + index math for Gini coefficient.

Four different statistical computations in four different styles. The Gini implementation at discourse-health.sh:52–61 is particularly dense — it would benefit from a comment citing the formula (it's the standard Gini, but the "2*weighted - (n+1)*total / (n*total)" form isn't immediately obvious).

**Fix**: Not urgent. When someone adds a 5th statistic, consolidate into `scripts/_stats.py`.

## Improvements

1. **Extract `scripts/_frontmatter.py`** to eliminate the `_parse_frontmatter` drift — the single most impactful quality refactor.
2. **Fix `token-count.py` exit contract** — either docstring or implementation; pick one and make them agree.
3. **Audit `2>&1 $(...)` patterns** — fluxbench-challenger.sh:208 is the known case; grep for others.
4. **Add pyproject.toml mypy config** — with type hints already present on most public functions, adding `mypy --strict` would catch the `isinstance(existing_version, int)` and other class-drift bugs (see Phase 1 type-design findings for context).
5. **Run shellcheck in CI** — `shellcheck -s bash scripts/*.sh` would catch 3–4 of the findings above automatically, plus the `|| true` posture audit becomes mechanical.
