---
artifact_type: plan
bead: iv-zsio
stage: design
---
# Discovery Sprint Presentation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-zsio
**Goal:** Make interject-originated beads display as enriched discovery items in Clavain's sprint discovery menu

**Architecture:** Add metadata extraction to lib-discovery.sh (parse source/score from bead description), add `review_discovery` action type for `[interject]` beads, and update route.md presentation rules to show enriched labels and route to individual review.

**Tech Stack:** Bash (lib-discovery.sh), Markdown (route.md), BATS (tests)

---

### Task 1: Add Metadata Extraction to lib-discovery.sh

**Files:**
- Modify: `interverse/interphase/hooks/lib-discovery.sh:269-378` (inside the scoring loop)
- Test: `interverse/interphase/tests/shell/test_discovery.bats` (if exists, else create)

**Step 1: Add extraction helper function**

Add after line 167 (after `infer_bead_action` function), before the parent-closed detection section:

```bash
# ---- Interject Metadata Extraction ----------------------------------------

# Extract discovery source and relevance score from [interject] bead descriptions.
# Parses the structured format written by interject's OutputPipeline._create_bead():
#   Source: <name> | <url>
#   Relevance score: <float>
#
# Args: $1 = bead_id
# Output: "source|score" to stdout (e.g. "arxiv|0.85"), or "|" if not an interject bead
_extract_interject_metadata() {
    local bead_id="$1"
    local desc
    desc=$(bd show "$bead_id" --json 2>/dev/null | jq -r '.description // ""') || { echo "|"; return 0; }

    local source="" score=""
    # Parse "Source: <name> | <url>" — extract the source name before the pipe
    if [[ "$desc" =~ ^Source:\ ([a-z_]+)\ \| ]]; then
        source="${BASH_REMATCH[1]}"
    fi
    # Parse "Relevance score: <float>"
    if [[ "$desc" =~ Relevance\ score:\ ([0-9]+\.[0-9]+) ]]; then
        score="${BASH_REMATCH[1]}"
    fi

    echo "${source}|${score}"
}
```

**Step 2: Call extraction in the scanner loop**

Inside `discovery_scan_beads()`, after the action inference block (around line 307) and before the staleness check, add interject metadata extraction:

```bash
        # Interject metadata extraction
        local discovery_source="" discovery_score=""
        if [[ "$title" == "[interject]"* ]]; then
            local ij_meta
            ij_meta=$(_extract_interject_metadata "$id")
            discovery_source="${ij_meta%%|*}"
            discovery_score="${ij_meta#*|}"
        fi
```

**Step 3: Include metadata in JSON output**

In the `jq` append command (around line 366-378), add two new fields. The updated jq call adds `--arg discovery_source` and `--arg discovery_score` parameters and includes them in the object:

```bash
        results=$(echo "$results" | jq \
            --arg id "$id" \
            --arg title "$title" \
            --argjson priority "${priority:-4}" \
            --arg status "$status" \
            --arg action "$action" \
            --arg plan_path "$plan_path" \
            --argjson stale "$stale" \
            --arg phase "$phase" \
            --argjson score "${score:-0}" \
            --arg parent_closed_epic "${parent_closed_epic:-}" \
            --arg claimed_by "${claimed_by}" \
            --arg discovery_source "${discovery_source}" \
            --arg discovery_score "${discovery_score}" \
            '. + [{id: $id, title: $title, priority: $priority, status: $status, action: $action, plan_path: $plan_path, stale: $stale, phase: $phase, score: $score, parent_closed_epic: (if $parent_closed_epic == "" then null else $parent_closed_epic end), claimed_by: (if $claimed_by == "" then null else $claimed_by end), discovery_source: (if $discovery_source == "" then null else $discovery_source end), discovery_score: (if $discovery_score == "" then null else $discovery_score end)}]')
```

**Step 4: Add `review_discovery` action for untriaged interject beads**

In `infer_bead_action()`, add a check before the filesystem-based fallback (around line 155). If the bead title starts with `[interject]` and has no phase set, return `review_discovery`:

```bash
    # Interject beads without phase → route to discovery review (not brainstorm)
    if [[ -z "$phase" ]]; then
        local bead_title
        bead_title=$(bd show "$bead_id" --json 2>/dev/null | jq -r '.title // ""') || bead_title=""
        if [[ "$bead_title" == "[interject]"* ]]; then
            echo "review_discovery|"
            return 0
        fi
    fi
```

Note: This must go AFTER the phase-based inference (line 142-153) but BEFORE the filesystem-based fallback (line 155).

**Step 5: Run syntax check**

Run: `bash -n interverse/interphase/hooks/lib-discovery.sh`
Expected: No output (clean syntax)

**Step 6: Commit**

```bash
cd interverse/interphase && git add hooks/lib-discovery.sh && git commit -m "feat: extract interject metadata and add review_discovery action (iv-zsio)"
```

---

### Task 2: Update route.md Presentation

**Files:**
- Modify: `os/clavain/commands/route.md:113-120` (Step 3 presentation rules)
- Modify: `os/clavain/commands/route.md:155-173` (Step 6 routing rules)

**Step 1: Add interject presentation rule to Step 3**

In Step 3, item 3 (line 118), add `review_discovery` to the action verbs list:

