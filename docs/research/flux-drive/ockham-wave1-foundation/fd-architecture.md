# Architecture Review: Ockham Wave 1 — Foundation PRD

**PRD:** `/home/mk/projects/Sylveste/docs/prds/2026-04-04-ockham-wave1-foundation.md`
**Reviewed:** 2026-04-04
**Scope:** Package boundaries, dependency feasibility, feature ordering, missing integration points
**Artifacts sampled:** `os/Ockham/` package stubs, `os/Clavain/hooks/lib-dispatch.sh`, `os/Clavain/hooks/lib-intercore.sh`, `interverse/interphase/hooks/lib-discovery.sh`, `interverse/interspect/hooks/lib-interspect.sh`, `interverse/interstat/scripts/cost-query.sh`, `interverse/intercept/bin/intercept`, `os/Clavain/cmd/clavain-cli/watchdog.go`

---

## Summary Verdict

**needs-changes** — Three interface assumptions in the PRD do not match what the referenced dependencies actually expose. Feature ordering between F3 and F2 has a hard prerequisite gap that will produce a broken integration cycle. The package map in AGENTS.md and the PRD's internal package naming differ in a way that will cause confusion at implementation start. All other boundaries and the dependency direction rule are sound.

---

## Findings Index

| ID | Severity | Section | Title |
|----|----------|---------|-------|
| A-01 | P1 | F3 | `ic state list` has no `--json` flag — F3's bulk pre-fetch assumption is wrong |
| A-02 | P1 | F2/F3 | Lane is a `label`, not a top-level field — bead-to-theme mapping requires per-bead `bd show`, not `bd list --json` |
| A-03 | P1 | F5/F6 | `agent_reliability(agent, domain)` does not exist — interspect exposes calibration stats, not that interface |
| A-04 | P2 | F3 before F2 | F3 integration requires the write side (F2's `ockham dispatch advise`) before the read side works end-to-end |
| A-05 | P2 | F7 | Interspect has no halt-record write path — double-sentinel's "agent-unwritable" guarantee is unimplemented |
| A-06 | P2 | F5 | `cost-query.sh` has no per-theme/per-lane query mode — drift detection baseline requires new interstat work |
| A-07 | P3 | F1/F3 | `ic lane status` is currently broken with SQL error — CONSTRAIN path in lib-dispatch.sh depends on a command returning an error |
| A-08 | P3 | AGENTS.md vs PRD | Package name mismatch: AGENTS.md uses `dispatch`, PRD introduces `scoring` and `governor` — stubs exist but are empty |
| A-09 | P3 | F6 | Ratchet AC calls `intercept decide` for logging but intercept's interface takes a gate name and structured JSON, not a free log record |

---

## 1. Boundaries and Coupling

### Component map

Wave 1 touches five distinct layers:

- **Ockham Go packages** (`internal/intent`, `internal/scoring`, `internal/governor`) — new
- **Ockham CLI** (`cmd/ockham`) — new
- **Clavain shell hook** (`hooks/lib-dispatch.sh`) — modified, existing
- **Intercore state store** (`ic` binary) — read/write, existing interface
- **Beads** (`bd` CLI) — read-only, existing interface

The dependency direction rule stated in the PRD (scoring imports nothing; governor imports all four) matches the brainstorm decision and is correct. The `internal/scoring` package receiving typed structs rather than importing upstreams directly prevents a god-module and is the right call.

The boundary between Ockham and Clavain is deliberately thin: Ockham writes state via `ic state set`, Clavain reads it in `dispatch_rescore()`. This is an appropriate seam — it decouples the governor's computation cycle from Clavain's dispatch cycle and means neither needs to call the other directly.

### What does not cross a boundary cleanly

F5 (weight-drift detection) requires reading cost and cycle time grouped by theme. Neither `interstat/cost-query.sh` nor `interphase/lib-discovery.sh` expose this segmentation. Cycle time per bead is derivable from `bd show`, but 7-day rolling aggregates by lane require either new SQL queries added to interstat or direct SQLite access from Ockham. This is new work against two existing modules, which the PRD does not call out as a dependency gap.

F6's use of `intercept decide` for "ratchet decision logging" does not match how intercept works. `intercept decide <gate> --input <json>` is a decision gate that returns a verdict — it is not a log sink. Logging ratchet decisions through intercept means defining a named gate (`ratchet-decision` or similar) and structuring every call as a gate evaluation. That is reasonable but requires a named gate contract that the PRD does not specify, and the non-goals section explicitly defers distillation to Wave 2, which means these logged decisions will accumulate without consumption. The integration is low-risk but the interface contract needs to be stated.

---

## 2. Pattern Analysis

### A-01 (P1) — `ic state list` has no `--json` flag

**F3 AC:** `lib-dispatch.sh reads offsets: ic state list "ockham_offset" --json (bulk pre-fetch, once per cycle)`

The `ic` binary's `state list <key>` command outputs one scope_id per line (plain text, tab-delimited when the Clavain lib wraps it). There is no `--json` flag — confirmed by live binary inspection. The existing `intercore_state_delete_all()` function uses the list output with `while read -r scope`, not JSON parsing.

The bulk pre-fetch pattern is correct and worth keeping; the implementation must use `ic state list "ockham_offset"` to enumerate scope IDs (bead IDs), then call `ic state get "ockham_offset" "$bead_id"` per bead and build the offset map in shell, or extend `ic` with a new `state list-values` subcommand that returns `{scope_id: value}` JSON. The PRD's AC as written will not compile into a working shell function.

**Smallest fix:** Either remove `--json` from the AC and specify the tab-delimited iteration pattern, or file a prerequisite intercore ticket to add `state list --json` before F3 can be shipped as specified.

### A-02 (P1) — Lane is stored as a label, not a top-level field

**F2 AC:** `Bead-to-theme mapping: theme = bead.lane (from beads bd list --json). No lane → open theme`

`bd list --json` output does not include a `lane` field. Lane is stored as a `lane:<name>` entry in the `labels` array, visible in `bd show <id> --json` but absent from `bd list --json`. The `bd list --json` output schema contains: `id`, `title`, `status`, `priority`, `issue_type`, `owner`, `created_at`, `updated_at`, `dependency_count`, `dependent_count`, `comment_count`. Labels only appear in `bd show`, not `bd list`.

This means `ockham dispatch advise` and `internal/scoring`'s bead-to-theme mapping cannot be built on a single `bd list --json` call. Each bead requires an individual `bd show <id> --json` to extract labels, which is O(N) per cycle and would be slow for large backlogs.

This is consistent with how `lib-dispatch.sh` already handles lanes: line 192-193 calls `bd show "$bead_id" --json` per bead and parses `grep -oP '^lane:\K.*'`. Ockham should follow the same per-bead pattern or request a `bd list --long --json` that includes labels.

**Brainstorm drift:** The brainstorm decision 2 states `bd list --json | jq '.[] | {id, lane}'` — this query will return null `lane` for every bead because `lane` is not a top-level JSON field. The decision was made against the wrong mental model of the bd schema. The label pattern used by `lib-dispatch.sh` is the correct approach.

**Smallest fix:** Update F2 AC to: `bd show <bead_id> --json | jq '.labels[]? | select(startswith("lane:")) | ltrimstr("lane:")'` pattern, matching existing lib-dispatch.sh behavior.

### A-03 (P1) — `agent_reliability(agent, domain)` does not exist

**F6 AC:** cold-start inference from `interspect evidence`, ratchet guard uses `hit_rate`, `sessions`, `confidence`

**Brainstorm decision 1 states:** `interface: interspect exposes agent_reliability(agent, domain) -> {hit_rate, sessions, confidence, last_active}`

This function does not exist. Interspect's calibration pipeline (`_interspect_calibrate_reviews`) computes `hit_rate`, `weighted_hit_rate`, `sessions`, and `confidence` per review agent — but grouped by flux-drive review agent (fd-architecture, fd-safety, etc.), not by `(agent, domain)` pairs in the authority-ratchet sense. The domain dimension does not exist in interspect's evidence schema. The `evidence` table has: `agent`, `event`, `source`, `context` (JSON), `ts`, `session_id` — no domain column.

Additionally, the calibration output is written to `.clavain/interspect/confidence.json` (a file) or accessed through `_interspect_calibrate_reviews()` (a shell function in lib-interspect.sh), neither of which is an API boundary Ockham's Go code can call directly.

For Wave 1 (where `AuthorityState` is a stub), this gap does not block anything. For F6's cold-start inference, Ockham either needs to read `confidence.json` directly and map its schema, or interspect needs a new query function. The PRD marks `AuthorityState` as a stub in Wave 1, which means F6's cold-start AC is Wave 3 work dressed as Wave 1 — but it is listed in Wave 1's F6.

**Smallest fix:** Clarify in F6 ACs that the cold-start inference from interspect evidence uses the existing `confidence.json` file, not a `agent_reliability()` function call, and note that the domain dimension is not available until a domain-annotated evidence schema is added to interspect (Wave 3 prerequisite).

---

## 3. Feature Ordering

### A-04 (P2) — F3 requires F2's write path before end-to-end integration works

F3 wires `lib-dispatch.sh` to read `ockham_offset` values from intercore state. This read path is inert until F2's `internal/governor` writes offsets via `ic state set "ockham_offset"`. The PRD lists F3 before F2 completes the write path, which means F3 can be code-complete but untestable until F2's `Evaluate()` loop runs at least once.

This ordering is not a blocking error (the fail-open default of offset=0 means dispatch continues correctly), but it makes F3's acceptance criteria untestable in isolation. The AC `ockham dispatch advise --json outputs the current weight vector without dispatching` is an F2 deliverable attached to F3's feature number — `ockham dispatch advise` requires the scoring package and governor from F2.

**Smallest fix:** Move `ockham dispatch advise --json` to F2's ACs where it belongs (it tests F2's scoring output), and confirm F3's ACs can be tested with manually-seeded `ic state set "ockham_offset" <bead> '{"offset":3}'` to decouple F3 testing from F2 readiness.

