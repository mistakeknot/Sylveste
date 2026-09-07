# fd-mirroring-instruction-determinism — Style Fingerprinting Go Port Findings

**Target:** `docs/brainstorms/2026-04-12-style-fingerprinting-go-port-brainstorm.md`
**Agent:** fd-mirroring-instruction-determinism (instruction string exact parity, threshold boundary behavior, map iteration order in `max()` calls, latent Python bugs that should not be ported)
**Track:** Adjacent (Project Agents)
**Decision Lens:** Evaluates whether `BuildMirroring` and `BuildInstantMirroring` in Go produce byte-identical instruction strings to their Python equivalents given identical fingerprint/observable inputs, and flags any Python-side bugs that would silently transfer to Go.

---

## Finding M-1: `build_instant_mirroring` has a latent crash bug — `list(obs["laughter"].keys())[0]` called on a list, not a dict

**Severity: P0**
**File:** `apps/Auraken/src/auraken/style.py:536-541`

```python
if obs["laughter"]:
    laugh = list(obs["laughter"].keys())[0]
    instructions.append("They use '%s' --- use that, not alternatives." % laugh)

if obs["affirmation"]:
    affirm = list(obs["affirmation"].keys())[0]
    instructions.append("They say '%s' --- mirror that." % affirm)
```

`compute_observables` returns `"laughter": _detect_tokens(text, _LAUGHTER_PATTERNS)` which is a `list[str]`, e.g., `["haha", "lol"]`. The code then calls `.keys()` on this list. `list` objects do not have a `.keys()` method. This raises `AttributeError: 'list' object has no attribute 'keys'` at runtime.

The same bug exists on line 541 for `affirmation`.

This bug is latent because `build_instant_mirroring` is called for early conversations (< 3 messages). If no laughter pattern matches in the first few messages, the `if obs["laughter"]:` check fails (empty list is falsy) and the buggy line is never reached. But for any message containing "haha", "lol", or "lmao" in the first 3 messages of a conversation, this function will crash.

**Verified:** The existing Python tests in `tests/test_agent.py` test `compute_observables` and `update_fingerprint` but never call `build_instant_mirroring` with a message that triggers laughter detection.

**Fix for Go port:** Do NOT port the `.keys()` call. The correct Go equivalent is:

```go
if len(obs.Laughter) > 0 {
    laugh := obs.Laughter[0]
    instructions = append(instructions, fmt.Sprintf("They use '%s' --- use that, not alternatives.", laugh))
}
```

Additionally, fix the Python source:
```python
laugh = obs["laughter"][0]  # not list(obs["laughter"].keys())[0]
```

The same fix applies to the `affirmation` access on line 541.

---

## Finding M-2: `max(counter, key=counter.get)` tie-breaking depends on dict insertion order — Go map iteration order is random

**Severity: P2**
**File:** `apps/Auraken/src/auraken/style.py:405-406, 417-418, 425-426`

```python
top_laugh = max(laughter, key=laughter.get)
top_affirm = max(affirmation, key=affirmation.get)
top_intense = max(intensifier, key=intensifier.get)
```

Python's `max()` on a dict iterates in insertion order (CPython 3.7+). When two keys have the same count, `max()` returns the first one encountered — i.e., the one inserted first.

Go has no equivalent. Iterating a `map[string]int` to find the max produces random tie-breaking because Go map iteration order is randomized. This means: if a user uses "haha" 5 times and "lol" 5 times, Python always picks whichever was seen first. Go picks randomly — and may pick differently on each call, even for the same fingerprint.

**Impact:** The mirroring instruction says `"If something is funny, use 'haha' --- never 'lol'"` or vice versa. A random flip between calls is harmless to the user experience but will break golden-file test determinism for tied counters.

**Fix:** In Go, when finding the max value in a map, break ties by lexicographic key order: `if count > maxCount || (count == maxCount && key < maxKey)`. This gives deterministic behavior (alphabetically first key wins) and is easily reproducible in golden-file tests. Document that Python uses insertion-order tie-breaking while Go uses alphabetical-order tie-breaking — the difference only manifests for exact ties, which are semantically equivalent.

---

## Finding M-3: `detect_current_mode` uses `Counter.most_common(1)` with insertion-order tie-breaking — same issue as M-2

**Severity: P2**
**File:** `apps/Auraken/src/auraken/style.py:593` — `counts.most_common(1)[0][0]`

When two non-general modes have the same count in the recent message window, Python picks the one that appeared first. Go would need explicit tie-breaking. Same fix as M-2: break ties alphabetically.

**Impact:** Affects which mode is selected when a user's recent messages are evenly split between two modes. The downstream effect is which mode profile feeds into `BuildMirroring` — but both modes would produce reasonable instructions, so the semantic impact is low.

**Fix:** Same as M-2 — alphabetical tie-breaking in Go's mode counting logic.

---

## Finding M-4: Em-dash character (U+2014) in instruction strings requires no special handling in Go

**Severity: P3 (informational)**
**File:** `apps/Auraken/src/auraken/style.py:370-401` — instruction string literals

Seven instruction strings contain the em-dash character `---` (U+2014, 3 bytes in UTF-8):
- `"Keep responses very short --- 1-2 sentences."`
- `"Keep responses concise --- 2-3 sentences max."`
- `"Use proper capitalization --- this person does."`
- etc.

Go string literals handle Unicode characters identically to Python. The em-dash can be embedded directly in Go source: `"Keep responses very short \u2014 1-2 sentences."` or simply pasted as the literal character. Go source files are UTF-8. No encoding issues.

**Recommendation:** Paste instruction strings directly from Python source into Go source. Verify with a golden-file test that the generated markdown output is byte-identical.

---

## Finding M-5: `_laugh_alt` mapping is a 3-entry lookup — trivially portable but should use a Go `map` literal

**Severity: P3 (informational)**
**File:** `apps/Auraken/src/auraken/style.py:462-465`

```python
def _laugh_alt(top: str) -> str:
    alts = {"haha": "lol", "lol": "haha", "lmao": "haha"}
    return alts.get(top, "lol")
```

Direct Go equivalent:

```go
var laughAlt = map[string]string{
    "haha": "lol", "lol": "haha", "lmao": "haha",
}

func altLaugh(top string) string {
    if alt, ok := laughAlt[top]; ok {
        return alt
    }
    return "lol"
}
```

**Recommendation:** Straightforward port. Package-level `var` for the map, consistent with the brainstorm's decision #3 ("compiled once at package init").

---

## Finding M-6: `_mode_context_note` returns static strings per mode — must match Python character-for-character

**Severity: P1**
**File:** `apps/Auraken/src/auraken/style.py:468-496`

The 6 mode-specific notes are multi-sentence strings embedded in a dict. These are injected directly into system prompts consumed by the LLM. Character-level differences (even whitespace) could affect prompt caching or downstream behavior.

The strings contain:
- Regular ASCII text
- Em-dashes (U+2014) -- actually, checking the source: no em-dashes in these strings. They use only ASCII punctuation.
- No special characters.

The strings MUST be copied character-for-character. The recommended approach: define them as Go `const` values at package level and verify with a golden-file test that `BuildMirroring` output for each mode matches Python output exactly.

**Fix:** Copy-paste from Python source. Golden-file test with fixed fingerprint inputs to verify all 6 mode notes produce identical output.
