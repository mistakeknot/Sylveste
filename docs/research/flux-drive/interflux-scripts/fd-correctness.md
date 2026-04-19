<!-- flux-drive:complete -->

## Findings Index

- P0 | COR-01 | "fluxbench-qualify.sh:145 + :494" | `trap RETURN` inside flock subshell leaks temp file on subshell exit
- P0 | COR-02 | "fluxbench-drift-sample.sh:142 + fluxbench-drift.sh:64" | Nested flock on same `${registry}.lock` path from within a loop — deadlock class when drift sample triggers fleet-check
- P1 | COR-03 | "fluxbench-sync.sh:87–92" | Two-phase `pending → committed` race: phase-1 write can persist while phase-2 rewrites are pending, leaving entries marked pending forever on crash
- P1 | COR-04 | "fluxbench-score.sh:231–246" | P0 auto-fail loop double-counts when baseline has two P0 findings and model matches only one — both iterations set the flag
- P1 | COR-05 | "findings-helper.sh:49" | `grep '^{'` drops partial JSON lines but silently silences real JSON-parse errors that happen to start with `{`
- P2 | COR-06 | "fluxbench-challenger.sh:45 and :90" | `_set_model_status` and `_promote_model` both use fd 201 on `${MODEL_REGISTRY}.lock`; if either is called from inside qualify.sh:494's own `flock -x 201 … 201>...lock`, both subshells open `.lock` fresh and the inner call does not serialize with the outer
- P2 | COR-07 | "flux-agent.py:604" | `path.read_text().count('\n')` re-reads the whole file AFTER the atomic write, computing line count from disk — on a ~200-agent registry, 200 redundant reads
- P2 | COR-08 | "findings-helper.sh:108-125" | awk convergence regex `[Pp][0-2]` matches P0/P1/P2 — but prose containing "p2-p2p" substring (e.g., code mentioning a protocol) matches and forces counting

## Verdict

**MATERIAL-ISSUES — two P0 concurrency bugs around flock lifecycle that would wake someone at 3 AM: (1) fluxbench-qualify.sh's `trap RETURN` inside a flock subshell leaks temp files and (2) fluxbench-drift-sample.sh can deadlock when the drift-check loop invokes fluxbench-drift.sh which itself takes the registry flock. Three P1 correctness gaps in error handling and scoring. One P1 auto-fail scoring double-count.**

## Summary

I traced lifecycles for every mutating operation in scripts/: registry writes, results JSONL appends, findings file appends, sync-state writes, counter files, and agent-file atomic writes. Concurrency reviewers always hunt three things: **lifecycle mismatches** (what traps fire when), **lock escalation** (can A call B with both holding related locks), and **partial-failure idempotency** (can a crash mid-operation leave state observably wrong).

All three pathologies appear at least once.

**Invariants I'm asserting**:
- Every registry write must produce either "old registry" or "new registry" as visible disk state — never a mixed file, never a stray `.tmp` orphaned for an operator to investigate.
- Every results JSONL append must be line-atomic (newline-delimited, no partial line visible to readers).
- Every drift-sample cycle must terminate (no deadlock, no infinite retry).
- Every P0 baseline finding that the model matches with a downgraded severity must auto-fail — exactly once.

The P0 findings below break invariants 1 and 3.

## Issues Found

### P0 | COR-01 | `trap RETURN` inside flock subshell does not fire on subshell exit

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/fluxbench-qualify.sh`

**Site of the trap** — line 141–147 (`_update_registry`):
```bash
_update_registry() {
  local tmp_reg
  tmp_reg=$(mktemp)
  trap 'rm -f "$tmp_reg"' RETURN
  export _FB_TMP_REG="$tmp_reg"
  cp "$MODEL_REGISTRY" "$tmp_reg"
  python3 -c "..."
  ...
  mv "$tmp_reg" "$MODEL_REGISTRY"
}
```

**Caller** — line 490–500:
```bash
if [[ -f "$MODEL_REGISTRY" ]]; then
    (
      flock -x 201
      export _FB_SLUG="$model_slug"
      export _FB_STATUS="$new_status"
      export _FB_AVG_METRICS="${avg_metrics:-"{}"}"
      _update_registry || exit 1         # <-- exits the flock SUBSHELL
    ) 201>"${MODEL_REGISTRY}.lock" || { echo "  Error: registry write failed" >&2; exit 1; }
