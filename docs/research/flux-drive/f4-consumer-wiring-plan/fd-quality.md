### Findings Index

- HIGH | F4-1 | "Task 4: Sprint env var injection" | `sprint_find_active` JSON shape mismatch — `.phase` field does not exist
- HIGH | F4-2 | "Task 2: Bats test file naming" | Test file named `lib_compose.bats` diverges from established naming conventions
- MED  | F4-3 | "Task 4: Sprint env var injection" | `_compose_find_cli` called before lib-compose.sh is sourced in session-start.sh
- MED  | F4-4 | "Task 2: Bats tests" | `_compose_has_agency_spec` test leaks temp dir on test failure; cleanup in `teardown` not used
- MED  | F4-5 | "Task 1: lib-compose.sh" | `compose_dispatch()` rewrite drops the first positional parameter rename without updating the call-site comment in the header
- LOW  | F4-6 | "Task 3: launch.md" | Temp-variable prefix `_fd_` is inconsistent — some variables use `_f4_` prefix in Task 4, mixing two different conventions in coordinated code
- LOW  | F4-7 | "Task 2: Bats tests" | `count` and `agent_type` assigned without `local` in test body — leaks to bats test scope
- LOW  | F4-8 | "Task 1: lib-compose.sh" | `compose_warn_if_expected` return value semantics are inverted relative to convention

Verdict: needs-changes

---

### Summary

The plan is well-structured and the bash code is mostly shellcheck-compatible. Two high-severity issues require fixes before implementation: the `sprint_find_active` JSON output uses `{id, title, phase, run_id}` — the plan's Task 4 reads `.phase` from `.[0]` correctly, but the field is actually present, so that part is fine; however the plan sources `lib-compose.sh` *after* using `_compose_find_cli` in the inject block, creating a real undefined-function hazard. The test file naming departs from the project's established `test_*.bats` prefix convention for lib tests. Remaining issues are low-risk naming inconsistencies and test hygiene gaps.

---

### Issues Found

**F4-1. HIGH: `_compose_find_cli` called before lib-compose.sh is sourced in session-start.sh**

Task 4 (line ~419 of the plan) uses `_f4_cli=$(_compose_find_cli 2>/dev/null)` inside the injection block, but lib-compose.sh is proposed to be sourced immediately before the sprint awareness scan at line ~210. The session-start.sh file currently sources `sprint-scan.sh` at line 212, which itself sources `lib-sprint.sh` — neither sources `lib-compose.sh`. The plan's own dependency note says "Source lib-compose.sh earlier in session-start.sh. Add before line 210", but the code block shown places the source *before* the sprint block and the injection block *after* it. If the `source … 2>/dev/null || true` line is placed correctly this resolves itself, but the plan presents these as two independent insertion points without making the ordering dependency explicit. An implementer following the instructions sequentially could insert the injection block (line 217) before inserting the source line (line 210) and end up calling an undefined function. The acceptance test (`bash -n`) will not catch this because `bash -n` does not check for undefined functions.

**F4-2. HIGH: Test file named `lib_compose.bats` conflicts with established naming convention**

The existing lib-level test file for sprint functions is `test_lib_sprint.bats`, the compose integration tests are `test_compose.bats`, and the naming convention for lib tests visible in the glob output is uniformly `test_*.bats`. The plan proposes `lib_compose.bats` (no `test_` prefix), which breaks `bats tests/shell/test_*.bats` glob invocations and differs from every other lib test in the directory. The correct name following the convention is `test_lib_compose.bats`.

**F4-3. MED: `_compose_has_agency_spec` test leaks temp dir on assertion failure**

In the bats tests for `_compose_has_agency_spec` (Tasks 2, steps for "finds spec in CLAUDE_PLUGIN_ROOT" and "returns 1 when no spec exists"), the `rm -rf "$tmpdir"` cleanup is placed after `assert_success`/`assert_failure`. When the assertion fails, bats exits the test immediately via a subshell trap and the `rm -rf` line is never reached, leaking the temp directory. The project's existing bats tests (e.g., `sprint_scan.bats`) use a `teardown()` function for cleanup. Move temp dir creation to `setup()` and deletion to `teardown()`, or use `BATS_TEST_TMPDIR` which bats cleans up automatically.

**F4-4. MED: `compose_dispatch()` header comment still refers to old `<sprint_id>` parameter name**

The existing `lib-compose.sh` header at line 7 reads `plan=$(compose_dispatch "$sprint_id" "$stage")`. Task 1 renames the first positional parameter from `sprint_id` to `bead_id` inside the function body, but the plan does not update the usage comment at the top of the file. Callers reading the header will see a misleading parameter name. The header comment must be updated to `plan=$(compose_dispatch "$bead_id" "$stage")` in the same edit.

**F4-5. LOW: `count` and `agent_type` variables in bats test body are not declared `local`**

In the `compose_agents_json` tests (lines ~235–245 of the plan), the assignments `count=$(echo "$output" | jq 'length')` and `agent_type=$(echo "$output" | jq -r '.[0].subagent_type')` are bare assignments inside a `@test` block. In bats, test bodies run in a subshell so leakage to other tests is not the concern, but the project's existing tests consistently use `local` for intermediate variables (visible in `test_lib_sprint.bats`). More critically, `assert_success` runs in a subshell that exits on failure — if `run compose_agents_json "$plan"` fails, the subsequent bare `count=` assignment will silently succeed with empty output, masking the failure. Declare these with `local` and check `assert_success` before using `$output`.

**F4-6. LOW: `compose_warn_if_expected` return semantics are inverted relative to naming**

The function name `compose_warn_if_expected` reads as "warn if a warning is expected (i.e., Composer is configured)". When `_compose_has_agency_spec` returns true, the function prints to stderr and returns 1. Call sites in Task 3 use `compose_warn_if_expected "…" 2>/dev/null || true`, discarding the return code anyway, so this is low risk. But the inverted return code (error when the condition is met) makes the function harder to compose correctly in future call sites. The convention for functions named `compose_warn_*` should return 0 (success) after warning, reserving non-zero for when the call itself fails. Consider either returning 0 always (it's a side-effect function, not a predicate) or renaming to `compose_require_functional` to clarify that non-zero means "you should stop".

---

### Improvements

**F4-I1. Use `BATS_TEST_TMPDIR` for temp directories in bats tests** — bats 1.3+ provides this variable as a per-test temp dir that is automatically cleaned up; it eliminates the cleanup-on-failure hazard and makes tests shorter.

**F4-I2. Make the lib-compose.sh source dependency in session-start.sh explicit in the plan** — add a single sentence noting that the source line (pre-line 210) must be inserted first, before the injection block (post-line 217), because the latter calls `_compose_find_cli` which is defined only after sourcing. This prevents implementation-order mistakes that `bash -n` will not detect.

**F4-I3. Add a `compose_dispatch` integration test using a fixture file** — the bats suite for `lib-compose.sh` currently tests only the helpers (`compose_has_agents`, `compose_agents_json`, `compose_warn_if_expected`). The core `compose_dispatch` stored-artifact path is untested because it requires the Go CLI binary. A bats test that stubs `_compose_find_cli` to return a script that cats a fixture file would cover the stored-path branch without needing the binary, matching the pattern used in `test_lib_sprint.bats` where intercore is mocked with shell functions.

<!-- flux-drive:complete -->
