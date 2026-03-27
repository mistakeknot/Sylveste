---
artifact_type: plan
bead: iv-5ztam
stage: design
requirements:
  - F1: Cross-project evidence aggregation (Sylveste-qyff)
  - F2: Prompt tuning overlay creation (iv-t1m4)
  - F3: Overlay injection in SessionStart
---
# Interspect Cross-Project & Overlays — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-5ztam
**Phase:** planned (as of 2026-03-17T21:43:13Z)
**Goal:** Add cross-project evidence aggregation and complete the prompt tuning overlay lifecycle.

**Architecture:** F1 adds project DB discovery and cross-project SQL aggregation to lib-interspect.sh, exposed via `--global` flag on effectiveness. F2 adds `/interspect:tune` command that generates overlay files from correction patterns. F3 adds overlay reading to the SessionStart hook's additionalContext output.

**Tech Stack:** Bash, SQLite3, jq

---

### Task 1: Cross-Project DB Discovery and Aggregation

**Files:**
- Modify: `interverse/interspect/hooks/lib-interspect.sh` (append functions)
- Modify: `interverse/interspect/commands/interspect-effectiveness.md` (add --global flag)
- Create: `interverse/interspect/tests/shell/test_cross_project.sh`

**Step 1: Write test**
```bash
# test_cross_project.sh — create 3 fake project dirs with interspect DBs,
# populate with evidence, verify _interspect_discover_project_dbs finds them
# and _interspect_cross_project_report aggregates correctly
```

**Step 2: Implement discovery function**
Append to lib-interspect.sh:
```bash
# _interspect_discover_project_dbs
# Finds all .clavain/interspect/interspect.db files under ~/projects/
# Returns one path per line. Excludes current project to avoid double-counting.
_interspect_discover_project_dbs() {
    local home_projects="${HOME}/projects"
    local current_db
    current_db=$(_interspect_db_path 2>/dev/null) || current_db=""

    find "$home_projects" -maxdepth 4 -path '*/.clavain/interspect/interspect.db' -type f 2>/dev/null | while read -r db_path; do
        [[ "$db_path" == "$current_db" ]] && continue
        echo "$db_path"
    done
}

# _interspect_cross_project_report <window_days>
# Aggregates effectiveness data across all project DBs.
# Returns JSON with per-agent stats including project_count.
_interspect_cross_project_report() {
    local window_days="${1:-30}"
    local all_agents=()

    # Collect from all project DBs
    while IFS= read -r db_path; do
        [[ -f "$db_path" ]] || continue
        local project_name
        project_name=$(basename "$(dirname "$(dirname "$(dirname "$db_path")")")")

        local agents
        agents=$(sqlite3 "$db_path" "
            SELECT json_group_array(json_object(
                'agent', source,
                'project', '${project_name}',
                'dispatches', SUM(CASE WHEN event='agent_dispatch' THEN 1 ELSE 0 END),
                'corrections', SUM(CASE WHEN event='override' THEN 1 ELSE 0 END)
            ))
            FROM evidence
            WHERE ts > datetime('now', '-${window_days} days') AND source LIKE 'fd-%'
            GROUP BY source
            HAVING SUM(CASE WHEN event='agent_dispatch' THEN 1 ELSE 0 END) > 0;
        " 2>/dev/null) || continue
        [[ -z "$agents" || "$agents" == "null" ]] && continue
        all_agents+=("$agents")
    done < <(_interspect_discover_project_dbs)

    # Also include current project
    local current_db
    current_db=$(_interspect_db_path 2>/dev/null) || current_db=""
    if [[ -n "$current_db" && -f "$current_db" ]]; then
        local current_project
        current_project=$(_interspect_project_name)
        local current_agents
        current_agents=$(sqlite3 "$current_db" "
            SELECT json_group_array(json_object(
                'agent', source,
                'project', '${current_project}',
                'dispatches', SUM(CASE WHEN event='agent_dispatch' THEN 1 ELSE 0 END),
                'corrections', SUM(CASE WHEN event='override' THEN 1 ELSE 0 END)
            ))
            FROM evidence
            WHERE ts > datetime('now', '-${window_days} days') AND source LIKE 'fd-%'
            GROUP BY source
            HAVING SUM(CASE WHEN event='agent_dispatch' THEN 1 ELSE 0 END) > 0;
        " 2>/dev/null) || true
        [[ -n "$current_agents" && "$current_agents" != "null" ]] && all_agents+=("$current_agents")
    fi

    # Merge: aggregate by agent across all projects
    if [[ ${#all_agents[@]} -eq 0 ]]; then
        echo '{"agents":[],"project_count":0}'
        return 0
    fi

    # Combine all JSON arrays and aggregate with jq
    printf '%s\n' "${all_agents[@]}" | jq -s '
        [. | flatten | group_by(.agent) | .[] | {
            agent: .[0].agent,
            projects: [.[].project] | unique,
            project_count: ([.[].project] | unique | length),
            total_dispatches: ([.[].dispatches] | add),
            total_corrections: ([.[].corrections] | add),
            override_rate: (([.[].corrections] | add) / ([.[].dispatches] | add) * 100 | . * 10 | floor / 10)
        }] | sort_by(-.total_corrections) | {
            agents: .,
            project_count: ([.[] | .projects[]] | unique | length)
        }
    '
}
```

