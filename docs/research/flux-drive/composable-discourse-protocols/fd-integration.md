# Integration Review: rsj.7 Discourse Protocol — interflux / intersynth

**Reviewer:** fd-integration-surface agent
**Date:** 2026-03-31
**Change set:** discourse protocol support (rsj.7) added to flux-drive review pipeline
**Scope:** cross-module data flows between interflux (orchestrator) and intersynth (synthesis subagent)

---

## Pre-Review Edge Inventory

Before reading the diff, the following integration edges were identified from
`docs/companion-graph.json` and `docs/contract-ownership.md` as potentially affected:

| Edge | Direction | Nature |
|------|-----------|--------|
| interflux → intersynth (`synthesize-review`) | producer → consumer | Task invocation with prompt parameters |
| `findings.json` schema | interflux writes spec → intersynth writes, orchestrator reads | Structured artifact contract |
| `synthesis.md` | intersynth writes → orchestrator reads | Human-readable report |
| `reaction.yaml` | interflux config → synthesize-review.md reads via `hearsay_detection`/`sycophancy_detection` flags | Config consumption |
| `discourse-lorenzen.yaml` | interflux config → orchestrator reads → JSON → synthesize-review.md | Config-to-parameter pipeline |
| `discourse-sawyer.yaml` | interflux config → synthesize-review.md Step 6.6 (hardcoded thresholds) | Config consumption gap (see P1 below) |

The `companion-graph.json` edge `interflux → intersynth: requires-for-feature` covers the synthesize-review invocation. No new graph edges are introduced by this change.

---

## Findings

### P0 — Silent Threshold Drift: Sawyer config not consumed by synthesize-review.md

**File:** `/home/mk/projects/Sylveste/interverse/interflux/config/flux-drive/discourse-sawyer.yaml`
**Consuming step:** `intersynth/agents/synthesize-review.md` Step 6.6

The Sawyer config is declared in `reaction.yaml` line 33 (`sawyer: discourse-sawyer.yaml`) and exists as a well-formed YAML file. However, `discourse-sawyer.yaml` is **never passed** to the synthesis subagent. The `synthesize.md` orchestrator passes `LORENZEN_CONFIG` as a JSON-serialized parameter but has no equivalent `SAWYER_CONFIG` (or threshold) injection. The synthesis agent does not read the file at all.

Step 6.6 in `synthesize-review.md` instead hardcodes the threshold values inline:

```
- **healthy:** gini ≤ 0.3 AND novelty ≥ 0.1 AND relevance ≥ 0.7
- **degraded:** gini ≤ 0.5 AND novelty ≥ 0.05 AND relevance ≥ 0.5
```

These happen to match `discourse-sawyer.yaml` today, but there is no enforcement relationship. If an operator edits the YAML thresholds, the synthesis agent will silently continue using the hardcoded values. The `discourse-health.sh` diagnostic script does accept `--config discourse-sawyer.yaml` and would use the updated thresholds — but since the synthesize-review agent ignores the config entirely, the canonical `findings.json discourse_health` block and the standalone `discourse-health.json` will diverge whenever thresholds are changed.

**Risk:** This is a silent correctness gap — no error is emitted, just wrong threshold enforcement in the primary artifact path. The standalone script would show different health conclusions than the findings.json that downstream consumers read.

**Fix:** Either (a) pass a `SAWYER_CONFIG` JSON parameter to the synthesis subagent via `synthesize.md` (mirroring the `LORENZEN_CONFIG` pattern), or (b) document that Step 6.6 thresholds are intentionally static copies, and add a note in `discourse-sawyer.yaml` that the synthesis agent does not hot-reload it.

---

### P1 — LORENZEN_CONFIG JSON shape mismatch

**Producer:** `interflux/skills/flux-drive/phases/synthesize.md` lines 76-78
**Consumer:** `intersynth/agents/synthesize-review.md` Step 3.7c line 18 (Input Contract example)

The orchestrator serializes the Lorenzen config with:

```bash
python3 -c "import yaml,json; print(json.dumps(yaml.safe_load(open('...discourse-lorenzen.yaml'))['dialogue_game']))"
```

This produces a JSON object of the full `dialogue_game` stanza, which includes these top-level keys:

```json
{
  "enabled": true,
  "move_types": {"attack": "...", "defense": "...", "new-assertion": "...", "concession": "..."},
  "validation": {"attack_requires_evidence": true, "defense_requires_new_evidence": true, "new_assertion_max_per_agent": 2},
  "legality_scoring": {"valid_attack": 1.0, "valid_defense": 1.0, "valid_new_assertion": 0.8, "invalid_move": 0.2}
}
```

The synthesize-review.md Input Contract example at line 18 shows a **flattened** shape:

