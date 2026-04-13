---
artifact_type: prd
bead: sylveste-benl.2
stage: design
---

# PRD: Style Fingerprinting Go Package

## Problem

Auraken's style fingerprinting system (mode classification, EMA accumulation, mirroring instruction generation) is locked inside a Python monolith. Any Skaffen agent that talks to humans needs this capability, but it's inaccessible from the Go ecosystem. The Auraken-to-Skaffen migration (sylveste-benl) requires a concurrent operation period where both Python and Go read/write the same JSONB fingerprint column.

## Solution

Port `apps/Auraken/src/auraken/style.py` (595 lines) to `os/Skaffen/pkg/style/` as a reusable Go package with thread-safe fingerprint accumulation and JSON wire compatibility with existing Python-generated fingerprints. Fix the latent Python crash bug in `BuildInstantMirroring` during the port.

## Features

### F1: Type Definitions and Constructors

**What:** Define `Mode` enum, `Observables`, `ModeProfile`, and `Fingerprint` structs with JSON tags matching Python dict keys exactly.

**Acceptance criteria:**
- [ ] `Mode` type with 7 constants + `ModeGeneral` default
- [ ] `Observables` struct includes all fields from Python `compute_observables`: `word_count`, `message_length`, `capitalization_ratio`, `emoji_count`, `emoji_density`, `has_contraction`, `has_question`, `has_period`, `has_exclamation`, `is_all_lowercase`, `is_multi_sentence`, `laughter`, `affirmation`, `intensifiers`, `hedges`, `opener`, `mode`
- [ ] `ModeProfile` struct with 15 fields matching `_empty_mode_profile()` keys — JSON tags use singular `intensifier`/`hedge` (not plural)
- [ ] `NewModeProfile()` initializes all 5 vocabulary counter maps with `make(map[string]int)` — no nil maps
- [ ] `Fingerprint` struct with `sync.Mutex`, `MessageCount`, `Global`, `Modes`, `Cadence` — `Global` tagged `json:"global"`
- [ ] `NewFingerprint()` constructor
- [ ] Table-driven test: `reflect.TypeOf(ModeProfile{})` has exactly 15 exported fields, each with `json` tag matching Python keylist
- [ ] Table-driven test: `Fingerprint` top-level JSON keys match `["message_count", "global", "modes", "cadence"]`
- [ ] `encoding/json.Marshal(NewModeProfile())` produces `{}` for vocabulary counters, not `null`
- [ ] No `omitempty` on vocabulary counter map fields
- [ ] `ensureMaps()` method called after JSON unmarshal to guarantee non-nil maps

### F2: Observable Extraction

**What:** `ComputeObservables(text) Observables` and `ClassifyMode(text) Mode` — pure functions with ~90 compiled regexes.

**Acceptance criteria:**
- [ ] All regex patterns from Python compiled via `regexp.MustCompile` at package init
- [ ] Emoji regex uses Go `\x{NNNNNN}` syntax (not Python `\U` escapes)
- [ ] `emoji_density` and `message_length` use `utf8.RuneCountInString(text)` (not `len()`)
- [ ] Mode signal weights preserved: emotional=3, analytical=2, others=1 — as named constants
- [ ] `ClassifyMode` tie-breaking via canonical priority slice `[emotional, analytical, playful, intimate, logistics, update]` — not map iteration
- [ ] `_detect_tokens` equivalent preserves duplicate labels (no deduplication)
- [ ] Word splitting uses `strings.Fields(text)` (not `strings.Split`)
- [ ] Opener extraction uses `strings.ToLower` + `strings.TrimRight(word, ",.!?")`
- [ ] `is_multi_sentence` uses `regexp.Split(text, -1)` with `> 2` threshold
- [ ] `\w`/`\b` ASCII-only behavior documented in godoc
- [ ] `ComputeObservables` and `ClassifyMode` are pure functions — no package-level mutable state after init

### F3: Fingerprint Accumulation

**What:** Thread-safe EMA-based fingerprint accumulation with mutex-protected methods.

