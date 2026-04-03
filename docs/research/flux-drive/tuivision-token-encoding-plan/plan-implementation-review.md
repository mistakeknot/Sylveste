---
artifact_type: review
plan: docs/plans/2026-04-03-tuivision-token-encoding.md
date: 2026-04-02
---

# Plan Implementation Review: tuivision-token-encoding

## P1: getFgColorMode() returns bitmask values, not 0/1/2/3 (F1, F4)

The plan states: "Use `cell.getFgColorMode()` to get color mode (0=default, 1=16, 2=256, 3=RGB)".

This is wrong. The actual implementation (`xterm-headless.js`) returns the raw bitmask field, not a normalized integer:

| Mode    | getFgColorMode() return value |
|---------|-------------------------------|
| Default | `0`                           |
| Palette (16-color or 256-color, index 0-15) | `16777216` (0x01000000) |
| Palette (256-color, index 16-255) | `33554432` (0x02000000) |
| RGB     | `50331648` (0x03000000)       |

The `quantizeColor()` method in F4 switches on modes 0/1/2/3, but `getFgColorMode()` never returns 1, 2, or 3 — every comparison would fall through. The plan's mode mapping is incorrect.

Use `cell.isFgDefault()`, `cell.isFgPalette()`, `cell.isFgRGB()` instead (they return `boolean`), or compare against the bitmask constants. Note that `isFgPalette()` covers both 16-color and 256-color ranges (indices 0-255); the distinction between 16-color and 256-color palette entries requires comparing `getFgColorMode()` against `16777216` vs `33554432` directly, not against 1 vs 2.

Same issue applies to `getBgColorMode()`.

## P1: [B] marker collision between bold and bright blue (F0, F2, F4)

The plan defines:
- `[B]` = bold (style marker)
- `[B]` = bright blue (color marker, uppercase of `[b]`)

Both are defined at the same token. The format spec section under F0 lists `[B]` as both "bright blue" (`[b]` uppercase → `[B]`) and "bold" in the style marker table. These collide. The implementer of F2 (`getAnnotatedText`) will hit an irresolvable ambiguity when composing `[rBI]` — is `B` bold or bright blue?

The spec needs to resolve this before F2 is implemented. Common fix: use a different character for bold (e.g., `*` or re-examine the uppercase-for-bright convention since uppercase `[B]` would be needed for a color but is also needed for bold).

## P1: F3 MCP handler update is incomplete — annotated format returns string, but handler logic only covers the pre-envelope `typeof result === "string"` case (F3)

The plan at F3 step 5 says "Update to read from `result.content` inside the envelope, preserving the MCP response shape". But after F3 wraps all returns in `ScreenResponse`, the handler's existing branch `if (typeof result === "string")` at `index.ts:169` will never fire (the result is now always an object). The annotated format returns a `string` in `result.content`, but the handler must branch on `result.format === "annotated"` or `typeof result.content === "string"` to emit it as plain text rather than `JSON.stringify`-ing the whole envelope.

The plan does not spell out this branching logic. An implementer following the plan literally would `JSON.stringify` the envelope for annotated output, wrapping the annotated string in unnecessary JSON — which defeats the token-efficiency goal.

## P2: Parallel safety — F1 and F3 both edit `src/tools/screen.ts` (F1 ∥ F3 ∥ F4)

F1 edits line 45 of `screen.ts` (compact format double-traversal fix). F3 adds the `ScreenResponse` interface, changes the default at line 9, and wraps all return values — touching lines 9, 28, 34–52.

These are non-overlapping lines, but they are the same file. Parallel agents working independently will produce a three-way merge conflict on `screen.ts`. Either F1's screen.ts edit must be sequenced before F3, or the implementer doing F3 must incorporate the F1 line-45 fix manually. The plan marks them as safe to parallelize (`F1 ∥ F3 ∥ F4`) without noting this constraint.

## P2: Line number references are accurate — no drift found

Verified against actual source:
- `extractColor` at lines 93-133: correct (lines 93–134)
- `as unknown as { fg: number; bg: number }` cast at line 208: correct
- `colorToHex` at lines 139-163: correct (lines 139–163)
- `getScreenText()` double-traversal in `screen.ts` at line 45: correct
- `getScreen` tool description at `index.ts:152`: correct
- `typeof result === "string"` branch at `index.ts:169`: correct
- `getScreenSchema` default at `screen.ts:9`: correct (`.default("full")`)

## P2: `[B]` bold vs `[W]`/`[K]` naming — [B] also clashes with bright for background (F0)

Secondary consequence of the bold/bright collision: the spec's "Uppercase for bright" rule is stated as generic (`[R]`, `[G]`, etc.) but `[B]` (bright blue) and `[B]` (bold) and `[I]` (inverse from F5) vs `[I]` in the style markers — all four style markers (`[B]` bold, `[U]` underline, `[D]` dim, `[I]` inverse) use the same character namespace as the uppercase bright colors. `[U]` is unambiguous (no color uses it), `[D]` is unambiguous, but `[I]` could conflict with future color codes. The main immediate collision is `[B]`.

## P3: `colorToHex` is not dead code — it has a different signature than `extractColor` (F1)

The plan says to remove `colorToHex` as "dead code, duplicates `extractColor` logic". `colorToHex` takes `(color: number, isDefault: boolean, defaultColor: string)` while `extractColor` takes a packed raw value. They are not called from anywhere else in the codebase (confirmed by search), so removal is safe — but the plan's description of it as a "duplicate" is misleading. It's unused code with different semantics, not a duplicate. This is a labeling issue, not a correctness issue.

## P3: Test files do not need updating for F1–F4

`src/session-manager.test.ts` and `src/screenshot.test.ts` test session cleanup and font resolution respectively — neither touches the `getScreen` tool, `terminal-renderer`, or color extraction. No existing test will break from F1/F3/F4 changes. New tests for annotated format are implied but not mentioned anywhere in the plan's verification checklists.
