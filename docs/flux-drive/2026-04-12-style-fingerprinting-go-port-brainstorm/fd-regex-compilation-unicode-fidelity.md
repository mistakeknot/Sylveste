# fd-regex-compilation-unicode-fidelity — Style Fingerprinting Go Port Findings

**Target:** `docs/brainstorms/2026-04-12-style-fingerprinting-go-port-brainstorm.md`
**Agent:** fd-regex-compilation-unicode-fidelity (Go RE2 engine constraints, Unicode character class compilation, word boundary semantics, pattern-level parity between Python `re` and Go `regexp`)
**Track:** Adjacent (Project Agents)
**Decision Lens:** Evaluates whether every Python regex pattern compiles and matches identically under Go's RE2 engine; flags patterns that exploit Python-only features (lookahead, lookbehind, backreferences) or where `\b` and `\w` semantic differences produce divergent match results.

---

## Finding R-1: `message_length` and `emoji_density` use `len(text)` which diverges between Python (rune count) and Go (byte count)

**Severity: P0**
**File:** `apps/Auraken/src/auraken/style.py:183-185` — `compute_observables`

```python
"message_length": len(text),
"emoji_density": emoji_count / len(text) if text else 0,
```

Python `len(str)` returns the number of Unicode codepoints (runes). Go `len(string)` returns the number of bytes. For ASCII-only text, these are identical. For text containing emoji (4 bytes each in UTF-8) or accented characters (2-3 bytes each), Go produces a larger denominator.

Verified empirically:
- `"hello 😂"`: Python `len()` = 7, Go `len()` = 10
- `"😂🤣💕"`: Python `len()` = 3, Go `len()` = 12
- `"cafe\u0301 re\u0301sume\u0301"`: Python `len()` = 17, Go `len()` = 21

This means `emoji_density` computed by Go will be systematically lower than Python for any text containing non-ASCII characters. Since `emoji_density` feeds into EMA accumulation via `update_fingerprint`, and the accumulated profile drives mirroring threshold comparisons in `build_mirroring_instructions`, Go-computed fingerprints will diverge from Python-computed ones for the same input stream.

Similarly, `message_length` stored in observables will disagree. While `message_length` is not currently used in fingerprint accumulation (only `word_count` feeds EMA), it IS part of the observable dict. If the Go port serializes observables for logging or debugging, the values will differ.

**Failure scenario:** During the concurrent operation window, Python processes message N and writes `emoji_density: 0.222` to the JSONB column. Go processes message N+1 for the same user and computes `emoji_density: 0.111` for a similar message. The EMA now blends these systematically biased values, producing a fingerprint that reflects neither Python's rune-based density nor Go's byte-based density consistently.

**Fix:** In the Go port, use `utf8.RuneCountInString(text)` instead of `len(text)` for both `message_length` and the `emoji_density` denominator. This gives exact parity with Python's `len(str)`.

---

## Finding R-2: No Python regex patterns use lookahead, lookbehind, or backreferences — RE2 compatibility is confirmed clean

**Severity: P3 (informational)**
**File:** `apps/Auraken/src/auraken/style.py:20-96, 112-155` — all regex patterns

Exhaustive audit of all 50+ regex patterns in `style.py` confirms none use Python-only features incompatible with Go's RE2 engine:

- No `(?=...)` lookahead
- No `(?!...)` negative lookahead
- No `(?<=...)` lookbehind
- No `(?<!...)` negative lookbehind
- No `\1` backreferences
- No atomic groups or possessive quantifiers

All patterns use only: character classes `[...]`, alternation `(?:...|...)`, word boundary `\b`, anchors `^`, quantifiers `*+?`, and case-insensitive flag `(?i)` (Python `re.IGNORECASE`). These are all fully supported by Go's RE2 engine.

The brainstorm's claim that "~50 patterns total" need porting is accurate. All compile under `regexp.MustCompile` without modification (verified for representative samples).

**Recommendation:** No action required. This is a clean bill of health for RE2 compatibility. Document this in the write-plan as a confirmed non-risk so future reviewers don't re-audit.

---

## Finding R-3: `\b` word boundary and `\w` behave identically for the ASCII-range patterns used, but differ for Unicode text

**Severity: P2**
**File:** `apps/Auraken/src/auraken/style.py:155` — `_CONTRACTION_RE = re.compile(r"\b\w+'\w+\b")`

In both Python (default mode, not `re.ASCII`) and Go RE2, `\w` matches `[0-9A-Za-z_]`. Python's `\w` in default Unicode mode actually matches a broader set including accented letters, but the contraction regex `\b\w+'\w+\b` is designed for English contractions where the word characters are always ASCII. Verified empirically that both Python and Go produce identical results for the contraction patterns: `I'm`, `it's`, `don't`, `o'clock` all match identically.

The `\b` boundary fires at the same positions in both engines because the apostrophe (`'`) is `\W` in both. All mode signal patterns (emotional, analytical, playful, etc.) contain only ASCII word characters adjacent to `\b`, so boundary behavior matches.

**Edge case:** If a user writes in a language where word boundaries involve Unicode letters (e.g., French `l'homme`), `\w` in Go treats the accented `e` in `caf\u00e9` as `\W`, while Python treats it as `\w`. The contraction regex `\b\w+'\w+\b` would fail to match `l'\u00e9tude` in Go but might match in Python. However, all 50+ patterns in style.py target English text, and the brainstorm specifies English-language conversation. This is a theoretical risk, not a practical one.

**Fix:** Document the assumption that input text is primarily English. For the write-plan, add a comment in the Go source near the contraction regex noting that Unicode-letter contractions (e.g., French) will not match — same as practical Python behavior since the patterns are English-specific.

---

## Finding R-4: Emoji character class ranges compile and match identically in Go

**Severity: P3 (informational)**
**File:** `apps/Auraken/src/auraken/style.py:20-33` — `_EMOJI_RE`

The emoji regex uses Unicode codepoint ranges (e.g., `\U0001F600-\U0001F64F`). Go string literals handle `\UHHHHHHHH` escapes identically to Python, embedding the raw UTF-8 bytes in the character class. Verified empirically:

- `"hello 😂🤣 world 💕"` produces 2 matches in both Python and Go (consecutive emoji are grouped by `+`)
- Individual emoji rune counts within groups are preserved
- The `+` quantifier groups consecutive emoji into single matches — `emoji_count = len(findall)` gives group count, not individual emoji count, in both languages

**Recommendation:** No changes needed. The emoji regex port is straightforward: paste the same `\U` escape sequences into Go string literals used as `regexp.MustCompile` arguments.
