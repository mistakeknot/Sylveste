# SYNTHESIS -- Style Fingerprinting Go Port Brainstorm (Track: Adjacent)

**Target:** `docs/brainstorms/2026-04-12-style-fingerprinting-go-port-brainstorm.md`
**Track:** Adjacent (Project Agents)
**Agents:** fd-regex-compilation-unicode-fidelity, fd-ema-float-accumulation-parity, fd-json-wire-compatibility-struct-tags, fd-fingerprint-concurrency-model, fd-mirroring-instruction-determinism
**Date:** 2026-04-12
**Bead:** sylveste-benl.2 (stage: discover)

---

## Findings Summary

| ID | Severity | Agent | Finding |
|----|----------|-------|---------|
| R-1 | P0 | Regex/Unicode | `len(text)` gives bytes in Go vs runes in Python -- `message_length` and `emoji_density` diverge for non-ASCII text |
| J-1 | P0 | JSON Wire | Go nil maps serialize as `null` vs Python `{}`; causes `AttributeError` in Python on read and nil-map panic in Go |
| M-1 | P0 | Mirroring Determinism | Latent Python bug: `build_instant_mirroring` calls `.keys()` on a list -- crashes on laughter/affirmation detection |
| E-3 | P1 | EMA Float | Vocabulary counter maps need explicit initialization after JSON unmarshal to avoid nil-map panic |
| J-3 | P1 | JSON Wire | Vocabulary counters must be `map[string]int` not `map[string]float64` to match Python integer semantics |
| C-1 | P1 | Concurrency | `BuildMirroring` must not leak internal map references through the lock boundary |
| C-3 | P1 | Concurrency | `UpdateCadence` must acquire same mutex as `Update` -- both modify shared `Fingerprint` state |
| M-6 | P1 | Mirroring Determinism | Mode context note strings must match Python character-for-character -- fed directly to LLM system prompts |
| R-3 | P2 | Regex/Unicode | `\b` and `\w` differ for Unicode letters (accented chars) -- theoretical risk for non-English text |
| J-2 | P2 | JSON Wire | `float64(0)` serializes as `0` in Go vs `0.0` in Python -- breaks golden-file byte comparison |
| M-2 | P2 | Mirroring Determinism | `max()` tie-breaking: Python uses insertion order, Go map iteration is random -- affects tied counters |
| M-3 | P2 | Mirroring Determinism | `Counter.most_common()` tie-breaking differs -- same root cause as M-2 |
| C-4 | P2 | Concurrency | `DetectCurrentMode` callers must not pass concurrently-modified message slices |
| R-2 | P3 | Regex/Unicode | No Python patterns use lookahead/lookbehind/backreferences -- RE2 compatibility confirmed clean |
| R-4 | P3 | Regex/Unicode | Emoji character class ranges compile and match identically in Go |
| E-1 | P3 | EMA Float | EMA arithmetic is bit-identical between Python float and Go float64 -- verified empirically |
| E-2 | P3 | EMA Float | Alpha transition discontinuity at n=5 handled identically by both languages |
| E-4 | P3 | EMA Float | `n` field as `int` is safe -- no overflow risk |
| J-4 | P3 | JSON Wire | Map key ordering differs (insertion vs alphabetical) -- cosmetic, no functional impact through JSONB |
| J-5 | P3 | JSON Wire | Cadence struct is trivially portable |
| M-4 | P3 | Mirroring Determinism | Em-dash (U+2014) in instruction strings needs no special handling in Go |
| M-5 | P3 | Mirroring Determinism | `_laugh_alt` lookup is trivially portable |
| C-2 | P3 | Concurrency | `sync.Mutex` on Fingerprint is correct granularity -- validated |

**Total findings: 23**
- P0: 3
- P1: 5
- P2: 5
- P3: 10

---

## Cross-Agent Convergence

Three findings converge from different lenses onto the same root issue:

### Convergence 1: nil maps are the dominant wire compatibility risk (J-1 + E-3)

