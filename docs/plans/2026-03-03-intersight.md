# intersight Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Goal:** Build the intersight Interverse plugin — automated UI/UX design analysis that extracts W3C DTCG tokens, component inventories, and layout analysis from any URL.

**Architecture:** Hybrid skill + JS extraction scripts. SKILL.md orchestrates a 7-phase pipeline (preflight → setup → Dembrandt → DOM extraction → structural analysis → visual analysis → interaction states → synthesis). 9 focused JS scripts run via Playwright MCP's `browser_evaluate`. Dembrandt CLI provides baseline token extraction. intercache provides optional caching.

**Tech Stack:** JavaScript (browser_evaluate scripts), Bash (bump-version.sh), Python (structural tests), Markdown (SKILL.md orchestration), W3C DTCG 2025.10 (output schema), Dembrandt v0.6.1 (npm CLI), Playwright MCP (browser automation)

**Review Findings (flux-drive plan review, 3 agents):**
- P0 FIXED: robots.txt parser rewritten — matches path prefixes, accepts target path param, fail-closed on errors
- P0 FIXED: contentHash.js — replaced `innerHTML.length` with stylesheet-structural data (rule count, property names, sheet hrefs)
- P0 FIXED: extractCSSCustomProperties.js — inverted priority: `getComputedStyle` authoritative, stylesheet walk for source only; added `resolvedValue`/`authoredValue` for `var()` cross-referencing
- P0 FIXED: SPA quiescence wait + challenge page detection added to Phase 1 in SKILL.md notes
- P0 FIXED: Phase 7 merge algorithm specified (custom props primary, computed fills gaps, Dembrandt names, multi-page conflicts explicit)
- P1 FIXED: intercache detection via try/catch, Dembrandt preflight check, output written to local file, error message templates specified
- P1 FIXED: schema.json — added `dembrandt_available`, `phases_completed`, `warnings` to intersight:meta
- P2 DEFERRED: spacing sort order (intentional ascending-by-value for scale presentation), multi-page F9 scope, dark mode detection, font source URLs

**Prior Learnings:**
- `docs/solutions/integration-issues/graceful-mcp-launcher-external-deps-interflux-20260224.md` — External dependencies must fail gracefully with clear install instructions. Do NOT let Dembrandt/npx failures crash the skill mid-execution.
- `docs/solutions/integration-issues/plugin-validation-errors-cache-manifest-divergence-20260217.md` — Every path in plugin.json must exist on disk. Skills must be `skills/name/SKILL.md`, never flat files. Do NOT declare hooks in plugin.json (auto-loaded).
- `docs/canon/plugin-standard.md` — Canonical plugin structure: 6 required root files, `.claude-plugin/plugin.json`, `skills/` subdirs, `tests/structural/`, `scripts/bump-version.sh`.

---

### Task 1: Plugin Scaffold — Directory and Required Files

**Files:**
- Create: `interverse/intersight/.claude-plugin/plugin.json`
- Create: `interverse/intersight/CLAUDE.md`
- Create: `interverse/intersight/AGENTS.md`
- Create: `interverse/intersight/PHILOSOPHY.md`
- Create: `interverse/intersight/README.md`
- Create: `interverse/intersight/LICENSE`
- Create: `interverse/intersight/.gitignore`
- Create: `interverse/intersight/scripts/bump-version.sh`
- Create: `interverse/intersight/skills/analyze/SKILL.md` (stub — full content in Task 10)

**Step 1: Create directory structure**

```bash
mkdir -p interverse/intersight/.claude-plugin
mkdir -p interverse/intersight/skills/analyze
mkdir -p interverse/intersight/scripts/extraction
mkdir -p interverse/intersight/tests/structural
```

**Step 2: Write plugin.json**

Create `interverse/intersight/.claude-plugin/plugin.json`:

```json
{
  "name": "intersight",
  "version": "0.1.0",
  "description": "Automated UI/UX design analysis — extracts W3C DTCG tokens, component inventory, and layout analysis from any URL.",
  "author": { "name": "mistakeknot" },
  "license": "MIT",
  "keywords": ["design-tokens", "ui-analysis", "dtcg", "playwright", "design-system"],
  "skills": ["./skills/analyze"]
}
```

Note: No `mcpServers` entry — intersight uses the user's existing Playwright MCP server, not a bundled one. No `hooks` entry — Claude Code auto-loads `hooks/hooks.json` if present; declaring it in plugin.json causes duplicate registration.

**Step 3: Write CLAUDE.md**

Create `interverse/intersight/CLAUDE.md`:

```markdown
# intersight

> See `AGENTS.md` for full development guide.

## Overview

Automated UI/UX design analysis plugin — 1 skill (`analyze`), 9 JS extraction scripts, 0 MCP servers. Orchestrates Dembrandt CLI + Playwright MCP + Claude vision to extract W3C DTCG design tokens, component inventories, and layout analysis from any URL. Three depth modes: `tokens` (DOM-only), `standard` (+ screenshot), `full` (+ responsive + interactions).

## Quick Commands

```bash
# Run structural tests
cd tests && uv sync && uv run pytest -q && cd ..

# Verify plugin structure
cat .claude-plugin/plugin.json | python3 -m json.tool

