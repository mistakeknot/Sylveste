---
artifact_type: prd-review
target: docs/prds/2026-04-03-tuivision-token-encoding.md
source_synthesis: docs/research/flux-review/tuivision-token-encoding/2026-04-03-brainstorm-synthesis.md
date: 2026-04-03
---

# PRD Feature Review — Tuivision Token Encoding

## Summary

17 findings from the synthesis are represented in the PRD. 5 gaps remain: 1 P1 (dependency graph contradiction), 2 P2 (incomplete ACs, missing constraint), 2 P3 (polish). No P0-level omissions. All synthesis P0s map to PRD features.

---

## P1 Findings

### P1-1: Execution order contradicts dependency text

**Location:** Dependencies section vs. Execution order line

The Dependencies section says "F3 is independent (can be done in parallel with F1)." The execution order reads `F0 → F1 → {F3 ∥ F4} → F2 → F5 → F6`, placing F3 strictly after F1. These are inconsistent.

If F3 is truly independent, the order should be `{F0 ∥ F3} → F1 → F4 → F2 → F5 → F6` (or some other arrangement that doesn't sequence F3 after F1). If F3 should wait on F1 for practical reasons (e.g., the format field in the envelope benefits from knowing the API shape), that dependency must be made explicit in the Dependencies section.

**Fix:** Either remove F3 from the sequenced execution order (it runs whenever, produces no blocking output) or add a sentence to the Dependencies section explaining why F3 waits on F1.

### P1-2: F0 does not explicitly block F4

**Location:** Dependencies section

The Dependencies section says "F0 blocks F2, F4, F5" — but F4's ACs include `SEMANTIC_COLOR_GROUPS` constant and single-character color codes, both of which must be consistent with the marker vocabulary documented in F0. The execution order shows F4 running after F1 but gives no indication it waits on F0.

The text "F0 (spec) blocks F2, F4, F5" is present — this is correct — but the execution order `F0 → F1 → {F3 ∥ F4}` implies F4 starts after F1 completes, not after F0 completes. Since F0 and F1 are sequential, F4 cannot safely start until F0 is done. The execution order is technically consistent only if F0 finishes before F1, which is true given the chain. But the parallel placement of F3 and F4 obscures that F4 depends on F0 (not just F1). Consider making this explicit: `F0 → {F1 ∥ F3 ∥ F4}` then `F1+F4 → F2 → F5 → F6`.

**Fix:** Clarify that F4 unblocks after F0 (not F1), or rewrite the execution order to show F0 as the gating prerequisite for F4 directly.

---

## P2 Findings

### P2-1: Token count range in F2 is inconsistent with the stated problem

**Location:** F2 acceptance criteria, last bullet

The AC says "within 400-800 range." The Problem statement, brainstorm, and synthesis all use "~400-600 tokens." The 800-token ceiling is 2x the Problem statement's upper bound and would leave the annotated format within reach of compact's cost without reliable downside protection.

The synthesis's token arithmetic concern (100-300 styled runs at 4 tokens/pair) makes a 400-800 target ambiguous: a 750-token htop capture still passes the AC but exceeds the advertised cost profile. Either tighten the AC to 400-600 to match the stated problem, or update the Problem section to reflect 400-800 as the actual target.

**Fix:** Align the AC ceiling with the Problem statement (600) or explicitly justify 800 as the revised upper bound.

### P2-2: F5's `include_roles` parameter has no defined behavior for MVP

**Location:** F2 acceptance criteria — `include_roles` bullet

F2 adds an `optional().default(false)` `include_roles` parameter but there are no ACs defining what happens when it is `true`. Role detection heuristics are deferred (correctly — brainstorm Open Question #1 is listed as deferred), but the MVP implementation of `include_roles: true` is undefined. A parameter that accepts a value but has no specified behavior for that value will either be silently ignored or will cause confusing output.

The synthesis noted this is intentionally deferred, but the PRD should either:
- Remove the parameter from F2's scope (add it when role detection is implemented), or
- Add an AC: "When `include_roles: true`, returns same output as `include_roles: false` (detection heuristics deferred; parameter accepted for forward compatibility)."

**Fix:** Add an explicit MVP behavior AC for `include_roles: true`, or defer the parameter to the child where detection is implemented.

### P2-3: F5 AC for inverse coverage does not acknowledge partial detection

**Location:** F5 acceptance criteria, first bullet

The synthesis (Track A, "Inverse coverage is partial") notes that most production TUI frameworks (ratatui, bubbletea, blessed with custom themes) use explicit fg/bg swaps rather than SGR 7. The `[I]` marker only fires for cells where `cell.isInverse() === true` — this is semantically correct but will miss application-level inverse implemented via color values.

The AC as written passes any implementation that correctly handles `isInverse()`. There is no AC that acknowledges or tests the known gap. An implementer reading only this PRD will ship `[I]` and consider inverse done, without the documentation note that flagged coverage is ~60-70% for production TUIs (varies by app).

**Fix:** Add a documentation AC to F5: "Annotated format spec notes that `[I]` only fires for SGR 7 inverse; applications using explicit fg/bg color swaps for selection/focus are not represented by `[I]`."

---

## P3 Findings

### P3-1: Open Question 2 (version field placement) is unresolved but has two conflicting ACs

**Location:** F0 acceptance criteria (version bullet) vs. Open Questions section

F0's version AC reads: "Version field reserved: first line includes `[v1]` or response envelope includes `schema: 1`." The OR is unresolved — there are two incompatible implementations, and this decision must be made before F0 is complete (since consumers must know where to look). The Open Questions section lists this as unresolved without a decision.

This is P3 because it does not block filing F0, but it will generate a revision loop during implementation. The simplest resolution is to pick preamble (`[v1]`) if F3's `format` field already satisfies the envelope versioning need — that's the logical split.

**Fix:** Resolve before F0 starts. Add a decision record rather than leaving two options in the AC.

### P3-2: F6 RTL/combining character test case AC is not actionable

**Location:** F6 acceptance criteria, last bullet

"RTL and combining character test case included" does not specify pass/fail criteria. What is the expected output for a bidi terminal line where adjacent red cells span an RTL boundary? Without a concrete expectation, an implementer cannot write the test and a reviewer cannot verify it. The synthesis (Track B) identified this as a merge failure mode specifically.

**Fix:** Replace with: "RTL: cells spanning a bidi boundary are not merged regardless of style. Combining diacritics: base + combiner are treated as a single cell for merge purposes."

---

## Synthesis Coverage Check

| Synthesis finding | Severity | PRD coverage |
|---|---|---|
| Default change has no consumer failure detection (P0) | P0 | Covered — F3 adds `format` field to every response |
| Unsafe internal API at terminal-renderer.ts:208 (P0) | P0 | Covered — F1 removes `as unknown` cast |
| Color quantization: semantic not visual (P1, 4/4) | P1 | Covered — F4 adds `SEMANTIC_COLOR_GROUPS`, CIELAB for truecolor |
| Marker grammar: no escape sequence (P1) | P1 | Covered — F0 AC specifies `[[r]]` escaping |
| Token cost claims unvalidated (P1) | P1 | Covered — F0 AC requires actual benchmark |
| SVG span-merge needs boundaries (P1) | P1 | Covered — F6 AC specifies no merge across line/whitespace boundaries |
| Marker composition rules undefined (P1) | P1 | Covered — F0 AC specifies `[rBI]...[/]` composition |
| Format ladder: fidelity not purpose (P1) | P1 | Covered — F0 adds structural preamble, F3 adds format field |
| Wide character handling (P1 from Track A) | P1 | Covered — F1 AC: skip cells where `getWidth() === 0` |
| Double traversal in compact format (Track A) | P1 | Covered — F1 AC: use computed `state` |
| Market data versioning (P2) | P2 | Covered — F0 version AC |
| Cartographic symbol overloading / theme caveat (P2) | P2 | Not addressed — no AC disclaims color-to-role mapping as theme-dependent. Low impact (roles deferred to later child). |
| Density threshold / modal color suppression (P2) | P2 | Covered — F2 AC |
| `screen_id` future hook (P2) | P2 | Explicitly deferred in Non-goals with note "future hook" |
| BPE inconsistency: long color names (P2) | P2 | Covered — F4 AC: all 16 names validated against cl100k |
| Mandala center-outward: structural preamble first (P2) | P2 | Covered — F0 structural preamble AC |
| Execution order vs dependency text contradiction | — | Not addressed — P1-1 above |

One synthesis P2 (cartographic theme caveat: color-to-role heuristics invalid without declared theme context) has no PRD coverage. This is low-impact for MVP since role detection is deferred, but if `include_roles` remains in F2's scope, the parameter's documentation should disclaim that color-to-role mappings assume default xterm color assignments.
