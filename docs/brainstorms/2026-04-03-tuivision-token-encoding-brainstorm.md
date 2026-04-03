---
artifact_type: brainstorm
bead: sylveste-sn7
stage: discover
date: 2026-04-03
---

# Tuivision: Token-Efficient Terminal State Encoding

## What We're Building

A new `annotated` output format for tuivision's `get_screen` MCP tool that closes the 25x token cost gap between text mode (~250 tokens, blind to color/style) and SVG/full modes (~5000-12000 tokens, verbose). The annotated format delivers semantic color and style information at ~400-600 tokens using inline markers optimized for BPE tokenizers.

**MVP scope: 5 children from the sylveste-sn7 epic.**

| Child | What | Why |
|-------|------|-----|
| .1 | `annotated` get_screen format with `[r]...[/]` markers | Core feature — closes the cost gap |
| .2 | Change default format from `full` (12K) to `compact` | Stop agents from burning 12K tokens per capture by default |
| .3 | Color quantization — map all hex/256/truecolor to 16 named colors | Eliminate hex strings from output, save 400-600 tokens/screen |
| .4 | Preserve inverse boolean for selection/focus semantics | Fix semantic loss — currently pre-resolved at terminal-renderer.ts:222-223 |
| .5 | SVG span-merging — group same-styled adjacent cells | Per-cell `<text>` elements waste 65-75% of SVG token budget |

Deferred: .6-.22 (LOD ladder L0/motif, diff mode, dictionaries, ROI encoding, channel selection, generative encoding, role annotations as first-class, multi-pane, agent backchanneling).

## Why This Approach

**The cost gap is the problem.** Anthropic's prompt caching gives 90% discount on text tokens but 0% on vision tokens. A 10-turn agent session using PNG screenshots costs 10-32x more than equivalent annotated text. Agents currently choose between "cheap but blind" (text) and "informed but expensive" (SVG/full). The annotated format gives "informed and cheap."

**Format choice: `[r]...[/]` ANSI-inspired markers.** The synthesis benchmarked four formats against cl100k and Claude's BPE tokenizer:
- `[r]...[/]` — 2-3 tokens per marker pair (winner)
- `<span class="red">` — 8-12 tokens
- Custom Unicode — 3-4 tokens but poor model understanding
- Markdown — ambiguity with content

Default output uses compact color markers. Optional `include_roles: true` parameter appends ARIA-inspired semantic role attributes (`[r role=error]...[/]`) for callers that need structural understanding at a ~100 token premium.

**Architecture: extend TerminalRenderer.** Add `getAnnotatedText()` alongside existing `getScreenText()` and `getScreenState()`. Color quantization as a private helper. screen.ts gets a new `annotated` format case. No new files or classes needed — keeps all rendering in one place (~150 new lines).

## Key Decisions

1. **MVP is 5 children, not 22.** The annotated format + default fix + color quantization close 80% of the cost gap. The remaining 17 children (LOD ladder, diff mode, dictionaries) are valuable but can be pursued incrementally after the MVP proves the approach.

2. **`[r]...[/]` with optional `role=` attributes.** Compact by default (BPE-optimal), extensible via opt-in roles. This means we don't need to build role detection logic for MVP — callers who want roles can request them later when we implement the detection heuristics.

3. **Default changes from `full` to `compact`.** This is a breaking change for any agent hardcoding expectations about `get_screen` output shape. Mitigation: `full` remains available via explicit parameter. The 12K default is actively harmful — agents that don't know about the format parameter burn context on every call.

4. **Inverse boolean preserved, not pre-resolved.** Current code at terminal-renderer.ts:220-223 swaps fg/bg when `inverse` is true, destroying the semantic signal. The annotated format will use `[I]` marker for inverse cells and pass through the original colors, letting agents interpret "inverse = selected/focused."

5. **SVG span-merging as L2 mode.** The SVG renderer currently emits per-cell `<text>` elements. Merging adjacent same-styled cells into spans reduces SVG from ~5000 to ~800-1500 tokens, making it viable as an "L2" mode for cases where callers need precise positioning.

## Open Questions

1. **Role detection heuristics.** When `include_roles: true`, how do we detect that a line is a "heading" vs "content"? The synthesis proposed: bold+top-row = heading, inverse = selected, red = error, green = success. This is app-specific and fragile. Defer to a follow-up child? Or include basic heuristics in MVP?

2. **Color quantization edge cases.** The 16-color palette maps cleanly from the xterm defaults, but truecolor applications (e.g., image viewers, color pickers) will lose fidelity. Is this acceptable for the annotated mode? (The full/SVG modes retain exact colors.)

3. **SVG backward compatibility.** Current `get_screenshot` returns per-cell SVG. Span-merging changes the SVG structure. Should this be a new format option, or replace the existing SVG output? The synthesis suggests replacing — the per-cell format has no advantages.

## Alignment

**Alignment:** This directly supports tuivision's north star of "robust terminal UI automation" by making screen capture economically viable for multi-turn agent sessions. Token efficiency enables more captures per session, improving determinism.

**Conflict/Risk:** The default format change (.2) trades backward compatibility for correctness. Low risk — the `full` format remains available, and the current default is actively harmful.
