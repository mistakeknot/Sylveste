---
date: 2026-04-02
prd: docs/prds/2026-04-03-tuivision-token-encoding.md
reviewer: claude-sonnet-4-6
---

# PRD API Review: Tuivision Token Encoding

## Finding 1 — F3 envelope applied to `get_screen` only, `get_screenshot` already has it (P2)

`get_screenshot` already returns a `ScreenshotResult` envelope with a `format` field (line 26–32 of screenshot.ts). F3 adds a `format` field to `get_screen` responses. These are parallel tools and the approach is consistent in intent, but the PRD describes F3 as "add `format` field to every `get_screen` response" without acknowledging that `get_screenshot` already does this — including a `note` field for format degradation. The `get_screen` envelope should be designed to match `ScreenshotResult` structurally (same field names, same degradation pattern) so consumers have a uniform envelope contract across both tools. As written, F3 may produce a thinner envelope than `get_screenshot` with no `note` equivalent and no explicit type/mime discriminator.

**Recommendation:** Define the shared envelope shape in F3 and have both tools conform to it. At minimum, document that `get_screen`'s envelope is intentionally lighter.

## Finding 2 — `annotated` added to `z.enum` breaks the Zod union return type (P1)

The current `getScreen` function returns `ScreenState | CompactScreenState | string`. Adding `annotated` as a new `z.enum` case and returning a new annotated string (or structured annotated object) expands this union. If the new case returns `string` (same as `text`), the union type is technically preserved but the format field in the response envelope becomes the only discriminator — meaning consumers relying on the return shape rather than the envelope field will silently misparse annotated output as plain text.

If `annotated` returns a structured object (the safer path given the preamble line and schema version field discussed in Open Question 2), it must be added to the return type union and any downstream MCP serialization or Zod output schema. The PRD does not specify which shape `annotated` returns — just a "string" with inline markers. This ambiguity must be resolved before implementation: returning a bare string collapses structured metadata into inline content and makes F3's envelope the only recovery path.

**Recommendation:** Specify the return type of `annotated` explicitly in F2's acceptance criteria. If it's a bare string like `text`, document that the `format` envelope field (F3) is load-bearing for consumers to distinguish it. If it's a structured object, add it to the union and update acceptance criteria accordingly.

## Finding 3 — `include_roles` at top-level is misplaced for a format-specific parameter (P2)

F2 places `include_roles` at the top level of `get_screen`'s input schema (`.optional().default(false)`). This parameter only has meaning for the `annotated` format — it is a no-op for `text`, `compact`, and `full`. Top-level placement implies it applies to all formats, which is misleading.

The `get_screenshot` tool sets a precedent for format-agnostic top-level parameters (`font_size`, `show_cursor`) that apply regardless of format. `include_roles` does not fit that pattern.

**Options:**
- Keep top-level but document it as annotated-only — cheapest, mildly confusing.
- Move to a `format_options` sub-object (e.g., `annotated_options: { include_roles: boolean }`) — cleanest but adds nesting.
- Validate in the handler and emit a warning/error if `include_roles: true` is passed with a non-annotated format — pragmatic.

**Recommendation:** At minimum, add "only applies when `format: annotated`" to the parameter description. If the parameter set grows (density threshold, version), prefer a `format_options` sub-object.

## Finding 4 — `svg_mode` on `get_screenshot` is inconsistently named vs `format` on `get_screen` (P2)

F6 adds `svg_mode: "per_cell" | "merged"` to `get_screenshot`. The existing `format` parameter on both tools selects the output representation. `svg_mode` is a sub-parameter of the `svg` format — it only applies when `format: "svg"`. This creates an inconsistency: `get_screen` uses `format` as a flat enum to select behavior, while `get_screenshot` now has two behavioral knobs (`format` + `svg_mode`) where one is a sub-option of the other.

The `note` field in `ScreenshotResult` handles format degradation (PNG→SVG). If `svg_mode` is top-level and `format: "png"`, `svg_mode` is silently ignored — same problem as `include_roles`.

**Recommendation:** Either nest it as `svg_options: { mode: "per_cell" | "merged" }` or make `format` a discriminated union with per-format options. As a minimum, document that `svg_mode` is ignored when `format: "png"` and add a handler-level guard that warns or errors.

## Finding 5 — Default format change (F3) is an unacknowledged breaking change for tool description consumers (P1)

The PRD acknowledges that changing the default from `full` to `compact` is a backward-compat risk and says it's "mitigated by the response envelope's format field." But the tool *description* string in `getScreenSchema` (line 10–13) will also change. MCP clients that embed the tool description in their system prompt or cache it for routing decisions will see schema drift without a version signal. More critically: any consumer that calls `get_screen` with no `format` argument and parses the response as `ScreenState` (the full format) will silently receive `CompactScreenState` after this change.

The `format` field in the response envelope partially mitigates this — but only if the consumer reads the envelope. Consumers that pattern-match on the presence of a `cells` array (or equivalent full-format field) will break silently.

**Recommendation:** The migration mitigation needs to be stronger than just the envelope field. Consider a deprecation warning in the response when `format` is omitted (transitional period), or bump the tool's schema version. At minimum, call this out explicitly in the PRD's Backward Compatibility section rather than burying it under "Mitigated by the response envelope."

## Finding 6 — Open Question 2 (version field placement) resolves differently depending on F3 (P3)

If the version field goes in the structural preamble (`[v1 screen 80x24]`), it's embedded in the string payload and invisible to any MCP middleware or router that inspects the response envelope. If it goes in the response envelope (`schema: 1`), it's visible at the envelope level but adds a field that only annotated responses carry — making the envelope shape non-uniform across formats. The PRD should pick one and explain why rather than leaving this for implementation to decide. Preamble-embedded version is simpler but ties schema evolution to string parsing; envelope-level version is more MCP-native.

**Recommendation:** Resolve this in F0 before F2 starts. Envelope-level is preferable for MCP because routers and consumers can inspect it without parsing the payload.

---

## Summary

| # | Severity | Finding |
|---|----------|---------|
| 2 | P1 | `annotated` return type unspecified — Zod union may silently misparse as `text` |
| 5 | P1 | Default format change breaks silent `full`-format consumers; mitigation understated |
| 1 | P2 | F3 envelope not aligned with existing `ScreenshotResult` shape |
| 3 | P2 | `include_roles` top-level but annotated-only; pattern mismatch vs tool precedent |
| 4 | P2 | `svg_mode` top-level but SVG-only; same pattern problem as `include_roles` |
| 6 | P3 | Open Question 2 (version field) should be resolved in F0, not deferred to implementation |