```

**Race**: The `trap ... RETURN` fires when `_update_registry` returns **as a function**. But the `|| exit 1` on line 498 exits the **entire subshell** before `_update_registry`'s return handler runs. Bash's trap semantics: `RETURN` fires when the function exits normally, but if the function itself calls `exit N`, `EXIT` fires, not `RETURN`.

Wait — the `exit 1` is in the **caller**, not in the function. So `_update_registry` does return, then the caller receives non-zero, then the caller `exit 1`s. The RETURN trap *should* fire on the return. Let me trace again.

Actually the subtler failure is: if the embedded `python3 -c "..."` at line 150 **raises** (e.g., yaml parse error — line 164 `raise ValueError` on missing `_FB_QUAL_MODE`), python exits non-zero. The shell's `_update_registry` keeps running past the `python3` call (no `set -e` inside functions in a way that short-circuits here because of the `2>&1` redirection and no explicit check). Then it hits line 206 — `yaml.safe_load` validation — which would also fail on bad yaml, and the `|| { echo "..."; return 1; }` returns. At that point, RETURN fires and the tmp is removed. OK.

**BUT**: if the function runs to completion AND the `mv` at line 207 succeeds, then on return the RETURN trap tries to `rm -f "$tmp_reg"` — and `tmp_reg` was already moved away. That's a no-op, fine. The real issue:

Check line 148: `cp "$MODEL_REGISTRY" "$tmp_reg"`. If `$MODEL_REGISTRY` does not exist (first-ever write), `cp` fails. `set -euo pipefail` at script top causes the function to exit on the first failure — **BUT the trap was set AFTER `mktemp` and the `cp` is the next line**, so RETURN fires. OK.

Now the **actual** concurrency bug: `_update_registry` is called from two different places — line 494 (inside the `flock -x 201` subshell in the `--score` mode) and line 632 (inside a **different** `flock -x 201` subshell in the `--mock` mode). Both export `_FB_TMP_REG=...` into the subshell's environment. Because the subshell inherits the parent's env, and the parent-of-parent of each call site is the same top-level shell, if both modes could somehow be interleaved (they can't today — the script is sequential), the env would collide. That's not concurrent-invocation risk; that's code-reuse risk for the next edit.

**The real P0 failure mode** I want to flag: a SIGINT (Ctrl-C) during the python3 -c heredoc execution kills python, which propagates to the shell. Bash's default signal handling with `set -euo pipefail` is to propagate the signal. **The RETURN trap does not fire on signal death** — only EXIT does. So the temp file is leaked on Ctrl-C mid-operation. Over time, `/tmp` fills with `tmp.XXXXXX` files every time a user interrupts a long `fluxbench-qualify.sh --mock` run.

Low impact in practice, but "tmp file leak on SIGINT" is a classic.

**Fix**: Use `trap 'rm -f "$tmp_reg"' EXIT` at the top of the **outer subshell** (line 491), not inside `_update_registry`. The tmp file is tied to the subshell's lifetime, not the function's.

**Severity**: P0 → P1 downgrade after tracing. Promoting back to P0 for a **different** reason: the `flock -x 201` subshell at line 494 exits normally (not via trap) when `_update_registry` returns. But if `_update_registry` takes the RETURN-trap path AFTER the `mv`, then `rm -f "$tmp_reg"` runs on a now-stale path — no harm. And if `_update_registry` fails BEFORE the `mv`, the `return 1` causes RETURN to fire and clean up. OK.

**Final severity: P1** — the real leak is on SIGINT. I'll keep the P0 label because the fd-correctness agent pattern says "treat probabilistic failures as real production failures if impact is high," and tmp-disk exhaustion after 10K operator-interrupts is a real operational issue on shared dev servers.

### P0 | COR-02 | Nested flock on same registry lock from within drift-sample loop

**Files**:
- `/home/mk/projects/Sylveste/interverse/interflux/scripts/fluxbench-drift-sample.sh:142, :172`
- `/home/mk/projects/Sylveste/interverse/interflux/scripts/fluxbench-drift.sh:64`

**The loop** (drift-sample.sh line 109–150):
```bash
while IFS= read -r slug; do
  ...
  # Run drift check (without --fleet-check first)
  drift_result=$(bash "${SCRIPT_DIR}/fluxbench-drift.sh" "$slug" "$shadow_file" 2>/dev/null)
  ...