**Step 3: Add --global flag to effectiveness command**
In `commands/interspect-effectiveness.md`, add a section:
```
If `--global` is in arguments:
1. Call `_interspect_cross_project_report "$WINDOW"` instead of `_interspect_effectiveness_report`
2. Add "Project Count" column to per-agent table
3. Show which projects each agent appears in
4. Highlight agents excluded in >50% of projects
```

**Step 4: Run tests**
Run: `bash interverse/interspect/tests/shell/test_cross_project.sh`

**Step 5: Commit**
```bash
cd interverse/interspect && git add hooks/lib-interspect.sh commands/interspect-effectiveness.md tests/shell/test_cross_project.sh
git commit -m "feat: add cross-project evidence aggregation (--global flag)"
```

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
- run: `bash interverse/interspect/tests/shell/test_cross_project.sh`
  expect: contains "All tests passed"
</verify>

---

### Task 2: /interspect:tune Command for Overlay Creation

**Files:**
- Create: `interverse/interspect/commands/interspect-tune.md`
- Modify: `interverse/interspect/hooks/lib-interspect.sh` (add generation function)
- Create: `interverse/interspect/tests/shell/test_tune.sh`

**Step 1: Write overlay generation function**
Append to lib-interspect.sh:
```bash
# _interspect_generate_overlay <agent>
# Generates overlay content from the agent's correction evidence.
# Returns the overlay markdown body (without frontmatter) on stdout.
_interspect_generate_overlay() {
    local agent="$1"
    local db
    db=$(_interspect_db_path) || return 1

    # Get top correction reasons
    local reasons
    reasons=$(sqlite3 -separator '|' "$db" "
        SELECT override_reason, COUNT(*) as cnt
        FROM evidence
        WHERE source LIKE '%${agent}%' AND event = 'override'
        GROUP BY override_reason
        ORDER BY cnt DESC
        LIMIT 5;
    " 2>/dev/null) || reasons=""

    # Get project context
    local project
    project=$(_interspect_project_name)
    local project_type=""
    if [[ -f "go.mod" || -f "go.sum" ]]; then project_type="Go"
    elif [[ -f "package.json" ]]; then project_type="TypeScript/JavaScript"
    elif [[ -f "pyproject.toml" || -f "setup.py" ]]; then project_type="Python"
    elif [[ -f "Cargo.toml" ]]; then project_type="Rust"
    fi

    # Generate template
    cat <<OVERLAY
## ${agent} — Project-Specific Tuning

This project (${project}) is ${project_type:+a ${project_type} project}.

### Correction Patterns

The following patterns have been observed in corrections for this agent:

$(echo "$reasons" | while IFS='|' read -r reason count; do
    [[ -z "$reason" ]] && continue
    echo "- **${reason}**: ${count} corrections"
done)

### Guidance

When reviewing code in this project:
- Focus on patterns relevant to ${project_type:-this project's} ecosystem
- Avoid generic recommendations that don't apply to this codebase
- Prioritize findings that are actionable within the project's architecture
OVERLAY
}
```

