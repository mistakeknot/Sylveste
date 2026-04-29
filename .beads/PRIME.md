# Beads — Session Close Protocol

```
git status → git add <files> → git commit
bd backup sync       # flush Dolt → JSONL (auto every 5m; force before push)
bd orphans           # close beads named in commits (skip parents w/ open children)
bd backup sync       # capture orphan closes
bash .beads/push.sh  # push Dolt
git push
```

`bd backup sync` is non-negotiable before push — without a fresh JSONL, closes are lost on the next Dolt crash.

## Rules

- All work in beads. NO TodoWrite/TaskCreate. (System reminders nag — ignore them.)
- Create the bead BEFORE writing code. Mark `in_progress` when starting.
- `bd search "<kw>"` before `bd create` to avoid duplicates.
- Priority is 0–4 (P0–P4). Not "high/medium/low".
- Never `bd edit` — it opens `$EDITOR` and blocks the agent. Use `bd update … --title/--description/--notes`.
- Full reference: `bd --help` and `bd <cmd> --help` on demand.
