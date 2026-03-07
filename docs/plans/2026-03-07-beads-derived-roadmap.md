# Plan: Beads-derived roadmap.json

**Bead:** iv-iqrv6 | **PRD:** [docs/prds/2026-03-07-beads-derived-roadmap.md](../prds/2026-03-07-beads-derived-roadmap.md)

---

## Tasks

### Task 1: Add collect_items_from_beads() function
**File:** `scripts/sync-roadmap-json.sh`
**Action:** Add a new function after the helper functions (~line 50) that:
1. Runs `bd list --json --status=open --status=in_progress --status=blocked` to get all active beads
2. Also runs `bd list --json --status=closed` with a recency filter (last 30 days) for "recently completed" items
3. For each bead, extract:
   - `id` → item_id
   - `title` → title (strip `[module]` prefix)
   - `priority` → phase mapping: 0-1 = now, 2 = next, 3-4 = later
   - `status` → status (map bd statuses to roadmap statuses)
   - Module → extract from title `[module]` bracket or `mod:` label or "demarch"
   - `dependency_count` → if >0, mark as blocked (actual dep IDs not available from list)
4. Call `add_item()` for each bead (reuse existing helper)

### Task 2: Add extract_module_from_bead() helper
**File:** `scripts/sync-roadmap-json.sh`
**Action:** Add a function that takes a bead title and labels array, returns module name:
1. Regex match `^\[([^\]]+)\]` from title → extract module name
2. If no bracket match, check labels for `mod:*` → strip prefix
3. Fallback: "demarch"

### Task 3: Delete markdown/JSON item parsers
**File:** `scripts/sync-roadmap-json.sh`
**Action:** Delete these functions:
- `collect_markdown_items()` (lines ~208-301)
- `collect_json_items()` (lines ~303-349)
- `collect_research_json()` (lines ~351-360)
- `collect_interverse_roadmap_from_json()` (lines ~390-426)
- `collect_interverse_roadmap_from_markdown()` (lines ~428-498, including backlog scan)

### Task 4: Update main loop to use beads
**File:** `scripts/sync-roadmap-json.sh`
**Action:** In the main module scanning loop (lines ~550-611):
- Keep module metadata collection (version, location, roadmap source detection)
- Remove calls to `collect_markdown_items()` and `collect_json_items()`
- After the module loop, call `collect_items_from_beads()` once (replaces all per-module item parsing)
- Remove the `collect_interverse_roadmap_from_json/markdown` calls (lines ~613-615)

### Task 5: Verify output compatibility
**Action:** Run the script and compare old vs new `roadmap.json`:
- Same top-level keys
- Reasonable item counts (beads may have more/fewer items than markdown-parsed)
- Module metadata (versions, locations) still present
- No JSON schema changes

## Sequence

Task 2 first (helper), then Task 1 (uses helper), then Task 3 (delete old), then Task 4 (rewire main loop), then Task 5 (verify).

## Verification
- [ ] `bash -n scripts/sync-roadmap-json.sh` passes
- [ ] Script runs without error
- [ ] roadmap.json has items from beads
- [ ] Module metadata still present
- [ ] No markdown parsing functions remain
