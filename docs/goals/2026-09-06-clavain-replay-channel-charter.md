# Clavain replay channel: both halves real

mk approved on 2026-09-06 ("please execute the above /goal") the successor proposed at the close of goal 7be37994 (interstat one meter). The condition file beside this charter carries the goal-shaped rendering.

## Why

The Pattern F doctrine says a verdict rests on a second run, not on the executor's word. Two facts from goal 7be37994 say neither half of that channel was real. The validation seat (`scripts/dispatch.sh --role validation`, resolved to claude-fable-5-1, run as `claude -p --permission-mode dontAsk --disallowedTools Edit,Write,NotebookEdit`) could not execute a command: every pytest, uv, python3 and `bash -n` call was denied and the brief outside `-C` was unreadable, yet the seat returned `VERDICT: PASS` from a hand trace (Sylveste-soj7). And across goals 1b53da77, c60de386, c4cda02c and 7be37994 the replays were 18 of 18 PASS and carried no information, while every exact contract was applied by a model doing what a tool could do byte for byte.

## Scope

In:
- `scripts/dispatch.sh`, the claude seat: Bash allowed under dontAsk; a `--plan <path>` option whose directory becomes a readable root (`--add-dir`) and whose absence at spawn is a configuration failure; a git snapshot of the checkout before and after the run, so a mutation by the read-only seat turns the verdict sidecar into an error that names the files; `VERDICT: PASS|FAIL|UNRUN` recognised by the sidecar synthesiser.
- `scripts/pattern-f-verdict.sh`: `--verdict UNRUN`, accepted with `--kind replay` only, listed like any other row.
- `scripts/plan-gauge-lint.py --apply`: applies an exact contract's edit pairs and Create blocks in document order, runs its `## Preconditions` and `### Verify` fences from the repo root, compares each with its `Expected:` line, exits non-zero at the first mismatch, never commits.
- Tests: bats for the seat and the register; pytest for `--apply` (frozen before the executor was dispatched).
- `skills/executing-plans/references/pattern-f-contracts.md`: which contract goes to a model and which to the tool; the UNRUN verdict; the receipt line.
- Two live demonstrations against a live checkout, one brief (executor: role-resolved routine-execution; validator: the fixed seat) and one exact plan (applied by the tool; validator: the fixed seat), every verdict in the register and read back.
- Clavain published from zklw and refreshed here with a content diff; Sylveste-soj7 closed.

Out: interstat (Sylveste-y8xx stays open); the Codex executor seat; calibration and quarantine policy; orchestrate.py timeouts (mk-kj2m); the prompt-audit hunks (mk's ruling).

## Gates

1. The seat change is proven by a validator that fails a deliberately broken checkout, not by one that passes a good one.
2. No hand trace counts as a replay anywhere in the run.
3. Role-resolved dispatch; producer and validator on different models.
4. Absolutes per attempt; no share-based claim.
5. The gauge rules stay as they are.
6. Every verdict in the register with `--db` explicit and read back.

## Interpretations recorded at mint

- "The register row carrying that kind": the replay row carries the verdict value `UNRUN`; the kind stays `replay`. No new kind.
- "File mutation still disallowed": Edit, Write and NotebookEdit stay disallowed. The seat does not run under a sandbox that denies writes to the checkout: a probe on 2026-09-06 (Haiku, `--settings` sandbox with `denyWrite` on the checkout) showed the sandbox also blocks uv's cache and the test venv, so every Verification that uses `uv run` would be UNRUN. Mutation is instead detected by a git snapshot before and after the run; a changed snapshot overrides the verdict sidecar with an error naming the files and fails the dispatch.
- "Proven by a validator that fails a deliberately broken checkout": a scratch worktree of Clavain with a defect only execution reveals; the plan's Verification runs the suite and prints a nonce written to disk after the prompt was fixed; the proof is `VERDICT: FAIL` naming the failing test plus the nonce echoed back. A second run whose Verification calls a tool that does not exist must return `VERDICT: UNRUN`.
- "Exact contracts applied and replayed by tool": `--apply` requires `--repo-root`, refuses brief contracts, runs the gauge first, refuses dirty targets, runs Preconditions before any edit, and leaves the commit to the main integrator per the plan's `## Commit` section.
- Turn budget: 10 tool-bearing turns.

## Close protocol

`ic goal close begin` → verified, reflected, compounded, successor_proposed → `ic goal successor` → finish; Sylveste-soj7 closed with the Clavain commit; docs on a Sylveste worktree branch and PR (main is protected).
