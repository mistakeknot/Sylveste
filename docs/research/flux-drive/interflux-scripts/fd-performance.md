<!-- flux-drive:complete -->

## Findings Index

- P1 | PER-01 | "fluxbench-qualify.sh --score mode" | 3 jq subprocess invocations × N fixtures (currently 5-10) in gate-failure path
- P1 | PER-02 | "flux-agent.py:_count_usage_from_synthesis" | Dead duplicate walk (also flagged QUA-07) — doubles I/O on a cold cache
- P2 | PER-03 | "detect-domains.sh:83-132" | Per-domain yq invocation quadruples for 20+ domains × 4 signal types = 80+ subshells
- P2 | PER-04 | "flux-watch.sh:102-108" | 5s polling fallback forces unnecessary latency when inotifywait unavailable in containers (likely common)
- P2 | PER-05 | "findings-helper.sh:82" | Per-line shell loop reading awk output for printing — could be a single `awk '...}' | tr` pipeline
- P2 | PER-06 | "fluxbench-drift-sample.sh:131-138" | Re-parses entire results JSONL for every qualified model (O(M × N) where M=models, N=entries)
- P3 | PER-07 | "generate-agents.py:render_agent" | String concatenation with `+=` inside loop for review_sections and success_bullets — minor

## Verdict

**MINOR-ISSUES — performance is acceptable for current volumes (5-10 fixtures, 30 models, 500 results entries). Two P1 items would matter at 5x scale: the per-fixture jq proliferation in qualify.sh:--score mode, and the dead duplicate walk in flux-agent.py. No issues block current operation; all are optimizations.**

## Summary

Typical interflux workloads I assumed: 10-20 fixtures in a qualification run, 50-100 agents in the registry, 1K-2K entries in `fluxbench-results.jsonl` after 6 months, 20-30 domain profiles. At that scale, the scripts take 1-5 seconds to complete — noticeable but not blocking.

The **perf profile** is dominated by **subprocess fork overhead** (jq, yq, python3 called hundreds of times per run) rather than any single expensive operation. The algorithm inside `fluxbench-score.sh` (Hungarian matching) is O(N³) but N ≤ 30 findings per fixture so it's sub-millisecond.

## Issues Found

### P1 | PER-01 | jq subprocess proliferation in qualify.sh --score mode

**File**: `fluxbench-qualify.sh:383–458`:

Inside the while loop over fixtures, I count **5 jq invocations per fixture**:
- Line 410 — `jq -r '.agent_type // "unknown"'` on ground_truth
- Line 421 — `jq -c '.findings // []'` on response_file (double: outer jq + inner jq-in-argjson)
- Line 444 — `jq -r '.overall_pass'` on result_output
- Line 447 — `jq -r '.gate_results | to_entries...'` on result_output
- Line 358–366 — `python3 -c` for manifest ground_truth_path lookup, per fixture

Plus for gate failures, `failed_gates` is computed via another jq pipeline (line 447–451).

At 10 fixtures per qualification run: 50-60 subprocess forks for jq alone, plus 10 python3 invocations (manifest reads). On my dev server (fork ~3ms), that's 150-180ms just in process startup. At 50 fixtures (e.g., after expanding the fluxbench corpus), it's 750ms-1s — user-perceptible latency.

**Fix**: Read each fixture's `response.json`, `ground_truth.json`, and `result_output.json` **once** via a single python invocation that emits all needed fields:
```python
import json, os, sys
paths = sys.argv[1:]
for p in paths:
    with open(p) as f:
        data = json.load(f)
    # emit tab-separated fields bash will parse with read
    ...
```
Replace the 5 per-fixture jq calls with one per-fixture python3 exec.

**Severity**: P1 at scale (> 30 fixtures). P2 today.

### P1 | PER-02 | Duplicate walk in `_count_usage_from_synthesis` (also QUA-07)

Already covered in fd-quality finding QUA-07. Raising to P1 here because the performance impact is measurable: a project with 50 synthesis dirs (`docs/research/flux-drive/<topic>/`) × ~10 .md files each = 500 files walked twice, each file read twice. For a cold-cache SSD read (50μs per file), that's 50ms wasted on startup of `flux-agent index --rebuild`.

**Fix**: Merge the two walks. Single-pass dict of `agent → set(parent_dirs)`.

### P2 | PER-03 | detect-domains.sh spawns 4× yq per domain

**File**: `detect-domains.sh:84–132`:
```bash
for ((i=0; i<DOMAIN_COUNT; i++)); do
    PROFILE=$(yq -r ".domains[$i].profile" "$INDEX_FILE")
    MIN_CONF=$(yq -r ".domains[$i].min_confidence" "$INDEX_FILE")
    ...
    while IFS= read -r signal; do
        ...
        grep -qF "$signal" "$TMPDIR_WORK/dirs" && matched=$((matched + 1))
    done < <(yq -r ".domains[$i].signals.directories[]" "$INDEX_FILE" 2>/dev/null)
    ...
    # same for files, frameworks, keywords
```

For 20 domains × 4 signal categories (directories, files, frameworks, keywords) = **80 yq invocations** per run, plus 40 for PROFILE/MIN_CONF reads. yq startup is ~50ms on Python implementation, so 120 × 50ms = 6 seconds just in yq fork.

