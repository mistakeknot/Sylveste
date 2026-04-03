---
artifact_type: prd
bead: sylveste-sn7
stage: design
date: 2026-04-03
---

# PRD: Tuivision Token-Efficient Terminal State Encoding

## Problem

Tuivision's `get_screen` MCP tool has a 25x token cost gap between useful modes (~5000-12000 tokens for full/SVG) and cheap modes (~250 tokens for text, which strips all color/style). Agents either operate blind or burn their context budget on screen captures. Vision tokens (PNG/SVG) cannot be prompt-cached, making multi-turn agent sessions 10-32x more expensive than equivalent text.

## Solution

Add an `annotated` text format at ~400-600 tokens that encodes semantic color and style information using BPE-optimized inline markers (`[r]...[/]`). Fix the default format, refactor the internal API to public xterm.js methods, optimize SVG output via span-merging, and establish a complete format specification before implementation.

## Features

### F0: Format Specification

**What:** Define the complete marker grammar before any code is written — escaping, composition, version field, structural preamble.

**Acceptance criteria:**
- [ ] Escape rule specified: `[[r]]` renders as literal `[r]`
- [ ] Composition rule specified: `[r+^]...[/]` for combined attributes, `[/]` closes all open markers
- [ ] Version field in response envelope: `schema: 1` (not in preamble — MCP-native, router-inspectable)
- [ ] Structural preamble defined: `[screen 80x24 cursor=12,8]` as first token of annotated output
- [ ] Marker vocabulary documented: all single-char color codes, style codes, and reserved future codes
- [ ] Token benchmark: actual cl100k/Claude BPE counts for 3 representative screens (vim, htop, empty shell)
- [ ] Spec written to `interverse/tuivision/docs/annotated-format-spec.md`

### F1: Refactor Internal API to Public xterm.js

**What:** Replace `cell as unknown as { fg: number; bg: number }` cast at terminal-renderer.ts:208 with public `IBufferCell` API methods. Prerequisite for all other features.

**Acceptance criteria:**
- [ ] `extractColor()` uses `cell.getFgColorMode()` + `cell.getFgColor()` instead of raw numeric properties
- [ ] `as unknown` cast removed entirely
- [ ] Wide character handling: skip continuation cells where `cell.getWidth() === 0`
- [ ] Existing tests pass (no behavioral change for current formats)
- [ ] Double traversal in compact format fixed: use computed `state` instead of calling `getScreenText()` separately

### F2: Annotated Format

**What:** Add `getAnnotatedText()` to TerminalRenderer and `annotated` format to `get_screen`, producing inline-marked text at ~400-600 tokens per 80x24 screen.

**Acceptance criteria:**
- [ ] New format case `annotated` in get_screen schema and handler
- [ ] Returns `string` type (consistent with `text` format — not a structured object)
- [ ] Builds on `ScreenState` from `getScreenState()` (no duplicate buffer traversal)
- [ ] Emits `[r]`, `[g]`, `[b]`, `[c]`, `[m]`, `[y]`, `[w]`, `[k]` for standard colors; `[R]`, `[G]`, `[B]`, `[C]`, `[M]`, `[Y]`, `[W]`, `[K]` for bright variants
- [ ] Style markers: `+` bold, `_` underline, `~` dim, `^` inverse — compose as `[r+^]...[/]` (non-letter chars avoid collision with bright color codes)
- [ ] Structural preamble on first line per spec
- [ ] Escape sequences applied for literal marker characters in terminal content
- [ ] Optional `include_roles` parameter (top-level, `.optional().default(false)`) — documented as forward-compatible stub; no-op in MVP until role detection heuristics are implemented in a follow-up child
- [ ] Density threshold: suppress markers for cells matching the modal foreground color
- [ ] Token count for htop, vim, and empty shell within 400-800 range (validated by benchmark)

### F3: Default Format Change + Response Envelope

**What:** Change default from `full` (12K tokens) to `compact`, add `format` field to every response for consumer failure detection.

**Acceptance criteria:**
- [ ] Default in Zod schema changed from `"full"` to `"compact"`
- [ ] Every `get_screen` response includes a `format` field identifying the returned format
- [ ] Deprecation warning emitted when `format` parameter is omitted (one-time `note` field in response: "Default format changed from 'full' to 'compact' in v0.X. Specify format explicitly.")
- [ ] Tool description updated to recommend `annotated` for color-aware output
- [ ] `full` format remains available via explicit parameter

