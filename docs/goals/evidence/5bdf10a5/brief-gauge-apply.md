# Brief: plan-gauge-lint.py --apply (an exact contract applied and replayed by the tool)

Contract: brief

## Objective

Add an `--apply` mode to `scripts/plan-gauge-lint.py` so an exact contract is applied to a live checkout and its verify fences are replayed by the tool itself, exiting non-zero at the first mismatch, so an exact plan needs no executor model. The frozen acceptance is `tests/structural/test_plan_gauge_apply.py` at commit 612f8f0; make it pass without editing it.

## Scope

One file: `scripts/plan-gauge-lint.py`. Extend its module docstring with a short paragraph on `--apply` (what it runs, the exit codes). No other file changes. Do not edit `tests/structural/test_plan_gauge_apply.py`, `tests/structural/test_plan_gauge_lint.py`, or any hook, doc, skill, or config file.

## Constraints

- The gauge rules stay as they are: every existing check (GAUGE001 to GAUGE005, BRIEF001 to BRIEF004), `--self-test`, the `--json` output of the non-apply path, exit codes 0/1/2, and the parsing helpers (`parse_blocks`, `_classify`, `collect_edits`, `_resolve_bare_targets`, `build_virtual_tree`, `extract_greps`, `parse_expectation`) keep their current behaviour. `tests/structural/test_plan_gauge_lint.py` and `tests/shell/gauge_gate_executor_spawn.bats` stay green.
- `--apply` requires `--repo-root` (argparse error, exit 2, when absent) and refuses a brief contract with exit 3 and a message that says brief contracts go to a model, not the tool.
- Order of operations under `--apply`: (1) run the exact gauge on the plan exactly as today; any finding prints the normal report and exits 1 with nothing applied. (2) Refuse with exit 3 when any edit target that exists in the repo has uncommitted changes (`git status --porcelain -- <targets>` non-empty); when the repo root is not inside a git work tree, skip this check and print a note. (3) Run every shell fence under a `## Preconditions` heading; a non-zero return code refuses with exit 3 before any edit, and the message contains the word Preconditions. (4) Walk the plan in document order: apply each old_string/new_string pair (the target file must exist and old_string must occur exactly once; otherwise exit 4) and each Create block (parent directories are created; the target must not already exist, otherwise exit 4); run each shell fence under a heading whose text starts with `Verify` when it is reached and compare with its `Expected:` line (exit 5 on the first mismatch).
- Fences run with `bash -e -o pipefail` from the repo root, each under a timeout (`--timeout SECONDS`, default 600; a timeout is a mismatch).
- Expectation rules for a verify fence, read from the first line that starts with `Expected:` within ten lines after the closing fence: `exit N` requires return code N; `prints NOTHING` or `no output` requires empty stdout and does not check the return code; otherwise return code 0 is required. A Preconditions fence requires return code 0.
- A shell fence that the existing heuristics classify as a verify but that sits under neither a Preconditions heading nor a Verify heading is not executed by `--apply`.
- Only the edit pairs and Create blocks the existing parser collects are applied; bare file names go through `_resolve_bare_targets`; an edit whose target cannot be resolved is exit 4.
- Messages. An edit mismatch prints a line of the form `apply: edit <target> (plan line N): old_string not found` or `... old_string found K times` or `apply: create <target> (plan line N): target already exists`. A verify mismatch prints `apply: verify <heading> (plan line N): FAILED rc=<code>, expected <expectation>` followed by the last twenty lines of the fence's stdout and stderr. A success prints `apply: <kind> <target or heading> (plan line N): ok`. On exit 4 or 5 the output also lists the files already written and the revert command `git checkout -- <files>`.
- With `--json`, the receipt object gains an `apply` key: `{"ok": bool, "repo_root": str, "steps": [{"kind": "precondition|edit|create|verify", "line": int, "target": str|null, "heading": str|null, "status": "ok|failed|skipped", "rc": int|null, "detail": str}]}` in execution order; steps after the first failure are omitted or marked skipped. With `--json` the receipt is the only thing on stdout.
- `--apply` never commits, stages, pushes, or otherwise touches git state; it writes only the plan's files.
- Python 3.12 standard library only; no new dependencies; keep the script executable.

## Authority

Commit on `main` in `/Users/sma/projects/Sylveste/os/Clavain` with `git commit -F <message file> -- scripts/plan-gauge-lint.py`; write the message file under /tmp. Subject: `feat(gauge): --apply applies an exact contract and replays its verify fences`. The body ends with these two trailer lines, verbatim: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01Xkt2xiuD4S5FGTWkUaUNdP`. No push, no other files in the commit, no tags.

## Acceptance Criteria

1. `cd tests && uv run pytest structural/test_plan_gauge_apply.py -q` reports 12 passed.
2. `cd tests && uv run pytest structural/test_plan_gauge_lint.py -q` passes.
3. `python3 scripts/plan-gauge-lint.py --self-test` prints `SELF-TEST PASSED`.
4. `bats tests/shell/gauge_gate_executor_spawn.bats` passes.
5. `tests/structural/test_plan_gauge_apply.py` is byte-identical to its content at commit 612f8f0.
6. The commit touches only `scripts/plan-gauge-lint.py`.

## Verification

```bash
cd /Users/sma/projects/Sylveste/os/Clavain
python3 -m py_compile scripts/plan-gauge-lint.py
python3 scripts/plan-gauge-lint.py --self-test 2>&1 | tail -1
(cd tests && uv run pytest structural/test_plan_gauge_apply.py structural/test_plan_gauge_lint.py -q 2>&1 | tail -2)
bats tests/shell/gauge_gate_executor_spawn.bats 2>&1 | tail -1
git diff --quiet 612f8f0 HEAD -- tests/structural/test_plan_gauge_apply.py && echo frozen-intact
git show --stat --format=%s HEAD | tail -4
```

## Deliverables

The bounded packet only: the commit hash; the checks run with their outcomes; failures (including the expected pre-implementation red of the frozen tests); unresolved questions.
