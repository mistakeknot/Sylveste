# Plan: intermem tidy — automatic structural tidy for memory files

**Bead:** iv-d1mcu
**PRD:** docs/prds/2026-03-01-intermem-tidy-prd.md
**Date:** 2026-03-01

## Steps

### Step 1: Add `tidy.py` — core tidy logic

**File:** `interverse/intermem/intermem/tidy.py`

Implement two functions:

**`tidy_memory(memory_dir, budget=120, section_threshold=15, apply=False) -> TidyResult`**
- Read MEMORY.md (if it exists, else return empty result)
- Count lines. If under budget, return early with `under_budget=True`
- Parse into sections (section name → line range → content)
- Protected sections: `Quick Reference`, `Topic Files` — never extract
- Score remaining sections by line count descending
- For each section exceeding `section_threshold`:
  - Slugify name: lowercase, replace spaces with hyphens, strip non-alnum
  - Check if `<slug>.md` already exists in memory_dir → skip if so
  - If `apply`: write `<slug>.md` with `# <Section Name>\n\n<content>`
  - Record extraction in result
- If `apply`: rewrite MEMORY.md with extracted sections replaced by links in `## Topic Files`
- If `## Topic Files` section doesn't exist, create it before the first non-protected section
- Return `TidyResult` with extractions list, stale counts, new line count

**`detect_stale_counts(memory_dir) -> list[StaleCount]`**
- Scan all `.md` files for patterns: `\d+ (plugins|commands|skills|tests|files|modules|tools|agents|hooks|servers|projects)`
- For file/directory-countable patterns (heuristic: check if a matching directory exists in the project), count actual files
- Return list of `StaleCount(text, stored_count, actual_count, source_file, line_number, verifiable)`

**Dataclasses:**
```python
@dataclass
class Extraction:
    section: str
    slug: str
    line_count: int
    skipped: bool  # True if topic file already exists

@dataclass
class StaleCount:
    text: str
    stored_count: int
    actual_count: int | None  # None if not verifiable
    source_file: str
    line_number: int

@dataclass
class TidyResult:
    memory_file: str
    total_lines: int
    budget: int
    under_budget: bool
    extractions: list[Extraction]
    stale_counts: list[StaleCount]
    new_line_count: int  # projected lines after extraction
```

### Step 2: Add `tidy` subcommand to `__main__.py`

**File:** `interverse/intermem/intermem/__main__.py`

- Add `tidy` subparser with args: `--budget` (default 120), `--section-threshold` (default 15), `--apply`
- Handler calls `tidy_memory()` and `detect_stale_counts()`
- Output: dry-run preview showing extractions and stale counts
- With `--apply`: execute extractions and report results
- JSON output when `--json` is passed

### Step 3: Add `/intermem:tidy` skill

**Directory:** `interverse/intermem/skills/tidy/SKILL.md`

Skill instructions for running the tidy CLI:
- How to find INTERMEM_DIR and run `uv run python -m intermem tidy`
- Dry-run first, then `--apply` after user review
- Explain what each output means

**File:** `interverse/intermem/.claude-plugin/plugin.json`

Register the new skill: add `"./skills/tidy"` to the skills array.

### Step 4: Add SessionStart nudge

**File:** `interverse/intermem/hooks/session-start.sh`

After existing interbase setup, add:
- Find project memory dir (same logic as `_find_memory_dir` but in bash)
- Count MEMORY.md lines with `wc -l`
- If exceeds budget (120): print `"intermem: MEMORY.md is N lines (budget: 120). Run /intermem:tidy to review."`

### Step 5: Write tests

**File:** `interverse/intermem/intermem/tests/test_tidy.py`

Test cases:
- Under-budget file returns early
- Section extraction when over budget
- Protected sections are never extracted
- Existing topic files are skipped (not clobbered)
- Topic Files section is created when missing
- Topic Files section is appended to when exists
- Dry-run doesn't modify files
- Apply mode writes files and rewrites MEMORY.md
- Stale count detection with verifiable and unverifiable patterns
- Slugification edge cases (special chars, unicode)
- Empty MEMORY.md
- MEMORY.md with only protected sections

### Step 6: Update CLAUDE.md

**File:** `interverse/intermem/CLAUDE.md`

Add tidy to quick reference and architecture sections.