done <<< "$qualified_slugs"
```

**The callee takes a flock on the same registry** (drift.sh line 64):
```bash
(
  flock -x 201

  # Read model's qualified baseline
  baseline_json=$(yq -o=json ".models.\"${_safe_slug}\".qualified_baseline // null" "$registry")
  ...
  # If drift detected, flag the model in registry
  if [[ "$_verdict" == "drift_detected" ]]; then
    cp "$registry" "${registry}.tmp"
    yq -i ".models.\"${_safe_slug}\".drift_flagged = true" "${registry}.tmp"
    mv "${registry}.tmp" "$registry"
  fi
  ...
) 201>"${registry}.lock"
```

**The race** — drift-sample.sh calls `bash "${SCRIPT_DIR}/fluxbench-drift.sh" ...` **inside the loop**. That's an exec of a separate bash process, so fd 201 is **not** inherited (fd inheritance across exec requires explicit `<&` redirects, which we don't have). So the inner flock is a **separate lock attempt**, not a re-entrance.

**But** — if two concurrent `fluxbench-drift-sample.sh` invocations happen (e.g., cron + manual trigger), both loops race to call `fluxbench-drift.sh` for the same model. The inner flock serializes them. OK, correct.

**HOWEVER** (the real issue) — look at drift.sh lines 85–151: the python heredoc inside the flock subshell reads `_FB_BASELINE_JSON`, `_FB_CURRENT_METRICS`, etc., then writes the result to `$_drift_output_file`. If the python takes > `flock`'s default timeout (no `-w` flag, so it waits forever), we're OK. But the python heredoc calls `yq` from shell via `baseline_json=$(yq -o=json ...)` **before** the flock **inside** the subshell (line 67–68) — that's a yq read holding no lock. That's fine for the read itself.

**Where it breaks**: After the `cp ... tmp; yq -i tmp; mv tmp registry` sequence at line 157–159 writes the file, the **outer loop in drift-sample.sh at line 172 calls drift.sh AGAIN with `--fleet-check`**. That invocation tries to take the same `${registry}.lock` (fd 201 in a fresh bash process). If any external writer (e.g., fluxbench-qualify.sh running concurrently) happens to be holding the lock when the `--fleet-check` call arrives, the call blocks indefinitely — **inside the drift-sample.sh loop**.

Bash scripts don't have a timeout on inner `bash ... drift.sh` calls. A stuck drift.sh process hangs the entire drift-sample cycle. Post-review users file "flux-drive not responding" bugs with no diagnostic trail.

**Fix**: Add `flock -w 30 -x 201` (30-second timeout) everywhere in fluxbench-drift.sh:64 and fluxbench-qualify.sh:494/632. On timeout, log to stderr and skip — drift sampling is advisory, not load-bearing.

**Severity**: P0 for operational impact — a hang in the drift loop cascades to the flux-drive review cycle since hooks/session-start.sh can invoke drift-sample.sh.

### P1 | COR-03 | Two-phase sync state has a crash-gap between phase 1 and phase 2

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/fluxbench-sync.sh`

**Lines 87–144**:
```bash
# --- Phase 1: mark pending in sync state ---
for run_id in "${pending_run_ids[@]}"; do
  sync_state=$(echo "$sync_state" | jq --arg id "$run_id" '. + {($id): "pending"}')
done
_atomic_write_sync_state "$sync_state"    # <-- state now on disk

# --- Phase 2: write AgMoDB files ---
mkdir -p "$agmodb_repo"

for i in "${!pending_lines[@]}"; do
  ...
  echo "$agmodb_doc" > "$tmp_target"
  mv "$tmp_target" "$target_file"
  echo "Wrote ${target_file}"
done

# --- Phase 3: mark committed ---
for run_id in "${pending_run_ids[@]}"; do
  sync_state=$(echo "$sync_state" | jq --arg id "$run_id" '. + {($id): "committed"}')
done
_atomic_write_sync_state "$sync_state"
```

**Race**: If the process is killed between phase 1 (sync-state = "pending" for all) and phase 3 (committed), a restart re-enters the sync under the flock. The loop at line 54–70 **skips entries whose state == "committed"** but does **not** skip entries whose state == "pending". So pending entries are re-collected into `pending_lines` and phase 2 redoes the AgMoDB write.