### F4: Color Quantization

**What:** Map terminal colors to 16 named categories using palette index for indexed colors and perceptual distance for truecolor.

**Acceptance criteria:**
- [ ] Mode 1 (16-color) and Mode 2 (indices 0-15): use palette index directly — `color 4` → `b` (blue) regardless of RGB value
- [ ] Mode 2 (indices 16-255): nearest-neighbor against xterm-256 palette, then map to nearest of 16
- [ ] Mode 3 (truecolor): CIELAB distance to 16 centroids instead of RGB Euclidean
- [ ] `SEMANTIC_COLOR_GROUPS` constant mapping 16 colors to functional classes: error (r, R), success (g, G), warning (y, Y), info (b, B, c, C), accent (m, M), neutral (w, W, k, K)
- [ ] Single-character codes (`r`, `R`, etc.) used in markers — consistent 2-token BPE cost
- [ ] All 16 marker names validated against cl100k tokenizer for consistent token count

### F5: Preserve Inverse Boolean

**What:** Stop pre-resolving inverse at terminal-renderer.ts:220-223 — emit original colors with `[I]` marker in annotated mode.

**Acceptance criteria:**
- [ ] Annotated format emits `^` marker for cells with `cell.isInverse() === true`, using original (unswapped) fg/bg
- [ ] Full format retains current behavior (pre-resolved) for backward compatibility
- [ ] Documentation notes `^` indicates SGR 7 inverse, not application-level selection
- [ ] Composition with color markers works per spec: `[r^]...[/]`

### F6: SVG Span-Merging

**What:** Group adjacent same-styled cells into `<text>` spans in SVG output, with semantic boundary awareness.

**Acceptance criteria:**
- [ ] Adjacent cells with identical style (fg, bg, bold, italic, underline, dim) merged into single `<text>` element
- [ ] Semantic boundaries: no merge across line boundaries or whitespace gaps
- [ ] New `svg_mode` parameter on `get_screenshot`: `per_cell` (current default) and `merged`
- [ ] Wide characters handled correctly (continuation cells not treated as merge candidates)
- [ ] Token reduction measured: before/after for htop, vim, empty shell
- [ ] RTL and combining character test case included

## Non-goals

- LOD ladder (L0 motif/summary mode) — deferred to future iteration
- Diff/delta mode — deferred; `screen_id` field is a future hook, not in MVP
- Session-local dictionary compression — deferred
- Multi-pane marshalling — deferred
- Agent backchanneling / adaptive detail — deferred
- Role detection heuristics beyond basic color grouping — deferred
- Generative encoding (template+data) — deferred

## Dependencies

- F0 (spec) blocks F2, F4, F5 (must know grammar before coding markers)
- F1 (API refactor) blocks F2, F5, F6 (must use public API for all new code)
- F2 depends on F4 (annotated format uses quantized color names)
- F3 is independent (no deps on F0 or F1 — schema and envelope changes only)
- F5 depends on F2 (inverse preservation is part of annotated format)
- F6 depends on F1 only (SVG changes use public API but don't need marker spec)

Execution order: F0 → {F1 ∥ F4} → F3 → F2 → F5 → F6

Note: F1 and F4 run in parallel after F0. F3 runs after F1 (both edit screen.ts — cannot run in parallel). F3 also needs F1's refactored code to build on.

## Open Questions

1. **Density threshold calibration:** What percentage of styled cells triggers modal-color suppression? Proposal: >60% non-default = suppress default-matching cells. Needs empirical validation.
2. ~~**Version field placement:**~~ **Resolved:** Version goes in the response envelope (`schema: 1`), consistent with F3's `format` field. The envelope is MCP-native — routers can inspect it without parsing the payload. The structural preamble carries screen geometry only.
3. **Inverse in full format:** Should the pre-resolution behavior in `getScreenState()` also be fixed, or only in annotated mode? Changing full format is a breaking change for consumers parsing the `fg`/`bg` fields. **Decision: annotated only for MVP.** Full format retains current behavior.

## Alignment

**Alignment:** Directly supports tuivision's north star of "robust terminal UI automation" by making screen capture economically viable for multi-turn agent sessions. The format spec and response envelope improve operational visibility.

**Conflict/Risk:** The default format change (F3) trades backward compatibility for correctness. Mitigated by the response envelope's format field.
