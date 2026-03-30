---
id: "005"
status: open
priority: P2
title: "Audit all Interverse skills/commands for text input support"
created: 2026-03-30
---

## Problem

flux-drive/flux-review rejected inline text input ("options/alternatives") because the input detection only handled file/directory/diff paths. This was fixed for interflux, but the same pattern likely exists in other skills and commands across Interverse.

## Scope

Audit all skills and commands in `interverse/` that accept file/path arguments and ensure they gracefully handle inline text input where it makes sense. Not every command needs text input (e.g., a linter that reads files), but any command designed for analysis, review, or exploration should accept it.

## Checklist

- [ ] Grep for `INPUT_TYPE.*file.*directory.*diff` and similar path-only detection patterns across all SKILL.md and command .md files
- [ ] Grep for "ask for one using AskUserQuestion" / "path is empty" — these are the rejection points
- [ ] For each match, assess: does this command make sense with inline text input?
- [ ] Add `text` input type where appropriate
- [ ] Ensure cognitive/analytical agents are not filtered out for text inputs
- [ ] Test at least 3 remediated commands with inline text

## Fixed So Far

- `interverse/interflux/skills/flux-drive/SKILL.md` — added INPUT_TYPE = text
- `interverse/interflux/skills/flux-drive/SKILL-compact.md` — same
- `interverse/interflux/commands/flux-review.md` — accepts text, triages to 4 tracks
