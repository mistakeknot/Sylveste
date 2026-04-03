---
artifact_type: plan
bead: sylveste-sn7
prd: docs/prds/2026-04-03-tuivision-token-encoding.md
brainstorm: docs/brainstorms/2026-04-03-tuivision-token-encoding-brainstorm.md
stage: plan
date: 2026-04-03
---

# Implementation Plan: Tuivision Token-Efficient Terminal State Encoding

## Overview

Add token-efficient annotated text output to tuivision's `get_screen` MCP tool. 7 features, execution order: F0 → {F1 ∥ F4} → F3 → F2 → F5 → F6. All work in `interverse/tuivision/`.

Note: F1 and F3 both edit `screen.ts` — cannot run in parallel. F3 runs after F1.

## Phase 1: F0 — Format Specification (doc only, no code)

**Bead:** sylveste-33y
**Files:** `interverse/tuivision/docs/annotated-format-spec.md` (new)
**Estimated:** 30-45 min

### Steps

1. **Write format spec** to `interverse/tuivision/docs/annotated-format-spec.md`:
   - Marker vocabulary: `[r]` red, `[g]` green, `[b]` blue, `[c]` cyan, `[m]` magenta, `[y]` yellow, `[w]` white, `[k]` black. Uppercase for bright: `[R]`, `[G]`, `[B]`, `[C]`, `[M]`, `[Y]`, `[W]`, `[K]`
   - Style markers: `+` bold, `_` underline, `~` dim, `^` inverse (non-letter chars avoid collision with bright color codes)
   - Composition: attributes combine in a single bracket `[r+^]...[/]`. `[/]` closes all open markers
   - Escaping: `[[` renders as literal `[`. No other escapes needed (only `[` is a control character)
   - Structural preamble: first line is `[screen WxH cursor=X,Y]`
   - Response envelope: `{ format: "annotated", schema: 1, content: "..." }`
   - Reserved future: `!` focus, `?` changed, `#` selection. Not emitted in v1

2. **Run BPE token benchmark** — write a quick script or use node REPL:
   - Manually construct annotated output for 3 screens: htop-like (dense color), vim-like (syntax highlight), empty shell (sparse)
   - Count tokens using tiktoken (install: `pip install tiktoken`) for cl100k_base
   - Record results in spec doc. If >800 tokens for any screen, adjust marker density threshold

3. **Verify:** Spec covers all acceptance criteria from PRD F0

### Verification
- [ ] Spec file exists and covers: escaping, composition, version, preamble, vocabulary, benchmark results

---

## Phase 2: F1 — Refactor Internal API (parallel-ready)

**Bead:** sylveste-028
**Files:** `src/terminal-renderer.ts`, `src/tools/screen.ts`
**Estimated:** 45-60 min

### Steps

1. **Refactor `extractColor()`** at `terminal-renderer.ts:93-133`:
   - Replace the `as unknown as { fg: number; bg: number }` cast at line 208 with public `IBufferCell` API
   - Use boolean detection methods (NOT `getFgColorMode()` which returns bitmask values, not 0/1/2/3):
     - `cell.isFgDefault()` → return default color
     - `cell.isFgPalette()` → `cell.getFgColor()` returns palette index 0-255
     - `cell.isFgRGB()` → `cell.getFgColor()` returns 24-bit RGB packed
     - Same for bg: `cell.isBgDefault()`, `cell.isBgPalette()`, `cell.isBgRGB()`
   - Remove `extractColor()` method — replace with `getCellColor(cell, isBackground)` using the boolean API
   - Remove `colorToHex()` at lines 139-163 (unused)

2. **Add wide character guard** in `getScreenState()` inner loop at line 186:
   ```typescript
   // After: const cell = line.getCell(x);
   if (!cell || cell.getWidth() === 0) continue; // skip continuation cells
   ```