**Acceptance criteria:**
- [ ] `(*Fingerprint) Update(obs Observables)` acquires mutex, updates global + per-mode profiles, increments message count
- [ ] `(*Fingerprint) UpdateCadence(burstSize int)` acquires same `Fingerprint` mutex (not a separate lock)
- [ ] `(*Fingerprint) UpdateWithCadence(obs Observables, burstSize int)` atomic combined method
- [ ] EMA uses exact operator form: `old*(1-alpha) + new*alpha` — not refactored to `old + alpha*(new-old)`
- [ ] Alpha check uses pre-increment n: `alpha = 0.3` when `n >= 5` (before `n = n + 1`)
- [ ] New mode profile created via `NewModeProfile()` when mode first seen (inside lock)
- [ ] Vocabulary counters increment raw counts (not EMA)
- [ ] Boolean rates use EMA with 1.0/0.0 values
- [ ] `go test -race` passes with 50 concurrent goroutines calling `Update` + `BuildMirroring` on same `Fingerprint`

### F4: Mirroring Instruction Generation

**What:** Generate concrete mirroring instructions from accumulated fingerprint stats or single-message observables.

**Acceptance criteria:**
- [ ] `(*Fingerprint) BuildMirroring(mode Mode) string` copies `ModeProfile` fields under lock, releases, generates text from copy
- [ ] Guard `message_count < 3` checked inside lock acquisition
- [ ] Falls back from mode-specific to global profile when mode profile has `n < 2`
- [ ] All 7 threshold-based instructions preserved with exact strings (including em dashes, inequality directions)
- [ ] Laughter/intensifier dominance calculations guard against division by zero
- [ ] Hedge emotional-mode special case: `"i feel like" in hedge` check
- [ ] Cadence burst instruction at `avg_burst >= 1.8`
- [ ] Mode context notes copied character-for-character from Python source
- [ ] `BuildInstantMirroring(text string) string` uses `obs.Laughter[0]` (fixes Python crash bug at lines 536-542)
- [ ] `DetectCurrentMode(messages []string, window int) Mode` filters `general` before majority vote, uses canonical priority for ties
- [ ] Godoc documents: "DetectCurrentMode does not hold Fingerprint mutex; caller must ensure messages slice is not concurrently modified"

### F5: Golden-File Parity Tests

**What:** Generate test fixtures from Python source, verify Go output is wire-compatible.

**Acceptance criteria:**
- [ ] Python script generates golden fixtures: 20-message sequence covering all 7 modes, messages 4-6 bracketing alpha transition, boundary-scoring messages for tie-breaking
- [ ] Go test reads fixtures, feeds same inputs, compares JSON output
- [ ] Float comparison uses decoded `float64` equality (not byte-string diff)
- [ ] Duplicate laughter label test: "ahaha" increments `"haha"` counter by 2
- [ ] `is_multi_sentence` boundary tests at exactly 2 and 3 split parts
- [ ] Round-trip test: Python writes → Go reads → Go writes → Python reads → compare
- [ ] `go test -race` concurrent test: 50 goroutines, 1000 iterations on same Fingerprint

## Non-goals

- Unicode-aware `\w`/`\b` matching (ASCII-only scope, documented)
- Decay for absent modes (known limitation, preserved from Python)
- Opener counter size bounds (tech debt for benl.11)
- New emoji Unicode range coverage beyond Python's current set
- Database interaction (package is pure computation)
- Signal bus / subscriber registration (Skaffen has its own event wiring)

## Dependencies

- `os/Skaffen/pkg/lens/` — sibling package, conventions reference (no code dependency)
- `apps/Auraken/src/auraken/style.py` — Python source for port
- `github.com/mistakeknot/Skaffen` Go module
- Standard library only: `regexp`, `sync`, `encoding/json`, `unicode/utf8`, `strings`, `math`, `sort`

## Open Questions

1. **Unicode case folding:** `strings.ToLower` vs Python `str.lower()` may diverge for Turkish/German/Greek characters. Accepted for this port — document as ASCII-typical scope.
2. **Cadence caller contract:** Who calls `UpdateCadence` and when? Document in godoc that callers must call `UpdateWithCadence` for atomic burst+message updates.
3. **Float serialization epsilon:** Should golden-file comparison use exact equality or epsilon tolerance? Recommendation: exact equality on decoded float64 (Go and Python both use IEEE 754 double).