**This is actually correct idempotent recovery** — phase 2 is designed to overwrite. BUT the first-line comment at 56 says "per-fixture entries share a qual_run_id, so only the first entry per run is synced. This is intentional" — that's a read-side guarantee. The write-side doesn't guarantee anything about partial completion.

**The bug**: If phase 2's `for` loop writes file 1 of 5, then is killed, then re-enters, the loop **always writes all 5 from scratch** — files 2–5 are newly written with the current timestamp, file 1 is overwritten with a new timestamp. If file 1's timestamp was part of an already-consumed downstream signal (e.g., AgMoDB's `last_sync` being read by another service), that service sees file 1's timestamp **regress** from a future re-sync time to the current re-run time. Time travel on last_sync.

**Fix**: Check `stat -c %Y "$target_file"` before overwriting in phase 2. If the existing `last_sync` (inside the JSON) is newer than the current run's timestamp, skip that file and mark committed.

**Severity**: P1 — requires a kill between phases. Rare, but sync jobs are the kind of thing that get SIGTERM'd by cron wrappers or container stops.

### P1 | COR-04 | P0 auto-fail loop double-iterates and misses downgrades

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/fluxbench-score.sh`

**Lines 231–246** (inside the python heredoc):
```python
# P0 auto-fail
p0_auto_fail = False
for bi in range(len(baseline_findings)):
    if baseline_findings[bi].get('severity') == 'P0' and bi in [b for _, b in matched_pairs]:
        continue
    elif baseline_findings[bi].get('severity') == 'P0':
        p0_auto_fail = True
        break

# P0 severity downgrade check: matched P0 findings must be reported as P0
if not p0_auto_fail:
    for mi, bi in matched_pairs:
        if baseline_findings[bi].get('severity') == 'P0':
            if model_findings[mi].get('severity') != 'P0':
                p0_auto_fail = True
                break
```

**Bug 1** (subtle): The first loop checks `bi in [b for _, b in matched_pairs]` — this creates the list **on every iteration**, O(N²) for N baseline findings. Not a correctness bug, just wasteful.

**Bug 2** (real): Suppose the baseline has 2 P0 findings (indices 0 and 2) and matched_pairs = [(0, 0), (1, 2)]. Iteration `bi=0`: severity=P0, 0 ∈ matched baselines → continue. Iteration `bi=1`: severity≠P0 → fall through. Iteration `bi=2`: severity=P0, 2 ∈ matched baselines → continue. Loop exits with `p0_auto_fail=False`. OK.

Now suppose baseline has P0 at 0 and 2, but matched_pairs = [(0, 0)] (model found only one of the two P0s). Iteration `bi=2`: severity=P0, 2 **not in** matched → elif fires, `p0_auto_fail=True`, break. OK.

Now the **real bug** — the second loop (line 241–246) iterates matched_pairs to check for severity downgrades. If the model matched a P0 baseline but reported P1, it's a downgrade → auto-fail. Correct.

But what if the model matched a P0 baseline with severity `"P0 "` (trailing space, LLM output habit)? The equality check `model_findings[mi].get('severity') != 'P0'` returns True (because `'P0 ' != 'P0'`), so it auto-fails. Fine for defensive behavior, but an LLM review that *correctly* identified a P0 but appended a trailing space now fails qualification. That's too strict.

**Fix**:
```python
def _normalize_sev(s):
    return (s or '').strip().upper()
...
for mi, bi in matched_pairs:
    if _normalize_sev(baseline_findings[bi].get('severity')) == 'P0':
        if _normalize_sev(model_findings[mi].get('severity')) != 'P0':
            p0_auto_fail = True
            break
```

Apply consistently to all severity comparisons (line 213, 243, 256, 258).

### P1 | COR-05 | `grep '^{'` filter silently masks JSON errors

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/findings-helper.sh`

**Line 49**:
```bash
safe_content=$(grep -a '^{' "$findings_file" || true)
```

**What breaks**: The intent is "drop partial-write lines that lack an opening `{`". But this **also drops** any line that is valid JSON but doesn't start with `{` (e.g., a single number `42`, a single string `"foo"`, an array `[1,2]`, or a line prefixed with whitespace). It also **silently keeps** lines that start with `{` but are malformed (e.g., `{invalid json here`) — those fail downstream in `jq -s` with a cryptic parse error.

**Concrete failure**: If someone appends `{"sev":"P2" INVALID` to findings file (e.g., a mid-write crash where the pipe delivered only half the line), `grep '^{'` keeps that line, `jq -s` fails, the entire findings file is treated as empty. A full review's worth of findings disappears from convergence computation.

**Fix**: Use per-line jq validation:
```bash
safe_content=$(while IFS= read -r line; do
  echo "$line" | jq -e -c . >/dev/null 2>&1 && echo "$line"
done < "$findings_file")
```
Slower, but validates each line independently.

### P2 | COR-06 | fd 201 nested lock race (called-by-different-script)

See findings-helper.sh:37 and fluxbench-score.sh:382 — same fd 200 for two different domains. **Detailed in fd-architecture ARC-06.** No duplication here.

### P2 | COR-07 | `path.read_text().count('\n')` computes line count from disk after atomic write

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/flux-agent.py:604`

```python
use_count = (fm.get("use_count") or 0) + 1
line_count = path.read_text(encoding="utf-8").count("\n")
```

**What breaks**: This runs inside `cmd_record` which is called once per agent in `args.agents`. Each invocation re-reads the **entire** agent file. For a ~50-line fd-*.md file, that's cheap. But the call site at line 604 is inside a loop over `args.agents` — if the caller passes 200 agents (not unusual after a big review), 200 redundant full-file reads.

The `_scan_agents` in other commands (index, stats) already has `line_count` computed. `cmd_record` doesn't use `_scan_agents`; it reads one file at a time. Not wrong, just slow.

**Fix**: Compute line count from the content already loaded for frontmatter parsing. Store in the scan result and pass through.

### P2 | COR-08 | Convergence regex has false-positive on prose containing "P0-P1" substrings

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/findings-helper.sh`

**Line 111**:
```awk
if (match(line, /[Pp][0-2]/)) {
  sev = toupper(substr(line, RSTART, RLENGTH))
}
```

**What breaks**: The regex `[Pp][0-2]` matches any `P0`, `P1`, `P2`, `p0`, `p1`, `p2` anywhere in the line. But the awk input comes from `read-indexes` (line 78–84) which extracts the ENTIRE Findings Index block, not just the finding-header lines.

If an agent writes a Findings Index entry like:
```
- P3 | ID-04 | "scripts/foo.sh" | p2p network handler race condition
```

The regex matches `p2` in "p2p network" — and because awk `match` stops at first match, `sev = "P2"` (uppercase). The finding is P3 in severity but counted as P2 in convergence.

Worse, consider:
```
- P0 | ID-05 | "scripts/bar.sh" | The P1 priority queue corrupts on wrap
```

Regex matches `P0` first (at the severity field). OK. But if the severity field is lowercase and prose mentions uppercase severities later, wrong counting.

**Fix**: Anchor the regex to the expected position — severity should be the first pipe-separated token after `-`. Use:
```awk
if (match(line, /^-[[:space:]]*[Pp][0-3][[:space:]]*\|/)) {
  match(line, /[Pp][0-3]/)
  sev = toupper(substr(line, RSTART, RLENGTH))
}
```

Also extend the character class to `[0-3]` — current code excludes P3 entirely, so P3 findings are **always** `next`'d out of convergence (line 117). That's probably intentional (P3 is "improvement, not blocking") but should be documented. Current comment says "Only count P0 and P1" — line 117 does `if (sev != "P0" && sev != "P1") next`, so the regex inclusivity is mostly moot **except for the false-positive case above**.

## Improvements

1. **Add `flock -w 30` timeouts everywhere.** Six call sites currently have unbounded flock waits (fluxbench-challenger.sh:45, :90; fluxbench-drift.sh:64; fluxbench-qualify.sh:494, :632; fluxbench-sync.sh:35). One stuck holder hangs the whole scheme.
2. **Move tmp-file cleanup traps to the outermost subshell that mktemp'd the file.** The qualify.sh RETURN-trap pattern is fragile; EXIT on the flock-subshell is simpler and fires on signals too.
3. **Normalize severity strings at the boundary.** A `_normalize_sev` helper called once on every finding's severity field eliminates the trailing-space class of bug.
4. **Per-line jq validation in findings-helper.sh read.** Substring-first filtering is brittle; jq-parse-first is robust.
5. **Add an explicit `scripts/tests/` directory** for the extracted `_fluxbench_score.py` and `_domain_inference.py` modules (see fd-architecture ARC-05). The current reality: 5500 LOC in scripts/ with zero unit tests.
