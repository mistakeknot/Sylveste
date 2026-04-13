---
artifact_type: plan
bead: sylveste-benl.2
prd: docs/prds/2026-04-12-style-fingerprinting-go-port.md
brainstorm: docs/brainstorms/2026-04-12-style-fingerprinting-go-port-brainstorm.md
review_synthesis: docs/research/flux-review/style-fingerprinting-go-port/2026-04-12-synthesis.md
stage: plan
---

# Plan: Style Fingerprinting Go Port

Port `apps/Auraken/src/auraken/style.py` (595 lines) to `os/Skaffen/pkg/style/`.

**Source:** Python style.py at `apps/Auraken/src/auraken/style.py`
**Target:** `os/Skaffen/pkg/style/`
**Go module:** `github.com/mistakeknot/Skaffen`
**Convention reference:** `os/Skaffen/pkg/lens/` (sibling package)

## Critical Constraints (from flux-review synthesis)

These are non-negotiable acceptance gates surfaced by the 4-track, 16-agent review:

### P0 Gates
1. All vocabulary counter maps initialized via `make(map[string]int)` — no nil maps ever
2. No `omitempty` on map fields; `ensureMaps()` after JSON unmarshal
3. `ClassifyMode`/`DetectCurrentMode` use canonical priority slice for tie-breaking
4. `emoji_density`/`message_length` use `utf8.RuneCountInString` (not `len`)
5. `BuildInstantMirroring` uses `obs.Laughter[0]` — fixes Python crash bug
6. `BuildMirroring` copies ModeProfile fields under lock, releases, generates text
7. EMA operator form: `old*(1-alpha) + new*alpha` exactly
8. Alpha check uses n's value *before* increment (`n >= 5` where n has NOT yet been incremented — at the 6th message, n=5 going in)
9. All Fingerprint mutations share single `sync.Mutex` (including `UnmarshalJSON`)
10. Table-driven struct tag test for all 19 JSON-serialized fields
11. `Update` must skip zero-value `Observables` (empty text → no fingerprint change, matching Python's `if not new_obs: return existing`)
12. `UnmarshalJSON` acquires mutex — prevents race with concurrent `Update`/`BuildMirroring`

### P1 Requirements
1. Go `\w`/`\b` ASCII-only — document in godoc
2. `UpdateWithCadence` combined atomic method
3. `intensifier`/`hedge` singular JSON tags; `Intensifiers`/`Hedges` plural Go fields
4. `strings.Fields(text)` not `strings.Split`
5. `message_length` and `emoji_count` in Observables struct
6. `BuildMirroring` guard `< 3` inside lock
7. Mode context notes character-for-character from Python
8. Duplicate laughter labels preserved (no dedup)
9. `is_multi_sentence` via `regexp.Split(text, -1)` with `> 2`
10. `go test -race` with 50 concurrent goroutines
11. Golden-file comparison via decoded float64
12. Mode weights as named constants

## File Layout

```
os/Skaffen/pkg/style/
  doc.go              # Package doc
  mode.go             # Mode type, classification, signal patterns
  mode_test.go        # Mode tests
  observables.go      # ComputeObservables, regex patterns
  observables_test.go # Observable tests
  types.go            # Observables, ModeProfile, Fingerprint structs
  types_test.go       # Struct tag parity tests, JSON marshal tests
  fingerprint.go      # Update, UpdateCadence, UpdateWithCadence, EMA
  fingerprint_test.go # Accumulation tests, concurrent tests
  mirroring.go        # BuildMirroring, BuildInstantMirroring, DetectCurrentMode
  mirroring_test.go   # Instruction generation tests
  testdata/
    golden_fixtures.json  # Generated from Python
```

## Tasks

### Task 1: Package scaffold and type definitions (F1)

**Files:** `doc.go`, `types.go`, `types_test.go`

**Steps:**
1. Create `doc.go`:
   ```go
   // Package style provides mode-aware style fingerprinting — tracks how users
   // communicate across different conversation modes and generates specific
   // mirroring instructions. Port of Auraken's style.py.
   package style
   ```

2. Create `types.go` with:
   - `Mode` string type with constants: `ModeEmotional`, `ModeAnalytical`, `ModePlayful`, `ModeIntimate`, `ModeLogistics`, `ModeUpdate`, `ModeGeneral`
   - `modePriority` unexported slice: `[]Mode{ModeEmotional, ModeAnalytical, ModePlayful, ModeIntimate, ModeLogistics, ModeUpdate}` — canonical tie-breaking order
   - `Observables` struct — all 17 fields from Python `compute_observables` output. JSON tags match Python keys. Note: `Intensifiers []string` (plural Go field) but this struct is not stored in JSONB — only used transiently.
   - `ModeProfile` struct — 15 fields matching `_empty_mode_profile()`. JSON tags: `json:"avg_words"`, `json:"capitalization_ratio"`, `json:"emoji_density"`, `json:"pct_contraction"`, `json:"pct_question"`, `json:"pct_period"`, `json:"pct_exclamation"`, `json:"pct_lowercase"`, `json:"pct_multi_sentence"`, `json:"n"`, `json:"laughter"`, `json:"affirmation"`, `json:"intensifier"` (singular!), `json:"hedge"` (singular!), `json:"opener"`. No `omitempty` on any map field.
   - `Cadence` struct: `AvgBurstSize float64 json:"avg_burst_size"`, `BurstCount int json:"burst_count"`
   - `Fingerprint` struct: `mu sync.Mutex` (unexported, no JSON tag), `MessageCount int json:"message_count"`, `Global *ModeProfile json:"global"`, `Modes map[Mode]*ModeProfile json:"modes"`, `Cadence Cadence json:"cadence"`
   - `NewModeProfile()` — returns `*ModeProfile` with all 5 maps initialized via `make(map[string]int)`
   - `NewFingerprint()` — returns `*Fingerprint` with `Global: NewModeProfile()`, `Modes: make(map[Mode]*ModeProfile)`, `Cadence: Cadence{AvgBurstSize: 1.0}`
   - `(*ModeProfile) ensureMaps()` — called after JSON unmarshal, initializes any nil maps
   - `(*Fingerprint) UnmarshalJSON(data []byte)` — custom unmarshaler that acquires mutex, delegates to standard unmarshal, calls `ensureMaps()` on Global and all mode profiles, then releases mutex. Prevents race with concurrent `Update`/`BuildMirroring`.

3. Create `types_test.go` with:
   - `TestModeProfileJSONTagParity` — table-driven: `reflect.TypeOf(ModeProfile{})` has exactly 15 exported fields, each `json` tag matches Python keylist `["n", "avg_words", "capitalization_ratio", "emoji_density", "pct_contraction", "pct_question", "pct_period", "pct_exclamation", "pct_lowercase", "pct_multi_sentence", "laughter", "affirmation", "intensifier", "hedge", "opener"]`
   - `TestFingerprintJSONTagParity` — top-level keys: `["message_count", "global", "modes", "cadence"]`
   - `TestNewModeProfileMapsNonNil` — all 5 maps non-nil after `NewModeProfile()`
   - `TestModeProfileMarshalEmptyMaps` — `json.Marshal(NewModeProfile())` produces `{}` for each map, not `null`
   - `TestFingerprintUnmarshalEnsuresMaps` — unmarshal JSON with `"laughter":null`, verify map is non-nil after

**Verify:** `cd os/Skaffen && go test ./pkg/style/ -run TestMode -v && go vet ./pkg/style/`

### Task 2: Mode classification (F2 partial)

**Files:** `mode.go`, `mode_test.go`

**Steps:**
1. Create `mode.go` with:
   - Mode weight constants: `const weightEmotional = 3; const weightAnalytical = 2; const weightDefault = 1`
   - `modeSignal` struct: `weight int`, `patterns []*regexp.Regexp`
   - `modeSignals` package-level `map[Mode]modeSignal` populated in `init()` — compile all patterns from Python `_RAW_SIGNALS` (lines 39-92). Use `regexp.MustCompile` with `(?i)` flag prefix for case-insensitive. Convert Python `\b` to Go `\b` (identical for ASCII). Convert emoji literals to `\x{NNNN}` hex escapes.
   - `ClassifyMode(text string) Mode` — for each mode in `modePriority`, count matching patterns and multiply by mode weight (score = matching_patterns * weight). Iterate the priority slice (not map keys) to find max score. For ties, the first mode in priority order wins.

2. Create `mode_test.go` with:
   - `TestClassifyModeClear` — unambiguous messages for each of 7 modes
   - `TestClassifyModeTieBreaking` — "i feel like the framework is important" → `ModeEmotional` (emotional and analytical both score, emotional wins by priority)
   - `TestClassifyModeGeneral` — "hello there" → `ModeGeneral` (no patterns match)
   - `TestClassifyModeEmoji` — messages with emoji-only patterns for playful/intimate modes

**Verify:** `cd os/Skaffen && go test ./pkg/style/ -run TestClassifyMode -v`

### Task 3: Observable extraction (F2 complete)

**Files:** `observables.go`, `observables_test.go`

**Steps:**
1. Create `observables.go` with:
   - Package-level compiled regexes (all `var` block, `regexp.MustCompile`):
     - `emojiRE` — 9 Unicode ranges using `\x{NNNNNN}` syntax
     - `contractionRE` — `\b\w+'\w+\b` (ASCII `\w`, documented)
     - `laughterPatterns` — `[]struct{pattern *regexp.Regexp; label string}` — 4 entries
     - `affirmationPatterns` — 10 entries (anchored with `^` + `(?i)`)
     - `intensifierPatterns` — 9 entries
     - `hedgePatterns` — 8 entries
     - `multiSentenceRE` — `[.!?]+`
   - `detectTokens(text string, patterns []struct{...}) []string` — returns ALL matching labels (no dedup). Both `haha` patterns can fire on "ahaha", returning `["haha", "haha"]`.
   - `ComputeObservables(text string) Observables`:
     - Empty text → zero Observables
     - `strings.Fields(text)` for word splitting (not `strings.Split`)
     - `utf8.RuneCountInString(text)` for `MessageLength`
     - Alpha chars counted via `unicode.IsLetter`, upper via `unicode.IsUpper`
     - `utf8.RuneCountInString(text)` for `EmojiDensity` denominator
     - Opener: `strings.ToLower(words[0])` then `strings.TrimRight(word, ",.!?")`
     - `is_multi_sentence`: `multiSentenceRE.Split(strings.TrimSpace(text), -1)` → `len(parts) > 2`
     - Mode: calls `ClassifyMode(text)`

2. Create `observables_test.go` with:
   - `TestComputeObservablesEmpty` — empty string → zero Observables
   - `TestComputeObservablesBasic` — "hey how are you" → word_count=4, has_question=false (no ?), opener="hey"
   - `TestEmojiDensityUsesRuneCount` — "hello 😂" → emoji_density = 1/7 (runes), NOT 1/10 (bytes)
   - `TestMessageLengthUsesRuneCount` — "café" → message_length = 4, NOT 5
   - `TestDuplicateLaughterLabels` — "ahaha" matches both patterns → laughter = ["haha", "haha"]
   - `TestOpenerLeadingWhitespace` — "  Hey how" → opener = "hey" (strings.Fields strips leading space)
   - `TestMultiSentenceBoundary` — "Hello!" → false, "Hello! Bye." → true
   - `TestContractionDetection` — "I'm fine" → has_contraction=true, "I am fine" → false

**Verify:** `cd os/Skaffen && go test ./pkg/style/ -run TestComputeObservables -v`

### Task 4: Fingerprint accumulation (F3)

**Files:** `fingerprint.go`, `fingerprint_test.go`

**Steps:**
1. Create `fingerprint.go` with:
   - `ema(old, new, alpha float64) float64` — exact form: `old*(1-alpha) + new*alpha`
   - `(*ModeProfile) update(obs Observables)` — unexported, called under lock:
     - Read `n := p.N` (pre-increment)
     - Compute `alpha`: if `n >= 5` → `0.3`, else `1.0 / float64(n+1)`
     - EMA update for: AvgWords, CapitalizationRatio, EmojiDensity
     - Boolean EMA for: PctContraction, PctQuestion, PctPeriod, PctExclamation, PctLowercase, PctMultiSentence (1.0 if true, 0.0 if false)
     - Vocabulary counter increment (raw, not EMA): laughter, affirmation, intensifier, hedge, opener
     - Increment `p.N`
   - `(*Fingerprint) Update(obs Observables)`:
     - If `obs.WordCount == 0 && obs.Mode == ""` → return (skip zero-value, matching Python's `if not new_obs`)
     - Lock mutex
     - `f.Global.update(obs)`
     - Mode lookup: `profile, ok := f.Modes[obs.Mode]`; if !ok → `profile = NewModeProfile(); f.Modes[obs.Mode] = profile`
     - `profile.update(obs)`
     - Increment `f.MessageCount`
     - Unlock mutex
   - `(*Fingerprint) UpdateCadence(burstSize int)`:
     - Lock SAME mutex
     - Compute alpha (same formula, using `f.Cadence.BurstCount` as n)
     - EMA update `f.Cadence.AvgBurstSize`
     - Increment `f.Cadence.BurstCount`
     - Unlock
   - `(*Fingerprint) UpdateWithCadence(obs Observables, burstSize int)`:
     - Lock mutex once
     - Call internal update logic (no double-lock)
     - Call internal cadence logic
     - Unlock

2. Create `fingerprint_test.go` with:
   - `TestEMAFormula` — verify `ema(10.0, 20.0, 0.3)` == `10.0*0.7 + 20.0*0.3` == `13.0`
   - `TestAlphaBoundary` — feed 6 observations, check alpha is `1/(n+1)` for first 5 (n=0..4), then `0.3` for 6th (n=5)
   - `TestUpdateNewMode` — first message in a new mode creates profile via NewModeProfile (maps non-nil)
   - `TestVocabularyCounterIncrement` — 3 messages with "haha" → laughter["haha"]==3 (raw count, not EMA)
   - `TestUpdateSkipsZeroObservables` — `Update(Observables{})` leaves `MessageCount` unchanged
   - `TestConcurrentUpdate` — 50 goroutines, 100 iterations each, `go test -race`. All call `Update` + `BuildMirroring` on same Fingerprint.
   - `TestUpdateWithCadenceAtomic` — verify message_count and burst_count are consistent after atomic update

**Verify:** `cd os/Skaffen && go test ./pkg/style/ -run TestEMA -v -race && go test ./pkg/style/ -run TestConcurrent -v -race`

### Task 5: Mirroring instruction generation (F4)

**Files:** `mirroring.go`, `mirroring_test.go`

**Steps:**
1. Create `mirroring.go` with:
   - `laughAlt(top string) string` — map: haha→lol, lol→haha, lmao→haha
   - `modeContextNote(mode Mode) string` — 6 mode notes copied character-for-character from Python (lines 470-496). Returns "" for ModeGeneral.
   - `(*Fingerprint) BuildMirroring(mode Mode) string`:
     - Lock mutex
     - Guard 1: if `f.MessageCount < 3` → unlock, return "" (inside lock)
     - Look up mode profile; if absent or `profile.N < 2` → fall back to Global
     - Guard 2: if fallback Global also has `N < 3` → unlock, return ""
     - **Copy all fields** into a local `profileCopy` value struct (not pointer):
       ```go
       type profileSnapshot struct {
           N int
           AvgWords float64
           // ... all scalar fields ...
           Laughter map[string]int // shallow copy: make + range
           // ... all map fields ...
       }
       ```
     - Copy `f.Cadence` into local cadence value
     - Unlock mutex
     - Generate instructions from the local copies (all string building happens outside lock)
     - 7 threshold checks (length, capitalization, punctuation, contractions, laughter, affirmation, intensifier, hedge, cadence, mode note) — exact thresholds from Python
     - If no instructions generated (all thresholds miss) → return ""
     - Format: header + `"\n".join("- " + instruction)` + footer
     - Header: `"\n## Communication Style — Mirror This Person\n"`
     - Footer: `"\n\nMirror their style by default. Use their vocabulary and tone.\n"` (note: double `\n` before "Mirror")

   - `BuildInstantMirroring(text string) string`:
     - Call `ComputeObservables(text)` (pure, no lock)
     - Check length, case, punctuation, contractions, vocabulary
     - **Fix Python bug:** `obs.Laughter[0]` (first element of slice), NOT `.keys()[0]`. Guard with `len(obs.Laughter) > 0`.
     - Same for affirmation: `obs.Affirmation[0]` with length guard
     - Header: `"\n## Communication Style — Match This Message\n"`

   - `DetectCurrentMode(messages []string, window int) Mode`:
     - Take last `window` messages
     - Classify each via `ClassifyMode`
     - Filter out `ModeGeneral`
     - Majority vote using `modePriority` for tie-breaking (iterate priority slice, pick first mode with max count)
     - Return `ModeGeneral` if all are general
     - Godoc: "Does not hold Fingerprint mutex; caller must ensure messages slice is not concurrently modified."

2. Create `mirroring_test.go` with:
   - `TestBuildMirroringTooFewMessages` — 2 messages → "" (empty string)
   - `TestBuildMirroringShortMessages` — avg_words <= 5 → "Keep responses very short"
   - `TestBuildMirroringLowercaseUser` — pct_lowercase > 0.6 → "Use lowercase"
   - `TestBuildMirroringLaughterDominance` — haha=10, lol=1 → "use 'haha' — never 'lol'"
   - `TestBuildMirroringEmptyInstructions` — user with average metrics where no threshold triggers → returns ""
   - `TestBuildMirroringSafeUnderConcurrency` — call BuildMirroring from 10 goroutines while Update runs on 10 others
   - `TestBuildInstantMirroringWithLaughter` — message with "haha" → instruction includes laughter guidance (verifies Python bug is fixed)
   - `TestDetectCurrentModeMajority` — 3 emotional + 2 analytical → ModeEmotional
   - `TestDetectCurrentModeAllGeneral` — 5 "hello" messages → ModeGeneral
   - `TestDetectCurrentModeTieBreaking` — 2 emotional + 2 analytical → ModeEmotional (priority)

**Verify:** `cd os/Skaffen && go test ./pkg/style/ -run TestBuildMirroring -v -race`

### Task 6: Golden-file parity tests (F5)

**Files:** `testdata/generate_fixtures.py`, `testdata/golden_fixtures.json`, `parity_test.go`

**Steps:**
1. Create `testdata/generate_fixtures.py`:
   - Import `sys, os; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../../apps/Auraken/src'))`
   - Import `auraken.style`
   - Define 20 test messages covering: all 7 modes, messages 4-6 for alpha transition, tie-breaking boundary messages, emoji-heavy message, all-lowercase message, multi-sentence message, empty string
   - For each message: compute observables, update fingerprint, serialize to JSON
   - Capture fingerprint state after each message
   - Write `golden_fixtures.json`: `{"messages": [...], "fingerprints_after_each": [...], "final_mirroring": {"general": "...", "emotional": "..."}}`
   - **Note:** `build_instant_mirroring` laughter/affirmation branches will crash in Python — capture the exception and mark those fields as `"PYTHON_BUG_SKIPPED"` in the fixture

2. Generate fixtures: `cd os/Skaffen/pkg/style && python3 testdata/generate_fixtures.py`

3. Create `parity_test.go` with:
   - `TestGoldenFileParity` — load `testdata/golden_fixtures.json`, replay all 20 messages through Go `ComputeObservables` + `Update`, compare fingerprint JSON after each message
   - Float comparison: `json.Unmarshal` both sides, compare decoded float64 values with exact equality (both are IEEE 754)
   - Map comparison: sort keys before comparison
   - `TestGoldenMirroringParity` — compare `BuildMirroring` output for general and emotional modes
   - `TestInstantMirroringFixed` — verify Go produces correct output where Python crashes (laughter/affirmation branches)
   - `TestRoundTrip` — Go marshals fingerprint → Python unmarshals (via subprocess) → Python marshals → Go unmarshals → compare. Verifies bidirectional wire compatibility.
   - `TestConcurrentRace` — 50 goroutines calling Update + BuildMirroring for 1000 iterations on same Fingerprint. Run with `-race`.

**Verify:** `cd os/Skaffen && go test ./pkg/style/ -run TestGolden -v && go test ./pkg/style/ -v -race -count=1`

## Build Sequence

```
Task 1 (types)  →  Task 2 (mode)  →  Task 3 (observables)  →  Task 4 (fingerprint)  →  Task 5 (mirroring)  →  Task 6 (golden tests)
```

Sequential — each task depends on the previous. After each task, run `go vet ./pkg/style/` and the task-specific tests.

Final verification after all tasks: `cd os/Skaffen && go test ./pkg/style/ -v -race -count=1 && go vet ./pkg/style/`

## Risk Mitigations

| Risk | Mitigation |
|------|-----------|
| Regex syntax divergence (Python \U vs Go \x{}) | Task 3 converts all emoji ranges; test each pattern individually |
| EMA floating-point drift | Task 4 golden-file comparison with exact decoded float64 equality |
| Map tie-breaking nondeterminism | Task 2 uses canonical priority slice; golden-file catches divergence |
| Nil map panic during concurrent operation | Task 1 NewModeProfile + ensureMaps + custom UnmarshalJSON |
| Lock contention under burst | Task 5 copy-under-lock pattern resolves both safety and performance |
| Python crash bug propagation | Task 5 explicitly fixes with slice index + length guard |
