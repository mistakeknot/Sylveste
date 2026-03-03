# PRD: intersight — Automated UI/UX Design Analysis Plugin

**Bead:** iv-gs4vo
**Date:** 2026-03-03
**Brainstorm:** [docs/brainstorms/2026-03-03-intersight-ui-design-analysis.md](../brainstorms/2026-03-03-intersight-ui-design-analysis.md)

## Problem

There is no reusable tool in the Demarch ecosystem (or broadly available as a Claude Code plugin) for systematically extracting design systems from live websites. Agents and developers repeatedly do manual, inconsistent design analysis when studying reference sites for inspiration.

## Solution

An Interverse plugin (`interverse/intersight/`) with a `/intersight:analyze` skill that orchestrates Dembrandt CLI, Playwright MCP, and Claude vision to extract W3C DTCG design tokens, component inventories, and layout analysis from any URL. Three depth modes (`tokens`, `standard`, `full`) balance cost vs. comprehensiveness.

## Features

### F1: Plugin Scaffold
**What:** Create the intersight plugin directory with standard Interverse structure.
**Acceptance criteria:**
- [ ] `interverse/intersight/` exists with `.claude-plugin/plugin.json`, `CLAUDE.md`, `AGENTS.md`, `README.md`, `LICENSE`
- [ ] `plugin.json` declares name `intersight`, version `0.1.0`, skill `analyze`, and Playwright MCP peer dependency
- [ ] `scripts/bump-version.sh` exists and delegates to root `scripts/interbump.sh`
- [ ] `uv run pytest tests/structural/ -v` passes (structural tests validate plugin.json, required files, skill structure)

### F2: Preflight Phase (Phase 0)
**What:** robots.txt compliance check and optional intercache lookup before any extraction.
**Acceptance criteria:**
- [ ] `parseRobotsTxt.js` script correctly parses robots.txt and returns allow/disallow for standard browser User-Agent
- [ ] Also checks `<meta name="robots">` tag via browser_evaluate
- [ ] If disallowed: skill aborts with clear message naming which rule matched
- [ ] If intercache available and `--fresh` not set: returns cached result on cache hit
- [ ] `contentHash.js` produces a stable structural signature (DOM node count + stylesheet count + content length)

### F3: Dembrandt Baseline (Phase 2)
**What:** Run Dembrandt CLI to extract baseline W3C DTCG tokens from the target URL.
**Acceptance criteria:**
- [ ] Invokes `npx dembrandt <url> --dtcg` and captures JSON output
- [ ] If `command -v npx` fails: clear error message with install instructions, skill aborts
- [ ] Dembrandt output is parsed and stored as the baseline token set for Phase 7 merge
- [ ] Handles Dembrandt failures gracefully (network errors, unsupported sites) — reports error, continues with DOM-only extraction

### F4: DOM/CSS Extraction (Phase 3)
**What:** 7 focused JS extraction scripts run via Playwright MCP `browser_evaluate` to extract design tokens from the live DOM.
**Acceptance criteria:**
- [ ] `extractCSSCustomProperties.js` extracts all `--*` custom properties from `:root` and computed styles
- [ ] `extractColorTokens.js` samples all visible elements, deduplicates colors, clusters into palette with frequency counts
- [ ] `extractTypography.js` extracts font-family, font-size, font-weight, line-height from all text elements with usage counts
- [ ] `extractSpacing.js` extracts margin, padding, gap values and identifies scale patterns
- [ ] `extractShadowsAndBorders.js` extracts box-shadow and border from all elements, deduplicates
- [ ] `extractBreakpoints.js` parses `@media` rules from accessible stylesheets
- [ ] All scripts return valid JSON strings (browser_evaluate constraint)
- [ ] All scripts handle edge cases: empty pages, no stylesheets, cross-origin blocked sheets

### F5: Structural Analysis (Phase 4)
**What:** Accessibility tree capture and component inventory extraction.
**Acceptance criteria:**
- [ ] Uses Playwright MCP `browser_snapshot` to capture ARIA accessibility tree
- [ ] `extractComponentInventory.js` identifies repeated DOM patterns via class frequency analysis + data attributes
- [ ] Component list includes: name, selector, variants, states, frequency, ARIA role
- [ ] Component list capped at 50 entries (ordered by frequency)
- [ ] Runs for `standard` and `full` depth modes (skipped for `tokens`)

### F6: Visual Analysis (Phase 5)
**What:** Screenshot capture + Claude vision analysis for layout patterns and visual hierarchy.
**Acceptance criteria:**
- [ ] `standard` depth: captures 1 desktop screenshot (1440x900)
- [ ] `full` depth: captures 3 screenshots (1440x900 desktop, 768x1024 tablet, 375x812 mobile), restores viewport after
- [ ] Claude vision prompt analyzes: layout pattern (sidebar-main, holy grail, etc.), visual hierarchy, color harmony, information density
- [ ] Vision analysis output written to `intersight:visual_analysis` extension
- [ ] Skipped entirely for `tokens` depth