### F4 depends on F1 and F2 — ordering is correct

`ockham check` (F4) reads `signals.db` and evaluates state written by F2's governor. F4 cannot be implemented before F2 defines what gets persisted. The PRD's feature numbering (F1 → F2 → F3 → F4) is correct here.

### F5 and F6 depend on F4 — also correct

F5's drift detection and F6's ratchet both depend on `signals.db` infrastructure established in F4. The ordering holds.

---

## 4. Missing Integration Points

### A-05 (P2) — No interspect halt-record write path exists

**F7 AC:** `Tier 3 BYPASS: write factory-paused.json AND interspect halt record (double-sentinel)` and `ockham check reconstructs factory-paused.json from interspect halt record if file deleted`

Interspect has no `halt record` concept. Its evidence table records verdict outcomes, routing overrides, canary periods, and delegation outcomes. There is no event type for factory halt, no write function for it, and no read function to reconstruct from. The "agent-unwritable" property of this sentinel depends on interspect's DB being in a path agents cannot modify — which is a filesystem permission assumption not currently enforced (interspect.db lives at `.clavain/interspect/interspect.db` and is writable by any process running as the same user).

The double-sentinel design is architecturally correct. Its security property requires either: (a) interspect adds a `factory_halt` event type with an insertion function that Ockham calls, and a query function `ockham check` can call on startup, or (b) an out-of-band path is used (e.g., a file owned by root or a separate SQLite DB with restricted permissions).

