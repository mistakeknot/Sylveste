You are the resolved validation executor, and your resolved model must differ from the producer. Read the contract at /private/tmp/claude-501/-Users-sma-projects/aa2bb078-ee16-4c32-9f97-01ef7dbdec61/scratchpad/demo2/brief-ihnv.md and the executor packet below. In /private/tmp/claude-501/-Users-sma-projects/aa2bb078-ee16-4c32-9f97-01ef7dbdec61/scratchpad/demo2/seq/Clavain/.clavain/orchestrate-runs/70691474/wt/ihnv at 6b0e95daee74dc5234218e01506f32d0a2ff5c46, run its Verification (a brief) or every `### Verify` fence (an exact plan; its `## Preconditions` fence describes the tree before the apply and is not replayed) with the Bash tool, every command, from the repo root, and judge only against its frozen Acceptance Criteria (a brief) or its `Expected:` lines (an exact plan): output line 1 `VERDICT: PASS`, `VERDICT: FAIL`, or `VERDICT: UNRUN` (UNRUN whenever any Verification command could not be executed: a denied tool call, a missing program, an unreadable path; never guess the outcome of a command you did not run), line 2 `CRITERION: <the failing criterion, or for UNRUN the command that could not run, or none>`, line 3 `RECEIPT: <the verbatim output of the receipt command named below, or none>`. Then output `BEYOND THE GAUGE:` with bullets for real defects or risks the replay did not check (`- none` allowed). Never restate the contract; never fix anything; never edit a file. Contract kind: brief. Receipt command: cat /private/tmp/claude-501/-Users-sma-projects/aa2bb078-ee16-4c32-9f97-01ef7dbdec61/scratchpad/demo2/seq/Clavain/.clavain/orchestrate-runs/70691474/ihnv/receipt. Executor packet:
COMMIT: `6b0e95daee74dc5234218e01506f32d0a2ff5c46`

DIFF: 2 files changed, 161 insertions, 18 deletions.

CHECKS:
- `python3 -m py_compile scripts/plan-gauge-lint.py` — exit 0
- Requested pytest suite — 37 passed
- `git diff --check HEAD^ HEAD` — exit 0
- Worktree clean on `pf/70691474/ihnv`

FAILURES: None remaining.

UNRESOLVED QUESTIONS: None.

VERDICT: PASS
