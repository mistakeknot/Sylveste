VERDICT: PASS
CRITERION: none
RECEIPT: receipt-ec9653ddc8

Both Verification commands ran from the worktree root at the named commit and exited 0. The syntax check passed. The Bats run reported 22 of 22 ok. The new settings file's first three tests assert exactly the three frozen sub-criteria: the flag appears immediately before `-p` and exactly once, the opt-out env var removes it, and the codex path never carries it. The commit touched only the two named files, so the seat and parser suites ran unchanged.

BEYOND THE GAUGE:
- The parser half of criterion 2 is vacuous on this machine. All 10 parser cases were platform-skipped for lack of GNU Awk, so nothing in that suite actually executed. The diff never touches the parser, so the risk is low, but the replay did not prove it.
- The dry-run display for claude changed beyond the flag. The old code stripped the last array element under a stale comment claiming it was the prompt. Since the stdin migration that element was `-p`, so old dry-run output silently omitted it. The new code prints the whole array, which now matches the real run at `scripts/dispatch.sh:2002`. This is a correctness fix, but anything outside the tree that parsed the old trailing-`-p`-less output will see different text.
- A dispatch without `--model` and without a tier now gets the CLI's built-in default model rather than the operator's user-scope model setting. Dropping user settings drops that key too. Role seats always receive a model from the orchestrator, so this only affects bare `--to claude` runs, and the opt-out env var restores it.
- The flag's real effect on the claude binary is asserted only by argv presence. No test launches claude, so the brief's hand measurement from 2026-09-07 remains the only evidence that project-plus-local sourcing actually drops the explanatory output style.
- The new help line is a single line over 150 characters wide, which breaks the column alignment of the surrounding option block. Cosmetic only.