This is Wave 1 implementation work that has no integration path today. F7 cannot ship the double-sentinel as specified without at minimum adding one insert and one read function to `lib-interspect.sh`.

**Smallest fix:** Add to the F7 ACs an explicit prerequisite: `lib-interspect.sh exposes _interspect_insert_halt_record() and _interspect_get_halt_record()` (or equivalent). Without this, F7 ships a single-sentinel with a comment, not the tamper-resistant double-sentinel the safety model requires.

### A-06 (P2) — `cost-query.sh` has no per-theme query mode

**F5 AC:** `cost_per_landed_change_trend (14-day rolling)` as a pleasure signal, and weight-drift compares `actual cycle time + gate pass rate vs predicted baseline per theme`

`cost-query.sh` supports aggregate, by-bead, by-phase, by-phase-model, cost-usd, baseline, shadow-savings, and related modes. None of these group results by lane/theme. The landed_changes table does not carry lane annotations — it is derived from git log with bead correlation. Cycle time per bead is computable from beads' `created_at`/`closed_at`, but the 7-day rolling average by theme requires: (a) fetching all closed beads from `bd`, (b) filtering by lane label via individual `bd show` calls or a new `bd list --label=lane:auth` query, (c) computing cycle time from timestamps.

This is Ockham's own computation, not a delegation to interstat. The dependency table lists `interstat (cost-query.sh)` as the mechanism for F5 cost trends, but cost-query.sh cannot answer per-theme cost without extension.

