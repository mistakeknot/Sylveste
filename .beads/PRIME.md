# Beads Workflow Context

> Run `bd prime` after compaction/clear to restore this context.

# 🚨 SESSION CLOSE PROTOCOL — REQUIRED BEFORE "DONE"

```
1. git status                       # see what changed
2. git add <files>                  # stage — NEVER git add .
3. bd backup                        # flush Dolt → JSONL (survives crashes)
4. git commit -m "..."              # commit
5. bd orphans                       # close beads named in commits (skip parents w/ open children)
6. bd backup                        # capture orphan closes
7. bash .beads/push.sh              # push Dolt to remote
8. git push                         # push git
```

`bd backup` is non-negotiable — without it, closes are lost on the next Dolt crash. Work is not done until pushed.

## Core Rules
- Track ALL work in beads. NO TodoWrite / TaskCreate / markdown-based task lists.
- Create the bead BEFORE writing code. Mark `in_progress` when you start.
- `bd search "<kw>"` before `bd create` to avoid duplicates.
- Priority is 0–4 (or P0–P4). Not "high/medium/low".
- Do NOT run `bd edit` — opens $EDITOR and blocks the agent. Use `bd update … --title/--description/--notes`.

## Command reference

Everything else (create/update/dep/sync/doctor/stats/close-multi/workflow examples) is in `bd --help` and `bd <cmd> --help`. Look it up on demand — don't memorize it from this preamble.
