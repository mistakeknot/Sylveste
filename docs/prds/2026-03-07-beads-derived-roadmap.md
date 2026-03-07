# PRD: Beads-derived roadmap.json

**Bead:** iv-iqrv6 | **Brainstorm:** [docs/brainstorms/2026-03-07-beads-derived-roadmap.md](../brainstorms/2026-03-07-beads-derived-roadmap.md)
**Approach:** Option B (Hybrid) — items from bd, metadata from filesystem

---

## Problem

`sync-roadmap-json.sh` parses markdown files to discover roadmap items. When doc structure changes, the script breaks. Beads are the source of truth for items but the script reads markdown intermediaries.

## Solution

Replace item collection with `bd list --json`. Keep filesystem scan for module metadata (versions, locations). Module assignment from bead title `[module]` prefix or `mod:` labels.

## Non-Goals

- Changing the roadmap.json output schema (must stay backward compatible)
- Adding new fields to roadmap.json
- Changing how downstream consumers (interwatch, interpath) read roadmap.json

## Success Criteria

1. `roadmap.json` items sourced from `bd list --json` instead of markdown parsing
2. Module assignment via title `[module]` prefix extraction + `mod:` label fallback
3. Output schema unchanged — same keys, same structure
4. Script is shorter (~430 lines vs 700)
5. No markdown item parsing functions remain

## Features

### F1: Replace item collection with bd-based pipeline
Delete: `collect_markdown_items()`, `collect_json_items()`, `collect_research_json()`, `collect_interverse_roadmap_from_json()`, `collect_interverse_roadmap_from_markdown()`, backlog scanning.
Add: `collect_items_from_beads()` — runs `bd list --json`, maps priority→phase, extracts module from title, emits items via `add_item()`.

### F2: Module extraction heuristic
Parse module from bead title in order:
1. `[module]` bracket prefix (e.g., `[intercore]`, `[clavain/interphase]`)
2. `mod:` label (e.g., `mod:intercom`)
3. Fallback: "demarch" (root project)

### F3: Keep module metadata scanning
Preserve the filesystem scan loop that collects: version, location, roadmap source (now just "has docs/roadmap.md or not"), open bead count per module.