**Smallest fix:** Clarify in F5 ACs that cost/cycle-time grouping by theme is computed by Ockham's `signals.db` logic (reading from bd and beads closed_at timestamps), not by delegating to cost-query.sh as-is. If cost-query.sh extension is desired, add it as a prerequisite task.

### A-07 (P3) — `ic lane status` currently returns a SQL error

Live test of `ic lane status "sota"` returns: `lane status failed: lane get by name: SQL logic error: no such column: intent`. Both `ic lane status` and `ic lane list` are broken in the current intercore build (same error).

F3's CONSTRAIN check in lib-dispatch.sh at line 195 already calls `ic lane status "$_bead_lane" --json | jq -r '.metadata.paused'` — this is an existing path that is currently silently failing. The PRD inherits this broken dependency without flagging it.

**Smallest fix:** Add `ic lane status` to the dependency table with status "broken — SQL schema migration needed" and gate F3's CONSTRAIN path on that fix.

---

## 5. AGENTS.md vs PRD Package Naming

### A-08 (P3) — Package name divergence

AGENTS.md defines four packages: `intent`, `authority`, `anomaly`, `dispatch`. The Ockham `internal/` directory confirms: `intent/`, `authority/`, `anomaly/`, `dispatch/` exist as stubs.

The PRD introduces two names not in AGENTS.md: `internal/scoring` and `internal/governor`. The brainstorm decision 1 (Key Decision 1) renamed `Dispatch` to `Scoring` and added `Governor` as the assembly layer. This renaming is correct and the rationale is sound. However, the existing `internal/dispatch/` stub and AGENTS.md's `dispatch` package entry were not updated. A developer starting from AGENTS.md would create work in `internal/dispatch/`, while the PRD specifies `internal/scoring/`. These are different directories.

**Smallest fix:** Update AGENTS.md to replace the `dispatch` row with `scoring` and add a `governor` row. Delete or repurpose the `internal/dispatch/` stub to avoid the name collision. This is a one-line AGENTS.md update and a directory rename.

### A-09 (P3) — Intercept logging contract needs a named gate

**F6 AC:** `Ratchet decisions logged through intercept for future distillation`

`intercept decide <gate-name> --input <json>` expects a named gate. There is no `ratchet-decision` gate defined in the intercept configuration for Ockham. A gate must exist (or intercept must be called in a record-only mode) before F6 can log to it. This is a minor setup task but is not listed in F6's ACs or the dependency table.

**Smallest fix:** Add one AC to F6: `intercept gate ratchet-decision created in ~/.config/intercept/` (or equivalent), and note the input schema (agent, domain, from_tier, to_tier, reason, evidence_snapshot).

---

## Must-Fix Before Implementation Starts

| Finding | Required action |
|---------|----------------|
| A-01 | Remove `--json` from the `ic state list` AC in F3; specify the tab-delimited iteration pattern or add an intercore prerequisite ticket |
| A-02 | Replace `bd list --json` with `bd show <id> --json` pattern in F2 bead-to-theme AC; update brainstorm decision 2 to match |
| A-03 | Clarify F6 cold-start inference against `confidence.json` file schema, not a non-existent function; note domain dimension is a Wave 3 prerequisite |

## Optional Before Shipping F7

| Finding | Required action |
|---------|----------------|
| A-05 | Add `_interspect_insert_halt_record()` / `_interspect_get_halt_record()` to interspect as a prerequisite, or document that F7 ships single-sentinel initially |
| A-06 | Clarify cost/cycle-time by theme is Ockham-computed, remove interstat from F5 dependency for this use |
| A-07 | Track `ic lane status` SQL bug as a blocker for F3's CONSTRAIN path |

## Cleanup (Non-blocking)

| Finding | Required action |
|---------|----------------|
| A-08 | Rename `internal/dispatch/` to `internal/scoring/`, update AGENTS.md package table |
| A-09 | Define `ratchet-decision` intercept gate contract in F6 ACs |
