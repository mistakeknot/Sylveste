# Exact plan: `--verdict UNRUN` in the verdict register, and the contracts doc routes exact plans to the tool

Contract: exact

REPO PATH: /Users/sma/projects/Sylveste/os/Clavain

## Preconditions

```bash
test -f scripts/pattern-f-verdict.sh
test -f skills/executing-plans/references/pattern-f-contracts.md
test ! -e tests/shell/pattern_f_verdict_unrun.bats
```

## Task 1: the register accepts UNRUN for replay rows

In `scripts/pattern-f-verdict.sh`:

old_string (scripts/pattern-f-verdict.sh):
```bash
#               reason (the linter's GAUGE lines). --kind gate pairs only with
#               --role gate.
#
# Usage:
```

new_string (scripts/pattern-f-verdict.sh):
```bash
#               reason (the linter's GAUGE lines). --kind gate pairs only with
#               --role gate.
#
# Verdict values (--verdict): PASS and FAIL for every kind; UNRUN only with
#   --kind replay, meaning the plan's Verification could not be executed by
#   that seat (a denied command, a missing program, an unreadable plan). An
#   UNRUN row is a refusal to rule, never a pass; --note says what did not run.
#
# Usage:
```

old_string (scripts/pattern-f-verdict.sh):
```bash
#       --verdict PASS|FAIL [--criterion TEXT] [--note TEXT] [--goal ID] [--db PATH]
```

new_string (scripts/pattern-f-verdict.sh):
```bash
#       --verdict PASS|FAIL|UNRUN [--criterion TEXT] [--note TEXT] [--goal ID] [--db PATH]
```

old_string (scripts/pattern-f-verdict.sh):
```bash
           --role executor|validator|gate --kind replay|independent|gate --verdict PASS|FAIL
           [--criterion TEXT] [--note TEXT] [--goal ID] [--db PATH]
```

new_string (scripts/pattern-f-verdict.sh):
```bash
           --role executor|validator|gate --kind replay|independent|gate --verdict PASS|FAIL|UNRUN
           [--criterion TEXT] [--note TEXT] [--goal ID] [--db PATH]
```

old_string (scripts/pattern-f-verdict.sh):
```bash
  case "$verdict" in
    PASS|FAIL) ;;
    *) bad "--verdict must be PASS or FAIL" ;;
  esac
```

new_string (scripts/pattern-f-verdict.sh):
```bash
  case "$verdict" in
    PASS|FAIL) ;;
    UNRUN)
      [[ "$kind" == replay ]] || bad "--verdict UNRUN pairs only with --kind replay"
      ;;
    *) bad "--verdict must be PASS, FAIL or UNRUN" ;;
  esac
```

Create `tests/shell/pattern_f_verdict_unrun.bats` with:

```bash
#!/usr/bin/env bats
# --verdict UNRUN in scripts/pattern-f-verdict.sh: a replay the seat could not
# execute is a refusal to rule, recorded as its own verdict value and never a
# pass. Same fresh-register setup as pattern_f_verdict.bats.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/scripts/pattern-f-verdict.sh"
    PROJ="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$PROJ/.clavain/interspect"
    export CLAUDE_PROJECT_DIR="$PROJ"
    export INTERSPECT_QUARANTINE_HOURS=0
    # shellcheck source=/dev/null
    source "$REPO_ROOT/hooks/lib.sh" 2>/dev/null || skip "hooks/lib.sh not sourceable"
    local root
    root=$(_discover_interspect_plugin 2>/dev/null) || root=""
    [[ -n "$root" && -f "$root/hooks/lib-interspect.sh" ]] || skip "interspect library not found"
    export INTERSPECT_ROOT="$root"
    # shellcheck source=/dev/null
    source "$root/hooks/lib-interspect.sh" 2>/dev/null || skip "lib-interspect.sh not sourceable"
    _interspect_ensure_db || skip "_interspect_ensure_db failed"
    DB="$PROJ/.clavain/interspect/interspect.db"
    [[ -f "$DB" ]] || skip "register not created at $DB"
    PLAN="$PROJ/plan-test.md"
}

@test "replay UNRUN row is recorded and listed with its note" {
    run bash "$SCRIPT" --db "$DB" --session sess-u --plan "$PLAN" --commit abc1234 \
        --role validator --kind replay --verdict UNRUN --note "uv run pytest: command denied" --goal g1
    [ "$status" -eq 0 ]
    [[ "$output" == *"recorded validator replay UNRUN"* ]]

    run bash "$SCRIPT" --list --db "$DB" --session sess-u
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" == *$'\tvalidator\treplay\tUNRUN\t'* ]]
    [[ "${lines[0]}" == *"command denied"* ]]
}

@test "UNRUN with --kind independent exits 2 and writes nothing" {
    run bash "$SCRIPT" --db "$DB" --session sess-u --plan "$PLAN" --commit abc1234 \
        --role validator --kind independent --verdict UNRUN
    [ "$status" -eq 2 ]
    [[ "$output" == *"UNRUN pairs only with --kind replay"* ]]
    run sqlite3 "$DB" "select count(*) from evidence where event='pattern_f_verdict';"
    [ "$output" = "0" ]
}

@test "an executor replay may be UNRUN too" {
    run bash "$SCRIPT" --db "$DB" --session sess-u --plan "$PLAN" --commit none \
        --role executor --kind replay --verdict UNRUN --note "bats not installed"
    [ "$status" -eq 0 ]
    [[ "$output" == *"recorded executor replay UNRUN"* ]]
}

@test "an unknown verdict value still exits 2" {
    run bash "$SCRIPT" --db "$DB" --session sess-u --plan "$PLAN" --commit abc1234 \
        --role executor --kind replay --verdict MAYBE
    [ "$status" -eq 2 ]
    [[ "$output" == *"PASS, FAIL or UNRUN"* ]]
}
```

