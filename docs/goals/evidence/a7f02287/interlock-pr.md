## Summary

The interlock commit lock never worked from a git worktree: `interlock-precommit-hook`, `commit_lock_path` in `hooks/lib.sh` and `interlock-install-hooks` built their paths from `$GIT_ROOT/.git`, which inside a worktree is the gitdir pointer *file*. Every `mkdir` under it failed, so a worktree commit spun for the whole 30 s timeout and died with `Commit lock timeout (30s). Another session is committing.` (seen 2026-09-02 on interlens; Sylveste-asqi, named mk-gly2 in an earlier handoff).

All three now use `git rev-parse --path-format=absolute --git-common-dir` (the installer: `--git-path hooks`), so every worktree of a checkout shares one lock and one hooks directory. `INTERLOCK_COMMIT_LOCK_TIMEOUT` overrides the timeout for tests.

## Proof

`tests/structural/test_precommit_lock.py` runs the real hook in a worktree of a throwaway repo with intermute unreachable (fail-open) and a 2 s lock timeout:

- the fixed hook passes from the worktree and from the main checkout, and releases the lock;
- a live holder in the common dir still blocks the worktree (one lock for all worktrees);
- the pre-fix hook from `d635136` fails the same fixture with the timeout message.

The commit on this branch was itself made from a worktree with the fixed hook installed and `INTERMUTE_AGENT_ID` set, in under a second.

`cd tests && uv run pytest -q`: 111 passed.

## Not in this PR

`INTERMUTE_PROJECT` still defaults to the basename of the worktree rather than of the main checkout, so reservations made from a worktree scope differently; recorded on Sylveste-asqi. No version bump: the local `sweep/2026-09-02` lane holds an unpushed 0.2.20.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Xkt2xiuD4S5FGTWkUaUNdP