**Step 2: Write /interspect:tune command**
Create `commands/interspect-tune.md`:
```markdown
---
name: interspect-tune
description: Generate a prompt tuning overlay for an agent from its correction evidence patterns
argument-hint: "<agent-name>"
---

# Interspect Tune

Generate a prompt tuning overlay from an agent's correction evidence.

<tune_agent> #$ARGUMENTS </tune_agent>

## Locate Library
[same library location pattern as other commands]

## Validate
- Extract agent name from arguments
- Verify agent exists in evidence (has corrections)
- Check if overlay already exists (offer to regenerate)

## Generate
```bash
CONTENT=$(_interspect_generate_overlay "$AGENT")
```

## Preview and Confirm
Show the generated overlay content to the user via AskUserQuestion:
- "Apply this overlay?" → write file + create canary
- "Edit first" → open in $EDITOR, then write
- "Cancel" → no changes

## Write
Use existing `_interspect_write_overlay` to write the file with proper frontmatter:
```bash
_interspect_write_overlay "$AGENT" "tuning" "$CONTENT" "$DB"
```
This automatically:
- Creates `.clavain/interspect/overlays/<agent>/tuning.md`
- Sets `active: true` in frontmatter
- Checks token budget (500 max)
- Creates canary record
- Git commits
```

**Step 3: Write test**
Test that `_interspect_generate_overlay` produces valid overlay content from test evidence.

**Step 4: Run tests and commit**

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
- run: `bash interverse/interspect/tests/shell/test_tune.sh`
  expect: contains "All tests passed"
</verify>

---

### Task 3: Overlay Injection in SessionStart Hook

**Files:**
- Modify: `interverse/interspect/hooks/interspect-session.sh` (add overlay reading)

**Step 1: Add overlay injection**
After the canary alerts section (line ~106) and before the final additionalContext emit, add:
```bash
# Inject active overlays into session context
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
OVERLAY_DIR="${ROOT}/.clavain/interspect/overlays"
if [[ -d "$OVERLAY_DIR" ]]; then
    OVERLAY_CONTENT=""
    OVERLAY_TOKENS=0
    MAX_OVERLAY_TOKENS=2000

    for agent_dir in "$OVERLAY_DIR"/*/; do
        [[ -d "$agent_dir" ]] || continue
        agent=$(basename "$agent_dir")
        agent_content=$(_interspect_read_overlays "$agent" 2>/dev/null) || continue
        [[ -z "$agent_content" ]] && continue

        tokens=$(_interspect_count_overlay_tokens "$agent_content")
        new_total=$((OVERLAY_TOKENS + tokens))
        if (( new_total > MAX_OVERLAY_TOKENS )); then
            break # Token budget exceeded
        fi
        OVERLAY_TOKENS=$new_total

        [[ -n "$OVERLAY_CONTENT" ]] && OVERLAY_CONTENT+=$'\n\n'
        OVERLAY_CONTENT+="[Interspect tuning for ${agent}]"$'\n'"${agent_content}"
    done

    if [[ -n "$OVERLAY_CONTENT" ]]; then
        SUMMARY_PARTS+=("$OVERLAY_CONTENT")
    fi
fi
```

**Step 2: Verify syntax**
Run: `bash -n interverse/interspect/hooks/interspect-session.sh`

**Step 3: Commit**
```bash
cd interverse/interspect && git add hooks/interspect-session.sh
git commit -m "feat: inject active overlays into session context via additionalContext"
```

<verify>
- run: `bash -n interverse/interspect/hooks/interspect-session.sh`
  expect: exit 0
</verify>

---

### Task 4: Bump Version, Test, Push

**Files:**
- Modify: `interverse/interspect/.claude-plugin/plugin.json` (bump to 0.1.17)

**Step 1: Bump version**

**Step 2: Run all tests**
Run: `bash interverse/interspect/tests/shell/test_effectiveness.sh && bash interverse/interspect/tests/shell/test_cross_project.sh && bash interverse/interspect/tests/shell/test_tune.sh`

**Step 3: Full syntax check**
Run: `bash -n interverse/interspect/hooks/lib-interspect.sh && bash -n interverse/interspect/hooks/interspect-session.sh`

**Step 4: Commit and push**
```bash
cd interverse/interspect && git add .claude-plugin/plugin.json
git commit -m "chore: bump interspect to v0.1.17 (cross-project + overlays)"
git push
```

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
- run: `bash interverse/interspect/tests/shell/test_effectiveness.sh`
  expect: contains "All tests passed"
</verify>
