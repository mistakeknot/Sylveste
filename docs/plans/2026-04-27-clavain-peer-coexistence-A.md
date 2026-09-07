---
artifact_type: plan
bead: sylveste-4ct0
stage: design
requirements:
  - F1: Reclassify agent-rig.json peers vs hard-conflicts (sylveste-gg3e)
  - F2: /clavain:setup detect-and-ask for peers (sylveste-3tm8)
  - F3: Bridge skills (interop-with-superpowers + interop-with-gsd) (sylveste-w9ys)
  - F4: /clavain:peers read-only viewer (sylveste-0i24)
  - F5: AGENTS.md beads-softening — bonus (sylveste-am1d)
  - F6: Peer-telemetry hook (sylveste-k3f7)
---

# Clavain Peer-Coexistence (A scope) — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `clavain:executing-plans` to implement this plan task-by-task.

**Bead:** sylveste-4ct0
**Goal:** Stop silently disabling peer rigs (superpowers, GSD, compound-engineering) during `/clavain:setup`; ship docs + read-only inspection + telemetry that gates future scope expansion.

**Architecture:** All edits are scoped to `os/Clavain/` (the Clavain pillar) plus a single `AGENTS.md` softening at repo root. No new runtime dependencies. Schema additions to `agent-rig.json` are additive plus one rename (`conflicts` → `hard_conflicts`). Three downstream consumers must be updated in lockstep with that rename: `verify-config.sh`, `commands/doctor.md` Section 4, `commands/setup.md` Step 3 fallback block. The new `/clavain:peers` command mirrors the existing `doctor.md` read-only-viewer pattern. Telemetry is a single shell hook that appends to `~/.clavain/peer-telemetry.jsonl`.

**Tech Stack:** Bash, JSON (jq), Markdown (SKILL.md / command frontmatter).

**Prior Learnings:**
- `docs/solutions/integration-issues/plugin-validation-errors-cache-manifest-divergence-20260217.md` — cache/manifest divergence is a recurring failure mode. F1 explicitly covers all `agent-rig.json` consumers to prevent it.
- First-stranger research session (cass) confirmed: `modpack-install.sh` `process_category("conflicts")` calls `disable_plugin` which calls `claude plugin disable` — the exact line we're guarding against. Also confirmed `doctor.md` Section 4 contains a hardcoded Python list of 10 conflicts that must be split.

---

## Must-Haves