3. **Fix double traversal in compact format** at `screen.ts:39-47`:
   - Change line 45 from `text: session.renderer.getScreenText()` to `text: state.lines.map(l => l.text).join("\n")`
   - This uses the already-computed `state` from line 40

4. **Run existing tests:** `cd interverse/tuivision && npm test`
   - All existing tests must pass with no behavioral change

### Verification
- [ ] `as unknown` cast gone from terminal-renderer.ts
- [ ] `colorToHex()` removed
- [ ] Wide char continuation cells skipped
- [ ] Compact format no longer double-traverses
- [ ] `npm test` passes

---

## Phase 2b: F3 — Default Format Change + Response Envelope (after F1)

**Bead:** sylveste-sn7.2
**Files:** `src/tools/screen.ts`, `src/index.ts`
**Estimated:** 30 min

### Steps

1. **Add response envelope type** in `screen.ts`:
   ```typescript
   export interface ScreenResponse {
     format: "full" | "text" | "compact" | "annotated";
     schema: number;
     content: ScreenState | CompactScreenState | string;
     note?: string;
   }
   ```

2. **Change default** in `getScreenSchema` at `screen.ts:9`:
   - `.default("full")` → `.default("compact")`

3. **Wrap all return values** in `getScreen()` to return `ScreenResponse`:
   - Each format case returns `{ format: "<name>", schema: 1, content: <value> }`
   - When `format` was not explicitly provided (detect via a new `format_explicit` boolean or checking the raw input), add `note: "Default format changed from 'full' to 'compact'. Specify format explicitly."`

4. **Update tool description** in `index.ts:152`:
   - Change to: `"Get terminal state. Use 'annotated' for efficient color-aware output (recommended), 'text' for plain text, 'compact' for text + cursor, 'full' for raw cell data."`

5. **Update MCP handler** in `index.ts:161-184`:
   - After F3, `getScreen()` always returns `ScreenResponse` (never raw string/object). Replace the `typeof result === "string"` branch with explicit format-based branching:
     ```typescript
     const result = getScreen(sessionManager, { ... });
     const noteContent = result.note ? `\n\n${result.note}` : "";
     if (result.format === "text" || result.format === "annotated") {
       // String content — return as plain text for token efficiency
       return { content: [{ type: "text", text: result.content + noteContent }] };
     }
     // Structured content (full, compact) — JSON serialize
     return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
     ```
   - Key: `annotated` and `text` formats return their string `content` directly (not JSON-wrapped), preserving token efficiency. `full` and `compact` return the full envelope as JSON.

### Verification
- [ ] Default is `compact`
- [ ] Every response has `format` and `schema` fields
- [ ] Tool description recommends `annotated`
- [ ] Existing tests still pass after adapting to envelope shape

---

## Phase 2 (parallel): F4 — Color Quantization

**Bead:** sylveste-sn7.3
**Files:** `src/terminal-renderer.ts`
**Estimated:** 45-60 min

### Steps

1. **Add color quantization constants** at top of `terminal-renderer.ts`:
   ```typescript
   // Single-char color codes for annotated format
   const COLOR_CODES: Record<number, string> = {
     0: 'k', 1: 'r', 2: 'g', 3: 'y', 4: 'b', 5: 'm', 6: 'c', 7: 'w',
     8: 'K', 9: 'R', 10: 'G', 11: 'Y', 12: 'B', 13: 'M', 14: 'C', 15: 'W',
   };

   // Semantic color groups for agent consumption
   const SEMANTIC_COLOR_GROUPS: Record<string, string> = {
     r: 'error', R: 'error', g: 'success', G: 'success',
     y: 'warning', Y: 'warning', b: 'info', B: 'info',
     c: 'info', C: 'info', m: 'accent', M: 'accent',
     w: 'neutral', W: 'neutral', k: 'neutral', K: 'neutral',
   };
   ```

