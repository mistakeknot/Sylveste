---
artifact_type: reflection
bead: sylveste-1n8u
stage: reflect
category: correctness
tags: [fluxbench, bash, concurrency, injection, testing]
---
# FluxBench Review Hardening — Sprint Reflection

## What happened

Retroactive sprint on the FluxBench closed-loop model discovery system (scoring engine, qualification pipeline, drift detection, challenger lifecycle). Code was already implemented in prior sessions. This sprint ran the full review/fix/verify cycle on the existing implementation.

## Key findings and fixes

### Atomic writes are not optional for YAML registries
The `model-registry.yaml` is the single source of truth for model state. Three scripts (challenger, drift, sync) had non-atomic writes — direct `yaml.dump(open(path, 'w'))` or `echo > file` without tmp+validate+mv. A SIGKILL during write permanently corrupts the registry. The fix applied the same pattern already used in `qualify.sh`: `cp → modify tmp → validate → mv`, all under flock. **Lesson:** when a file is written by multiple scripts, the atomic write pattern must be enforced in every writer, not just the first one implemented.

### String interpolation into `python3 -c` is the Bash equivalent of SQL injection
Four `_gate_pass` calls passed shell variables directly into Python source: `python3 -c "print('true' if float('$value') >= float('$threshold') else 'false')"`. A crafted `format_compliance_rate` in qualification output could execute arbitrary code. The fix moved all gate evaluation into the existing Python block, reading values from environment variables. **Lesson:** the project's own MEMORY.md rule ("pass data to inline Python via env vars, never interpolation") was already established — the FluxBench code predated that rule and was never retrofitted.

### Greedy bipartite matching produces false negatives on P0 detection
The finding matching algorithm used greedy sort-by-score assignment. When two model findings match two baseline P0 findings with similar scores, the greedy order can misassign, leaving a P0 unmatched and triggering a false `p0_auto_fail`. Replaced with a pure-Python Hungarian algorithm (no scipy dependency). Also added a P0 severity downgrade check — a model that finds a P0 but reports it as P1 now correctly fails.

### TOCTOU in registry reads requires a single flock scope
`drift.sh` read the baseline and `drift_flagged` state outside the flock, then wrote inside it. A concurrent writer could change the registry between read and write. The fix wraps all reads and writes in a single `flock -x 201` block. The flock-inside-`$()` pattern doesn't work (fd not inherited) — use a temp file to capture output from the subshell.

### flock fd 201 inside `$()` subshell fails with "Bad file descriptor"
`result=$( flock -x 201; ... ) 201>"file.lock"` does not work because `$()` opens a fresh subshell where fd 201 from the outer redirect isn't accessible. The fix: use `( flock -x 201; ...; echo > tmpfile ) 201>"file.lock"` and read the tmpfile after.

## Process learnings

- **Retroactive reviews catch real bugs.** The 4-agent parallel review found 5 P0s and 9 P1s in code that passed all tests. Tests verify behavior but not concurrency safety, injection resistance, or crash recovery.
- **Quality gates on the fixes themselves caught a P0 regression** (double-prefixed `qualification_run_id`) that the fix agents introduced. Two-pass review is worth it for >500-line diffs.
- **Test fixtures must produce compact JSONL** (`jq -cn` not `jq -n`). Multi-line JSON objects break line-by-line JSONL parsing.
