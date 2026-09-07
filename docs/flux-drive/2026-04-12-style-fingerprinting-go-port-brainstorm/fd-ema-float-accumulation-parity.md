# fd-ema-float-accumulation-parity — Style Fingerprinting Go Port Findings

**Target:** `docs/brainstorms/2026-04-12-style-fingerprinting-go-port-brainstorm.md`
**Agent:** fd-ema-float-accumulation-parity (floating-point EMA arithmetic, IEEE 754 double-precision representation, alpha computation precision, accumulation drift over long sequences)
**Track:** Adjacent (Project Agents)
**Decision Lens:** Evaluates whether the EMA formula `old * (1 - alpha) + new * alpha` with `alpha = 0.3 when n >= 5 else 1/(n+1)` produces bit-identical results between Python `float` and Go `float64`, and whether vocabulary counter increments match.

---

## Finding E-1: EMA arithmetic is bit-identical between Python and Go — no float precision issue

**Severity: P3 (informational — clean bill of health)**
**File:** `apps/Auraken/src/auraken/style.py:228-229` — `_ema` function

Both Python `float` and Go `float64` are IEEE 754 double-precision (64-bit). The EMA formula `old * (1 - alpha) + new * alpha` involves only multiplication and addition — operations that are deterministic for the same inputs under IEEE 754 with default rounding mode (round-to-nearest, ties-to-even), which both Python and Go use.

Verified empirically with a 20-step sequence of varying word counts `[3, 15, 7, 22, 4, 8, 11, 2, 30, 5, 6, 18, 1, 9, 14, 3, 7, 12, 8, 5]`:
- Python final value: `7.63788965772470352` (repr)
- Go final value: `7.63788965772470352` (Printf %.17f)
- **Bit-identical at all 20 steps**, including the critical `1/(n+1)` alpha values for n=0..4.

The `1/3` case (n=2, alpha=0.33333333333333331) produces the same representable double in both languages. The `0.3` literal is the same representable double (0.29999999999999999) in both languages. No divergence accumulates.

Boolean EMA values (pct_contraction, pct_question, etc.) were also verified bit-identical over a 10-step sequence of mixed true/false inputs.

**Recommendation:** The brainstorm's decision #4 ("EMA formula preserved exactly") is validated. No special handling needed for float precision. The existing pattern in `pkg/lens/evolution.go` (which also uses EMA for effectiveness scoring) confirms that Skaffen already has precedent for this arithmetic in Go.

---

## Finding E-2: Alpha transition at n=5 is a discontinuity — but both languages handle it identically

**Severity: P3 (informational)**
**File:** `apps/Auraken/src/auraken/style.py:286` — `alpha = 0.3 if n >= 5 else 1.0 / (n + 1)`

The alpha function jumps from `1/6 = 0.1667` (at n=4) to `0.3` (at n=5). This is a deliberate design choice in the Python source: early messages use decreasing alpha (giving each new observation proportionally less weight as more accumulate), then switch to fixed alpha=0.3 for long-term EMA behavior.

Both Python and Go evaluate `n >= 5` on the same integer `n` field, so the transition point is identical. The `1.0 / float64(n+1)` division in Go produces the same double as Python's `1.0 / (n + 1)`.

**Recommendation:** Port the conditional directly: `if n >= 5 { alpha = 0.3 } else { alpha = 1.0 / float64(n+1) }`. No special handling needed.

---

## Finding E-3: Vocabulary counters use integer increment, not EMA — trivially portable but JSON `null` vs `{}` is the real risk

**Severity: P1**
**File:** `apps/Auraken/src/auraken/style.py:308-327` — vocabulary counter accumulation

The vocabulary counters (`laughter`, `affirmation`, `intensifier`, `hedge`, `opener`) use simple integer increment: `counter[token] = counter.get(token, 0) + 1`. This is trivially portable to Go: `profile.Laughter[token]++`.

However, the Go struct must initialize these maps. If a `ModeProfile` is deserialized from JSON and the counter fields are absent or `null`, Go will leave the `map[string]int` fields as `nil`. Subsequent `profile.Laughter[token]++` will panic on a nil map.

Additionally, when Go serializes a `ModeProfile` with nil maps, it writes `"laughter": null` instead of Python's `"laughter": {}`. Python code reading this JSON will get `None` for the laughter field, and `profile.get("laughter", {})` correctly falls back to `{}`. But if Python code does `counter = profile.get("laughter", {})` followed by `for token in obs.get("laughter", [])`, then `counter[token] = counter.get(token, 0) + 1` — this works because `counter` is the fallback `{}`, but the mutation is on the temporary dict, not the profile dict. The profile still has `None`. On next serialization, Python writes `"laughter": null` again, losing the accumulated count.

Wait — re-reading the Python code more carefully: line 315-317 does `counter = profile.get(counter_key, {})` then mutates `counter`, then writes it back: `profile[counter_key] = counter`. So even if profile had `None`, the fallback `{}` is mutated and written back. Python handles Go's `null` correctly on read.

**Remaining risk:** Go nil map panic on increment. The `_empty_mode_profile()` equivalent in Go must initialize all maps to `make(map[string]int)`, not leave them nil. The JSON unmarshaling path must also handle `null` → initialize to empty map.

**Fix:** Implement a custom `UnmarshalJSON` on `ModeProfile` or use a constructor that calls `make()` on all map fields after deserialization. Alternatively, use the `encoding/json` decoder's default behavior (which does allocate maps for JSON objects) but add nil checks before map writes. The simplest approach: after `json.Unmarshal`, call `profile.ensureMaps()` which does `if m.Laughter == nil { m.Laughter = make(map[string]int) }` for each map field.

---

## Finding E-4: `n` field is `int` in Python and should be `int` in Go — no precision issue even at high message counts

**Severity: P3 (informational)**
**File:** `apps/Auraken/src/auraken/style.py:209, 285` — `"n": 0` and `n = profile.get("n", 0)`

Python `int` is arbitrary precision. Go `int` is platform-dependent (64-bit on all modern platforms). A user would need to send 9.2 quintillion messages to overflow Go's `int`. The `n` field is safe as `int` in Go.

JSON serializes `n` as a plain integer in both languages. Go reads Python's `"n": 0` as `int(0)`. Python reads Go's `"n": 0` as `int(0)`. No type confusion.

**Recommendation:** Use `int` for `n` in Go structs. No special handling.
