---
module: dotfiles
date: 2026-03-04
problem_type: concurrency_pattern
component: hooks
symptoms:
  - "Concurrent agent edits on Mac and server silently lose data via Mutagen last-write-wins"
  - "Agent starts session with stale code from other machine"
  - "No conflict detection when two agents edit the same file"
root_cause: mutagen_last_write_wins
resolution_type: pattern
severity: high
tags: [git, mutagen, multi-agent, hooks, debounce, locking, autosync, shell, concurrency]
lastConfirmed: 2026-03-04
provenance: independent
review_count: 0
---

# Git Autosync: Coordination Layer for Concurrent Multi-Agent Development

## Problem

Multiple Claude Code agents work concurrently in the same monorepo — some on the Mac laptop, some on the ethics-gradient server. Mutagen bidirectionally syncs the projects directory, providing real-time file visibility. However, Mutagen uses **last-write-wins** for conflict resolution: concurrent edits to the same file silently discard one side's changes.

This is invisible to agents — no error, no warning, no merge conflict. Work simply disappears.

## Solution

Layer **git as the coordination mechanism** on top of Mutagen's file sync. Claude Code hooks automatically commit and push after every file edit, and pull at session start. Git's three-way merge handles conflicts properly. The system is opt-in per repo via a `.git-autosync` marker file.

### Architecture

Two hooks registered in `~/.claude/settings.json`:

1. **PostToolUse** (`git-autosync.sh`, async) — fires on Edit/Write, debounces, commits, pushes
2. **SessionStart** (`git-autosync-pull.sh`, sync) — fires on session start, pulls with rebase

### Key Design Patterns

#### Token-Based Debounce (No External Tools)

Rapid Edit/Write calls (common in agent sessions) would produce N commits without debouncing. The approach: write a unique token to `.git/autosync.trigger`, sleep, then check if the token is still current.

```bash
TOKEN="$$-$(date +%s%N)"
echo "$TOKEN" > "$TRIGGER"
sleep "$DEBOUNCE_SECS"
CURRENT=$(cat "$TRIGGER" 2>/dev/null || echo "")
if [[ "$CURRENT" != "$TOKEN" ]]; then
  exit 0  # superseded by newer invocation
fi
```

If another hook invocation wrote a newer token during the sleep, this one exits — the newer one handles the commit. No external dependencies, no daemons, works cross-platform.

#### mkdir as Atomic Lock

`flock` is Linux-only. `mkdir` is atomic on POSIX filesystems — it either succeeds or fails with no TOCTOU race:

```bash
LOCKDIR="$REPO_ROOT/.git/autosync.lockdir"
while ! mkdir "$LOCKDIR" 2>/dev/null; do
  # check for stale lock (>60s), wait up to 15s
done
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT
```

Stale lock detection uses platform-aware `stat` (Darwin vs Linux have different flags: `-f %m` vs `-c %Y`).

#### All State in .git/

Lock, trigger, and log files all live in `.git/`:
- `.git/autosync.lockdir` — atomic lock
- `.git/autosync.trigger` — debounce token
- `.git/autosync.log` — audit trail

This directory is excluded from both Mutagen sync and git tracking, preventing the coordination metadata from causing its own sync conflicts (a meta-circularity problem).

#### Push-Retry with Auto-Rebase

On push failure (concurrent push from another agent), the hook pulls with rebase and retries:

```bash
if ! git push origin "$BRANCH"; then
  git pull --rebase --autostash origin "$BRANCH"
  git push origin "$BRANCH"  # retry
fi
```

Up to MAX_RETRIES attempts. `--autostash` preserves any uncommitted work during rebase.

#### Fail-Silent Contract

All failures exit 0 — the hook must never disrupt the agent's work. Errors are logged to `.git/autosync.log` for debugging but never surface to the agent.

### Opt-In via Marker File

Repos opt in by creating `.git-autosync` in the repo root (committed to git so both machines see it). The marker is sourced as bash, allowing per-repo config overrides:

```bash
# .git-autosync
DEBOUNCE_SECS=3
MAX_RETRIES=2
```

## Trade-Offs

- **Noisy history**: `chore(sync):` commits accumulate. Squash manually if needed.
- **`git add -A` is aggressive**: First commit in a dirty repo sweeps up all untracked files.
- **`--no-verify` skips pre-commit hooks**: Intentional — autosync shouldn't block on linters.
- **Not a replacement for intentional commits**: Session close protocol still applies for meaningful milestones.

## Cross-References

- `~/.claude/hooks/git-autosync.sh` — PostToolUse hook (canonical: `dotfiles/common/.claude/hooks/`)
- `~/.claude/hooks/git-autosync-pull.sh` — SessionStart hook
- `agents/session-protocol.md` § "Git Autosync" — agent-facing documentation
- `Sylveste/.git-autosync` — first opt-in repo
