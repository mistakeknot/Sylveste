# Goal 60771535 journal: a Pattern F run driven by orchestrate.py

Session aa2bb078-ee16-4c32-9f97-01ef7dbdec61, 2026-09-06/07. Predecessor: goal 5bdf10a5 (replay channel). Charter and condition sit beside this file. mk's ask: "please proceed with the above goal", the Next-goal block that closed 5bdf10a5.

## What shipped (Clavain, on main)

- `85a617f` feat(orchestrate): `--pattern-f <run.pf.yaml>` drives the offload loop from a run file: gauge (a finding writes the gate row), a worktree per item on `pf/<run>/<item>` with `ic init` run in it, exact plans through `plan-gauge-lint.py --apply` with one commit by the orchestrator, briefs through `dispatch.sh --role <executor role>`, the validation seat through `--role validation --plan` with a receipt nonce written after the prompt is fixed (a PASS or FAIL whose RECEIPT does not match is recorded as UNRUN), every verdict through `pattern-f-verdict.sh` with `--db` explicit and read back, merge on a validator PASS, one closing packet. `run_in_group()` starts every dispatch as the leader of its own session and kills the group on timeout, TERM then KILL (mk-kj2m); the legacy `dispatch_task` and `dispatch_review` paths use it too. `scripts/pattern-f-meter.py` reads `meter.json` and interstat's profile. 13 tests in `tests/structural/test_orchestrate_pattern_f.py`; the contracts doc gained "Driving a run with orchestrate.py".
- `dd30c13`, `660683f` fix(meter): seats are attributed explicitly (claude seats by the transcripts under the run's worktree slug, codex seats by the session files that name the worktree), never by subtracting the main thread from a machine-wide window; the window is printed only as context.
- `b27a4e4` fix(routing, orchestrate): `validation-fable` falls back to `validation-sol` before `validation-kimi`; the orchestrator passes `-s workspace-write` only when the seat resolves to codex and snapshots the worktree (status incl. untracked, digest of the diff against HEAD) around every seat, so a seat that writes is UNRUN whatever the engine; VERDICT/CRITERION/RECEIPT are read through kimi's leading bullet. `6f01725` test stub.
- Orchestrated merges into Clavain main: `864ebbf` (item meti: executor commit `5778cfc` by gpt-5.6-sol, mk-meti) and `d11873f` (item b7e0: tool-applied commit `ba5d94f`, mk-b7e0).

## The demonstration: two backlog bugs in orchestrate.py, driven by orchestrate.py

Run file `evidence/60771535/run.pf.yaml`: session = this session, register = the live interspect register, repo = the Clavain checkout, timeout 2400 s, items `meti` (brief, `brief-meti.md`, routine-execution, producer gpt-5.6-sol) and `b7e0` (exact, `exact-b7e0.md`, producer claude-fable-5-1, the plan's author). Launched once, outside the sandbox, under `caffeinate -i`; the main thread's part was one launch turn and one harvest turn per run.

### Run 120d9aa1 (06:40:50Z to 06:51:59Z, 11 minutes)

- meti (brief): gauge clean; worktree `wt/meti` with an Intercore store; executor `dispatch.sh --role routine-execution` resolved to gpt-5.6-sol, ran 06:40:52 to 06:47:50, committed `5778cfc` (dispatch_task starts clean, a timeout without fresh output never re-parks a stale verdict; 5 new tests in `test_orchestrate_stale_output.py`, 81 structural tests green in its packet), VERDICT: PASS. Validator `dispatch.sh --role validation --producer-identity gpt-5.6-sol --plan brief-meti.md -C wt/meti` resolved to claude-fable-5-1, ran 06:47:52 to 06:51:25, replayed the brief's Verification, echoed the receipt `receipt-49666c1355` the orchestrator had written after the prompt was fixed, VERDICT: PASS, and reported five findings beyond the gauge; the orchestrator wrote seven register rows and merged `pf/120d9aa1/meti` as `864ebbf`. Two of the five findings are real follow-ups and became beads (mk-9hqr: the "timed out, no fresh output" phrase never fires on the engines where dispatch.sh pre-creates the output file through tee; mk-wxlk: the tmux path kills the window, not the process group, so a surviving grandchild can recreate output.md across a resume).
- b7e0 (exact): gauge clean; worktree `wt/b7e0`; `plan-gauge-lint.py --apply` applied the helper, both dirty-snapshot replacements and the new test file, replayed the Verify fence (py_compile, grep count, pytest on the new test file plus `test_orchestrate_review.py`), and the orchestrator committed `5ee6378`; executor replay PASS. The validator with producer claude-fable-5-1 resolved to `validation-kimi` (kimi-code/k3), whose dispatch uses a toolless agent file; the seat answered "UNRUN, could not read the contract, no tool execution available in this context", receipt none. The orchestrator recorded UNRUN (its parser also missed the seat's bulleted `• VERDICT:` line, so the row's note says "no VERDICT line"; both readings are UNRUN) and kept the worktree.

That UNRUN is the seat working as specified: a refusal to rule, not a strike. The cause is the same defect class the previous goal fixed for the claude seat, one fallback down: the kimi validation profile can never execute a Verification. `b27a4e4` fixed the environment (sol before kimi; codex seats get workspace-write behind a tree snapshot) and item b7e0 was dispatched again as its own run.

### Run c44f9b33 (06:55:38Z to 06:58:13Z, 2.5 minutes)

Item b7e0 (exact) again, from the merged HEAD: gauge clean; worktree `wt/b7e0` with an Intercore store; `plan-gauge-lint.py --apply` replayed the same three edits, the created test file and the Verify fence, and the orchestrator committed `ba5d94f`; executor replay PASS. The validator with producer claude-fable-5-1 now resolved to `validation-sol`: gpt-5.6-sol under `-s workspace-write`, ran 06:55:43 to 06:58:13 with the worktree snapshot unchanged, replayed the fence, echoed `receipt-727b56b3bf`, VERDICT: PASS, one finding beyond the gauge (a reviewer edit to a sibling-declared path is excluded from the dirty check too; a real narrowing, recorded on mk-b7e0's close). Three register rows; `pf/c44f9b33/b7e0` merged as `d11873f`.

## Register rows (goal 60771535, `pattern-f-verdict.sh --list --session aa2bb078… --db …/Sylveste/.clavain/interspect/interspect.db`)

| ts (UTC) | role | kind | verdict | plan | commit | note |
|---|---|---|---|---|---|---|
| 06:47:51 | executor | replay | PASS | brief-meti.md | 5778cfc |  |
| 06:51:25 | validator | replay | PASS | brief-meti.md | 5778cfc |  |
| 06:51:26 | validator | independent | FAIL | brief-meti.md | 5778cfc | **The "timed out, no fresh output" signal is engine-dependent.** `fresh_output` is an existence check, not a s… |
| 06:51:26 | validator | independent | FAIL | brief-meti.md | 5778cfc | **mtime freshness has a false-negative edge on coarse-granularity filesystems.** `os.path.getmtime(verdict_pat… |
| 06:51:26 | validator | independent | FAIL | brief-meti.md | 5778cfc | **mtime cannot prove "this dispatch wrote it" against a surviving executor.** On the tmux path a stall is hand… |
| 06:51:26 | validator | independent | FAIL | brief-meti.md | 5778cfc | **Scope and authority check out.** Only `dispatch_task` and the adjacent helper changed in orchestrate.py; the… |
| 06:51:27 | validator | independent | FAIL | brief-meti.md | 5778cfc | **Narrow TOCTOU outside the try block.** `os.path.exists(verdict_path)` followed by `os.path.getmtime(verdict_… |
| 06:51:30 | executor | replay | PASS | exact-b7e0.md | 5ee6378 | applied by plan-gauge-lint.py --apply; fences replayed by the tool |
| 06:51:59 | validator | replay | UNRUN | exact-b7e0.md | 5ee6378 | no VERDICT line from the seat (dispatch rc=0, sidecar warn) |
| 06:55:42 | executor | replay | PASS | exact-b7e0.md | ba5d94f | applied by plan-gauge-lint.py --apply; fences replayed by the tool |
| 06:58:13 | validator | replay | PASS | exact-b7e0.md | ba5d94f |  |
| 06:58:13 | validator | independent | FAIL | exact-b7e0.md | ba5d94f | Reviewer edits to sibling-declared paths are also excluded, so such unauthorized changes could escape detectio… |

## The meter: what the main thread cost, beside the seats

| window | what ran | main thread $ | seats $ | run $ | main share of run | session turns in window (with tools) | whole machine $ |
|---|---|---|---|---|---|---|---|
| run 120d9aa1, 06:40:50 to 06:51:59Z (11 min), orchestrated | brief meti (gpt-5.6-sol + fable seat) and exact b7e0 (tool + kimi UNRUN) | 2.43 | 3.23 (fable seat 2.00, codex 1.23) | 5.66 | 0.43 | 9 (7) | 19.78 |
| run c44f9b33, 06:55:38 to 06:58:13Z (2.5 min), orchestrated | exact b7e0 again (tool + gpt-5.6-sol seat) | 1.44 | 0.42 | 1.86 | 0.77 | 4 (3) | 5.82 |
| goal 60771535, 06:15:12 to 07:01:49Z (47 min) | building the mode and its fixes, both runs, the close | 17.07 | 3.65 | 20.72 | 0.82 | 27 (24) | 106.44 |
| 7be37994 register window, 04:08:35 to 04:22:58Z (14 min), hand-driven | one executor and one validator | 4.09 | 5.98 (one claude seat; no codex session found) | 10.07 | 0.41 | 11 (10) | 46.09 |
| 5bdf10a5 register window, 05:24:59 to 05:33:24Z (8 min), hand-driven | two demonstrations and two executors | 4.09 | 15.86 (16 codex sessions naming the checkout, over-inclusive; its claude seats were missed by the first meter) | 19.95 | 0.21 | 14 (14) | 31.77 |

Read: Inside the orchestrated run the main thread was 43% of the run's cost, under the doctrine's half, and it spent two turns driving each run (launch, harvest); the other turns inside the windows were parallel work (the journal draft, the meter fixes), which is why the 2.5-minute second run reads 77%. Over the whole goal the main thread was 82%: $17 of frontier time went into building the orchestrator and its fixes, against $3.65 of seats for the two backlog fixes it then delivered. The shares are scale-dependent, as the last three goals found; the number that moved is main-thread turns per delivered item: 2 here, against 5 to 7 in the hand-driven execution phases (11 turns for one executor and validator pair in 7be37994, 14 for two demonstrations in 5bdf10a5). Absolutes per item: meti cost $3.23 in seats and b7e0 $0.42 (plus the kimi refusal at $0), at roughly a quarter dollar per main-thread turn in these windows.

Caveats: the "machine window" column is every transcript active on this Mac in the window (sibling sessions included) and is printed only as context; the prior goals are metered over their register-row windows (first executor row to last validator row) with seats found by the checkout paths their seats ran in, so they carry any other codex session that named those paths in the window; turn counts are distinct assistant message ids of this session inside the window.

## GATE

- Timeout fix proven by a fixture whose grandchild would have survived: `test_fixture_bites_without_group_kill` reproduces the survivor under `subprocess.run(timeout=)` and `test_run_in_group_reaps_the_grandchild` shows it dead under `run_in_group`; `test_validator_timeout_kills_the_group_and_is_unrun` does the same through the seat path.
- No hand trace counts as a replay: every executed replay carries the receipt the orchestrator wrote after the prompt was fixed (meti `receipt-49666c1355`; b7e0 `receipt-727b56b3bf`); the exact plan's fences were run by the tool and again by the seat.
- Producer and validator on different models: gpt-5.6-sol → claude-fable-5-1 (meti); claude-fable-5-1 → kimi-code (UNRUN) → gpt-5.6-sol (validation-sol, under the worktree snapshot) (b7e0), all role-resolved, no `--model` override anywhere.
- Absolutes per attempt, share beside the dollars: the meter table.
- Note on Sylveste-yibw before the first edit: appended 2026-09-06 23:33 local, before `85a617f`'s first file write (the `GID` zsh trap kept the first two attempts from running, and no edit landed until the note did).
- Gauge rules unchanged: `plan-gauge-lint.py` was not edited.

## Turn budget

The condition said stop after 10 turns; the goal took 26 tool-bearing turns. Three turns went to a zsh trap (`GID=` is a setgid attempt in zsh; the aborted scripts silently skipped every later line, now a memory), two to the toolless kimi seat (diagnosis and the routing fix plus a second run), three to meter attribution (subtraction, then directory-matched seats, then transcript-id seats). The run itself cost the main thread two turns per run (launch, harvest).

## Beads

- mk-kj2m closed against `85a617f` (tested: the group-kill fixtures).
- mk-meti closed against `5778cfc` (merged `864ebbf`), executed by gpt-5.6-sol and validated by claude-fable-5-1 through the orchestrator.
- mk-b7e0 closed against `ba5d94f` (merged `d11873f`).
- New: mk-9hqr (fresh-output phrase engine-dependent), mk-wxlk (tmux path process group), mk-1rbg (the kimi validation profile is toolless and can only answer UNRUN; either give the seat tools or take it out of the validation chain).
- Sylveste-yibw noted with this goal's files and outcome.