2. **Add `quantizeColor()` method** to `TerminalRenderer`:
   - Input: cell (`IBufferCell`), isBackground (`boolean`)
   - Use boolean detection methods (NOT `getFgColorMode()` — it returns bitmask values, not 0/1/2/3):
     ```typescript
     quantizeFgColor(cell: IBufferCell): string {
       if (cell.isFgDefault()) return '';  // no marker for default color
       const colorValue = cell.getFgColor();
       if (cell.isFgPalette()) {
         // Palette index 0-15: direct lookup (semantic, not visual)
         if (colorValue < 16) return COLOR_CODES[colorValue] || 'w';
         // 16-255: compute RGB, then CIELAB nearest
         return this.nearestColorCode(this.palette256ToRgb(colorValue));
       }
       if (cell.isFgRGB()) {
         // Truecolor: CIELAB nearest to 16 centroids
         const r = (colorValue >> 16) & 0xFF;
         const g = (colorValue >> 8) & 0xFF;
         const b = colorValue & 0xFF;
         return this.nearestColorCode([r, g, b]);
       }
       return '';
     }
     ```
   - Same pattern for `quantizeBgColor(cell)` using `isBgDefault()`, `isBgPalette()`, `isBgRGB()`

3. **Add CIELAB conversion helpers** (private methods):
   - `rgbToLab(r, g, b)`: RGB → XYZ → CIELAB conversion (~20 lines, standard formulas)
   - `labDistance(lab1, lab2)`: Euclidean distance in CIELAB space
   - Precompute `CIELAB_CENTROIDS` from `DEFAULT_COLORS` array at class construction

4. **Validate BPE consistency:** All 16 marker codes (`[r]`, `[R]`, `[k]`, `[K]`, etc.) should tokenize as 2 tokens each. Verify during F0 benchmark step.

### Verification
- [ ] Palette index 0-15 maps directly to single-char codes
- [ ] Truecolor uses CIELAB distance
- [ ] `SEMANTIC_COLOR_GROUPS` exported for future role detection
- [ ] `npm test` passes

---

## Phase 3: F2 — Annotated Format

**Bead:** sylveste-sn7.1
**Files:** `src/terminal-renderer.ts`, `src/tools/screen.ts`, `src/index.ts`
**Estimated:** 60-90 min (largest feature)

### Steps

1. **Add `getAnnotatedText()` method** to `TerminalRenderer`:
   - Build on `getScreenState()` output (no duplicate buffer traversal)
   - Algorithm:
     a. Compute modal foreground color across all non-space cells (for density threshold)
     b. Emit structural preamble: `[screen ${width}x${height} cursor=${cursor.x},${cursor.y}]`
     c. For each line, run-length encode styled spans:
        - Track current style state (color code, bold, underline, dim, inverse)
        - When style changes: emit `[/]` to close, then open new marker
        - Compose attributes: e.g., red+bold+inverse = `[r+^]`
        - Skip markers for cells matching modal foreground color (density threshold)
        - Apply escaping: if char is `[`, emit `[[`
     d. Trim trailing whitespace per line
     e. Join lines with `\n`
   - Signature: `getAnnotatedText(options?: { includeRoles?: boolean }): string`
   - The `includeRoles` parameter is accepted but is a no-op in v1 (returns same output)

2. **Add `annotated` format to schema** in `screen.ts`:
   - Update Zod enum: `.enum(["full", "text", "compact", "annotated"])`
   - Add `include_roles` parameter: `z.boolean().optional().default(false).describe("Include semantic role annotations (forward-compatible stub, not yet active)")`
   - Add case in `getScreen()`:
     ```typescript
     case "annotated":
       return {
         format: "annotated",
         schema: 1,
         content: session.renderer.getAnnotatedText({ includeRoles: input.include_roles }),
       };
     ```

3. **Update MCP handler** in `index.ts`:
   - Add `annotated` to the format enum in `inputSchema`
   - Add `include_roles` parameter to `inputSchema`
   - Handle annotated response (string content in envelope)

4. **Update tool description** to list `annotated` format