### Verify Task 1

```bash
bash -n scripts/pattern-f-verdict.sh
grep -c 'UNRUN' scripts/pattern-f-verdict.sh
bats tests/shell/pattern_f_verdict.bats tests/shell/pattern_f_verdict_unrun.bats 2>&1 | tail -1
```

Expected: exit 0

## Task 2: the contracts doc says which contract goes to a model and which to the tool

In `skills/executing-plans/references/pattern-f-contracts.md`:

old_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
Every contract declares `Contract: brief` or `Contract: exact`. The linter also accepts `--contract`; absent either declaration it treats legacy plans as `exact`.
```

new_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
Every contract declares `Contract: brief` or `Contract: exact`. The linter also accepts `--contract`; absent either declaration it treats legacy plans as `exact`.

Which goes where: a `brief` goes to a model (the executor resolved through `routine-execution` or `deep-execution`), because it prescribes outcomes and someone has to find the mechanics. An `exact` contract goes to the tool: `python3 scripts/plan-gauge-lint.py --apply <plan> --repo-root <repo>` applies its edit pairs and Create blocks in document order, runs its `## Preconditions` and `### Verify` fences from the repo root with `bash -e -o pipefail`, compares each fence with its `Expected:` line (`exit N`; `prints NOTHING`; otherwise exit 0), and exits non-zero at the first mismatch (1 a gauge defect, nothing applied; 3 refused before any edit: brief contract, dirty targets, failed preconditions; 4 an edit did not anchor; 5 a verify fence missed). It never commits: the main integrator commits with the plan's `## Commit` pathspec and message file. An exact plan therefore needs no executor model, and the validator replays its Verify fences the way it replays a brief's Verification.
```

old_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
It must exit 0. The spawn gate `hooks/gauge-gate-executor-spawn.sh`
```

new_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
It must exit 0. For an exact plan the same script with `--apply` then applies the plan and replays its fences (see Planning contracts); the gauge runs first either way. The spawn gate `hooks/gauge-gate-executor-spawn.sh`
```

old_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
The validator is dispatched only after the executor reports, with the producer identity passed to routing. `<REF>` is the commit or working-tree reference and `<REPORT>` is the bounded packet. The prompt is:
```

new_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
The validator is dispatched only after the executor reports, with the producer identity passed to routing and the plan named to the seat: `bash scripts/dispatch.sh --role validation --producer-identity <producer model> --plan <plan path> -C <repo path> --prompt-file <prompt> -o <report>`. The claude seat runs with Bash allowed and Edit, Write and NotebookEdit disallowed, the plan's directory added as a readable root, and the checkout snapshotted before and after the run: a run that changes the checkout is an error verdict and a failed dispatch, never a ruling. `<REF>` is the commit or working-tree reference and `<REPORT>` is the bounded packet. The prompt is:
```

old_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
You are the resolved validation executor, and your resolved model must differ from the producer. Read the contract at <plan path> and the executor packet below. In <repo path> at <REF>, replay its Verification and judge only against its frozen Acceptance Criteria: output line 1 `VERDICT: PASS` or `VERDICT: FAIL`, line 2 `CRITERION: <the failing criterion, or none>`. Then output `BEYOND THE GAUGE:` with bullets for real defects or risks the replay did not check (`- none` allowed). Never restate the contract; never fix anything. Executor packet: <REPORT>
```

