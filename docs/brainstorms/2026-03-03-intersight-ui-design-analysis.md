# Brainstorm: intersight — Automated UI/UX Design Analysis Plugin

**Bead:** iv-gs4vo
**Date:** 2026-03-03

---

## What We're Building

An Interverse plugin (`interverse/intersight/`) that analyzes websites and extracts structured design system reports. Given a URL, intersight orchestrates Dembrandt CLI, Playwright MCP browser tools, and Claude vision to produce W3C DTCG design tokens, component inventories, and layout analysis.

**Skill invocation:** `/intersight:analyze <URL> [--depth tokens|standard|full] [--format json|markdown|tokens-only] [--fresh] [--pages /path1,/path2]`

**Three depth modes (all shipping in v1):**
- `tokens` (~$0.02/URL): Dembrandt baseline + DOM CSS extraction only
- `standard` (~$0.05/URL): + 1 desktop screenshot for layout analysis via Claude vision
- `full` (~$0.10/URL): + multi-breakpoint screenshots, hover/focus state capture, interaction analysis

## Why This Approach

### Form factor: Interverse plugin

Evaluated four options (plugin, L3 app, skill-only, plugin+CLI shim). Plugin wins on three PHILOSOPHY.md principles:

1. **Composition over capability** — intersight composes existing tools (Playwright MCP, intercache, Claude vision, Dembrandt) rather than building its own browser automation or caching. "Plugins are dumb and independent. The platform is smart and aware."
2. **External tools: adopt, don't rebuild** — Dembrandt handles 80-95% of token extraction. Playwright MCP handles all browser automation. intersight is an orchestration layer, not an engine.
3. **Efficiency = quality** — A plugin can declare dependencies (Playwright MCP required, intercache optional), version itself, and be discovered in the marketplace. A skill-only approach can't.

**Closest analog:** interdeep — Python plugin that orchestrates Playwright for content extraction. intersight orchestrates Playwright for design extraction.

### Architecture: Hybrid skill + JS extraction scripts

Not a dedicated MCP server (50K+ token schema overhead, maintenance burden). Not a skill-only approach (Claude would regenerate extraction JS from scratch each invocation — inconsistent, wasteful). Instead:

- **SKILL.md** orchestrates the pipeline (phases 0-7)
- **9 focused JS extraction scripts** (~365 lines total) run via Playwright MCP's `browser_evaluate`
- **Dembrandt CLI** (hard dependency, npm) provides the baseline token extraction
- **intercache MCP** (optional) provides per-URL caching with content-hash invalidation

### Output format: W3C Design Tokens 2025.10

Industry-standard DTCG format with an `intersight:*` extension namespace for component inventory, UX flow analysis, and visual analysis metadata. Machine-readable by Style Dictionary, Tokens Studio, Figma, and downstream AI agents.

## Key Decisions

### 1. Dembrandt is a hard dependency
- Required: `npx dembrandt` must work (npm/npx on PATH)
- Rationale: covers 80-95% of token surface automatically, zero custom code. Per PHILOSOPHY.md "adopt mature external tools" principle.
- Fail behavior: clear error message with install instructions if `command -v npx` fails.

### 2. Many focused scripts, not few combined scripts
- 9 separate JS extraction scripts, each doing one thing (colors, typography, spacing, shadows, borders, breakpoints, CSS custom properties, component inventory, content hash)
- Plus `parseRobotsTxt.js` for ethics compliance
- Rationale: modularity, testability, easier to debug individual extractors. More browser_evaluate round-trips but clearer failure isolation.

### 3. Generic extension namespace (`intersight:*`)
- Output uses `intersight:meta`, `intersight:components`, `intersight:ux_flow`, `intersight:visual_analysis`
- NOT Shadow Work-specific — any project can consume intersight output
- Shadow Work or other consumers map intersight output to their own domain

### 4. All three depth modes ship in v1
- `tokens`, `standard`, `full` — no phased rollout
- Rationale: the pipeline is the same, depth modes just control which phases execute. Shipping all three adds ~2h of interaction state scripts, not a fundamentally different architecture.

