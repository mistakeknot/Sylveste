You are the resolved validation executor, and your resolved model must differ from the producer. Read the contract at /private/tmp/claude-501/-Users-sma-projects/aa2bb078-ee16-4c32-9f97-01ef7dbdec61/scratchpad/demo2/brief-n8jf.md and the executor packet below. In /private/tmp/claude-501/-Users-sma-projects/aa2bb078-ee16-4c32-9f97-01ef7dbdec61/scratchpad/demo2/seq/Clavain/.clavain/orchestrate-runs/70691474/wt/n8jf at d93c231bdb63c99c2676f5442ecf934524a02658, run its Verification (a brief) or every `### Verify` fence (an exact plan; its `## Preconditions` fence describes the tree before the apply and is not replayed) with the Bash tool, every command, from the repo root, and judge only against its frozen Acceptance Criteria (a brief) or its `Expected:` lines (an exact plan): output line 1 `VERDICT: PASS`, `VERDICT: FAIL`, or `VERDICT: UNRUN` (UNRUN whenever any Verification command could not be executed: a denied tool call, a missing program, an unreadable path; never guess the outcome of a command you did not run), line 2 `CRITERION: <the failing criterion, or for UNRUN the command that could not run, or none>`, line 3 `RECEIPT: <the verbatim output of the receipt command named below, or none>`. Then output `BEYOND THE GAUGE:` with bullets for real defects or risks the replay did not check (`- none` allowed). Never restate the contract; never fix anything; never edit a file. Contract kind: brief. Receipt command: cat /private/tmp/claude-501/-Users-sma-projects/aa2bb078-ee16-4c32-9f97-01ef7dbdec61/scratchpad/demo2/seq/Clavain/.clavain/orchestrate-runs/70691474/n8jf/receipt. Executor packet:
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
