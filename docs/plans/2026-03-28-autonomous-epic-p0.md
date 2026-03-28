---
bead: sylveste-rsj.1
stage: plan
children: [sylveste-rsj.1.1, sylveste-rsj.1.2, sylveste-rsj.1.3, sylveste-rsj.1.4]
---

# Implementation Plan: Autonomous Epic Execution — P0 Actions

**Source:** 10-agent brainstorm analysis (`docs/brainstorms/2026-03-28-autonomous-epic-execution-brainstorm.md`)
**Scope:** 4 P0 beads under sylveste-80y.49 — the structural foundations that all later autonomy work depends on.

## Execution Order

The beads have a natural dependency chain:
1. **rsj.1.1** (strategic_intent) — standalone, touches intercore + Clavain
2. **rsj.1.4** (evidence quarantine) — standalone, touches interspect only
3. **rsj.1.3** (review backpressure) — needs a way to count pending reviews → can use existing review_queue.go from NTM or a simpler bd-based count
4. **rsj.1.2** (post-merge canary) — benefits from rsj.1.4 being in place (quarantined evidence won't pollute routing if canary catches a bad merge)

Recommended: implement rsj.1.1 and rsj.1.4 in parallel, then rsj.1.3, then rsj.1.2.

---

## Bead rsj.1.1: Lane-Level `strategic_intent` Field

**Why:** 6 agents converge — intent decays to ~20% by sprint 3. The fix: store intent on the lane, inject it into every dispatch briefing.

### Files to Modify

| File | Change |
|------|--------|
| `core/intercore/internal/lane/store.go` | Add `StrategicIntent` field to `Lane` struct. Store it in the existing `metadata` JSON column (no schema migration needed). |
| `core/intercore/cmd/ic/lane.go` | Add `--intent=` flag to `cmdLaneCreate`. Add `ic lane update --intent=` subcommand. Include `strategic_intent` in JSON output. |
| `os/Clavain/hooks/lib-sprint.sh` | In `sprint_create()`, look up the lane's intent via `ic lane status <lane> --json` and pass it through to the sprint's scope metadata. |
| `os/Clavain/commands/sprint.md` | Document: sprint briefing now includes lane intent. Agents should check for strategic contradiction. |
| `os/Clavain/skills/lane/SKILL.md` | Document `--intent` flag in lane creation and update. |

### Implementation Details

**Lane metadata approach (no migration):**
The `Lane` struct already has `Metadata string // JSON`. Store intent inside it:
```json
{"strategic_intent": "Ship PLG onboarding so power individuals can self-serve agent coordination"}
```

Add helper methods on `Store`:
```go
func (s *Store) SetMetadata(ctx context.Context, id string, key, value string) error
func (s *Store) GetMetadata(ctx context.Context, id string, key string) (string, error)
```

**Briefing injection:**
In `sprint_create()` (lib-sprint.sh), after resolving the lane:
```bash
lane_intent=""
if [[ -n "$lane" ]]; then
    lane_json=$(ic lane status "$lane" --json 2>/dev/null) || lane_json=""
    lane_intent=$(echo "$lane_json" | jq -r '.metadata.strategic_intent // empty' 2>/dev/null) || lane_intent=""
fi
```

Pass `lane_intent` into the sprint's scope metadata via `ic run create` so it's available when the sprint briefing is rendered.

**`ic lane update` subcommand:**
```go
case "update":
    return cmdLaneUpdate(ctx, args[1:])
```
Accepts `--name=<id-or-name>` and `--intent=<text>`. Reads current metadata, merges intent, writes back.

### Acceptance Criteria
- [ ] `ic lane create --name=test --intent="Ship X"` stores intent in metadata
- [ ] `ic lane status test --json` includes `strategic_intent` in output
- [ ] `ic lane update --name=test --intent="Updated X"` overwrites intent
- [ ] Sprint briefing for a bead in lane `test` includes the intent text
- [ ] Integration test: create lane with intent, create sprint in that lane, verify intent propagates

---

## Bead rsj.1.2: Post-Merge Canary Gate

**Why:** 5 agents converge — silent failure is P0 risk. The system currently records sprint success at bead close, before verifying the merged code actually works.

### Files to Modify

| File | Change |
|------|--------|
| `os/Clavain/skills/landing-a-change/SKILL.md` | Add Step 4.5: post-push canary validation. |
| `os/Clavain/hooks/lib-sprint.sh` | Add `sprint_canary_check()` — run build+test on current HEAD after push. Record result. |
| `os/Clavain/hooks/auto-stop-actions.sh` | After successful land, invoke canary check before declaring sprint success. |
| `interverse/interspect/hooks/lib-interspect.sh` | Add `quality_failure` event type. When canary fails, emit this instead of normal session-end success. |

### Implementation Details

**Canary check function:**
```bash
sprint_canary_check() {
    local bead_id="$1"
    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1

    # Detect language and run appropriate checks
    local canary_passed=true
    if [[ -f "$project_root/go.mod" ]]; then
        go build ./... 2>/dev/null || canary_passed=false
        go test ./... -count=1 -short 2>/dev/null || canary_passed=false
    elif [[ -f "$project_root/package.json" ]]; then
        npm run build 2>/dev/null || canary_passed=false
        npm test 2>/dev/null || canary_passed=false
    fi
    # ... (rust, python patterns)

    if [[ "$canary_passed" == "false" ]]; then
        # Emit quality_failure to Interspect
        _interspect_insert_evidence "..." "quality_failure" \
            "post_merge_canary_failed" '{"bead":"'$bead_id'"}' 2>/dev/null || true
        return 1
    fi
    return 0
}
```

**Integration point in landing skill:**
After Step 4 (commit and push), add:
```
## Step 4.5: Post-Push Canary

After push succeeds, run canary validation:
1. `go build ./...` (or language equivalent)
2. `go test ./... -short` (fast subset)
3. If canary fails: warn user, emit quality_failure event, do NOT record sprint as success
4. If canary passes: proceed to bead close
```

**Why after push, not before?** The pre-push tests catch local issues. The canary catches merge conflicts, dependency version skew, and issues that only manifest on the integrated codebase. The landing skill already runs tests in Step 1 — the canary is the second check on the merged state.

### Acceptance Criteria
- [ ] After `git push`, canary runs build + test automatically
- [ ] On canary failure: `quality_failure` event emitted to Interspect
- [ ] On canary failure: sprint is NOT recorded as successful
- [ ] On canary pass: normal sprint completion flow proceeds
- [ ] Canary is skippable with `CLAVAIN_SKIP_CANARY=true` for known-good situations

---

## Bead rsj.1.3: Review Queue Backpressure in Self-Dispatch Scoring

**Why:** 4 agents converge — system optimizes for agent utilization, not flow. Self-dispatch keeps producing when review queue is full.

### Files to Modify

| File | Change |
|------|--------|
| `os/Clavain/hooks/lib-dispatch.sh` | Add `_dispatch_review_pressure()` function. Integrate into `dispatch_rescore()` as negative score modifier. |
| `os/Clavain/hooks/lib-dispatch.sh` | Add `DISPATCH_REVIEW_PRESSURE_THRESHOLD` config (default: 3 pending reviews). |

### Implementation Details

**Review pressure detection:**
Count pending reviews via beads — any bead in state `needs_review` or with a `review_requested` label but not yet `review_complete`:
```bash
_dispatch_review_pressure() {
    # Count beads awaiting review (shipped but not yet reviewed)
    local pending=0
    if command -v bd &>/dev/null; then
        pending=$(bd list --status=open --label=needs-review 2>/dev/null | wc -l) || pending=0
    fi
    echo "$pending"
}
```

**Score modification in `dispatch_rescore()`:**
```bash
# Review backpressure: reduce scores when review queue is deep
local review_depth
review_depth=$(_dispatch_review_pressure)
local pressure_penalty=0
if [[ "$review_depth" -gt "${DISPATCH_REVIEW_PRESSURE_THRESHOLD:-3}" ]]; then
    # Penalty scales linearly: 5 points per excess review
    pressure_penalty=$(( (review_depth - DISPATCH_REVIEW_PRESSURE_THRESHOLD) * 5 ))
fi
adjusted_score=$(( score + perturbation - pressure_penalty ))
# Floor at 1 — don't go negative (still claimable, just deprioritized)
(( adjusted_score < 1 )) && adjusted_score=1
```

**"In the weeds" protocol (from cuisine agent):**
When `review_depth > 2 * DISPATCH_REVIEW_PRESSURE_THRESHOLD`, reduce dispatch cap for the session:
```bash
if [[ "$review_depth" -gt $(( DISPATCH_REVIEW_PRESSURE_THRESHOLD * 2 )) ]]; then
    DISPATCH_CAP=1  # Reduce to single dispatch — recover flow before producing more
    dispatch_log "$session_id" "" "0" "in_the_weeds"
fi
```

### Acceptance Criteria
- [ ] `_dispatch_review_pressure()` returns count of pending reviews
- [ ] Dispatch scores are penalized proportionally to review queue depth
- [ ] At 2x threshold, dispatch cap drops to 1 ("in the weeds" mode)
- [ ] Penalty logged in dispatch telemetry for observability
- [ ] `DISPATCH_REVIEW_PRESSURE_THRESHOLD` is configurable

---

## Bead rsj.1.4: Interspect Evidence Quarantine (48h)

**Why:** CI/CD agent: bad sprints can corrupt the learning baseline. Evidence needs time to season before influencing routing.

### Files to Modify

| File | Change |
|------|--------|
| `interverse/interspect/hooks/lib-interspect.sh` | Add `quarantine_until` column to evidence table. Filter quarantined evidence from `_interspect_classify_pattern` and `_interspect_get_routing_eligible`. |

### Implementation Details

**Schema change (migration in `_interspect_ensure_db`):**
Add column if not exists:
```sql
ALTER TABLE evidence ADD COLUMN quarantine_until INTEGER DEFAULT 0;
```

**On insert — set quarantine:**
In `_interspect_insert_evidence()`, compute quarantine timestamp:
```bash
local quarantine_hours="${INTERSPECT_QUARANTINE_HOURS:-48}"
local quarantine_until=$(( $(date +%s) + quarantine_hours * 3600 ))
```

**Filter from routing queries:**
In `_interspect_get_routing_eligible()` and `_interspect_get_classified_patterns()`, add:
```sql
WHERE quarantine_until <= strftime('%s', 'now')
```

This means evidence is invisible to routing calculations until 48h after recording. The evidence is still queryable for debugging (`/interspect:evidence` shows it with a `[quarantined]` marker).

**Configuration:**
```bash
INTERSPECT_QUARANTINE_HOURS="${INTERSPECT_QUARANTINE_HOURS:-48}"
```

**Why 48h?** The CI/CD agent suggested this based on typical integration test cycle times. If a bad sprint ships on day 1, integration issues typically surface within 48h through downstream failures or human review. Evidence recorded after the quarantine period is implicitly "survived integration."

### Acceptance Criteria
- [ ] New evidence rows have `quarantine_until` set to now + 48h
- [ ] `_interspect_classify_pattern` excludes quarantined evidence
- [ ] `_interspect_get_routing_eligible` excludes quarantined evidence
- [ ] `/interspect:evidence` shows quarantined rows with a `[Q]` marker
- [ ] `INTERSPECT_QUARANTINE_HOURS=0` disables quarantine (all evidence immediate)
- [ ] Existing evidence (quarantine_until=0) is treated as non-quarantined (backward compatible)

---

## Build Sequence

```
Phase 1 (parallel):
  rsj.1.1: ic lane update + strategic_intent in metadata     [intercore + Clavain]
  rsj.1.4: evidence quarantine column + filter                [interspect]

Phase 2:
  rsj.1.3: review backpressure in dispatch_rescore()          [Clavain]

Phase 3:
  rsj.1.2: post-merge canary gate in landing skill            [Clavain + interspect]
```

**Why this order:**
- rsj.1.1 and rsj.1.4 are independent — no shared code, different modules
- rsj.1.3 needs review tracking which may surface design questions during rsj.1.1/rsj.1.4 work
- rsj.1.2 depends on rsj.1.4 (quarantined evidence is the safety net if canary misses something)

## Original Intent

The 10-agent brainstorm surfaced 15 prioritized actions. This plan covers P0 only. The remaining P1/P2 items are tracked as beads (rsj.1.5–rsj.1.10 for P1, P2 items are captured in the brainstorm doc):

| P1 | Bead | Trigger |
|----|------|---------|
| strategic_contradiction escalation | rsj.1.5 | After rsj.1.1 ships — uses the intent field it creates |
| Epic-level DoD | rsj.1.6 | After rsj.1.2 ships — builds on canary infrastructure |
| Provenance vectors | rsj.1.7 | After rsj.1.4 ships — evidence lineage needs quarantine-aware queries |
| Compound autonomy guard | rsj.1.8 | When Mycroft T2 ships |
| Decomposition quality metric | rsj.1.9 | After 3 months of data from P0 instruments |
| Temple invariant checker | rsj.1.10 | After rsj.1.2 proves the canary concept |
