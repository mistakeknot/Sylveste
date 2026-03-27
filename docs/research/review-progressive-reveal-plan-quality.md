# Quality Review: Pollard Progressive Result Reveal — Full Analysis
**Plan reviewed:** `/home/mk/projects/Sylveste/docs/plans/2026-02-23-pollard-progressive-reveal.md`
**Source files read:** `pollard.go`, `research_overlay.go`, `research/run.go`, `research/coordinator.go`, `research/messages.go`, `pkg/autarch/models.go`, `pkg/autarch/source.go`, existing test files in `internal/tui/views/`
**Reviewer:** fd-quality (Flux-drive Quality & Style Reviewer)
**Date:** 2026-02-23

---

## File Written

Full review findings are at:
`/home/mk/projects/Sylveste/.claude/reviews/fd-quality-progressive-reveal.md`

---

## Executive Summary

Five findings. Two require fixes before implementation begins.

### Finding 1 — sort.Search predicate (Task 2)

The predicate `v.insights[i].Score < insight.Score` is correct for descending insertion. The `copy`-overlap pattern is safe for Go value-type slices. No code change required; a comment explaining copy-overlap safety is recommended.

### Finding 2 — Map iteration non-determinism in SidebarItems (Task 3) — MUST FIX

```go
// Proposed (broken):
for name, status := range v.hunterStatuses {
```

This iterates a `map[string]research.HunterStatus` in non-deterministic order. The project MEMORY.md explicitly documents this as a cache-breaking bug class: "Always sort Go map keys before hashing — non-deterministic iteration kills cache effectiveness." The `SidebarItems()` output feeds the render pipeline. Beyond caching, hunter badge order will flicker on every render during an active run.

Fix: collect keys, `sort.Strings`, then iterate. The same pre-existing defect is present in `ResearchOverlay.renderHunterStatus` but is out of scope for this plan.

Note: the `renderDocument()` map iteration in Task 4 only aggregates counts and does not affect output order — that usage is safe.

### Finding 3 — Test construction: RunCompleted test will panic (Task 6) — MUST FIX

`TestPollardView_RunCompletedClearsRunActive` constructs `NewPollardView(&autarch.Client{}, nil)`. The `RunCompletedMsg` handler calls `v.loadInsights()`, which calls `v.client.ListInsights()` on a zero-value `Client` with nil `httpClient`. This panics at the HTTP client dereference.

Fix: pass `nil` as the client (not `&autarch.Client{}`), and discard the returned `tea.Cmd` — it is not executed in unit test context. All other four tests in the suite do not reach `loadInsights` and are safe with either `nil` or `&autarch.Client{}`.

Additionally, all five tests discard the `(tui.View, tea.Cmd)` return from `Update`. This compiles because Go allows discarding multi-returns, and works today because `Update` mutates `v` through pointer receiver and returns `v` itself. It is fragile. Tests should capture and type-assert the returned view: `newView.(*PollardView)`.

### Finding 4 — HunterStartedMsg nil-map guard (Task 2) — no action

The `if ok` guard before the map write prevents a nil-map panic when `HunterStartedMsg` arrives before `RunStartedMsg`. Reading a nil map in Go returns `false` for `ok`. Safe.

### Finding 5 — Hardcoded hunter names in Commands() (Task 5) — low priority

Three hunter names are hardcoded. They should come from `coordinator.registry` or a new `GetRegisteredHunterNames()` method. This limits the feature's utility for Pollard deployments using domain-specific hunters (`openalex`, `pubmed`, etc.).

---

## Required Fixes Before Implementation

| Priority | Task | Fix |
|----------|------|-----|
| Must fix | Task 3 `SidebarItems` | Sort map keys before ranging (documented project pattern) |
| Must fix | Task 6 `TestPollardView_RunCompletedClearsRunActive` | Use `nil` client; capture returned view |
| Recommended | Task 6 all tests | Capture `newView.(*PollardView)` from `Update` return |
| Low | Task 5 `Commands` | Add `GetRegisteredHunterNames()` or TODO comment |