```json
{"enabled":true,"attack_requires_evidence":true,"defense_requires_new_evidence":true,"new_assertion_max_per_agent":2}
```

Step 3.7c then reads:

- `enabled` — present at root in both shapes: **consistent**
- `attack_requires_evidence` — present at root in the example, but in the actual JSON it is nested under `validation.attack_requires_evidence`: **mismatch**
- `defense_requires_new_evidence` — same nesting problem
- `new_assertion_max_per_agent` — same nesting problem; Step 3.7c line 151 reads it as `new_assertion_max_per_agent` from `LORENZEN_CONFIG` (root level), but it arrives under `validation`

**Impact:** Step 3.7c will find `LORENZEN_CONFIG.attack_requires_evidence` as `undefined`/null and fall back to whatever implicit default the agent applies. The `new_assertion_max_per_agent` cap check at line 151 will use a null value. In practice the agent will likely default to the fallback described: "from LORENZEN_CONFIG, default: 2" — so the cap may accidentally work, but the evidence-requirement checks for `attack` and `defense` legality will be skipped silently. There is no error; invalid moves will be scored as `valid`.

**Fix:** Either (a) flatten the config in the orchestrator's python3 extraction command to match the example, or (b) update Step 3.7c to read nested paths (`validation.attack_requires_evidence`). Option (a) is lower risk because it keeps the contract stable for future move-type additions.

Flattened extraction:

```bash
python3 -c "
import yaml,json
d=yaml.safe_load(open('interverse/interflux/config/flux-drive/discourse-lorenzen.yaml'))['dialogue_game']
flat={'enabled':d['enabled'],'new_assertion_max_per_agent':d['validation']['new_assertion_max_per_agent'],'attack_requires_evidence':d['validation']['attack_requires_evidence'],'defense_requires_new_evidence':d['validation']['defense_requires_new_evidence']}
print(json.dumps(flat))"
```

---

### P1 — Move Type names: one inconsistency in reaction-prompt.md

**Producer contract:** `reaction-prompt.md` (defines what agents write)
**Consumer contract:** `synthesize-review.md` Step 3.7c (validates what agents wrote)

The four canonical move type names defined in `discourse-lorenzen.yaml` are:
`attack`, `defense`, `new-assertion`, `concession`

`reaction-prompt.md` uses these same four names in the Move Type Assignment section and in the output format block. **Consistent.**

`synthesize-review.md` Step 3.7c validates against `attack`, `defense`, `new-assertion`, `concession`. **Consistent.**

The `findings.json` schema in Step 8 uses `"move_distribution": {"attack": 0, "defense": 0, "new-assertion": 0, "concession": 0}`. **Consistent.**

No inconsistency found in move type names across the four files reviewed. This integration point is correctly wired.

---

### P1 — discourse-health.sh output schema does not match findings.json discourse_health block

**Producer:** `interflux/scripts/discourse-health.sh` (writes `discourse-health.json`)
**Reference schema:** `synthesize-review.md` Step 8 `findings.json` `discourse_health` block

The synthesis agent writes this `discourse_health` block into `findings.json`:

```json
{
  "participation_gini": 0.0,
  "novelty_rate": 0.0,
  "response_relevance": 0.0,
  "flow_state": "healthy",
  "warnings": []
}
```

The `discourse-health.sh` script emits a JSON object that includes these same fields plus additional ones not present in the synthesis output:

- `agent_finding_counts` (object — per-agent count map)
- `total_findings` (integer)
- `metrics_source` (string: `"findings.json"`)

The **inverse** is also true: `discourse-health.sh` does not emit a `lorenzen` sub-block. The `discourse_analysis.lorenzen` block that appears in `findings.json` is synthesis-only and has no representation in the standalone script's output at all.

This is not a hard failure — `synthesize.md` step 3.4 footnote correctly states "The canonical health data is already in findings.json" and treats the script as a convenience artifact. However, downstream tooling (e.g., any future script that reads `discourse-health.json`) will see a superset schema relative to `findings.json`'s `discourse_health`, which may cause shape confusion. There is currently no consumer declared for `discourse-health.json` in `contract-ownership.md`.

**Fix:** Document the schema difference explicitly in `discourse-health.sh`'s header comment, or align the output to emit only the fields present in `findings.json discourse_health`. The extra fields (`agent_finding_counts`, `total_findings`) are diagnostically useful and should probably be retained, so documentation is preferable to removal.

---

### P2 — discourse-health.sh exit-on-error may mask ordering issue

**File:** `/home/mk/projects/Sylveste/interverse/interflux/scripts/discourse-health.sh` line 9

The script begins with `set -euo pipefail`. The orchestrator calls it after synthesis completes:

```bash
bash interverse/interflux/scripts/discourse-health.sh "{OUTPUT_DIR}" 2>/dev/null || true
```

