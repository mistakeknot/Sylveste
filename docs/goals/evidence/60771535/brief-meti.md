# Brief: a dispatch starts clean and a timeout without fresh output never re-parks a stale verdict (mk-meti)

Contract: brief

## Objective

`dispatch_task()` in `scripts/orchestrate.py` reuses `<run dir>/<task>/output.md` and its `.verdict` sidecar across dispatches without deleting them first. On uncrancher run 57651f7d resume-3 a task's executor timed out, the previous round's `output.md` was read as if it were this round's, its `VERDICT: QUESTION` was re-parked verbatim by `extract_question`, and the executor's real work (staged, tests green) was orphaned. Make every dispatch start from a clean slate, and make a timeout that produced no fresh output say exactly that.

## Scope

Two files. `scripts/orchestrate.py`: the function `dispatch_task` and any small helper you add next to it. A new test file `tests/structural/test_orchestrate_stale_output.py`. Nothing else changes; `run_in_group`, the Pattern F mode (`orchestrate_pattern_f` and the `pf_*` functions), `dispatch_review` and `run_task_pipeline` are not edited.

## Constraints

- Before the dispatch command runs, remove any existing `output.md`, `output.md.verdict` and `output.md.verdict.pre-error` for that task and phase (the `stem`-prefixed names that `dispatch_task` computes). Other files in the task dir (prompt, dispatch logs, meta of earlier rounds) stay.
- After the run, a verdict sidecar counts only when this dispatch wrote it: its mtime is at or after the dispatch start time; an older sidecar is treated as absent.
- On a timeout with no fresh output file, the returned `TaskResult` has `output_path` None and a note containing the exact phrase `timed out, no fresh output`; the outcome check (`_outcome_check`) still runs so completed-but-unwitnessed work is still detected and dependents still run when it passes.
- With the files removed before the run, `extract_question` can never see a stale output: a timed-out dispatch that produced nothing reports no question.
- Existing behaviour is otherwise unchanged: `tests/structural/test_orchestrate.py`, `test_orchestrate_review.py`, `test_orchestrate_resume.py`, `test_orchestrate_observability.py` and `test_orchestrate_pattern_f.py` stay green without edits.
- Python 3.12 standard library only; keep the script executable; no new dependencies.

## Authority

Commit on the current branch of the checkout you are run in (a dedicated worktree) with `git commit -F <message file> -- scripts/orchestrate.py tests/structural/test_orchestrate_stale_output.py`; write the message file outside the repo. Subject: `fix(orchestrate): a dispatch starts clean; a timeout without fresh output never re-parks a stale verdict (mk-meti)`. The body ends with these two trailer lines, verbatim: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01Xkt2xiuD4S5FGTWkUaUNdP`. No push, no tags, no other files in the commit.

## Acceptance Criteria

1. `tests/structural/test_orchestrate_stale_output.py` exists and holds at least three tests, each driving `dispatch_task` (or `run_task_pipeline`) with a stub `dispatch.sh` through `CLAVAIN_DISPATCH_SH` the way `tests/structural/test_orchestrate_review.py` does: (a) an `output.md` and `output.md.verdict` left by an earlier round are gone before the stub runs (the stub itself asserts their absence and fails otherwise); (b) a stub that times out having written nothing yields `status == "error"`, `output_path is None` and a note containing `timed out, no fresh output`; (c) a stub that writes a fresh `VERDICT: QUESTION which colour?` output and then times out still parks as `question`, because fresh output is honoured.
2. The five existing orchestrate test files listed under Constraints pass unchanged.
3. `python3 -m py_compile scripts/orchestrate.py` succeeds.

## Verification

```bash
python3 -m py_compile scripts/orchestrate.py
cd tests && uv run pytest structural/test_orchestrate_stale_output.py structural/test_orchestrate.py structural/test_orchestrate_review.py structural/test_orchestrate_resume.py structural/test_orchestrate_observability.py structural/test_orchestrate_pattern_f.py -q
```

Expected: exit 0.

## Deliverables

diff or commit, checks run with outcomes, failures, unresolved questions.
