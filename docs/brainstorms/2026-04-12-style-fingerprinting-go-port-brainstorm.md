---
artifact_type: brainstorm
bead: sylveste-benl.2
stage: discover
---

# Style Fingerprinting Go Port

Port Auraken's `style.py` (595 lines) to `os/Skaffen/pkg/style/` as a reusable Go package. This is the second child of the Auraken-to-Skaffen migration epic (sylveste-benl), following the lens library port (benl.1).

## What We're Building

A Go package that computes per-message style observables (word count, capitalization, emoji, punctuation, vocabulary tokens), classifies conversation modes (emotional, analytical, playful, intimate, logistics, update, general), accumulates per-mode fingerprints using EMA, and generates concrete mirroring instructions for any Skaffen agent that talks to humans.

### Public API

- `ComputeObservables(text string) Observables` — per-message feature extraction
- `ClassifyMode(text string) Mode` — weighted regex scoring over 7 mode categories
- `(*Fingerprint) Update(obs Observables)` — thread-safe EMA accumulation into global + per-mode profiles
- `(*Fingerprint) UpdateCadence(burstSize int)` — thread-safe cadence tracking
- `(*Fingerprint) BuildMirroring(mode Mode) string` — generate mirroring instructions from accumulated stats
- `BuildInstantMirroring(text string) string` — single-message mirroring for early conversations (< 3 messages)
- `DetectCurrentMode(messages []string, window int) Mode` — majority-vote mode over recent messages

### Types

- `Mode` — string enum with 7 values + `ModeGeneral` default
- `Observables` — struct with word count, capitalization ratio, emoji count/density, boolean flags, vocabulary token slices, opener, mode
- `ModeProfile` — per-mode EMA accumulator (N, avg words, capitalization ratio, emoji density, pct_* rates, vocabulary counters)
- `Fingerprint` — top-level struct with `sync.Mutex`, message count, global profile, per-mode map, cadence

## Why This Approach

### Approach A: Literal Port with Thread-Safe Methods

Chosen over idiomatic redesign (Approach B) and interface-first extensibility (Approach C).

**Rationale:** The parent epic's migration plan requires a concurrent operation period where Python Auraken and Go Skaffen read/write the same `core_profiles.style_fingerprint` JSONB column. JSON wire compatibility is non-negotiable during this window. A literal port with matching JSON tags ensures fingerprints written by Python are readable by Go and vice versa — no migration step required.

Thread-safe methods (mutex-protected `Update`/`BuildMirroring`) chosen over pure functions because Skaffen agents may process concurrent messages for the same user (e.g., burst messages arriving simultaneously). The mutex lives on `Fingerprint`, keeping the concurrency boundary tight.

**Post-migration:** Once Python Auraken is decommissioned (benl.11), field names can be refactored to Go conventions. This is a known tech-debt acceptance for migration safety.

## Key Decisions

1. **JSON field names match Python dict keys exactly.** `avg_words`, `pct_contraction`, `emoji_density` — not Go-style `AvgWords`. Struct tags enforce this. Verified against source: `style.py:206-225` (_empty_mode_profile keys).

2. **Thread-safe via mutex on Fingerprint.** `Update()` and `BuildMirroring()` acquire lock. `ComputeObservables()` and `ClassifyMode()` are pure functions — no lock needed.

3. **Regex compiled once at package init.** Go `regexp.MustCompile` in `var` block, same pattern as Python's module-level precompilation. One compiled regex per pattern — ~50 patterns total.

4. **EMA formula preserved exactly.** `alpha = 0.3` when `n >= 5`, else `1/(n+1)`. No smoothing changes. Vocabulary counters use raw increment (not EMA) — same as Python.

5. **No database dependency.** Package is pure computation. Serialization via `encoding/json` — callers handle DB read/write. Matches lens package pattern.

6. **Mode signal weights preserved.** Emotional=3, analytical=2, others=1. Pattern lists match Python exactly — verified against `style.py:39-92`.

7. **Package at `os/Skaffen/pkg/style/`.** Sibling to `pkg/lens/`. Same conventions: `doc.go`, `types.go`, separate files per concern, `_test.go` alongside.

## Open Questions

1. **Cadence gap tracking.** Python tracks `avg_burst_size` but the intra-burst gap timing isn't implemented (comment in docstring says it's tracked but no code computes it). Port the implemented behavior only, not the aspirational docstring.

2. **register_subscribers stub.** Python has a `register_subscribers()` stub that does nothing (comment says "TODO: replace direct call"). Skip this — Skaffen has its own event wiring.

3. **Test strategy.** Port with golden-file tests: feed same inputs to Python and Go, compare JSON output. This is the strongest parity guarantee. Exact approach for write-plan.