**Truths** (observable behaviors):
- After `/clavain:setup` runs on a system with `superpowers` installed, `claude plugin list` still shows `superpowers` enabled.
- `bash modpack-install.sh --dry-run --quiet | jq` returns `peers_detected` and `peers_active` arrays.
- `bash modpack-install.sh --dry-run --quiet | jq '.would_disable'` does NOT contain any peer entry (`superpowers@superpowers-marketplace`, `compound-engineering@every-marketplace`, or any `gsd-plugin@*`).
- `/clavain:peers` invocation produces a structured detection report and does not modify any file.
- `~/.clavain/peer-telemetry.jsonl` gains one new line per session start (when telemetry not opted out).
- `/clavain:doctor` no longer reports peer rigs as conflicts (they're informational only).
- `verify-config.sh` returns success when peer rigs are present and active (does NOT report a false PASS by reading an empty `conflicts` list).

**Artifacts** (files with specific exports):
- `os/Clavain/agent-rig.json` — has `plugins.hard_conflicts` and `plugins.peers` arrays; `plugins.conflicts` removed.
- `os/Clavain/scripts/modpack-install.sh` — exports `process_peers()` shell function; preserves existing `process_category()` shape with renamed case.
- `os/Clavain/scripts/verify-config.sh` — reads both new arrays.
- `os/Clavain/commands/doctor.md` — Section 4 split into hard_conflicts (WARN) + peers (informational).
- `os/Clavain/commands/setup.md` — Step 3 fallback block no longer disables peers; Step 7 conflict count reflects hard_conflicts only.
- `os/Clavain/skills/interop-with-superpowers/SKILL.md` — exists with valid frontmatter.
- `os/Clavain/skills/interop-with-gsd/SKILL.md` — exists with valid frontmatter.
- `os/Clavain/commands/peers.md` — exists with valid command frontmatter.
- `os/Clavain/hooks/peer-telemetry.sh` (or equivalent location) — exports a single hook entry point that appends one JSONL record per session.
- `AGENTS.md` — Conventions → Work tracking paragraph reworded.

**Key Links** (where breakage cascades):
- `agent-rig.json` shape change → all 5 consumers must be updated atomically (F1).
- `modpack-install.sh` JSON output schema → `setup.md` Step 7 parsing (F2).
- `process_peers()` function existence → `peers.md` command and `setup.md` post-detection summary depend on the new JSON keys (F2 → F4).

---

## Task 1: Snapshot current state + write COMPLETE test harness (TDD)

**Files:**
- Read: `os/Clavain/agent-rig.json`, `os/Clavain/scripts/verify-config.sh`, `os/Clavain/commands/doctor.md`, `os/Clavain/commands/setup.md`, `os/Clavain/scripts/modpack-install.sh`, `os/Clavain/hooks/hooks.json`
- Create: `os/Clavain/scripts/test-peer-coexistence.sh` (acceptance harness for F1–F6, written ONCE in this task)

**IMPORTANT:** Other tasks never modify this file. All test cases for F1–F6 live here from the start. This avoids write contention in Wave 3.

**Step 1: Write the complete failing harness**

Create `os/Clavain/scripts/test-peer-coexistence.sh` with all test cases (F1.1–F6.3), all expected to FAIL before any implementation lands:

```bash
#!/usr/bin/env bash
# test-peer-coexistence.sh — acceptance tests for sylveste-4ct0 (A scope, all features)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RIG="$SCRIPT_DIR/../agent-rig.json"
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# ---- F1: agent-rig.json reclassification ----
jq -e '.plugins.hard_conflicts | type == "array"' "$RIG" >/dev/null || fail "F1.1 hard_conflicts missing"
pass "F1.1 hard_conflicts array exists"

jq -e '.plugins.peers | type == "array"' "$RIG" >/dev/null || fail "F1.2 peers missing"
pass "F1.2 peers array exists"

jq -e '.plugins.conflicts == null' "$RIG" >/dev/null || fail "F1.3 legacy conflicts still present"
pass "F1.3 legacy conflicts removed"

jq -e '.plugins.peers[]? | select(.source == "superpowers@superpowers-marketplace")' "$RIG" >/dev/null || fail "F1.4 superpowers should be in peers"
pass "F1.4 superpowers in peers"

jq -e '.plugins.peers | all(.bridge_skill != null)' "$RIG" >/dev/null || fail "F1.5 peer missing bridge_skill"
pass "F1.5 each peer has bridge_skill"

# F1.6: verify-config.sh updated to read new arrays (no false PASS via empty conflicts)
grep -q "hard_conflicts" "$SCRIPT_DIR/verify-config.sh" || fail "F1.6 verify-config.sh still references legacy conflicts"
pass "F1.6 verify-config.sh updated"

# ---- F2: modpack-install.sh process_peers() ----
DRYRUN=$(bash "$SCRIPT_DIR/modpack-install.sh" --dry-run --quiet 2>/dev/null) || fail "F2.0 modpack-install --dry-run failed"
echo "$DRYRUN" | jq -e '.peers_detected | type == "array"' >/dev/null || fail "F2.1 peers_detected missing"
pass "F2.1 peers_detected key present"

echo "$DRYRUN" | jq -e '.peers_active | type == "array"' >/dev/null || fail "F2.2 peers_active missing"
pass "F2.2 peers_active key present"

peer_in_disable=$(echo "$DRYRUN" | jq '[.would_disable[]? | select(. == "superpowers@superpowers-marketplace" or . == "compound-engineering@every-marketplace")] | length')
[[ "$peer_in_disable" == "0" ]] || fail "F2.3 peer found in would_disable: $peer_in_disable"
pass "F2.3 no peers in would_disable"

bash "$SCRIPT_DIR/modpack-install.sh" --dry-run --quiet --category=hard_conflicts >/dev/null || fail "F2.4 hard_conflicts category not accepted"
pass "F2.4 hard_conflicts category accepted"

bash "$SCRIPT_DIR/modpack-install.sh" --dry-run --quiet --category=peers >/dev/null || fail "F2.5 peers category not accepted"
pass "F2.5 peers category accepted"

if bash "$SCRIPT_DIR/modpack-install.sh" --dry-run --quiet --category=conflicts 2>/dev/null; then
    fail "F2.6 legacy conflicts category should be rejected"
fi
pass "F2.6 legacy conflicts category rejected"

# ---- F3: bridge skills exist ----
[[ -f "$SCRIPT_DIR/../skills/interop-with-superpowers/SKILL.md" ]] || fail "F3.1 interop-with-superpowers/SKILL.md missing"
pass "F3.1 interop-with-superpowers exists"

[[ -f "$SCRIPT_DIR/../skills/interop-with-gsd/SKILL.md" ]] || fail "F3.2 interop-with-gsd/SKILL.md missing"
pass "F3.2 interop-with-gsd exists"

# ---- F4: /clavain:peers viewer ----
[[ -f "$SCRIPT_DIR/../commands/peers.md" ]] || fail "F4.1 peers.md missing"
head -5 "$SCRIPT_DIR/../commands/peers.md" | grep -q "^name:" || fail "F4.2 peers.md missing name frontmatter"
pass "F4.1 peers.md exists with frontmatter"
grep -q "[Rr]ead-only" "$SCRIPT_DIR/../commands/peers.md" || fail "F4.3 peers.md missing read-only assertion"
pass "F4.3 peers.md asserts read-only"

# ---- F5: AGENTS.md beads-softening (bonus) ----
# Soft-check — F5 is bonus; don't fail the whole harness if not landed
if grep -q "is the canonical tracker for Sylveste-internal work" "$SCRIPT_DIR/../../../AGENTS.md" 2>/dev/null; then
    pass "F5.1 AGENTS.md softened (bonus)"
else
    echo "SKIP: F5.1 AGENTS.md softening not applied (bonus, optional)"
fi

# ---- F6: peer-telemetry hook ----
[[ -x "$SCRIPT_DIR/../hooks/peer-telemetry.sh" ]] || fail "F6.1 peer-telemetry.sh missing/not executable"
pass "F6.1 peer-telemetry.sh exists"

TMPLOG=$(mktemp); rm -f "$TMPLOG"
CLAVAIN_PEER_TELEMETRY_FILE="$TMPLOG" bash "$SCRIPT_DIR/../hooks/peer-telemetry.sh" >/dev/null 2>&1
[[ -s "$TMPLOG" ]] || fail "F6.2 telemetry hook produced no output"
jq -e '. | type == "object"' "$TMPLOG" >/dev/null || fail "F6.2 telemetry not valid JSON"
pass "F6.2 hook emits valid JSONL"

TMPLOG2=$(mktemp); rm -f "$TMPLOG2"
CLAVAIN_PEER_TELEMETRY=0 CLAVAIN_PEER_TELEMETRY_FILE="$TMPLOG2" bash "$SCRIPT_DIR/../hooks/peer-telemetry.sh" >/dev/null 2>&1
[[ ! -s "$TMPLOG2" ]] || fail "F6.3 opt-out did not suppress telemetry"
pass "F6.3 opt-out env var works"
rm -f "$TMPLOG"

# F6.4: hook is registered in hooks.json (not plugin.json)
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"
[[ -f "$HOOKS_JSON" ]] || fail "F6.4 hooks.json missing"
jq -e '.hooks.SessionStart | map(.hooks[]?.command) | flatten | any(. | contains("peer-telemetry.sh"))' "$HOOKS_JSON" >/dev/null || fail "F6.4 peer-telemetry not registered in hooks.json SessionStart"
pass "F6.4 peer-telemetry registered in hooks.json"

echo
echo "=== ALL ACCEPTANCE TESTS PASSED ==="
```

**Step 2: Run test to verify it fails on F1.1**

Run: `bash os/Clavain/scripts/test-peer-coexistence.sh`
Expected: FAIL on F1.1 (hard_conflicts not yet added).

**Step 3: Commit the complete harness**

```bash
git add os/Clavain/scripts/test-peer-coexistence.sh
git commit -m "test(clavain): complete peer-coexistence acceptance harness (sylveste-4ct0)"
```

<verify>
- run: `bash os/Clavain/scripts/test-peer-coexistence.sh 2>&1 | head -1`
  expect: contains "FAIL: F1.1"
</verify>

---

## Task 2: F1 — agent-rig.json reclassification (sylveste-gg3e)

**Files:**
- Modify: `os/Clavain/agent-rig.json`
- Modify: `os/Clavain/scripts/verify-config.sh`
- Modify: `os/Clavain/commands/doctor.md`
- Modify: `os/Clavain/commands/setup.md`

**Step 1: Edit `agent-rig.json`**

Rename `plugins.conflicts` → `plugins.hard_conflicts`. Move these entries (which represent true duplicates):
- `code-review@claude-plugins-official`
- `pr-review-toolkit@claude-plugins-official`
- `code-simplifier@claude-plugins-official`
- `commit-commands@claude-plugins-official`
- `feature-dev@claude-plugins-official`
- `claude-md-management@claude-plugins-official`
- `frontend-design@claude-plugins-official`
- `hookify@claude-plugins-official`

Add a new `plugins.peers` array with these entries (move from old `conflicts`):
```json
{
  "source": "superpowers@superpowers-marketplace",
  "reason": "Peer agent rig. Clavain shares vocabulary but does not replace it.",
  "bridge_skill": "skills/interop-with-superpowers"
},
{
  "source": "compound-engineering@every-marketplace",
  "reason": "Peer agent rig. Predecessor of several Clavain skills; coexistence supported.",
  "bridge_skill": "skills/interop-with-superpowers"
},
{
  "source": "gsd-plugin@jnuyens",
  "reason": "Peer agent rig (Get Stuff Done). Spec-driven workflow; coexistence supported.",
  "bridge_skill": "skills/interop-with-gsd"
}
```

(GSD marketplace identifier — confirm before commit. If `jnuyens` is not the canonical marketplace, leave a TODO comment and use the closest match.)

**Step 2: Update `verify-config.sh`**

Find the line (~48) that reads `plugins.conflicts`:
```bash
jq -r '[.plugins.conflicts[]?.source] | sort | .[]'
```
Replace with logic that:
- Reads `plugins.hard_conflicts` for the existing "expected disabled" check.
- Reads `plugins.peers` and reports them as expected-present-and-active (NOT as expected-disabled).

The function should not produce a false PASS when `hard_conflicts` is empty after the rename.

**Step 3: Update `commands/doctor.md` Section 4**

Locate the hardcoded Python list (Section 4: "Conflicting Plugins"). Split into two distinct blocks:

```python
# Hard conflicts (true duplicates — WARN if installed)
HARD_CONFLICTS = [
    "code-review@claude-plugins-official",
    "pr-review-toolkit@claude-plugins-official",
    # ... (8 total)
]

# Peer rigs (alternate methodologies — informational only, NOT a conflict)
PEER_RIGS = [
    "superpowers@superpowers-marketplace",
    "compound-engineering@every-marketplace",
    "gsd-plugin@jnuyens",
]
```

Update output formatting: hard_conflicts continue to WARN; peers report as `Peer rig detected — see /clavain:peers`.

**Step 4: Update `commands/setup.md` Step 3**

Locate the `<!-- agent-rig:begin:disable-conflicts -->` region (around lines 95–108). Remove these two lines:
```bash
claude plugin disable superpowers@superpowers-marketplace
claude plugin disable compound-engineering@every-marketplace
```
Leave the hard-conflict disables in place (those are still correct behavior).

**Step 5: Run F1 acceptance tests**

```bash
bash os/Clavain/scripts/test-peer-coexistence.sh
```
Expected: F1.1–F1.5 PASS.

Plus a manual check that the doctor.md/setup.md changes are consistent (use git diff).

**Step 6: Commit**

```bash
git add os/Clavain/agent-rig.json os/Clavain/scripts/verify-config.sh os/Clavain/commands/doctor.md os/Clavain/commands/setup.md
git commit -m "feat(clavain): reclassify agent-rig.json peers vs hard-conflicts (sylveste-gg3e)"
```

<verify>
- run: `jq -e '.plugins.peers | length >= 3' os/Clavain/agent-rig.json`
  expect: exit 0
- run: `jq -e '.plugins.conflicts == null' os/Clavain/agent-rig.json`
  expect: exit 0
- run: `grep -c "claude plugin disable superpowers" os/Clavain/commands/setup.md`
  expect: contains "0"
- run: `grep -c "hard_conflicts" os/Clavain/scripts/verify-config.sh`
  expect: contains "1"
- run: `bash os/Clavain/scripts/test-peer-coexistence.sh 2>&1 | grep -E "PASS: F1\."`
  expect: contains "F1.6"
</verify>

**Pre-commit hygiene check (catches missed downstream consumers):**
```bash
# After all four files edited but before commit, scan for any remaining bare `plugins.conflicts` reference
# in tracked Clavain source files. Hits indicate a missed consumer.
grep -rn "plugins\.conflicts" os/Clavain/ --include="*.sh" --include="*.md" --include="*.json" --include="*.go" --include="*.py"
```
Expected output: empty (zero hits).

---

## Task 3: F2 — modpack-install.sh process_peers() (sylveste-3tm8)

**Files:**
- Modify: `os/Clavain/scripts/modpack-install.sh`
- Modify: `os/Clavain/commands/setup.md` (Step 7 count update)

(F2 test cases F2.1–F2.6 already exist in the harness from Task 1; they currently FAIL. This task makes them pass.)

**Step 1: Edit `modpack-install.sh` — six edit sites**

Site 1 — `process_category()` rename `conflicts` → `hard_conflicts`:
```bash
hard_conflicts)
    sources=$(jq -r '.plugins.hard_conflicts[]?.source' "$RIG_FILE")
    ;;
```

Site 2 — add `peers` case routing to a new `process_peers()` function:
```bash
peers)
    process_peers
    return 0
    ;;
```

Site 3 — add the `process_peers()` function (sibling to `process_category()`, NEVER calls `disable_plugin`):
```bash
process_peers() {
    local sources
    sources=$(jq -r '.plugins.peers[]?.source' "$RIG_FILE")
    if [[ -z "$sources" ]]; then
        return 0
    fi
    while IFS= read -r source; do
        [[ -z "$source" ]] && continue
        if is_installed "$source"; then
            peers_detected+=("$source")
            if is_disabled "$source"; then
                log "  [peer-detected, disabled] $source"
            else
                peers_active+=("$source")
                log "  [peer-detected, active] $source"
            fi
        fi
        # NB: never call disable_plugin for peers
    done <<< "$sources"
}
```

Site 4 — update the `all` main block (around line 217–242) to call both new category names:
```bash
all)
    process_category "core"
    process_category "required"
    process_category "recommended"
    process_category "optional"
    process_category "hard_conflicts"
    process_peers
    ;;
```

Site 5 — update `--category=` validation allowlist (around line 234):
```bash
required|recommended|optional|infrastructure|hard_conflicts|peers|core)
```

Site 6 — add accumulators near top (after `optional_available=()`):
```bash
peers_detected=()
peers_active=()
```

Site 7 (also part of site 6, both JSON output blocks) — both dry-run and live JSON outputs must include the new keys:
```bash
peers_detected_json=$(json_array "${peers_detected[@]}")
peers_active_json=$(json_array "${peers_active[@]}")
```
And add `--argjson peers_detected "$peers_detected_json" --argjson peers_active "$peers_active_json"` plus `peers_detected: $peers_detected, peers_active: $peers_active` to both `jq -n` calls.

**Step 4: Add failure-loud peer-detection-warning**

In `is_installed` (or a wrapper called by `process_peers`), if a partial match is found (e.g., plugin name found but version mismatch in cache), emit:
```bash
echo "peer_detection_warning: ambiguous match for $source" >&2
```

**Step 5: Update `setup.md` Step 7 conflict count**

Find the Step 7 "Conflicts disabled" reference and change the implied total to reflect `hard_conflicts` only (8, not 10).

**Step 6: Run F2 tests**

```bash
bash os/Clavain/scripts/test-peer-coexistence.sh
```
Expected: F1.* + F2.1–F2.6 all PASS.

**Idempotency note:** `process_peers()` is called from the `peers` case AND from `all` mode. Both paths share the global accumulators (`peers_detected`, `peers_active`). Either short-circuit if accumulators are already populated, OR ensure `--category=peers` is never combined with `all` mode (the existing case structure already enforces this — `all` is one branch, `peers` is another). Verify by inspection.

**Step 7: Commit**

```bash
git add os/Clavain/scripts/modpack-install.sh os/Clavain/commands/setup.md
git commit -m "feat(clavain): add process_peers() report-only path; never auto-disable peer rigs (sylveste-3tm8)"
```

<verify>
- run: `bash os/Clavain/scripts/modpack-install.sh --dry-run --quiet | jq -e '.peers_detected'`
  expect: exit 0
- run: `bash os/Clavain/scripts/test-peer-coexistence.sh`
  expect: exit 0
- run: `grep -c "process_peers" os/Clavain/scripts/modpack-install.sh`
  expect: contains "3"
</verify>

---

## Task 4: F3 — Bridge skills (sylveste-w9ys) [parallel-able]

**Files:**
- Create: `os/Clavain/skills/interop-with-superpowers/SKILL.md`
- Create: `os/Clavain/skills/interop-with-gsd/SKILL.md`

**Step 1: Create `interop-with-superpowers/SKILL.md`**

```markdown
---
name: interop-with-superpowers
description: If superpowers is not installed, this skill is informational only. Use when the user mentions /superpowers:* commands or asks how Clavain relates to superpowers (obra/superpowers).
---

# Interop with Superpowers

Clavain shares vocabulary with [superpowers](https://github.com/obra/superpowers) — specifically the `dispatching-parallel-agents`, `executing-plans`, `subagent-driven-development`, `code-review-discipline` (renamed from `requesting-code-review`), and `using-clavain` (renamed from `using-superpowers`) skills are vendored from upstream and continue to evolve via `/clavain:upstream-sync`.

## Vocabulary mapping

| Clavain command | superpowers command | Notes |
|---|---|---|
| `/clavain:write-plan` | `/superpowers:write-plan` | Both produce `docs/plans/<date>-<slug>.md` |
| `/clavain:brainstorm` | `/superpowers:brainstorm` | Same goal; Clavain emits beads |
| `/clavain:execute-plan` | `/superpowers:execute-plan` | Clavain integrates with sprint orchestrator |
| `clavain:dispatching-parallel-agents` skill | `superpowers:dispatching-parallel-agents` skill | Identical semantics; vendored |
| `clavain:subagent-driven-development` skill | `superpowers:subagent-driven-development` skill | Vendored; identical |

## When to reach for superpowers instead

If you prefer the original obra workflow (lighter integration, no beads requirement, no Sylveste-specific routing), invoke superpowers directly. Both rigs coexist — Clavain does not replace superpowers, and `/clavain:setup` does not disable it.
```

**Step 2: Create `interop-with-gsd/SKILL.md`**

```markdown
---
name: interop-with-gsd
description: If gsd-plugin is not installed, this skill is informational only. Use when the user mentions /gsd:* commands, references the GSD framework (Get Stuff Done), or asks how Clavain compares to spec-driven development workflows.
---

# Interop with GSD (Get Stuff Done)

[GSD](https://github.com/gsd-build/get-shit-done) (also packaged as [gsd-plugin](https://github.com/jnuyens/gsd-plugin)) is a spec-driven development framework for Claude Code. It splits complex tasks into plan/execute/review phases, each with its own clean context. Clavain's sprint orchestrator follows a similar pattern with additional review gates.

## Vocabulary mapping

| Clavain command | GSD command | Notes |
|---|---|---|
| `/clavain:write-plan` | `/gsd:plan` | Both produce a structured plan doc |
| `/clavain:execute-plan` | `/gsd:execute` | Clavain dispatches subagents per task; GSD spawns fresh Claude instances |
| `/clavain:verify` | `/gsd:verify` | Both check the implementation matches the spec |
| `/clavain:brainstorm` | (no direct GSD equivalent) | GSD jumps straight to plan; Clavain has a separate brainstorm phase |
| `/clavain:reflect` | (no direct GSD equivalent) | Clavain captures sprint learnings; GSD relies on PR review |

## When to reach for GSD instead

GSD's strength is fresh-context-per-phase isolation — useful when context rot is the dominant failure mode. If you are working on a project with extensive specs and want each phase to start clean, invoke `/gsd:*` directly. Clavain's strength is multi-agent review gates and sprint-state continuity. Pick whichever your project's workflow needs; both rigs coexist.
```

**Step 3: Register skills in plugin manifest**

If `interverse/clavain/.claude-plugin/plugin.json` (or the manifest read by Clavain) has a `skills` array, add `./skills/interop-with-superpowers` and `./skills/interop-with-gsd`. Otherwise (skills auto-discovered from filesystem), no further change.

**Step 4: Verify the skills load**

```bash
ls os/Clavain/skills/interop-with-superpowers/SKILL.md os/Clavain/skills/interop-with-gsd/SKILL.md
head -3 os/Clavain/skills/interop-with-superpowers/SKILL.md  # check frontmatter
head -3 os/Clavain/skills/interop-with-gsd/SKILL.md
```

**Step 5: Commit**

```bash
git add os/Clavain/skills/interop-with-superpowers/ os/Clavain/skills/interop-with-gsd/
[[ -f os/Clavain/.claude-plugin/plugin.json ]] && git add os/Clavain/.claude-plugin/plugin.json
git commit -m "docs(clavain): add interop-with-superpowers + interop-with-gsd bridge skills (sylveste-w9ys)"
```

<verify>
- run: `test -f os/Clavain/skills/interop-with-superpowers/SKILL.md && test -f os/Clavain/skills/interop-with-gsd/SKILL.md`
  expect: exit 0
- run: `head -3 os/Clavain/skills/interop-with-superpowers/SKILL.md`
  expect: contains "interop-with-superpowers"
</verify>

---

## Task 5: F4 — /clavain:peers viewer (sylveste-0i24)

**Depends on:** Task 2 (F1) for the new `peers` array; Task 3 (F2) for `--category=peers` support in `modpack-install.sh`. Both must land before this task's smoke test will pass.

**Files:**
- Create: `os/Clavain/commands/peers.md`

(F4 test cases F4.1–F4.3 already exist in the harness from Task 1.)

**Step 1: Create `commands/peers.md`**

```markdown
---
name: peers
description: Read-only viewer for detected peer agent rigs (superpowers, GSD, compound-engineering). Lists detection state and recommended bridge skills. Never makes changes.
argument-hint: "[no arguments]"
---

# Clavain Peer Status

Read-only diagnostic. Never makes changes.

## What This Does

Reports which peer agent rigs (alternative Claude Code rigs that share vocabulary with Clavain) are present on this system, whether they are active, and which bridge skill documents the methodology mapping. Mirrors the inspection pattern of `/clavain:doctor`.

## How To Run

```bash
CLAVAIN_DIR=$(dirname "$(ls ~/.claude/plugins/cache/interagency-marketplace/clavain/*/agent-rig.json 2>/dev/null | head -1)")
bash "$CLAVAIN_DIR/scripts/modpack-install.sh" --dry-run --quiet --category=peers
```

Parse the JSON output and present:

```
Detected peer rigs:
  - superpowers@superpowers-marketplace          [installed, active]      bridge: skills/interop-with-superpowers
  - compound-engineering@every-marketplace       [installed, disabled]    bridge: skills/interop-with-superpowers
  - gsd-plugin@jnuyens                           [not installed]          bridge: skills/interop-with-gsd

No peer rigs are auto-disabled by /clavain:setup. To inspect interop guidance for a detected peer:
  /clavain:help interop-with-superpowers
  /clavain:help interop-with-gsd
```

## Codex CLI

This command is Claude Code only. On Codex, use:
```bash
bash ~/.codex/clavain/scripts/modpack-install.sh --dry-run --quiet --category=peers | jq
```
to get the equivalent peer status.

## Output Contract

Read-only. Does not modify `~/.claude/settings.json`, any plugin file, or any project file. Implementation MUST verify this by running the underlying script with `--dry-run` and reading the JSON.
```

**Step 2: Run F4 tests**

```bash
bash os/Clavain/scripts/test-peer-coexistence.sh
```
Expected: F4.1 + F4.3 PASS.

**Step 3: Smoke-test the command**

Manually invoke `/clavain:peers` in this session (or document that it requires a fresh session to register). Verify:
- The command produces output naming each peer.
- `~/.claude/settings.json` mtime is unchanged before/after.
- `git status` shows no unintended changes.

**Step 4: Commit**

```bash
git add os/Clavain/commands/peers.md
git commit -m "feat(clavain): add /clavain:peers read-only viewer (sylveste-0i24)"
```

<verify>
- run: `test -f os/Clavain/commands/peers.md`
  expect: exit 0
- run: `head -1 os/Clavain/commands/peers.md`
  expect: contains "---"
- run: `bash os/Clavain/scripts/test-peer-coexistence.sh`
  expect: exit 0
</verify>

---

## Task 6: F6 — Peer-telemetry hook (sylveste-k3f7) [parallel-able]

**Files:**
- Create: `os/Clavain/hooks/peer-telemetry.sh`
- Modify: `os/Clavain/hooks/hooks.json` (NOT plugin.json — Clavain registers hooks here per existing convention; verified by reading hooks.json)
- Modify: `os/Clavain/CLAUDE.md` (one-line documentation)

(F6 test cases F6.1–F6.4 already exist in the harness from Task 1.)

**Step 1: Create `hooks/peer-telemetry.sh`**

```bash
#!/usr/bin/env bash
# peer-telemetry.sh — Append one JSONL record per session with peer-rig detection state.
# Opt out: set CLAVAIN_PEER_TELEMETRY=0 or `telemetry.peers: false` in ~/.clavain/config.json.
set -euo pipefail

[[ "${CLAVAIN_PEER_TELEMETRY:-1}" == "0" ]] && exit 0
if [[ -f "$HOME/.clavain/config.json" ]] && \
   jq -e '.telemetry.peers == false' "$HOME/.clavain/config.json" >/dev/null 2>&1; then
    exit 0
fi

LOG="${CLAVAIN_PEER_TELEMETRY_FILE:-$HOME/.clavain/peer-telemetry.jsonl}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0  # silent fail if HOME unwritable

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RIG="$SCRIPT_DIR/../agent-rig.json"
[[ -f "$RIG" ]] || exit 0  # no rig, nothing to report

# Detect peers (best-effort; no failures propagate)
peers_detected="[]"
if command -v jq &>/dev/null; then
    peers_detected=$(jq -c '[.plugins.peers[]?.source]' "$RIG" 2>/dev/null || echo "[]")
fi

# Hash session_id (no PII)
SID="${CLAUDE_SESSION_ID:-${CODEX_SESSION_ID:-unknown}}"
SID_HASH=$(printf '%s' "$SID" | sha256sum | cut -c1-12)

# Build record
TS=$(date +%s)
RECORD=$(jq -nc \
    --arg ts "$TS" \
    --arg sid "$SID_HASH" \
    --argjson peers "$peers_detected" \
    '{ts:($ts|tonumber), session:$sid, peers_detected:$peers, using_skill_invoked:null}')

echo "$RECORD" >> "$LOG" 2>/dev/null || true
```

Make executable:
```bash
chmod +x os/Clavain/hooks/peer-telemetry.sh
```

**Step 2: Register the SessionStart hook in `os/Clavain/hooks/hooks.json`**

The existing schema is:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh", "async": true }
        ]
      }
    ],
    ...
  }
}
```

Add a new entry to the `SessionStart` matcher's `hooks` array (NOT a new top-level matcher block — share the existing `startup|resume|clear|compact` matcher):

```json
{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/peer-telemetry.sh", "async": true, "timeout": 3 }
```

(`async: true` so it never blocks session start; `timeout: 3` because telemetry should never delay a session more than ~3 seconds.)

**Step 3: Document in CLAUDE.md**

Add one line under a "Telemetry" subsection:

```markdown
### Telemetry
- `~/.clavain/peer-telemetry.jsonl` — one record per session with detected peer rigs. Opt out via `CLAVAIN_PEER_TELEMETRY=0` env or `telemetry.peers: false` in `~/.clavain/config.json`. Used to gate B′/C′ scope expansion (sylveste-fj1w / sylveste-yofd).
```

**Step 4: Run F6 tests**

```bash
bash os/Clavain/scripts/test-peer-coexistence.sh
```
Expected: F6.1–F6.4 PASS.

**Step 5: Commit**

```bash
git add os/Clavain/hooks/peer-telemetry.sh os/Clavain/hooks/hooks.json os/Clavain/CLAUDE.md
git commit -m "feat(clavain): peer-telemetry hook for B'/C' gating (sylveste-k3f7)"
```

<verify>
- run: `test -x os/Clavain/hooks/peer-telemetry.sh`
  expect: exit 0
- run: `jq -e '.hooks.SessionStart | map(.hooks[]?.command) | flatten | any(. | contains("peer-telemetry.sh"))' os/Clavain/hooks/hooks.json`
  expect: exit 0
- run: `bash os/Clavain/scripts/test-peer-coexistence.sh`
  expect: exit 0
</verify>

**Recovery note (from review):** If a malformed `hooks.json` causes Claude Code to skip the hook entirely, the plugin still loads — just the telemetry doesn't fire. Validate the JSON parses (`jq . os/Clavain/hooks/hooks.json`) before commit. If the hook script itself errors at runtime, `async: true` ensures it doesn't block session start; the hook script's `|| true` safety net at the end prevents bubbling.

---

## Task 7: F5 — AGENTS.md beads-softening — bonus (sylveste-am1d)

**Files:**
- Modify: `AGENTS.md` (repo root)

**Step 1: Edit `AGENTS.md`** — locate the "Conventions → Work tracking" paragraph:

Current text (approximately):
> **Work tracking:** Beads (`bd create/close`) is the single source of truth. Never create TODO files, markdown checklists, or pending-beads lists.

New text:
> **Work tracking:** Beads (`bd create/close`) is the canonical tracker for Sylveste-internal work. Sylveste agents and contributors use beads for all work tracking inside this repo. External rigs (superpowers, GSD, compound-engineering) ship their own task surfaces and are not displaced by this rule — that tracking belongs to those rigs. Never duplicate Sylveste work tracking via TODO files or markdown checklists.

Then locate the `<!-- BEGIN BEADS INTEGRATION v:1 -->` block's "Rules" section and reword similarly to remove absolute prohibitions while keeping beads as canonical for Sylveste.

**Step 2: Commit**

(No global grep needed — the verify block scopes the check to `AGENTS.md` only. The phrase "Never create TODO files" appears in committed docs files (PRD, plan, research notes) and that is fine — those are historical artifacts, not active prohibitions.)

```bash
git add AGENTS.md
git commit -m "docs: scope Beads canonicalization to project, not absolute prohibition (sylveste-am1d)"
```

<verify>
- run: `grep -c "is the canonical tracker for Sylveste-internal work" AGENTS.md`
  expect: contains "1"
- run: `grep -c "Never create TODO files" AGENTS.md`
  expect: contains "0"
</verify>

---

## Task 8: End-to-end manual verification (no commit unless additional fixes needed)

Run the full acceptance harness one more time:

```bash
bash os/Clavain/scripts/test-peer-coexistence.sh
```

Plus the CUJ smoke test (manual, requires a system with superpowers installed):

1. Confirm `superpowers@superpowers-marketplace` is enabled in `~/.claude/settings.json`.
2. Run `bash os/Clavain/scripts/modpack-install.sh --dry-run --quiet | jq '{would_disable, peers_detected, peers_active}'`. Expect `would_disable` to NOT contain superpowers; expect `peers_detected` to contain it.
3. Verify `~/.claude/settings.json` mtime is unchanged.
4. Invoke `/clavain:peers` (in a fresh Claude Code session) — verify output includes superpowers row.
5. Verify `~/.clavain/peer-telemetry.jsonl` gained one line during the session.

If anything fails: fix, re-run from the failing task, commit. If everything passes: proceed to sprint Step 6 (Test & Verify) and Step 7 (Quality Gates).

<verify>
- run: `bash os/Clavain/scripts/test-peer-coexistence.sh`
  expect: exit 0
</verify>

---

## Notes

- **Order matters for F1 → F2 → F4.** F2 (modpack-install.sh) reads the new `peers` array. F4 (`/clavain:peers` viewer) invokes `modpack-install.sh --category=peers` which only exists after F2. The manifest enforces `task-5 depends: [task-2, task-3]`.
- **Test harness ownership.** Task 1 writes the COMPLETE harness for F1–F6. No other task modifies it. This eliminates write contention in Wave 3.
- **F3 is fully independent** of F1/F2; it can land in Wave 3 alongside F2 and F6.
- **F5 is bonus.** If during F5 implementation the AGENTS.md rewrite turns out non-trivial (e.g., the BEGIN BEADS INTEGRATION block has its own auto-generation), defer to a follow-up bead and ship without it.
- **GSD marketplace identifier is the only unconfirmed detail.** If `gsd-plugin@jnuyens` is wrong, the F1 entry can be updated by anyone who confirms the correct marketplace; downstream consumers will detect-or-not-detect based on the source string, no breakage.
- **Telemetry capture point** is session start (per F6 design). It does not capture which `using-*` skill ultimately won the routing decision — that requires a session-end hook which is fragile. Document this limitation in the F6 implementation comments. B′ scope can refine if telemetry data justifies it.
- **Hook registration target** is `os/Clavain/hooks/hooks.json`, NOT `plugin.json`. Verified by reading the existing file's schema (it already has SessionStart/PreToolUse/PostToolUse blocks). Add to the existing `startup|resume|clear|compact` matcher rather than introducing a new top-level matcher.
- **compound-engineering bridge_skill** points to `skills/interop-with-superpowers` for V1 (shared with superpowers since they're closely related). A dedicated `interop-with-compound-engineering` bridge skill is filed as P3 for B-scope (sylveste-fj1w) if telemetry shows compound-engineering coexistence usage.
- **Idempotency**: `process_peers()` in F2 is called from either the `peers` case OR `all` mode (mutually exclusive in the existing case structure). Accumulators don't double-fill in normal operation. Note this in the implementation comment.
- **Pre-commit consumer scan**: After Task 2 edits, run `grep -rn "plugins\.conflicts" os/Clavain/` to catch any consumer not yet updated. Expected output: empty. If non-empty, update the matched file(s) before commit.