# Check extraction scripts are present
ls scripts/extraction/*.js | wc -l  # expect 9
```

## Design Decisions (Do Not Re-Ask)

- No dedicated MCP server — uses Playwright MCP's browser_evaluate for all DOM extraction
- Dembrandt CLI is a hard dependency (npm) — provides 80-95% of token extraction baseline
- intercache is optional — works without it, just slower
- W3C DTCG 2025.10 output format with `intersight:*` extension namespace
- 9 focused extraction scripts (not fewer combined scripts) — modularity over fewer round-trips
- robots.txt compliance mandatory — Phase 0 checks before any extraction
```

**Step 4: Write AGENTS.md**

Create `interverse/intersight/AGENTS.md`:

```markdown
# intersight — Development Guide

## Canonical References
1. [`PHILOSOPHY.md`](./PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](./PHILOSOPHY.md) during:
- Intake/scoping
- Brainstorming
- Planning
- Execution kickoff
- Review/gates
- Handoff/retrospective

For brainstorming/planning outputs, add two short lines:
- **Alignment:** ...
- **Conflict/Risk:** ...

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.

## Quick Reference

| Field | Value |
|-------|-------|
| Repo | `interverse/intersight` |
| Namespace | `intersight` |
| Manifest | `.claude-plugin/plugin.json` |
| Skills | 1 (`analyze`) |
| Scripts | 9 JS extraction scripts |
| License | MIT |

## Release Workflow

```bash
scripts/bump-version.sh <version>
```

## Overview

**Problem:** No reusable tool for systematically extracting design systems from live websites.

**Solution:** A skill that orchestrates Dembrandt CLI, Playwright MCP, and Claude vision across a 7-phase extraction pipeline, producing W3C DTCG tokens + component inventory + layout analysis.

**Type:** Skill-only plugin (no MCP server, no hooks, no agents)

## Architecture

```
interverse/intersight/
├── .claude-plugin/plugin.json       # Plugin metadata
├── skills/analyze/SKILL.md          # Orchestration: 7-phase pipeline
├── scripts/
│   ├── bump-version.sh              # Version management
│   └── extraction/                  # JS scripts for browser_evaluate
│       ├── parseRobotsTxt.js        # Phase 0: ethics compliance
│       ├── contentHash.js           # Phase 0: cache invalidation
│       ├── extractCSSCustomProperties.js  # Phase 3
│       ├── extractColorTokens.js          # Phase 3
│       ├── extractTypography.js           # Phase 3
│       ├── extractSpacing.js              # Phase 3
│       ├── extractShadowsAndBorders.js    # Phase 3
│       ├── extractBreakpoints.js          # Phase 3
│       └── extractComponentInventory.js   # Phase 4
├── tests/structural/                # Pytest validation
└── docs/                            # Brainstorms, PRDs, plans
```

## Integration Points

| Plugin | Relationship |
|--------|-------------|
| Playwright MCP | Hard dependency — provides browser automation |
| intercache | Optional — caches analysis results per-URL |

## Testing

```bash
cd tests && uv sync && uv run pytest -q
```

## Known Constraints

- Dembrandt requires Node.js 18+ and npm/npx on PATH
- Playwright MCP must be configured in the user's Claude Code setup
- Cross-origin stylesheets cannot be parsed via CSSOM — use getComputedStyle fallback
- Screenshots are ephemeral (used for Claude vision, then discarded)
```

**Step 5: Write PHILOSOPHY.md**

Create `interverse/intersight/PHILOSOPHY.md`:

```markdown
# intersight Philosophy

## Purpose

Automated UI/UX design analysis — extracts design tokens, component inventories, and layout patterns from live websites. 1 skill, 9 extraction scripts, 0 MCP servers. Composes Dembrandt CLI + Playwright MCP + Claude vision.

## North Star

Maximize design intelligence extracted per token spent.

## Working Priorities

1. **Accuracy** — Extracted tokens must faithfully represent the target site's design system. Wrong tokens are worse than missing tokens.
2. **Composition** — Orchestrate existing tools (Dembrandt, Playwright MCP, Claude vision) rather than rebuilding. Adopt mature external tools.
3. **Cost efficiency** — Depth modes let users pay for exactly the analysis they need. DOM extraction is free; screenshots cost tokens.

## Brainstorming Doctrine

1. Start from outcomes and failure modes, not implementation details.
2. Generate at least three options: conservative, balanced, and aggressive.
3. Explicitly call out assumptions, unknowns, and dependency risk across modules.
4. Prefer ideas that improve clarity, reversibility, and operational visibility.

## Planning Doctrine

1. Convert selected direction into small, testable, reversible slices.
2. Define acceptance criteria, verification steps, and rollback path for each slice.
3. Sequence dependencies explicitly and keep integration contracts narrow.
4. Reserve optimization work until correctness and reliability are proven.

## Decision Filters

- Does this extraction produce tokens that a design tool can actually consume?
- Does this add a browser round-trip that could be avoided?
- Is the cost proportional to the value of the extracted information?
- Can this work without the optional dependency (intercache)?
```

**Step 6: Write LICENSE**

Create `interverse/intersight/LICENSE` with standard MIT license text, copyright `2026 MK`.

**Step 7: Write .gitignore**

Create `interverse/intersight/.gitignore`:

```
node_modules/
__pycache__/
*.pyc
.venv/
.pytest_cache/
.claude/
.beads/
*.log
.DS_Store
Thumbs.db
*.swp
*.swo
*~
output/
```

**Step 8: Write README.md**

Create `interverse/intersight/README.md`:

```markdown
# intersight

Automated UI/UX design analysis for Claude Code.

## What this does

intersight analyzes live websites and extracts structured design system reports in W3C Design Tokens format (DTCG 2025.10). Given a URL, it orchestrates Dembrandt CLI for baseline token extraction, Playwright MCP for deep DOM analysis, and Claude vision for layout pattern recognition.

The plugin produces three categories of output: design tokens (colors, typography, spacing, shadows, borders, breakpoints), a component inventory (repeated DOM patterns with variants and interaction states), and visual analysis (layout patterns, visual hierarchy, information density).

Three depth modes let you balance cost and comprehensiveness. The `tokens` mode extracts design tokens via DOM analysis only (~$0.02/URL). The `standard` mode adds a desktop screenshot for Claude vision layout analysis (~$0.05/URL). The `full` mode adds responsive breakpoint screenshots and interaction state extraction (~$0.10/URL).

## Installation

```bash
claude plugin add intersight
```

**Requirements:**
- Playwright MCP server configured in Claude Code
- Node.js 18+ with npm/npx on PATH (for Dembrandt CLI)

## Usage

```bash
# Basic analysis (standard depth)
/intersight:analyze https://play.grafana.org

# Tokens only (fastest, cheapest)
/intersight:analyze https://linear.app --depth tokens

# Full analysis with responsive + interactions
/intersight:analyze https://ui.shadcn.com --depth full

# Multiple pages merged
/intersight:analyze https://example.com --pages /,/dashboard,/settings

# Force fresh extraction (bypass cache)
/intersight:analyze https://example.com --fresh

# Human-readable report
/intersight:analyze https://example.com --format markdown
```

## Architecture

```
interverse/intersight/
├── .claude-plugin/plugin.json       # Plugin metadata
├── skills/analyze/SKILL.md          # 7-phase extraction pipeline
├── scripts/extraction/              # 9 JS scripts for browser_evaluate
└── tests/structural/                # Plugin validation tests
```

## Design decisions

- Composes existing tools (Dembrandt, Playwright MCP, Claude vision) — no custom MCP server
- W3C DTCG 2025.10 output format with `intersight:*` extensions for components and layout
- 9 focused extraction scripts for modularity and debuggability
- robots.txt compliance mandatory before any extraction
- intercache integration optional — works without it

## License

MIT
```

**Step 9: Write bump-version.sh**

Create `interverse/intersight/scripts/bump-version.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
if command -v ic &>/dev/null; then
    exec ic publish "${1:---patch}"
else
    echo "ic not available — use interbump.sh" >&2
    exit 1
fi
```

Make it executable: `chmod +x interverse/intersight/scripts/bump-version.sh`

**Step 10: Write stub SKILL.md**

Create `interverse/intersight/skills/analyze/SKILL.md` with minimal valid content (full orchestration in Task 10):

```yaml
---
name: analyze
description: "Analyze a website's UI/UX design system — extracts W3C DTCG tokens, component inventory, and layout patterns from any URL. Use when the user wants to study a reference site's design or extract design tokens."
user_invocable: true
argument-hint: "<URL> [--depth tokens|standard|full] [--format json|markdown|tokens-only] [--fresh] [--pages /path1,/path2]"
---
```

```markdown
# /intersight:analyze

Stub — full orchestration content will be added in Task 10.
```

**Step 11: Commit**

```bash
git add interverse/intersight/
git commit -m "feat(intersight): scaffold plugin with required files and structure"
```

---

### Task 2: Structural Tests

**Files:**
- Create: `interverse/intersight/tests/pyproject.toml`
- Create: `interverse/intersight/tests/structural/conftest.py`
- Create: `interverse/intersight/tests/structural/helpers.py`
- Create: `interverse/intersight/tests/structural/test_structure.py`
- Create: `interverse/intersight/tests/structural/test_skills.py`

**Step 1: Write pyproject.toml**

Create `interverse/intersight/tests/pyproject.toml`:

```toml
[project]
name = "intersight-tests"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["pytest>=8.0", "pyyaml>=6.0"]

[tool.pytest.ini_options]
testpaths = ["structural"]
pythonpath = ["structural"]
```

**Step 2: Write conftest.py**

Create `interverse/intersight/tests/structural/conftest.py`:

```python
"""Shared fixtures for structural tests."""

import json
from pathlib import Path

import pytest


@pytest.fixture(scope="session")
def project_root() -> Path:
    """Path to the repository root."""
    return Path(__file__).resolve().parent.parent.parent


@pytest.fixture(scope="session")
def skills_dir(project_root: Path) -> Path:
    return project_root / "skills"


@pytest.fixture(scope="session")
def scripts_dir(project_root: Path) -> Path:
    return project_root / "scripts"


@pytest.fixture(scope="session")
def plugin_json(project_root: Path) -> dict:
    """Parsed plugin.json."""
    with open(project_root / ".claude-plugin" / "plugin.json") as f:
        return json.load(f)
```

**Step 3: Write helpers.py**

Create `interverse/intersight/tests/structural/helpers.py`:

```python
"""Shared helpers for structural tests."""

import yaml


def parse_frontmatter(path):
    """Parse YAML frontmatter from a markdown file.

    Returns (frontmatter_dict, body_text) or (None, full_text) if no frontmatter.
    """
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return None, text
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None, text
    fm = yaml.safe_load(parts[1])
    body = parts[2]
    return fm, body
```

**Step 4: Write test_structure.py**

Create `interverse/intersight/tests/structural/test_structure.py`:

```python
"""Tests for plugin structure."""

import json
import os
from pathlib import Path


def test_plugin_json_valid(project_root):
    """plugin.json is valid JSON with required fields."""
    path = project_root / ".claude-plugin" / "plugin.json"
    assert path.exists(), "Missing .claude-plugin/plugin.json"
    data = json.loads(path.read_text())
    for field in ("name", "version", "description", "author"):
        assert field in data, f"plugin.json missing required field: {field}"
    assert data["name"] == "intersight"


def test_required_root_files(project_root):
    """All required root-level files exist."""
    required = ["CLAUDE.md", "PHILOSOPHY.md", "LICENSE", ".gitignore",
                "README.md", "AGENTS.md"]
    for name in required:
        assert (project_root / name).exists(), f"Missing required file: {name}"


def test_scripts_executable(project_root):
    """All shell scripts are executable."""
    scripts_dir = project_root / "scripts"
    if not scripts_dir.is_dir():
        return
    for script in scripts_dir.glob("*.sh"):
        assert os.access(script, os.X_OK), f"Script not executable: {script.name}"


def test_scripts_count(project_root):
    """Expected number of scripts (1 shell + 9 JS extraction)."""
    scripts_dir = project_root / "scripts"
    assert scripts_dir.is_dir(), "Expected scripts/ directory"
    sh_scripts = list(scripts_dir.glob("*.sh"))
    assert len(sh_scripts) == 1, (
        f"Expected 1 shell script, found {len(sh_scripts)}: {[s.name for s in sh_scripts]}"
    )
    extraction_dir = scripts_dir / "extraction"
    assert extraction_dir.is_dir(), "Expected scripts/extraction/ directory"
    js_scripts = list(extraction_dir.glob("*.js"))
    assert len(js_scripts) == 9, (
        f"Expected 9 JS extraction scripts, found {len(js_scripts)}: {[s.name for s in js_scripts]}"
    )


def test_extraction_scripts_present(project_root):
    """All 9 required extraction scripts exist."""
    extraction_dir = project_root / "scripts" / "extraction"
    required = [
        "parseRobotsTxt.js",
        "contentHash.js",
        "extractCSSCustomProperties.js",
        "extractColorTokens.js",
        "extractTypography.js",
        "extractSpacing.js",
        "extractShadowsAndBorders.js",
        "extractBreakpoints.js",
        "extractComponentInventory.js",
    ]
    for name in required:
        assert (extraction_dir / name).exists(), f"Missing extraction script: {name}"


def test_plugin_json_skills_match_filesystem(project_root, plugin_json):
    """Every skill listed in plugin.json exists on disk."""
    for skill_path in plugin_json.get("skills", []):
        resolved = project_root / skill_path
        assert resolved.is_dir(), f"Skill dir not found: {skill_path}"
        assert (resolved / "SKILL.md").exists(), f"Missing SKILL.md in {skill_path}"
```

**Step 5: Write test_skills.py**

Create `interverse/intersight/tests/structural/test_skills.py`:

```python
"""Tests for skill definitions."""

from helpers import parse_frontmatter


def test_skill_count(skills_dir):
    """Expected number of skills."""
    skill_dirs = [d for d in skills_dir.iterdir() if d.is_dir()]
    assert len(skill_dirs) == 1, (
        f"Expected 1 skill, found {len(skill_dirs)}: {[d.name for d in skill_dirs]}"
    )


def test_skill_frontmatter(skills_dir):
    """Every SKILL.md has valid frontmatter with description."""
    for skill_dir in skills_dir.iterdir():
        if not skill_dir.is_dir():
            continue
        skill_md = skill_dir / "SKILL.md"
        assert skill_md.exists(), f"Missing SKILL.md in {skill_dir.name}"
        fm, _ = parse_frontmatter(skill_md)
        assert fm is not None, f"No YAML frontmatter in {skill_dir.name}/SKILL.md"
        assert "description" in fm, f"Missing 'description' in {skill_dir.name}/SKILL.md frontmatter"
```

**Step 6: Generate uv.lock and run tests**

```bash
cd interverse/intersight/tests && uv sync && uv run pytest -v && cd ../../..
```

Expected: Tests for extraction scripts will FAIL (scripts not created yet). Scaffold tests should PASS.

**Step 7: Commit**

```bash
git add interverse/intersight/tests/
git commit -m "test(intersight): structural test suite for plugin validation"
```

---

### Task 3: Preflight Scripts — robots.txt + Content Hash

**Files:**
- Create: `interverse/intersight/scripts/extraction/parseRobotsTxt.js`
- Create: `interverse/intersight/scripts/extraction/contentHash.js`

**Step 1: Write parseRobotsTxt.js**

This script parses robots.txt content (already loaded as the page body) and checks if a standard browser User-Agent is allowed **for a specific target path**. The SKILL.md injects the target path by replacing `__TARGET_PATH__` before passing to `browser_evaluate`.

> **Review fix (P0):** Original version only detected total lockout (`Disallow: /`). Rewritten to match disallow path prefixes against the actual target path. Fail-closed on parse errors (was fail-open). See flux-drive correctness finding #3.

Create `interverse/intersight/scripts/extraction/parseRobotsTxt.js`:

```javascript
(() => {
  try {
    const targetPath = '__TARGET_PATH__'; // Replaced by SKILL.md before evaluation
    const text = document.body?.innerText || '';
    if (!text.trim()) return JSON.stringify({ allowed: true, reason: 'no robots.txt found' });

    const lines = text.split('\n').map(l => l.trim());
    let inRelevantBlock = false;
    const allowedPaths = [];
    const disallowedPaths = [];

    for (const line of lines) {
      if (line.startsWith('#') || !line) continue;

      const lower = line.toLowerCase();
      if (lower.startsWith('user-agent:')) {
        const agent = lower.replace('user-agent:', '').trim();
        inRelevantBlock = agent === '*' || agent.includes('mozilla') || agent.includes('chrome');
      } else if (inRelevantBlock) {
        if (lower.startsWith('disallow:')) {
          const path = line.substring(line.indexOf(':') + 1).trim();
          if (path) disallowedPaths.push(path);
        } else if (lower.startsWith('allow:')) {
          const path = line.substring(line.indexOf(':') + 1).trim();
          if (path) allowedPaths.push(path);
        }
      }
    }

    // RFC 9309: most specific path wins (longest match). Allow > Disallow at same length.
    let bestAllow = '';
    let bestDisallow = '';
    for (const p of allowedPaths) {
      if (targetPath.startsWith(p) && p.length > bestAllow.length) bestAllow = p;
    }
    for (const p of disallowedPaths) {
      if (targetPath.startsWith(p) && p.length > bestDisallow.length) bestDisallow = p;
    }

    if (bestDisallow && bestDisallow.length > bestAllow.length) {
      return JSON.stringify({
        allowed: false,
        reason: 'disallowed by robots.txt: Disallow ' + bestDisallow + ' matches ' + targetPath,
        matchedRule: bestDisallow
      });
    }
    if (bestAllow) {
      return JSON.stringify({ allowed: true, reason: 'explicitly allowed: Allow ' + bestAllow });
    }
    if (disallowedPaths.length === 0) {
      return JSON.stringify({ allowed: true, reason: 'no matching disallow rules' });
    }
    return JSON.stringify({ allowed: true, reason: 'no disallow rule matches ' + targetPath });
  } catch (e) {
    // FAIL-CLOSED: parse errors block extraction (mandatory compliance)
    return JSON.stringify({ allowed: false, reason: 'parse error (fail-closed): ' + e.message });
  }
})()
```

**Step 2: Write contentHash.js**

> **Review fix (P0):** Original used `innerHTML.length` which is session-variant (CSRF tokens, timestamps, auth state change it on every load). Replaced with stylesheet-structural data: CSS rule count + custom property sample from `:root`. These are deployment-stable. See flux-drive architecture/correctness finding.

Create `interverse/intersight/scripts/extraction/contentHash.js`:

```javascript
(() => {
  try {
    // Count total CSS rules across accessible stylesheets (deployment-stable)
    let ruleCount = 0;
    const sheetHrefs = [];
    for (const sheet of document.styleSheets) {
      try {
        ruleCount += sheet.cssRules?.length || 0;
        if (sheet.href) sheetHrefs.push(sheet.href);
      } catch (_) {
        // Cross-origin — count the sheet but not rules
        if (sheet.href) sheetHrefs.push(sheet.href);
      }
    }

    // Sample custom property names from :root (stable across sessions)
    const rootProps = [];
    const rootStyles = getComputedStyle(document.documentElement);
    for (let i = 0; i < rootStyles.length && rootProps.length < 20; i++) {
      if (rootStyles[i].startsWith('--')) rootProps.push(rootStyles[i]);
    }

    const sig = [
      document.querySelectorAll('*').length,
      document.styleSheets.length,
      ruleCount,
      rootProps.sort().join(','),
      sheetHrefs.sort().join(','),
      getComputedStyle(document.documentElement).getPropertyValue('--version') || ''
    ].join(':');
    return JSON.stringify({ hash: sig, timestamp: new Date().toISOString() });
  } catch (e) {
    return JSON.stringify({ hash: 'error', error: e.message });
  }
})()
```

**Step 3: Commit**

```bash
git add interverse/intersight/scripts/extraction/parseRobotsTxt.js interverse/intersight/scripts/extraction/contentHash.js
git commit -m "feat(intersight): preflight scripts — robots.txt parser + content hash"
```

---

### Task 4: CSS Custom Properties Extraction

**Files:**
- Create: `interverse/intersight/scripts/extraction/extractCSSCustomProperties.js`

**Step 1: Write extractCSSCustomProperties.js**

This script extracts all CSS custom properties (`--*`) from `:root` and computed styles.

> **Review fix (P0):** Original used first-write-wins from stylesheet walk, which ignores cascade order (later override sheets get suppressed). Fixed: `getComputedStyle` is authoritative (reflects cascade winner), stylesheet walk adds source attribution only. Also records `resolvedValue` for `var()` references so Phase 7 can cross-reference named tokens with computed colors. See flux-drive correctness findings #1 and #6.

Create `interverse/intersight/scripts/extraction/extractCSSCustomProperties.js`:

```javascript
(() => {
  try {
    const properties = {};
    const root = document.documentElement;
    const rootStyles = getComputedStyle(root);

    // Step 1 (AUTHORITATIVE): Computed custom properties from :root
    // getComputedStyle reflects the cascade winner — this is the ground truth
    for (let i = 0; i < rootStyles.length; i++) {
      const prop = rootStyles[i];
      if (prop.startsWith('--')) {
        const computedValue = rootStyles.getPropertyValue(prop).trim();
        if (computedValue) {
          properties[prop] = {
            value: computedValue,
            source: ':root (computed)',
            resolvedValue: computedValue // same unless overridden by Step 2 below
          };
        }
      }
    }

    // Step 2 (ATTRIBUTION): Walk accessible stylesheets for authored values and source selectors
    // Does NOT overwrite the computed value — only adds source attribution and authored form
    for (const sheet of document.styleSheets) {
      try {
        for (const rule of sheet.cssRules || []) {
          if (rule.style) {
            for (let i = 0; i < rule.style.length; i++) {
              const prop = rule.style[i];
              if (prop.startsWith('--')) {
                const authoredValue = rule.style.getPropertyValue(prop).trim();
                if (authoredValue && properties[prop]) {
                  // Add source attribution from stylesheet (last-write-wins for source, since
                  // CSS cascade means the last matching rule in document order is the winner)
                  properties[prop].source = rule.selectorText || ':root';
                  // If authored value contains var() references, preserve it as authoredValue
                  // so downstream can see both the token reference and the resolved value
                  if (authoredValue.includes('var(')) {
                    properties[prop].authoredValue = authoredValue;
                    // resolvedValue stays as the getComputedStyle result (fully resolved)
                  }
                } else if (authoredValue && !properties[prop]) {
                  // Property not on :root computed — scoped to a selector
                  properties[prop] = {
                    value: authoredValue,
                    source: rule.selectorText || ':root',
                    resolvedValue: authoredValue
                  };
                }
              }
            }
          }
        }
      } catch (_) {
        // Cross-origin stylesheet — skip silently
      }
    }

    return JSON.stringify({
      count: Object.keys(properties).length,
      properties: properties
    });
  } catch (e) {
    return JSON.stringify({ count: 0, properties: {}, error: e.message });
  }
})()
```

**Step 2: Commit**

```bash
git add interverse/intersight/scripts/extraction/extractCSSCustomProperties.js
git commit -m "feat(intersight): CSS custom properties extraction script"
```

---

### Task 5: Color Token Extraction

**Files:**
- Create: `interverse/intersight/scripts/extraction/extractColorTokens.js`

**Step 1: Write extractColorTokens.js**

Samples all visible elements, deduplicates colors, clusters into a palette with frequency counts. Capped at 100 unique colors.

Create `interverse/intersight/scripts/extraction/extractColorTokens.js`:

```javascript
(() => {
  try {
    const colorMap = {};
    const colorProps = ['color', 'backgroundColor', 'borderColor', 'outlineColor',
                        'borderTopColor', 'borderRightColor', 'borderBottomColor', 'borderLeftColor'];

    const elements = document.querySelectorAll('body *');
    const sampleLimit = Math.min(elements.length, 2000);

    for (let i = 0; i < sampleLimit; i++) {
      const el = elements[i];
      const styles = getComputedStyle(el);
      for (const prop of colorProps) {
        const val = styles[prop];
        if (val && val !== 'rgba(0, 0, 0, 0)' && val !== 'transparent') {
          if (!colorMap[val]) {
            colorMap[val] = { value: val, frequency: 0, contexts: new Set() };
          }
          colorMap[val].frequency++;
          const tag = el.tagName.toLowerCase();
          if (colorMap[val].contexts.size < 5) {
            colorMap[val].contexts.add(tag);
          }
        }
      }
    }

    // Sort by frequency, cap at 100
    const sorted = Object.entries(colorMap)
      .sort((a, b) => b[1].frequency - a[1].frequency)
      .slice(0, 100)
      .map(([key, data]) => ({
        value: data.value,
        frequency: data.frequency,
        contexts: Array.from(data.contexts)
      }));

    return JSON.stringify({ count: sorted.length, colors: sorted });
  } catch (e) {
    return JSON.stringify({ count: 0, colors: [], error: e.message });
  }
})()
```

**Step 2: Commit**

```bash
git add interverse/intersight/scripts/extraction/extractColorTokens.js
git commit -m "feat(intersight): color token extraction script"
```

---

### Task 6: Typography Extraction

**Files:**
- Create: `interverse/intersight/scripts/extraction/extractTypography.js`

**Step 1: Write extractTypography.js**

Create `interverse/intersight/scripts/extraction/extractTypography.js`:

```javascript
(() => {
  try {
    const typoMap = {};
    const textElements = document.querySelectorAll('body h1, body h2, body h3, body h4, body h5, body h6, body p, body span, body a, body li, body td, body th, body label, body button, body input, body textarea, body div, body section');
    const sampleLimit = Math.min(textElements.length, 1500);

    for (let i = 0; i < sampleLimit; i++) {
      const el = textElements[i];
      if (!el.textContent?.trim()) continue;

      const styles = getComputedStyle(el);
      const key = [
        styles.fontFamily,
        styles.fontSize,
        styles.fontWeight,
        styles.lineHeight,
        styles.letterSpacing
      ].join('|');

      if (!typoMap[key]) {
        typoMap[key] = {
          fontFamily: styles.fontFamily.split(',').map(f => f.trim().replace(/['"]/g, '')),
          fontSize: styles.fontSize,
          fontWeight: parseInt(styles.fontWeight) || 400,
          lineHeight: styles.lineHeight,
          letterSpacing: styles.letterSpacing,
          frequency: 0,
          sampleTags: new Set()
        };
      }
      typoMap[key].frequency++;
      if (typoMap[key].sampleTags.size < 3) {
        typoMap[key].sampleTags.add(el.tagName.toLowerCase());
      }
    }

    const sorted = Object.values(typoMap)
      .sort((a, b) => b.frequency - a.frequency)
      .slice(0, 30)
      .map(t => ({
        fontFamily: t.fontFamily,
        fontSize: t.fontSize,
        fontWeight: t.fontWeight,
        lineHeight: t.lineHeight,
        letterSpacing: t.letterSpacing,
        frequency: t.frequency,
        sampleTags: Array.from(t.sampleTags)
      }));

    return JSON.stringify({ count: sorted.length, typography: sorted });
  } catch (e) {
    return JSON.stringify({ count: 0, typography: [], error: e.message });
  }
})()
```

**Step 2: Commit**

```bash
git add interverse/intersight/scripts/extraction/extractTypography.js
git commit -m "feat(intersight): typography extraction script"
```

---

### Task 7: Spacing, Shadows, Borders, and Breakpoints Extraction

**Files:**
- Create: `interverse/intersight/scripts/extraction/extractSpacing.js`
- Create: `interverse/intersight/scripts/extraction/extractShadowsAndBorders.js`
- Create: `interverse/intersight/scripts/extraction/extractBreakpoints.js`

**Step 1: Write extractSpacing.js**

Create `interverse/intersight/scripts/extraction/extractSpacing.js`:

```javascript
(() => {
  try {
    const spacingMap = {};
    const spacingProps = ['marginTop', 'marginRight', 'marginBottom', 'marginLeft',
                          'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
                          'gap', 'rowGap', 'columnGap'];
    const elements = document.querySelectorAll('body *');
    const sampleLimit = Math.min(elements.length, 1500);

    for (let i = 0; i < sampleLimit; i++) {
      const styles = getComputedStyle(elements[i]);
      for (const prop of spacingProps) {
        const val = styles[prop];
        if (val && val !== '0px' && val !== 'auto' && val !== 'normal') {
          const px = parseFloat(val);
          if (!isNaN(px) && px > 0 && px < 500) {
            const key = px + 'px';
            if (!spacingMap[key]) {
              spacingMap[key] = { value: px, unit: 'px', frequency: 0 };
            }
            spacingMap[key].frequency++;
          }
        }
      }
    }

    const sorted = Object.values(spacingMap)
      .sort((a, b) => a.value - b.value)
      .slice(0, 20);

    return JSON.stringify({ count: sorted.length, spacing: sorted });
  } catch (e) {
    return JSON.stringify({ count: 0, spacing: [], error: e.message });
  }
})()
```

**Step 2: Write extractShadowsAndBorders.js**

Create `interverse/intersight/scripts/extraction/extractShadowsAndBorders.js`:

```javascript
(() => {
  try {
    const shadowMap = {};
    const borderMap = {};
    const elements = document.querySelectorAll('body *');
    const sampleLimit = Math.min(elements.length, 1500);

    for (let i = 0; i < sampleLimit; i++) {
      const styles = getComputedStyle(elements[i]);

      // Shadows
      const shadow = styles.boxShadow;
      if (shadow && shadow !== 'none') {
        if (!shadowMap[shadow]) {
          shadowMap[shadow] = { value: shadow, frequency: 0 };
        }
        shadowMap[shadow].frequency++;
      }

      // Borders
      const borderWidth = styles.borderWidth;
      if (borderWidth && borderWidth !== '0px') {
        const allZero = borderWidth.split(' ').every(v => v === '0px');
        if (!allZero) {
          const key = styles.borderWidth + ' ' + styles.borderStyle + ' ' + styles.borderColor;
          if (!borderMap[key]) {
            borderMap[key] = {
              width: styles.borderWidth,
              style: styles.borderStyle,
              color: styles.borderColor,
              radius: styles.borderRadius,
              frequency: 0
            };
          }
          borderMap[key].frequency++;
        }
      }
    }

    const shadows = Object.values(shadowMap)
      .sort((a, b) => b.frequency - a.frequency)
      .slice(0, 10);

    const borders = Object.values(borderMap)
      .sort((a, b) => b.frequency - a.frequency)
      .slice(0, 10);

    return JSON.stringify({
      shadows: { count: shadows.length, values: shadows },
      borders: { count: borders.length, values: borders }
    });
  } catch (e) {
    return JSON.stringify({
      shadows: { count: 0, values: [] },
      borders: { count: 0, values: [] },
      error: e.message
    });
  }
})()
```

**Step 3: Write extractBreakpoints.js**

Create `interverse/intersight/scripts/extraction/extractBreakpoints.js`:

```javascript
(() => {
  try {
    const breakpoints = new Set();

    for (const sheet of document.styleSheets) {
      try {
        for (const rule of sheet.cssRules || []) {
          if (rule instanceof CSSMediaRule) {
            const text = rule.conditionText || rule.media?.mediaText || '';
            const matches = text.match(/\d+(?:\.\d+)?px/g);
            if (matches) {
              for (const m of matches) {
                const px = parseFloat(m);
                if (px >= 320 && px <= 2560) {
                  breakpoints.add(px);
                }
              }
            }
          }
        }
      } catch (_) {
        // Cross-origin stylesheet — skip silently
      }
    }

    const sorted = Array.from(breakpoints)
      .sort((a, b) => a - b)
      .map(px => ({ value: px, unit: 'px' }));

    return JSON.stringify({ count: sorted.length, breakpoints: sorted });
  } catch (e) {
    return JSON.stringify({ count: 0, breakpoints: [], error: e.message });
  }
})()
```

**Step 4: Commit**

```bash
git add interverse/intersight/scripts/extraction/extractSpacing.js interverse/intersight/scripts/extraction/extractShadowsAndBorders.js interverse/intersight/scripts/extraction/extractBreakpoints.js
git commit -m "feat(intersight): spacing, shadows, borders, and breakpoints extraction scripts"
```

---

### Task 8: Component Inventory Extraction

**Files:**
- Create: `interverse/intersight/scripts/extraction/extractComponentInventory.js`

**Step 1: Write extractComponentInventory.js**

Create `interverse/intersight/scripts/extraction/extractComponentInventory.js`:

```javascript
(() => {
  try {
    const componentMap = {};
    const elements = document.querySelectorAll('body *');

    for (const el of elements) {
      const role = el.getAttribute('role') || el.tagName.toLowerCase();
      const classes = Array.from(el.classList);
      if (classes.length === 0) continue;

      // Use the first meaningful class as the component identifier
      const primaryClass = classes[0];
      const key = role + ':' + primaryClass;

      if (!componentMap[key]) {
        componentMap[key] = {
          name: primaryClass,
          selector: '.' + primaryClass,
          role: role,
          frequency: 0,
          variants: new Set(),
          dataAttributes: new Set()
        };
      }
      componentMap[key].frequency++;

      // Track variant classes (2nd+ classes)
      for (let i = 1; i < classes.length && componentMap[key].variants.size < 10; i++) {
        componentMap[key].variants.add(classes[i]);
      }

      // Track data attributes
      for (const attr of el.attributes) {
        if (attr.name.startsWith('data-') && componentMap[key].dataAttributes.size < 5) {
          componentMap[key].dataAttributes.add(attr.name);
        }
      }
    }

    // Filter: only components that appear 2+ times (repeated patterns)
    // Sort by frequency, cap at 50
    const sorted = Object.values(componentMap)
      .filter(c => c.frequency >= 2)
      .sort((a, b) => b.frequency - a.frequency)
      .slice(0, 50)
      .map(c => ({
        name: c.name,
        selector: c.selector,
        role: c.role,
        frequency: c.frequency,
        variants: Array.from(c.variants),
        dataAttributes: Array.from(c.dataAttributes)
      }));

    return JSON.stringify({ count: sorted.length, components: sorted });
  } catch (e) {
    return JSON.stringify({ count: 0, components: [], error: e.message });
  }
})()
```

**Step 2: Run all structural tests**

```bash
cd interverse/intersight/tests && uv run pytest -v && cd ../../..
```

Expected: ALL PASS — all 9 extraction scripts now exist.

**Step 3: Commit**

```bash
git add interverse/intersight/scripts/extraction/extractComponentInventory.js
git commit -m "feat(intersight): component inventory extraction script"
```

---

### Task 9: Output Schema Definition

This task defines the W3C DTCG output schema as a reference JSON file used by the SKILL.md to structure synthesis output.

**Files:**
- Create: `interverse/intersight/scripts/extraction/schema.json`

**Step 1: Write schema.json**

Create `interverse/intersight/scripts/extraction/schema.json`:

```json
{
  "$schema": "https://www.designtokens.org/schemas/2025.10/format.json",
  "$extensions": {
    "intersight:meta": {
      "source_url": "",
      "analyzed_at": "",
      "analysis_depth": "standard",
      "pages_analyzed": ["/"],
      "tool_version": "0.1.0",
      "content_hash": "",
      "dembrandt_available": true,
      "phases_completed": ["preflight", "setup", "dembrandt", "dom_extraction", "structural", "visual", "synthesis"],
      "warnings": []
    },
    "intersight:components": [],
    "intersight:ux_flow": {
      "navigation_pattern": "",
      "primary_actions": [],
      "information_density": ""
    },
    "intersight:visual_analysis": {
      "layout_pattern": "",
      "visual_hierarchy_notes": "",
      "color_contrast_issues": [],
      "responsive_behavior": ""
    }
  },
  "color": {
    "$type": "color",
    "$description": "Extracted color palette"
  },
  "dimension": {
    "$type": "dimension",
    "$description": "Spacing scale"
  },
  "typography": {
    "$description": "Typography scale"
  },
  "shadow": {
    "$type": "shadow",
    "$description": "Elevation system"
  },
  "border": {
    "$type": "border",
    "$description": "Border system"
  }
}
```

This is a reference template — the SKILL.md instructs Claude to populate it with extraction results during Phase 7 (Synthesis).

**Step 2: Commit**

```bash
git add interverse/intersight/scripts/extraction/schema.json
git commit -m "feat(intersight): W3C DTCG output schema reference template"
```

---

### Task 10: SKILL.md — Full Orchestration

This is the core deliverable. The SKILL.md contains the complete 7-phase pipeline orchestration that Claude follows when the user invokes `/intersight:analyze`.

**Files:**
- Modify: `interverse/intersight/skills/analyze/SKILL.md`

**Step 1: Write the complete SKILL.md**

Replace the stub content in `interverse/intersight/skills/analyze/SKILL.md` with the full orchestration. The SKILL.md is a long file (~400 lines) containing:

1. YAML frontmatter (name, description, user_invocable, argument-hint, allowed-tools)
2. Argument parsing section
3. Phase 0: Preflight (robots.txt check, cache lookup)
4. Phase 1: Setup (navigate, resize, wait)
5. Phase 2: Dembrandt baseline (`npx dembrandt <url> --dtcg --json-only`)
6. Phase 3: DOM/CSS extraction (7 browser_evaluate calls reading scripts from `${CLAUDE_PLUGIN_ROOT}/scripts/extraction/`)
7. Phase 4: Structural analysis (browser_snapshot + extractComponentInventory.js) — skipped for `tokens` depth
8. Phase 5: Visual analysis (browser_take_screenshot + Claude vision prompt) — skipped for `tokens` depth, 1 screenshot for `standard`, 3 for `full`
9. Phase 6: Interaction states (browser_hover + style diff extraction) — `full` depth only
10. Phase 7: Synthesis (merge Dembrandt + DOM results into DTCG schema, format output, cache if intercache available)
11. Multi-page handling (if `--pages` specified: iterate, merge with deduplication, rate limit 10s for non-localhost)
12. Error handling per phase
13. Output format templates (json, markdown, tokens-only)

Key implementation notes for the SKILL.md author:
- Each `browser_evaluate` call reads the script content from `${CLAUDE_PLUGIN_ROOT}/scripts/extraction/<name>.js` using the Read tool, then passes the full script text to `browser_evaluate`
- **robots.txt target path injection:** Before passing `parseRobotsTxt.js` to `browser_evaluate`, replace the `__TARGET_PATH__` placeholder with the actual target URL path (e.g., `/dashboard`). Use string replacement on the script content.
- Dembrandt is invoked via Bash: `npx dembrandt "<url>" --dtcg --json-only 2>/dev/null`
- The `--fresh` flag skips the Phase 0 cache lookup
- If Dembrandt fails, continue with DOM-only extraction (log warning, don't abort). Set `intersight:meta.dembrandt_available = false` and add a warning to `intersight:meta.warnings`.
- Claude vision prompt for Phase 5 should request: layout pattern classification, visual hierarchy assessment, color harmony evaluation, information density rating
- intercache calls use MCP tool syntax: `cache_lookup(key)` / `cache_store(key, value, ttl)`
- **intercache detection (P1 fix):** Do NOT assume intercache is available. Attempt `cache_lookup` wrapped in try/catch. If the tool call fails with "tool not found" or similar, set `intercache_available = false` for the session and skip all subsequent cache operations silently.

**Phase 0 preflight — dependency checks (P1 fix):**
Before any browser interaction, verify both hard dependencies:
1. `command -v npx` — if fails: warn "Dembrandt requires npx (Node.js). Install Node.js: https://nodejs.org" and set `dembrandt_available = false`
2. Attempt `browser_navigate` to `about:blank` — if fails: abort with "intersight requires Playwright MCP server. Install: https://github.com/microsoft/playwright-mcp and add to your Claude Code MCP settings."

**Phase 1 — SPA quiescence wait (P0 fix):**
After `browser_navigate` to the target URL:
1. Wait for page load (Playwright MCP's default behavior)
2. Run a quiescence check via `browser_evaluate`:
```javascript
(() => {
  return new Promise(resolve => {
    let lastCount = document.querySelectorAll('*').length;
    let stableChecks = 0;
    const interval = setInterval(() => {
      const current = document.querySelectorAll('*').length;
      if (current === lastCount) stableChecks++;
      else { stableChecks = 0; lastCount = current; }
      if (stableChecks >= 3) { clearInterval(interval); resolve(JSON.stringify({ stable: true, elementCount: current })); }
    }, 500);
    setTimeout(() => { clearInterval(interval); resolve(JSON.stringify({ stable: false, elementCount: lastCount })); }, 5000);
  });
})()
```
3. **Challenge page detection:** After navigation, check for Cloudflare/bot-protection:
```javascript
(() => {
  const title = document.title.toLowerCase();
  const bodyText = (document.body?.innerText || '').substring(0, 500).toLowerCase();
  const indicators = ['just a moment', 'checking your browser', 'please wait', 'access denied',
                       'verify you are human', 'captcha', 'challenge-platform'];
  const detected = indicators.filter(i => title.includes(i) || bodyText.includes(i));
  return JSON.stringify({ challengeDetected: detected.length > 0, indicators: detected });
})()
```
If challenge detected: abort with warning "Target site served a bot-protection challenge page. intersight cannot analyze sites behind Cloudflare/bot protection. Try running against a local dev server or a site without bot protection."

**Phase 3 — skeleton element filtering (P0 fix):**
All extraction scripts already run after quiescence, but the SKILL.md should note: if extraction results show suspiciously low token counts (e.g., < 3 colors, 0 custom properties), add a warning to `intersight:meta.warnings`: "Low token count — site may use client-side rendering that wasn't fully hydrated. Try `--wait` flag or analyze a server-rendered version."

**Phase 7 — merge algorithm (P0 fix):**
The synthesis merge follows this algorithm:
1. **Custom properties are the primary token source.** Each CSS custom property from `extractCSSCustomProperties.js` becomes a named token. The `resolvedValue` field links it to computed colors.
2. **Computed colors fill gaps.** Colors from `extractColorTokens.js` that don't match any custom property's `resolvedValue` are added as unnamed tokens (e.g., `color.extracted-1`).
3. **Dembrandt provides token names.** For any Dembrandt token whose value matches a DOM custom property's resolved value, use Dembrandt's semantic name. DOM value is authoritative on conflicts (reflects runtime state).
4. **Multi-page conflicts:** When the same CSS custom property name has different resolved values across pages, report BOTH values with their page context in `intersight:meta.warnings` rather than silently picking one. Use the value from the page with higher frequency.
5. **Track which phases completed.** Set `intersight:meta.phases_completed` to the list of phases that actually ran successfully.

**Phase 7 — output file (P1 fix):**
Always write the DTCG JSON output to a local file: `./intersight-analysis-<domain>-<timestamp>.json`. This provides a durable receipt that persists beyond the conversation. Report the file path to the user.

**Error message templates (P1 fix):**
- Playwright MCP missing: "intersight requires Playwright MCP server to analyze websites. Install: `npx @anthropic-ai/mcp-playwright` and add it to your Claude Code MCP settings (Settings > MCP Servers)."
- Dembrandt missing: "Dembrandt (design token extractor) not found. Continuing with DOM-only extraction. For better results, install: `npm install -g dembrandt`"
- robots.txt blocked: "robots.txt disallows access to [path] for web crawlers (matched rule: [rule]). intersight respects robots.txt. Suggestions: analyze a different page, or run against a local copy of the site."
- Challenge page: "Target site served a bot-protection challenge (detected: [indicators]). intersight cannot bypass bot protection. Try analyzing a local dev server or a site without protection."

**Step 2: Run structural tests to verify**

```bash
cd interverse/intersight/tests && uv run pytest -v && cd ../../..
```

Expected: ALL PASS

**Step 3: Commit**

```bash
git add interverse/intersight/skills/analyze/SKILL.md
git commit -m "feat(intersight): complete SKILL.md orchestration for 7-phase analysis pipeline"
```

---

### Task 11: Final Validation

**Files:**
- No new files — validation of all existing work

**Step 1: Run full structural test suite**

```bash
cd interverse/intersight/tests && uv run pytest -v && cd ../../..
```

Expected: ALL PASS

**Step 2: Validate plugin.json**

```bash
python3 -c "import json; d=json.load(open('interverse/intersight/.claude-plugin/plugin.json')); print(f'Name: {d[\"name\"]}, Version: {d[\"version\"]}, Skills: {d[\"skills\"]}')"
```

Expected: `Name: intersight, Version: 0.1.0, Skills: ['./skills/analyze']`

**Step 3: Verify script is executable**

```bash
ls -la interverse/intersight/scripts/bump-version.sh
```

Expected: `-rwxr-xr-x` permissions

**Step 4: Count everything**

```bash
echo "JS scripts: $(ls interverse/intersight/scripts/extraction/*.js | wc -l)"
echo "Shell scripts: $(ls interverse/intersight/scripts/*.sh | wc -l)"
echo "Skills: $(find interverse/intersight/skills -name SKILL.md | wc -l)"
echo "Root files: $(ls interverse/intersight/CLAUDE.md interverse/intersight/AGENTS.md interverse/intersight/PHILOSOPHY.md interverse/intersight/README.md interverse/intersight/LICENSE interverse/intersight/.gitignore 2>/dev/null | wc -l)"
```

Expected: 9 JS scripts, 1 shell script, 1 skill, 6 root files

**Step 5: Final commit (if any fixups needed)**

```bash
git status interverse/intersight/
# If clean: nothing to do
# If changes: git add + commit with appropriate message
```