The `|| true` suppresses exit-1 from a missing `findings.json`. This is the intended path and is correct.

However, within the script, the `exit 1` at line 27 (when `findings.json` is not found) runs after `set -e` is in effect. If the script is invoked before the synthesis subagent finishes writing `findings.json` — which is possible if the orchestrator does not await the Task return before running the diagnostic — it will emit `{"error":"findings.json not found"}` and write that as `discourse-health.json`. The `|| true` in the orchestrator swallows the non-zero exit, so no error surfaces, but `discourse-health.json` will contain an error object rather than valid health data.

`synthesize.md` Step 3.2 says the script runs "optionally" after the synthesis subagent returns, and the subagent return is synchronous via `Task()`. If the orchestrator correctly awaits the Task, findings.json will always exist before the script runs. The ordering is implicitly safe, but the dependency is not stated explicitly in `synthesize.md`. A reader implementing the orchestrator could plausibly run the script in parallel.

**Fix:** Add an explicit note in `synthesize.md` Step 3.2: "Run the diagnostic only after the synthesis Task has returned (findings.json is written by the subagent, not the orchestrator)."

---

### P2 — `legality_scoring` block in discourse-lorenzen.yaml is unread by any consumer

**File:** `/home/mk/projects/Sylveste/interverse/interflux/config/flux-drive/discourse-lorenzen.yaml` lines 16-20

```yaml
legality_scoring:
  valid_attack: 1.0
  valid_defense: 1.0
  valid_new_assertion: 0.8
  invalid_move: 0.2
```

The orchestrator's extraction command slices only `dialogue_game` and the consumer (Step 3.7c) reads only `enabled`, `attack_requires_evidence`, `defense_requires_new_evidence`, and `new_assertion_max_per_agent`. The `legality_scoring` values are never passed to the synthesis agent and are never applied. The Step 3.7c tagging uses hardcoded scores: `"legality_score": 1.0` for valid moves (no config value applied) and no fractional scoring for `new-assertion` (which would be 0.8 per the config).

This is either dead config or an incomplete implementation. If the intent is for `valid_new_assertion: 0.8` to weight new-assertion moves differently in convergence calculations, that weighting is not present in Step 3.7c or Step 6 of synthesize-review.md.

**Fix:** Either extend the LORENZEN_CONFIG extraction to include the `legality_scoring` sub-block and implement score application in Step 3.7c, or remove `legality_scoring` from the YAML and document it as a future extension.

---

### P3 — companion-graph.json has no edge for discourse config files

The `discourse-sawyer.yaml` and `discourse-lorenzen.yaml` files in interflux are consumed by synthesize-review.md (indirectly — Lorenzen via JSON parameter; Sawyer only by the standalone script). The `companion-graph.json` `interflux → intersynth` edge documents "Verdict synthesis and deduplication after multi-agent review" but does not mention the config dependency direction. This is a documentation gap, not a code gap. The graph is not wrong, just incomplete now that config shapes flow from interflux to intersynth.

No action required unless the team wants the graph to capture config-level coupling.

---

## Summary Table

| Severity | Finding | File(s) |
|----------|---------|---------|
| P0 | Sawyer thresholds hardcoded in synthesize-review.md — discourse-sawyer.yaml is never read by the synthesis agent, so threshold edits have no effect on findings.json | `discourse-sawyer.yaml`, `synthesize-review.md` Step 6.6 |
| P1 | LORENZEN_CONFIG JSON shape mismatch — orchestrator emits nested structure, consumer expects flat | `synthesize.md` lines 76-78, `synthesize-review.md` Input Contract + Step 3.7c |
| P1 | discourse-health.sh output schema diverges from findings.json discourse_health block (extra fields; no lorenzen block) | `discourse-health.sh`, `synthesize-review.md` Step 8 |
| P2 | Script ordering dependency implicit — discourse-health.sh could run before findings.json is written if orchestrator is not awaiting Task | `synthesize.md` Step 3.2 |
| P2 | legality_scoring block in discourse-lorenzen.yaml is fully unread — partial scores (0.8 for new-assertion) never applied | `discourse-lorenzen.yaml`, `synthesize-review.md` Step 3.7c |
| P3 | companion-graph.json edge does not capture config-level coupling from interflux to intersynth | `docs/companion-graph.json` |

Move type name consistency (the user's integration point 2) is **confirmed correct** — all four files agree on `attack`, `defense`, `new-assertion`, `concession`.

The `FINDINGS_TIMELINE` parameter wiring is unaffected by this change.

No new `ic events emit` calls, `_interspect_insert_evidence` calls, or hook_id registrations are introduced by this diff — the Interspect event pipeline is not involved.

No new cross-module shell library sourcing (`lib-*.sh`) is introduced.
