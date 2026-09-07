Commit: `d93c231bdb63c99c2676f5442ecf934524a02658`

Changed:

- `scripts/dispatch.sh`
- `tests/shell/dispatch_claude_settings.bats`

Checks:

- `bash -n scripts/dispatch.sh` — PASS
- Specified Bats suite — exit 0; 12 passed, 10 parser tests skipped by existing `gawk` guard
- Commit path and trailer verification — PASS
- Worktree clean; no push performed

Failures: none  
Unresolved questions: none

VERDICT: PASS