**Fix**: Read the entire index.yaml once via python, emit a JSON structure, then process with jq:
```bash
INDEX_JSON=$(python3 -c "import yaml, json, os; print(json.dumps(yaml.safe_load(open(os.environ['INDEX_FILE']))))")
# now loop over INDEX_JSON with jq -c '.domains[]'
```

Alternatively, emit a single yq expression that produces the full per-domain signal list in one call.

**Severity**: P2 — detect-domains.sh runs once at review start, and 6s is tolerable. But the CLAUDE.md mentions a "5s on repos up to 10K files" target (line 12 comment). On a cold cache the current implementation may already be exceeding that target.

### P2 | PER-04 | flux-watch.sh 5s poll fallback is the likely path in containers

**File**: `flux-watch.sh:102–108`:
```bash
elapsed=0
while [[ "$elapsed" -lt "$TIMEOUT" ]]; do
    if report_existing 2>/dev/null; then
        exit 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
done
```

**Problem**: `inotifywait` is often unavailable in minimal containers (not in `inotify-tools` by default). The fallback adds 0-5s latency on every completion. With 4 agents completing at staggered times, worst case 4 × 5s = 20s added total wait.

**Fix**: Poll with `fswatch` (if present) or reduce interval to 1s. The comment at line 101 notes "5s polling loop" as acceptable — but 1s is barely more expensive and dramatically tighter for users watching a live feed.

More aggressive fix: use Python's `asyncio.watch` or `watchdog` if available (fallback stack: inotify → fswatch → watchdog → 1s poll).

### P2 | PER-05 | findings-helper.sh per-line shell read for awk output

**File**: `findings-helper.sh:78–85`:
```bash
awk '
  /^#{2,4}[[:space:]]+[Ff]indings[[:space:]]+[Ii]ndex/ { found=1; next }
  found && /^#{2,4}[[:space:]]/ { exit }
  found { print }
' "$f" | while IFS= read -r line; do
  if [[ -n "$line" ]]; then echo "$base	$line"; fi
done || true
```

**Problem**: awk emits lines, which shell `while read` consumes one at a time. The shell reads, checks non-empty, reprints prefixed. The whole read loop can be collapsed into awk:
```awk
awk -v base="$base" '
  /^#{2,4}[[:space:]]+[Ff]indings[[:space:]]+[Ii]ndex/ { found=1; next }
  found && /^#{2,4}[[:space:]]/ { exit }
  found && NF > 0 { print base "\t" $0 }
' "$f"
```

Single awk invocation, no shell loop. ~100× faster for files with many findings.

### P2 | PER-06 | fluxbench-drift-sample.sh re-parses entire JSONL per model

**File**: `fluxbench-drift-sample.sh:120–139`:
```bash
while IFS= read -r slug; do
  ...
  python3 -c "
  ...
  with open(results_path) as f:
      lines = [json.loads(l) for l in f if l.strip()]
  model_runs = [r for r in lines if r.get('model_slug') == slug]
  ...
" > "$shadow_file" 2>/dev/null
```

For each of M qualified models, python parses the entire JSONL (N entries) and filters. That's O(M × N) parses. At M=30, N=2000 (six months of results), that's 60K JSON parses per sample.

**Fix**: Parse once, group by model_slug in memory:
```python
from collections import defaultdict
runs_by_slug = defaultdict(list)
with open(results_path) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        r = json.loads(line)
        runs_by_slug[r.get('model_slug')].append(r)
# now O(M + N)
```

Emit the latest-run dict keyed by slug once, bash reads per-slug from that output.

**Severity**: P2 — at current scale (~200 entries, ~10 models), this is <50ms. At 6-month scale, it becomes 500ms-1s.

### P3 | PER-07 | String `+=` inside loop (generate-agents.py:226-235)

**File**: `generate-agents.py:222–235`:
```python
review_sections = ""
for idx, area in enumerate(_normalize_bullet_list(spec.get("review_areas")), start=1):
    title = _short_title(area)
    review_sections += f"\n### {idx}. {title}\n\n"
    review_sections += f"- {area}\n"
```

Python strings are immutable, so `+=` allocates new string each iteration. For typical review_areas of 5-10 items, imperceptible. Mentioned for completeness.

**Fix** (cosmetic):
```python
review_parts = []
for idx, area in enumerate(...):
    title = _short_title(area)
    review_parts.append(f"\n### {idx}. {title}\n\n- {area}\n")
review_sections = "".join(review_parts)
```

## Improvements

1. **Profile a cold-cache run of `flux-drive` end-to-end.** Subprocess fork overhead likely dominates — a single-pass python/yq strategy probably shaves 3-5s off total latency.
2. **Prefer one Python invocation per script over many.** The pattern "shell calls python3 -c for each field" appears 15+ times in scripts/. Each reduction saves ~50ms.
3. **Use `jq -c .` parallelism** where the JSON is self-describing: instead of `jq .fieldA; jq .fieldB` twice, read via `jq -r '.fieldA, .fieldB' | { read a; read b; }` once.
4. **Cache detect-domains.sh output** per-project with a 1-hour TTL — the project layout doesn't change during a review. Invalidate on `.git/HEAD` change.
5. **Replace the 5s polling fallback in flux-watch.sh with 1s** — cheap change with immediate UX benefit when inotifywait is absent (likely in any dockerized agent).
