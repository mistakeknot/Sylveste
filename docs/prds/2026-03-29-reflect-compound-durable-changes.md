---
artifact_type: prd
bead: sylveste-b49
stage: design
---

# PRD: Durable Reflect & Compound

## Problem

Sprint learnings written to `docs/reflections/` and `docs/solutions/` are dead files with no automated consumers. Future sessions don't behave differently because nothing loads these files. The 7-step engineering-docs workflow is heavyweight ceremony for what should be a simple "where does this learning belong?" routing decision.

## Solution

Replace the "write a reflection document" pattern with a "route each learning to its durable target" pattern. Each learning is classified and written to the location where it will actually influence future behavior: CLAUDE.md, auto-memory, code/config, or hooks.

## Features

### F1: Rewrite reflect command to produce durable changes
**What:** Replace the reflection-file workflow with a learning router that classifies each insight and writes it to the appropriate target.
**Acceptance criteria:**
- [ ] Reflect extracts 1-5 learnings from the sprint
- [ ] Each learning is classified into a target: `claude-md`, `agents-md`, `memory`, `code`, `hook`, `philosophy`
- [ ] Each learning is written to its target (e.g., appended to CLAUDE.md, written as memory file, added as code comment)
- [ ] The ship gate checks for at least 1 durable change (git diff shows modified target file) instead of a reflection file
- [ ] No standalone `docs/reflections/` file is produced (or it's optional archive only)

### F2: Rewrite compound to patch the codebase
**What:** Replace the solutions-file workflow with targeted code/doc patches.
**Acceptance criteria:**
- [ ] Compound identifies what was learned (root cause, fix, prevention)
- [ ] Output is written to the point of use: code comment near the fix, CLAUDE.md warning, AGENTS.md gotcha, or config change
- [ ] No standalone `docs/solutions/` file is the primary output
- [ ] Engineering-docs 7-step workflow is no longer invoked by compound (reserved for manual deep documentation only)

### F3: Update sprint.md to use new reflect gate
**What:** Change Step 9 and Step 10 to work with durable changes instead of reflection files.
**Acceptance criteria:**
- [ ] Step 9 invokes updated reflect command
- [ ] Step 10 gate checks for durable changes (at least 1 target file modified) instead of reflection file line count
- [ ] `recent-reflect-learnings` reads from CLAUDE.md/memory instead of reflection files

## Non-goals

- Migrating existing docs/reflections/ or docs/solutions/ files
- Changing the interwatch/drift-check steps in reflect
- Changing cost/routing calibration steps in reflect

## Dependencies

- os/Clavain/commands/reflect.md (the reflect command)
- os/Clavain/commands/compound.md (the compound command)
- os/Clavain/commands/sprint.md (sprint Step 9 + Step 10)
- os/Clavain/cmd/clavain-cli/stats.go (recent-reflect-learnings)
