---
date: 2026-04-19
session: ql9.a-repair-complete
topic: Mac repo repair after autosync contamination — ql9.a done, ql9.b pending
beads: [Sylveste-ql9]
---

## Session Handoff — 2026-04-19 ql9.a complete, ql9.b pending

### Status

- **ql9.a (repair 110 contaminated Mac child indexes)**: ✅ COMPLETE. 110 → 0 contaminated. All 113 child repos clean.
- **ql9.b (structural autosync fix before re-enabling)**: ⛔ STILL OPEN. Autosync remains disabled (`/Users/sma/projects/Sylveste/.git-autosync.disabled`). Do not re-enable until ql9.b lands.

### Directive (next session)

> Land ql9.b: structurally fix `~/.claude/hooks/git-autosync.sh` so it cannot recontaminate child repos when re-enabled. Two failure mechanisms must be addressed (see Root Cause). Then verify on a single test repo, re-enable autosync by renaming `.git-autosync.disabled` → `.git-autosync`, and monitor.

### Root Cause (revised — deeper than original ql9 hypothesis)

The phantom `fatal: unable to read <SHA>` errors come from TWO compounding mechanisms, not just one:

1. **Autosync recurses into child repos.** The umbrella `.gitignore` excludes `apps/`, `os/`, `core/`, `interverse/`, `sdk/*` — but not `research/`, `masaq`, `docs/`, etc. Each `git add -A` walks into uncovered child working trees and stages their files at the umbrella level.

2. **Claude Code sets `GIT_INDEX_FILE=<umbrella>/.git/index-<session-uuid>` on every shell.** The autosync hook inherits this env var. So `git add -A` writes those staged blob refs into the *per-session umbrella index*, NOT the umbrella's real `.git/index`. The blob SHAs are fresh hashes of working-tree content that was *never written to any object store*. Subsequent operations in child repos inherit the same env var → child `git status` reads the umbrella's per-session index, sees a phantom blob ref, and fatals.

This is why the first repair attempt this session also failed: my `git read-tree HEAD` calls were writing into the umbrella's per-session index, not the child's local `.git/index`. The fix was to prefix every git op with `env -u GIT_INDEX_FILE`.

### Repair recipe used (for reference)

```bash
# Inventory (correct — clears the inherited env var):
bash /tmp/inventory_contam_v2.sh

# Per-repo repair:
env -u GIT_INDEX_FILE git -C "$repo" cat-file -t HEAD >/dev/null  # safety check
rm -f "$repo/.git/index"
env -u GIT_INDEX_FILE git -C "$repo" read-tree HEAD
```

Ran via `xargs -P 8` across all 110 repos in `/tmp/mac_no_index.txt`. 110/110 OK in one pass.

### ql9.b options (pick one before re-enabling)

- **(a) Defensive hook prefix.** Edit `~/.claude/hooks/git-autosync.sh` to start with `unset GIT_INDEX_FILE` (or `env -u GIT_INDEX_FILE` wrapping every git invocation). This neutralizes mechanism #2 alone — autosync will still walk into uncovered child repos but writes will land in the umbrella's real index, not phantoms. **Lowest risk, smallest change.** Recommended starting point.
- **(b) Refuse to recurse into child .git dirs.** Make the hook detect any subdir containing its own `.git/` and add a transient `.gitignore` exclusion or pass `--no-recurse-submodules`-equivalent flags to `git add`. More invasive; harder to get right.
- **(c) Both (a) and (b).** Belt-and-suspenders. Probably correct long-term.

After whichever fix: rename `/Users/sma/projects/Sylveste/.git-autosync.disabled` → `.git-autosync`, then run `bash /tmp/inventory_contam_v2.sh` after a few autosync cycles to confirm zero recontamination.

### Artifacts (in /tmp, may not survive reboots — copy if needed long-term)

- `/tmp/inventory_contam_v2.sh` — correct inventory (clears `GIT_INDEX_FILE`). Categorizes as `Contaminated (fatal:)`, `No index (recoverable)`, or `Truly clean`.
- `/tmp/repair_mac_repo_v2.sh` — correct repair script (clears `GIT_INDEX_FILE`).
- `/tmp/mac_status_clean.txt` — final state, 113 truly clean repos.
- `/tmp/repair_results_v2.txt` — per-repo OK log from repair run.

### Background (unchanged from prior handoff)

- zklw is source of truth (113 repos cleaned + pushed today, autosync only on Mac).
- HTTPS→SSH migration: Mac child repo origins still HTTPS; switch to SSH before pushing from Mac.
- Tarball backup of Mac pre-rename state: `/tmp/sylveste-mac-git-backup-2026-04-18.tar.gz` (289 MB).

### CORRECTION — "genuinely corrupt" repos are not actually corrupt (verified 2026-04-21)

The prior handoff flagged two repos as corrupt. Re-inspection shows both are healthy:

- `interverse/interfer` — `fsck --full` returns only a cosmetic dangling commit (`550cdcf…`, harmless). `git status` / `log` / `cat-file HEAD` all work. The "missing `ae02e04b…`" object is unreachable from any branch, so nothing references it. Repo has 2 local unpushed commits and 5 modified tracked files from prior work, which may have been mistaken for corruption.
- `research/pi_agent_rust` — `fsck --full` clean, zero output. `git fetch` works. 150 commits behind `origin/main` (upstream is `Dicklesworthstone/pi_agent_rust`, which has been pushed to since). No missing objects, no blocked operations.

No repair needed for either. Delete this sub-section once confirmed stable.

### Important shell hygiene

Every git op in this session needed `env -u GIT_INDEX_FILE` prefix because Claude Code's per-shell env var poisons all git work. Even umbrella-level `git status` from a fresh agent shell reports `fatal: unable to read <SHA>` until you prefix. Either prefix every command or `unset GIT_INDEX_FILE` once at session start.
