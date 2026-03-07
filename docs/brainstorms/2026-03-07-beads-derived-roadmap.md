# Brainstorm: Make roadmap.json beads-derived

**Bead:** iv-iqrv6 (P2, task)
**Date:** 2026-03-07

---

## Current State

`sync-roadmap-json.sh` (700 lines) generates `docs/roadmap.json` by:
1. Scanning module directories for `docs/roadmap.md` or `docs/roadmap.json`
2. Parsing markdown/JSON items with regex matching
3. Scanning the root roadmap (`demarch-roadmap.md`) and `docs/backlog.md` for interverse-level items
4. Assembling module metadata (version, location, roadmap source)
5. Computing cross-module dependencies
6. Writing a unified JSON output

The problem: the script parses *markdown files* to discover roadmap items. When docs change structure (like the iv-ey5wb backlog split), the script breaks. The source of truth for items is beads, but the script reads markdown intermediaries.

## What bd list --json Provides

Fields: `id`, `title`, `description`, `status`, `priority`, `issue_type`, `owner`, `labels`, `dependency_count`, `dependent_count`, `created_at`, `updated_at`.

Key constraints:
- **Module attribution:** Only 11/700+ beads have `mod:` labels. Most use `[module]` prefix in title (e.g., `[intercore]`, `[clavain/interphase]`). A parser must extract module from title brackets.
- **Phase mapping:** Priority maps to phase: P0-P1 = now, P2 = next, P3-P4 = later.
- **Blocked-by:** Available via `dependency_count` but not as bead IDs. Would need `bd show` per bead for actual dependency IDs — expensive for 700+ beads.
- **No version info:** bd doesn't track module versions. Still need filesystem scan for that.
- **No module directory locations:** bd doesn't know where modules live on disk.

## Design Options

### Option A: Pure bd-derived (replace everything)
Replace the entire script with `bd list --json | jq` pipeline. Drop module metadata, cross-deps, version tracking.

**Pro:** Simple, single source of truth.
**Con:** Loses module metadata (versions, locations, roadmap coverage) that interwatch and other consumers use. The roadmap.json schema would break for downstream consumers.

### Option B: Hybrid — items from bd, metadata from filesystem
Keep the module scanning portion (versions, locations, roadmap coverage tracking) but replace the *item collection* with `bd list --json`. Items come from beads; module metadata comes from filesystem scan.

**Pro:** Items are always fresh (beads are the source of truth). Module metadata still available. Schema stays compatible.
**Con:** Still need the filesystem scan portion (~200 lines). Module assignment needs heuristic parsing of `[module]` prefixes from bead titles.

### Option C: Incremental — add bd as primary source, keep markdown as fallback
Add `bd list --json` as the *first* source for items. If a bead is already found via bd, don't also parse it from markdown. Keep markdown parsing as a fallback for items not in beads (synthetic items, roadmap-only entries).

**Pro:** Backward compatible. Gradual migration. No downstream breakage.
**Con:** More complexity, two data sources. Harder to reason about which source won.

## Recommendation

**Option B (Hybrid).** The script does two distinct things: (1) collect roadmap items and (2) collect module metadata. These should use different sources:
- Items → `bd list --json` (single source of truth, always fresh)
- Module metadata → filesystem scan (versions, locations, roadmap coverage)

The module assignment heuristic: parse `[module]` from title, fall back to `mod:` label, fall back to "unassigned".

The key simplification: we can delete all of `collect_markdown_items()`, `collect_json_items()`, `collect_interverse_roadmap_from_markdown()`, `collect_interverse_roadmap_from_json()`, and the backlog scanning code we just added in iv-fkjam. Replace with a single `collect_items_from_beads()` function that runs `bd list --json` and transforms the output.

## Scope Assessment

- Delete: ~350 lines (markdown/JSON item parsers)
- Add: ~80 lines (bd-based item collection + module heuristic)
- Keep: ~250 lines (module scanning, cross-deps, output assembly)
- Net: -270 lines
