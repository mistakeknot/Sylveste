# Brief: plan-gauge-lint.py --apply runs fences from a file in their own process group and round-trips edits as bytes (Sylveste-ihnv)

Contract: brief

## Objective

Three defects in the exact-contract applier in `scripts/plan-gauge-lint.py` (`apply_exact` and `_run_fence`), reasoned from code by the brief validator of goal 5bdf10a5 and not yet reproduced: (1) `_run_fence` passes the fence body to bash on stdin, so a fence whose command reads stdin (`read`, `cat`, `xargs`, `python3 -`) consumes the rest of the script; (2) the fence timeout kills only the bash process, so a child the fence started (a test runner, a server) outlives the deadline; (3) edits round-trip through `read_text(errors="replace")` and `write_text`, so a file with invalid UTF-8 or CRLF line endings is rewritten with different bytes from the ones the plan's old_string and new_string named. Fix all three, with a regression test for each that fails on the current code.

## Scope

One source file, `scripts/plan-gauge-lint.py`, limited to `_run_fence`, `apply_exact`, the edit-application code they call, and small helpers beside them; tests in `tests/structural/test_plan_gauge_apply.py`. The gauge rules (GAUGE001 to GAUGE005, every `check_*` function, and the plain lint path without `--apply`) do not change; the JSON receipt keys already emitted by `--apply` do not change; the exit codes documented in the file header do not change.

## Constraints

- `_run_fence` writes the fence body to a temporary file and runs it as `bash -e -o pipefail <file>` from the repo root with stdin redirected from `/dev/null`, so a stdin-reading command sees end-of-file rather than the script. The temporary file is removed after the run, including on timeout.
- The fence runs as the leader of its own process group (`start_new_session=True`). On timeout the whole group is killed (SIGTERM, a short grace, then SIGKILL) and the receipt still says `timed out after N seconds`. A background child the fence started must not survive the timeout.
- Edits read and write bytes. The current file bytes are decoded strictly as UTF-8 (no `errors=`), old_string and new_string are matched on the decoded text with the file's line endings normalised for the match, and the result is written back with the original line endings (a CRLF file stays CRLF on every line, an LF file stays LF) and no BOM added or removed. A file that does not decode as UTF-8 is refused with an apply error naming the path; nothing is written for that plan and the receipt reports the refusal with the exit code the header documents for a refused apply.
- Everything else in `--apply` is unchanged: the revert hint, created-file handling, the order of verify replays, the JSON receipt shape.
- Python 3.12 standard library only; keep the script executable; no new dependencies.

## Authority

Commit on the current branch of the checkout you are run in (a dedicated worktree) with `git commit -F <message file> -- scripts/plan-gauge-lint.py tests/structural/test_plan_gauge_apply.py`; write the message file outside the repo. Subject: `fix(gauge): --apply runs fences from a file in their own process group and round-trips edits as bytes (Sylveste-ihnv)`. The body ends with these two trailer lines, verbatim: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01Xkt2xiuD4S5FGTWkUaUNdP`. No push, no tags, no other files in the commit.

## Acceptance Criteria

1. `tests/structural/test_plan_gauge_apply.py` gains at least four tests: (a) a verify fence `read -r line; echo "after"` followed by an `Expected:` line for exit 0 passes and its recorded stdout contains `after`; (b) a verify fence `( sleep 3; touch survived ) & sleep 30` under `--timeout 1` is reported as timed out and, two seconds after the apply returns, `survived` does not exist in the repo; (c) an edit to a target file written with CRLF line endings applies the replacement and every line of the result still ends in CRLF; (d) a target file containing invalid UTF-8 makes the apply refuse before writing anything: the tree is unchanged and the receipt or stderr names the path.
2. Every existing test in `tests/structural/test_plan_gauge_apply.py`, `tests/structural/test_plan_gauge_apply_followup.py` and `tests/structural/test_plan_gauge_lint.py` passes unchanged.
3. `python3 -m py_compile scripts/plan-gauge-lint.py` succeeds.

## Verification

```bash
python3 -m py_compile scripts/plan-gauge-lint.py
cd tests && uv run pytest structural/test_plan_gauge_apply.py structural/test_plan_gauge_apply_followup.py structural/test_plan_gauge_lint.py -q
```

Expected: exit 0.

## Deliverables

diff or commit, checks run with outcomes, failures, unresolved questions.