### F7: Interaction States (Phase 6)
**What:** Hover and focus state extraction for primary interactive elements.
**Acceptance criteria:**
- [ ] Identifies primary interactive elements from Phase 5 component inventory (buttons, links, inputs)
- [ ] Uses Playwright MCP `browser_hover` + `browser_evaluate` to extract hover style changes
- [ ] Extracts focus ring patterns via `browser_evaluate`
- [ ] Captures state variants (default, hover, active, disabled, focus) where detectable
- [ ] Runs for `full` depth mode only

### F8: Synthesis & Output (Phase 7)
**What:** Merge all extraction results into W3C DTCG format with intersight extensions, format per user preference, cache result.
**Acceptance criteria:**
- [ ] Merges Dembrandt baseline tokens with DOM extraction results (DOM overrides Dembrandt on conflicts, since DOM reflects runtime state)
- [ ] Output conforms to W3C DTCG 2025.10 schema (`$schema`, `$type`, `$value` structure)
- [ ] `intersight:meta` extension includes: source_url, analyzed_at, analysis_depth, pages_analyzed, tool_version, content_hash
- [ ] `intersight:components` extension includes component inventory array
- [ ] `intersight:ux_flow` extension includes navigation pattern, primary actions, information density
- [ ] `intersight:visual_analysis` extension includes layout pattern, visual hierarchy notes, responsive behavior (when applicable)
- [ ] `--format json` produces full DTCG + extensions JSON
- [ ] `--format markdown` produces human-readable design system report
- [ ] `--format tokens-only` produces bare DTCG tokens (no extensions)
- [ ] If intercache available: stores result per-URL per-category with 7-day TTL
- [ ] Color palette capped at 100 unique colors, component list at 50 entries

### F9: Multi-Page Analysis
**What:** `--pages` flag to analyze multiple URL paths and merge results.
**Acceptance criteria:**
- [ ] Accepts comma-separated relative paths (e.g., `--pages /,/dashboard,/settings`)
- [ ] Navigates to each page, runs extraction phases, merges results
- [ ] Deduplicates tokens across pages (union with frequency counts — higher frequency wins on conflicts)
- [ ] Component inventory merged across pages with cumulative frequency
- [ ] Rate limiting: 10s delay between pages for third-party sites (no delay for localhost)

### F10: SKILL.md Orchestration
**What:** The master skill file that orchestrates all phases in sequence.
**Acceptance criteria:**
- [ ] Skill is invocable as `/intersight:analyze <URL> [options]`
- [ ] Parses arguments: `--depth`, `--format`, `--fresh`, `--pages`
- [ ] Executes phases 0-7 in order, respecting depth mode (tokens skips phases 5-6, standard skips phase 6)
- [ ] Handles errors at each phase: reports which phase failed, what succeeded, suggests recovery
- [ ] Reads JS scripts from `${CLAUDE_PLUGIN_ROOT}/scripts/extraction/` and passes to browser_evaluate
- [ ] Total execution time: <30s for tokens, <60s for standard, <120s for full (single page)

## Non-goals

- **No dedicated MCP server** — all extraction via Playwright MCP's `browser_evaluate` + Dembrandt CLI
- **No authentication support** — intersight analyzes publicly accessible pages only (login-required pages are out of scope for v1)
- **No continuous monitoring** — intersight is a point-in-time snapshot, not a watcher
- **No design token diffing** — comparing two analyses is a future feature (intercache `session_diff` could support it)
- **No Figma import/export** — output is W3C DTCG JSON; Figma integration via Style Dictionary is downstream
- **No custom extraction rules** — v1 uses fixed extraction logic; user-defined extractors are a future feature

## Dependencies

| Dependency | Type | Status |
|-----------|------|--------|
| **Playwright MCP server** | Hard (peer) | Exists — must be configured in user's Claude Code |
| **Dembrandt** (npm) | Hard | External — `npx dembrandt` must work |
| **intercache MCP** | Optional | Exists as Interverse plugin |
| **Claude vision** | Implicit | Built into Claude |
| **W3C DTCG 2025.10 spec** | Schema | Stable external standard |

## Open Questions

1. **Dembrandt version pinning** — Pin `npx dembrandt@latest` or a specific version? Risk: breaking changes in DTCG output. Recommendation: use `@latest` for v1, pin after we understand their release cadence.
2. **Screenshot storage** — Screenshots are ephemeral (used for Claude vision analysis, then discarded). No persistent storage needed for v1. If users want to keep screenshots, that's a v2 feature.
3. **Rate limiting config** — Hardcode 10s delay between pages for non-localhost URLs. Not user-configurable in v1. Revisit if users report issues.
4. **Marketplace timing** — Publish to marketplace after successful end-to-end testing on 3+ diverse sites. Local-only until then.