### Verification
- [ ] `get_screen format="annotated"` returns string with `[r]...[/]` markers
- [ ] Structural preamble present on first line
- [ ] Escaping works for literal `[` in terminal content
- [ ] Density threshold suppresses markers when >60% of cells share the modal color
- [ ] `include_roles` parameter accepted (no-op)
- [ ] Token count: htop ~400-600, vim ~500-800, empty shell ~50-100
- [ ] `npm test` passes

---

## Phase 4: F5 — Preserve Inverse Boolean

**Bead:** sylveste-sn7.4
**Files:** `src/terminal-renderer.ts`
**Estimated:** 20-30 min

### Steps

1. **Modify `getAnnotatedText()`** to handle inverse:
   - When `cell.isInverse()` is true, use the ORIGINAL (unswapped) fg/bg colors
   - Include `^` in the marker: `[r^]...[/]` for inverse red
   - This is done in the annotated format path only — `getScreenState()` retains current pre-resolution behavior for backward compatibility

2. **Do NOT change `getScreenState()`** at lines 220-222:
   - The `full` format retains `fg: inverse ? bg : fg` behavior
   - Only annotated mode uses original colors + `[I]` marker

3. **Document** in the format spec: "`^` (inverse marker) indicates SGR 7 inverse attribute set by the terminal application. Not all selection UIs use SGR 7 — some use explicit fg/bg colors."

### Verification
- [ ] Annotated format emits `^` for inverse cells with original colors
- [ ] Full format unchanged (pre-resolved, backward compatible)
- [ ] Composition works: `[r^]...[/]`

---

## Phase 5: F6 — SVG Span-Merging

**Bead:** sylveste-sn7.5
**Files:** `src/screenshot.ts`, `src/tools/screenshot.ts`
**Estimated:** 45-60 min

### Steps

1. **Add `svg_mode` parameter** to `getScreenshotSchema` in `tools/screenshot.ts`:
   ```typescript
   svg_mode: z.enum(["per_cell", "merged"]).optional().default("per_cell")
     .describe("SVG rendering mode: 'per_cell' (current) or 'merged' (optimized, groups same-styled spans)")
   ```

2. **Add `renderToSvgMerged()` function** in `screenshot.ts`:
   - Same SVG boilerplate as `renderToSvg()` (header, defs, background rect)
   - For each row, run-length encode cells with identical style (fg, bg, bold, italic, underline, dim):
     - Merge condition: `sameStyle(cell, prev) && sameRow && !isWhitespace(prev) && cell.getWidth() !== 0`
     - Do NOT merge across: line boundaries, whitespace gaps (space chars), or continuation cells
     - Emit one `<text>` element per span with concatenated characters
     - Background rects also merge for same-bg runs
   - Handles: HTML entity escaping, cursor overlay, underline strokes (one per span)

3. **Wire up in `getScreenshot()`**:
   - When `svg_mode === "merged"` and format is svg: call `renderToSvgMerged()` instead of `renderToSvg()`
   - Per-cell remains default for backward compatibility

4. **Test with representative content:**
   - Empty terminal: should produce near-identical output to per-cell (few merges possible)
   - Dense colored output: significant span reduction
   - Verify RTL text and combining characters are not merged incorrectly (add test case)

### Verification
- [ ] `get_screenshot format="svg" svg_mode="merged"` returns span-merged SVG
- [ ] Default `per_cell` mode unchanged
- [ ] No merge across line boundaries or whitespace
- [ ] Wide character continuation cells handled
- [ ] Token reduction measured and documented

---

## Build & Test

After all features:

```bash
cd interverse/tuivision
npm run build
npm test
```

Update MCP tools docs: `interverse/tuivision/agents/mcp-tools.md` — add `annotated` format, `include_roles`, `svg_mode` parameters, and document the response envelope.

## Rollback

Each feature is independently revertable via git. The most sensitive change is F3 (default format change) — if it causes downstream breakage, revert just that commit and keep the new formats available via explicit parameters.