new_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
You are the resolved validation executor, and your resolved model must differ from the producer. Read the contract at <plan path> and the executor packet below. In <repo path> at <REF>, run its Verification with the Bash tool, every command, from the repo root, and judge only against its frozen Acceptance Criteria: output line 1 `VERDICT: PASS`, `VERDICT: FAIL`, or `VERDICT: UNRUN` (UNRUN whenever any Verification command could not be executed: a denied tool call, a missing program, an unreadable path; never guess the outcome of a command you did not run), line 2 `CRITERION: <the failing criterion, or none>`, line 3 `RECEIPT: <the verbatim output of the receipt command named below, or none>`. Then output `BEYOND THE GAUGE:` with bullets for real defects or risks the replay did not check (`- none` allowed). Never restate the contract; never fix anything; never edit a file. Receipt command: <RECEIPT COMMAND>. Executor packet: <REPORT>
```

old_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
1. `VERDICT: PASS|FAIL` (line 1): the result of replaying the plan's VERIFY block at the executor's commit.
2. `CRITERION: <failing VERIFY line or none>` (line 2): the failing VERIFY line quoted verbatim when the verdict is FAIL, otherwise `none`.
3. `BEYOND THE GAUGE:`: the second channel. A bullet list of real defects or risks in the change that the VERIFY block did not check; `- none` is allowed and means the validator looked and found nothing.
```

new_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
1. `VERDICT: PASS|FAIL|UNRUN` (line 1): the result of running the plan's VERIFY block at the executor's commit. `UNRUN` means the seat could not execute some command of it and refuses to rule; it is never a pass and it is recorded as its own verdict value.
2. `CRITERION: <failing VERIFY line or none>` (line 2): the failing VERIFY line quoted verbatim when the verdict is FAIL, the command that could not run when it is UNRUN, otherwise `none`.
3. `RECEIPT: <value or none>` (line 3): the verbatim output of the receipt command the orchestrator named in the prompt, which prints a value the orchestrator wrote to disk after the prompt was fixed (for example `cat <plan>.receipt`). The orchestrator compares it with what it wrote; a PASS or FAIL whose receipt does not match is recorded as UNRUN, because nothing shows the block was run.
4. `BEYOND THE GAUGE:`: the second channel. A bullet list of real defects or risks in the change that the VERIFY block did not check; `- none` is allowed and means the validator looked and found nothing.
```

old_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
When the executor reports a defect, the orchestrator fixes the plan (never the repo) and re-spawns once; when the validator rejects, the same.
```

new_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
When the executor reports a defect, the orchestrator fixes the plan (never the repo) and re-spawns once; when the validator rejects, the same. An UNRUN is neither strike: it says the seat could not run, so the orchestrator fixes the seat or the environment and dispatches again, and the UNRUN row stays in the register.
```

old_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
bash scripts/pattern-f-verdict.sh --session <id> --plan <plan path> --commit <hash> --role validator --kind replay --verdict PASS|FAIL [--criterion "<failing VERIFY line>"] --goal <goal id> --db <db>
```

new_string (skills/executing-plans/references/pattern-f-contracts.md):
```markdown
bash scripts/pattern-f-verdict.sh --session <id> --plan <plan path> --commit <hash> --role validator --kind replay --verdict PASS|FAIL|UNRUN [--criterion "<failing VERIFY line>"] [--note "<what did not run>"] --goal <goal id> --db <db>
```

### Verify Task 2

```bash
grep -c 'Which goes where' skills/executing-plans/references/pattern-f-contracts.md
grep -c 'RECEIPT' skills/executing-plans/references/pattern-f-contracts.md
grep -c 'UNRUN' skills/executing-plans/references/pattern-f-contracts.md
```

Expected: exit 0

## Commit

Message file: `/tmp/msg-verdict-unrun.txt`. Pathspec: `scripts/pattern-f-verdict.sh tests/shell/pattern_f_verdict_unrun.bats skills/executing-plans/references/pattern-f-contracts.md`. Commit authority: the main integrator, after `--apply` exits 0.