### 5. Playwright MCP is a hard requirement
- intersight declares Playwright MCP as a peer dependency
- Fail-open with clear message: "intersight requires Playwright MCP server. See: https://github.com/microsoft/playwright-mcp"

### 6. intercache is optional
- If intercache MCP is available: cache results per-URL per-category with content-hash invalidation, 7-day TTL
- If not available: every invocation runs the full pipeline. `--fresh` flag bypasses cache regardless.

### 7. robots.txt compliance is mandatory
- Phase 0 (preflight) checks robots.txt before any extraction
- If disallowed: abort with message suggesting alternatives
- Also checks `<meta name="robots">` via browser_evaluate

## Extraction Pipeline (7 Phases)

```
PHASE 0: Preflight (cache lookup, robots.txt check)
PHASE 1: Setup (navigate, resize viewport, wait for networkidle)
PHASE 2: Dembrandt baseline (npx dembrandt <url> --dtcg)
PHASE 3: DOM/CSS extraction (9 browser_evaluate scripts)
PHASE 4: Structural analysis (accessibility tree, component inventory)
PHASE 5: Visual analysis (screenshot + Claude vision) [standard+full]
PHASE 6: Interaction states (hover/focus) [full only]
PHASE 7: Synthesis (merge Dembrandt + DOM results, format, cache, return)
```

## File Structure

```
interverse/intersight/
├── .claude-plugin/plugin.json
├── skills/analyze/SKILL.md
├── scripts/
│   └── extraction/
│       ├── extractCSSCustomProperties.js  (~40 lines)
│       ├── extractColorTokens.js          (~60 lines)
│       ├── extractTypography.js           (~50 lines)
│       ├── extractSpacing.js              (~40 lines)
│       ├── extractShadowsAndBorders.js    (~40 lines)
│       ├── extractBreakpoints.js          (~30 lines)
│       ├── extractComponentInventory.js   (~60 lines)
│       ├── parseRobotsTxt.js              (~30 lines)
│       └── contentHash.js                 (~15 lines)
├── tests/structural/
├── scripts/bump-version.sh
├── CLAUDE.md
├── AGENTS.md
├── README.md
└── LICENSE
```

## Effort Estimate

| Component | Hours |
|-----------|-------|
| Plugin scaffold (plugin.json, CLAUDE.md, AGENTS.md) | 1h |
| SKILL.md (orchestration instructions, all 7 phases) | 2-3h |
| 9 JS extraction scripts (~365 lines) | 4-6h |
| Output schema (W3C DTCG + intersight extensions) | 1-2h |
| Dembrandt integration + error handling | 1h |
| intercache integration (optional path) | 1h |
| Structural tests | 1h |
| End-to-end testing on 3+ sites | 2-3h |
| **Total** | **13-18h** |

## Open Questions

1. **Dembrandt version pinning:** Should intersight pin to a specific Dembrandt version or use latest? Risk: breaking changes in Dembrandt output format.
2. **Screenshot storage:** Where do captured screenshots go? Temp directory? Project-local `.intersight/` cache? Only in intercache?
3. **Multi-page merge strategy:** When `--pages` specifies multiple paths, how to handle conflicting tokens (e.g., different color palettes on different pages)? Union with frequency counts? Last-write-wins?
4. **Rate limiting between pages:** The research suggests 10-30s delays for third-party sites. Should this be configurable or hardcoded?
5. **Marketplace registration timing:** Publish to marketplace after v1 is tested, or keep as local-only first?

## Research References

Full 5-agent research synthesis: `shadow-work/.clavain/scratch/synthesis-uiux-design-analysis.md`
Individual findings:
- `shadow-work/.clavain/scratch/fd-playwright-dom-extraction.md`
- `shadow-work/.clavain/scratch/fd-css-design-token-reverse-engineering.md`
- `shadow-work/.clavain/scratch/fd-component-pattern-cataloging.md`
- `shadow-work/.clavain/scratch/fd-ux-flow-and-state-analysis.md`
- `shadow-work/.clavain/scratch/fd-uiux-workflow-plugin.md`
