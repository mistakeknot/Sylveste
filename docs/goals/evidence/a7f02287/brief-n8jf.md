# Brief: a claude role seat does not inherit the operator's user-scope settings (Sylveste-n8jf)

Contract: brief

## Objective

`scripts/dispatch.sh --to claude` runs `claude -p` with the operator's user-scope settings loaded, so a validation seat inherits the operator's output style, plugins and hooks: on goal 5bdf10a5 the seat's report ended in a star-Insight block from the explanatory output style, which polluted the register note and the packet. Measured 2026-09-07 with `claude -p --model sonnet "Which output style is active?"`: without flags the answer is `explanatory`; with `--settings '{"outputStyle":"default"}'` still `explanatory` (the style comes from an enabled plugin, not a settings key); with `--setting-sources project,local` the answer is `Default`. Make every role dispatch on the claude engine run without the operator's user-scope settings.

## Scope

One source file, `scripts/dispatch.sh`, in the claude command build (`CMD=(claude)` under `elif [[ "$ENGINE" == "claude" ]]`) and its help text; one new bats file `tests/shell/dispatch_claude_settings.bats`. Nothing else changes: the codex, kimi, flere and zaka paths, the seat snapshot, the verdict sidecar, `--claude-unsafe`.

## Constraints

- When the claude engine is dispatched through `--role` (a role-resolved seat), or whenever `--to claude` is used without `CLAVAIN_CLAUDE_KEEP_USER_SETTINGS=1`, the command carries `--setting-sources project,local` so user-scope settings (output style plugins, user hooks, user MCP servers) are not loaded. `CLAVAIN_CLAUDE_KEEP_USER_SETTINGS=1` restores today's behaviour for an operator who wants it.
- The `--dry-run` output shows the flag exactly as the real command would carry it, in the same position.
- The flag is added once, before `-p`, and never for the other engines.
- The help text (`--to, --engine` block) gains one line saying the claude seat runs with `--setting-sources project,local` and how to keep user settings.
- Bash 3.2 compatible (macOS /bin/bash); `bash -n scripts/dispatch.sh` clean.

## Authority

Commit on the current branch of the checkout you are run in (a dedicated worktree) with `git commit -F <message file> -- scripts/dispatch.sh tests/shell/dispatch_claude_settings.bats`; write the message file outside the repo. Subject: `fix(dispatch): a claude role seat runs without the operator's user-scope settings (Sylveste-n8jf)`. The body ends with these two trailer lines, verbatim: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01Xkt2xiuD4S5FGTWkUaUNdP`. No push, no tags, no other files in the commit.

## Acceptance Criteria

1. `tests/shell/dispatch_claude_settings.bats` exists with at least three tests that run `bash scripts/dispatch.sh --to claude --dry-run --prompt-file <tmp> -o <tmp>` the way `tests/shell/dispatch_claude_seat.bats` does: (a) the printed command contains `--setting-sources project,local` before `-p`; (b) with `CLAVAIN_CLAUDE_KEEP_USER_SETTINGS=1` in the environment it does not; (c) `--to codex --dry-run` output never contains `--setting-sources`.
2. `tests/shell/dispatch_claude_seat.bats` and `tests/shell/dispatch_parser.bats` pass unchanged.
3. `bash -n scripts/dispatch.sh` succeeds.

## Verification

```bash
bash -n scripts/dispatch.sh
bats tests/shell/dispatch_claude_settings.bats tests/shell/dispatch_claude_seat.bats tests/shell/dispatch_parser.bats
```

Expected: exit 0.

## Deliverables

diff or commit, checks run with outcomes, failures, unresolved questions.
