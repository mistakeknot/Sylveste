# fd-json-wire-compatibility-struct-tags — Style Fingerprinting Go Port Findings

**Target:** `docs/brainstorms/2026-04-12-style-fingerprinting-go-port-brainstorm.md`
**Agent:** fd-json-wire-compatibility-struct-tags (JSON serialization round-trip fidelity, struct tag accuracy, nil vs empty map semantics, float zero representation, JSONB normalization behavior)
**Track:** Adjacent (Project Agents)
**Decision Lens:** Evaluates whether a fingerprint written by Python Auraken can be read by Go Skaffen and vice versa without data loss, semantic drift, or runtime errors during the concurrent operation window.

---

## Finding J-1: Go serializes nil maps as `null` while Python writes empty dicts as `{}` — causes nil map panic on Go side and potential data loss on round-trip

**Severity: P0**
**File:** `apps/Auraken/src/auraken/style.py:206-225` — `_empty_mode_profile()` keys
**Referenced brainstorm:** Key Decision #1 ("JSON field names match Python dict keys exactly")

The `ModeProfile` struct in Go has five `map[string]int` fields: `laughter`, `affirmation`, `intensifier`, `hedge`, `opener`. When these maps are `nil` (the zero value for Go maps), `encoding/json.Marshal` writes `"laughter": null`. Python's `_empty_mode_profile()` writes `"laughter": {}`.

**Round-trip scenario 1 (Go writes, Python reads):**
Go writes `"laughter": null`. Python does `counter = profile.get("laughter", {})`. The `.get()` returns `None` (because the key exists with value `None`), NOT the default `{}`. Python then does `counter[token] = counter.get(token, 0) + 1` on `None`, which raises `AttributeError: 'NoneType' object has no attribute 'get'`.

Actually, re-reading the Python code at line 315: `counter = profile.get(counter_key, {})`. If the JSON was `"laughter": null`, Python's `json.loads` produces `{"laughter": None}`. Then `profile.get("laughter", {})` returns `None` (not `{}`), because the key IS present — it just has value `None`. This means `counter.get(token, 0)` will raise `AttributeError`.

**Round-trip scenario 2 (Python writes, Go reads):**
Python writes `"laughter": {}`. Go's `json.Unmarshal` into `map[string]int` produces an initialized empty map — no issue.

**Round-trip scenario 3 (Go reads its own output):**
Go writes `"laughter": null`, reads it back. `json.Unmarshal` produces `nil` map. Next `profile.Laughter[token]++` panics with `assignment to entry in nil map`.

**Fix:** Initialize all map fields in the Go `ModeProfile` constructor and after every JSON unmarshal. The recommended pattern:

```go
func (p *ModeProfile) ensureMaps() {
    if p.Laughter == nil { p.Laughter = make(map[string]int) }
    if p.Affirmation == nil { p.Affirmation = make(map[string]int) }
    if p.Intensifier == nil { p.Intensifier = make(map[string]int) }
    if p.Hedge == nil { p.Hedge = make(map[string]int) }
    if p.Opener == nil { p.Opener = make(map[string]int) }
}
```

Call `ensureMaps()` in the constructor and in `UnmarshalJSON`. This ensures Go always writes `{}` (not `null`) and never panics on map access.

Additionally, use `json:",omitempty"` carefully: do NOT use `omitempty` on map fields, because an empty initialized map serializes as `{}` (correct), but `omitempty` would omit it entirely, which Python would then not find in the dict at all.

---

## Finding J-2: Go serializes `float64(0)` as `0` while Python serializes `float(0.0)` as `0.0` — functionally compatible through JSONB but breaks golden-file byte comparison

**Severity: P2**
**File:** `apps/Auraken/src/auraken/style.py:206-225` — float fields in `_empty_mode_profile()`

Go's `encoding/json` serializes `float64(0)` as `0` (no decimal point). Python's `json.dumps` serializes `0.0` as `0.0`. When these values pass through PostgreSQL JSONB, the distinction is erased — JSONB normalizes both to a numeric type. On read, Python's `json.loads` parses `0` as `int(0)` and `0.0` as `float(0.0)`, but both work in arithmetic. Go's `json.Unmarshal` parses both into `float64(0)`.

This means the concurrent operation window is safe — both languages can read each other's JSONB correctly. However, the brainstorm's test strategy ("golden-file tests: feed same inputs to Python and Go, compare JSON output") will fail on byte-level comparison due to `0` vs `0.0`.

**Fix:** Golden-file tests should compare parsed JSON structures (semantic equality), not raw JSON bytes. Use `reflect.DeepEqual` on unmarshaled structs in Go or `json.loads()` equality in Python. Alternatively, implement a custom JSON encoder in Go that writes `0.0` for zero float values (using `strconv.FormatFloat` with 'f' format and minimum 1 decimal place), but this adds complexity for minimal benefit.

---

## Finding J-3: Vocabulary counter values are `int` in Python but the Go struct must use `map[string]int` not `map[string]float64`

**Severity: P1**
**File:** `apps/Auraken/src/auraken/style.py:316-317` — `counter[token] = counter.get(token, 0) + 1`

Python increments vocabulary counters with integer arithmetic. The JSON output writes `"haha": 3` (integer). If the Go struct uses `map[string]float64` (a common mistake when "everything is a number"), it would write `"haha": 3` but read `"haha": 3.0` after a round-trip through Go's marshal/unmarshal, which would then write `"haha": 3` again (since `float64(3)` marshals without decimal). The values are functionally equivalent, but using `int` is cleaner and matches the Python behavior exactly.

However, if Go uses `map[string]int` and Python has written `"haha": 3.0` (which it doesn't — Python writes `3` for integers), Go would fail to unmarshal into `int`. Since Python never writes floats for counters, this is safe.

**Fix:** Use `map[string]int` for all vocabulary counter fields. This matches Python's integer arithmetic exactly.

---

## Finding J-4: `modes` map key ordering differs between Python and Go JSON serialization — not a functional issue but affects golden-file comparison

**Severity: P3**
**File:** `apps/Auraken/src/auraken/style.py:264` — `modes[mode] = _update_mode_profile(modes.get(mode), new_obs)`

Python `dict` preserves insertion order since 3.7. `json.dumps` serializes keys in insertion order. Go `map` has random iteration order. `json.Marshal` serializes map keys in sorted order (Go 1.12+).

This means: if a user's messages are classified as `emotional`, then `playful`, then `emotional` again, Python writes `"modes": {"emotional": {...}, "playful": {...}}` (insertion order). Go writes `"modes": {"emotional": {...}, "playful": {...}}` (alphabetical order — same in this case, but would differ for e.g., `"update"` appearing before `"playful"` in insertion order but after in alphabetical order).

PostgreSQL JSONB does not preserve key order. Both languages read JSONB into their native map/dict types without order dependency.

**Fix:** No functional fix needed. Golden-file tests must use order-independent comparison (parsed JSON equality, not string equality). Document this as a known cosmetic difference.

---

## Finding J-5: The `cadence` struct has only two fields — wire compatible as-is

**Severity: P3 (informational)**
**File:** `apps/Auraken/src/auraken/style.py:276` — `"cadence": {"avg_burst_size": 1.0, "burst_count": 0}`

The cadence sub-object has `avg_burst_size` (float) and `burst_count` (int). Go struct with `json:"avg_burst_size"` and `json:"burst_count"` tags will round-trip cleanly. The only cosmetic difference is `avg_burst_size: 1` (Go) vs `avg_burst_size: 1.0` (Python) for the initial value — see Finding J-2.

**Recommendation:** Straightforward port. No issues.