```
   - Action verbs: continue → "Continue", execute → "Execute plan for", plan → "Plan", strategize → "Strategize", brainstorm → "Brainstorm", ship → "Ship", closed → "Closed", create_bead → "Link orphan:", verify_done → "Verify (parent closed):", review_discovery → "Review discovery:"
```

**Step 2: Add interject-specific label format**

After the orphan entries line (line 120), add:

```markdown
   - **Interject discovery entries** (action: "review_discovery"): Label format: `"Review discovery: <bead-id> — <clean_title> (<discovery_source>, score <discovery_score>)"`. Strip `[interject] ` prefix from title. If `discovery_source` or `discovery_score` are null, omit the parenthetical.
```

**Step 3: Add routing rule for review_discovery**

In Step 6 (line 155-173), add after the `brainstorm` entry:

```markdown
   - `review_discovery` → Show bead description (the full discovery details), then AskUserQuestion with options:
     1. "Promote to sprint" → Set phase to `brainstorm`, route to `/clavain:sprint`
     2. "Dismiss discovery" → `bd close <id> --reason="Discovery dismissed — not relevant"`, then re-run discovery
     3. "Skip for now" → Re-run discovery (don't close the bead)
```

**Step 4: Commit**

```bash
cd os/clavain && git add commands/route.md && git commit -m "feat: enriched presentation for interject discoveries in route (iv-zsio)"
```

---

### Task 3: Add BATS Tests for Metadata Extraction

**Files:**
- Create: `interverse/interphase/tests/shell/test_interject_discovery.bats`

**Step 1: Write BATS test file**

```bash
#!/usr/bin/env bats
# Tests for interject metadata extraction in lib-discovery.sh

setup() {
    # Source the library under test
    export DISCOVERY_PROJECT_DIR="$BATS_TEST_TMPDIR"
    mkdir -p "$BATS_TEST_TMPDIR/.beads"
    source "${BATS_TEST_DIRNAME}/../../hooks/lib-discovery.sh"
}

@test "_extract_interject_metadata parses source and score" {
    # Mock bd show --json to return a structured description
    bd() {
        if [[ "$1" == "show" && "$3" == "--json" ]]; then
            cat <<'JSON'
{"id":"iv-test1","title":"[interject] Cool arxiv paper","description":"Source: arxiv | https://arxiv.org/abs/1234\n\nSome summary\n\nRelevance score: 0.85\nDiscovered: 2026-03-05","status":"open","priority":4}
JSON
        fi
    }
    export -f bd

    run _extract_interject_metadata "iv-test1"
    [ "$status" -eq 0 ]
    [ "$output" = "arxiv|0.85" ]
}

@test "_extract_interject_metadata returns empty for non-interject bead" {
    bd() {
        if [[ "$1" == "show" && "$3" == "--json" ]]; then
            echo '{"id":"iv-test2","title":"Normal bead","description":"Just a task","status":"open","priority":2}'
        fi
    }
    export -f bd

    run _extract_interject_metadata "iv-test2"
    [ "$status" -eq 0 ]
    [ "$output" = "|" ]
}

@test "infer_bead_action returns review_discovery for unphased interject bead" {
    # Mock bd and phase_get
    bd() {
        if [[ "$1" == "show" && "$3" == "--json" ]]; then
            echo '{"id":"iv-test3","title":"[interject] GitHub repo","description":"Source: github | https://github.com/foo","status":"open","priority":4}'
        fi
    }
    export -f bd
    phase_get() { echo ""; }
    export -f phase_get

    run infer_bead_action "iv-test3" "open"
    [ "$status" -eq 0 ]
    [ "$output" = "review_discovery|" ]
}

@test "infer_bead_action returns normal action for phased interject bead" {
    bd() {
        if [[ "$1" == "show" && "$3" == "--json" ]]; then
            echo '{"id":"iv-test4","title":"[interject] Paper","description":"Source: arxiv | url","status":"open","priority":2}'
        fi
    }
    export -f bd
    phase_get() { echo "brainstorm"; }
    export -f phase_get

    run infer_bead_action "iv-test4" "open"
    [ "$status" -eq 0 ]
    [[ "$output" == "strategize|"* ]]
}
```

**Step 2: Run the tests**

Run: `cd interverse/interphase && bats tests/shell/test_interject_discovery.bats`
Expected: 4 tests, 4 passed

**Step 3: Commit**

```bash
cd interverse/interphase && git add tests/shell/test_interject_discovery.bats && git commit -m "test: BATS tests for interject discovery metadata extraction (iv-zsio)"
```

---

### Task 4: Verify End-to-End and Push

**Files:** (none — verification only)

**Step 1: Syntax check both modified files**

Run: `bash -n interverse/interphase/hooks/lib-discovery.sh && echo "interphase OK"`
Run: `python3 -c "import json; json.load(open('os/clavain/.claude-plugin/plugin.json'))" && echo "clavain manifest OK"`

**Step 2: Run existing interphase tests**

Run: `cd interverse/interphase && bats tests/shell/ 2>&1 | tail -5`
Expected: All tests pass

**Step 3: Push both subprojects**

```bash
cd interverse/interphase && git push
cd os/clavain && git push
```

**Step 4: Push monorepo**

```bash
cd /home/mk/projects/Sylveste && git add docs/ && git commit -m "docs: brainstorm + PRD + plan for discovery sprint presentation (iv-zsio)" && git push
```