The JSON Wire agent (J-1) and EMA Float agent (E-3) independently identified that Go's nil map serialization as `null` is the primary wire compatibility hazard. J-1 identified the Python read failure (`AttributeError` on `None.get()`). E-3 identified the Go write failure (nil-map panic on increment). Both point to the same fix: mandatory map initialization via `ensureMaps()` after construction and after unmarshal.

**Combined severity: P0.** This is the single most likely production failure during the concurrent operation window.

### Convergence 2: `len(text)` semantic gap is the dominant computation parity risk (R-1)

Only the Regex/Unicode agent identified this, but it affects two observables (`message_length` and `emoji_density`) that feed into EMA accumulation. The fix is surgical: use `utf8.RuneCountInString(text)` instead of `len(text)`. No other agent's findings intersect with this -- the EMA Float agent confirmed the arithmetic is identical IF the inputs are identical, which makes R-1 the gating dependency.

**Combined severity: P0.** Without this fix, fingerprints will drift during concurrent operation for any user who sends emoji or non-ASCII text.

### Convergence 3: Map iteration order affects determinism but not correctness (M-2 + M-3 + J-4)

Three findings from two agents (Mirroring Determinism and JSON Wire) note that Go's random map iteration differs from Python's insertion-order iteration. This affects: (1) `max()` tie-breaking for vocabulary tokens, (2) `Counter.most_common()` tie-breaking for mode detection, and (3) JSON key ordering in serialized fingerprints. None of these cause functional failures -- tied counters are semantically equivalent, and JSONB ignores key order. But golden-file tests will be non-deterministic without explicit tie-breaking.

**Combined severity: P2.** Fix with alphabetical tie-breaking in Go. Affects test strategy, not production correctness.

---

## Clean Bills of Health

The review produced several definitive confirmations:

1. **RE2 compatibility is clean.** No Python regex pattern in `style.py` uses features unsupported by Go's RE2 engine. All ~50 patterns compile and match identically. (R-2, R-4)

2. **EMA arithmetic is bit-identical.** Python `float` and Go `float64` produce the same results for the same inputs at all precision levels tested. The alpha computation, including the `1/(n+1)` fractional values, matches to the last representable bit. (E-1, E-2)

3. **Mutex on Fingerprint is correct.** The concurrency model proposed in the brainstorm (mutex-protected `Update`/`BuildMirroring`, pure `ComputeObservables`/`ClassifyMode`) is the right design. No per-field or per-mode locking is needed. (C-2)

4. **Word boundary behavior matches for English text.** `\b` and `\w` in Go RE2 produce identical results to Python `re` for all patterns in `style.py`, which target English vocabulary exclusively. (R-3, confirmed for contraction regex, all mode signal patterns)

---

## Recommendations for Write-Plan

### Must-fix before implementation (P0):

1. **Use `utf8.RuneCountInString(text)` for `message_length` and `emoji_density` denominator.** (R-1)
2. **Initialize all `map[string]int` fields via `ensureMaps()` in constructor and after `json.Unmarshal`.** Never use `omitempty` on map fields. (J-1, E-3)
3. **Fix the Python source bug in `build_instant_mirroring` lines 537 and 541**: change `list(obs["laughter"].keys())[0]` to `obs["laughter"][0]`. Port the corrected version to Go. (M-1)

### Must-fix during implementation (P1):

4. **`UpdateCadence` must acquire `fp.mu.Lock()`.** Add concurrent test. (C-3)
5. **Use `map[string]int` for vocabulary counters.** (J-3)
6. **Copy mode context note strings character-for-character from Python source.** Verify with golden-file test. (M-6)
7. **`BuildMirroring` must not return internal map references.** Document invariant. (C-1)

### Should-fix for test reliability (P2):

8. **Implement alphabetical tie-breaking for `max()` on maps.** (M-2, M-3)
9. **Golden-file tests must compare parsed JSON, not raw bytes.** (J-2, J-4)
10. **Document English-text assumption for word boundary behavior.** (R-3)
11. **Document thread-safety contract for `DetectCurrentMode` input slices.** (C-4)
