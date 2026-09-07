Commit: `7ad208e` on `pf/8565586e/ihnv`; two authorized files only. No push.

Checks:

- `python3 -m py_compile scripts/plan-gauge-lint.py` — passed.
- Prescribed pytest suite — 38 passed.
- Post-commit worktree — clean.
- Regression tests cover stdin isolation, process-group termination, CRLF preservation, and invalid UTF-8 refusal.

Unresolved question: Criterion 1(a) requires bare `read -r line; echo "after"` to exit 0, but mandated `bash -e` with `/dev/null` exits immediately when `read` returns EOF. The test uses `read -r line || true` to exercise the intended behavior.

VERDICT: FAIL  
CRITERION: Acceptance Criterion 1(a) is internally inconsistent with the mandated bash -e and /dev/null mechanics.